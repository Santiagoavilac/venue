-- El pago que llega tarde no emite nada, y queda escrito quién pagó qué.
--
-- Hasta ahora aftr_pago_confirmado_entradas emitía si la orden estaba
-- `pendiente` **o `vencida`**. Con los diez minutos de la migración anterior eso
-- es justo lo que no se quiere: el cupo ya volvió al evento y pudo venderse otra
-- vez, así que emitir contra una orden vencida es sobrevender (el chequeo de
-- cupo lo frena, pero recién con una excepción) o entregarle la entrada a quien
-- pagó media hora después mientras otro se quedó sin la suya.
--
-- Decidido: si la plata llega tarde **no se entrega la entrada**. Se cobra -el
-- dinero ya está en el banco, no se puede hacer de cuenta que no-, el cobro
-- queda en `revisar` con la nota PAGADO_FUERA_DE_PLAZO y se abre una incidencia
-- con el monto y el id del banco para que el boliche devuelva o emita a mano.
--
-- Tres cosas más que estaban sueltas:
--
-- * `aftr_incidencias` no guardaba monto ni transacción del banco, así que la
--   incidencia no alcanzaba para resolver nada sin ir a buscar a mano el pago.
--   Tampoco tenía forma de quedar cerrada: era una lista que sólo crecía.
-- * las dos salidas malas del camino de órdenes -PAGADO_SIN_EMISION y
--   PAGADO_CON_PEDIDO_CANCELADO- no abrían incidencia: el cobro quedaba en
--   `revisar` y nadie se enteraba. Sólo la rama de barra la abría.
-- * `aftr_pagar_pulse` se niega a cobrar con saldo si la orden "ya tiene un QR",
--   mirando también los anulados con `qr_id`. Antes no importaba porque sólo
--   podía existir un QR por orden; ahora que el QR muere a los diez minutos,
--   esa condición dejaría la orden sin poder pagarse nunca más con PULSE.
--
-- Y para que la persona se entere sin preguntar: `aftr_mis_accesos` devuelve sus
-- cobros en revisión. Es la misma RPC que la app ya llama, así que no hay una
-- nueva que guardar ni permisos nuevos que mantener.

-- ── 1 · la incidencia, con lo necesario para resolverla ───────────────
alter table public.aftr_incidencias
  add column if not exists orden_id uuid references public.aftr_ordenes(id) on delete set null,
  add column if not exists recarga_id uuid,
  add column if not exists monto numeric,
  add column if not exists banco_tx text,
  add column if not exists estado text not null default 'abierta',
  add column if not exists resolucion text,
  add column if not exists resuelta_por uuid,
  add column if not exists resuelta_at timestamptz;

do $$ begin
  alter table public.aftr_incidencias
    add constraint aftr_incidencias_estado_check check (estado in ('abierta', 'resuelta'));
exception when duplicate_object then null; end $$;

create index if not exists aftr_incidencias_abiertas
  on public.aftr_incidencias (club_id, created_at desc) where estado = 'abierta';

comment on column public.aftr_incidencias.estado is
  'abierta mientras el boliche no la resolvio (emitir, devolver o cerrar).';

-- Una sola por cobro mientras siga abierta: el barrido y el webhook pueden
-- pasar por el mismo pago más de una vez.
create or replace function impl.aftr_incidencia(p_pago uuid, p_detalle text)
returns void language plpgsql security definer set search_path = public as $$
declare q pago_qr; v_club text;
begin
  select * into q from pago_qr where id = p_pago;
  if not found then return; end if;
  if exists (select 1 from aftr_incidencias where pago_id = p_pago and estado = 'abierta') then return; end if;
  select e.club_id into v_club
    from aftr_ordenes o join eventos e on e.id = o.evento_id where o.id = q.orden_id;
  if v_club is null then
    select club_id into v_club from aftr_bar_pedidos where id = q.pedido_id;
  end if;
  insert into aftr_incidencias (pago_id, pedido_id, orden_id, recarga_id, club_id, monto, banco_tx, detalle)
  values (p_pago, q.pedido_id, q.orden_id, q.recarga_id, v_club, q.monto, q.banco_tx, p_detalle);
end $$;

