-- 41 · Relacionadores: cuenta global, solicitudes para sumarse a un
--      boliche (por enlace o directas), permisos y revocación por boliche,
--      y datos del espacio personal del relacionador.
--
-- Reglas que se cumplen acá, no en la pantalla:
--   · Registrarse como relacionador crea un perfil SIN boliches: no da
--     acceso a nada.
--   · Abrir un enlace no da acceso: crea una solicitud pendiente.
--   · Nadie aprueba su propia solicitud. El admin aprueba en su boliche;
--     el jefe, solo para su team (o las que no tienen team).
--   · Nadie se cambia a sí mismo rol, boliches, team ni flags: antes
--     cualquier relacionador podía ponerse rol admin y todos los boliches
--     editando su propia fila.
--   · Revocar un boliche no toca los demás y conserva el historial.

-- ── 1. el propio perfil ya no se puede subir de rango ──────────────────
-- Las RPC que escriben perfiles o membresías hacen sus propios chequeos y
-- prenden venue.perfil_aprobado (como las de db/34); el cliente no puede
-- prenderla porque no corre SQL suelto.
create or replace function public.perfil_update_guard()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare v_uid uuid := auth.uid(); v_rol text; v_plat boolean;
begin
  if v_uid is null or current_setting('venue.perfil_aprobado', true) = '1' then return new; end if;
  select rol into v_rol from profiles where id = v_uid;
  v_plat := exists (select 1 from platform_admins pa where pa.user_id = v_uid);
  if v_uid = old.id then
    if not v_plat and (
         new.rol is distinct from old.rol
      or new.clubs is distinct from old.clubs
      or new.team_id is distinct from old.team_id
      or new.activo is distinct from old.activo
      or new.cut_rel is distinct from old.cut_rel
      or new.puede_tickear is distinct from old.puede_tickear
      or new.eliminado_at is distinct from old.eliminado_at
      or new.solo_invitaciones is distinct from old.solo_invitaciones
      or new.contabilidad_total is distinct from old.contabilidad_total
      or new.credencial_code is distinct from old.credencial_code
      or new.creado_por is distinct from old.creado_por
      or new.usuario is distinct from old.usuario) then
      raise exception 'Eso lo cambia el administrador del boliche.' using errcode = '42501';
    end if;
    if v_rol is distinct from 'admin' and not v_plat
       and (new.nombre is distinct from old.nombre
            or (new.foto_url is distinct from old.foto_url and old.foto_url is not null)) then
      raise exception 'Ese cambio lo tiene que aprobar el administrador.';
    end if;
    return new;
  end if;
  if not v_plat then
    -- nadie suma a otro a un boliche que no administra
    if exists (select 1 from unnest(coalesce(new.clubs, '{}')) c
                where not (c = any(coalesce(old.clubs, '{}')))
                  and rol_en_club(c) is distinct from 'admin') then
      raise exception 'Solo podés sumar gente a los boliches que administrás.' using errcode = '42501';
    end if;
    if new.contabilidad_total is distinct from old.contabilidad_total then
      raise exception 'Ese permiso lo da la plataforma.' using errcode = '42501';
    end if;
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

-- ── 2. columnas nuevas ─────────────────────────────────────────────────
alter table clubs
  add column if not exists invite_code text,
  add column if not exists invite_activo boolean not null default true,
  add column if not exists solicitudes_publicas boolean not null default false;
update clubs set invite_code = replace(gen_random_uuid()::text, '-', '') where invite_code is null;
alter table clubs alter column invite_code set default replace(gen_random_uuid()::text, '-', '');
create unique index if not exists clubs_invite_code_uq on clubs (invite_code);

alter table club_membership
  add column if not exists activo boolean not null default true,
  add column if not exists origen text,
  add column if not exists aprobado_por uuid references profiles(id),
  add column if not exists aprobado_at timestamptz,
  add column if not exists revocado_at timestamptz,
  add column if not exists permisos jsonb not null default '{}'::jsonb;

-- enlace personal de venta (AFTR): un código corto, no el id ni la credencial
alter table profiles add column if not exists ref_code text;
create unique index if not exists profiles_ref_code_uq on profiles (ref_code);

create table if not exists solicitud_union (
  id           uuid primary key default gen_random_uuid(),
  user_id      uuid not null references profiles(id) on delete cascade,
  club_id      text not null references clubs(id) on delete cascade,
  team_id      uuid references teams(id) on delete set null,
  origen       text not null check (origen in ('enlace_club', 'enlace_team', 'directa')),
  estado       text not null default 'pendiente'
               check (estado in ('pendiente', 'aprobada', 'rechazada', 'cancelada')),
  created_at   timestamptz not null default now(),
  resuelto_por uuid references profiles(id),
  resuelto_at  timestamptz
);
create unique index if not exists solicitud_union_pendiente_uq
  on solicitud_union (user_id, club_id) where estado = 'pendiente';
