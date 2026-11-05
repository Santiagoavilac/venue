-- Tocar dos veces "Comprar" no crea dos pedidos, y la recarga tiene techo.
--
-- aftr_comprar y aftr_reservar_mesa no tenían nada que las hiciera idempotentes:
-- con el celular lento, dos toques -o un reintento de red del cliente, que la
-- app no controla- creaban dos órdenes. En entradas el daño es que el cupo queda
-- retenido dos veces y la persona ve dos pedidos sin saber cuál pagar; en mesas
-- la segunda falla, pero sólo porque hay un chequeo de "ya tenés una reserva
-- pendiente" que depende de que la primera haya terminado de escribirse.
--
-- La solución ya está probada en esta base: aftr_recargar_pulse y aftr_reventa
-- reciben un `client_key` que el cliente genera UNA vez por hoja de compra, y
-- la unicidad la pone la base. Se copia eso, con un advisory lock por
-- (persona, clave) para que dos llamadas simultáneas se ordenen en vez de
-- chocar contra el índice.
--
-- El parámetro va al final y con `default null`: las apps publicadas siguen
-- llamando con tres argumentos y funcionan igual que hoy, sin clave. Hay que
-- borrar y volver a crear porque agregar un parámetro con default sobre la
-- función existente dejaría dos versiones y las llamadas de tres argumentos
-- quedarían ambiguas.
--
-- Y aftr_recargar_pulse validaba el mínimo pero no el máximo: se podía dejar
-- pedido un QR de cualquier importe. Techo por recarga y por día.

-- ── 1 · la clave del cliente en la orden ──────────────────────────────
alter table public.aftr_ordenes add column if not exists client_key uuid;
comment on column public.aftr_ordenes.client_key is
  'Clave que el cliente genera una vez por hoja de compra: dos toques devuelven el mismo pedido.';

create unique index if not exists aftr_ordenes_client_key
  on public.aftr_ordenes (cliente_id, client_key) where client_key is not null;

/* Devuelve el pedido que esta persona ya creó con esta clave, si existe. El
   lock es por (persona, clave): dos llamadas simultáneas se ordenan y la
   segunda encuentra lo que escribió la primera. */
create or replace function impl.aftr_orden_repetida(p_cliente uuid, p_clave uuid)
returns aftr_ordenes language plpgsql security definer set search_path = public as $$
declare o aftr_ordenes;
begin
  if p_clave is null then return null; end if;
  perform pg_advisory_xact_lock(hashtextextended(p_cliente::text || ':' || p_clave::text, 0));
  select * into o from aftr_ordenes where cliente_id = p_cliente and client_key = p_clave;
  return o;
end $$;

/* Si la clave se repite con otros datos, no se devuelve el pedido viejo en
   silencio: la persona cambió la cantidad o la mesa y esperaría eso. Mismo
   criterio que aftr_recargar_pulse con el importe. */
create or replace function impl.aftr_orden_misma(o aftr_ordenes, p_cantidad integer, p_mesa uuid)
returns void language plpgsql immutable as $$
begin
  if o.cantidad is distinct from p_cantidad or o.mesa_id is distinct from p_mesa then
    raise exception 'Esa operación ya se hizo con otros datos. Volvé a entrar al evento.';
  end if;
end $$;

-- ── 2 · comprar entradas ──────────────────────────────────────────────
drop function if exists public.aftr_comprar(uuid, uuid, integer);
create function public.aftr_comprar(p_evento uuid, p_fase uuid, p_cantidad integer,
                                    p_client_key uuid default null)
returns jsonb language plpgsql security definer set search_path to 'public'
as $function$
declare
  c aftr_clientes := impl.aftr_yo();
  e eventos; f evento_fase; o aftr_ordenes;
  v_precio int; v_quedan int; v_ref uuid;
