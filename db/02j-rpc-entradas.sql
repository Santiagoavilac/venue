-- RPCs de ENTRADAS · generar, anular, eliminar.
--
-- ETAPA 1: paridad. Nada de mejoras acá.
--
-- REGLA DURA: ninguna se ejecutó contra el origen. Evidencia (2026-08-20,
-- sobre las 3.285 entradas reales):
--
-- · MANILLAS DE MESA (426): precio SIEMPRE 0, fase_id SIEMPRE null, y
--   rrpp_id = quien llama (no el vendedor de la mesa: hay manillas de
--   aqueirolo en una mesa vendida por IpadQueirolo — el que las cargó).
-- · TOPE POR MESA: NO se aplica en el servidor — 34 mesas reales superan
--   incluye_manillas×qty+extra (el "quedan N" es solo del cliente).
-- · VENTANA DE VENTA (manilla_desde/hasta + excepciones): NO se aplica en
--   el servidor — 76 emisiones reales fuera de ventana por rrpp/jefe/admin
--   comunes (54 en Last Dance, 14 HOLIDAY, 8 NYSM, todas post-cierre). La
--   ventana y ventana_venta son informativas para la UI.
-- · FASES: SÍ se aplican y son atómicas — los cupos reales quedaron en
--   30/30 y 50/50 exactos con venta concurrente. Cuando venta_por_fases,
--   TODA entrada suelta lleva fase (95/95 en Aniversario) con el precio de
--   SU fase; sin fase abierta no se vende (el botón del cliente se
--   deshabilita y el server tiene que validar igual para no pasar el cupo).
-- · PRECIO sin fases: el precio_manilla VIGENTE al generar (HOLIDAY tiene
--   16 entradas a 60 y 311 a 70: subieron el precio a mitad de venta y
--   cada entrada conservó el suyo).
--
-- SUPUESTOS (documentados): los TEXTOS de los errores de negocio (el
-- cliente muestra error.message tal cual; los reales no se pueden conocer
-- sin ejecutar el origen) y los permisos exactos de anular/eliminar
-- (reconstruidos de la UI y sus comentarios: "jefe no anula").


/* generar_entrada(p_evento, p_cliente, p_mesa default null) -> json
 *
 * Devuelve la fila completa de la entrada creada (el cliente hace
 * lastTk = {...data, estado:'valida'} y usa data.id, data.code, data.fase_id).
 *
 * Camino MESA (manilla de combo): precio 0, sin fase, sin validar tope
 * (evidencia arriba). rrpp_id = auth.uid().
 *
 * Camino SUELTA:
 *   - evento con venta_por_fases: exige fase vigente (con lock sobre la
 *     fila de la fase para que el cupo no se pase en concurrencia — los
 *     30/30 y 50/50 reales exigen esa atomicidad), respeta el cupo por
 *     team si está configurado (fase_cupo_team, tabla deducida), y toma
 *     precio y fase_id de la fase.
 *   - sin fases: precio = precio_manilla actual del evento.
 */
create or replace function generar_entrada(p_evento uuid, p_cliente text, p_mesa uuid default null)
returns json
language plpgsql
volatile
security definer
set search_path = public
as $$
declare
  e eventos%rowtype;
  f evento_fase%rowtype;
  fila entradas%rowtype;
  v_precio numeric;
  v_fase uuid;
  v_team uuid;
  v_vendidas int;
  v_cupo_team int;