create index if not exists solicitud_union_club_idx on solicitud_union (club_id, estado);
alter table solicitud_union enable row level security;
drop policy if exists solicitud_union_leer on solicitud_union;
create policy solicitud_union_leer on solicitud_union for select
  using (user_id = auth.uid());
-- sin políticas de escritura: todo pasa por las RPC de abajo

create table if not exists link_visita (
  id         bigint generated always as identity primary key,
  rrpp_id    uuid not null references profiles(id) on delete cascade,
  evento_id  uuid not null references eventos(id) on delete cascade,
  cliente_id uuid,
  at         timestamptz not null default now()
);
create index if not exists link_visita_rrpp_idx on link_visita (rrpp_id, evento_id);
alter table link_visita enable row level security;
-- nadie la lee directo: sale agregada en rrpp_links()

create index if not exists registros_rrpp_evento_idx on registros (rrpp_id, evento_id);
create index if not exists entradas_rrpp_evento_idx on entradas (rrpp_id, evento_id);
create index if not exists mesas_vendedor_evento_idx on mesas (vendido_por, evento_id);

-- ── 3. rol por boliche: una membresía revocada corta el acceso ─────────
create or replace function public.rol_en_club(p_club text)
returns text
language sql
stable
security definer
set search_path = public
as $$
  select case
           when not p.activo or p.eliminado_at is not null then null
           when p.admin_principal
             or exists (select 1 from platform_admins pa where pa.user_id = p.id) then 'admin'
           when cm.user_id is not null and not cm.activo then null
           when p.rol = 'admin' then
             case when p_club = any(p.clubs) then 'admin' end
           when cm.rol is not null then cm.rol
           when p_club = any(p.clubs) then
             case when p.rol = 'jefe'
                   and not coalesce((select t.clubs is null or p_club = any(t.clubs)
                                       from teams t where t.id = p.team_id), false)
                  then 'rrpp' else p.rol end
         end
    from profiles p
    left join club_membership cm on cm.user_id = p.id and cm.club_id = p_club
   where p.id = auth.uid();
$$;

-- la membresía la escribe el admin del boliche, o una RPC que ya chequeó
-- (y prendió venue.perfil_aprobado)
create or replace function public.membresia_protegida_guard()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  v_target uuid := coalesce(new.user_id, old.user_id);
  v_club text := coalesce(new.club_id, old.club_id);
begin
  if es_servicio() then return coalesce(new, old); end if;
  if v_uid is null then
    raise exception 'No autenticado.' using errcode = '28000';
  end if;
  if exists (select 1 from profiles p where p.id = v_target and p.admin_principal)
     and v_uid <> v_target then
    raise exception 'Esta cuenta administrativa está protegida.';
  end if;
  if current_setting('venue.perfil_aprobado', true) = '1' then return coalesce(new, old); end if;
  if rol_en_club(v_club) is distinct from 'admin'
     or (tg_op = 'UPDATE' and rol_en_club(new.club_id) is distinct from 'admin') then
    raise exception 'No autorizado.' using errcode = '42501';
  end if;
  return coalesce(new, old);
end;
$$;

-- ── 4. permisos por boliche ────────────────────────────────────────────
-- Sin clave = permitido (lo de hoy sigue igual). {"entradas": false}
-- le corta a esa persona vender QR en ese boliche.
create or replace function impl.exigir_permiso(p_club text, p_permiso text)
returns void
language plpgsql
stable
security definer
set search_path = public
as $$
begin
  if es_servicio() or auth.uid() is null then return; end if;
  if rol_en_club(p_club) not in ('rrpp', 'jefe') then return; end if;
  if exists (select 1 from club_membership cm
              where cm.user_id = auth.uid() and cm.club_id = p_club
                and cm.permisos ->> p_permiso = 'false') then
    raise exception 'No tenés permiso para % en este boliche.', p_permiso using errcode = '42501';
  end if;
end;
$$;
grant execute on function impl.exigir_permiso(text, text) to authenticated;

-- se agrega el chequeo a las RPC que ya existen, sin tocar su lógica
do $$
declare f record; d text; v_new text;
begin
  for f in
    select p.oid, p.proname from pg_proc p join pg_namespace n on n.oid = p.pronamespace
     where n.nspname = 'public'
       and p.proname in ('generar_entrada', 'registrar_lista', 'vender_mesa', 'vender_mesa_grupo')
  loop
    d := pg_get_functiondef(f.oid);
    if d like '%impl.exigir_permiso%' then continue; end if;
    v_new := case f.proname
      when 'generar_entrada'   then replace(d, 'return impl.generar_entrada(',
             'perform impl.exigir_permiso(impl.club_de(''evento'', p_evento), ''entradas''); return impl.generar_entrada(')
      when 'registrar_lista'   then replace(d, 'return impl.registrar_lista(',
             'perform impl.exigir_permiso(impl.club_de(''lista'', p_lista), ''listas''); return impl.registrar_lista(')
      when 'vender_mesa'       then replace(d, 'return impl.vender_mesa(',
             'perform impl.exigir_permiso(impl.club_de(''mesa'', p_mesa), ''mesas''); return impl.vender_mesa(')
      when 'vender_mesa_grupo' then replace(d, 'return impl.vender_mesa_grupo(',
             'perform impl.exigir_permiso(impl.club_de(''mesa'', p_mesas[1]), ''mesas''); return impl.vender_mesa_grupo(')
    end;
    if v_new = d then raise exception 'No se pudo agregar el permiso a %', f.proname; end if;
    execute v_new;
  end loop;
