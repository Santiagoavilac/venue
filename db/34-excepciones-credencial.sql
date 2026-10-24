-- EXCEPCIONES POR PERSONA, CREDENCIAL DEL RELACIONADOR, FOTO CON APROBACIÓN
-- Y MESAS DE CORTESÍA. Re-ejecutable. Va después de 19 (guardas) y 33.
--
-- (1) Excepción de lista por persona. cupo_rrpp ya guardaba "Fulano anota 5
--     en vez de 1"; ahora también "y sus invitados entran hasta las 00:00 en
--     vez de las 23:00". Las dos partes son opcionales: cupo null = el cupo
--     general, ingreso_hasta null = la hora de la lista.
-- (2) Credencial: cada persona tiene un código propio. El portero lo escanea
--     con el mismo escáner (QR "CRD|<code>") y ve foto, nombre, team, rol y lo
--     que tiene esa noche en cada lista. No consume nada.
-- (3) Foto de perfil: la primera se pone directo. Después, cambiar la foto o
--     el nombre pasa por una solicitud que el admin del boliche acepta o
--     rechaza. Los admins cambian lo suyo sin pedir permiso.
-- (4) Mesas de cortesía: quedan pagadas y verificadas al venderse. Antes una
--     cortesía "reservada" o vendida por un jefe quedaba pidiendo comprobante
--     y aparecía en la cola de verificación.

-- ── (1) excepción de lista por persona ──────────────────────────────────
alter table cupo_rrpp add column if not exists ingreso_hasta time;
alter table cupo_rrpp alter column cupo drop not null;
comment on column cupo_rrpp.cupo is 'cupo propio en esta lista; null = el general de su rol';
comment on column cupo_rrpp.ingreso_hasta is 'hora tope de ingreso de SUS invitados; null = la de la lista';

/* límite de ingreso de los invitados de una persona: su excepción si la
   tiene, si no la hora de la lista. Mismo cálculo que lista_limite_ingreso
   (+1 día si la hora es <= hora_inicio, hora de Bolivia). */
create or replace function lista_limite_ingreso(p_lista uuid, p_rrpp uuid)
returns timestamptz
language sql
stable
set search_path = public
as $$
  select case when h.hasta is null then null
              else ((e.fecha + h.hasta)
                    + case when h.hasta <= e.hora_inicio then interval '1 day' else interval '0' end)
                   at time zone 'America/La_Paz'
         end
    from lista_tipos lt
    join eventos e on e.id = lt.evento_id
    cross join lateral (
      select coalesce((select cr.ingreso_hasta from cupo_rrpp cr
                        where cr.lista_tipo_id = lt.id and cr.user_id = p_rrpp),
                      lt.ingreso_hasta) as hasta) h
   where lt.id = p_lista;
$$;

/* hora tope (texto HH24:MI) que rige para los invitados de una persona */
create or replace function lista_hora_ingreso(p_lista uuid, p_rrpp uuid)
returns time
language sql
stable
set search_path = public
as $$
  select coalesce((select cr.ingreso_hasta from cupo_rrpp cr
                    where cr.lista_tipo_id = p_lista and cr.user_id = p_rrpp),
                  (select lt.ingreso_hasta from lista_tipos lt where lt.id = p_lista));
$$;
revoke all on function lista_limite_ingreso(uuid, uuid) from public, anon;
revoke all on function lista_hora_ingreso(uuid, uuid) from public, anon;
grant execute on function lista_hora_ingreso(uuid, uuid) to authenticated;

/* El escáner de listas y el tick manual, con la hora de la persona que anotó.
   Mismo cuerpo que 02i; solo cambia el cálculo del límite. Viven en impl
   (la guarda de 19 delega acá). */
create or replace function impl.validar_qr_lista(p_evento uuid, p_code text)
returns json
language plpgsql
volatile
security definer
set search_path = public
as $$
declare
  r registros%rowtype;
  v_club text; v_lista text; v_rrpp text; v_team text;
  v_sin_tope boolean; v_limite timestamptz; v_hasta time;