-- ── 2 · emitir deja de aceptar una orden muerta ───────────────────────
-- Misma función, un estado menos: sólo `pendiente`. La orden vencida liberó su
-- cupo, así que emitirla es venderla dos veces.
create or replace function impl.aftr_emitir_orden(p_orden uuid, p_por uuid)
returns integer language plpgsql security definer set search_path to 'public'
as $function$
declare o aftr_ordenes; c aftr_clientes; m mesas; v_n int; v_cupo int; v_ocupadas int;
begin
  select * into o from aftr_ordenes where id = p_orden for update;
  if not found then raise exception 'Pedido no encontrado.'; end if;
  if o.estado = 'confirmada' then return 0; end if;
  if o.estado <> 'pendiente' then raise exception 'Pedido no emitible'; end if;
  if o.tipo = 'entrada' and o.fase_id is not null then
    select cupo into v_cupo from evento_fase where id = o.fase_id for update;
    if not found then raise exception 'Fase inexistente'; end if;
    if v_cupo is not null then
      select (select count(*) from impl.entradas_vigentes where fase_id = o.fase_id)
        + coalesce((select sum(cantidad) from aftr_ordenes where fase_id = o.fase_id
          and id <> o.id and estado = 'pendiente' and (vence_at is null or vence_at > now())), 0)
        into v_ocupadas;
      if v_ocupadas + o.cantidad > v_cupo then raise exception 'Sin cupo para emitir'; end if;
    end if;
  end if;
  select * into c from aftr_clientes where user_id = o.cliente_id;
  if o.tipo = 'entrada' then
    insert into entradas (id, evento_id, code, cliente, rrpp_id, precio, estado, created_at, fase_id, cliente_id, canal)
    select gen_random_uuid(), o.evento_id, gen_code_evento(o.evento_id), c.nombre, null, o.precio_unit,
           'valida', now(), o.fase_id, c.user_id, 'aftr'
      from generate_series(1, o.cantidad);
    v_n := o.cantidad;
  else
    select * into m from mesas where id = o.mesa_id for update;
    if not found or m.cliente_id is distinct from o.cliente_id or m.estado <> 'reservada' then
      raise exception 'La reserva de esta mesa ya no está vigente.';
    end if;
    update mesas set estado = 'pagada', pagada_por = p_por, pagada_at = now(),
                     pago_verificado = true, verificado_por = p_por, verificado_at = now(),
                     reserva_vence_at = null, updated_at = now()
     where id = m.id;
    insert into entradas (id, evento_id, code, cliente, rrpp_id, precio, estado, created_at, mesa_id, cliente_id, canal)
    select gen_random_uuid(), o.evento_id, gen_code_evento(o.evento_id), c.nombre, null, 0,
           'valida', now(), m.id, c.user_id, 'aftr'
      from generate_series(1, m.manillas);
    v_n := m.manillas;
  end if;
  update aftr_ordenes set estado = 'confirmada', confirmada_por = p_por, confirmada_at = now()
   where id = o.id;
  return v_n;
end;
$function$;

/* Reabre una orden muerta y emite. Es para dos casos acotados: el botón manual
   del staff -que ya exige que el banco haya confirmado la plata- y el pago que
   entra dentro de los 90 s de gracia, donde el barrido pudo haberla cancelado
   un segundo antes. El chequeo de cupo sigue adentro: si el cupo ya se vendió,
   esto falla y queda la incidencia. */
create or replace function impl.aftr_emitir_orden_forzado(p_orden uuid, p_por uuid)
returns integer language plpgsql security definer set search_path = public as $$
begin
  update aftr_ordenes set estado = 'pendiente'
   where id = p_orden and estado in ('vencida', 'cancelada');
  return impl.aftr_emitir_orden(p_orden, p_por);
end $$;
revoke all on function impl.aftr_emitir_orden_forzado(uuid, uuid) from public, anon, authenticated;

-- ── 3 · el camino del pago de una orden ───────────────────────────────
create or replace function public.aftr_pago_confirmado_entradas(p_qr text, p_pago jsonb)
returns jsonb language plpgsql security definer set search_path to 'public'
as $function$
declare q pago_qr; o aftr_ordenes; v_monto numeric; v_moneda text; v_tx text; v_n int;
        v_limite timestamptz; v_a_tiempo boolean;
