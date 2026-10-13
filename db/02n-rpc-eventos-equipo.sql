-- RPCs de EVENTOS, FASES y EQUIPO + defaults para los INSERTs directos de
-- la app. ETAPA 1: paridad. Nada de mejoras acá.
--
-- REGLA DURA: ninguna se ejecutó contra el origen. Evidencia (2026-08-20):
--
-- · Firmas confirmadas por hint de PostgREST (sin ejecutar): publicar_evento
--   (p_evento), eliminar_evento(p_evento), borrar_fase(p_fase),
--   set_manillas_externas(p_cant, p_evento), guardar_telefono(p_tel),
--   guardar_telefono_de(p_tel, p_user), marcar_aviso_visto(p_aviso).
-- · TELÉFONOS (128 reales): 126 son '591'+8 dígitos; los otros 2 (10 y 12
--   dígitos, prefijos 447/854) se guardaron TAL CUAL ⇒ normalización: solo
--   dígitos; si quedan 8 se antepone 591; si no, va como vino.
-- · ELIMINAR USUARIO: 3 perfiles reales archivados con usuario renombrado
--   '<usuario>.borrado.<6 hex minúsculas>', activo=false, eliminado_at
--   seteado y el resto intacto; y usuarios borrados DUROS que ya no están
--   en profiles (el portero eecf049b que marcó ingresos) ⇒ con actividad
--   se archiva, sin actividad se borra la fila.
-- · TEAMS: cero teams inactivos o archivados ⇒ eliminar_team borra duro
--   (tras mover a la gente). invite_code real: 6 hex minúsculas.
-- · PUBLICAR: eventos.publicado_por sólo en el evento más nuevo (feature
--   nueva); el flujo borrador de la UI exige default publicado=false.
-- · DEFAULTS de eventos: derivados de la fila creada por la app
--   (Aniversario) descontando lo editado después, contrastado con los
--   eventos viejos (p.ej. cut_base='usada' en 9/10 ⇒ default).
--
-- SUPUESTOS documentados por función: textos de error, el modo 'eliminado'
-- de eliminar_usuario (la UI solo distingue 'archivado'), el team destino
-- de set_team_qr sin p_team (team base del caller), y guardar_cupo_team
-- con 0/null = quitar la fila (el cliente manda 0 al vaciar el campo y
-- todos los cupos reales observados son null).


-- ============================================================
-- DEFAULTS · la app escribe DIRECTO en estas tablas con pocas columnas;
-- el origen completa el resto con defaults. Sin esto, la app no puede
-- crear eventos/listas/mesas/teams/combos contra el destino.
-- ============================================================
alter table eventos alter column hora_inicio set default '21:00';
alter table eventos alter column hora_fin set default '06:00';
alter table eventos alter column edad_min set default 18;
alter table eventos alter column pct_rrpp set default 50;
alter table eventos alter column estado set default 'proximo';
alter table eventos alter column created_at set default now();
alter table eventos alter column ticket_url set default '';
alter table eventos alter column lista_hasta set default '23:00';
alter table eventos alter column manillas_externas set default 0;
alter table eventos alter column venta_por_fases set default false;
alter table eventos alter column publicado set default false;
alter table eventos alter column publicado_at drop not null;   -- un borrador aún no se publicó
alter table eventos alter column permite_reserva set default true;
alter table eventos alter column horas_reserva set default 3;
alter table eventos alter column permite_agrupar set default true;
alter table eventos alter column combo_obligatorio set default true;
alter table eventos alter column combo_por_mesa set default false;
alter table eventos alter column cut_base set default 'usada';
alter table eventos alter column id set default gen_random_uuid();

alter table lista_tipos alter column id set default gen_random_uuid();
alter table lista_tipos alter column registro_hasta drop not null;  -- la app inserta listas sin ventana

alter table mesas alter column id set default gen_random_uuid();
alter table mesas alter column estado set default 'disponible';
alter table mesas alter column botellas set default '{}';
alter table mesas alter column manillas set default 0;
alter table mesas alter column combo_qty set default 1;
alter table mesas alter column pago_verificado set default false;
alter table mesas alter column cortesia set default false;
alter table mesas alter column updated_at set default now();

