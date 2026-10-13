-- RPCs de busqueda y avisos · reconstruidas para dar exactamente lo mismo
-- que las originales.
--
-- ETAPA 1: paridad. Nada de mejoras aca.
--
-- ESTADO DE ESTE ARCHIVO: escrito y corregido, TODAVIA NO APLICADO al
-- destino ni comparado por ejecucion contra el origen. La version anterior
-- ni siquiera se podia aplicar: referenciaba dos columnas inexistentes
-- (ingreso_sin_tope.entrada_id y fases.lista_tipo_id) y su regla de
-- `alcance` en avisos_admin quedo refutada con datos (daba 45 contra el
-- 149 real registrado). Detalle de cada correccion en su funcion.


/* tabla auxiliar: lecturas de avisos ------------------------------------
 * NO aparece en el respaldo de 19 tablas (01-tablas.sql) ni en el destino.
 * `marcar_aviso_visto` (RPC de escritura, fuera de este grupo) necesita
 * guardar quien vio cada aviso, y aviso_lectores / avisos_pendientes /
 * avisos_admin leen de ahi.
 *
 * Forma deducida de la salida real de aviso_lectores: [{nombre, visto_at}]
 * ordenado por visto_at DESC. Si la tabla real tiene otro nombre o
 * columnas extra, ajustar — NO VERIFICADA contra el esquema real.
 *
 * DATOS: el respaldo no incluye esta tabla (no es legible por REST con
 * ningun nombre probado). Las 45 lecturas del aviso real se pueden
 * reconstruir desde la salida de aviso_lectores(origen) — con la salvedad
 * de que mapear nombre->user_id es ambiguo si hay homonimos. Pendiente en
 * el arnes (db/paridad): capturar esa salida y generar el import.
 */
create table if not exists aviso_visto (
  aviso_id   uuid not null references avisos(id) on delete cascade,
  user_id    uuid not null references profiles(id),
  visto_at   timestamptz not null default now(),
  primary key (aviso_id, user_id)
);


/* buscar_registros(p_evento uuid, p_q text) -> array
 *
 * Busca clientes por nombre (SOLO nombre, no por rrpp: verificado que
 * buscar "Espinoza" o "Limon" — que solo aparecen como rrpp, nunca como
 * nombre de cliente — da []). Junta dos fuentes:
 *   - registros (listas): tipo = 'lista'
 *   - entradas (manillas/prepagadas): tipo = 'entrada'
 *
 * Coincidencia parcial, insensible a mayusculas Y a acentos (verificado:
 * "MAR"/"mar" identicos; "jose"/"josé" identicos, matcheando "José María
 * Mealla"). Se implementa con unaccent(lower(..)) ilike.
 *
 * Orden observado en el origen (2026-08-20, caso con 10+10 filas):
 *   - todos los de tipo 'lista' primero, despues los de tipo 'entrada'
 *   - lista: agrupados POR LISTA (uuid del lista_tipo, descendente en el
 *     caso observado) y created_at asc adentro
 *   - entrada: las de mesa primero (created_at asc entre ellas); las
 *     prepagadas en un orden que NO sigue created_at, nombre, code, id ni
 *     used_at -> orden fisico del original, NO ES CONTRATO (la spec
 *     normaliza dentro de cada bloque). La nota anterior "created_at asc"
 *     venia de un caso chico donde coincidia.
 *
 * p_q='zzzzz' -> [] (verificado).
 *
 * CORRECCIONES sobre la version anterior (no aplicada), FIJADAS con
 * capturas reales del origen (2026-08-19, .scratch/capturas/):
 *
 * 1) sin_tope: la version anterior hacia exists(... st.entrada_id = e.id),
 *    pero ingreso_sin_tope NO tiene columna entrada_id — su PK real es
 *    (user_id, club_id). La regla es POR VENDEDOR: sin_tope = el rrpp de
 *    la entrada esta en ingreso_sin_tope para el club del evento.
 *    CONFIRMADO por ejecucion: una entrada vendida por aqueirolo devuelve
 *    sin_tope=true en la RPC real; una de otro vendedor, false.
 *
 * 2) lista: la version anterior consultaba fases.lista_tipo_id, columna
 *    que no existe. Lo que devuelve el original, capturado por ejecucion:
 *      - manilla DE MESA -> 'Mesa ' || etiqueta de la mesa ("Mesa B2")
 *      - entrada CON FASE -> 'Prepagada' (la fase NO cambia el campo)
 *      - prepagada comun -> 'Prepagada'
 *    El prefijo es "Mesa " literal aunque la mesa sea un lounge (el caso
 *    capturado apunta a un lounge y dice "Mesa A3").
 *
 * 3) forma: el original devuelve setof jsonb, no una tabla — se ve en que
 *    las filas de tipo 'lista' NO traen las claves code/estado (undefined
 *    en el JSON real, no null) y en el orden de claves canonico de jsonb.
 *    Para el cliente da igual (undefined y null se comportan igual), pero
 *    la paridad es exacta: se construye el jsonb por rama.
 */
