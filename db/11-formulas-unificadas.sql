-- FÓRMULAS UNIFICADAS (aprobado 2026-08-22) · APLICAR DESPUÉS DEL CORTE.
-- Antes del corte rompería la verificación de paridad (comparar.mjs), que
-- exige reproducir los números del original, inconsistencias incluidas.
--
-- Criterio de unificación: gana la fórmula de LA PLATA REAL (lo que se
-- paga / lo que queda al boliche = liquidación y cierre).
--
-- (1) ranking_rrpp pagaba la comisión de mesas ×1 por mesa ignorando
--     combo_qty, mientras la liquidación (lo que se paga de verdad) y
--     v_stats_mesas usan ×qty. Medido: el ranking subreportaba 150 Bs en
--     Like a Diamond y 120 Bs en Aniversario. → ×qty.
-- (2) historico_eventos.utilidad no restaba las manillas EXTERNAS que el
--     cierre sí descuenta del reparto. Medido: HOLIDAY PARTY aparecía
--     805 Bs más rentable que su cierre (23 externas × 70 Bs × 50%).
--     → se resta externas × precio × pct_boliche, como el cierre.

create or replace function ranking_rrpp(p_club text, p_desde date)
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
    select id, precio_manilla, pct_boliche, pct_rrpp
      from eventos where club_id = p_club and fecha >= p_desde
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
        coalesce((select sum(coalesce(b.cut_rel,
              e.precio_manilla * (1 - e.pct_boliche / 100.0) * (e.pct_rrpp / 100.0)))
            from entradas x join evs e on e.id = x.evento_id
           where x.rrpp_id = b.id and x.estado = 'usada' and x.mesa_id is null), 0)
        -- UNIFICADO: comisión de mesas × combo_qty, como se paga de verdad
        + coalesce((select sum(coalesce(c.comision_rrpp, 0) * coalesce(m.combo_qty, 1))
            from mesas m left join combos c on c.id = m.combo_id
           where m.vendido_por = b.id and m.evento_id in (select id from evs) and m.estado <> 'disponible'), 0)
      ) as comision
      from base b
  )
  select s.mesas, s.nombre, s.usuario, s.anotados, s.comision, s.entradas, s.ingresados
    from stats s
   where s.anotados + s.entradas + s.mesas > 0
   order by (s.entradas + s.mesas) desc, s.ingresados desc, s.nombre asc
   limit 50;
$$;

create or replace function historico_eventos(p_club text)
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
           - coalesce((select sum(coalesce(p.cut_rel,
                 e.precio_manilla * (1 - e.pct_boliche / 100.0) * (e.pct_rrpp / 100.0)))
               from entradas x join profiles p on p.id = x.rrpp_id
              where x.evento_id = e.id and x.estado = 'usada' and x.mesa_id is null), 0)
           - coalesce((select count(*) from entradas x where x.evento_id = e.id and x.estado = 'usada' and x.mesa_id is null), 0)
             * e.precio_manilla * (1 - e.pct_boliche / 100.0) * (1 - e.pct_rrpp / 100.0)
           + coalesce((select sum(m.precio
                 - (coalesce(c.comision_rrpp, 0) + coalesce(c.comision_jefe, 0)) * coalesce(m.combo_qty, 1))
               from mesas m left join combos c on c.id = m.combo_id
              where m.evento_id = e.id and m.estado <> 'disponible'), 0)
           -- UNIFICADO: las manillas externas no entran al reparto, como en el cierre
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
