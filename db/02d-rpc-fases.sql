-- Fases de venta · tabla reconstruida + RPCs, para dar exactamente lo mismo
-- que las originales (fase_vigente, fases_evento, fase_arte).
--
-- ETAPA 1: paridad. Nada de mejoras acá.
--
-- ============================================================================
-- LA TABLA "fases" NO ES LEGIBLE EN EL ORIGEN
-- ============================================================================
-- PostgREST devuelve 404 para cualquier nombre probado: fases, evento_fases,
-- fases_venta, lista_fases, ticket_fases, fase. No está expuesta como tabla/
-- vista en el schema public accesible por REST, así que sus filas NO se
-- pudieron leer ni importar directamente.
--
-- La estructura de abajo es DEDUCIDA leyendo:
--   - las respuestas de fases_evento/fase_vigente (columnas propias vs.
--     calculadas),
--   - el formulario de alta/edición de fases en app.js (sheetFases, ids
--     fsN/fsP/fsC/fsO/fsD/fsH -> nombre/precio/cupo/orden/desde/hasta),
--   - la llamada a fase_arte(p_fase, p_url) que setea ticket_url.
--
-- Columnas propias de la fase (no calculadas):
--   id (uuid), evento_id (uuid), nombre (text), precio (numeric),
--   cupo (int, nullable = sin tope), desde (timestamptz, nullable),
--   hasta (timestamptz, nullable), orden (int), activo (boolean),
--   ticket_url (text, nullable)
--
-- Campos que las RPCs devuelven pero que NO son columnas (se calculan al
-- vuelo, ver las funciones más abajo): vendidas, quedan, agotada, vigente,
-- cupo_team, quedan_team.
--
-- Las 3 filas insertadas abajo para "Aniversario Bowie" son RECONSTRUIDAS a
-- partir de las respuestas reales de fases_evento/fase_vigente ejecutadas
-- contra el origen (evento bde536c8-9056-4588-a9d2-7e994f2fdff1), NO son un
-- import de la tabla real (que es ilegible). Se usan los mismos id de fase
-- que trae el origen para que fase_id en la tabla entradas del destino siga
-- apuntando a algo válido.
/* ACTUALIZACIÓN 2026-08-20: la tabla real se llama `evento_fase` y SÍ es
 * legible por REST (el intento anterior probó seis nombres pero no el
 * singular; lo reveló el hint de PostgREST). Sus filas y columnas reales
 * se leyeron completas: la estructura deducida era EXACTA salvo la columna
 * created_at, que se agrega acá. Las filas de abajo son las REALES. */
create table if not exists evento_fase (
  id uuid primary key default gen_random_uuid(),
  evento_id uuid not null references eventos(id) on delete cascade,
  nombre text not null,
  precio numeric not null,
  cupo int,                    -- null = sin tope
  desde timestamptz,
  hasta timestamptz,
  orden int not null default 1,
  activo boolean not null default true,
  created_at timestamptz,
  ticket_url text
);

comment on table evento_fase is
  'RECONSTRUIDA: no legible por PostgREST en el origen (404 en todos los '
  'nombres probados). Estructura deducida de las respuestas de las RPCs '
  'fases_evento/fase_vigente y del formulario sheetFases en app.js. Las '
  'filas de Aniversario Bowie son reconstruidas de esas respuestas, no '
  'importadas.';

-- Aniversario Bowie = bde536c8-9056-4588-a9d2-7e994f2fdff1 (unico evento con
-- venta_por_fases = true al momento de la reconstruccion).
-- Se usan los mismos id que devuelve el origen para que entradas.fase_id siga
-- apuntando correctamente.
-- Solo si ese evento existe: son filas del proyecto de origen. En una
-- instalación limpia el evento no está y el insert violaba la FK.
do $seed$
begin
  if exists (select 1 from eventos where id = 'bde536c8-9056-4588-a9d2-7e994f2fdff1') then
    insert into evento_fase (id, evento_id, nombre, precio, cupo, desde, hasta, orden, activo, created_at, ticket_url)
    values
      ('4a2a7564-0ccf-40dc-bef9-c027cf140792', 'bde536c8-9056-4588-a9d2-7e994f2fdff1',
       'Hot Tickets', 90, 30, '2026-08-17T10:00:00+00:00', null, 1, true, '2026-08-18T04:02:03.160797+00:00',
       'https://kdkjmqrbiszmkcprinir.supabase.co/storage/v1/object/public/disenos/fase-4a2a7564-0ccf-40dc-bef9-c027cf140792.jpg?v=1787085787143'),
      ('c950ee3e-dce5-4af3-810b-65c114a585d8', 'bde536c8-9056-4588-a9d2-7e994f2fdff1',
       'Fase 1', 120, 50, null, null, 2, true, '2026-08-18T04:02:32.242876+00:00',
       'https://kdkjmqrbiszmkcprinir.supabase.co/storage/v1/object/public/disenos/fase-c950ee3e-dce5-4af3-810b-65c114a585d8.jpg?v=1787085794015'),
      ('3f5eda06-2e0f-4e36-a912-2e0a735fa1a9', 'bde536c8-9056-4588-a9d2-7e994f2fdff1',
       'Fase 2', 150, null, null, null, 3, true, '2026-08-18T04:02:44.363421+00:00',
       'https://kdkjmqrbiszmkcprinir.supabase.co/storage/v1/object/public/disenos/fase-3f5eda06-2e0f-4e36-a912-2e0a735fa1a9.jpg?v=1787187519423')
    on conflict (id) do nothing;
  end if;
end
$seed$;