drop function if exists buscar_registros(uuid, text);  -- cambio de tipo de retorno (table -> setof jsonb)
create or replace function buscar_registros(p_evento uuid, p_q text)
returns setof jsonb
language sql
stable
security definer
set search_path = public
as $$
  with q as (
    select unaccent(lower(p_q)) as needle
  ),
  de_lista as (
    select jsonb_build_object(
             'id', r.id,
             'rrpp', p.nombre,
             'tipo', 'lista',
             'lista', lt.nombre,
             'nombre', r.nombre,
             'sin_tope', false,
             'filtro_at', r.filtro_at,
             'ingreso_at', r.ingreso_at
           ) as fila,
           false as es_entrada,
           r.lista_tipo_id as grupo,
           null::uuid as grupo2,
           r.created_at as orden_at
    from registros r
    join lista_tipos lt on lt.id = r.lista_tipo_id
    join profiles p on p.id = r.rrpp_id
    cross join q
    where r.evento_id = p_evento
      and unaccent(lower(r.nombre)) ilike '%' || q.needle || '%'
  ),
  de_entrada as (
    select jsonb_build_object(
             'id', e.id,
             'code', e.code,
             'rrpp', p.nombre,
             'tipo', 'entrada',
             'lista', case when e.mesa_id is not null then 'Mesa ' || ms.etiqueta
                           else 'Prepagada' end,
             'estado', e.estado,
             'nombre', e.cliente,
             'sin_tope', exists (
               select 1 from ingreso_sin_tope st
                where st.user_id = e.rrpp_id and st.club_id = ev.club_id
             ),
             'filtro_at', e.filtro_at,
             'ingreso_at', e.used_at
           ) as fila,
           true as es_entrada,
           null::uuid as grupo,
           e.mesa_id as grupo2,
           e.created_at as orden_at
    from entradas e
    join eventos ev on ev.id = e.evento_id
    join profiles p on p.id = e.rrpp_id
    left join mesas ms on ms.id = e.mesa_id
    cross join q
    where e.evento_id = p_evento
      and unaccent(lower(e.cliente)) ilike '%' || q.needle || '%'
  )
  select fila
    from (
      select * from de_lista
      union all
      select * from de_entrada
    ) u
   order by es_entrada,          -- lista primero, entrada despues (contrato)
            grupo desc,          -- lista: agrupado por lista_tipo (observado desc)
            (grupo2 is null),    -- entrada: las de mesa primero
            orden_at asc;        -- created_at asc dentro de cada grupo
$$;