end $$;

-- ── 5. cuenta de relacionador ──────────────────────────────────────────
create or replace function public.rrpp_crear_cuenta(p_nombre text)
returns json
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  v_email text;
  v_base text;
  v_usuario text;
  v_nombre text := nullif(trim(p_nombre), '');
begin
  if v_uid is null then raise exception 'Iniciá sesión.' using errcode = '28000'; end if;
  if exists (select 1 from profiles where id = v_uid) then
    return (select json_build_object('id', id, 'usuario', usuario, 'nombre', nombre, 'nuevo', false)
              from profiles where id = v_uid);
  end if;
  if v_nombre is null or length(v_nombre) < 2 then raise exception 'Poné tu nombre.'; end if;
  select email into v_email from auth.users where id = v_uid;
  v_base := left(regexp_replace(lower(unaccent(split_part(coalesce(v_email, ''), '@', 1))), '[^a-z0-9_.]', '', 'g'), 20);
  if length(v_base) < 3 then
    v_base := left(regexp_replace(lower(unaccent(v_nombre)), '[^a-z0-9]', '', 'g'), 20);
  end if;
  if length(v_base) < 3 then v_base := 'rrpp'; end if;
  v_usuario := v_base;
  while exists (select 1 from profiles where usuario = v_usuario) loop
    v_usuario := v_base || (100 + floor(random() * 9900))::int;
  end loop;
  insert into profiles (id, usuario, nombre, rol, activo, clubs, creado_por)
  values (v_uid, v_usuario, left(v_nombre, 60), 'rrpp', true, '{}', v_uid);
  return json_build_object('id', v_uid, 'usuario', v_usuario, 'nombre', v_nombre, 'nuevo', true);
end;
$$;

-- ── 6. invitaciones y solicitudes ──────────────────────────────────────
-- Qué boliche (o team) hay detrás de un código. No da acceso a nada.
create or replace function public.ver_invitacion(p_code text)
returns json
language plpgsql
stable
security definer
set search_path = public
as $$
declare c clubs; t teams;
begin
  select * into c from clubs where invite_code = p_code and invite_activo and activo;
  if found then
    return json_build_object('tipo', 'club', 'team', null,
      'clubs', json_build_array(json_build_object('id', c.id, 'nombre', c.nombre,
                 'logo_url', c.logo_url, 'ciudad', c.ciudad, 'color', c.color_primario)));
  end if;
  select * into t from teams where invite_code = p_code and activo
     and (invite_expira is null or invite_expira > now());
  if found then
    return json_build_object('tipo', 'team',
      'team', json_build_object('id', t.id, 'nombre', t.nombre),
      'clubs', coalesce((select json_agg(json_build_object('id', k.id, 'nombre', k.nombre,
                 'logo_url', k.logo_url, 'ciudad', k.ciudad, 'color', k.color_primario) order by k.nombre)
                 from clubs k
                where k.activo and (coalesce(array_length(t.clubs, 1), 0) = 0 or k.id = any(t.clubs))), '[]'::json));
  end if;
  return null;
end;
$$;

create or replace function public.solicitar_union(p_club text, p_code text default null)
returns json
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  v_origen text;
  v_team uuid;
  c clubs;
  t teams;
  s solicitud_union;
