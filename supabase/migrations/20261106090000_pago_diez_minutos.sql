-- El cobro vive diez minutos, y cancelar deja de regalar plata.
--
-- Tres cosas que hoy se cruzan mal:
--
-- 1. El botón "Cancelar" de Accesos llama a aftr_cancelar_mi_orden, que
--    cancela la orden y libera el cupo pero NO mira pago_qr: el QR del banco
--    queda cobrable. Si la persona paga después, el sistema cobra, no emite
--    nada y deja una incidencia que se resuelve a mano. La función segura
--    -aftr_cancelar_cobro- ya existe y no se usaba ahí.
--
-- 2. Una orden de entrada retiene cupo doce horas. El QR del banco tampoco
--    tiene límite propio: su `vence` es una fecha de día, así que puede
--    cobrar horas después de que el pedido murió.
--
-- 3. Las órdenes sólo vencen cuando alguien casualmente llama otra función
--    (el propio db/35 dice "no hay cron"), y las mesas de AFTR vencidas sólo
--    se liberan si un staff de Venue abre el evento.
--
-- Acá: el cobro vive diez minutos y el barrido lo anula en el banco; al
-- anularse, la orden se cancela y el cupo vuelve; cancelar pasa por un solo
-- camino, el que sabe mirar el banco; y los vencimientos corren solos.

-- ── 1 · que se pueda pedir un QR nuevo ────────────────────────────────
-- pago_qr.orden_id era unique a secas: cuando el QR muere a los diez minutos
-- la orden se quedaba sin forma de generar otro. Ahora lo único es el QR
-- VIVO; los anulados quedan de histórico y no estorban.
alter table public.pago_qr drop constraint if exists pago_qr_orden_id_key;
alter table public.pago_qr drop constraint if exists pago_qr_recarga_id_key;
alter table public.pago_qr drop constraint if exists pago_qr_pedido_id_key;

create unique index if not exists pago_qr_orden_vivo
  on public.pago_qr (orden_id) where orden_id is not null
   and estado in ('generando', 'activo', 'pagado', 'revisar');
create unique index if not exists pago_qr_recarga_viva
  on public.pago_qr (recarga_id) where recarga_id is not null
   and estado in ('generando', 'activo', 'pagado', 'revisar');
create unique index if not exists pago_qr_pedido_vivo
  on public.pago_qr (pedido_id) where pedido_id is not null
   and estado in ('generando', 'activo', 'pagado', 'revisar');

-- ── 2 · el cobro vive diez minutos ────────────────────────────────────
create or replace function public.baneco_reservar_destino(p_tipo text, p_id uuid, p_cliente uuid, p_ambiente text)
returns jsonb language plpgsql security definer set search_path to 'public'
as $function$
declare q pago_qr; v_total numeric; v_vence timestamptz; v_estado text; v_limite timestamptz;
begin
  if p_ambiente is null or p_ambiente not in ('certificacion','produccion')
     or p_tipo is null or p_tipo not in ('orden','recarga','pedido') then
    raise exception 'Destino no válido';
  end if;
  -- el último, no "alguno": puede haber anulados de intentos anteriores
  select * into q from pago_qr
   where (p_tipo='orden' and orden_id=p_id) or (p_tipo='recarga' and recarga_id=p_id)
      or (p_tipo='pedido' and pedido_id=p_id)
   order by created_at desc limit 1 for update;
  if p_tipo='orden' then
    select total,vence_at,estado into v_total,v_vence,v_estado from aftr_ordenes where id=p_id and cliente_id=p_cliente for update;
  elsif p_tipo='recarga' then
    select importe_centavos::numeric/100,vence_at,estado into v_total,v_vence,v_estado from pulse_recargas where id=p_id and cliente_id=p_cliente for update;
  else
    select total_centavos::numeric/100,vence_at,estado into v_total,v_vence,v_estado from aftr_bar_pedidos where id=p_id and cliente_id=p_cliente and metodo='qr' for update;
  end if;
  if v_total is null then raise exception 'Pedido no encontrado'; end if;

  -- hay un cobro vivo: se devuelve ese, no se genera otro
  if q.id is not null and q.estado in ('generando','activo','pagado','revisar') then
    if q.ambiente<>p_ambiente then raise exception 'Ambiente diferente'; end if;
    return jsonb_build_object('reservado',false,'pago',to_jsonb(q));
  end if;
  if v_estado<>'pendiente' or v_vence<=now() or v_total<=0 then raise exception 'Pedido no disponible'; end if;

  -- Diez minutos para pagar, o menos si el pedido muere antes. El barrido
  -- (db/45) lo anula en el banco en cuanto pasa limite_at.
  v_limite := least(v_vence, now() + interval '10 minutes');

  if q.id is not null and q.estado='fallido' and q.qr_id is null then
    -- una generación que no llegó a nacer: se reusa la fila
    update pago_qr set estado='generando', generacion_id=gen_random_uuid(),
           generacion_iniciada_at=now(), nota=null, limite_at=v_limite,
           vence=(v_limite at time zone 'America/La_Paz')::date
     where id=q.id returning * into q;
  else
    insert into pago_qr(orden_id,recarga_id,pedido_id,ambiente,transaction_id,monto,moneda,vence,limite_at,estado,generacion_id,generacion_iniciada_at)
    values(case when p_tipo='orden' then p_id end,
           case when p_tipo='recarga' then p_id end,
           case when p_tipo='pedido' then p_id end,
           p_ambiente,
           -- único por intento: el banco no acepta dos cobros con el mismo id
           left(replace(gen_random_uuid()::text,'-',''),30),
           v_total,'BOB',(v_limite at time zone 'America/La_Paz')::date,v_limite,
           'generando',gen_random_uuid(),now())
    returning * into q;
  end if;
  return jsonb_build_object('reservado',true,'pago',to_jsonb(q));