begin
  select r2.* into r
    from registros r2
    join lista_tipos lt on lt.id = r2.lista_tipo_id
   where r2.evento_id = p_evento and r2.code = upper(p_code);
  if not found then
    return json_build_object('resultado', 'no_existe');
  end if;

  select e.club_id into v_club from eventos e where e.id = p_evento;
  select lt.nombre into v_lista from lista_tipos lt where lt.id = r.lista_tipo_id;
  v_hasta := lista_hora_ingreso(r.lista_tipo_id, r.rrpp_id);
  select p.nombre, t.nombre into v_rrpp, v_team
    from profiles p left join teams t on t.id = p.team_id
   where p.id = r.rrpp_id;
  v_sin_tope := exists (select 1 from ingreso_sin_tope st
                         where st.user_id = r.rrpp_id and st.club_id = v_club);

  if r.ingreso_at is not null then
    return json_build_object('resultado', 'usada', 'cliente', r.nombre, 'code', r.code,
                             'used_at', r.ingreso_at, 'lista_nombre', v_lista,
                             'rrpp', v_rrpp, 'team', v_team);
  end if;

  v_limite := lista_limite_ingreso(r.lista_tipo_id, r.rrpp_id);
  if v_limite is not null and now() > v_limite and not v_sin_tope then
    return json_build_object('resultado', 'fuera_horario', 'cliente', r.nombre, 'code', r.code,
                             'lista_nombre', v_lista, 'limite', to_char(v_hasta, 'HH24:MI'),
                             'rrpp', v_rrpp, 'team', v_team);
  end if;

  update registros set ingreso_at = now(), ingreso_por = auth.uid()
   where id = r.id and ingreso_at is null;
  if not found then
    select reg.* into r from registros reg where reg.id = r.id;
    return json_build_object('resultado', 'usada', 'cliente', r.nombre, 'code', r.code,
                             'used_at', r.ingreso_at, 'lista_nombre', v_lista,
                             'rrpp', v_rrpp, 'team', v_team);
  end if;
  return json_build_object('resultado', 'valida', 'cliente', r.nombre, 'code', r.code,
                           'lista', true, 'lista_nombre', v_lista,
                           'rrpp', v_rrpp, 'team', v_team, 'sin_tope', v_sin_tope);
end;
$$;

create or replace function impl.checkin_registro(p_registro uuid)
returns json
language plpgsql
volatile
security definer
set search_path = public
as $$
declare
  r registros%rowtype;
  v_club text; v_sin_tope boolean; v_limite timestamptz;
begin
  select * into r from registros where id = p_registro;
  if not found then
    return json_build_object('resultado', 'no_existe');
  end if;
  if r.ingreso_at is not null then
    return json_build_object('resultado', 'ya', 'nombre', r.nombre, 'hora', r.ingreso_at);
  end if;

  select e.club_id into v_club from eventos e where e.id = r.evento_id;
  v_sin_tope := exists (select 1 from ingreso_sin_tope st
                         where st.user_id = r.rrpp_id and st.club_id = v_club);
  v_limite := lista_limite_ingreso(r.lista_tipo_id, r.rrpp_id);
  if v_limite is not null and now() > v_limite and not v_sin_tope then
    return json_build_object('resultado', 'fuera_horario', 'nombre', r.nombre);
  end if;

  update registros set ingreso_at = now(), ingreso_por = auth.uid()
   where id = p_registro and ingreso_at is null;
  if not found then
    select reg.* into r from registros reg where reg.id = p_registro;
    return json_build_object('resultado', 'ya', 'nombre', r.nombre, 'hora', r.ingreso_at);
  end if;
  return json_build_object('resultado', 'ok', 'nombre', r.nombre, 'hora', now());
end;
$$;

/* heredar_cupos_lista también copia la hora propia */
create or replace function impl.heredar_cupos_lista(p_lista uuid)
returns int
language plpgsql
volatile
security definer
set search_path = public
as $$
declare
  lt lista_tipos%rowtype;
  v_club text;
  v_origen uuid;
  v_n int := 0;
begin
  select * into lt from lista_tipos where id = p_lista;
  if not found then return 0; end if;
  select club_id into v_club from eventos where id = lt.evento_id;

  select lt2.id into v_origen
    from lista_tipos lt2
    join eventos e2 on e2.id = lt2.evento_id
   where lt2.id <> p_lista
     and e2.club_id = v_club
     and lower(trim(lt2.nombre)) = lower(trim(lt.nombre))
   order by e2.fecha desc, lt2.orden desc
   limit 1;
  if v_origen is null then return 0; end if;

  insert into cupo_rrpp (lista_tipo_id, user_id, cupo, ingreso_hasta)
  select p_lista, c.user_id, c.cupo, c.ingreso_hasta
    from cupo_rrpp c
   where c.lista_tipo_id = v_origen
     and not exists (select 1 from cupo_rrpp c2
                      where c2.lista_tipo_id = p_lista and c2.user_id = c.user_id);
  get diagnostics v_n = row_count;
  return v_n;
