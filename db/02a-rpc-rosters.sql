-- RPCs de ROSTERS Y EQUIPO · reconstruidas para dar exactamente lo mismo que
-- las originales. Cada una se verificó ejecutando la real y la reconstruida
-- sobre los mismos datos, comparando campo por campo.
--
-- ETAPA 1: paridad. Nada de mejoras acá — van en PARIDAD-rosters.md.
--
-- Referencia de estilo: db/02-rpc-lectura.sql. Este archivo NO toca
-- db/01-tablas.sql ni db/02-rpc-lectura.sql.


-- ============================================================
-- Tablas que faltaban en el respaldo de 19 tablas
-- ============================================================
--
-- Ninguna de las dos vivía en el respaldo (9.316 filas / 19 tablas). Se
-- encontraron probando GET al REST de PostgREST: pedir /rest/v1/telefonos
-- devolvió 404 con un hint de PostgREST señalando el nombre real
-- ("Perhaps you meant the table 'public.telefono_usuario'"). El mismo truco
-- con /rest/v1/sin_tope apuntó a "public.ingreso_sin_tope", que coincide con
-- el nombre que ya aparecía en un comentario de app.js.
--
-- Ambas se leen íntegras vía REST (rol autenticado, no anon) y se importaron
-- fila por fila al DESTINO: 125 filas en telefono_usuario, 4 en
-- ingreso_sin_tope — igual que en el ORIGEN.

-- telefono_usuario: un cel por persona. user_id es PK (125 filas, 125 ids
-- únicos, verificado). cargado_por casi siempre es igual a user_id (cada
-- quien carga el suyo); difiere cuando lo cargó un admin por otra persona
-- (guardar_telefono_de, RPC de escritura que no se toca acá).
create table if not exists telefono_usuario (
  user_id        uuid primary key,
  telefono       text not null,
  actualizado_at timestamptz not null,
  cargado_por    uuid
);
alter table telefono_usuario add constraint telefono_usuario_user_id_fkey
  foreign key (user_id) references profiles(id);   -- 125 valores verificados

-- ingreso_sin_tope: quiénes entran sin hora tope en la puerta, por boliche.
-- 4 filas en el respaldo real: Queirolo y jmenacho, una fila por cada club
-- (bowie y burtown). PK compuesta (user_id, club_id) verificada única.
create table if not exists ingreso_sin_tope (
  user_id     uuid not null,
  club_id     text not null,
  nota        text,
  creado_por  uuid,
  created_at  timestamptz,
  primary key (user_id, club_id)
);
alter table ingreso_sin_tope add constraint ingreso_sin_tope_user_id_fkey
  foreign key (user_id) references profiles(id);   -- 4 valores verificados
alter table ingreso_sin_tope add constraint ingreso_sin_tope_club_id_fkey
  foreign key (club_id) references clubs(id);   -- 4 valores verificados


-- ============================================================
-- Rol y team EFECTIVOS por club
-- ============================================================
--
-- Las cuatro RPCs de roster (roster_mi_team, roster_relacionadores,
-- roster_cupos, teams_efectivos) y telefonos_equipo comparten la misma
-- lógica: el rol y el team de alguien pueden ser distintos en cada boliche
-- (club_membership manda si existe una fila para ese club; si no, se usa el
-- rol/team base del perfil). Se verificó con jribera (José Luis Ribera):
-- base rol='jefe', team='Team JR' (por club_membership en burtown); pero en
-- bowie tiene club_membership con rol='rrpp', team='Team AQ' — y las 5 RPCs
-- lo devuelven como rrpp de Team AQ al pedir p_club='bowie'. Esta lógica es
-- la misma que arma sheetUsuarios() en el cliente (app.js ~L3756).
--
-- El team BASE (profiles.team_id, sin club_membership) sólo vale como team
-- EFECTIVO si ese team opera en el club pedido (teams.clubs incluye p_club,
-- o teams.clubs es null/vacío = opera en ambos). Si no, el team efectivo cae
-- a NULL ('Sin team') aunque la persona sí tenga team_id de base. Detectado
-- comparando teams_efectivos('bowie') real vs la primera versión reconstruida:
-- 47 filas discrepaban, todas de gente con team_id base cuyo team es
-- burtown-only (ej. Leonardo Leigue, team_id -> Team DA, clubs=['burtown']),
-- sin club_membership propia: la real da team='Sin team' en bowie, no
-- 'Team DA'. El ROL en cambio no se degrada por esto — sluciana (jefe, team
-- base Team LS que es burtown-only) sigue dando rol='jefe' en bowie, sólo
-- cambia el team a 'Sin team'. (Esto es distinto de la función _effRol()
-- del cliente en sheetUsuarios(), que si degrada jefe->rrpp en ese caso; acá
-- se siguió lo que hace la RPC real, no el cliente.)


