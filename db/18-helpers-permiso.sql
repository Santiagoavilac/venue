-- SEGURIDAD (1/…) · helpers de permiso POR BOLICHE.
--
-- Hasta acá el único helper era rol_actual() (06-rls.sql), que devuelve el
-- rol BASE de la persona e ignora en qué boliche está operando. Con eso un
-- admin o un jefe de un local tenía los mismos permisos en todos.
--
-- Estos helpers resuelven el rol EFECTIVO en un boliche, con la misma regla
-- que ya usa la app (applyClubRole en app.js):
--   · platform admin (tabla platform_admins o profiles.admin_principal)
--       -> 'admin' en todos los boliches.
--   · rol base 'admin'  -> 'admin' solo en los boliches de profiles.clubs.
--   · fila en club_membership para ese boliche -> ese rol.
--   · si no, rol base, siempre que el boliche esté en profiles.clubs; y un
--     jefe cuyo team no opera en ese boliche queda como 'rrpp'.
--   · cuenta inactiva o eliminada -> null (sin permisos).
--
-- CAMBIO DELIBERADO respecto del origen: profiles.clubs vacío ya NO
-- significa "todos los boliches". Con boliches dinámicos eso le daba acceso
-- automático a cada local nuevo. Vacío = ninguno (salvo platform admin).
--
-- Re-ejecutable.

create schema if not exists impl;
revoke all on schema impl from public, anon, authenticated;
comment on schema impl is
  'Implementación interna: las RPC originales viven acá y solo se llaman '
  'a través de las guardas de public (ver 19-rpc-guardas.sql). No se expone por la API.';

-- Superadministradores de la plataforma (gestionan boliches).
create table if not exists platform_admins (
  user_id    uuid primary key references profiles(id) on delete cascade,
  created_at timestamptz not null default now()
);
alter table platform_admins enable row level security;
-- sin políticas: nadie la lee ni escribe por la API; solo contexto de servicio.

/* ¿la llamada viene del contexto de servicio (service_role, SQL editor,
   migraciones) y no de una persona? Antes los triggers tomaban
   "auth.uid() is null" como servicio, y una llamada ANÓNIMA también tiene
   uid nulo: pasaba por servicio. */
create or replace function es_servicio()
returns boolean language sql stable
as $$
  select coalesce(nullif(current_setting('request.jwt.claims', true), '')::jsonb ->> 'role', '') = 'service_role'
      or (nullif(current_setting('request.jwt.claims', true), '') is null
          and session_user in ('postgres', 'supabase_admin'));
$$;

create or replace function es_platform_admin()
returns boolean language sql stable security definer set search_path = public
as $$
  select exists (
    select 1 from profiles p
     where p.id = auth.uid() and p.activo and p.eliminado_at is null
       and (p.admin_principal
            or exists (select 1 from platform_admins pa where pa.user_id = p.id)));
$$;

create or replace function rol_en_club(p_club text)
returns text language sql stable security definer set search_path = public
as $$
  select case
           when not p.activo or p.eliminado_at is not null then null
           when p.admin_principal
             or exists (select 1 from platform_admins pa where pa.user_id = p.id) then 'admin'
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

/* team efectivo de la persona en un boliche (membresía, o el team base si
   opera ahí) */
create or replace function mi_team_en_club(p_club text)
returns uuid language sql stable security definer set search_path = public
as $$
  select coalesce(
           cm.team_id,
           (select t.id from teams t
             where t.id = p.team_id and (t.clubs is null or p_club = any(t.clubs))))
    from profiles p
    left join club_membership cm on cm.user_id = p.id and cm.club_id = p_club
   where p.id = auth.uid() and p.activo and p.eliminado_at is null;
$$;

/* boliches donde la persona tiene algún rol (para RLS) */
create or replace function mis_clubs()
returns setof text language sql stable security definer set search_path = public
as $$
  select c.id from clubs c where rol_en_club(c.id) is not null;
$$;