begin
  if v_uid is null then raise exception 'Iniciá sesión.' using errcode = '28000'; end if;
  if not exists (select 1 from profiles where id = v_uid and activo and eliminado_at is null) then
    raise exception 'Completá tu cuenta de relacionador primero.';
  end if;
  insert into rate_limit (clave) values ('solicitud:' || v_uid);
  if (select count(*) from rate_limit where clave = 'solicitud:' || v_uid
        and at > now() - interval '1 hour') > 20 then
    raise exception 'Demasiadas solicitudes seguidas. Probá en un rato.';
  end if;

  if p_code is not null and p_code <> '' then
    select * into c from clubs where invite_code = p_code and invite_activo and activo;
    if found then
      v_origen := 'enlace_club';
    else
      select * into t from teams where invite_code = p_code and activo
         and (invite_expira is null or invite_expira > now());
      if not found then raise exception 'El enlace no es válido o fue desactivado.'; end if;
      if p_club is null and coalesce(array_length(t.clubs, 1), 0) = 1 then p_club := t.clubs[1]; end if;
      if p_club is null then raise exception 'Elegí el boliche.'; end if;
      if coalesce(array_length(t.clubs, 1), 0) > 0 and not (p_club = any(t.clubs)) then
        raise exception 'Ese team no trabaja en ese boliche.';
      end if;
      select * into c from clubs where id = p_club and activo;
      if not found then raise exception 'Ese boliche no existe.'; end if;
      v_origen := 'enlace_team';
      v_team := t.id;
    end if;
  else
    select * into c from clubs where id = p_club and activo and solicitudes_publicas;
    if not found then raise exception 'Ese boliche no está recibiendo solicitudes.'; end if;
    v_origen := 'directa';
  end if;

  if rol_en_club(c.id) is not null then
    raise exception 'Ya trabajás con %.', c.nombre;
  end if;
  select * into s from solicitud_union where user_id = v_uid and club_id = c.id and estado = 'pendiente';
  if found then
    if v_team is not null and s.team_id is null then
      update solicitud_union set team_id = v_team, origen = v_origen where id = s.id returning * into s;
    end if;
    return to_jsonb(s);
  end if;
  insert into solicitud_union (user_id, club_id, team_id, origen)
  values (v_uid, c.id, v_team, v_origen) returning * into s;
  return to_jsonb(s);
end;
$$;

