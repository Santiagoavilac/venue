-- RPCs de REPORTES · historico_eventos, ranking_rrpp, reporte_fases,
-- reporte_filtro. Reconstruidas para dar exactamente lo mismo que las
-- originales.
--
-- ETAPA 1: paridad. Nada de mejoras acá.
--
-- MÉTODO: se capturaron las salidas reales (2026-08-19, .scratch/capturas/)
-- con parámetros reales, y cada fórmula se ajustó offline contra el respaldo
-- completo hasta reproducirlas: historico_eventos 8/8 eventos cerrados
-- exactos en TODOS los campos; ranking_rrpp 200/200 filas exactas en los 4
-- juegos (bowie/burtown × todo/mes). Falta la comparación por ejecución en
-- el destino (arnés db/paridad), que es la confirmación final.


/* historico_eventos(p_club) -> filas por evento, fecha desc
 *
 * TODOS los eventos del club (incluye 'proximo': verificado, Aniversario
 * aparece), orden fecha desc.
 *
 * Campos (verificados campo por campo en los 8 cerrados):
 *   lista_total / lista_in  = registros del evento / con ingreso_at
 *   mesas                   = mesas con estado <> 'disponible'
 *   bruto_mesas             = sum(precio) de esas mesas
 *   entradas_vendidas       = entradas SIN mesa y NO anuladas
 *   entradas_usadas         = entradas SIN mesa en estado 'usada'
 *   bruto_entradas          = sum(precio) de las usadas sin mesa
 *   utilidad                = bruto_entradas
 *                             − Σ por usada: coalesce(cut_rel del vendedor,
 *                                 precio_manilla×(1−pct_boliche/100)×(pct_rrpp/100))
 *                             − usadas × precio_manilla×(1−pct_boliche/100)×(1−pct_rrpp/100)
 *                             + Σ mesas (precio − (comision_rrpp+comision_jefe)×combo_qty)
 *
 * HALLAZGOS que la derivación dejó al descubierto:
 *   - utilidad NO resta manillas_externas (HOLIDAY tiene 23 y el número
 *     real solo cierra sin restarlas) — DISTINTO de liquidacion_evento,
 *     que sí las resta. Inconsistencia del original, replicada adrede.
 *   - utilidad usa el cut POR PERSONA (cut_rel) cuando existe: el único
 *     perfil con cut_rel (25) explica exactamente los -82.5/-220 que
 *     faltaban en 3 eventos.
 *   - utilidad IGNORA eventos.cut_rrpp (el monto fijo de 15): usa la
 *     fórmula porcentual vieja. Con manilla a 60 ambas dan 15 y son
 *     indistinguibles; con manilla a 70 la real da 17.5, no 15.
 */
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


