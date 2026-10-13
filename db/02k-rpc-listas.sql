-- RPCs de LISTAS · registrar_lista, eliminar_registro, heredar_cupos_lista.
--
-- ETAPA 1: paridad. Nada de mejoras acá.
--
-- REGLA DURA: ninguna se ejecutó contra el origen. Evidencia (2026-08-20,
-- sobre los 5.049 registros reales):
--
-- · DUPLICADOS: NO se bloquean. Todos los eventos tienen decenas de
--   duplicados EXACTOS ("Mariana Mendoza" dos veces en Now You See Me,
--   etc.). `duplicados` en la respuesta es solo el AVISO de qué nombres ya
--   estaban en el evento; las filas se insertan igual.
-- · CUPOS (por rrpp/jefe/admin, especiales y cupo_total): NO se validan en
--   el servidor — 51 violaciones reales repartidas en TODA la historia
--   (28 en ROAR del 01/08: rrpps comunes con 2 anotados y cupo 1; jefes
--   con 16/5 y 18/5). El "N/M tuyos" del cliente es informativo.
--   MEJORA PENDIENTE anotada, no implementada.
-- · VENTANA registro_desde/hasta: SÍ se valida, con bypass de ADMIN — los
--   únicos 3 registros post-cierre en 24 listas con ventana son de admin
--   (Friends, 04:48 vs cierre 03:30). Miles de registros dentro. (Dos
--   casos pre-apertura en In The Dark parecen edición retroactiva de la
--   ventana: quedan anotados como no concluyentes.)
-- · cargado_por: null en los 5.049 — el "a nombre de" nunca se usó en
--   listas. Se escribe auth.uid() solo cuando p_a_nombre_de difiere del
--   que llama (el hint del cliente lo promete: "Se guarda que los
--   anotaste vos") — SUPUESTO consistente con los 5.049 nulls.
-- · HERENCIA de cupos especiales: isabella (cupo 7 en "Invitados")
--   aparece encadenada por club: ROAR→HOLIDAY→Aniversario en bowie y
--   Last Dance→NYSM en burtown ⇒ se copia de la lista homónima más
--   reciente DEL MISMO CLUB.
--
-- SUPUESTOS (documentados): textos de error; comparación de duplicados
-- insensible a mayúsculas/acentos (misma vara que buscar_registros); el
-- permiso de p_a_nombre_de (jefe/admin efectivos — el cliente lo afirma
-- para mesas: "La base lo vuelve a validar igual", y para listas dice
-- "lo mismo que ya rige para las mesas").


/* registrar_lista(p_lista, p_nombres, p_a_nombre_de default null) -> json
 *
 * Anota un lote de nombres en una lista. Respuesta que consume el cliente:
 *   { insertados: n, duplicados: [nombres que YA estaban en el evento],
 *     a_nombre_de: nombre del dueño elegido o null }
 *
 * - rrpp_id = p_a_nombre_de ?? quien llama; cargado_por = quien llama solo
 *   si anotó para otro.
 * - Ventana de la lista: rechaza fuera de [registro_desde, registro_hasta]
 *   salvo para admin (rol efectivo del club del evento).
 * - Duplicados: se detectan contra los registros PREVIOS del evento
 *   (insensible a mayúsculas y acentos) y se informan; se inserta igual.
 * - Cupos: NO se validan (evidencia arriba).
 */
create or replace function registrar_lista(p_lista uuid, p_nombres text[], p_a_nombre_de uuid default null)
returns json
language plpgsql
volatile
security definer
set search_path = public
as $$
declare
  lt lista_tipos%rowtype;
  e eventos%rowtype;
  v_rol text;
  v_duenio uuid;
  v_duenio_nombre text;
  v_nombre text;
  v_insertados int := 0;
  v_dups text[] := '{}';
begin
  select * into lt from lista_tipos where id = p_lista;
  if not found then
    raise exception 'Lista no encontrada';   -- TEXTO SUPUESTO
  end if;
  select * into e from eventos where id = lt.evento_id;

  select coalesce(cm.rol, p.rol) into v_rol
    from profiles p
    left join club_membership cm on cm.user_id = p.id and cm.club_id = e.club_id
   where p.id = auth.uid();

  -- ventana de anotación (admin exento: los 3 post-cierre reales son admin)
  if v_rol is distinct from 'admin' then
    if lt.registro_desde is not null and now() < lt.registro_desde then
      raise exception 'Esta lista todavía no abre para anotar';   -- TEXTO SUPUESTO
    end if;
    if lt.registro_hasta is not null and now() > lt.registro_hasta then
      raise exception 'Esta lista ya cerró para anotar';          -- TEXTO SUPUESTO
    end if;
  end if;

  -- a nombre de otro: jefe o admin (efectivos del club del evento)
  v_duenio := coalesce(p_a_nombre_de, auth.uid());
  if v_duenio is distinct from auth.uid() then
    if v_rol not in ('jefe', 'admin') then
      raise exception 'No podés anotar a nombre de otra persona';  -- TEXTO SUPUESTO
    end if;
    select nombre into v_duenio_nombre from profiles where id = v_duenio;
    if v_duenio_nombre is null then
      raise exception 'Persona no encontrada';                     -- TEXTO SUPUESTO
    end if;
  end if;

  foreach v_nombre in array p_nombres loop
    v_nombre := trim(v_nombre);
    continue when v_nombre = '';
    if exists (
      select 1 from registros r
       where r.evento_id = lt.evento_id
         and unaccent(lower(r.nombre)) = unaccent(lower(v_nombre))
         and r.created_at < now()          -- solo los previos a este lote
    ) then
      v_dups := v_dups || v_nombre;
    end if;
    insert into registros (id, evento_id, lista_tipo_id, nombre, rrpp_id, created_at, cargado_por)
    values (gen_random_uuid(), lt.evento_id, p_lista, v_nombre, v_duenio, now(),
            case when v_duenio is distinct from auth.uid() then auth.uid() end);
    v_insertados := v_insertados + 1;
  end loop;

  return json_build_object(
    'insertados', v_insertados,
    'duplicados', to_json(v_dups),
    'a_nombre_de', v_duenio_nombre
  );
end;
$$;


/* eliminar_registro(p_registro) -> void
 * Quita a alguien de la lista (borrado físico; se puede volver a anotar).
 * Permiso RECONSTRUIDO de la UI: admin o el dueño del registro (el ✕ solo
 * aparece para admin || rrpp_id === yo; el jefe no borra ajenos). */
create or replace function eliminar_registro(p_registro uuid)
returns void
language plpgsql
volatile
security definer
set search_path = public
as $$
declare
  r registros%rowtype;
  v_rol text;
begin
  select * into r from registros where id = p_registro;
  if not found then
    raise exception 'Registro no encontrado';   -- TEXTO SUPUESTO
  end if;
  select rol into v_rol from profiles where id = auth.uid();
  if v_rol is distinct from 'admin' and r.rrpp_id is distinct from auth.uid() then
    raise exception 'Solo quien lo anotó o un admin pueden eliminarlo';  -- TEXTO SUPUESTO
  end if;
  delete from registros where id = p_registro;
end;
$$;


/* heredar_cupos_lista(p_lista) -> int
 *
 * Copia los cupos especiales (cupo_rrpp) de la lista homónima más reciente
 * DEL MISMO CLUB hacia la lista nueva, y devuelve cuántos copió. Evidencia:
 * la cadena real de isabella (cupo 7 en "Invitados") por club:
 * bowie ROAR→HOLIDAY→Aniversario, burtown Last Dance→NYSM.
 *
 * "Más reciente" = mayor fecha de evento entre las anteriores con el mismo
 * nombre (comparación insensible a mayúsculas, como cupo_permanente que la
 * pantalla consulta con ilike). No pisa cupos ya existentes en la lista
 * destino. SUPUESTO: el desempate exacto si hubiera dos listas homónimas
 * en el mismo evento (no pasa en los datos).
 */
create or replace function heredar_cupos_lista(p_lista uuid)
returns int
language plpgsql
volatile
security definer
set search_path = public
as $$
declare
  lt lista_tipos%rowtype;
  v_club text;
  v_origen uuid;
  v_n int := 0;
begin
  select * into lt from lista_tipos where id = p_lista;
  if not found then return 0; end if;
  select club_id into v_club from eventos where id = lt.evento_id;

  select lt2.id into v_origen
    from lista_tipos lt2
    join eventos e2 on e2.id = lt2.evento_id
   where lt2.id <> p_lista
     and e2.club_id = v_club
     and lower(trim(lt2.nombre)) = lower(trim(lt.nombre))
   order by e2.fecha desc, lt2.orden desc
   limit 1;
  if v_origen is null then return 0; end if;

  insert into cupo_rrpp (lista_tipo_id, user_id, cupo)
  select p_lista, c.user_id, c.cupo
    from cupo_rrpp c
   where c.lista_tipo_id = v_origen
     and not exists (select 1 from cupo_rrpp c2
                      where c2.lista_tipo_id = p_lista and c2.user_id = c.user_id);
  get diagnostics v_n = row_count;
  return v_n;
end;
$$;