/* Compatibilidad persona<->aviso · regla compartida ----------------------
 *
 * VERIFICADA CON DATOS (offline, respaldo completo + fixture real):
 * el aviso real (club bowie, destino rrpp) tiene alcance = 149 segun la
 * RPC original. Candidatos probados sobre el respaldo (248 perfiles, 96
 * memberships):
 *   - join club_membership & cm.rol='rrpp' (version anterior)  ->  45  NO
 *   - rol base 'rrpp' & clubs∋bowie                            -> 145  NO
 *   - rol EFECTIVO 'rrpp' & activo & no eliminado & clubs∋bowie -> 149 SI
 * Rol efectivo = coalesce(club_membership.rol del club, rol base) — la
 * misma regla ya verificada en la familia de rosters (02a).
 *
 * AMBIGUO (mismos 149 en los datos actuales, elegida la primera):
 *   - clubs∋p_club  vs  "opera en el club" al estilo telefonos_equipo
 *     (admin siempre + clubs vacio = ambos): empatan porque hoy ningun
 *     admin tiene rol efectivo rrpp ni hay rrpp activo con clubs vacio.
 *   - con/sin filtro eliminado_at: empatan porque no hay rrpp activo y
 *     eliminado a la vez.
 *   - destino='todos' y destino='team': sin fixture real (el unico aviso
 *     del respaldo es destino='rrpp'). 'todos' = cualquier rol que opere
 *     en el club; 'team' = team EFECTIVO igual al del aviso (con el mismo
 *     porton teams.clubs verificado en rosters). AJUSTAR si el arnes
 *     encuentra un aviso real de esos destinos.
 */

/* avisos_pendientes(p_club text) -> array
 *
 * Avisos que el usuario logueado todavia no vio, para el club dado.
 *
 * CORRECCION sobre la version anterior: usaba join obligatorio a
 * club_membership — pero la mayoria del personal NO tiene fila de
 * membership (96 filas para 248 perfiles) y con ese join casi nadie
 * habria visto avisos. Con la regla de alcance refutada por datos (45 vs
 * 149), se pasa a rol/team EFECTIVOS, igual que la familia de rosters.
 *
 * Deducido, sin fixture propio (el usuario de prueba es admin y la real
 * le dio [] siempre — consistente: 'admin' no es ningun destino posible).
 * Orden por created_at asc: supuesto razonable con 1 solo aviso real —
 * NO VERIFICADO con varios avisos pendientes a la vez.
 */
create or replace function avisos_pendientes(p_club text)
returns table (
  id      uuid,
  titulo  text,
  mensaje text
)
language sql
stable
security definer
set search_path = public
as $$
  with yo as (
    select p.id,
           coalesce(cm.rol, p.rol) as rol_ef,
           coalesce(
             cm.team_id,
             case when tb.id is not null
                       and (tb.clubs is null or coalesce(array_length(tb.clubs, 1), 0) = 0 or p_club = any(tb.clubs))
                  then p.team_id
             end
           ) as team_ef
      from profiles p
      left join club_membership cm on cm.user_id = p.id and cm.club_id = p_club
      left join teams tb on tb.id = p.team_id
     where p.id = auth.uid()
       and p.activo
       and p.eliminado_at is null
  )
  select a.id, a.titulo, a.mensaje
    from avisos a
    cross join yo
   where a.activo = true
     and (a.hasta_ts is null or a.hasta_ts > now())
     and (a.club_id is null or a.club_id = p_club)
     and (
       a.destino = 'todos'
       or (a.destino = 'rrpp' and yo.rol_ef = 'rrpp')
       or (a.destino = 'jefe' and yo.rol_ef = 'jefe')
       or (a.destino = 'team' and a.team_id = yo.team_ef)
     )
     and not exists (
       select 1 from aviso_visto al
        where al.aviso_id = a.id and al.user_id = auth.uid()
     )
   order by a.created_at asc;
$$;


