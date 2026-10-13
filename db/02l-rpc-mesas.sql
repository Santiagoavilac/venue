-- RPCs de MESAS · vender, vender en grupo, editar, pagar, estado, liberar
-- reservas vencidas, heredar y copiar planimetría.
--
-- ETAPA 1: paridad. Nada de mejoras acá.
--
-- REGLA DURA: ninguna se ejecutó contra el origen. Evidencia (2026-08-20,
-- sobre las 235 mesas reales):
--
-- · PRECIO = combo.precio × combo_qty AL MOMENTO de vender (los 51 casos
--   que hoy no calzan con el precio actual del combo son ventas viejas:
--   el combo cambió de precio después y la mesa conservó el suyo).
-- · GRUPOS (11 reales): UNA primaria con el precio total; las secundarias
--   en 0 pero con el MISMO combo_id, cliente, estado y vendedor
--   (0 inconsistencias). La primaria es la mesa desde la que se vendió.
-- · PAGADAS: pagada_at ⇔ pagada_por (136/136 juntos desde Friends; los
--   viejos sin esos campos son de antes de la feature). El admin que vende
--   o cobra deja pago_verificado=true con verificado_por/at; el resto queda
--   por verificar.
-- · DISPONIBLES: 61/61 completamente limpias ⇒ liberar borra TODO el
--   estado de venta (cliente, combo, precio, grupo, botellas, manillas,
--   reserva, pago, comprobante, cortesía, cargada_por).
-- · cargada_por = quien llama (20 filas recientes: 10 propias y 10 de
--   admin cargando a nombre de otro); vendido_por = coalesce(a_nombre_de,
--   quien llama).
-- · CORTESÍAS (4 reales): precio 0, combo conservado, cortesia=true,
--   cortesia_por = quien llama.
-- · RESERVAS: reserva_vence_at lo fija la base al reservar (el comentario
--   del cliente lo afirma; la única reservada actual no tiene timestamps
--   porque viene de un rechazo de verificar_mesa, que no los toca).
-- · HERENCIA: las 20 mesas de Aniversario calcan etiqueta/planta/categoría/
--   x/y/w/h/team_id de HOLIDAY (20/20) y nacen disponibles.
--
-- SUPUESTOS (documentados): textos de error; que permite_reserva=false
-- rechaza reservas y permite_agrupar=false rechaza grupos (la config lo
-- promete, la UI lo esconde; sin datos en contra); permisos de editar_mesa
-- ("quien la vendió, su jefe, o el admin" — el comentario del cliente
-- afirma que el RPC lo rebota).


/* helper interno: limpiar una mesa (visto en las 61 disponibles) */
create or replace function mesa_limpiar(p_mesa uuid)
returns void
language sql
volatile
as $$
  update mesas set
    estado = 'disponible', cliente = null, combo_id = null, botellas = '{}',
    manillas = 0, precio = null, vendido_por = null, grupo_id = null,
    combo_qty = 1, pagada_por = null, pagada_at = null, reservada_at = null,
    comprobante_url = null, pago_verificado = false, verificado_por = null,
    verificado_at = null, metodo_pago = null, reserva_vence_at = null,
    cortesia = false, cortesia_por = null, cargada_por = null,
    updated_at = now()
  where id = p_mesa;
$$;


/* vender_mesa(...) -> json {etiqueta, precio}
 *
 * p_estado: 'reservada' (fija reservada_at=now() y reserva_vence_at =
 * now() + horas_reserva del evento) o 'pagada' (pagada_at/por; admin deja
 * verificada, el resto por verificar). Cortesía: precio 0, conserva combo.
 * Sin combo (combo_obligatorio=false): precio 0.
 */
create or replace function vender_mesa(
  p_mesa uuid, p_cliente text, p_combo uuid, p_botellas text[],
  p_manillas int, p_estado text, p_cantidad int default 1,
  p_comprobante text default null, p_efectivo boolean default false,
  p_a_nombre_de uuid default null, p_cortesia boolean default false)
returns json
language plpgsql
volatile
security definer
set search_path = public
as $$
declare
  m mesas%rowtype;
  e eventos%rowtype;
  c combos%rowtype;
  v_rol text;
  v_precio numeric := 0;
  v_qty int := greatest(coalesce(p_cantidad, 1), 1);