begin
  select * into q from pago_qr where qr_id = p_qr for update;
  if not found then raise exception 'QR desconocido'; end if;
  select * into o from aftr_ordenes where id = q.orden_id for update;
  if q.estado = 'pagado' then return jsonb_build_object('estado', 'pagado', 'nuevo', false); end if;
  -- transaction_id es del comercio; PaymentQR.transactionId es del banco.
  v_tx := nullif(btrim(p_pago ->> 'transactionId'), '');
  v_moneda := upper(coalesce(p_pago ->> 'currency', ''));
  begin
    v_monto := nullif(p_pago ->> 'amount', '')::numeric;
  exception when invalid_text_representation or numeric_value_out_of_range then v_monto := null;
  end;
  if p_pago ->> 'qrId' is distinct from q.qr_id or v_tx is null
     or v_monto is distinct from q.monto or v_moneda <> q.moneda then
    update pago_qr set estado = 'revisar', pago = p_pago, nota = 'DATOS_BANCARIOS_NO_COINCIDEN', ultimo_chequeo = now() where id = q.id;
    return jsonb_build_object('estado', 'revisar', 'nuevo', false);
  end if;
  -- La plata está: se anota siempre, emita o no.
  update pago_qr set estado = 'pagado', pago = p_pago, banco_tx = v_tx,
    pagado_at = now(), ultimo_chequeo = now(), nota = null where id = q.id;
  -- Si fue confirmado manualmente, registrar el dinero sin emitir dos veces.
  if o.estado = 'confirmada' then return jsonb_build_object('estado', 'pagado', 'nuevo', false); end if;

  -- Los diez minutos del cobro, más 90 s por la latencia del banco.
  v_limite := coalesce(q.limite_at, o.vence_at);
  v_a_tiempo := v_limite is null or now() <= v_limite + interval '90 seconds';

  if v_a_tiempo and o.estado in ('pendiente', 'vencida', 'cancelada') then
    begin
      v_n := impl.aftr_emitir_orden_forzado(o.id, null);
    exception when others then
      update pago_qr set estado = 'revisar', nota = 'PAGADO_SIN_EMISION' where id = q.id;
      perform impl.aftr_incidencia(q.id,
        'Pago confirmado por el banco y la entrada no se pudo emitir: ' || coalesce(sqlerrm, '') ||
        '. Hay que emitir a mano o devolver la plata.');
      return jsonb_build_object('estado', 'revisar', 'nuevo', false);
    end;
    return jsonb_build_object('estado', 'pagado', 'nuevo', true, 'emitidas', v_n);
  end if;

  -- Tarde. No se entrega nada: el cupo ya volvió al evento y pudo venderse.
  update pago_qr set estado = 'revisar', nota = 'PAGADO_FUERA_DE_PLAZO' where id = q.id;
  perform impl.aftr_incidencia(q.id,
    'El pago llegó después del plazo de diez minutos (vencía ' ||
    to_char(v_limite at time zone 'America/La_Paz', 'DD/MM HH24:MI') ||
    '). No se emitió la entrada: hay que devolver la plata o emitir a mano si todavía hay cupo.');
  return jsonb_build_object('estado', 'revisar', 'nuevo', false, 'motivo', 'tarde');
end;
$function$;

-- El botón manual del staff sigue pudiendo emitir una orden vencida: para eso
-- existe, y ya exige que el banco haya confirmado un pago válido.
create or replace function public.aftr_confirmar_orden(p_orden uuid)
returns jsonb language plpgsql security definer set search_path = public
as $$
declare q pago_qr; o aftr_ordenes; v_n int;
begin
  select * into q from pago_qr where orden_id = p_orden
   and estado in ('generando', 'activo', 'pagado', 'revisar')
   order by created_at desc limit 1 for update;
  o := impl.aftr_staff_orden(p_orden);
  if q.id is null or q.banco_tx is null or q.pagado_at is null
     or q.pago ->> 'qrId' is distinct from q.qr_id
     or upper(coalesce(q.pago ->> 'currency', '')) <> q.moneda
     or (q.pago ->> 'amount')::numeric is distinct from q.monto then
    raise exception 'El banco todavía no confirmó un pago válido para este pedido';
  end if;
  v_n := impl.aftr_emitir_orden_forzado(o.id, auth.uid());
  update pago_qr set estado = 'pagado', nota = null where id = q.id;
  update aftr_incidencias set estado = 'resuelta', resuelta_por = auth.uid(), resuelta_at = now(),
         resolucion = coalesce(resolucion, 'Se emitió la entrada a mano.')
   where pago_id = q.id and estado = 'abierta';
  return jsonb_build_object('emitidas', v_n);
end;
$$;
revoke all on function public.aftr_confirmar_orden(uuid) from public, anon;
grant execute on function public.aftr_confirmar_orden(uuid) to authenticated, service_role;

