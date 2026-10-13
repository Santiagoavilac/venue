-- SEGURIDAD (3/…) · los triggers de protección confundían "anónimo" con
-- "servicio".
--
-- cuenta_protegida_guard, perfil_update_guard y membresia_protegida_guard
-- dejaban pasar todo cuando auth.uid() era NULL, asumiendo que eso solo
-- ocurre en el contexto de servicio. Pero una llamada con la anon key (sin
-- sesión) también tiene uid NULL: a través de cualquier RPC definer sin
-- guarda, un anónimo podía tocar la cuenta protegida.
--
-- Ahora "servicio" se decide con es_servicio() (18-helpers-permiso.sql):
-- JWT con rol service_role, o sesión directa de postgres sin JWT. Un uid
-- NULL que no es servicio se rechaza.
--
-- Mismas reglas de negocio que 08 y 09; solo cambia esa condición.
-- Re-ejecutable.

create or replace function cuenta_protegida_guard()
returns trigger language plpgsql security definer set search_path = public
as $$
declare v_uid uuid := auth.uid();
begin
  if es_servicio() then
    return coalesce(new, old);
  end if;
  if v_uid is null then
    raise exception 'No autenticado.' using errcode = '28000';
  end if;
  if tg_op = 'DELETE' then
    if old.admin_principal then
      raise exception 'Esta cuenta administrativa está protegida.';
    end if;
    return old;
  end if;
  if old.admin_principal and v_uid <> old.id then
    raise exception 'Esta cuenta administrativa está protegida.';
  end if;
  if new.admin_principal is distinct from old.admin_principal then
    raise exception 'Esta cuenta administrativa está protegida.';
  end if;
  return new;
end;
$$;

create or replace function perfil_update_guard()
returns trigger language plpgsql security definer set search_path = public
as $$
declare v_uid uuid := auth.uid(); v_rol text;
begin
  if es_servicio() then return new; end if;
  if v_uid is null then
    raise exception 'No autenticado.' using errcode = '28000';
  end if;

  /* La persona sobre su propia fila: antes pasaba sin mirar (v_uid = old.id
     -> return new), y la política de RLS deja al jefe hacer UPDATE de las
     filas de su team, que incluyen LA SUYA: podía subirse a admin. Nadie se
     cambia a sí mismo rol, boliches, team ni marcas de permiso. */
  if v_uid = old.id then
    if new.rol is distinct from old.rol
       or new.clubs is distinct from old.clubs
       or new.team_id is distinct from old.team_id
       or new.activo is distinct from old.activo
       or new.cut_rel is distinct from old.cut_rel
       or new.puede_tickear is distinct from old.puede_tickear
       or new.eliminado_at is distinct from old.eliminado_at
       or new.solo_invitaciones is distinct from old.solo_invitaciones
       or new.contabilidad_total is distinct from old.contabilidad_total
       or new.usuario is distinct from old.usuario then
      if not es_platform_admin() then
        raise exception 'No podés cambiar tus propios permisos.' using errcode = '42501';
      end if;
    end if;
    return new;
  end if;

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
                and new.solo_invitaciones is not distinct from old.solo_invitaciones
                and new.contabilidad_total is not distinct from old.contabilidad_total) then
      raise exception 'Un jefe solo puede activar o pausar a la gente de su team.';
    end if;
    return new;
  end if;

  /* Admin de boliche sobre otra persona: solo gente que administra, y la
     marca de contabilidad general la da únicamente un platform admin. */
  if not impl.puede_admin_usuario(old.id) then
    raise exception 'No autorizado.' using errcode = '42501';
  end if;
  if new.contabilidad_total is distinct from old.contabilidad_total
     and not es_platform_admin() then
    raise exception 'No autorizado.' using errcode = '42501';
  end if;
  if new.rol = 'admin' and old.rol <> 'admin' and not es_platform_admin() then
    raise exception 'Solo un administrador de la plataforma puede nombrar administradores.' using errcode = '42501';
  end if;
  -- no puede asignarle boliches que él mismo no administra
  if new.clubs is distinct from old.clubs and not es_platform_admin()
     and exists (select 1 from unnest(new.clubs) c where rol_en_club(c) is distinct from 'admin') then
    raise exception 'No autorizado.' using errcode = '42501';
  end if;
  return new;
end;
$$;

create or replace function membresia_protegida_guard()
returns trigger language plpgsql security definer set search_path = public
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
  /* la membresía ES el rol en ese boliche: solo la escribe el admin de ese
     boliche (y, si la mueve de boliche, del nuevo también). Antes quien
     llamaba sobre SU PROPIA fila pasaba sin mirar. */
  if rol_en_club(v_club) is distinct from 'admin'
     or (tg_op = 'UPDATE' and rol_en_club(new.club_id) is distinct from 'admin') then
    raise exception 'No autorizado.' using errcode = '42501';
  end if;
  return coalesce(new, old);
end;
$$;