end $function$;

-- ── 3 · al anularse el cobro, la orden se cae y el cupo vuelve ────────
create or replace function public.baneco_qr_anulado(p_qr text)
returns void language plpgsql security definer set search_path to 'public'
as $function$
declare q pago_qr; o aftr_ordenes;
begin
  select * into q from pago_qr where qr_id=p_qr for update;
  if not found or q.estado in ('pagado','revisar') or q.banco_tx is not null then return; end if;
  update pago_qr set estado='anulado',ultimo_chequeo=now() where id=q.id;
  if q.pedido_id is not null then perform impl.aftr_bar_liberar(q.pedido_id); end if;
  if q.recarga_id is not null then update pulse_recargas set estado='cancelada' where id=q.recarga_id and estado='pendiente'; end if;
  if q.orden_id is not null then
    select * into o from aftr_ordenes where id=q.orden_id for update;
    if found and o.estado='pendiente' then
      update aftr_ordenes set estado='cancelada' where id=o.id;
      -- la mesa vuelve a estar disponible para quien la quiera
      if o.tipo='mesa' and o.mesa_id is not null then
        perform mesa_limpiar(o.mesa_id) from mesas
          where id=o.mesa_id and cliente_id=o.cliente_id and estado='reservada';
      end if;
    end if;
  end if;
end $function$;

-- ── 4 · un solo camino para cancelar ──────────────────────────────────
-- Delega en la que sabe mirar el banco: si hay cobro en curso no cancela
-- nada y lo manda a anular; recién ahí la orden se cae (punto 3).
create or replace function public.aftr_cancelar_mi_orden(p_orden uuid)
returns void language plpgsql security definer set search_path to 'public'
as $function$
declare c aftr_clientes := impl.aftr_yo(); o aftr_ordenes;
begin
  select * into o from aftr_ordenes where id = p_orden and cliente_id = c.user_id;
  if not found or o.estado <> 'pendiente' then
    raise exception 'Ese pedido ya no se puede cancelar.';
  end if;
  perform public.aftr_cancelar_cobro('orden', p_orden);
end $function$;

-- ── 5 · los vencimientos corren solos ─────────────────────────────────
-- Las mesas de AFTR vencidas que no tengan un cobro vivo esperando.
create or replace function impl.aftr_mesas_vencer()
returns void language plpgsql security definer set search_path to 'public'
as $function$
declare m record;
begin
  for m in
    select mesa.id
      from mesas mesa
     where mesa.canal='aftr' and mesa.estado='reservada'
       and mesa.reserva_vence_at is not null and mesa.reserva_vence_at <= now()
       and not exists (
         select 1 from aftr_ordenes o join pago_qr q on q.orden_id=o.id
          where o.mesa_id=mesa.id and q.estado in ('generando','activo','pagado','revisar'))
     for update skip locked
  loop
    perform mesa_limpiar(m.id);
  end loop;
end $function$;

select cron.schedule('aftr-vencer', '* * * * *', $$select impl.aftr_vencer();$$)
 where not exists (select 1 from cron.job where jobname='aftr-vencer');
select cron.schedule('aftr-mesas-vencer', '* * * * *', $$select impl.aftr_mesas_vencer();$$)
 where not exists (select 1 from cron.job where jobname='aftr-mesas-vencer');

notify pgrst,'reload schema';