end;
$$;

/* mis_cupos: además del cupo, la hora de ingreso propia de cada lista */
drop function if exists mis_horas_lista(uuid);
create or replace function mis_horas_lista(p_evento uuid)
returns table (lista_tipo_id uuid, ingreso_hasta time, especial boolean)
language sql
stable
security definer
set search_path = public
as $$
  select lt.id,
         coalesce(cr.ingreso_hasta, lt.ingreso_hasta),
         cr.ingreso_hasta is not null
    from lista_tipos lt
    left join cupo_rrpp cr on cr.lista_tipo_id = lt.id and cr.user_id = auth.uid()
   where lt.evento_id = p_evento
     and impl.exigir((select e.club_id from eventos e where e.id = p_evento), '{*}'::text[]) is not null
   order by lt.orden;
$$;
revoke all on function mis_horas_lista(uuid) from public, anon;
grant execute on function mis_horas_lista(uuid) to authenticated;


-- ── (2) y (3) foto, credencial y solicitudes de cambio ──────────────────
alter table profiles add column if not exists foto_url text;
alter table profiles add column if not exists credencial_code text;
create unique index if not exists profiles_credencial_code_key on profiles (credencial_code);
comment on column profiles.foto_url is 'foto de perfil (bucket perfiles, <uid>/...). Cambiarla pide aprobación del admin.';
comment on column profiles.credencial_code is 'código del QR de credencial (CRD|<code>). Se genera al pedirlo.';

insert into storage.buckets (id, name, public)
values ('perfiles', 'perfiles', true)
on conflict (id) do nothing;

-- cada quien sube solo bajo su carpeta; el admin puede borrar lo de cualquiera
drop policy if exists perfiles_subir on storage.objects;
create policy perfiles_subir on storage.objects for insert to authenticated
  with check (bucket_id = 'perfiles' and (storage.foldername(name))[1] = auth.uid()::text);
drop policy if exists perfiles_pisar on storage.objects;
create policy perfiles_pisar on storage.objects for update to authenticated
  using (bucket_id = 'perfiles' and (storage.foldername(name))[1] = auth.uid()::text);
drop policy if exists perfiles_leer on storage.objects;
create policy perfiles_leer on storage.objects for select to authenticated
  using (bucket_id = 'perfiles');

create table if not exists solicitud_perfil (
  id           uuid primary key default gen_random_uuid(),
  user_id      uuid not null references profiles(id) on delete cascade,
  cambios      jsonb not null,            -- {nombre?, foto_url?}
  estado       text not null default 'pendiente'
               check (estado in ('pendiente', 'aprobada', 'rechazada')),
  created_at   timestamptz not null default now(),
  resuelto_por uuid references profiles(id),
  resuelto_at  timestamptz
);
create index if not exists solicitud_perfil_pend_idx on solicitud_perfil (user_id) where estado = 'pendiente';
alter table solicitud_perfil enable row level security;   -- sin políticas: solo las RPC

/* La foto y el nombre de uno mismo ya no se cambian por REST directo (salvo
   admin o servicio): van por solicitar_cambio_perfil. Se suma a la regla del
   jefe que ya tenía este trigger (09). */
create or replace function perfil_update_guard()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare v_uid uuid := auth.uid(); v_rol text;
begin
  if v_uid is null or current_setting('venue.perfil_aprobado', true) = '1' then return new; end if;
  select rol into v_rol from profiles where id = v_uid;
  if v_uid = old.id then
    if v_rol is distinct from 'admin'
       and not exists (select 1 from platform_admins pa where pa.user_id = v_uid)
       and (new.nombre is distinct from old.nombre
            or (new.foto_url is distinct from old.foto_url and old.foto_url is not null)) then
      raise exception 'Ese cambio lo tiene que aprobar el administrador.';
    end if;
    return new;
  end if;
  if v_rol = 'jefe' then
    if row(new.*) is distinct from row(old.*)
       and not (new.activo is distinct from old.activo
                and new.id = old.id and new.usuario = old.usuario
                and new.nombre is not distinct from old.nombre
                and new.rol = old.rol
                and new.team_id is not distinct from old.team_id
                and new.clubs is not distinct from old.clubs
                and new.cut_rel is not distinct from old.cut_rel
                and new.puede_tickear is not distinct from old.puede_tickear
                and new.admin_principal = old.admin_principal
                and new.eliminado_at is not distinct from old.eliminado_at
                and new.solo_invitaciones is not distinct from old.solo_invitaciones
                and new.foto_url is not distinct from old.foto_url
                and new.credencial_code is not distinct from old.credencial_code) then
      raise exception 'Un jefe solo puede activar o pausar a la gente de su team.';
    end if;
  end if;
  return new;
