-- ENDURECIMIENTO (auditoría 2026-08-21) · dos huecos server-side donde la
-- regla existía solo en la UI. No cambia ninguna regla de negocio: hace
-- cumplir en el servidor lo que la interfaz ya prometía.

-- (1) La política de RLS dejaba al JEFE hacer UPDATE de CUALQUIER columna
-- de la gente de su team (rol, clubs, team_id…) por REST directo, cuando
-- la regla real de la UI es: el jefe solo activa/pausa a los suyos.
-- El trigger limita al jefe a la columna `activo`; admins y el propio
-- usuario siguen igual; contexto de servicio (sync) intacto.
create or replace function perfil_update_guard()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare v_uid uuid := auth.uid(); v_rol text;
begin
  if v_uid is null or v_uid = old.id then return new; end if;
  select rol into v_rol from profiles where id = v_uid;
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
                and new.solo_invitaciones is not distinct from old.solo_invitaciones) then
      raise exception 'Un jefe solo puede activar o pausar a la gente de su team.';
    end if;
  end if;
  return new;
end;
$$;

drop trigger if exists perfil_update on profiles;
create trigger perfil_update
  before update on profiles
  for each row execute function perfil_update_guard();

-- (2) La cuenta protegida: sus MEMBRESÍAS por boliche (rol/team efectivos
-- en club_membership) quedaban editables por cualquier admin vía REST,
-- un camino indirecto para "cambiarle el rol". Misma regla que profiles:
-- solo el dueño o el contexto de servicio.
create or replace function membresia_protegida_guard()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare v_uid uuid := auth.uid(); v_target uuid := coalesce(new.user_id, old.user_id);
begin
  if v_uid is null or v_uid = v_target then return coalesce(new, old); end if;
  if exists (select 1 from profiles p where p.id = v_target and p.admin_principal) then
    raise exception 'Esta cuenta administrativa está protegida.';
  end if;
  return coalesce(new, old);
end;
$$;

drop trigger if exists membresia_protegida on club_membership;
create trigger membresia_protegida
  before insert or update or delete on club_membership
  for each row execute function membresia_protegida_guard();
