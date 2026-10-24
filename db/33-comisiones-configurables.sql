-- 33 · Comisiones configurables por boliche y reparto del jefe en su team.
--
-- Qué agrega
--   clubs.usa_relacionadores  ¿el boliche trabaja con relacionadores?
--   clubs.usa_teams           ¿con teams? Sin teams cada relacionador cobra
--                             la comisión entera de lo que vende.
--   clubs.comision_manillas   ¿se paga comisión por manilla/entrada?
--   clubs.comision_combos     ¿se paga comisión por combo de mesa?
--   teams.rrpp_por_manilla    lo que el jefe le da a CADA relacionador de su
--                             team por manilla. El resto de la comisión del
--                             team es del jefe; lo que vende el jefe es todo suyo.
--   teams.rrpp_por_combo      lo mismo, por combo.
--
-- La comisión del team por manilla es lo que NO es del boliche:
--   precio_manilla × (1 − pct_boliche / 100)    → manilla de 50 al 50 % = 25 Bs.
-- La del combo es comision_rrpp + comision_jefe del combo.
--
-- Todo es opcional y los valores por defecto dejan las cuentas EXACTAMENTE
-- como estaban: mientras el boliche no cambie nada y el jefe no fije su
-- reparto, corre la regla de siempre (cut_rel > cut_rrpp > fórmula por
-- porcentaje, y para el jefe la fórmula por porcentaje).
--
-- Una sola función decide cuánto es de cada uno (impl.comision_manilla e
-- impl.comision_combo) y todo lo que muestra o paga comisiones la usa:
-- v_stats_rrpp, v_stats_mesas, rendiciones_evento, ranking_rrpp,
-- historico_eventos y liquidacion_evento. Antes la cuenta estaba copiada en
-- cada una.
--
-- Re-ejecutable.

alter table clubs add column if not exists usa_relacionadores boolean not null default true;
alter table clubs add column if not exists usa_teams          boolean not null default true;
alter table clubs add column if not exists comision_manillas  boolean not null default true;
alter table clubs add column if not exists comision_combos    boolean not null default true;

alter table teams add column if not exists rrpp_por_manilla numeric;
alter table teams add column if not exists rrpp_por_combo   numeric;
do $$ begin
  alter table teams add constraint teams_reparto_no_negativo
    check (coalesce(rrpp_por_manilla, 0) >= 0 and coalesce(rrpp_por_combo, 0) >= 0);
exception when duplicate_object then null; end $$;


/* Team EFECTIVO de una persona en un boliche: la misma regla que
   v_stats_rrpp y teams_efectivos (la membresía del boliche manda; el team
   base solo si opera en ese boliche). */
create or replace function impl.team_efectivo(p_persona uuid, p_club text)
returns uuid language sql stable security definer set search_path = public
as $$
  select coalesce(cm.team_id, case when tb.id is not null
           and (p.rol = 'admin' or tb.clubs is null
                or coalesce(array_length(tb.clubs, 1), 0) = 0
                or p_club = any(tb.clubs))
         then p.team_id end)
    from profiles p
    left join club_membership cm on cm.user_id = p.id and cm.club_id = p_club
    left join teams tb on tb.id = p.team_id
   where p.id = p_persona;
$$;


/* ¿Corre la regla nueva para esta persona en este evento? Sí si el boliche
   cambió algo de su configuración o si el team de la persona tiene reparto
   fijado. Si no, cada cuenta sigue exactamente como era (ranking e
   histórico tenían su propia variante vieja y la conservan). */
create or replace function impl.reparto_nuevo(p_evento uuid, p_persona uuid)
returns boolean language sql stable security definer set search_path = public
as $$
  select not (coalesce(c.usa_relacionadores, true) and coalesce(c.usa_teams, true)
              and coalesce(c.comision_manillas, true) and coalesce(c.comision_combos, true))
      or exists (select 1 from teams t
                  where t.id = impl.team_efectivo(p_persona, e.club_id)
                    and (t.rrpp_por_manilla is not null or t.rrpp_por_combo is not null))
    from eventos e left join clubs c on c.id = e.club_id
   where e.id = p_evento;
$$;

/* Comisión de UNA manilla vendida por p_persona en p_evento:
   rrpp = lo que cobra quien la vendió · jefe = lo que cobra su jefe. */
create or replace function impl.comision_manilla(p_evento uuid, p_persona uuid,
                                                 out rrpp numeric, out jefe numeric)
language plpgsql stable security definer set search_path = public
as $$
declare
  e  record;
  c  record;
  p  record;
  t  record;
  v_team   uuid;
  v_total  numeric;   -- comisión del team por manilla
  v_pct    numeric;   -- la cuenta vieja por porcentaje
