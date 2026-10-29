-- 44 · Cobro con QR bancario (Banco Económico, API Market)
--
-- El pedido de AFTR (aftr_ordenes) se paga con un QR que genera el banco.
-- La Edge Function `baneco` crea el QR, consulta su estado y, cuando EL
-- BANCO dice que está pagado, llama a aftr_pago_confirmado. Nada que mande
-- el cliente marca un pago.
--
-- Las entradas se emiten por un solo camino (impl.aftr_emitir_orden), el
-- mismo que usa la confirmación manual del boliche. La confirmación del
-- banco es idempotente: reintentos, consultas dobles o avisos repetidos
-- nunca emiten dos veces (fila bloqueada + estado del pedido).

create table if not exists pago_qr (
  id             uuid primary key default gen_random_uuid(),
  orden_id       uuid not null unique references aftr_ordenes (id) on delete cascade,
  proveedor      text not null default 'baneco',
  ambiente       text not null,
  transaction_id text not null unique,
  qr_id          text unique,
  qr_imagen      text,
  monto          numeric(12, 2) not null check (monto > 0),
  moneda         text not null default 'BOB',
  vence          date not null,
  estado         text not null default 'activo'
                 check (estado in ('activo', 'pagado', 'anulado', 'vencido', 'revisar')),
  pago           jsonb,
  banco_tx       text,
  pagado_at      timestamptz,
  nota           text,
  intentos       int not null default 0,
  ultimo_chequeo timestamptz,
  created_at     timestamptz not null default now()
);
create index if not exists pago_qr_activos_idx on pago_qr (estado) where estado = 'activo';
alter table pago_qr enable row level security;
drop policy if exists pago_qr_leer on pago_qr;
create policy pago_qr_leer on pago_qr for select to authenticated
  using (exists (select 1 from aftr_ordenes o where o.id = orden_id and o.cliente_id = auth.uid()));
-- sin políticas de escritura: solo la Edge Function (service role)

-- ── emisión: un solo camino ────────────────────────────────────────────
create or replace function impl.aftr_emitir_orden(p_orden uuid, p_por uuid)
returns int
language plpgsql
volatile
security definer
set search_path = public
as $$
declare o aftr_ordenes; c aftr_clientes; m mesas; v_n int;
begin
  select * into o from aftr_ordenes where id = p_orden for update;
  if not found then raise exception 'Pedido no encontrado.'; end if;
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
$$;

-- la confirmación manual del boliche, igual que antes pero por el camino común
create or replace function public.aftr_confirmar_orden(p_orden uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare o aftr_ordenes := impl.aftr_staff_orden(p_orden);
begin
  if o.estado <> 'pendiente' then
    raise exception 'Este pedido ya está %.', o.estado;
  end if;
  return jsonb_build_object('emitidas', impl.aftr_emitir_orden(o.id, auth.uid()));
end;
$$;

-- ── el banco confirmó el pago (solo la Edge Function, con service role) ──
-- p_pago: el objeto PaymentQR que devolvió el banco (statusQR o paidQR).
create or replace function public.aftr_pago_confirmado(p_qr text, p_pago jsonb)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  q pago_qr; o aftr_ordenes; v_monto numeric; v_moneda text; v_n int;
begin
  select * into q from pago_qr where qr_id = p_qr for update;
  if not found then raise exception 'QR desconocido: %', p_qr; end if;
  select * into o from aftr_ordenes where id = q.orden_id for update;

  -- ya resuelto: no se emite de nuevo
  if q.estado = 'pagado' or o.estado = 'confirmada' then
    return jsonb_build_object('estado', 'pagado', 'nuevo', false);
  end if;

  v_monto := nullif(p_pago ->> 'amount', '')::numeric;
  v_moneda := upper(coalesce(p_pago ->> 'currency', ''));
  if v_monto is distinct from q.monto or v_moneda <> q.moneda then
    update pago_qr set estado = 'revisar', pago = p_pago,
           nota = format('El banco informó %s %s y el pedido es %s %s', v_monto, v_moneda, q.monto, q.moneda)
     where id = q.id;
    return jsonb_build_object('estado', 'revisar', 'nuevo', false);
  end if;

  update pago_qr set estado = 'pagado', pago = p_pago, banco_tx = p_pago ->> 'transactionId',
         pagado_at = now(), ultimo_chequeo = now()
   where id = q.id;

  -- el dinero entró: se emite aunque el pedido haya vencido mientras pagaba
  if o.estado in ('pendiente', 'vencida') then
    begin
      v_n := impl.aftr_emitir_orden(o.id, null);
    exception when others then
      update pago_qr set estado = 'revisar', nota = 'Pagado, pero no se pudo emitir: ' || sqlerrm where id = q.id;
      return jsonb_build_object('estado', 'revisar', 'nuevo', false);
    end;
    return jsonb_build_object('estado', 'pagado', 'nuevo', true, 'emitidas', v_n);
  end if;

  update pago_qr set estado = 'revisar', nota = 'Pagado con el pedido ' || o.estado where id = q.id;
  return jsonb_build_object('estado', 'revisar', 'nuevo', false);
end;
$$;

revoke all on function public.aftr_pago_confirmado(text, jsonb) from public, anon, authenticated;
grant execute on function public.aftr_pago_confirmado(text, jsonb) to service_role;
revoke all on function impl.aftr_emitir_orden(uuid, uuid) from public, anon, authenticated;
