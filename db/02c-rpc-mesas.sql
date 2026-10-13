-- RPCs de permisos y mesas · reconstruidas para dar exactamente lo mismo
-- que las originales. Cada una se verifico ejecutando la real en el origen
-- (kdkjmqrbiszmkcprinir) con parametros reales y comparando campo por campo
-- contra la version reconstruida en el destino (udhkvqdoqbuiwcfzeoqu).
--
-- ETAPA 1: paridad. Nada de mejoras aca — van en paridad-mesas.md, aparte.


/* vendedores_posibles(p_evento) -> table(id, rol, team, nombre)
 *
 * La lista de "a nombre de quien" se puede cargar una mesa o un anotado:
 * todo el personal de venta (rrpp, jefe, admin) activo que pertenece al
 * club del evento, con el nombre de su team.
 *
 * Deducida leyendo app.js: se llama junto con mis_permisos_mesa en las dos
 * pantallas que muestran "A nombre de" (mesas y listas), y el resultado se
 * usa como {id, nombre, team} para llenar un <select> (líneas ~2229 y
 * ~5666 de app.js). El campo "rol" viaja pero no se usa en la UI — se
 * incluyó porque aparecio en la respuesta real.
 *
 * Verificada primero con el usuario admin (160/208 filas, evento
 * inexistente -> []). CORREGIDA el 2026-08-20: la deriva de datos del
 * origen destapo que rol y team son los EFECTIVOS del club del evento, no
 * los base — IpadQueirolo (base admin, membership jefe) sale como 'jefe',
 * y la gente con membership muestra el team de SU membership en ese club.
 * Con datos sincronizados, la version base difería en ~24 campos por club;
 * la efectiva da identico (salvo el orden entre homonimos, que es fisico
 * en el original — se compara normalizado, ver paridad-rosters.md).
 * Roles excluidos (portero, caja, barra...) e inactivos: ausentes en la
 * respuesta real. Filtro de club: p.clubs, como sheetUsuarios().
 * El porton teams.clubs para el team base sin membership replica el de la
 * familia de rosters (02a) — sin caso real que lo distinga aca.
 * Orden: alfabetico por nombre; homonimos en orden fisico (caso limite).
 */
create or replace function vendedores_posibles(p_evento uuid)
returns table(id uuid, rol text, team text, nombre text)
language sql
stable
security definer
set search_path = public
as $$
  select p.id,
         coalesce(cm.rol, p.rol) as rol,
         tef.nombre as team,
         p.nombre
    from profiles p
    join eventos e on e.id = p_evento
    left join club_membership cm on cm.user_id = p.id and cm.club_id = e.club_id
    left join teams tb on tb.id = p.team_id
    left join teams tef on tef.id = coalesce(
      cm.team_id,
      case when tb.id is not null
                and (p.rol = 'admin'
                     or tb.clubs is null or coalesce(array_length(tb.clubs, 1), 0) = 0
                     or e.club_id = any(tb.clubs))
           then p.team_id
      end
    )
   where p.activo = true
     and coalesce(cm.rol, p.rol) in ('rrpp', 'jefe', 'admin')
     and p.clubs @> array[e.club_id]
   order by p.nombre;
$$;


/* mis_permisos_mesa(p_evento) -> json {cortesia, a_nombre_de}
 *
 * Los dos flags que la UI de mesas y listas lee para decidir que campos
 * mostrar: "puedeCort" (puede vender/anotar como cortesia) y "puedeANombre"
 * (puede cargar la mesa/anotado a nombre de otro vendedor). Ver app.js
 * lineas ~1908 y ~5624: "const puedeANombre = !!permLs?.a_nombre_de" /
 * "const puedeCort = !!permMesa?.cortesia".
 *
 * Deducida por el comportamiento observado del origen, sin poder ver el
 * codigo SQL real:
 *   - Con sesion de admin (aqueirolo) y evento valido: {"cortesia": true,
 *     "a_nombre_de": true} — probado en un evento de bowie Y uno de
 *     burtown, mismo resultado.
 *   - Sin sesion (llamada anonima) y evento valido: {"cortesia": false,
 *     "a_nombre_de": false} — no da error ni null, da los dos flags en
 *     false. Esto dice que la funcion no exige que exista auth.uid(): hace
 *     left join con profiles y cuando no hay fila coalesce-ea a false.
 *   - Evento inexistente (o null), con o sin sesion: null (no una fila con
 *     flags en false). Esto dice que el evento se resuelve con un join
 *     obligatorio contra eventos (inner join): sin fila de evento no hay
 *     fila de resultado.
 * De ahi la forma reconstruida: inner join a eventos (para que el evento
 * inexistente de null), left join a profiles por auth.uid() (para que la
 * sesion anonima de false/false en vez de null), y los flags salen de
 * p.rol in ('jefe','admin') con coalesce a false.
 *
 * La regla exacta de que roles dan que flags (jefe y admin ambos true,
 * rrpp ambos false) es una inferencia razonable a partir de los
 * comentarios de app.js ("jefe tambien vende", "jefe anota lo suyo") y de
 * que la pantalla solo llama a esta RPC para rol in (rrpp,jefe,admin) —
 * pero NO se pudo confirmar ejecutando la RPC real con una sesion de rrpp
 * o de jefe: la unica cuenta disponible para autenticar en el origen es
 * la de admin (aqueirolo). Por eso esta funcion NO se marca como
 * verificada con paridad exacta — ver paridad-mesas.md.
 */