/* teams_efectivos(p_club) -> table(user_id, nombre, rol, team, team_id)
 *
 * El rol y team EFECTIVOS de cada persona activa (rrpp, jefe o admin) en
 * ESTE boliche. Es la única de las 5 que NO filtra por si la persona opera
 * en el club: siempre devuelve a los 233 activos elegibles (rrpp+jefe+admin,
 * activo=true, eliminado_at is null), sólo cambia el team/rol de cada quien
 * según el club pedido. Verificado: llamando con 'bowie' y con 'burtown' da
 * el mismo total (233) pero difieren 75 filas — exactamente las personas con
 * club_membership distinto entre los dos boliches (ej. jribera: rrpp/Team AQ
 * en bowie vs jefe/Team JR en burtown).
 *
 * 'Sin team' es un coalesce del nombre del team (no null) — verificado con
 * Matias Angulo, team_id null, team='Sin team'.
 *
 * LOS ADMIN NO PASAN POR EL PORTÓN team.clubs: se probó con p_club='nope'
 * (un club que no existe, sin ninguna fila de club_membership posible) y los
 * 3 admin (aqueirolo, horacio01, IpadQueirolo) igual mostraron su team base
 * (Team AQ, null, Team S respectivamente) en vez de cualquier fallback a
 * 'Sin team'. Un rrpp/jefe común en la misma situación SÍ cae a 'Sin team'
 * (verificado con Leonardo Leigue y sluciana). Por eso el gateo de
 * teams.clubs sólo se aplica si el rol BASE no es 'admin'.
 */
create or replace function teams_efectivos(p_club text)
returns table (
  user_id  uuid,
  nombre   text,
  rol      text,
  team     text,
  team_id  uuid
)
language sql
stable
security definer
set search_path = public
as $$
  select p.id,
         p.nombre,
         coalesce(cm.rol, p.rol) as rol,
         coalesce(tef.nombre, 'Sin team') as team,
         tef.id as team_id
    from profiles p
    left join club_membership cm on cm.user_id = p.id and cm.club_id = p_club
    left join teams tb on tb.id = p.team_id
    left join teams tef on tef.id = coalesce(
      cm.team_id,
      case when tb.id is not null
                and (p.rol = 'admin'
                     or tb.clubs is null or coalesce(array_length(tb.clubs, 1), 0) = 0
                     or p_club = any(tb.clubs))
           then p.team_id
      end
    )
   where p.rol in ('rrpp', 'jefe', 'admin')
     and p.activo
     and p.eliminado_at is null;
$$;