begin
  select * into m from mesas where id = p_mesa;
  if not found then raise exception 'Mesa no encontrada'; end if;      -- TEXTO SUPUESTO
  if m.estado <> 'disponible' then
    raise exception 'La mesa % ya está vendida', m.etiqueta;           -- TEXTO SUPUESTO
  end if;
  select * into e from eventos where id = m.evento_id;

  select coalesce(cm.rol, p.rol) into v_rol
    from profiles p
    left join club_membership cm on cm.user_id = p.id and cm.club_id = e.club_id
   where p.id = auth.uid();

  if p_estado = 'reservada' and e.permite_reserva = false then
    raise exception 'En este evento las mesas se venden solo pagadas';  -- TEXTO SUPUESTO
  end if;
  if p_a_nombre_de is not null and p_a_nombre_de is distinct from auth.uid()
     and v_rol not in ('jefe', 'admin') then
    raise exception 'No podés cargar la mesa a nombre de otra persona'; -- TEXTO SUPUESTO
  end if;
  if p_cortesia and v_rol not in ('jefe', 'admin') then
    raise exception 'No podés registrar cortesías';                     -- TEXTO SUPUESTO
  end if;

  if p_combo is not null then
    select * into c from combos where id = p_combo;
    if not found then raise exception 'Combo no encontrado'; end if;    -- TEXTO SUPUESTO
    v_precio := c.precio * v_qty;
  end if;
  if p_cortesia then v_precio := 0; end if;

  update mesas set
    estado = p_estado,
    cliente = trim(p_cliente),
    combo_id = p_combo,
    combo_qty = v_qty,
    botellas = coalesce(p_botellas, '{}'),
    manillas = coalesce(p_manillas, 0),
    precio = v_precio,
    vendido_por = coalesce(p_a_nombre_de, auth.uid()),
    cargada_por = auth.uid(),
    cortesia = p_cortesia,
    cortesia_por = case when p_cortesia then auth.uid() end,
    reservada_at = case when p_estado = 'reservada' then now() end,
    reserva_vence_at = case when p_estado = 'reservada'
                            then now() + make_interval(hours => coalesce(e.horas_reserva, 3)) end,
    pagada_at = case when p_estado = 'pagada' then now() end,
    pagada_por = case when p_estado = 'pagada' then auth.uid() end,
    metodo_pago = case when p_estado = 'pagada'
                       then case when p_efectivo then 'efectivo' else 'transferencia' end end,
    comprobante_url = case when p_estado = 'pagada' then p_comprobante end,
    pago_verificado = (p_estado = 'pagada' and v_rol = 'admin'),
    verificado_por = case when p_estado = 'pagada' and v_rol = 'admin' then auth.uid() end,
    verificado_at = case when p_estado = 'pagada' and v_rol = 'admin' then now() end,
    updated_at = now()
  where id = p_mesa;

  return json_build_object('etiqueta', m.etiqueta, 'precio', v_precio);
end;
$$;


/* vender_mesa_grupo(p_mesas uuid[], ...) -> json {mesas, precio, primaria}
 * La PRIMERA mesa del array es la primaria (lleva el precio, las manillas
 * y el comprobante); las demás quedan en 0 con el mismo combo, cliente,
 * estado y vendedor (estructura verificada en los 11 grupos reales). Si el
 * evento cobra el combo POR MESA (combo_por_mesa), el precio de la
 * primaria es combo × qty × cantidad de mesas.
 */
create or replace function vender_mesa_grupo(
  p_mesas uuid[], p_cliente text, p_combo uuid, p_botellas text[],
  p_manillas int, p_estado text, p_cantidad int default 1,
  p_comprobante text default null, p_efectivo boolean default false,
  p_a_nombre_de uuid default null, p_cortesia boolean default false)
returns json
language plpgsql
volatile
security definer
set search_path = public
as $$
declare
  v_prim uuid := p_mesas[1];
  v_grupo uuid := gen_random_uuid();
  v_resp json;
  v_etiquetas text[];
  e eventos%rowtype;
  v_id uuid;
  v_precio numeric;