create or replace function mis_permisos_mesa(p_evento uuid)
returns json
language sql
stable
security definer
set search_path = public
as $$
  select json_build_object(
    'cortesia',    coalesce(p.rol in ('jefe', 'admin'), false),
    'a_nombre_de', coalesce(p.rol in ('jefe', 'admin'), false)
  )
  from eventos e
  left join profiles p on p.id = auth.uid()
  where e.id = p_evento;
$$;


/* verificar_mesa(p_mesa, p_ok) -> void
 *
 * El admin confirma o rechaza el pago de una mesa que ya esta 'pagada'
 * pero sin verificar (pago_verificado = false). Se llama desde el sheet de
 * la mesa (botones "Confirmar que el pago entro" / "Rechazar — volver a
 * reservada", solo visibles para me.rol === "admin", app.js linea ~5882)
 * y desde la pantalla de contabilidad que lista todas las pendientes de
 * una (app.js linea ~6041, "sheetContabilidad").
 *
 * p_ok = true:  pago_verificado = true. El estado de la mesa NO cambia
 *               (sigue 'pagada'). El cliente actualiza localmente solo
 *               "m.pago_verificado = true" sin tocar el estado (linea
 *               6087), lo que confirma que la RPC tampoco lo toca.
 * p_ok = false: pago_verificado = false, estado = 'reservada'. El cliente
 *               actualiza localmente "m.estado = 'reservada'; pago_verificado
 *               = false" (linea 6103) y el mensaje de confirmacion dice
 *               literalmente "La mesa vuelve al estado reservada y queda
 *               pendiente de cobro" (lineas 5906 y 6097).
 * En los dos casos se registra verificado_por (auth.uid()) y verificado_at
 * (now()) — son las columnas que la UI muestra como "Pago verificado" con
 * fecha (linea 5859) y que solo tienen sentido si las llena esta RPC, ya
 * que no hay otro punto en app.js que las escriba.
 *
 * NO se toco reservada_at ni reserva_vence_at al rechazar: no hay evidencia
 * en app.js de que se deba dar una nueva ventana de pago (el comentario de
 * la linea 5184 dice que el vencimiento "viaja en la mesa" y no se
 * recalcula), asi que se dejo la reconstruccion minima: solo lo que la UI
 * confirma que cambia. Ver "Mejoras detectadas" en paridad-mesas.md por si
 * en el original si se resetea el plazo — no se pudo verificar ninguna de
 * las dos hipotesis sin poder llamar a la RPC real (esta prohibido: es una
 * RPC de escritura y la base origen no se puede modificar).
 *
 * IMPORTANTE: por regla dura del encargo, esta RPC nunca se ejecuto contra
 * el origen (ni con p_ok=true ni false) para no modificar esa base. La
 * reconstruccion sale entera de leer app.js y del esquema de columnas de
 * 01-tablas.sql. Se probo (aplicar + revertir) contra el DESTINO nomas,
 * sobre la mesa M1 del evento "Aniversario Bowie" (pago_verificado=false),
 * confirmando que p_ok=true la deja pagada+verificada y p_ok=false la
 * vuelve reservada+sin verificar, y se restauro su estado original. Con
 * mesa inexistente no tira error (UPDATE de 0 filas). No cuenta como
 * paridad verificada contra el origen — ver paridad-mesas.md.
 */
create or replace function verificar_mesa(p_mesa uuid, p_ok boolean)
returns void
language sql
security definer
set search_path = public
as $$
  update mesas
     set pago_verificado = p_ok,
         verificado_por   = auth.uid(),
         verificado_at    = now(),
         estado           = case when p_ok then estado else 'reservada' end,
         updated_at       = now()
   where id = p_mesa;
$$;