begin
  rrpp := 0; jefe := 0;
  select ev.club_id, ev.precio_manilla, ev.pct_boliche, ev.pct_rrpp, ev.cut_rrpp
    into e from eventos ev where ev.id = p_evento;
  if not found then return; end if;
  select pr.rol, pr.cut_rel into p from profiles pr where pr.id = p_persona;
  -- los admin no cobran comisión (regla de siempre)
  if not found or p.rol = 'admin' then return; end if;
  select cl.usa_relacionadores, cl.usa_teams, cl.comision_manillas into c
    from clubs cl where cl.id = e.club_id;
  if not coalesce(c.usa_relacionadores, true) or not coalesce(c.comision_manillas, true) then return; end if;

  v_total := coalesce(e.precio_manilla, 0) * (1 - coalesce(e.pct_boliche, 0) / 100.0);
  v_pct   := v_total * (coalesce(e.pct_rrpp, 0) / 100.0);

  -- sin teams: el relacionador cobra la comisión entera (o su arreglo propio)
  if not coalesce(c.usa_teams, true) then
    rrpp := coalesce(p.cut_rel, v_total);
    return;
  end if;

  v_team := impl.team_efectivo(p_persona, e.club_id);
  if v_team is not null then
    select tm.jefe_id, tm.rrpp_por_manilla into t from teams tm where tm.id = v_team;
    if t.rrpp_por_manilla is not null then
      -- el jefe fijó su reparto: lo que vende él es todo suyo
      if t.jefe_id = p_persona then
        rrpp := v_total;
      else
        rrpp := least(coalesce(p.cut_rel, t.rrpp_por_manilla), v_total);
        jefe := v_total - rrpp;
      end if;
      return;
    end if;
  end if;

  -- como siempre
  rrpp := coalesce(p.cut_rel, e.cut_rrpp, v_pct);
  jefe := v_pct;
end;
$$;


/* Comisión de UN combo de mesa (multiplicar por combo_qty). Venda quien
   venda, el combo lleva su comisión (regla de siempre del cierre): si lo
   vende un admin o nadie, queda la del combo tal cual. */
create or replace function impl.comision_combo(p_combo uuid, p_persona uuid, p_club text,
                                               out rrpp numeric, out jefe numeric)
language plpgsql stable security definer set search_path = public
as $$
declare
  co record;
  c  record;
  p  record;
  t  record;
  v_team  uuid;
  v_total numeric;
begin
  rrpp := 0; jefe := 0;
  select cb.comision_rrpp, cb.comision_jefe into co from combos cb where cb.id = p_combo;
  if not found then return; end if;
  select cl.usa_relacionadores, cl.usa_teams, cl.comision_combos into c
    from clubs cl where cl.id = p_club;
  if not coalesce(c.usa_relacionadores, true) or not coalesce(c.comision_combos, true) then return; end if;

  v_total := coalesce(co.comision_rrpp, 0) + coalesce(co.comision_jefe, 0);
  select pr.rol into p from profiles pr where pr.id = p_persona;

  if found and p.rol <> 'admin' then
    if not coalesce(c.usa_teams, true) then
      rrpp := v_total;
      return;
    end if;
    v_team := impl.team_efectivo(p_persona, p_club);
    if v_team is not null then
      select tm.jefe_id, tm.rrpp_por_combo into t from teams tm where tm.id = v_team;
      if t.rrpp_por_combo is not null then
        if t.jefe_id = p_persona then
          rrpp := v_total;
        else
          rrpp := least(t.rrpp_por_combo, v_total);
          jefe := v_total - rrpp;
        end if;
        return;
      end if;
    end if;
  end if;

  -- como siempre
  rrpp := coalesce(co.comision_rrpp, 0);
  jefe := coalesce(co.comision_jefe, 0);
end;
$$;

revoke all on function impl.team_efectivo(uuid, text) from public, anon;
revoke all on function impl.comision_manilla(uuid, uuid) from public, anon;
revoke all on function impl.comision_combo(uuid, uuid, text) from public, anon;
-- las vistas corren con los permisos de quien consulta (security_invoker):
-- tienen que poder llamarlas. Solo devuelven montos.
grant usage on schema impl to authenticated;
grant execute on function impl.comision_manilla(uuid, uuid) to authenticated;
grant execute on function impl.comision_combo(uuid, uuid, text) to authenticated;
grant execute on function impl.team_efectivo(uuid, text) to authenticated;
revoke all on function impl.reparto_nuevo(uuid, uuid) from public, anon;
grant execute on function impl.reparto_nuevo(uuid, uuid) to authenticated;