begin
  if coalesce(array_length(p_mesas, 1), 0) < 1 then
    raise exception 'Sin mesas para vender';                            -- TEXTO SUPUESTO
  end if;
  select e2.* into e from eventos e2 join mesas m on m.evento_id = e2.id where m.id = v_prim;
  if e.permite_agrupar = false and array_length(p_mesas, 1) > 1 then
    raise exception 'En este evento cada mesa se vende sola';           -- TEXTO SUPUESTO
  end if;
  foreach v_id in array p_mesas loop
    if exists (select 1 from mesas where id = v_id and estado <> 'disponible') then
      raise exception 'Una de las mesas ya está vendida';               -- TEXTO SUPUESTO
    end if;
  end loop;

  -- la primaria se vende con la lógica normal (combo por mesa: × número de mesas)
  v_resp := vender_mesa(v_prim, p_cliente, p_combo, p_botellas, p_manillas,
                        p_estado,
                        case when e.combo_por_mesa then coalesce(p_cantidad, 1) * array_length(p_mesas, 1)
                             else p_cantidad end,
                        p_comprobante, p_efectivo, p_a_nombre_de, p_cortesia);
  v_precio := (v_resp->>'precio')::numeric;

  -- todas (primaria incluida) comparten grupo; las secundarias en 0
  update mesas set grupo_id = v_grupo, updated_at = now() where id = any(p_mesas);
  update mesas m set
    estado = p_estado, cliente = trim(p_cliente), combo_id = p_combo, combo_qty = 1,
    botellas = '{}', manillas = 0, precio = 0,
    vendido_por = coalesce(p_a_nombre_de, auth.uid()), cargada_por = auth.uid(),
    cortesia = p_cortesia, cortesia_por = case when p_cortesia then auth.uid() end,
    reservada_at = case when p_estado = 'reservada' then now() end,
    reserva_vence_at = (select reserva_vence_at from mesas where id = v_prim),
    pagada_at = (select pagada_at from mesas where id = v_prim),
    pagada_por = (select pagada_por from mesas where id = v_prim),
    metodo_pago = (select metodo_pago from mesas where id = v_prim),
    pago_verificado = (select pago_verificado from mesas where id = v_prim),
    verificado_por = (select verificado_por from mesas where id = v_prim),
    verificado_at = (select verificado_at from mesas where id = v_prim),
    updated_at = now()
  where m.id = any(p_mesas) and m.id <> v_prim;

  select array_agg(etiqueta order by etiqueta) into v_etiquetas from mesas where id = any(p_mesas);
  return json_build_object('mesas', to_json(v_etiquetas), 'precio', v_precio, 'primaria', v_prim);
end;
$$;


/* editar_mesa(p_mesa, p_cliente, p_combo) -> json {etiqueta, precio}
 * Cambia cliente y combo sin liberar. El precio se recalcula con el precio
 * ACTUAL del combo × la cantidad existente (la UI lo avisa: "si cambiás el
 * combo se recalcula el precio"). En un grupo, cliente y combo cambian en
 * todas y el precio solo en la primaria. Permiso: quien la vendió, su jefe
 * (efectivo del club) o admin. */
create or replace function editar_mesa(p_mesa uuid, p_cliente text, p_combo uuid)
returns json
language plpgsql
volatile
security definer
set search_path = public
as $$
declare
  m mesas%rowtype;
  prim mesas%rowtype;
  e eventos%rowtype;
  c combos%rowtype;
  v_rol text; v_team uuid; v_team_vendedor uuid;
  v_precio numeric := 0;