/* ranking_rrpp(p_club, p_desde) -> top 50
 *
 * Universo: perfiles con rol BASE rrpp o jefe (los 2 admin quedan afuera
 * aunque tengan ventas — verificado: aqueirolo e IpadQueirolo no aparecen
 * en la respuesta real pese a tener actividad). Eventos del club con
 * fecha >= p_desde. LIMIT 50 (las cuatro respuestas reales traen 50 justas).
 *
 * Campos verificados 200/200 filas (4 juegos de parámetros):
 *   anotados / ingresados = registros por rrpp_id (todos / con ingreso)
 *   entradas              = entradas USADAS sin mesa
 *   mesas                 = mesas <> disponible con vendido_por = la persona
 *   comision              = Σ usadas × coalesce(cut_rel,
 *                             precio_manilla×(1−pct_bol/100)×(pct_rrpp/100))
 *                           + Σ mesas × comision_rrpp del combo (×1, SIN
 *                             combo_qty; cortesías y secundarias de grupo
 *                             INCLUIDAS)
 *
 * HALLAZGOS:
 *   - La comisión de mesas acá es POR MESA (comision_rrpp × 1): una mesa
 *     con combo_qty=2 paga 150, no 300. DISTINTO de liquidacion/historico
 *     (comisión × qty) y del criterio del Reporte del cliente. Se descubrió
 *     porque una mesa real con qty=2 pagaba 150 en el ranking real; con
 *     esta regla las 200 filas cierran exactas. Inconsistencia del
 *     original, replicada adrede.
 *   - Igual que historico: fórmula porcentual por evento + cut_rel por
 *     persona; ignora eventos.cut_rrpp y el escalón cut_umbral/sobre_umbral.
 *
 * ORDEN: (entradas+mesas) desc y después ingresados desc reproduce 170/200
 * posiciones; bowie.todo da 50/50. El resto difiere SOLO dentro de empates
 * (ver paridad-reportes.md): el desempate final del original no se pudo
 * determinar con los datos disponibles. Se usa nombre asc como desempate
 * estable — CASO LÍMITE DOCUMENTADO, igual que los homónimos de rosters.
 */
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
        + coalesce((select sum(coalesce(c.comision_rrpp, 0))
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


/* reporte_fases(p_evento) -> jsonb {usa_fases, bruto_total, fases[], sin_fase}
 *
 * Verificado contra las respuestas reales de Aniversario Bowie (3 fases) y
 * Freaky Show (sin fases), cuadrando cada número con el respaldo:
 *   - por fase: vendidas (sin mesa, no anuladas — en los datos no había
 *     anuladas con fase, así que el filtro de anuladas replica el criterio
 *     de sin_fase, donde SÍ se verificó: 141 = 142 − 1 anulada),
 *     ingresaron (usadas), bruto = sum(precio), conversion =
 *     round(ing/vend×100) entero, pct_bruto = round(bruto/total×100, 1) con
 *     UN decimal, agotada = cupo alcanzado.
 *   - sin_fase: mismas cuentas sobre las entradas SIN fase y SIN mesa
 *     (las manillas de mesa no cuentan: Aniversario tiene 34 sin fase pero
 *     todas de mesa, y la real da sin_fase = null). null si no hay ninguna.
 *   - bruto_total = fases + sin_fase.
 */
create or replace function reporte_fases(p_evento uuid)
returns jsonb
language sql
stable
security definer
set search_path = public
as $$
  with ent as (
    select fase_id, estado, precio
      from entradas
     where evento_id = p_evento and mesa_id is null
  ),
  porfase as (
    select f.id, f.nombre, f.precio, f.cupo, f.orden,
           count(e.*) filter (where e.estado <> 'anulada') as vendidas,
           count(e.*) filter (where e.estado = 'usada') as ingresaron,
           coalesce(sum(e.precio) filter (where e.estado <> 'anulada'), 0) as bruto
      from evento_fase f
      left join ent e on e.fase_id = f.id
     where f.evento_id = p_evento
     group by f.id, f.nombre, f.precio, f.cupo, f.orden
  ),
  sinfase as (
    select count(*) filter (where estado <> 'anulada') as vendidas,
           count(*) filter (where estado = 'usada') as ingresaron,
           coalesce(sum(precio) filter (where estado <> 'anulada'), 0) as bruto
      from ent where fase_id is null
  ),
  total as (
    select coalesce((select sum(bruto) from porfase), 0)
         + coalesce((select bruto from sinfase where vendidas > 0), 0) as bruto_total
  )
  select jsonb_build_object(
    'usa_fases', (select venta_por_fases from eventos where id = p_evento),
    'bruto_total', (select bruto_total from total),
    'fases', coalesce((
      select jsonb_agg(jsonb_build_object(
        'cupo', pf.cupo,
        'bruto', pf.bruto,
        'nombre', pf.nombre,
        'precio', pf.precio,
        'agotada', (pf.cupo is not null and pf.vendidas >= pf.cupo),
        'vendidas', pf.vendidas,
        'pct_bruto', case when (select bruto_total from total) > 0
                          then round(pf.bruto * 100.0 / (select bruto_total from total), 1) end,
        'conversion', case when pf.vendidas > 0
                           then round(pf.ingresaron * 100.0 / pf.vendidas) else 0 end,
        'ingresaron', pf.ingresaron
      ) order by pf.orden)
      from porfase pf), '[]'::jsonb),
    'sin_fase', (
      select case when sf.vendidas > 0 then jsonb_build_object(
        'bruto', sf.bruto,
        'vendidas', sf.vendidas,
        'conversion', case when sf.vendidas > 0 then round(sf.ingresaron * 100.0 / sf.vendidas) else 0 end,
        'ingresaron', sf.ingresaron
      ) end from sinfase sf)
  );
$$;


/* reporte_filtro(p_evento) -> filas {rrpp, team, usuario, cantidad, personas[]}
 *
 * Marcas de "no pasó el filtro" de las dos fuentes (registros.filtro_at y
 * entradas.filtro_at), agrupadas por el rrpp que trajo/vendió.
 *
 * Verificado contra 4 eventos reales (1+11+2+3 filas): cantidades y
 * personas exactas.
 *
 * team = el team BASE del perfil (profiles.team_id -> teams.nombre), NO el
 * efectivo del club: verificado con 2 casos donde difieren (ariasm da
 * 'Team MA' — su base — aunque su team efectivo en bowie es Team S).
 *
 * personas[]: orden alfabético del nombre (verificado en filas de 4 y 5
 * personas, insensible a mayúsculas).
 *
 * Orden de filas: cantidad desc (verificado). El orden ENTRE empatadas del
 * original no sigue ninguna clave visible (parece orden físico del union);
 * se usa max(filtro_at) asc como desempate estable — CASO LÍMITE, puede
 * diferir del original solo entre filas con la misma cantidad.
 */
create or replace function reporte_filtro(p_evento uuid)
returns table (
  rrpp     text,
  team     text,
  usuario  text,
  cantidad bigint,
  personas text[]
)
language sql
stable
security definer
set search_path = public
as $$
  with marcas as (
    select r.rrpp_id, r.nombre as persona, r.filtro_at
      from registros r where r.evento_id = p_evento and r.filtro_at is not null
    union all
    select e.rrpp_id, e.cliente as persona, e.filtro_at
      from entradas e where e.evento_id = p_evento and e.filtro_at is not null
  )
  select p.nombre as rrpp,
         t.nombre as team,
         p.usuario,
         count(*) as cantidad,
         array_agg(m.persona order by lower(m.persona)) as personas
    from marcas m
    join profiles p on p.id = m.rrpp_id
    left join teams t on t.id = p.team_id
   group by p.id, p.nombre, p.usuario, t.nombre
   order by count(*) desc, max(m.filtro_at) asc;
$$;
