-- RPCs de CUPOS Y VENTANA DE VENTA · mis_cupos, ventana_venta,
-- excepciones_venta, cupos_fase. Reconstruidas para dar exactamente lo
-- mismo que las originales.
--
-- ETAPA 1: paridad. Nada de mejoras acá.
--
-- MÉTODO: capturas reales del 2026-08-19 (.scratch/capturas/) con
-- parámetros elegidos del respaldo para tocar cada rama (excepción de
-- team, de persona, sin excepción; 10 juegos de ventana_venta), más el
-- ajuste offline contra el respaldo. Falta la comparación por ejecución
-- en el destino (arnés db/paridad).


/* Tabla deducida: cupo por team dentro de una fase --------------------
 * guardar_cupo_team / cupos_fase / fase_vigente (cupo_team) necesitan un
 * almacén (fase, team) -> cupo. NO es legible en el origen (mismo caso que
 * la tabla fases) y en TODOS los datos observados el cupo es null, así que
 * ni el nombre real ni columnas extra se pudieron confirmar.
 * NO VERIFICADA — si el original usa otro nombre, ajustar acá y en
 * guardar_cupo_team cuando se reconstruya (etapa de escritura). */
create table if not exists fase_cupo_team (
  fase_id uuid not null references evento_fase(id) on delete cascade,
  team_id uuid not null references teams(id),
  cupo    int,
  primary key (fase_id, team_id)
);


/* mis_cupos(p_evento) -> filas {cupo, especial, lista_tipo_id}
 *
 * Una fila por lista del evento, en el orden de lista_tipos.orden
 * (verificado con la sesión admin en los 10 eventos: 2-3 filas cada uno,
 * cupo = cupo_admin — null en todos — y especial = false).
 *
 * Precedencia del cupo (la parte especial NO se pudo ejecutar: la única
 * sesión disponible es admin y no tiene cupos especiales; la regla sale
 * de la deducción ya documentada en ESTADO.md y del uso en app.js):
 *   1. cupo_rrpp (lista_tipo_id, user)            -> especial = true
 *   2. cupo_permanente (club, lista_nombre, user) -> especial = true
 *   3. según rol EFECTIVO en el club del evento:
 *        admin -> cupo_admin · jefe -> coalesce(cupo_jefe, cupo_por_rrpp)
 *        rrpp  -> cupo_por_rrpp                   -> especial = false
 * (el fallback jefe->cupo_por_rrpp replica el del cliente, app.js L1979)
 */
create or replace function mis_cupos(p_evento uuid)
returns table (
  cupo          int,
  especial      boolean,
  lista_tipo_id uuid
)
language sql
stable
security definer
set search_path = public
as $$
  with ctx as (
    select e.club_id,
           coalesce(cm.rol, p.rol) as rol_ef
      from eventos e
      left join profiles p on p.id = auth.uid()
      left join club_membership cm on cm.user_id = p.id and cm.club_id = e.club_id
     where e.id = p_evento
  )
  select
    coalesce(cr.cupo, cp.cupo,
      case (select rol_ef from ctx)
        when 'admin' then lt.cupo_admin
        when 'jefe'  then coalesce(lt.cupo_jefe, lt.cupo_por_rrpp)
        else lt.cupo_por_rrpp
      end) as cupo,
    (cr.user_id is not null or cp.user_id is not null) as especial,
    lt.id as lista_tipo_id
  from lista_tipos lt
  left join cupo_rrpp cr on cr.lista_tipo_id = lt.id and cr.user_id = auth.uid()
  left join cupo_permanente cp on cp.user_id = auth.uid()
    and cp.club_id = (select club_id from ctx)
    and lower(trim(cp.lista_nombre)) = lower(trim(lt.nombre))
  where lt.evento_id = p_evento
  order by lt.orden;
$$;


/* ventana_venta(p_evento, p_user) -> jsonb {desde, hasta, origen}
 *
 * Hasta cuándo puede vender prepagadas UNA persona en UN evento.
 * Verificado con 10 juegos reales de parámetros (3 eventos con
 * excepciones × admin / con excepción de persona / de team / sin nada):
 *
 *   1. excepción de PERSONA (venta_excepcion.user_id = p_user)
 *        -> {desde: desde_ts, hasta: hasta_ts, origen: 'persona'}
 *   2. si no, excepción del TEAM de la persona
 *        -> {..., origen: 'team'}
 *   3. si no -> {desde: manilla_desde, hasta: manilla_hasta_ts,
 *                origen: 'evento'}   (los del evento, aunque sean null)
 *
 * En todas las capturas con excepción, `desde` vino null — coincide con
 * que venta_excepcion.desde_ts es null en las 6 filas reales, así que
 * "desde = desde_ts de la excepción" y "desde = null fijo" son
 * indistinguibles hoy; se usa desde_ts (la lectura natural de la tabla).
 *
 * Team de la persona: coalesce(club_membership del club del evento,
 * team base). El caso verificado del admin (team base, sin membership)
 * salió por su team base; si el portón teams.clubs aplica acá no se pudo
 * determinar (sin caso real) — no se aplica, igual que telefonos_equipo.
 *
 * Si hay más de una excepción del mismo alcance, gana la de hasta_ts más
 * lejano (no hay caso real con duplicados; supuesto documentado).
 */