begin
  select * into m from mesas where id = p_mesa;
  if not found then raise exception 'Mesa no encontrada'; end if;
  select * into e from eventos where id = m.evento_id;
  if m.grupo_id is not null then
    select * into prim from mesas where grupo_id = m.grupo_id and coalesce(precio, 0) > 0 limit 1;
  end if;
  if prim.id is null then prim := m; end if;

  select coalesce(cm.rol, p.rol),
         coalesce(cm.team_id, case when tb.id is not null and (p.rol='admin' or tb.clubs is null
             or coalesce(array_length(tb.clubs,1),0)=0 or e.club_id = any(tb.clubs)) then p.team_id end)
    into v_rol, v_team
    from profiles p
    left join club_membership cm on cm.user_id = p.id and cm.club_id = e.club_id
    left join teams tb on tb.id = p.team_id
   where p.id = auth.uid();
  select coalesce(cm.team_id, case when tb.id is not null and (p.rol='admin' or tb.clubs is null
             or coalesce(array_length(tb.clubs,1),0)=0 or e.club_id = any(tb.clubs)) then p.team_id end)
    into v_team_vendedor
    from profiles p
    left join club_membership cm on cm.user_id = p.id and cm.club_id = e.club_id
    left join teams tb on tb.id = p.team_id
   where p.id = prim.vendido_por;

  if v_rol is distinct from 'admin'
     and prim.vendido_por is distinct from auth.uid()
     and not (v_rol = 'jefe' and v_team is not null and v_team = v_team_vendedor) then
    raise exception 'No podés editar esta mesa';                        -- TEXTO SUPUESTO
  end if;

  if p_combo is not null then
    select * into c from combos where id = p_combo;
    if not found then raise exception 'Combo no encontrado'; end if;
    v_precio := c.precio * coalesce(prim.combo_qty, 1);
  end if;
  if prim.cortesia then v_precio := 0; end if;

  if m.grupo_id is not null then
    update mesas set cliente = trim(p_cliente), combo_id = p_combo, updated_at = now()
     where grupo_id = m.grupo_id;
    update mesas set precio = v_precio, updated_at = now() where id = prim.id;
  else
    update mesas set cliente = trim(p_cliente), combo_id = p_combo, precio = v_precio,
                     updated_at = now()
     where id = prim.id;
  end if;
  return json_build_object('etiqueta', prim.etiqueta, 'precio', v_precio);
end;
$$;


/* pagar_mesa(p_mesa, p_url, p_efectivo) -> void
 * Reservada (u ocupada) pasa a pagada. La plata queda en la primaria del
 * grupo; el estado cambia en todo el grupo. Admin deja verificado. */
create or replace function pagar_mesa(p_mesa uuid, p_url text default null, p_efectivo boolean default false)
returns void
language plpgsql
volatile
security definer
set search_path = public
as $$
declare
  m mesas%rowtype;
  prim uuid;
  v_rol text;
begin
  select * into m from mesas where id = p_mesa;
  if not found then raise exception 'Mesa no encontrada'; end if;
  select coalesce(cm.rol, p.rol) into v_rol
    from profiles p
    join eventos e on e.id = m.evento_id
    left join club_membership cm on cm.user_id = p.id and cm.club_id = e.club_id
   where p.id = auth.uid();

  prim := m.id;
  if m.grupo_id is not null then
    select id into prim from mesas where grupo_id = m.grupo_id and coalesce(precio, 0) > 0 limit 1;
    update mesas set estado = 'pagada', updated_at = now() where grupo_id = m.grupo_id;
  else
    update mesas set estado = 'pagada', updated_at = now() where id = m.id;
  end if;

  update mesas set
    pagada_at = now(), pagada_por = auth.uid(),
    metodo_pago = case when p_efectivo then 'efectivo' else 'transferencia' end,
    comprobante_url = coalesce(p_url, comprobante_url),
    pago_verificado = (v_rol = 'admin'),
    verificado_por = case when v_rol = 'admin' then auth.uid() end,
    verificado_at = case when v_rol = 'admin' then now() end,
    updated_at = now()
  where id = coalesce(prim, m.id);
end;
$$;


/* estado_mesa(p_mesa, p_estado) -> void
 * 'ocupada': marca que llegaron (conserva toda la venta — evidencia: la
 * ocupada real de HOLIDAY mantiene precio, combo y comisión).
 * 'disponible': LIBERA la mesa — y todo su grupo — limpiando todos los
 * campos de venta (evidencia: las 61 disponibles están impecables). */
create or replace function estado_mesa(p_mesa uuid, p_estado text)
returns void
language plpgsql
volatile
security definer
set search_path = public
as $$
declare
  m mesas%rowtype;
  v_id uuid;