-- ── 4 · la rama de barra también abre incidencia por un solo camino ───
create or replace function public.aftr_pago_confirmado(p_qr text, p_pago jsonb)
returns jsonb language plpgsql security definer set search_path to 'public'
as $function$
declare q pago_qr; r pulse_recargas; p aftr_bar_pedidos; o aftr_ordenes; v numeric; resultado jsonb; v_club text;
begin
 select * into q from pago_qr where qr_id=p_qr for update;
 if not found then raise exception 'QR desconocido'; end if;
 if q.estado='pagado' then return jsonb_build_object('estado','pagado','nuevo',false); end if;
 begin v:=(p_pago->>'amount')::numeric; exception when others then v:=null; end;
 if p_pago->>'qrId' is distinct from q.qr_id or nullif(trim(p_pago->>'transactionId'),'') is null or v is distinct from q.monto or upper(coalesce(p_pago->>'currency',''))<>q.moneda then
 update pago_qr set estado='revisar',pago=p_pago,nota='DATOS_BANCARIOS_NO_COINCIDEN',ultimo_chequeo=now() where id=q.id;
 return jsonb_build_object('estado','revisar','nuevo',false); end if;
 -- Certificación nunca acredita dinero ni emite productos en la base real.
 if q.ambiente<>'produccion' then
 update pago_qr set estado='revisar',pago=p_pago,banco_tx=p_pago->>'transactionId',pagado_at=now(),nota='CERTIFICACION_SIN_EFECTO_MONETARIO' where id=q.id;
 return jsonb_build_object('estado','revisar','nuevo',false); end if;
 if q.orden_id is not null then
 resultado:=aftr_pago_confirmado_entradas(p_qr,p_pago);
 select * into o from aftr_ordenes where id=q.orden_id;
 if o.estado='confirmada' then
 select club_id into v_club from eventos where id=o.evento_id;
 perform impl.aftr_venta('orden:'||o.id,v_club,(o.total*100)::bigint,'qr');
 end if;
 return resultado;
 end if;
 update pago_qr set estado='pagado',pago=p_pago,banco_tx=p_pago->>'transactionId',pagado_at=now(),ultimo_chequeo=now(),nota=null where id=q.id;
 begin
 if q.recarga_id is not null then
 select * into r from pulse_recargas where id=q.recarga_id for update;
 perform impl.pulse_mover(r.cliente_id,r.importe_centavos,'recarga:'||r.id,'Recarga PULSE por QR');
 update pulse_recargas set estado='confirmada' where id=r.id;
 else
 select * into p from aftr_bar_pedidos where id=q.pedido_id for update;
 perform impl.aftr_bar_emitir(p.id);
 end if;
 exception when others then
 update pago_qr set estado='revisar',nota='PAGADO_SIN_EMISION' where id=q.id;
 -- antes insertaba la fila a mano y le faltaba monto y transaccion
 perform impl.aftr_incidencia(q.id,'Pago confirmado sin completar la venta: '||coalesce(sqlerrm,'')||'. Revision requerida.');
 return jsonb_build_object('estado','revisar','nuevo',false);
 end;
 return jsonb_build_object('estado','pagado','nuevo',true);
end $function$;

-- ── 5 · pagar con saldo despues de que el QR murio ────────────────────
-- Sólo frena si hay un cobro VIVO: un anulado es justamente el caso en que la
-- persona quiere cambiar de método.
create or replace function public.aftr_pagar_pulse(p_orden uuid) returns jsonb
language plpgsql security definer set search_path = public as $$
declare c aftr_clientes := impl.aftr_yo(); o aftr_ordenes; n int; v_club text;
begin
  -- Mismo orden de bloqueo que la confirmación bancaria: QR, orden, saldo.
  perform 1 from pago_qr where orden_id = p_orden for update;
  select * into o from aftr_ordenes where id = p_orden and cliente_id = c.user_id for update;
  if not found then raise exception 'Pedido no encontrado'; end if;
  if o.estado = 'confirmada' then return jsonb_build_object('estado', 'confirmada'); end if;
  if o.estado <> 'pendiente' or o.vence_at <= now() or o.total <= 0 then raise exception 'Pedido vencido o no disponible'; end if;
  if exists (select 1 from pago_qr where orden_id = o.id
             and estado in ('generando', 'activo', 'pagado', 'revisar')) then
    raise exception 'Este pedido ya tiene un QR. Esperá su cancelación antes de cambiar de método.';
  end if;
  perform impl.pulse_mover(c.user_id, -(o.total * 100)::bigint, 'orden:' || o.id, 'Compra ' || o.tipo);
  n := impl.aftr_emitir_orden(o.id, null);
  select club_id into v_club from eventos where id = o.evento_id;
  perform impl.aftr_venta('orden:' || o.id, v_club, (o.total * 100)::bigint, 'pulse');
  return jsonb_build_object('estado', 'confirmada', 'emitidas', n);
end $$;