-- ── vistas de estadísticas ─────────────────────────────────────────────
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
 where p.rol in ('rrpp', 'jefe', 'admin');

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
 where p.rol in ('rrpp', 'jefe');


-- ── cierre del boliche ─────────────────────────────────────────────────
-- Sin comisión por manilla (o sin relacionadores) la manilla entera es del
-- boliche; las mesas restan lo que de verdad se paga por sus combos.
create or replace function impl.liquidacion_evento(p_evento uuid)
returns json
language sql
stable
security definer
set search_path = public
as $$
  with ev as (
    select e.precio_manilla, e.pct_boliche, coalesce(e.manillas_externas, 0) as externas, e.club_id,
           coalesce(c.usa_relacionadores, true) and coalesce(c.comision_manillas, true) as con_comision
      from eventos e left join clubs c on c.id = e.club_id
     where e.id = p_evento
  ),
  man as (
    select count(*)::int as usadas
      from entradas
     where evento_id = p_evento and estado = 'usada' and mesa_id is null
  ),
  mes as (
    select coalesce(sum(m.precio), 0)::numeric as bruto,
           coalesce(sum(((impl.comision_combo(m.combo_id, m.vendido_por, ev.club_id)).rrpp
                       + (impl.comision_combo(m.combo_id, m.vendido_por, ev.club_id)).jefe)
                        * coalesce(m.combo_qty, 1)), 0)::numeric as comision
      from mesas m, ev
     where m.evento_id = p_evento and m.estado <> 'disponible'
  ),
  calc as (
    select ev.precio_manilla,
           ev.externas                                   as manillas_externas,
           man.usadas                                    as manillas_usadas,
           greatest(man.usadas - ev.externas, 0)         as manillas_netas,
           case when ev.con_comision then ev.precio_manilla * ev.pct_boliche / 100.0
                else ev.precio_manilla::numeric end      as por_manilla,
           mes.bruto                                     as bruto_mesas,
           mes.comision                                  as comision_mesas
      from ev, man, mes
  )
  select json_build_object(
    'precio_manilla',    precio_manilla,
    'manillas_externas', manillas_externas,
    'manillas_usadas',   manillas_usadas,
    'manillas_netas',    manillas_netas,
    'por_manilla',       por_manilla,
    'total_manillas',    manillas_netas * por_manilla,
    'bruto_mesas',       bruto_mesas,
    'comision_mesas',    comision_mesas,
    'total_mesas',       bruto_mesas - comision_mesas,
    'total_a_pagar',     (manillas_netas * por_manilla) + (bruto_mesas - comision_mesas)
  ) from calc;
$$;


-- ── ranking e histórico ────────────────────────────────────────────────
create or replace function impl.ranking_rrpp(p_club text, p_desde date)
returns table (
  mesas      bigint,
  nombre     text,
  usuario    text,
  anotados   bigint,
  comision   numeric,
  entradas   bigint,
  ingresados bigint
)
language sql
stable
security definer
set search_path = public
as $$
  with evs as (
    select id, precio_manilla, pct_boliche, pct_rrpp from eventos where club_id = p_club and fecha >= p_desde
  ),
  base as (
    select p.id, p.nombre, p.usuario, p.cut_rel
      from profiles p
     where p.rol in ('rrpp', 'jefe')
  ),
  stats as (
    select b.id, b.nombre, b.usuario,
      (select count(*) from registros r where r.rrpp_id = b.id and r.evento_id in (select id from evs)) as anotados,
      (select count(*) from registros r where r.rrpp_id = b.id and r.evento_id in (select id from evs) and r.ingreso_at is not null) as ingresados,
      (select count(*) from entradas x where x.rrpp_id = b.id and x.evento_id in (select id from evs) and x.estado = 'usada' and x.mesa_id is null) as entradas,
      (select count(*) from mesas m where m.vendido_por = b.id and m.evento_id in (select id from evs) and m.estado <> 'disponible') as mesas,
      (
        coalesce((select sum(q.n * case when impl.reparto_nuevo(q.id, b.id)
                                        then (impl.comision_manilla(q.id, b.id)).rrpp
                                        else coalesce(b.cut_rel, q.precio_manilla * (1 - q.pct_boliche / 100.0) * (q.pct_rrpp / 100.0)) end)
            from (select e.id, e.precio_manilla, e.pct_boliche, e.pct_rrpp, count(*) as n
                    from entradas x join evs e on e.id = x.evento_id
                   where x.rrpp_id = b.id and x.estado = 'usada' and x.mesa_id is null
                   group by e.id, e.precio_manilla, e.pct_boliche, e.pct_rrpp) q), 0)
        + coalesce((select sum((impl.comision_combo(m.combo_id, b.id, p_club)).rrpp * coalesce(m.combo_qty, 1))
            from mesas m
           where m.vendido_por = b.id and m.evento_id in (select id from evs)
             and m.estado <> 'disponible' and m.combo_id is not null), 0)
      ) as comision
      from base b
  )
  select s.mesas, s.nombre, s.usuario, s.anotados, s.comision, s.entradas, s.ingresados
    from stats s
   where s.anotados + s.entradas + s.mesas > 0
   order by (s.entradas + s.mesas) desc, s.ingresados desc, s.nombre asc
   limit 50;