/* avisos_admin(p_club text) -> array
 *
 * Panel de administracion de avisos (sheetAvisos). Trae TODOS los avisos
 * del club (activos e inactivos — el cliente pinta atenuados), con:
 *   - leidos:  count(*) de aviso_visto para ese aviso
 *   - alcance: a cuanta gente le toca el aviso segun su destino
 *
 * alcance VERIFICADO CON DATOS contra el fixture real (149 para el aviso
 * rrpp/bowie — ver bloque "Compatibilidad persona<->aviso" arriba, que
 * documenta tambien lo que quedo ambiguo). leidos=45 NO verificable
 * offline: la tabla aviso_visto no esta en el respaldo; queda para el
 * arnes una vez importadas las lecturas.
 *
 * DOS HALLAZGOS por ejecucion (2026-08-19, avisos_admin en ambos clubs):
 *   - NO filtra por club: el panel de burtown devuelve el aviso de bowie,
 *     identico (el cliente muestra la etiqueta del club por eso mismo).
 *   - alcance se calcula con el club DEL AVISO, no con p_club: burtown
 *     devuelve alcance=149 (el conteo rrpp/bowie). Para avisos con
 *     club_id null ("ambos") se usa p_club — SUPUESTO no verificable
 *     (el unico aviso real tiene club_id concreto).
 *
 * Campos y orden (created_at desc) segun la respuesta real registrada.
 */
create or replace function avisos_admin(p_club text)
returns table (
  id         uuid,
  team       text,
  activo     boolean,
  leidos     bigint,
  titulo     text,
  alcance    bigint,
  club_id    text,
  destino    text,
  mensaje    text,
  hasta_ts   timestamptz,
  created_at timestamptz
)
language sql
stable
security definer
set search_path = public
as $$
  select
    a.id,
    t.nombre as team,
    a.activo,
    (select count(*) from aviso_visto al where al.aviso_id = a.id) as leidos,
    a.titulo,
    (
      select count(*)
        from profiles p
        left join club_membership cm on cm.user_id = p.id
              and cm.club_id = coalesce(a.club_id, p_club)
        left join teams tb on tb.id = p.team_id
       where p.activo
         and p.eliminado_at is null
         and coalesce(a.club_id, p_club) = any(coalesce(p.clubs, '{}'))
         and (
           a.destino = 'todos'
           or (a.destino = 'rrpp' and coalesce(cm.rol, p.rol) = 'rrpp')
           or (a.destino = 'jefe' and coalesce(cm.rol, p.rol) = 'jefe')
           or (a.destino = 'team' and a.team_id = coalesce(
                 cm.team_id,
                 case when tb.id is not null
                           and (tb.clubs is null or coalesce(array_length(tb.clubs, 1), 0) = 0
                                or coalesce(a.club_id, p_club) = any(tb.clubs))
                      then p.team_id
                 end
               ))
         )
    ) as alcance,
    a.club_id,
    a.destino,
    a.mensaje,
    a.hasta_ts,
    a.created_at
  from avisos a
  left join teams t on t.id = a.team_id
  order by a.created_at desc;
$$;


/* aviso_lectores(p_aviso uuid) -> array
 *
 * Quien vio un aviso puntual. Verificado con el aviso real: devuelve
 * [{nombre, visto_at}] ordenado por visto_at DESC (mas reciente primero).
 */
create or replace function aviso_lectores(p_aviso uuid)
returns table (
  nombre   text,
  visto_at timestamptz
)
language sql
stable
security definer
set search_path = public
as $$
  select p.nombre, al.visto_at
    from aviso_visto al
    join profiles p on p.id = al.user_id
   where al.aviso_id = p_aviso
   order by al.visto_at desc;
$$;


/* validar_entrada(p_evento uuid, p_code text) -> json
 *
 * NO RECONSTRUIDA: es de ESCRITURA, no de lectura.
 *
 * Se identifico por su uso en app.js (lineas 2363-2374 y 2870): marca la
 * entrada como usada (ingreso) y devuelve un resultado que puede ser
 * 'valida' (recien marcada, trae cliente/rrpp/team/mesa/lista_nombre/
 * sin_tope), 'usada' (ya habia entrado antes, trae cliente/used_at),
 * 'anulada' (trae cliente), 'fuera_hora' (trae cliente), o ausente/null
 * (no se encontro esa entrada para el evento).
 *
 * Por la regla de "nunca modificar el ORIGEN" no se ejecuto ahi. Va en la
 * etapa de escritura, modulo check-in.
 */