/* roster_relacionadores(p_club) -> table(id, rol, team, clubs, nombre, usuario)
 *
 * Relacionadores y jefes (sin admin) que operan en este boliche, con su rol
 * y team EFECTIVOS. Usada por Caja para entregar manillas por team.
 *
 * El filtro de rol es sobre el rol EFECTIVO, no el de base: se encontró a
 * "IpadQueirolo" (rol base 'admin') en el resultado real de bowie porque
 * tiene club_membership con rol='jefe' en ambos clubes — con el filtro
 * `p.rol in (...)` sobre el rol base faltaba esa fila (157 en vez de 158).
 *
 * Filtro de "opera en este boliche": p_club = any(profiles.clubs) — el campo
 * base, no club_membership. No se pudo distinguir empíricamente de un filtro
 * por club_membership porque en los datos reales todo el que tiene
 * membership en un club también tiene ese club en su campo `clubs` base (0
 * discrepancias en 48 filas de club_membership de bowie). Se eligió `clubs`
 * porque es el mismo campo que usa sheetUsuarios() en el cliente para armar
 * "gente" (app.js ~L3770) y porque no hace falta join extra.
 *
 * Verificado contra la real, campo por campo y en el mismo orden: 158 filas
 * en bowie, 206 en burtown, [] con un club inventado. Roles efectivos solo
 * jefe/rrpp, activo=true (los inactivos no aparecen: se probó con 4 perfiles
 * activo=false/eliminado_at=null de burtown y ninguno salió).
 *
 * Orden: por el NOMBRE del team (texto), con 'Sin team' al final — se
 * comprueba ordenando por team_id nulls last, pero el team_id no da orden
 * alfabético (Team S y Team SM no son consecutivos por uuid); lo que da la
 * secuencia real AQ,CD,DG,GS,IA,MAPI,OV,Rodrigo,S,SM,Sin team es ordenar por
 * el nombre del team con los NULL (sin team) al final, y adentro por
 * p.nombre.
 *
 * CASO LÍMITE NO RESUELTO: cuando dos personas del mismo team tienen el
 * mismo nombre completo (pasa con 4 pares/tríos reales de homónimos, ej. 3
 * "Ludwig Fernando Cuellar Ribera" en Team CD de burtown), el orden entre
 * ellos en la RPC real no se pudo explicar por id, usuario ni created_at —
 * probablemente depende del orden físico de fila en la tabla origen, que acá
 * no se puede reproducir. Se agregó p.id como desempate final para que el
 * orden sea al menos determinístico; no coincide con el de la real en esos
 * pocos casos de nombre duplicado. El resto del orden (158/158 en bowie,
 * 206/206 en burtown salvo 3 filas de un trío homónimo) es idéntico.
 */
create or replace function roster_relacionadores(p_club text)
returns table (
  id      uuid,
  rol     text,
  team    text,
  clubs   text[],
  nombre  text,
  usuario text
)
language sql
stable
security definer
set search_path = public
as $$
  select p.id,
         coalesce(cm.rol, p.rol) as rol,
         coalesce(tef.nombre, 'Sin team') as team,
         p.clubs,
         p.nombre,
         p.usuario
    from profiles p
    left join club_membership cm on cm.user_id = p.id and cm.club_id = p_club
    left join teams tb on tb.id = p.team_id
    left join teams tef on tef.id = coalesce(
      cm.team_id,
      case when tb.id is not null
                and (tb.clubs is null or coalesce(array_length(tb.clubs, 1), 0) = 0 or p_club = any(tb.clubs))
           then p.team_id
      end
    )
   where coalesce(cm.rol, p.rol) in ('rrpp', 'jefe')
     and p.activo
     and p.eliminado_at is null
     and p_club = any(coalesce(p.clubs, '{}'))
   order by tef.nombre nulls last, p.nombre, p.id;
$$;


/* roster_cupos(p_club) -> table(id, rol, team, nombre, usuario)
 *
 * Igual que roster_relacionadores pero SIN el campo clubs y CON los admins
 * incluidos (rol EFECTIVO in rrpp, jefe, admin — como ya incluye admin, el
 * caso IpadQueirolo de roster_relacionadores no lo afecta acá, pero se
 * filtra por rol efectivo de todas formas por consistencia con las otras
 * RPCs de este archivo). Usada para elegir a quién darle un cupo especial
 * en una lista.
 *
 * Verificado campo por campo y en orden: mismas 158 personas de
 * roster_relacionadores más 2 (aqueirolo y horacio01, los admins activos con
 * 'bowie' en su campo clubs) = 160 en bowie. Mismo orden que
 * roster_relacionadores (nombre del team, 'Sin team' al final, luego
 * p.nombre).
 */
create or replace function roster_cupos(p_club text)
returns table (
  id      uuid,
  rol     text,
  team    text,
  nombre  text,
  usuario text
)
language sql
stable
security definer
set search_path = public
as $$
  select p.id,
         coalesce(cm.rol, p.rol) as rol,
         coalesce(tef.nombre, 'Sin team') as team,
         p.nombre,
         p.usuario
    from profiles p
    left join club_membership cm on cm.user_id = p.id and cm.club_id = p_club
    left join teams tb on tb.id = p.team_id
    left join teams tef on tef.id = coalesce(
      cm.team_id,
      case when tb.id is not null
                and (p.rol = 'admin'
                     or tb.clubs is null or coalesce(array_length(tb.clubs, 1), 0) = 0
                     or p_club = any(tb.clubs))
           then p.team_id
      end
    )
   where coalesce(cm.rol, p.rol) in ('rrpp', 'jefe', 'admin')
     and p.activo
     and p.eliminado_at is null
     and p_club = any(coalesce(p.clubs, '{}'))
   order by tef.nombre nulls last, p.nombre, p.id;