begin
  -- Antes que nada: si es el mismo toque de antes, se devuelve lo mismo.
  o := impl.aftr_orden_repetida(c.user_id, p_client_key);
  if o.id is not null then
    perform impl.aftr_orden_misma(o, p_cantidad, null);
    return to_jsonb(o);
  end if;
  if p_cantidad is null or p_cantidad < 1 or p_cantidad > 10 then
    raise exception 'Podés comprar de 1 a 10 entradas.';
  end if;
  if not impl.aftr_visible(p_evento) then
    raise exception 'Este evento no está a la venta.';
  end if;
  select * into e from eventos where id = p_evento;
  perform impl.aftr_vencer(p_evento);
  if (select count(*) from aftr_ordenes where cliente_id = c.user_id and evento_id = p_evento
        and estado = 'pendiente') >= 3 then
    raise exception 'Ya tenés pedidos pendientes para este evento.';
  end if;
  if e.venta_por_fases then
    select * into f from evento_fase where id = p_fase and evento_id = p_evento for update;
    if not found or impl.aftr_estado_fase(f) <> 'abierta' then
      raise exception 'Esa fase no está a la venta.';
    end if;
    v_quedan := impl.aftr_quedan_fase(f.id);
    if v_quedan is not null and v_quedan < p_cantidad then
      raise exception 'Quedan % en esta fase.', v_quedan;
    end if;
    v_precio := f.precio::int;
  else
    if (e.manilla_desde is not null and now() < e.manilla_desde)
       or (e.manilla_hasta_ts is not null and now() > e.manilla_hasta_ts) then
      raise exception 'La venta de entradas está cerrada.';
    end if;
    v_precio := e.precio_manilla;
  end if;
  -- relacionador que trajo a este cliente a este evento: su última visita
  select v.rrpp_id into v_ref from link_visita v
   where v.evento_id = p_evento and v.cliente_id = c.user_id
   order by v.at desc, v.id desc limit 1;
  insert into aftr_ordenes (cliente_id, evento_id, tipo, fase_id, cantidad, precio_unit, total,
                            vence_at, referido_rrpp_id, client_key)
  values (c.user_id, p_evento, 'entrada', case when e.venta_por_fases then f.id end, p_cantidad,
          v_precio, v_precio * p_cantidad,
          least(now() + interval '12 hours', impl.aftr_inicio(e.fecha, e.hora_inicio)), v_ref,
          p_client_key)
  returning * into o;
  return to_jsonb(o);
end;
$function$;
revoke all on function public.aftr_comprar(uuid, uuid, integer, uuid) from public, anon;
grant execute on function public.aftr_comprar(uuid, uuid, integer, uuid) to authenticated, service_role;

-- ── 3 · reservar mesa ─────────────────────────────────────────────────
drop function if exists public.aftr_reservar_mesa(uuid, uuid, uuid);
create function public.aftr_reservar_mesa(p_evento uuid, p_mesa uuid, p_combo uuid default null,
                                          p_client_key uuid default null)
returns jsonb language plpgsql security definer set search_path to 'public'
as $function$
declare
  c aftr_clientes := impl.aftr_yo();
  e eventos; m mesas; k combos; o aftr_ordenes;
  v_precio int; v_vence timestamptz;
begin
  o := impl.aftr_orden_repetida(c.user_id, p_client_key);
  if o.id is not null then
    perform impl.aftr_orden_misma(o, 1, p_mesa);
    return to_jsonb(o) || jsonb_build_object(
      'mesa', (select etiqueta from mesas where id = o.mesa_id));
  end if;
  if not impl.aftr_visible(p_evento) then
    raise exception 'Este evento no está a la venta.';
  end if;
  select * into e from eventos where id = p_evento;
  select * into m from mesas where id = p_mesa and evento_id = p_evento for update;
  if not found or m.estado <> 'disponible' or m.grupo_id is not null then
    raise exception 'Esa mesa ya no está disponible.';
  end if;
  if exists (select 1 from aftr_ordenes where cliente_id = c.user_id and evento_id = p_evento
              and tipo = 'mesa' and estado = 'pendiente') then
    raise exception 'Ya tenés una reserva de mesa pendiente en este evento.';
  end if;
  if p_combo is not null then
    select * into k from combos where id = p_combo and coalesce(activo, true)
       and (club_id is null or club_id = e.club_id);
    if not found then
      raise exception 'Ese combo no está disponible.';
    end if;
    if coalesce(array_length(k.categorias, 1), 0) > 0 and not (m.categoria = any (k.categorias)) then
      raise exception 'Ese combo no corresponde a esta mesa.';
    end if;
  elsif e.combo_obligatorio then
    raise exception 'Elegí un combo para la mesa.';
  end if;
  v_precio := coalesce(k.precio, m.precio, 0);
  v_vence := least(now() + make_interval(hours => coalesce(e.horas_reserva, 3)),
                   impl.aftr_inicio(e.fecha, e.hora_inicio));
  update mesas set estado = 'reservada', cliente = c.nombre, cliente_id = c.user_id, canal = 'aftr',
                   combo_id = k.id, combo_qty = 1, precio = v_precio,
                   manillas = coalesce(k.incluye_manillas, 0),
                   reservada_at = now(), reserva_vence_at = v_vence, vendido_por = null,
                   updated_at = now()
   where id = m.id;
  insert into aftr_ordenes (cliente_id, evento_id, tipo, mesa_id, combo_id, cantidad, precio_unit, total,
                            vence_at, client_key)
  values (c.user_id, p_evento, 'mesa', m.id, k.id, 1, v_precio, v_precio, v_vence, p_client_key)
  returning * into o;
  return to_jsonb(o) || jsonb_build_object('mesa', m.etiqueta);