alter table teams alter column id set default gen_random_uuid();
alter table teams alter column activo set default true;
alter table teams alter column created_at set default now();
alter table teams alter column invite_code set default lower(substr(md5(random()::text), 1, 6));

alter table combos alter column id set default gen_random_uuid();
alter table combos alter column activo set default true;
alter table qr_cobro alter column id set default gen_random_uuid();
alter table qr_cobro alter column activo set default true;
alter table qr_cobro alter column created_at set default now();
alter table avisos alter column id set default gen_random_uuid();
alter table avisos alter column activo set default true;
alter table avisos alter column created_at set default now();
alter table avisos alter column creado_por set default auth.uid();
alter table venta_excepcion alter column id set default gen_random_uuid();
alter table venta_excepcion alter column created_at set default now();
alter table venta_excepcion alter column creado_por set default auth.uid();
alter table cupo_permanente alter column updated_at set default now();
alter table plano_fondos alter column updated_at set default now();
alter table caja_check alter column marcado_por set default auth.uid();

-- bonos: la app la inserta directo (evento_id, user_id, monto, motivo)
create table if not exists bonos (
  id         uuid primary key default gen_random_uuid(),
  evento_id  uuid not null references eventos(id),
  user_id    uuid not null references profiles(id),
  monto      numeric not null,
  motivo     text,
  created_at timestamptz not null default now(),
  creado_por uuid default auth.uid()
);


/* publicar_evento(p_evento) -> json {nombre, listas, mesas}
 * El borrador se hace visible. La UI muestra "N lista(s) y M mesa(s) ya
 * visibles" con los conteos de la respuesta. */
create or replace function publicar_evento(p_evento uuid)
returns json
language plpgsql
volatile
security definer
set search_path = public
as $$
declare e eventos%rowtype;
begin
  select * into e from eventos where id = p_evento;
  if not found then raise exception 'Evento no encontrado'; end if;   -- TEXTO SUPUESTO
  update eventos set publicado = true, publicado_por = auth.uid(), publicado_at = now()
   where id = p_evento;
  return json_build_object(
    'nombre', e.nombre,
    'listas', (select count(*) from lista_tipos where evento_id = p_evento),
    'mesas',  (select count(*) from mesas where evento_id = p_evento));
end;
$$;


/* eliminar_evento(p_evento) -> json {nombre}
 * Borra el evento con TODO su contenido (el diálogo del cliente lo avisa:
 * listas, anotados, entradas, mesas y ventas). */
create or replace function eliminar_evento(p_evento uuid)
returns json
language plpgsql
volatile
security definer
set search_path = public
as $$
declare v_nombre text;
begin
  select nombre into v_nombre from eventos where id = p_evento;
  if not found then raise exception 'Evento no encontrado'; end if;   -- TEXTO SUPUESTO
  delete from entradas where evento_id = p_evento;
  delete from registros where evento_id = p_evento;
  delete from cupo_rrpp where lista_tipo_id in (select id from lista_tipos where evento_id = p_evento);
  delete from lista_tipos where evento_id = p_evento;
  delete from mesas where evento_id = p_evento;
  delete from pagos where evento_id = p_evento;
  delete from caja_check where evento_id = p_evento;
  delete from venta_excepcion where evento_id = p_evento;
  delete from bonos where evento_id = p_evento;
  delete from bar_venta_items where venta_id in (select id from bar_ventas where evento_id = p_evento);
  delete from bar_ventas where evento_id = p_evento;
  delete from stock_mov where evento_id = p_evento;
  delete from bar_staff where evento_id = p_evento;
  delete from evento_fase where evento_id = p_evento;   -- arrastra fase_cupo_team (cascade)
  delete from eventos where id = p_evento;
  return json_build_object('nombre', v_nombre);
end;
$$;


/* guardar_fase(...) -> void · alta o edición según p_id */
create or replace function guardar_fase(
  p_evento uuid, p_id uuid, p_nombre text, p_precio numeric, p_cupo int,
  p_desde timestamptz, p_hasta timestamptz, p_orden int, p_activo boolean)