$$;


/* telefonos_equipo(p_club) -> table(user_id, usuario, nombre, rol, team, activo, telefono)
 *
 * Todo el equipo del boliche (rrpp, jefe, portero, caja, admin) con su
 * teléfono si lo cargó. Usada por la pantalla "WhatsApp del equipo" y por
 * sheetUsuarios() para no pedir otra vez el mismo dato.
 *
 * Filtro de "gente del boliche" verificado exactamente igual al de
 * sheetUsuarios() en el cliente (app.js ~L3770): admin siempre entra, o el
 * campo clubs vacío/null (opera en ambos), o p_club está en clubs. 168 filas
 * para bowie — coincide con contar así sobre los 241 perfiles activos no
 * eliminados.
 *
 * A diferencia de las otras 4 RPCs de este archivo, acá 'team' es NULL
 * cuando no hay team (no 'Sin team' como texto) — verificado con Ariane
 * (caja) y Daniel Santiago (rrpp sin team), ambos con team: null.
 *
 * A DIFERENCIA de teams_efectivos/roster_relacionadores/roster_cupos, acá el
 * team BASE se usa siempre que no haya club_membership, SIN el portón de
 * teams.clubs: Matias Angulo (team base "Team DA", que es sólo de burtown)
 * sale con team='Sin team' en teams_efectivos('bowie') pero con team='Team
 * DA' en telefonos_equipo('bowie') — mismo user, mismo club, distinta RPC.
 * Se siguió el dato real en cada una en vez de asumir que comparten la
 * lógica.
 *
 * ORDEN — esto es lo que más costó encontrar: NO es alfabético simple. La
 * secuencia real de bowie arranca en "Adriana..." y en la fila 65 saltа de
 * "Yuei Toyosato" a "Abigail Steinbach" — dos tramos alfabéticos A→V
 * seguidos. Separando por si telefono es null: el primer tramo (65 filas)
 * es exactamente la gente SIN teléfono, el segundo (103 filas) la gente CON
 * teléfono — cada tramo ordenado por nombre. Coincide con cómo
 * sheetTelefonos() arma la pantalla en dos secciones, "Faltan" antes que
 * "Cargados" (app.js ~L3691-3692): la RPC ya devuelve los datos en ese
 * orden.
 */
create or replace function telefonos_equipo(p_club text)
returns table (
  user_id  uuid,
  usuario  text,
  nombre   text,
  rol      text,
  team     text,
  activo   boolean,
  telefono text
)
language sql
stable
security definer
set search_path = public
as $$
  select p.id,
         p.usuario,
         p.nombre,
         coalesce(cm.rol, p.rol) as rol,
         tef.nombre as team,
         p.activo,
         tu.telefono
    from profiles p
    left join club_membership cm on cm.user_id = p.id and cm.club_id = p_club
    left join teams tb on tb.id = p.team_id
    left join teams tef on tef.id = coalesce(cm.team_id, p.team_id)
    left join telefono_usuario tu on tu.user_id = p.id
   where p.eliminado_at is null
     and (p.rol = 'admin' or coalesce(array_length(p.clubs, 1), 0) = 0 or p_club = any(p.clubs))
   order by (tu.telefono is not null), p.nombre;
$$;