$$;

create or replace function impl.historico_eventos(p_club text)
returns table (
  id                uuid,
  fecha             date,
  mesas             bigint,
  estado            text,
  nombre            text,
  lista_in          bigint,
  utilidad          numeric,
  bruto_mesas       numeric,
  lista_total       bigint,
  bruto_entradas    numeric,
  entradas_usadas   bigint,
  entradas_vendidas bigint
)
language sql
stable
security definer
set search_path = public
as $$
  select e.id,
         e.fecha,
         (select count(*) from mesas m where m.evento_id = e.id and m.estado <> 'disponible') as mesas,
         e.estado,
         e.nombre,
         (select count(*) from registros r where r.evento_id = e.id and r.ingreso_at is not null) as lista_in,
         (
           coalesce((select sum(x.precio) from entradas x where x.evento_id = e.id and x.estado = 'usada' and x.mesa_id is null), 0)
           -- lo que cobra quien vende y su jefe, persona por persona
           - coalesce((select sum(q.n * case when impl.reparto_nuevo(e.id, q.rrpp_id)
                    then (impl.comision_manilla(e.id, q.rrpp_id)).rrpp + (impl.comision_manilla(e.id, q.rrpp_id)).jefe
                    -- la cuenta vieja del histórico: cut de la persona o porcentaje, más la parte del jefe
                    else coalesce(q.cut_rel, e.precio_manilla * (1 - e.pct_boliche / 100.0) * (e.pct_rrpp / 100.0))
                       + e.precio_manilla * (1 - e.pct_boliche / 100.0) * (1 - e.pct_rrpp / 100.0) end)
                from (select x.rrpp_id, p.cut_rel, count(*) as n
                        from entradas x join profiles p on p.id = x.rrpp_id
                       where x.evento_id = e.id and x.estado = 'usada' and x.mesa_id is null
                       group by x.rrpp_id, p.cut_rel) q), 0)
           + coalesce((select sum(m.precio
                 - ((impl.comision_combo(m.combo_id, m.vendido_por, e.club_id)).rrpp
                  + (impl.comision_combo(m.combo_id, m.vendido_por, e.club_id)).jefe) * coalesce(m.combo_qty, 1))
               from mesas m
              where m.evento_id = e.id and m.estado <> 'disponible'), 0)
           -- las manillas externas no entran al reparto, como en el cierre
           - coalesce(e.manillas_externas, 0) * e.precio_manilla * (e.pct_boliche / 100.0)
         ) as utilidad,
         coalesce((select sum(m.precio) from mesas m where m.evento_id = e.id and m.estado <> 'disponible'), 0) as bruto_mesas,
         (select count(*) from registros r where r.evento_id = e.id) as lista_total,
         coalesce((select sum(x.precio) from entradas x where x.evento_id = e.id and x.estado = 'usada' and x.mesa_id is null), 0) as bruto_entradas,
         (select count(*) from entradas x where x.evento_id = e.id and x.estado = 'usada' and x.mesa_id is null) as entradas_usadas,
         (select count(*) from entradas x where x.evento_id = e.id and x.estado <> 'anulada' and x.mesa_id is null) as entradas_vendidas
    from eventos e
   where e.club_id = p_club
   order by e.fecha desc;
$$;


-- ── rendiciones: la comisión por manilla de cada uno ───────────────────
create or replace function rendiciones_evento(p_evento uuid)
returns table (
  rrpp_id uuid, nombre text, team_id uuid, team text,
  vendidas int, ingresaron int, cobrado numeric, comision_unit numeric,
  comision numeric, a_pagar numeric, pagado boolean, marcado_por text,
  marcado_at timestamptz, comprobantes text[], rendido numeric)