returns void
language plpgsql
volatile
security definer
set search_path = public
as $$
begin
  if p_id is null then
    insert into evento_fase (id, evento_id, nombre, precio, cupo, desde, hasta, orden, activo, created_at)
    values (gen_random_uuid(), p_evento, trim(p_nombre), p_precio, p_cupo, p_desde, p_hasta, p_orden, coalesce(p_activo, true), now());
  else
    update evento_fase set nombre = trim(p_nombre), precio = p_precio, cupo = p_cupo,
           desde = p_desde, hasta = p_hasta, orden = p_orden, activo = coalesce(p_activo, true)
     where id = p_id and evento_id = p_evento;
  end if;
end;
$$;


/* borrar_fase(p_fase) -> void · la UI solo lo ofrece sin vendidas; el
 * server lo re-valida (SUPUESTO: sin evidencia en contra). */
create or replace function borrar_fase(p_fase uuid)
returns void
language plpgsql
volatile
security definer
set search_path = public
as $$
begin
  if exists (select 1 from entradas where fase_id = p_fase) then
    raise exception 'La fase ya tiene entradas vendidas';   -- TEXTO SUPUESTO
  end if;
  delete from evento_fase where id = p_fase;
end;
$$;


create or replace function set_venta_por_fases(p_evento uuid, p_on boolean)
returns void
language sql volatile security definer set search_path = public
as $$ update eventos set venta_por_fases = p_on where id = p_evento; $$;

create or replace function set_manillas_externas(p_evento uuid, p_cant int)
returns void
language sql volatile security definer set search_path = public
as $$ update eventos set manillas_externas = greatest(coalesce(p_cant, 0), 0) where id = p_evento; $$;


/* set_team_qr(p_url, p_team default null) -> void
 * El jefe sube el QR de SU team; el admin puede apuntar a cualquiera con
 * p_team. p_url null quita el QR. Sin p_team se usa el team BASE del que
 * llama — SUPUESTO: la RPC no recibe club y no hay evidencia de otra
 * resolución (el único caso ambiguo sería un jefe con team distinto por
 * boliche usando la forma sin p_team). */
create or replace function set_team_qr(p_url text, p_team uuid default null)
returns void
language plpgsql
volatile
security definer
set search_path = public
as $$
declare v_team uuid;
begin
  v_team := coalesce(p_team, (select team_id from profiles where id = auth.uid()));
  if v_team is null then
    raise exception 'No tenés team asignado';   -- TEXTO SUPUESTO
  end if;
  update teams set qr_cobro_url = p_url where id = v_team;
end;
$$;


/* normalización de celular (126/128 reales son 591+8 dígitos; los
 * extranjeros van tal cual) */
create or replace function telefono_normalizar(p_tel text)
returns text
language sql immutable
as $$
  select case when d = '' then null
              when length(d) = 8 then '591' || d
              else d end
  from (select regexp_replace(coalesce(p_tel, ''), '\D', '', 'g') as d) x;
$$;

create or replace function guardar_telefono(p_tel text)
returns void
language plpgsql
volatile
security definer
set search_path = public
as $$
declare v text := telefono_normalizar(p_tel);
begin
  if v is null then
    delete from telefono_usuario where user_id = auth.uid();
    return;
  end if;
  insert into telefono_usuario (user_id, telefono, actualizado_at, cargado_por)
  values (auth.uid(), v, now(), auth.uid())
  on conflict (user_id) do update set telefono = excluded.telefono,
    actualizado_at = now(), cargado_por = auth.uid();
end;
$$;

/* guardar_telefono_de(p_tel, p_user) -> void · el admin carga o borra el
 * número de otro ("Dejalo vacío para borrarlo"). */
create or replace function guardar_telefono_de(p_tel text, p_user uuid)
returns void
language plpgsql
volatile
security definer
set search_path = public
as $$
declare v text := telefono_normalizar(p_tel);
begin
  if (select rol from profiles where id = auth.uid()) is distinct from 'admin' then
    raise exception 'Solo el admin puede cargar el número de otra persona';  -- TEXTO SUPUESTO
  end if;
  if v is null then
    delete from telefono_usuario where user_id = p_user;
    return;
  end if;
  insert into telefono_usuario (user_id, telefono, actualizado_at, cargado_por)
  values (p_user, v, now(), auth.uid())
  on conflict (user_id) do update set telefono = excluded.telefono,
    actualizado_at = now(), cargado_por = auth.uid();
end;
$$;