create or replace function ventana_venta(p_evento uuid, p_user uuid)
returns jsonb
language sql
stable
security definer
set search_path = public
as $$
  with ev as (
    select id, club_id, manilla_desde, manilla_hasta_ts
      from eventos where id = p_evento
  ),
  mi_team as (
    select coalesce(cm.team_id, p.team_id) as team_id
      from profiles p
      left join club_membership cm on cm.user_id = p.id
       and cm.club_id = (select club_id from ev)
     where p.id = p_user
  ),
  exc_persona as (
    select desde_ts, hasta_ts from venta_excepcion
     where evento_id = p_evento and user_id = p_user
     order by hasta_ts desc nulls last limit 1
  ),
  exc_team as (
    select x.desde_ts, x.hasta_ts from venta_excepcion x
     where x.evento_id = p_evento
       and x.team_id is not null
       and x.team_id = (select team_id from mi_team)
     order by x.hasta_ts desc nulls last limit 1
  )
  select case
    when exists (select 1 from exc_persona) then
      (select jsonb_build_object('desde', desde_ts, 'hasta', hasta_ts, 'origen', 'persona') from exc_persona)
    when exists (select 1 from exc_team) then
      (select jsonb_build_object('desde', desde_ts, 'hasta', hasta_ts, 'origen', 'team') from exc_team)
    else
      (select jsonb_build_object('desde', manilla_desde, 'hasta', manilla_hasta_ts, 'origen', 'evento') from ev)
  end
  where exists (select 1 from ev);
$$;


/* excepciones_venta(p_evento) -> filas
 *
 * Las excepciones de horario del evento, con el nombre resuelto según el
 * tipo. Verificado contra 3 eventos reales (1, 2 y 3 filas):
 *   tipo   = 'team' si team_id no es null, si no 'persona'
 *   nombre = teams.nombre o profiles.nombre según el tipo
 *   orden  = teams primero, y por nombre dentro de cada tipo (la
 *            secuencia real Team AQ, Team CD, persona coincide; created_at
 *            quedó descartado con el caso HOLIDAY)
 */
create or replace function excepciones_venta(p_evento uuid)
returns table (
  id       uuid,
  nota     text,
  tipo     text,
  nombre   text,
  team_id  uuid,
  user_id  uuid,
  desde_ts timestamptz,
  hasta_ts timestamptz
)
language sql
stable
security definer
set search_path = public
as $$
  select x.id,
         x.nota,
         case when x.team_id is not null then 'team' else 'persona' end as tipo,
         coalesce(t.nombre, p.nombre) as nombre,
         x.team_id,
         x.user_id,
         x.desde_ts,
         x.hasta_ts
    from venta_excepcion x
    left join teams t on t.id = x.team_id
    left join profiles p on p.id = x.user_id
   where x.evento_id = p_evento
   order by (x.team_id is null), coalesce(t.nombre, p.nombre);
$$;


/* cupos_fase(p_fase) -> filas {cupo, team, quedan, team_id, vendidas}
 *
 * Cuánto vendió cada team en una fase y su cupo propio si lo tiene.
 * Verificado contra las 3 fases reales de Aniversario Bowie (10 filas
 * cada una): los 10 teams ACTIVOS del club del evento, orden por nombre,
 * y vendidas contadas por el team EFECTIVO del vendedor en ese club
 * (misma regla verificada de 02a: Team AQ 6 · Team S 21 · Team SM 3
 * cierran exacto contra las respuestas reales).
 *
 * cupo / quedan: en TODOS los datos reales son null (nunca se configuró
 * un cupo por team). La tabla de almacenamiento es deducida
 * (fase_cupo_team, arriba) — si algún día el original devuelve cupos no
 * nulos, re-verificar contra eso.
 */
create or replace function cupos_fase(p_fase uuid)
returns table (
  cupo     int,
  team     text,
  quedan   int,
  team_id  uuid,
  vendidas bigint
)
language sql
stable
security definer
set search_path = public
as $$
  with ctx as (
    select f.id as fase_id, e.club_id
      from evento_fase f join eventos e on e.id = f.evento_id
     where f.id = p_fase
  ),
  ventas as (
    select coalesce(
             cm.team_id,
             case when tb.id is not null
                       and (p.rol = 'admin'
                            or tb.clubs is null or coalesce(array_length(tb.clubs, 1), 0) = 0
                            or (select club_id from ctx) = any(tb.clubs))
                  then p.team_id
             end
           ) as team_ef
      from entradas x
      join profiles p on p.id = x.rrpp_id
      left join club_membership cm on cm.user_id = p.id and cm.club_id = (select club_id from ctx)
      left join teams tb on tb.id = p.team_id
     where x.fase_id = p_fase
  )
  select fc.cupo,
         t.nombre as team,
         case when fc.cupo is null then null
              else fc.cupo - coalesce(v.vendidas, 0)::int end as quedan,
         t.id as team_id,
         coalesce(v.vendidas, 0) as vendidas
    from teams t
    left join fase_cupo_team fc on fc.fase_id = (select fase_id from ctx) and fc.team_id = t.id
    left join (select team_ef, count(*) as vendidas from ventas group by team_ef) v on v.team_ef = t.id
   where t.activo
     and (t.clubs is null or coalesce(array_length(t.clubs, 1), 0) = 0
          or (select club_id from ctx) = any(t.clubs))
   order by t.nombre;
$$;