begin
  select * into e from eventos where id = p_evento;
  if not found then
    raise exception 'Evento no encontrado';
  end if;

  if p_mesa is not null then
    if not exists (select 1 from mesas m where m.id = p_mesa and m.evento_id = p_evento) then
      raise exception 'Mesa no encontrada';
    end if;
    v_precio := 0; v_fase := null;
  elsif e.venta_por_fases then
    -- fase vigente, con lock: el cupo se decide en serie
    select * into f
      from evento_fase
     where evento_id = p_evento
       and activo
       and (desde is null or now() >= desde)
       and (hasta is null or now() <= hasta)
       and (cupo is null or cupo > (select count(*) from entradas x where x.fase_id = evento_fase.id))
     order by orden
     limit 1
     for update;
    if not found then
      raise exception 'No hay ninguna fase de venta abierta';   -- TEXTO SUPUESTO
    end if;

    -- cupo por team dentro de la fase (todos los cupos reales observados
    -- son null: esta rama nunca corrió con datos reales — tabla deducida)
    select coalesce(cm.team_id,
             case when tb.id is not null
                       and (p.rol = 'admin' or tb.clubs is null
                            or coalesce(array_length(tb.clubs, 1), 0) = 0
                            or e.club_id = any(tb.clubs))
                  then p.team_id end)
      into v_team
      from profiles p
      left join club_membership cm on cm.user_id = p.id and cm.club_id = e.club_id
      left join teams tb on tb.id = p.team_id
     where p.id = auth.uid();
    select fc.cupo into v_cupo_team from fase_cupo_team fc
     where fc.fase_id = f.id and fc.team_id = v_team;
    if v_cupo_team is not null then
      select count(*) into v_vendidas
        from entradas x
        join profiles p2 on p2.id = x.rrpp_id
        left join club_membership cm2 on cm2.user_id = p2.id and cm2.club_id = e.club_id
        left join teams tb2 on tb2.id = p2.team_id
       where x.fase_id = f.id
         and coalesce(cm2.team_id,
               case when tb2.id is not null
                         and (p2.rol = 'admin' or tb2.clubs is null
                              or coalesce(array_length(tb2.clubs, 1), 0) = 0
                              or e.club_id = any(tb2.clubs))
                    then p2.team_id end) = v_team;
      if v_vendidas >= v_cupo_team then
        raise exception 'CUPO AGOTADO: tu team ya vendió sus % de esta fase', v_cupo_team;  -- TEXTO SUPUESTO
      end if;
    end if;

    v_precio := f.precio; v_fase := f.id;
  else
    v_precio := e.precio_manilla; v_fase := null;
  end if;

  insert into entradas (id, evento_id, code, cliente, rrpp_id, precio, estado, created_at, mesa_id, fase_id)
  values (gen_random_uuid(), p_evento, gen_code_evento(p_evento), trim(p_cliente), auth.uid(),
          v_precio, 'valida', now(), p_mesa, v_fase)
  returning * into fila;
  return to_jsonb(fila);
end;
$$;


/* anular_entrada(p_entrada) -> json {code}
 *
 * Permiso: admin o el dueño (rrpp_id = quien llama) — "jefe no anula"
 * (comentario del cliente, app.js:862; permiso RECONSTRUIDO de la UI).
 * Solo sobre entradas 'valida' (la UI solo lo ofrece ahí; una usada
 * registra un ingreso real y se elimina, no se anula).
 * Invariante respetado: una anulada nunca tiene used_at.
 */
create or replace function anular_entrada(p_entrada uuid)
returns json
language plpgsql
volatile
security definer
set search_path = public
as $$
declare
  e entradas%rowtype;
  v_rol text;
begin
  select * into e from entradas where id = p_entrada;
  if not found then
    raise exception 'Entrada no encontrada';   -- TEXTO SUPUESTO
  end if;
  select rol into v_rol from profiles where id = auth.uid();
  if v_rol is distinct from 'admin' and e.rrpp_id is distinct from auth.uid() then
    raise exception 'Solo el vendedor o un admin pueden anular esta entrada';  -- TEXTO SUPUESTO
  end if;
  if e.estado <> 'valida' then
    raise exception 'Solo se puede anular una entrada válida (está %)', e.estado;  -- TEXTO SUPUESTO
  end if;
  update entradas set estado = 'anulada' where id = p_entrada;
  return json_build_object('code', e.code);
end;
$$;


/* eliminar_entrada(p_entrada) -> json {code}
 *
 * Borrado físico (el diálogo del cliente avisa que se pierde el registro
 * de ingreso). Permisos RECONSTRUIDOS de la UI:
 *   - admin: cualquiera (el ✕ de Entradas es solo admin, incluso usadas);
 *   - no admin: solo manillas de SU mesa (mesas.vendido_por = caller) en
 *     estado 'valida' (el ✕ de la ficha de mesa: editMan && estado valida).
 */
create or replace function eliminar_entrada(p_entrada uuid)
returns json
language plpgsql
volatile
security definer
set search_path = public
as $$
declare
  e entradas%rowtype;
  v_rol text;
  v_ok boolean;
begin
  select * into e from entradas where id = p_entrada;
  if not found then
    raise exception 'Entrada no encontrada';   -- TEXTO SUPUESTO
  end if;
  select rol into v_rol from profiles where id = auth.uid();
  v_ok := (v_rol = 'admin')
       or (e.mesa_id is not null and e.estado = 'valida'
           and exists (select 1 from mesas m where m.id = e.mesa_id and m.vendido_por = auth.uid()));
  if not v_ok then
    raise exception 'No podés eliminar esta entrada';   -- TEXTO SUPUESTO
  end if;
  delete from entradas where id = p_entrada;
  return json_build_object('code', e.code);
end;
$$;
