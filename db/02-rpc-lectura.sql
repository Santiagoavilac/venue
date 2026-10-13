-- RPCs de lectura · reconstruidas para dar exactamente lo mismo que las
-- originales. Cada una se verificó ejecutando la real y la reconstruida
-- sobre los mismos datos, comparando campo por campo.
--
-- ETAPA 1: paridad. Nada de mejoras acá — van en un archivo aparte, después.


/* liquidacion_evento(p_evento) -> json
 *
 * Lo que se le paga al boliche por una noche.
 *
 * Deducida ejecutando la real sobre 3 eventos y verificando cada relación
 * interna (todas dieron true en los 3):
 *   manillas_netas = manillas_usadas − manillas_externas
 *   por_manilla    = precio_manilla × pct_boliche / 100
 *   total_manillas = manillas_netas × por_manilla
 *   total_mesas    = bruto_mesas − comision_mesas
 *   total_a_pagar  = total_manillas + total_mesas
 *
 * manillas_usadas = entradas 'usada' SIN mesa_id (verificado: 290 en HOLIDAY
 * PARTY, idéntico a la RPC real). Las de mesa ya están dentro del precio de
 * la mesa, por eso no se cuentan aparte.
 *
 * Mesas: las que no están 'disponible'. La comisión es la fija del combo por
 * cantidad, venda quien venda (verificado: 14740 bruto / 2450 comisión).
 */
create or replace function liquidacion_evento(p_evento uuid)
returns json
language sql
stable
security definer
set search_path = public
as $$
  with ev as (
    select precio_manilla, pct_boliche, coalesce(manillas_externas, 0) as externas
      from eventos where id = p_evento
  ),
  man as (
    select count(*)::int as usadas
      from entradas
     where evento_id = p_evento and estado = 'usada' and mesa_id is null
  ),
  mes as (
    select coalesce(sum(m.precio), 0)::numeric as bruto,
           coalesce(sum((coalesce(c.comision_rrpp, 0) + coalesce(c.comision_jefe, 0))
                        * coalesce(m.combo_qty, 1)), 0)::numeric as comision
      from mesas m
      left join combos c on c.id = m.combo_id
     where m.evento_id = p_evento and m.estado <> 'disponible'
  ),
  calc as (
    select ev.precio_manilla,
           ev.externas                                   as manillas_externas,
           man.usadas                                    as manillas_usadas,
           greatest(man.usadas - ev.externas, 0)         as manillas_netas,
           (ev.precio_manilla * ev.pct_boliche / 100.0)  as por_manilla,
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


/* resumen_evento(p_evento) -> json
 *
 * Los contadores de la pantalla de inicio.
 *
 * Los tres contadores de entrada NO son la misma cuenta, y la diferencia se
 * dedujo comparando contra la real en Velvet Noir (332 / 415 / 368):
 *   entradas  = no anuladas Y sin mesa   -> las prepagadas sueltas
 *   qr_total  = TODAS, anuladas incluidas -> cuántos QR se emitieron
 *   qr_usados = estado 'usada', con mesa incluida
 *
 * Una primera versión contaba las tres igual y daba distinto en los 10
 * eventos; estos filtros dan idéntico.
 */
create or replace function resumen_evento(p_evento uuid)
returns json
language sql
stable
security definer
set search_path = public
as $$
  select json_build_object(
    'anotados',   (select count(*)::int from registros where evento_id = p_evento),
    'ingresaron', (select count(*)::int from registros where evento_id = p_evento and ingreso_at is not null),
    'entradas',   (select count(*)::int from entradas  where evento_id = p_evento and estado <> 'anulada' and mesa_id is null),
    'qr_total',   (select count(*)::int from entradas  where evento_id = p_evento),
    'qr_usados',  (select count(*)::int from entradas  where evento_id = p_evento and estado = 'usada'),
    'mesas',      (select count(*)::int from mesas     where evento_id = p_evento and estado <> 'disponible')
  );
$$;