language plpgsql stable security definer set search_path = public
as $$
#variable_conflict use_column
declare
  v_club text := impl.club_de('evento', p_evento);
  v_rol  text;
  v_team uuid;
begin
  v_rol := impl.exigir(v_club, '{admin,jefe,rrpp}'::text[]);
  select t.team_id into v_team from impl.teams_efectivos(v_club) t where t.user_id = auth.uid();

  return query
  with tm as (select * from impl.teams_efectivos(v_club)),
  ent as (
    select x.rrpp_id,
           count(*)::int                                         as vendidas,
           (count(*) filter (where x.estado = 'usada'))::int     as ingresaron,
           coalesce(sum(x.precio) filter (where x.estado = 'usada'), 0)::numeric as cobrado
      from entradas x
     where x.evento_id = p_evento and x.mesa_id is null and x.estado <> 'anulada'
       and x.rrpp_id is not null
     group by x.rrpp_id),
  pg as (
    select g.rrpp_id,
           array_agg(g.comprobante_url order by g.created_at desc)
             filter (where g.comprobante_url is not null)        as comps,
           sum(g.monto)::numeric                                  as rendido
      from pagos g where g.evento_id = p_evento group by g.rrpp_id)
  select ent.rrpp_id, coalesce(tm.nombre, pr.nombre), tm.team_id, coalesce(tm.team, 'Sin team'),
         ent.vendidas, ent.ingresaron, ent.cobrado,
         cu.c, cu.c * ent.ingresaron, greatest(ent.cobrado - cu.c * ent.ingresaron, 0),
         coalesce(r.pagado, false), mp.nombre, r.marcado_at,
         coalesce(pg.comps, '{}'::text[]), coalesce(pg.rendido, 0)
    from ent
    join profiles pr on pr.id = ent.rrpp_id
    left join tm on tm.user_id = ent.rrpp_id
    left join rendicion_rrpp r on r.evento_id = p_evento and r.rrpp_id = ent.rrpp_id
    left join profiles mp on mp.id = r.marcado_por
    left join pg on pg.rrpp_id = ent.rrpp_id
    cross join lateral (
      select round((impl.comision_manilla(p_evento, ent.rrpp_id)).rrpp, 2) as c
    ) cu
   where v_rol in ('admin', 'servicio')
      or ent.rrpp_id = auth.uid()
      or (v_rol = 'jefe' and v_team is not null and tm.team_id = v_team)
   order by coalesce(tm.team, 'Sin team'), coalesce(tm.nombre, pr.nombre);
end;
$$;


-- ── para las pantallas ─────────────────────────────────────────────────
/* Comisión por manilla y por combo de quien llama en un evento (lo que le
   muestran la app y la web en Pagos). */
create or replace function mi_comision(p_evento uuid)
returns json language plpgsql stable security definer set search_path = public
as $$
declare v_club text := impl.club_de('evento', p_evento);
begin
  perform impl.exigir(v_club, '{*}'::text[]);
  return json_build_object('por_manilla', (impl.comision_manilla(p_evento, auth.uid())).rrpp);
end;
$$;

/* El jefe fija cuánto le da a cada relacionador de su team, por manilla y
   por combo (null = la regla de siempre). También lo puede hacer el admin
   de un boliche donde opera el team. */
create or replace function fijar_reparto_team(p_team uuid, p_por_manilla numeric, p_por_combo numeric)
returns void language plpgsql security definer set search_path = public
as $$
declare
  t record;
  v_ok boolean := false;
  c text;
begin
  select tm.id, tm.jefe_id, tm.clubs into t from teams tm where tm.id = p_team;
  if not found then raise exception 'Team inexistente.'; end if;
  if coalesce(p_por_manilla, 0) < 0 or coalesce(p_por_combo, 0) < 0 then
    raise exception 'El monto no puede ser negativo.';
  end if;
  if es_servicio() or t.jefe_id = auth.uid() then
    v_ok := true;
  else
    foreach c in array coalesce(t.clubs, '{}'::text[]) loop
      if rol_en_club(c) = 'admin' then v_ok := true; end if;
    end loop;
  end if;
  if not v_ok then raise exception 'No autorizado.' using errcode = '42501'; end if;
  update teams set rrpp_por_manilla = p_por_manilla, rrpp_por_combo = p_por_combo where id = p_team;
end;
$$;

revoke all on function mi_comision(uuid) from public, anon;
grant execute on function mi_comision(uuid) to authenticated;
revoke all on function fijar_reparto_team(uuid, numeric, numeric) from public, anon;
grant execute on function fijar_reparto_team(uuid, numeric, numeric) to authenticated;

notify pgrst, 'reload schema';