-- ── 6 · que la persona se entere sin preguntar ────────────────────────
-- Se agrega `revisar` a lo que la app ya pide. Las apps publicadas ignoran la
-- clave nueva; las nuevas muestran la tarjeta con el monto y el WhatsApp.
create or replace function impl.aftr_mis_accesos_social_base()
returns jsonb language plpgsql security definer set search_path to 'public'
as $function$
declare c aftr_clientes := impl.aftr_yo();
begin
  perform impl.aftr_vencer(null, c.user_id);
  return jsonb_build_object(
    'entradas', coalesce((select jsonb_agg(jsonb_build_object(
        'id', x.id, 'code', x.code, 'qr', 'EVT:' || x.evento_id || ':' || x.code,
        'estado', x.estado, 'precio', x.precio, 'usada_at', x.used_at,
        'fase', f.nombre, 'mesa', m.etiqueta,
        'transferible', x.estado = 'valida' and impl.aftr_fin(e.fecha, e.hora_inicio, e.hora_fin) > now(),
        'evento', impl.aftr_tarjeta(x.evento_id))
      order by e.fecha desc, x.created_at)
      from impl.entradas_vigentes x join eventos e on e.id = x.evento_id
      left join evento_fase f on f.id = x.fase_id
      left join mesas m on m.id = x.mesa_id
      where x.cliente_id = c.user_id), '[]'::jsonb),
    'listas', coalesce((select jsonb_agg(jsonb_build_object(
        'id', r.id, 'code', r.code, 'qr', 'LST:' || r.evento_id || ':' || r.code,
        'estado', case when r.qr_anulado then 'anulada' when r.ingreso_at is not null then 'usada' else 'valida' end,
        'lista', l.nombre, 'hasta', to_char(l.ingreso_hasta, 'HH24:MI'),
        'evento', impl.aftr_tarjeta(r.evento_id))
      order by e.fecha desc)
      from registros r join lista_tipos l on l.id = r.lista_tipo_id join eventos e on e.id = r.evento_id
      where r.cliente_id = c.user_id), '[]'::jsonb),
    'mesas', coalesce((select jsonb_agg(jsonb_build_object(
        'id', m.id, 'etiqueta', m.etiqueta, 'categoria', m.categoria, 'estado', m.estado,
        'precio', m.precio, 'combo', k.nombre, 'manillas', m.manillas, 'vence_at', m.reserva_vence_at,
        'evento', impl.aftr_tarjeta(m.evento_id))
      order by e.fecha desc)
      from mesas m join eventos e on e.id = m.evento_id left join combos k on k.id = m.combo_id
      where m.cliente_id = c.user_id), '[]'::jsonb),
    'ordenes', coalesce((select jsonb_agg(jsonb_build_object(
        'id', o.id, 'tipo', o.tipo, 'estado', o.estado, 'cantidad', o.cantidad, 'total', o.total,
        'vence_at', o.vence_at, 'created_at', o.created_at, 'fase', f.nombre, 'mesa', m.etiqueta,
        'evento', impl.aftr_tarjeta(o.evento_id))
      order by o.created_at desc)
      from aftr_ordenes o left join evento_fase f on f.id = o.fase_id left join mesas m on m.id = o.mesa_id
      where o.cliente_id = c.user_id and o.estado = 'pendiente'), '[]'::jsonb),
    -- Plata cobrada que no entregó nada. Un mes: después ya se resolvió por
    -- fuera y la tarjeta sólo preocuparía.
    'revisar', coalesce((select jsonb_agg(jsonb_build_object(
        'id', q.id, 'monto', q.monto, 'nota', q.nota, 'pagado_at', q.pagado_at,
        'tipo', case when q.orden_id is not null then 'orden'
                     when q.recarga_id is not null then 'recarga' else 'pedido' end,
        'evento', case when o.evento_id is not null then impl.aftr_tarjeta(o.evento_id) end,
        'resuelta', not exists (select 1 from aftr_incidencias i
                                 where i.pago_id = q.id and i.estado = 'abierta'))
      order by q.pagado_at desc)
      from pago_qr q
      left join aftr_ordenes o on o.id = q.orden_id
      left join pulse_recargas pr on pr.id = q.recarga_id
      left join aftr_bar_pedidos bp on bp.id = q.pedido_id
      where q.estado = 'revisar' and q.banco_tx is not null and q.ambiente = 'produccion'
        and coalesce(o.cliente_id, pr.cliente_id, bp.cliente_id) = c.user_id
        and q.pagado_at > now() - interval '30 days'), '[]'::jsonb));
end;
$function$;

notify pgrst,'reload schema';