/* eliminar_usuario(p_user) -> json {modo}
 * Con actividad (listas, entradas, mesas o pagos): ARCHIVA — usuario
 * renombrado '<usuario>.borrado.<hex6>', activo=false, eliminado_at=now()
 * (patrón exacto de los 3 archivados reales). Sin actividad: borra la
 * fila (los usuarios duros ya no están en profiles). El valor del modo
 * no-archivado es SUPUESTO: la UI solo distingue 'archivado'. */
create or replace function eliminar_usuario(p_user uuid)
returns json
language plpgsql
volatile
security definer
set search_path = public
as $$
declare
  v_usuario text;
  v_actividad boolean;
begin
  select usuario into v_usuario from profiles where id = p_user;
  if not found then raise exception 'Usuario no encontrado'; end if;   -- TEXTO SUPUESTO
  v_actividad := exists (select 1 from registros where rrpp_id = p_user)
              or exists (select 1 from entradas where rrpp_id = p_user)
              or exists (select 1 from mesas where vendido_por = p_user)
              or exists (select 1 from pagos where rrpp_id = p_user);
  if v_actividad then
    update profiles set
      usuario = v_usuario || '.borrado.' || lower(substr(md5(random()::text), 1, 6)),
      activo = false,
      eliminado_at = now()
    where id = p_user;
    return json_build_object('modo', 'archivado');
  end if;
  delete from club_membership where user_id = p_user;
  delete from telefono_usuario where user_id = p_user;
  delete from cupo_rrpp where user_id = p_user;
  delete from cupo_permanente where user_id = p_user;
  delete from aviso_visto where user_id = p_user;
  delete from caja_check where user_id = p_user;
  delete from profiles where id = p_user;
  return json_build_object('modo', 'eliminado');
end;
$$;


/* eliminar_team(p_team, p_destino) -> json {movidos}
 * Mueve a la gente al team destino (o la deja sin team) y borra el team
 * DURO (cero teams archivados en los datos). Las membresías sin destino se
 * borran (team_id es NOT NULL ahí). */
create or replace function eliminar_team(p_team uuid, p_destino uuid default null)
returns json
language plpgsql
volatile
security definer
set search_path = public
as $$
declare v_movidos int;
begin
  if not exists (select 1 from teams where id = p_team) then
    raise exception 'Team no encontrado';   -- TEXTO SUPUESTO
  end if;
  select count(*) into v_movidos from profiles where team_id = p_team;
  update profiles set team_id = p_destino where team_id = p_team;
  if p_destino is null then
    delete from club_membership where team_id = p_team;
  else
    update club_membership set team_id = p_destino where team_id = p_team;
  end if;
  delete from fase_cupo_team where team_id = p_team;
  update venta_excepcion set team_id = p_destino where team_id = p_team;
  delete from venta_excepcion where team_id is null and user_id is null;
  update mesas set team_id = null where team_id = p_team;
  update avisos set team_id = p_destino where team_id = p_team;
  delete from teams where id = p_team;
  return json_build_object('movidos', v_movidos);
end;
$$;


/* guardar_cupo_team(p_fase, p_team, p_cupo) -> void
 * Cupo por team dentro de una fase. El cliente manda 0 al VACIAR el campo
 * (nuevo || 0) y todos los cupos reales observados son null ⇒ 0 o null
 * quitan la fila (SUPUESTO documentado; si el original guardara 0 literal,
 * cupos_fase mostraría teams con cupo 0 y nunca se observó). */
create or replace function guardar_cupo_team(p_fase uuid, p_team uuid, p_cupo int)
returns void
language plpgsql
volatile
security definer
set search_path = public
as $$
begin
  if p_cupo is null or p_cupo <= 0 then
    delete from fase_cupo_team where fase_id = p_fase and team_id = p_team;
    return;
  end if;
  insert into fase_cupo_team (fase_id, team_id, cupo)
  values (p_fase, p_team, p_cupo)
  on conflict (fase_id, team_id) do update set cupo = excluded.cupo;
end;
$$;


/* marcar_aviso_visto(p_aviso) -> void · idempotente */
create or replace function marcar_aviso_visto(p_aviso uuid)
returns void
language sql
volatile
security definer
set search_path = public
as $$
  insert into aviso_visto (aviso_id, user_id, visto_at)
  values (p_aviso, auth.uid(), now())
  on conflict (aviso_id, user_id) do nothing;
$$;
