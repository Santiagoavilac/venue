-- 40 · Stats por team: cada uno ve solo lo suyo
--
-- v_stats_rrpp y v_stats_mesas devolvían las filas de TODOS los
-- relacionadores del evento a cualquiera del boliche (la app escondía el
-- resto). Ahora, leídas desde la API:
--   · admin del boliche: todo
--   · jefe: su team efectivo en ese boliche (y él mismo)
--   · rrpp: solo su fila
-- Las funciones security definer (contabilidad_evento, ranking_teams…)
-- corren como su dueño, no como "authenticated", y siguen viendo todo.
--
-- El top de teams del jefe sale de ranking_teams: solo totales por team,
-- nunca la gente de los otros teams.

-- team de una persona en un boliche: la misma regla que usan las vistas
create or replace function impl.team_en_club(p_user uuid, p_club text)
returns uuid
language sql
stable
security definer
set search_path = public
as $$
  select coalesce(cm.team_id, case when tb.id is not null
                and (p.rol = 'admin' or tb.clubs is null
                     or coalesce(array_length(tb.clubs, 1), 0) = 0
                     or p_club = any(tb.clubs))
           then p.team_id end)
    from profiles p
    left join club_membership cm on cm.user_id = p.id and cm.club_id = p_club
    left join teams tb on tb.id = p.team_id
   where p.id = p_user;
$$;

-- security INVOKER a propósito: current_user es "authenticated" solo cuando
-- la vista se lee directo desde la API.
create or replace function impl.ve_stats(p_club text, p_user uuid, p_team uuid)
returns boolean
language sql
stable
set search_path = public
as $$
  select current_user not in ('authenticated', 'anon')
      or p_user = auth.uid()
      or rol_en_club(p_club) = 'admin'
      or (rol_en_club(p_club) = 'jefe' and p_team is not null
          and p_team = impl.team_en_club(auth.uid(), p_club));
$$;

grant execute on function impl.team_en_club(uuid, text) to authenticated;
grant execute on function impl.ve_stats(text, uuid, uuid) to authenticated;

create or replace view v_stats_rrpp with (security_invoker = true) as
select e.id  as evento_id,
       p.id  as rrpp_id,
       p.nombre as rrpp,
       coalesce(cm.team_id, case when tb.id is not null
                and (p.rol = 'admin' or tb.clubs is null
                     or coalesce(array_length(tb.clubs, 1), 0) = 0
                     or e.club_id = any(tb.clubs))
           then p.team_id end) as team_id,
       (select count(*) from registros r
         where r.evento_id = e.id and r.rrpp_id = p.id) as anotados,
       (select count(*) from registros r
         where r.evento_id = e.id and r.rrpp_id = p.id and r.ingreso_at is not null) as ingresaron,
       (select count(*) from entradas x
         where x.evento_id = e.id and x.rrpp_id = p.id
           and x.estado <> 'anulada' and x.mesa_id is null) as entradas_vendidas,
       (select count(*) from entradas x
         where x.evento_id = e.id and x.rrpp_id = p.id
           and x.estado = 'usada' and x.mesa_id is null) as entradas_usadas,
       (select coalesce(sum(x.precio), 0) from entradas x
         where x.evento_id = e.id and x.rrpp_id = p.id
           and x.estado <> 'anulada' and x.mesa_id is null) as bruto_entradas,
       -- quien vende: por vendidas mientras el evento está abierto, por usadas al cerrar
       (case when e.estado = 'cerrado'
             then (select count(*) from entradas x
                    where x.evento_id = e.id and x.rrpp_id = p.id
                      and x.estado = 'usada' and x.mesa_id is null)
             else (select count(*) from entradas x
                    where x.evento_id = e.id and x.rrpp_id = p.id
                      and x.estado <> 'anulada' and x.mesa_id is null) end)
         * u.rrpp as comision_rrpp,
       -- el jefe: siempre por usadas
       (select count(*) from entradas x
         where x.evento_id = e.id and x.rrpp_id = p.id
           and x.estado = 'usada' and x.mesa_id is null)
         * u.jefe as comision_jefe
  from eventos e
 cross join profiles p
  left join club_membership cm on cm.user_id = p.id and cm.club_id = e.club_id
  left join teams tb on tb.id = p.team_id
 cross join lateral impl.comision_manilla(e.id, p.id) u
 where p.rol in ('rrpp', 'jefe', 'admin')
   and impl.ve_stats(e.club_id, p.id, coalesce(cm.team_id, case when tb.id is not null
                       and (p.rol = 'admin' or tb.clubs is null
                            or coalesce(array_length(tb.clubs, 1), 0) = 0
                            or e.club_id = any(tb.clubs))
                  then p.team_id end));