end;
$$;

/* ¿quien llama administra algún boliche de esta persona? */
create or replace function impl.admin_de(p_user uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1 from profiles p
     where p.id = p_user
       and exists (select 1 from unnest(p.clubs || coalesce(
                     (select array_agg(cm.club_id) from club_membership cm where cm.user_id = p.id),
                     '{}'::text[])) c(club)
                    where rol_en_club(c.club) = 'admin'));
$$;
revoke all on function impl.admin_de(uuid) from public, anon;

/* solicitar_cambio_perfil(p_cambios) -> json {estado: 'aplicada'|'pendiente'}
 * Claves admitidas: nombre, foto_url. La primera foto (sin foto previa) y
 * cualquier cambio de un admin se aplican al toque; el resto queda
 * pendiente y reemplaza una solicitud pendiente anterior. */
create or replace function solicitar_cambio_perfil(p_cambios jsonb)
returns json
language plpgsql
volatile
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  p profiles%rowtype;
  v_c jsonb := '{}'::jsonb;
  v_admin boolean;
begin
  perform impl.exigir_sesion();
  select * into p from profiles where id = v_uid;

  if p_cambios ? 'nombre' then
    if length(trim(coalesce(p_cambios ->> 'nombre', ''))) < 2 then
      raise exception 'Poné tu nombre.';
    end if;
    if trim(p_cambios ->> 'nombre') is distinct from p.nombre then
      v_c := v_c || jsonb_build_object('nombre', trim(p_cambios ->> 'nombre'));
    end if;
  end if;
  if p_cambios ? 'foto_url' then
    if (p_cambios ->> 'foto_url') not like '%/storage/v1/object/public/perfiles/' || v_uid::text || '/%' then
      raise exception 'La foto tiene que estar subida desde la app.';
    end if;
    if (p_cambios ->> 'foto_url') is distinct from p.foto_url then
      v_c := v_c || jsonb_build_object('foto_url', p_cambios ->> 'foto_url');
    end if;
  end if;
  if v_c = '{}'::jsonb then
    return json_build_object('estado', 'aplicada');
  end if;

  v_admin := p.rol = 'admin' or p.admin_principal
             or exists (select 1 from platform_admins pa where pa.user_id = v_uid);
  -- la primera foto entra directo; si además cambia el nombre, eso se pide
  if not v_admin and p.foto_url is null and v_c ? 'foto_url' then
    perform set_config('venue.perfil_aprobado', '1', true);
    update profiles set foto_url = v_c ->> 'foto_url' where id = v_uid;
    perform set_config('venue.perfil_aprobado', '', true);
    v_c := v_c - 'foto_url';
    if v_c = '{}'::jsonb then return json_build_object('estado', 'aplicada'); end if;
  end if;

  if v_admin then
    perform set_config('venue.perfil_aprobado', '1', true);
    update profiles set nombre = coalesce(v_c ->> 'nombre', nombre),
                        foto_url = coalesce(v_c ->> 'foto_url', foto_url)
     where id = v_uid;
    perform set_config('venue.perfil_aprobado', '', true);
    return json_build_object('estado', 'aplicada');
  end if;

  update solicitud_perfil set estado = 'rechazada', resuelto_at = now(), resuelto_por = v_uid
   where user_id = v_uid and estado = 'pendiente';
  insert into solicitud_perfil (user_id, cambios) values (v_uid, v_c);
  return json_build_object('estado', 'pendiente');
end;
$$;

/* mi_solicitud_perfil() -> json | null · la pendiente de quien llama */
create or replace function mi_solicitud_perfil()
returns json
language sql
stable
security definer
set search_path = public
as $$
  select json_build_object('id', s.id, 'cambios', s.cambios, 'created_at', s.created_at)
    from solicitud_perfil s
   where s.user_id = auth.uid() and s.estado = 'pendiente'
   order by s.created_at desc limit 1;
$$;

/* solicitudes_perfil(p_club) · las pendientes de la gente del boliche (admin) */
create or replace function solicitudes_perfil(p_club text)
returns table (id uuid, user_id uuid, nombre text, usuario text, foto_url text,
               team text, cambios jsonb, created_at timestamptz)