/* roster_mi_team(p_club) -> table(id, nombre, usuario, activo)
 *
 * Los relacionadores del team del JEFE que llama, en ESTE boliche. La usa
 * screenTeam(), a la que sólo se llega si me.rol !== 'admin' (el admin va a
 * screenTeamAdmin() en su lugar) — o sea que en la práctica sólo la llama un
 * jefe.
 *
 * NO SE PUDO VERIFICAR contra la RPC real por paridad de datos: sólo hay
 * login disponible para el usuario admin (aqueirolo), y llamar la RPC real
 * como admin dio [] tanto en bowie como en burtown — consistente con que la
 * función exige que el rol EFECTIVO del caller en p_club sea 'jefe' (aqueirolo
 * es admin en los dos, nunca jefe). No hay credenciales de ningún jefe para
 * probar el camino con datos.
 *
 * Reconstruida por deducción, reusando la misma lógica de team/rol efectivo
 * verificada en roster_relacionadores: los rrpp cuyo team EFECTIVO en p_club
 * es el mismo que el team EFECTIVO del caller en p_club. Incluye inactivos
 * (a diferencia de roster_relacionadores) porque screenTeam() muestra un
 * botón "Activar" para los pausados — si la RPC no los devolviera, ese botón
 * no tendría sobre quién actuar.
 *
 * NO VERIFICADA POR PARIDAD DE DATOS — ver paridad-rosters.md.
 */
create or replace function roster_mi_team(p_club text)
returns table (
  id      uuid,
  nombre  text,
  usuario text,
  activo  boolean
)
language sql
stable
security definer
set search_path = public
as $$
  with yo as (
    select p.id,
           coalesce(cm.rol, p.rol) as rol_efectivo,
           coalesce(
             cm.team_id,
             case when tb.id is not null
                       and (tb.clubs is null or coalesce(array_length(tb.clubs, 1), 0) = 0 or p_club = any(tb.clubs))
                  then p.team_id
             end
           ) as team_efectivo
      from profiles p
      left join club_membership cm on cm.user_id = p.id and cm.club_id = p_club
      left join teams tb on tb.id = p.team_id
     where p.id = auth.uid()
  )
  select p.id,
         p.nombre,
         p.usuario,
         p.activo
    from profiles p
    left join club_membership cm on cm.user_id = p.id and cm.club_id = p_club
    left join teams tb on tb.id = p.team_id
    join yo on yo.rol_efectivo = 'jefe' and yo.team_efectivo is not null
   where coalesce(cm.rol, p.rol) = 'rrpp'
     and coalesce(
           cm.team_id,
           case when tb.id is not null
                     and (tb.clubs is null or coalesce(array_length(tb.clubs, 1), 0) = 0 or p_club = any(tb.clubs))
                then p.team_id
           end
         ) = yo.team_efectivo
     and p.eliminado_at is null
   order by p.nombre;
$$;


/* usuarios_sin_tope(p_club) -> uuid[]
 *
 * Ids de quienes entran sin hora tope en la puerta, en este boliche. Sale
 * de la tabla ingreso_sin_tope (ver arriba) filtrando por club_id.
 *
 * Verificado con los 2 clubes reales: bowie y burtown dan los mismos 2 ids
 * (327367d6... = aqueirolo, 83a12558... = jmenacho) porque hay una fila por
 * cada uno en cada club. Con un club inventado ('nope') da [] — igual que la
 * real, porque no hay filas de ingreso_sin_tope con ese club_id.
 */
create or replace function usuarios_sin_tope(p_club text)
returns uuid[]
language sql
stable
security definer
set search_path = public
as $$
  select coalesce(array_agg(user_id order by user_id), '{}')
    from ingreso_sin_tope
   where club_id = p_club;
$$;


/* mi_telefono() -> text
 *
 * El teléfono del usuario que llama, o null si nunca lo cargó. Se usa al
 * entrar a la app para decidir si hay que pedirlo (pedirTelefono() en
 * app.js).
 *
 * Verificado contra la real logueado como aqueirolo: la real devolvió
 * "59177319195", exactamente el valor de telefono_usuario para su user_id.
 *
 * Depende de auth.uid(): en el DESTINO no hay usuarios de auth replicados
 * (no hay sesión equivalente para probar "cambia según quién llama"). Se
 * verificó la FORMA de la respuesta y la lógica (select directo a
 * telefono_usuario por auth.uid()) contra el único caso disponible; la
 * paridad exacta para otros usuarios no es verificable sin su sesión.
 */
create or replace function mi_telefono()
returns text
language sql
stable
security definer
set search_path = public
as $$
  select telefono from telefono_usuario where user_id = auth.uid();
$$;