create or replace view v_stats_mesas with (security_invoker = true) as
select e.id  as evento_id,
       p.id  as rrpp_id,
       p.nombre as rrpp,
       coalesce(cm.team_id, case when tb.id is not null
                and (p.rol = 'admin' or tb.clubs is null
                     or coalesce(array_length(tb.clubs, 1), 0) = 0
                     or e.club_id = any(tb.clubs))
           then p.team_id end) as team_id,
       (select count(*) from mesas mm
         where mm.evento_id = e.id and mm.vendido_por = p.id
           and mm.estado <> 'disponible') as mesas_vendidas,
       (select coalesce(sum(mm.precio), 0) from mesas mm
         where mm.evento_id = e.id and mm.vendido_por = p.id
           and mm.estado <> 'disponible') as bruto_mesas,
       -- bigint como siempre (los clientes ya lo leen así): los combos van en Bs enteros
       (select coalesce(round(sum((impl.comision_combo(mm.combo_id, p.id, e.club_id)).rrpp * mm.combo_qty)), 0)::bigint
          from mesas mm
         where mm.evento_id = e.id and mm.vendido_por = p.id and mm.combo_id is not null
           and mm.estado <> 'disponible') as comision_rrpp_mesas,
       (select coalesce(round(sum((impl.comision_combo(mm.combo_id, p.id, e.club_id)).jefe * mm.combo_qty)), 0)::bigint
          from mesas mm
         where mm.evento_id = e.id and mm.vendido_por = p.id and mm.combo_id is not null
           and mm.estado <> 'disponible') as comision_jefe_mesas
  from eventos e
 cross join profiles p
  left join club_membership cm on cm.user_id = p.id and cm.club_id = e.club_id
  left join teams tb on tb.id = p.team_id
 where p.rol in ('rrpp', 'jefe')
   and impl.ve_stats(e.club_id, p.id, coalesce(cm.team_id, case when tb.id is not null
                       and (p.rol = 'admin' or tb.clubs is null
                            or coalesce(array_length(tb.clubs, 1), 0) = 0
                            or e.club_id = any(tb.clubs))
                  then p.team_id end));

-- Top de teams de un evento: solo totales (entraron = listas + QR usados,
-- mesas, score = entraron + mesas). Admin y jefes del boliche.
create or replace function public.ranking_teams(p_evento uuid)
returns table (team_id uuid, team text, entraron bigint, mesas bigint, score bigint, es_mio boolean)
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_club text := impl.club_de('evento', p_evento);
  v_mio  uuid;
begin
  perform impl.exigir(v_club, '{admin,jefe}'::text[]);
  v_mio := impl.team_en_club(auth.uid(), v_club);
  return query
  with g as (
    select s.team_id,
           sum(s.ingresaron + s.entradas_usadas)::bigint as en,
           coalesce(sum(m.mesas_vendidas), 0)::bigint as mv
      from v_stats_rrpp s
      left join v_stats_mesas m on m.evento_id = s.evento_id and m.rrpp_id = s.rrpp_id
     where s.evento_id = p_evento and s.team_id is not null
     group by s.team_id
  )
  select g.team_id, t.nombre, g.en, g.mv, g.en + g.mv, g.team_id = v_mio
    from g join teams t on t.id = g.team_id
   where g.en + g.mv > 0 or g.team_id = v_mio
   order by g.en + g.mv desc, t.nombre;
end;
$$;

revoke all on function public.ranking_teams(uuid) from public, anon;
grant execute on function public.ranking_teams(uuid) to authenticated;