/* boliche al que pertenece una entidad */
create or replace function impl.club_de(p_tipo text, p_id uuid)
returns text language sql stable security definer set search_path = public
as $$
  select case p_tipo
    when 'evento'   then (select e.club_id from eventos e where e.id = p_id)
    when 'mesa'     then (select e.club_id from mesas m join eventos e on e.id = m.evento_id where m.id = p_id)
    when 'fase'     then (select e.club_id from evento_fase f join eventos e on e.id = f.evento_id where f.id = p_id)
    when 'lista'    then (select e.club_id from lista_tipos l join eventos e on e.id = l.evento_id where l.id = p_id)
    when 'registro' then (select e.club_id from registros r join eventos e on e.id = r.evento_id where r.id = p_id)
    when 'entrada'  then (select e.club_id from entradas x join eventos e on e.id = x.evento_id where x.id = p_id)
    when 'pago'     then (select e.club_id from pagos g join eventos e on e.id = g.evento_id where g.id = p_id)
    when 'aviso'    then (select a.club_id from avisos a where a.id = p_id)
    when 'bebida'   then (select b.club_id from bebidas b where b.id = p_id)
    when 'barra'    then (select b.club_id from barras b where b.id = p_id)
    when 'lote'     then (select coalesce(l.club_id, b.club_id) from lotes l join bebidas b on b.id = l.bebida_id where l.id = p_id)
    when 'venta'    then (select coalesce(v.club_id, e.club_id) from bar_ventas v join eventos e on e.id = v.evento_id where v.id = p_id)
  end;
$$;

/* Exige sesión y uno de los roles en el boliche. Devuelve el rol efectivo.
   '*' en p_roles = cualquier rol del boliche. El contexto de servicio pasa. */
create or replace function impl.exigir(p_club text, p_roles text[])
returns text language plpgsql stable security definer set search_path = public
as $$
declare v text;
begin
  if es_servicio() then return 'servicio'; end if;
  if auth.uid() is null then
    raise exception 'No autenticado.' using errcode = '28000';
  end if;
  v := rol_en_club(p_club);
  if v is null or not (v = any(p_roles) or '*' = any(p_roles)) then
    raise exception 'No autorizado.' using errcode = '42501';
  end if;
  return v;
end;
$$;

/* Exige sesión activa, sin boliche (operaciones sobre uno mismo). */
create or replace function impl.exigir_sesion()
returns text language plpgsql stable security definer set search_path = public
as $$
declare v text;
begin
  if es_servicio() then return 'servicio'; end if;
  if auth.uid() is null then
    raise exception 'No autenticado.' using errcode = '28000';
  end if;
  select p.rol into v from profiles p
   where p.id = auth.uid() and p.activo and p.eliminado_at is null;
  if v is null then
    raise exception 'No autorizado.' using errcode = '42501';
  end if;
  return v;
end;
$$;

/* varias mesas a la vez: el rol se exige en el boliche de CADA una */
create or replace function impl.exigir_mesas(p_mesas uuid[], p_roles text[])
returns text language plpgsql stable security definer set search_path = public
as $$
declare c text; v text;
begin
  if coalesce(array_length(p_mesas, 1), 0) = 0 then
    return impl.exigir_sesion();
  end if;
  for c in select distinct impl.club_de('mesa', x) from unnest(p_mesas) x loop
    v := impl.exigir(c, p_roles);
  end loop;
  return v;
end;
$$;

/* ¿quien llama administra a esta persona? Platform admin siempre; un admin
   de boliche solo si la persona NO es admin y todos sus boliches son
   boliches que él administra. */
create or replace function impl.puede_admin_usuario(p_user uuid)
returns boolean language sql stable security definer set search_path = public
as $$
  select es_servicio() or es_platform_admin() or exists (
    select 1 from profiles t
     where t.id = p_user
       and t.rol <> 'admin' and not t.admin_principal
       and coalesce(array_length(t.clubs, 1), 0) > 0
       and not exists (select 1 from unnest(t.clubs) c
                        where rol_en_club(c) is distinct from 'admin')
       and not exists (select 1 from club_membership cm
                        where cm.user_id = t.id
                          and rol_en_club(cm.club_id) is distinct from 'admin'));
$$;

/* ídem para un team: todos los boliches donde opera */
create or replace function impl.puede_admin_team(p_team uuid)
returns boolean language sql stable security definer set search_path = public
as $$
  select es_servicio() or es_platform_admin() or exists (
    select 1 from teams t
     where t.id = p_team
       and coalesce(array_length(t.clubs, 1), 0) > 0
       and not exists (select 1 from unnest(t.clubs) c
                        where rol_en_club(c) is distinct from 'admin'));
$$;

grant execute on function es_servicio(), es_platform_admin(), rol_en_club(text),
  mi_team_en_club(text), mis_clubs() to authenticated;