create or replace function public.cancelar_solicitud(p_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  update solicitud_union set estado = 'cancelada', resuelto_at = now(), resuelto_por = auth.uid()
   where id = p_id and user_id = auth.uid() and estado = 'pendiente';
  if not found then raise exception 'Esa solicitud ya no está pendiente.'; end if;
end;
$$;

create or replace function public.explorar_boliches(p_q text default null)
returns table (id text, nombre text, subtitulo text, logo_url text, ciudad text, zona text,
               color text, ya_miembro boolean, pendiente boolean)
language sql
stable
security definer
set search_path = public
as $$
  select c.id, c.nombre, c.subtitulo, c.logo_url, c.ciudad, c.zona, c.color_primario,
         rol_en_club(c.id) is not null,
         exists (select 1 from solicitud_union s where s.user_id = auth.uid()
                  and s.club_id = c.id and s.estado = 'pendiente')
    from clubs c
   where c.activo and c.solicitudes_publicas
     and (p_q is null or p_q = '' or unaccent(c.nombre) ilike '%' || unaccent(p_q) || '%'
          or unaccent(coalesce(c.ciudad, '')) ilike '%' || unaccent(p_q) || '%')
   order by c.nombre
   limit 50;
$$;

-- Mis boliches: activos y revocados (los revocados sirven para el historial)
create or replace function public.mis_establecimientos()
returns table (id text, nombre text, logo_url text, ciudad text, color text,
               rol text, team text, activo boolean, desde timestamptz)
language sql
stable
security definer
set search_path = public
as $$
  with mios as (
    select c.id from clubs c, profiles p
     where p.id = auth.uid() and c.id = any(p.clubs)
    union
    select cm.club_id from club_membership cm where cm.user_id = auth.uid()
  )
  select c.id, c.nombre, c.logo_url, c.ciudad, c.color_primario,
         rol_en_club(c.id),
         (select t.nombre from teams t where t.id = impl.team_en_club(auth.uid(), c.id)),
         rol_en_club(c.id) is not null,
         (select cm.aprobado_at from club_membership cm where cm.user_id = auth.uid() and cm.club_id = c.id)
    from clubs c join mios m on m.id = c.id
   where c.activo
   order by rol_en_club(c.id) is null, c.nombre;
$$;

create or replace function public.mis_solicitudes()
returns table (id uuid, club_id text, club text, logo_url text, team text, origen text,
               estado text, created_at timestamptz, resuelto_at timestamptz)
language sql
stable
security definer
set search_path = public
as $$
  select s.id, s.club_id, c.nombre, c.logo_url, t.nombre, s.origen, s.estado, s.created_at, s.resuelto_at
    from solicitud_union s
    join clubs c on c.id = s.club_id
    left join teams t on t.id = s.team_id
   where s.user_id = auth.uid()
     and (s.estado = 'pendiente' or s.resuelto_at > now() - interval '30 days')
   order by s.created_at desc;
$$;

-- Lo que ve el admin (todas) o el jefe (las de su team y las sin team)
create or replace function public.solicitudes_club(p_club text)
returns table (id uuid, user_id uuid, nombre text, usuario text, email text, foto_url text,
               origen text, team_id uuid, team text, created_at timestamptz,
               eventos_trabajados bigint, boliches bigint)
language plpgsql
stable
security definer
set search_path = public
as $$
#variable_conflict use_column
declare v_rol text; v_team uuid;
begin
  v_rol := impl.exigir(p_club, '{admin,jefe}'::text[]);
  if v_rol = 'jefe' then v_team := impl.team_en_club(auth.uid(), p_club); end if;
  return query
  select s.id, s.user_id, p.nombre, p.usuario,
         case when u.email like '%@plataforma.local' then null else u.email::text end,
         p.foto_url, s.origen, s.team_id, t.nombre, s.created_at,
         (select count(distinct x.evento_id) from (
            select r.evento_id from registros r where r.rrpp_id = s.user_id
            union select e.evento_id from entradas e where e.rrpp_id = s.user_id
            union select m.evento_id from mesas m where m.vendido_por = s.user_id) x),
         (select count(*) from club_membership cm where cm.user_id = s.user_id and cm.activo)
           + coalesce(array_length(p.clubs, 1), 0)
    from solicitud_union s
    join profiles p on p.id = s.user_id
    left join auth.users u on u.id = s.user_id
    left join teams t on t.id = s.team_id
   where s.club_id = p_club and s.estado = 'pendiente'
     and (v_rol <> 'jefe' or s.team_id is null or s.team_id = v_team)
   order by s.created_at;
end;
$$;

create or replace function public.resolver_solicitud(p_id uuid, p_aprobar boolean, p_team uuid default null)
returns json
language plpgsql
security definer
set search_path = public
as $$
declare
  s solicitud_union;
  v_rol text;
  v_team uuid;
begin
  select * into s from solicitud_union where id = p_id for update;
  if not found or s.estado <> 'pendiente' then raise exception 'Esa solicitud ya fue resuelta.'; end if;
  if s.user_id = auth.uid() then raise exception 'No podés resolver tu propia solicitud.' using errcode = '42501'; end if;
  v_rol := impl.exigir(s.club_id, '{admin,jefe}'::text[]);
  if v_rol = 'jefe' then
    v_team := impl.team_en_club(auth.uid(), s.club_id);
    if v_team is null or (s.team_id is not null and s.team_id <> v_team) then
      raise exception 'Esa solicitud es de otro team.' using errcode = '42501';
    end if;
  else
    v_team := coalesce(p_team, s.team_id);
    if v_team is not null and not exists (select 1 from teams t where t.id = v_team and t.activo
              and (coalesce(array_length(t.clubs, 1), 0) = 0 or s.club_id = any(t.clubs))) then
      raise exception 'Ese team no trabaja en este boliche.';
    end if;
  end if;

  update solicitud_union
     set estado = case when p_aprobar then 'aprobada' else 'rechazada' end,
         team_id = case when p_aprobar then v_team else team_id end,
         resuelto_por = auth.uid(), resuelto_at = now()
   where id = s.id;

  if p_aprobar then
    perform set_config('venue.perfil_aprobado', '1', true);
    insert into club_membership (user_id, club_id, rol, team_id, activo, origen, aprobado_por, aprobado_at, revocado_at)
    values (s.user_id, s.club_id, 'rrpp', v_team, true, s.origen, auth.uid(), now(), null)
    on conflict (user_id, club_id) do update
       set rol = 'rrpp', team_id = excluded.team_id, activo = true, origen = excluded.origen,
           aprobado_por = excluded.aprobado_por, aprobado_at = excluded.aprobado_at, revocado_at = null;
  end if;
  return json_build_object('estado', case when p_aprobar then 'aprobada' else 'rechazada' end, 'team_id', v_team);
end;
$$;

-- Saca a alguien de ESTE boliche. Sus números quedan; los otros boliches, intactos.
create or replace function public.revocar_acceso(p_user uuid, p_club text)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare v_rol text; p profiles;
begin
  v_rol := impl.exigir(p_club, '{admin,jefe}'::text[]);
  if p_user = auth.uid() then raise exception 'No podés quitarte el acceso a vos mismo.'; end if;
  select * into p from profiles where id = p_user;
  if not found then raise exception 'Esa persona no existe.'; end if;
  if p.admin_principal or p.rol not in ('rrpp', 'jefe')
     or exists (select 1 from platform_admins pa where pa.user_id = p_user) then
    raise exception 'Desde acá solo se quita el acceso a relacionadores y jefes.' using errcode = '42501';
  end if;
  if v_rol = 'jefe' and (impl.team_en_club(p_user, p_club) is distinct from impl.team_en_club(auth.uid(), p_club)
                         or p.rol = 'jefe') then
    raise exception 'Solo podés quitar a gente de tu team.' using errcode = '42501';
  end if;
  perform set_config('venue.perfil_aprobado', '1', true);
  insert into club_membership (user_id, club_id, rol, team_id, activo, revocado_at)
  values (p_user, p_club, case when p.rol = 'jefe'
                   and not coalesce((select t.clubs is null or p_club = any(t.clubs)
                                       from teams t where t.id = p.team_id), false)
               then 'rrpp' else p.rol end, null, false, now())
  on conflict (user_id, club_id) do update set activo = false, revocado_at = now();
end;
$$;

create or replace function public.set_permisos(p_user uuid, p_club text, p_permisos jsonb)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare p profiles;
begin
  perform impl.exigir(p_club, '{admin}'::text[]);
  select * into p from profiles where id = p_user;
  if not found then raise exception 'Esa persona no existe.'; end if;
  perform set_config('venue.perfil_aprobado', '1', true);
  if exists (select 1 from club_membership cm where cm.user_id = p_user and cm.club_id = p_club) then
    update club_membership set permisos = coalesce(p_permisos, '{}'::jsonb)
     where user_id = p_user and club_id = p_club;
  elsif p_club = any(p.clubs) then
    insert into club_membership (user_id, club_id, rol, team_id, activo, permisos)
    values (p_user, p_club, case when p.rol = 'jefe'
                   and not coalesce((select t.clubs is null or p_club = any(t.clubs)
                                       from teams t where t.id = p.team_id), false)
               then 'rrpp' else p.rol end, null, true, coalesce(p_permisos, '{}'::jsonb));
  else
    raise exception 'Esa persona no trabaja en este boliche.';
  end if;
end;
$$;

create or replace function public.permisos_de(p_user uuid, p_club text)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
begin
  perform impl.exigir(p_club, '{admin}'::text[]);
  return coalesce((select permisos from club_membership where user_id = p_user and club_id = p_club), '{}'::jsonb);
end;
$$;

create or replace function public.invitacion_club(p_club text)
returns json
language plpgsql
stable
security definer
set search_path = public
as $$
begin
  perform impl.exigir(p_club, '{admin}'::text[]);
  return (select json_build_object('code', invite_code, 'activo', invite_activo,
                                   'publicas', solicitudes_publicas)
            from clubs where id = p_club);
end;
$$;

create or replace function public.regenerar_invitacion_club(p_club text)
returns text
language plpgsql
security definer
set search_path = public
as $$
declare v text := replace(gen_random_uuid()::text, '-', '');
begin
  perform impl.exigir(p_club, '{admin}'::text[]);
  update clubs set invite_code = v, invite_activo = true where id = p_club;
  return v;
end;
$$;

create or replace function public.config_solicitudes_club(p_club text, p_invite_activo boolean default null,
                                                          p_publicas boolean default null)
returns json
language plpgsql
security definer
set search_path = public
as $$
begin
  perform impl.exigir(p_club, '{admin}'::text[]);
  update clubs set invite_activo = coalesce(p_invite_activo, invite_activo),
                   solicitudes_publicas = coalesce(p_publicas, solicitudes_publicas)
   where id = p_club;
  return public.invitacion_club(p_club);
end;
$$;

-- ── 7. espacio del relacionador ────────────────────────────────────────
-- Una fila por evento trabajado, solo del que pregunta. Corre como dueño,
-- así que lee las vistas completas y filtra por auth.uid(): el historial
-- queda aunque le hayan quitado el boliche.
create or replace function public.rrpp_eventos(p_desde date default null, p_hasta date default null,
                                              p_club text default null)
returns table (
  evento_id uuid, club_id text, club text, logo_url text, evento text, fecha date, estado text,
  anotados bigint, ingresaron bigint, entradas_vendidas bigint, entradas_usadas bigint,
  mesas_confirmadas bigint, mesas_reservadas bigint, bruto_entradas numeric, bruto_mesas numeric,
  comision_entradas numeric, comision_mesas numeric, comision_jefe numeric, bono numeric,
  comision_total numeric, por_manilla numeric, estado_comision text, pagado_at timestamptz)
language plpgsql
stable
security definer
set search_path = public
as $$
#variable_conflict use_column
declare v_uid uuid := auth.uid();
begin
  if v_uid is null then raise exception 'Iniciá sesión.' using errcode = '28000'; end if;
  return query
  with evs as (
    select e.* from eventos e
     where (p_club is null or e.club_id = p_club)
       and (p_desde is null or e.fecha >= p_desde)
       and (p_hasta is null or e.fecha <= p_hasta)
       and (exists (select 1 from registros r where r.evento_id = e.id and r.rrpp_id = v_uid)
         or exists (select 1 from entradas x where x.evento_id = e.id and x.rrpp_id = v_uid)
         or exists (select 1 from mesas m where m.evento_id = e.id and m.vendido_por = v_uid)
         or exists (select 1 from bonos b where b.evento_id = e.id and b.user_id = v_uid))
  ),
  base as (
    select e.id, e.club_id, e.nombre, e.fecha, e.estado,
           s.anotados, s.ingresaron, s.entradas_vendidas, s.entradas_usadas,
           s.bruto_entradas::numeric as bruto_entradas, s.comision_rrpp::numeric as comision_rrpp,
           coalesce(m.comision_rrpp_mesas, 0)::numeric as comision_rrpp_mesas,
           s.team_id,
           (select count(*) from mesas mm where mm.evento_id = e.id and mm.vendido_por = v_uid
              and mm.estado not in ('disponible', 'reservada')) as mesas_conf,
           (select count(*) from mesas mm where mm.evento_id = e.id and mm.vendido_por = v_uid
              and mm.estado = 'reservada') as mesas_res,
           (select coalesce(sum(mm.precio), 0) from mesas mm where mm.evento_id = e.id
              and mm.vendido_por = v_uid and mm.estado not in ('disponible', 'reservada'))::numeric as bruto_mesas,
           coalesce((select sum(b.monto) from bonos b where b.evento_id = e.id and b.user_id = v_uid), 0)::numeric as bono,
           (impl.comision_manilla(e.id, v_uid)).rrpp::numeric as por_manilla
      from evs e
      join v_stats_rrpp s on s.evento_id = e.id and s.rrpp_id = v_uid
      left join v_stats_mesas m on m.evento_id = e.id and m.rrpp_id = v_uid
  ),
  -- comisión de jefe: la de todo su team en ese evento, solo si es jefe ahí
  jefe as (
    select b.id,
           case when exists (select 1 from profiles p where p.id = v_uid and p.rol = 'jefe')
                 and b.team_id is not null
                then coalesce((select sum(s2.comision_jefe) from v_stats_rrpp s2
                                where s2.evento_id = b.id and s2.team_id = b.team_id), 0)
                   + coalesce((select sum(m2.comision_jefe_mesas) from v_stats_mesas m2
                                where m2.evento_id = b.id and m2.team_id = b.team_id), 0)
                else 0 end::numeric as cj
      from base b
  )
  select b.id, b.club_id, c.nombre, c.logo_url, b.nombre, b.fecha, b.estado,
         b.anotados, b.ingresaron, b.entradas_vendidas, b.entradas_usadas,
         b.mesas_conf, b.mesas_res, b.bruto_entradas, b.bruto_mesas,
         b.comision_rrpp, b.comision_rrpp_mesas, j.cj, b.bono,
         b.comision_rrpp + b.comision_rrpp_mesas + j.cj + b.bono,
         b.por_manilla,
         case when rr.pagado then 'pagada'
              when b.estado = 'cerrado' then 'confirmada'
              else 'estimada' end,
         case when rr.pagado then rr.marcado_at end
    from base b
    join jefe j on j.id = b.id
    join clubs c on c.id = b.club_id
    left join rendicion_rrpp rr on rr.evento_id = b.id and rr.rrpp_id = v_uid
   order by b.fecha desc;
end;
$$;

-- Próximos eventos de los boliches donde trabaja hoy
create or replace function public.rrpp_proximos(p_club text default null)
returns table (evento_id uuid, club_id text, club text, logo_url text, evento text, fecha date,
               hora_inicio time, flyer_url text, anotados bigint, ingresaron bigint,
               entradas_vendidas bigint, mesas bigint, por_manilla numeric, cupo_total bigint,
               ref_code text, aftr_publico boolean)
language plpgsql
stable
security definer
set search_path = public
as $$
#variable_conflict use_column
declare v_uid uuid := auth.uid();
begin
  if v_uid is null then raise exception 'Iniciá sesión.' using errcode = '28000'; end if;
  return query
  select e.id, e.club_id, c.nombre, c.logo_url, e.nombre, e.fecha, e.hora_inicio, e.flyer_url,
         (select count(*) from registros r where r.evento_id = e.id and r.rrpp_id = v_uid),
         (select count(*) from registros r where r.evento_id = e.id and r.rrpp_id = v_uid and r.ingreso_at is not null),
         (select count(*) from entradas x where x.evento_id = e.id and x.rrpp_id = v_uid
             and x.estado <> 'anulada' and x.mesa_id is null),
         (select count(*) from mesas m where m.evento_id = e.id and m.vendido_por = v_uid
             and m.estado <> 'disponible'),
         (impl.comision_manilla(e.id, v_uid)).rrpp::numeric,
         (select sum(cr.cupo) from cupo_rrpp cr join lista_tipos lt on lt.id = cr.lista_tipo_id
           where lt.evento_id = e.id and cr.user_id = v_uid)::bigint,
         (select p.ref_code from profiles p where p.id = v_uid),
         coalesce(e.aftr_publico, false)
    from eventos e
    join clubs c on c.id = e.club_id
   where e.fecha >= current_date and e.estado <> 'cerrado' and c.activo
     and (p_club is null or e.club_id = p_club)
     and rol_en_club(e.club_id) in ('rrpp', 'jefe', 'admin')
   order by e.fecha, e.hora_inicio nulls last
   limit 30;
end;
$$;

-- Código del enlace personal (se crea la primera vez)
create or replace function public.rrpp_mi_ref()
returns text
language plpgsql
security definer
set search_path = public
as $$
declare v text;
begin
  if auth.uid() is null then raise exception 'Iniciá sesión.' using errcode = '28000'; end if;
  select ref_code into v from profiles where id = auth.uid();
  if v is not null then return v; end if;
  loop
    v := lower(substr(replace(gen_random_uuid()::text, '-', ''), 1, 8));
    exit when not exists (select 1 from profiles where ref_code = v);
  end loop;
  update profiles set ref_code = v where id = auth.uid();
  return v;
end;
$$;

-- AFTR registra cada visita que llega con ?r=. Público, con tope.
create or replace function public.aftr_visita_ref(p_evento uuid, p_ref text)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare v_rrpp uuid; v_cli uuid;
begin
  select id into v_rrpp from profiles where ref_code = lower(p_ref) and activo;
  if v_rrpp is null or not exists (select 1 from eventos where id = p_evento) then return; end if;
  if auth.uid() is not null then
    select user_id into v_cli from aftr_clientes where user_id = auth.uid();
  end if;
  -- una visita por cliente (o por minuto si es anónimo) alcanza
  if exists (select 1 from link_visita where rrpp_id = v_rrpp and evento_id = p_evento
               and ((v_cli is not null and cliente_id = v_cli)
                    or (v_cli is null and cliente_id is null and at > now() - interval '1 minute'))) then
    return;
  end if;
  insert into link_visita (rrpp_id, evento_id, cliente_id) values (v_rrpp, p_evento, v_cli);
end;
$$;

-- Conversión del enlace: visitas y compras de clientes que entraron por él
create or replace function public.rrpp_links(p_desde date default null)
returns table (evento_id uuid, evento text, fecha date, visitas bigint, clientes bigint, compras bigint)
language sql
stable
security definer
set search_path = public
as $$
  select e.id, e.nombre, e.fecha, count(v.id),
         count(distinct v.cliente_id),
         (select count(*) from aftr_ordenes o
           where o.evento_id = e.id and o.estado = 'confirmada'
             and o.cliente_id in (select v2.cliente_id from link_visita v2
                                   where v2.rrpp_id = auth.uid() and v2.evento_id = e.id
                                     and v2.cliente_id is not null and v2.at <= o.created_at))
    from link_visita v join eventos e on e.id = v.evento_id
   where v.rrpp_id = auth.uid() and (p_desde is null or e.fecha >= p_desde)
   group by e.id, e.nombre, e.fecha
   order by e.fecha desc;
$$;

-- Invitados que vuelven: mismo cliente de AFTR o mismo nombre en 2+ eventos suyos
create or replace function public.rrpp_recurrentes(p_club text default null)
returns table (nombre text, eventos bigint, ultima date)
language sql
stable
security definer
set search_path = public
as $$
  select min(r.nombre), count(distinct r.evento_id), max(e.fecha)
    from registros r join eventos e on e.id = r.evento_id
   where r.rrpp_id = auth.uid() and (p_club is null or e.club_id = p_club)
     and coalesce(r.oculto, false) = false
   group by coalesce(r.cliente_id::text, lower(unaccent(trim(r.nombre))))
  having count(distinct r.evento_id) >= 2
   order by count(distinct r.evento_id) desc, max(e.fecha) desc
   limit 30;
$$;

-- ── 8. permisos de ejecución ───────────────────────────────────────────
do $$
declare f text;
begin
  foreach f in array array[
    'rrpp_crear_cuenta(text)', 'solicitar_union(text, text)', 'cancelar_solicitud(uuid)',
    'explorar_boliches(text)', 'mis_establecimientos()', 'mis_solicitudes()',
    'solicitudes_club(text)', 'resolver_solicitud(uuid, boolean, uuid)', 'revocar_acceso(uuid, text)',
    'set_permisos(uuid, text, jsonb)', 'permisos_de(uuid, text)', 'invitacion_club(text)',
    'regenerar_invitacion_club(text)', 'config_solicitudes_club(text, boolean, boolean)',
    'rrpp_eventos(date, date, text)', 'rrpp_proximos(text)', 'rrpp_mi_ref()',
    'rrpp_links(date)', 'rrpp_recurrentes(text)']
  loop
    execute format('revoke all on function public.%s from public, anon', f);
    execute format('grant execute on function public.%s to authenticated', f);
  end loop;
end $$;
revoke all on function public.ver_invitacion(text) from public;
grant execute on function public.ver_invitacion(text) to anon, authenticated;
revoke all on function public.aftr_visita_ref(uuid, text) from public;
grant execute on function public.aftr_visita_ref(uuid, text) to anon, authenticated;