language plpgsql
stable
security definer
set search_path = public
as $$
begin
  perform impl.exigir(p_club, '{admin}'::text[]);
  return query
    select s.id, p.id, p.nombre, p.usuario, p.foto_url, t.nombre, s.cambios, s.created_at
      from solicitud_perfil s
      join profiles p on p.id = s.user_id
      left join teams t on t.id = p.team_id
     where s.estado = 'pendiente'
       and (p_club = any(p.clubs)
            or exists (select 1 from club_membership cm where cm.user_id = p.id and cm.club_id = p_club))
     order by s.created_at;
end;
$$;

/* resolver_solicitud_perfil(p_id, p_aprobar) · el admin acepta o rechaza */
create or replace function resolver_solicitud_perfil(p_id uuid, p_aprobar boolean)
returns void
language plpgsql
volatile
security definer
set search_path = public
as $$
declare s solicitud_perfil%rowtype;
begin
  perform impl.exigir_sesion();
  select * into s from solicitud_perfil where id = p_id for update;
  if not found or s.estado <> 'pendiente' then
    raise exception 'La solicitud ya no está pendiente.';
  end if;
  if not impl.admin_de(s.user_id) then
    raise exception 'No autorizado.' using errcode = '42501';
  end if;
  if p_aprobar then
    perform set_config('venue.perfil_aprobado', '1', true);
    update profiles set nombre = coalesce(s.cambios ->> 'nombre', nombre),
                        foto_url = coalesce(s.cambios ->> 'foto_url', foto_url)
     where id = s.user_id;
    perform set_config('venue.perfil_aprobado', '', true);
  end if;
  update solicitud_perfil
     set estado = case when p_aprobar then 'aprobada' else 'rechazada' end,
         resuelto_por = auth.uid(), resuelto_at = now()
   where id = p_id;
end;
$$;

/* mi_credencial() -> text · el código del QR propio; lo crea la primera vez */
create or replace function mi_credencial()
returns text
language plpgsql
volatile
security definer
set search_path = public
as $$
declare v text;
begin
  perform impl.exigir_sesion();
  select credencial_code into v from profiles where id = auth.uid();
  if v is null then
    loop
      v := upper(substr(md5(random()::text || clock_timestamp()::text || auth.uid()::text), 1, 10));
      exit when not exists (select 1 from profiles where credencial_code = v);
    end loop;
    perform set_config('venue.perfil_aprobado', '1', true);
    update profiles set credencial_code = v where id = auth.uid();
    perform set_config('venue.perfil_aprobado', '', true);
  end if;
  return v;
end;
$$;

/* renovar_credencial(p_user) · el admin invalida un QR perdido o compartido */
create or replace function renovar_credencial(p_user uuid)
returns void
language plpgsql
volatile
security definer
set search_path = public
as $$
begin
  perform impl.exigir_sesion();
  if p_user is distinct from auth.uid() and not impl.admin_de(p_user) then
    raise exception 'No autorizado.' using errcode = '42501';
  end if;
  perform set_config('venue.perfil_aprobado', '1', true);
  update profiles set credencial_code = null where id = p_user;
  perform set_config('venue.perfil_aprobado', '', true);
end;
$$;

/* ver_credencial(p_evento, p_code) -> json
 * Lo que ve el portero al escanear la credencial de un relacionador:
 *   {resultado: 'credencial', nombre, usuario, rol, team, foto_url, activo,
 *    del_boliche, sin_tope, listas: [{nombre, cupo, anotados, ingresaron,
 *    entra_hasta, especial}]}
 *   o {resultado: 'no_existe'}. No marca ingresos. */
create or replace function ver_credencial(p_evento uuid, p_code text)
returns json
language plpgsql
volatile
security definer
set search_path = public
as $$
declare
  v_club text;
  p profiles%rowtype;
  v_rol text; v_team text; v_del boolean;