/* fases_evento(p_evento) -> setof json (array)
 *
 * Todas las fases del evento, en orden, con sus campos calculados.
 *
 * Verificado contra el origen sobre Aniversario Bowie (3 fases: Hot Tickets
 * agotada, Fase 1 agotada, Fase 2 vigente) y sobre HOLIDAY PARTY
 * (venta_por_fases = false -> array vacio []): coincidencia exacta campo por
 * campo en ambos casos.
 *
 *   vendidas = count(entradas.fase_id = f.id). En el origen todas las
 *              entradas de Bowie estan en estado 'valida' (30/50/4, exacto),
 *              asi que no se pudo verificar si vendidas descuenta las
 *              'anulada'. Se implementa contando TODAS las entradas de la
 *              fase sin filtrar por estado, que es la lectura mas simple y
 *              consistente con los numeros observados. Ver nota en
 *              paridad-fases.md.
 *   quedan   = cupo - vendidas si cupo no es null, si no null.
 *   agotada  = quedan <= 0 (false si cupo es null).
 *   vigente  = la fase de menor "orden" entre las activas, no agotadas, y
 *              cuya ventana desde/hasta (si tiene) ya arranco y no termino.
 *              Verificado: Hot Tickets y Fase 1 agotadas -> vigente=false;
 *              Fase 2 sin cupo, nunca agotada -> vigente=true.
 */
create or replace function fases_evento(p_evento uuid)
returns setof json
language sql
stable
security definer
set search_path = public
as $$
  with ventas as (
    select fase_id, count(*)::int as vendidas
      from entradas
     where evento_id = p_evento and fase_id is not null
     group by fase_id
  ),
  calc as (
    select f.*,
           coalesce(v.vendidas, 0) as vendidas
      from evento_fase f
      left join ventas v on v.fase_id = f.id
     where f.evento_id = p_evento
  ),
  calc2 as (
    select *,
           case when cupo is null then null else cupo - vendidas end as quedan,
           case when cupo is null then false else (cupo - vendidas) <= 0 end as agotada
      from calc
  ),
  primera_vigente as (
    select id
      from calc2
     where activo
       and not agotada
       and (desde is null or now() >= desde)
       and (hasta is null or now() <= hasta)
     order by orden
     limit 1
  )
  select json_build_object(
           'id', c.id,
           'cupo', c.cupo,
           'desde', c.desde,
           'hasta', c.hasta,
           'orden', c.orden,
           'activo', c.activo,
           'nombre', c.nombre,
           'precio', c.precio,
           'quedan', c.quedan,
           'agotada', c.agotada,
           'vigente', (c.id = pv.id),
           'vendidas', c.vendidas,
           'ticket_url', c.ticket_url
         )
    from calc2 c
    left join primera_vigente pv on true
   order by c.orden;
$$;


/* fase_vigente(p_evento) -> json (objeto unico, o null)
 *
 * La fase actualmente abierta para vender. null si el evento no vende por
 * fases o no hay ninguna vigente en este momento.
 *
 * Verificado: Aniversario Bowie -> Fase 2 (id 3f5eda06...), campo por campo
 * identico a la real. HOLIDAY PARTY (sin fases) -> null, identico.
 *
 * cupo_team / quedan_team: la RPC real los devuelve, pero en TODOS los casos
 * probados dieron null (no hay tope por team configurado en las fases
 * observadas). No se encontro ninguna columna en la tabla deducida ni en el
 * formulario sheetFases que sugiera de donde saldrian estos valores cuando
 * no son null, asi que NO se pudo verificar su logica real. Se devuelven
 * siempre en null, que es el unico comportamiento verificado. Ver nota en
 * paridad-fases.md.
 */
create or replace function fase_vigente(p_evento uuid)
returns json
language sql
stable
security definer
set search_path = public
as $$
  with ventas as (
    select fase_id, count(*)::int as vendidas
      from entradas
     where evento_id = p_evento and fase_id is not null
     group by fase_id
  ),
  calc as (
    select f.*,
           coalesce(v.vendidas, 0) as vendidas
      from evento_fase f
      left join ventas v on v.fase_id = f.id
     where f.evento_id = p_evento
  ),
  calc2 as (
    select *,
           case when cupo is null then null else cupo - vendidas end as quedan,
           case when cupo is null then false else (cupo - vendidas) <= 0 end as agotada
      from calc
  )
  select json_build_object(
           'id', id,
           'cupo', cupo,
           'desde', desde,
           'hasta', hasta,
           'nombre', nombre,
           'precio', precio,
           'quedan', quedan,
           'vendidas', vendidas,
           'cupo_team', null,
           'ticket_url', ticket_url,
           'quedan_team', null
         )
    from calc2
   where activo
     and not agotada
     and (desde is null or now() >= desde)
     and (hasta is null or now() <= hasta)
   order by orden
   limit 1;
$$;


/* fase_arte(p_fase, p_url) -> void
 *
 * Setea el ticket_url propio de una fase (arte de entrada distinto al del
 * evento). Se llama desde sheetFases al subir una imagen al bucket
 * "disenos" con el path fase-<id>.jpg.
 *
 * NO se pudo probar contra el origen (la tarea prohibe expresamente llamar
 * a guardar_fase/borrar_fase, y por extension no se ejecutaron mutaciones
 * de fase_arte para no modificar el origen). Reconstruida solo a partir del
 * uso que hace app.js: p_fase (uuid) identifica la fase, p_url (text) es la
 * URL publica ya subida a storage. No verificada por ejecucion; el
 * comportamiento surge directo del sitio de llamada:
 *   sb.rpc("fase_arte", { p_fase: b.dataset.farte, p_url: url })
 */
create or replace function fase_arte(p_fase uuid, p_url text)
returns void
language sql
security definer
set search_path = public
as $$
  update evento_fase set ticket_url = p_url where id = p_fase;
$$;
