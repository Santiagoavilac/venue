-- ACCESO A LA EXPORTACIÓN CONTABLE (2026-08-21)
--
-- Regla pedida por el dueño:
--   · contabilidad GENERAL (todos los teams): SOLO @aqueirolo y
--     @IpadQueirolo. Horacio NO, aunque su rol también sea admin.
--   · cada JEFE de team: su propio team y nada más.
--   · el resto (rrpp, portero, caja, admin sin marca): nada.
--
-- POR QUÉ UNA COLUMNA Y NO UNA LISTA DE USUARIOS EN EL CÓDIGO:
-- los tres admins son rol='admin' — el rol no alcanza para distinguirlos.
-- Clavar 'aqueirolo'/'IpadQueirolo' en el JS sería frágil (el usuario
-- visible se puede editar) y obligaría a tocar código para dar o quitar el
-- permiso. La marca vive en la base, igual que admin_principal.
alter table profiles add column if not exists contabilidad_total boolean not null default false;

comment on column profiles.contabilidad_total is
  'Puede exportar la contabilidad de TODOS los teams. Los jefes exportan '
  'solo su team sin esta marca. Se gestiona desde la base, no desde la app.';

-- Las dos cuentas autorizadas. Por USUARIO (estable), no por nombre.
update profiles set contabilidad_total = true
 where usuario in ('aqueirolo', 'IpadQueirolo');

-- Cualquier otra queda explícitamente fuera (incluye horacio01 y futuros
-- admins: el permiso se da a mano, no se hereda del rol).
update profiles set contabilidad_total = false
 where usuario not in ('aqueirolo', 'IpadQueirolo') and contabilidad_total;


/* contabilidad_evento(p_evento) -> json
 *
 * ÚNICA puerta de entrada a los datos del libro. Existe porque la app NO
 * puede ser la que filtre: `v_stats_rrpp` no es security_invoker (corre
 * con los permisos de su dueño y saltea RLS), así que hoy un jefe que la
 * consulta directo ve las 240 filas de los 13 teams y la liquidación
 * entera del evento. Filtrar sólo en el navegador dejaría esos datos
 * viajando igual, y se leen desde la consola.
 *
 * Acá el filtro es del lado del servidor y depende de auth.uid():
 *   · contabilidad_total  -> todos los teams + la liquidación del evento.
 *   · rol 'jefe'          -> SOLO su team; sin cifras globales del evento
 *                            (manillas_usadas/externas del evento entero no
 *                            son suyas: se devuelven las de SU team).
 *   · cualquier otro      -> excepción, no una respuesta vacía: el pedido
 *                            explícito tiene que fallar claro.
 *
 * El team del jefe es el EFECTIVO del club del evento, la misma regla que
 * ya usa v_stats_rrpp (club_membership manda sobre el team base).
 */
create or replace function contabilidad_evento(p_evento uuid)
returns json
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_uid   uuid := auth.uid();
  v_rol   text;
  v_total boolean;
  v_team  uuid;
  v_club  text;
  v_filas json;
  v_liq   json;
begin
  if v_uid is null then
    raise exception 'No autenticado.';
  end if;

  select rol, contabilidad_total into v_rol, v_total
    from profiles where id = v_uid;

  if v_rol is null then
    raise exception 'Perfil inexistente.';
  end if;

  if not v_total and v_rol <> 'jefe' then
    raise exception 'No autorizado para exportar la contabilidad.';
  end if;

  select club_id into v_club from eventos where id = p_evento;
  if v_club is null then
    raise exception 'Evento inexistente.';
  end if;

  if v_total then
    /* --- contabilidad GENERAL --- */
    select json_agg(json_build_object(
             'rrpp_id',   s.rrpp_id,
             'rrpp',      s.rrpp,
             'team_id',   s.team_id,
             'team',      t.nombre,
             'jefe',      (select p2.nombre from profiles p2
                            where p2.team_id = s.team_id and p2.rol = 'jefe'
                            order by p2.nombre limit 1),
             'prepagadas', s.entradas_usadas,
             'lista',      s.ingresaron))
      into v_filas
      from v_stats_rrpp s
      left join teams t on t.id = s.team_id
     where s.evento_id = p_evento
       and (s.entradas_usadas > 0 or s.ingresaron > 0);

    select liquidacion_evento(p_evento) into v_liq;
    return json_build_object(
      'alcance', 'total',
      'team',    null,
      'filas',   coalesce(v_filas, '[]'::json),
      'liq',     v_liq);
  end if;

  /* --- JEFE: sólo su team --- */
  select s.team_id into v_team
    from v_stats_rrpp s
   where s.evento_id = p_evento and s.rrpp_id = v_uid;

  if v_team is null then
    raise exception 'Sin team asignado en este evento.';
  end if;

  select json_agg(json_build_object(
           'rrpp_id',   s.rrpp_id,
           'rrpp',      s.rrpp,
           'team_id',   s.team_id,
           'team',      t.nombre,
           'jefe',      (select p2.nombre from profiles p2
                          where p2.team_id = s.team_id and p2.rol = 'jefe'
                          order by p2.nombre limit 1),
           'prepagadas', s.entradas_usadas,
           'lista',      s.ingresaron))
    into v_filas
    from v_stats_rrpp s
    left join teams t on t.id = s.team_id
   where s.evento_id = p_evento
     and s.team_id = v_team
     and (s.entradas_usadas > 0 or s.ingresaron > 0);

  /* Mismos parámetros de cálculo (precio y % son del evento, no secretos),
     pero las CANTIDADES son las de su team: manillas_usadas del evento
     entero no le corresponde. Las manillas de externos son un ajuste
     global del boliche: no se reparten por team, van en 0. */
  select json_build_object(
           'precio_manilla',    e.precio_manilla,
           'por_manilla',       (e.precio_manilla * e.pct_boliche / 100.0),
           'manillas_externas', 0,
           'manillas_usadas',   coalesce((select sum(s.entradas_usadas) from v_stats_rrpp s
                                           where s.evento_id = p_evento and s.team_id = v_team), 0),
           'manillas_netas',    coalesce((select sum(s.entradas_usadas) from v_stats_rrpp s
                                           where s.evento_id = p_evento and s.team_id = v_team), 0))
    into v_liq
    from eventos e where e.id = p_evento;

  return json_build_object(
    'alcance', 'team',
    'team',    (select nombre from teams where id = v_team),
    'filas',   coalesce(v_filas, '[]'::json),
    'liq',     v_liq);
end;
$$;

revoke all on function contabilidad_evento(uuid) from public, anon;
grant execute on function contabilidad_evento(uuid) to authenticated;

notify pgrst, 'reload schema';
