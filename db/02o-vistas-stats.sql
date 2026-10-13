-- v_stats_rrpp y v_stats_mesas · las DOS VISTAS que la app lee directo
-- (screenStats, sheetHistTeam, sheetComisiones, copyDesgloseTeam). No son
-- RPCs y por eso no estaban en el inventario de 77 — se detectaron al armar
-- la matriz de accesos directos para RLS. Al ser vistas son 100% legibles
-- por REST: TODA la salida del origen se capturó (2.410 + 2.370 filas) y la
-- reconstrucción se ajustó hasta calzar CADA fila y CADA campo (0 diffs).
--
-- Reglas derivadas del ajuste (todas con contraejemplo que las probó):
-- · Universo rrpp: profiles rol in (rrpp,jefe,admin) × TODOS los eventos
--   (cross join; incluye inactivos y archivados .borrado). Mesas: solo
--   rrpp/jefe (los 4 admin están en la de rrpp — socio1 sin actividad
--   incluido — y no en la de mesas).
-- · team_id: el EFECTIVO del club del evento (misma regla que
--   teams_efectivos: club_membership manda; el team base solo si opera en
--   ese club vía teams.clubs; admins no pasan por ese portón).
-- · entradas: solo mesa_id IS NULL (las manillas de mesa no cuentan acá);
--   vendidas = no anuladas; bruto = sum(precio) de no anuladas.
-- · comision_rrpp = 0 si el rol BASE es admin (iPad de Queirolo: efectivo
--   jefe y aun así 0). Si no: cut × (evento CERRADO ? usadas : vendidas).
--   El cut: cut_rel de la persona > cut_rrpp del evento > fórmula
--   precio×(1−pct_boliche/100)×(pct_rrpp/100). Probado con Nicolas Pereya
--   (cut_rel 25 × 8 vendidas = 200 en el evento activo).
-- · comision_jefe = fórmula porcentual SIN overrides × usadas SIEMPRE
--   (17.5 en el evento de precio 70 aunque cut_rrpp=15; y 0 en el evento
--   activo donde nadie ingresó). SUPUESTO el caso límite: con el evento
--   activo y gente ya ingresada, se asume que también corre por usadas.
-- · mesas: vendido_por + estado<>'disponible'; comisiones del combo de la
--   mesa × combo_qty (Natalia Aguirre: 240 sería ×1, la real da 360 = ×qty
--   — OJO: ranking_rrpp usa ×1; inconsistencia del ORIGINAL, replicada).
--   comision_jefe_mesas ×qty es SUPUESTO (los 12 combos tienen 0).

create or replace view v_stats_rrpp as
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
       case when p.rol = 'admin' then 0 else
         (case when e.estado = 'cerrado'
               then (select count(*) from entradas x
                      where x.evento_id = e.id and x.rrpp_id = p.id
                        and x.estado = 'usada' and x.mesa_id is null)
               else (select count(*) from entradas x
                      where x.evento_id = e.id and x.rrpp_id = p.id
                        and x.estado <> 'anulada' and x.mesa_id is null) end)
         * coalesce(p.cut_rel, e.cut_rrpp,
                    e.precio_manilla * (1 - e.pct_boliche / 100.0) * (e.pct_rrpp / 100.0))
       end as comision_rrpp,
       case when p.rol = 'admin' then 0 else
         (select count(*) from entradas x
           where x.evento_id = e.id and x.rrpp_id = p.id
             and x.estado = 'usada' and x.mesa_id is null)
         * (e.precio_manilla * (1 - e.pct_boliche / 100.0) * (e.pct_rrpp / 100.0))
       end as comision_jefe
  from eventos e
 cross join profiles p
  left join club_membership cm on cm.user_id = p.id and cm.club_id = e.club_id
  left join teams tb on tb.id = p.team_id
 where p.rol in ('rrpp', 'jefe', 'admin');

create or replace view v_stats_mesas as
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
       (select coalesce(sum(co.comision_rrpp * mm.combo_qty), 0)
          from mesas mm join combos co on co.id = mm.combo_id
         where mm.evento_id = e.id and mm.vendido_por = p.id
           and mm.estado <> 'disponible') as comision_rrpp_mesas,
       (select coalesce(sum(co.comision_jefe * mm.combo_qty), 0)
          from mesas mm join combos co on co.id = mm.combo_id
         where mm.evento_id = e.id and mm.vendido_por = p.id
           and mm.estado <> 'disponible') as comision_jefe_mesas
  from eventos e
 cross join profiles p
  left join club_membership cm on cm.user_id = p.id and cm.club_id = e.club_id
  left join teams tb on tb.id = p.team_id
 where p.rol in ('rrpp', 'jefe');