begin
  select * into m from mesas where id = p_mesa;
  if not found then raise exception 'Mesa no encontrada'; end if;
  if p_estado = 'disponible' then
    if m.grupo_id is not null then
      for v_id in select id from mesas where grupo_id = m.grupo_id loop
        perform mesa_limpiar(v_id);
      end loop;
    else
      perform mesa_limpiar(m.id);
    end if;
  else
    if m.grupo_id is not null then
      update mesas set estado = p_estado, updated_at = now() where grupo_id = m.grupo_id;
    else
      update mesas set estado = p_estado, updated_at = now() where id = m.id;
    end if;
  end if;
end;
$$;


/* liberar_reservas_vencidas(p_evento) -> json {liberadas: [{etiqueta, vendido_por}]}
 * Barre las reservas cuyo plazo venció (reserva_vence_at, o reservada_at +
 * horas_reserva si el vencimiento no viajó) y las libera con la misma
 * limpieza total. Devuelve qué liberó para el aviso del cliente. */
create or replace function liberar_reservas_vencidas(p_evento uuid)
returns json
language plpgsql
volatile
security definer
set search_path = public
as $$
declare
  v_filas json;
  r record;
begin
  select coalesce(json_agg(json_build_object('etiqueta', x.etiqueta, 'vendido_por', x.vendido_por)), '[]'::json)
    into v_filas
    from mesas x
    join eventos e on e.id = x.evento_id
   where x.evento_id = p_evento
     and x.estado = 'reservada'
     and coalesce(x.reserva_vence_at,
                  x.reservada_at + make_interval(hours => coalesce(e.horas_reserva, 3))) < now();
  for r in
    select x.id from mesas x
    join eventos e on e.id = x.evento_id
    where x.evento_id = p_evento and x.estado = 'reservada'
      and coalesce(x.reserva_vence_at,
                   x.reservada_at + make_interval(hours => coalesce(e.horas_reserva, 3))) < now()
  loop
    perform mesa_limpiar(r.id);
  end loop;
  return json_build_object('liberadas', v_filas);
end;
$$;


/* heredar_mesas(p_hacia) -> int
 * Copia el plano (etiqueta, planta, categoría, posición, tamaño, team) del
 * evento más reciente del MISMO club hacia el evento nuevo, como mesas
 * disponibles. Evidencia: las 20 de Aniversario calcan HOLIDAY 20/20. */
create or replace function heredar_mesas(p_hacia uuid)
returns int
language plpgsql
volatile
security definer
set search_path = public
as $$
declare
  v_club text;
  v_desde uuid;
  v_n int := 0;
begin
  select club_id into v_club from eventos where id = p_hacia;
  select e.id into v_desde
    from eventos e
   where e.club_id = v_club and e.id <> p_hacia
     and exists (select 1 from mesas m where m.evento_id = e.id)
   order by e.fecha desc
   limit 1;
  if v_desde is null then return 0; end if;
  insert into mesas (id, evento_id, planta, etiqueta, categoria, x, y, w, h, team_id,
                     estado, botellas, manillas, combo_qty, pago_verificado, cortesia, updated_at)
  select gen_random_uuid(), p_hacia, planta, etiqueta, categoria, x, y, w, h, team_id,
         'disponible', '{}', 0, 1, false, false, now()
    from mesas where evento_id = v_desde;
  get diagnostics v_n = row_count;
  return v_n;
end;
$$;


/* copiar_mesas(p_desde, p_hacia) -> int
 * Igual que heredar pero con el evento de origen elegido a mano. */
create or replace function copiar_mesas(p_desde uuid, p_hacia uuid)
returns int
language plpgsql
volatile
security definer
set search_path = public
as $$
declare v_n int := 0;
begin
  insert into mesas (id, evento_id, planta, etiqueta, categoria, x, y, w, h, team_id,
                     estado, botellas, manillas, combo_qty, pago_verificado, cortesia, updated_at)
  select gen_random_uuid(), p_hacia, planta, etiqueta, categoria, x, y, w, h, team_id,
         'disponible', '{}', 0, 1, false, false, now()
    from mesas where evento_id = p_desde;
  get diagnostics v_n = row_count;
  return v_n;
end;
$$;