begin
  select club_id into v_club from eventos where id = p_evento;
  perform impl.exigir(v_club, '{admin,portero}'::text[]);
  if (select count(*) from intento_validacion iv where iv.user_id = auth.uid() and not iv.ok
        and iv.at > now() - interval '5 minutes') >= 40 then
    raise exception 'Demasiados códigos inválidos seguidos. Esperá unos minutos o avisá al administrador.';
  end if;

  select * into p from profiles where credencial_code = upper(trim(p_code)) and eliminado_at is null;
  insert into intento_validacion (user_id, evento_id, ok) values (auth.uid(), p_evento, p.id is not null);
  if p.id is null then
    return json_build_object('resultado', 'no_existe');
  end if;

  select coalesce(cm.rol, p.rol), t.nombre into v_rol, v_team
    from profiles x
    left join club_membership cm on cm.user_id = x.id and cm.club_id = v_club
    left join teams t on t.id = coalesce(cm.team_id, x.team_id)
   where x.id = p.id;
  v_del := v_club = any(p.clubs)
           or exists (select 1 from club_membership cm where cm.user_id = p.id and cm.club_id = v_club);

  return json_build_object(
    'resultado', 'credencial',
    'nombre', p.nombre, 'usuario', p.usuario, 'rol', v_rol, 'team', v_team,
    'foto_url', p.foto_url, 'activo', p.activo, 'del_boliche', v_del,
    'sin_tope', exists (select 1 from ingreso_sin_tope st where st.user_id = p.id and st.club_id = v_club),
    'listas', coalesce((
      select json_agg(json_build_object(
               'nombre', lt.nombre,
               'cupo', coalesce(cr.cupo, cp.cupo,
                         case v_rol when 'admin' then lt.cupo_admin
                                    when 'jefe' then coalesce(lt.cupo_jefe, lt.cupo_por_rrpp)
                                    else lt.cupo_por_rrpp end),
               'anotados', (select count(*) from registros r where r.lista_tipo_id = lt.id and r.rrpp_id = p.id),
               'ingresaron', (select count(*) from registros r where r.lista_tipo_id = lt.id and r.rrpp_id = p.id and r.ingreso_at is not null),
               'entra_hasta', to_char(coalesce(cr.ingreso_hasta, lt.ingreso_hasta), 'HH24:MI'),
               'especial', (cr.user_id is not null or cp.user_id is not null))
             order by lt.orden)
        from lista_tipos lt
        left join cupo_rrpp cr on cr.lista_tipo_id = lt.id and cr.user_id = p.id
        left join cupo_permanente cp on cp.user_id = p.id and cp.club_id = v_club
          and lower(trim(cp.lista_nombre)) = lower(trim(lt.nombre))
       where lt.evento_id = p_evento), '[]'::json));
end;
$$;

do $$
declare f text;
begin
  foreach f in array array[
    'solicitar_cambio_perfil(jsonb)', 'mi_solicitud_perfil()', 'solicitudes_perfil(text)',
    'resolver_solicitud_perfil(uuid, boolean)', 'mi_credencial()', 'renovar_credencial(uuid)',
    'ver_credencial(uuid, text)']
  loop
    execute format('revoke all on function %s from public, anon', f);
    execute format('grant execute on function %s to authenticated', f);
  end loop;
end $$;


-- ── (4) mesas de cortesía ───────────────────────────────────────────────
/* Una cortesía no se cobra: al venderse queda pagada y verificada, sin
   comprobante ni método, para cualquier camino (vender_mesa, grupo, editar). */
create or replace function mesa_cortesia_guard()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  if new.cortesia and new.estado in ('reservada', 'pagada')
     and (tg_op = 'INSERT' or not old.cortesia or old.estado is distinct from new.estado) then
    new.estado := 'pagada';
    new.precio := 0;
    new.reservada_at := null;
    new.reserva_vence_at := null;
    new.pagada_at := coalesce(new.pagada_at, now());
    new.pagada_por := coalesce(new.pagada_por, auth.uid());
    new.metodo_pago := null;
    new.comprobante_url := null;
    new.pago_verificado := true;
    new.verificado_por := coalesce(new.verificado_por, new.cortesia_por, auth.uid());
    new.verificado_at := coalesce(new.verificado_at, now());
  end if;
  return new;
end;
$$;
drop trigger if exists mesa_cortesia on mesas;
create trigger mesa_cortesia
  before insert or update on mesas
  for each row execute function mesa_cortesia_guard();

-- las cortesías que ya quedaron colgadas
update mesas
   set estado = 'pagada', precio = 0, reservada_at = null, reserva_vence_at = null,
       pagada_at = coalesce(pagada_at, updated_at, now()), metodo_pago = null, comprobante_url = null,
       pago_verificado = true, verificado_por = coalesce(verificado_por, cortesia_por),
       verificado_at = coalesce(verificado_at, now())
 where cortesia and estado in ('reservada', 'pagada') and (estado = 'reservada' or not pago_verificado);

notify pgrst, 'reload schema';