end;
$function$;
revoke all on function public.aftr_reservar_mesa(uuid, uuid, uuid, uuid) from public, anon;
grant execute on function public.aftr_reservar_mesa(uuid, uuid, uuid, uuid) to authenticated, service_role;

-- La mesa reservada desde una historia lleva la misma clave. Igual que arriba:
-- hay que borrar la vieja, porque `create or replace` con un parámetro nuevo
-- crea OTRA función y las llamadas de cuatro argumentos quedarían ambiguas.
drop function if exists public.aftr_reservar_historia(uuid, uuid, uuid, uuid);
create function public.aftr_reservar_historia(p_historia uuid, p_evento uuid, p_mesa uuid,
                                                         p_combo uuid default null,
                                                         p_client_key uuid default null)
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp'
as $function$
declare h aftr_historias := impl.historia_atribucion(p_historia, 'mesa'); r jsonb;
begin
  if h.evento_id is distinct from p_evento then raise exception 'La historia no pertenece a este evento.'; end if;
  r := aftr_reservar_mesa(h.evento_id, p_mesa, p_combo, p_client_key);
  update aftr_ordenes set historia_id = h.id,
         referido_rrpp_id = case when h.identidad = 'rrpp' then h.autor_id end
   where id = (r ->> 'id')::uuid;
  update mesas set vendido_por = case when h.identidad = 'rrpp' then h.autor_id end where id = p_mesa;
  return r;
end $function$;
revoke all on function public.aftr_reservar_historia(uuid, uuid, uuid, uuid, uuid) from public, anon;
grant execute on function public.aftr_reservar_historia(uuid, uuid, uuid, uuid, uuid) to authenticated, service_role;

-- ── 4 · techo a la recarga ────────────────────────────────────────────
-- Bs 2.000 por recarga y Bs 10.000 por día. No es un límite de riesgo
-- financiero: es que una recarga de Bs 300.000 es siempre un error de tipeo o
-- alguien probando, y ninguna de las dos cosas tiene que llegar al banco.
create or replace function public.aftr_recargar_pulse(p_centavos bigint, p_client_key uuid)
returns jsonb language plpgsql security definer set search_path to 'public'
as $function$
declare c aftr_clientes := impl.aftr_yo(); r pulse_recargas; v_dia bigint;
begin
  if p_centavos is null or p_centavos < 100 or p_client_key is null then
    raise exception 'La recarga mínima es Bs 1';
  end if;
  if p_centavos > 200000 then raise exception 'La recarga máxima es Bs 2.000'; end if;
  -- Lo ya pedido hoy cuenta, pagado o esperando pago: si no, se evita el techo
  -- dejando diez QR abiertos.
  select coalesce(sum(importe_centavos), 0) into v_dia from pulse_recargas
   where cliente_id = c.user_id and created_at > now() - interval '24 hours'
     and estado in ('pendiente', 'confirmada') and client_key is distinct from p_client_key;
  if v_dia + p_centavos > 1000000 then
    raise exception 'Llegaste al máximo de Bs 10.000 de recarga por día.';
  end if;
  insert into pulse_recargas (cliente_id, importe_centavos, client_key)
  values (c.user_id, p_centavos, p_client_key)
    on conflict (cliente_id, client_key) do nothing;
  select * into r from pulse_recargas where cliente_id = c.user_id and client_key = p_client_key;
  if r.importe_centavos <> p_centavos then raise exception 'La operación ya tiene otro importe'; end if;
  return to_jsonb(r);
end $function$;
revoke all on function public.aftr_recargar_pulse(bigint, uuid) from public, anon;
grant execute on function public.aftr_recargar_pulse(bigint, uuid) to authenticated, service_role;

notify pgrst,'reload schema';

-- La compra desde una historia lleva la misma clave.
drop function if exists public.aftr_comprar_historia(uuid, uuid, uuid, integer);
create function public.aftr_comprar_historia(p_historia uuid, p_evento uuid, p_fase uuid,
                                                        p_cantidad integer, p_client_key uuid default null)
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp'
as $function$
declare h aftr_historias := impl.historia_atribucion(p_historia, 'entrada'); r jsonb;
begin
  if h.evento_id is distinct from p_evento then raise exception 'La historia no pertenece a este evento.'; end if;
  r := aftr_comprar(h.evento_id, p_fase, p_cantidad, p_client_key);
  update aftr_ordenes set historia_id = h.id,
         referido_rrpp_id = case when h.identidad = 'rrpp' then h.autor_id end
   where id = (r ->> 'id')::uuid;
  return r;
end $function$;
revoke all on function public.aftr_comprar_historia(uuid, uuid, uuid, integer, uuid) from public, anon;
grant execute on function public.aftr_comprar_historia(uuid, uuid, uuid, integer, uuid) to authenticated, service_role;
notify pgrst,'reload schema';
