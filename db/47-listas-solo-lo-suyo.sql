-- 47 · Listas: cada uno ve lo que anotó
--
-- Antes cualquier relacionador o jefe del boliche leía la lista entera del
-- evento (todos los nombres, de todos). Ahora:
--   admin y seguridad  → todo (la puerta tiene que encontrar a cualquiera)
--   jefe               → lo suyo y lo de la gente de su team en ese boliche
--   relacionador       → solo lo suyo
-- Los controles de cupo y duplicados corren en funciones del servidor, que
-- siguen viendo todo.

-- team efectivo de una persona en un boliche (la misma regla que
-- impl.teams_efectivos, para una sola persona)
create or replace function impl.team_en_club(p_user uuid, p_club text)
returns uuid
language sql
stable
security definer
set search_path = public
as $$
  select coalesce(cm.team_id,
           case when tb.id is not null
                     and (p.rol = 'admin' or coalesce(array_length(tb.clubs, 1), 0) = 0 or p_club = any(tb.clubs))
                then p.team_id end)
    from profiles p
    left join club_membership cm on cm.user_id = p.id and cm.club_id = p_club
    left join teams tb on tb.id = p.team_id
   where p.id = p_user;
$$;

create or replace function impl.ve_registro(p_evento uuid, p_rrpp uuid)
returns boolean
language plpgsql
stable
security definer
set search_path = public
as $$
declare v_rol text := rol_en('evento', p_evento); v_club text; v_mio uuid;
begin
  if v_rol in ('admin', 'portero') then return true; end if;
  if v_rol = 'rrpp' then return p_rrpp = auth.uid(); end if;
  if v_rol = 'jefe' then
    if p_rrpp = auth.uid() then return true; end if;
    select club_id into v_club from eventos where id = p_evento;
    v_mio := impl.team_en_club(auth.uid(), v_club);
    return v_mio is not null and v_mio = impl.team_en_club(p_rrpp, v_club);
  end if;
  return false;
end;
$$;
grant execute on function impl.ve_registro(uuid, uuid) to authenticated;
grant execute on function impl.team_en_club(uuid, text) to authenticated;

drop policy if exists registros_leer on registros;
create policy registros_leer on registros for select to authenticated
  using (impl.ve_registro(evento_id, rrpp_id));
