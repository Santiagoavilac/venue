-- API Market 1.3.0. Aplicar antes de publicar la función baneco.
-- No contiene credenciales y no llama al banco.
begin;
alter table public.pago_qr add column if not exists generacion_id uuid;
alter table public.pago_qr add column if not exists generacion_iniciada_at timestamptz;
alter table public.pago_qr drop constraint if exists pago_qr_estado_check;
alter table public.pago_qr add constraint pago_qr_estado_check
  check (estado in ('generando', 'fallido', 'activo', 'pagado', 'anulado', 'vencido', 'revisar'));
create index if not exists pago_qr_chequeo_idx on public.pago_qr(ambiente, estado, ultimo_chequeo nulls first);
-- No crear una unicidad de banco_tx sin confirmar su alcance con el banco:
-- el manual lo describe como número bancario, no como ID global del comercio.

create or replace function public.baneco_reservar_qr(p_orden uuid, p_cliente uuid, p_ambiente text)
returns jsonb language plpgsql security definer set search_path = public
as $$
declare o aftr_ordenes; q pago_qr;
begin
  if p_ambiente not in ('certificacion', 'produccion') or p_ambiente is null then raise exception 'Ambiente inválido'; end if;
  select * into o from aftr_ordenes where id = p_orden for update;
  if not found or o.cliente_id is distinct from p_cliente then raise exception 'Pedido no encontrado'; end if;
  select * into q from pago_qr where orden_id = o.id for update;
  if found and q.estado <> 'fallido' then
    if q.ambiente <> p_ambiente then raise exception 'El pedido pertenece a otro ambiente'; end if;
    return jsonb_build_object('reservado', false, 'pago', to_jsonb(q));
  end if;
  if o.estado <> 'pendiente' or o.vence_at <= now() or o.total <= 0 then raise exception 'Pedido no disponible'; end if;
  if q.id is not null then
    if q.qr_id is not null or q.ambiente <> p_ambiente then raise exception 'Cobro no regenerable'; end if;
    update pago_qr set estado = 'generando', generacion_id = gen_random_uuid(), generacion_iniciada_at = now(), nota = null
    where id = q.id returning * into q;
  else
    insert into pago_qr(orden_id, ambiente, transaction_id, monto, moneda, vence, estado, generacion_id, generacion_iniciada_at)
    values(o.id, p_ambiente, left(replace(o.id::text, '-', ''), 30), o.total, 'BOB',
      coalesce((o.vence_at at time zone 'America/La_Paz')::date, (now() at time zone 'America/La_Paz')::date),
      'generando', gen_random_uuid(), now()) returning * into q;
  end if;
  return jsonb_build_object('reservado', true, 'pago', to_jsonb(q));
end;
$$;

-- Un trabajador por ambiente y cursor de conciliación que sobrevive caídas.
create table if not exists public.baneco_conciliacion (
  ambiente text primary key check (ambiente in ('certificacion', 'produccion')),
  dia date not null,
  lease uuid,
  lease_hasta timestamptz,
  ultimo_exito timestamptz,
  ultimo_intento timestamptz,
  errores int not null default 0
);
alter table public.baneco_conciliacion enable row level security;
revoke all on public.baneco_conciliacion from public, anon, authenticated;
grant all on public.baneco_conciliacion to service_role;

create or replace function public.baneco_tomar_barrido(p_ambiente text)
returns jsonb language plpgsql security definer set search_path = public
as $$
declare s baneco_conciliacion; v_dia date; v_token uuid := gen_random_uuid();
begin
  if p_ambiente not in ('certificacion', 'produccion') or p_ambiente is null then raise exception 'Ambiente inválido'; end if;
  select coalesce(min((created_at at time zone 'America/La_Paz')::date), (now() at time zone 'America/La_Paz')::date)
    into v_dia from pago_qr where ambiente = p_ambiente;
  insert into baneco_conciliacion(ambiente, dia) values(p_ambiente, v_dia) on conflict do nothing;
  select * into s from baneco_conciliacion where ambiente = p_ambiente for update;
  if s.lease_hasta > now() then return null; end if;
  -- Una ejecución que murió generando un QR no habilita otra generación a ciegas.
  update pago_qr set estado = 'revisar', nota = 'GENERACION_INCIERTA'
    where ambiente = p_ambiente and estado = 'generando' and coalesce(generacion_iniciada_at, created_at) < now() - interval '2 minutes';
  update baneco_conciliacion set lease = v_token, lease_hasta = now() + interval '90 seconds', ultimo_intento = now()
    where ambiente = p_ambiente;
  return jsonb_build_object('dia', s.dia, 'token', v_token);
end;
$$;

create or replace function public.baneco_finalizar_barrido(p_ambiente text, p_token uuid, p_dia_ok date, p_errores int)
returns void language plpgsql security definer set search_path = public
as $$
begin
  update baneco_conciliacion set
    dia = case when p_dia_ok = dia
      then least(dia + 1, (now() at time zone 'America/La_Paz')::date) else dia end,
    ultimo_exito = case when p_dia_ok = dia then now() else ultimo_exito end,
    errores = greatest(0, p_errores), lease = null, lease_hasta = null
    where ambiente = p_ambiente and lease = p_token;
end;
$$;

create or replace function impl.aftr_emitir_orden(p_orden uuid, p_por uuid)
returns int
language plpgsql
volatile
security definer
set search_path = public
as $$
declare o aftr_ordenes; c aftr_clientes; m mesas; v_n int; v_cupo int; v_ocupadas int;
begin
  select * into o from aftr_ordenes where id = p_orden for update;
  if not found then raise exception 'Pedido no encontrado.'; end if;
  if o.estado = 'confirmada' then return 0; end if;
  if o.estado not in ('pendiente', 'vencida') then raise exception 'Pedido no emitible'; end if;
  -- Una reserva vencida ya liberó cupo: no sobrevendemos al recibir un pago tardío.
  if o.tipo = 'entrada' and o.fase_id is not null then
    select cupo into v_cupo from evento_fase where id = o.fase_id for update;
    if not found then raise exception 'Fase inexistente'; end if;
    if v_cupo is not null then
      select (select count(*) from entradas where fase_id = o.fase_id)
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
$$;


create or replace function public.aftr_pago_confirmado(p_qr text, p_pago jsonb)
returns jsonb language plpgsql security definer set search_path = public
as $$
declare q pago_qr; o aftr_ordenes; v_monto numeric; v_moneda text; v_tx text; v_n int;
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
  update pago_qr set estado = 'pagado', pago = p_pago, banco_tx = v_tx,
    pagado_at = now(), ultimo_chequeo = now(), nota = null where id = q.id;
  -- Si fue confirmado manualmente, registrar el dinero sin emitir dos veces.
  if o.estado = 'confirmada' then return jsonb_build_object('estado', 'pagado', 'nuevo', false); end if;
  if o.estado in ('pendiente', 'vencida') then
    begin
      v_n := impl.aftr_emitir_orden(o.id, null);
    exception when others then
      update pago_qr set estado = 'revisar', nota = 'PAGADO_SIN_EMISION' where id = q.id;
      return jsonb_build_object('estado', 'revisar', 'nuevo', false);
    end;
    return jsonb_build_object('estado', 'pagado', 'nuevo', true, 'emitidas', v_n);
  end if;
  update pago_qr set estado = 'revisar', nota = 'PAGADO_CON_PEDIDO_CANCELADO' where id = q.id;
  return jsonb_build_object('estado', 'revisar', 'nuevo', false);
end;
$$;

-- El botón manual sólo puede reintentar una emisión cuyo dinero ya confirmó
-- el banco. Un comprobante o un cambio de estado del cliente no alcanza.
create or replace function public.aftr_confirmar_orden(p_orden uuid)
returns jsonb language plpgsql security definer set search_path = public
as $$
declare q pago_qr; o aftr_ordenes; v_n int;
begin
  select * into q from pago_qr where orden_id = p_orden for update;
  o := impl.aftr_staff_orden(p_orden);
  if q.id is null or q.banco_tx is null or q.pagado_at is null
     or q.pago ->> 'qrId' is distinct from q.qr_id
     or upper(coalesce(q.pago ->> 'currency', '')) <> q.moneda
     or (q.pago ->> 'amount')::numeric is distinct from q.monto then
    raise exception 'El banco todavía no confirmó un pago válido para este pedido';
  end if;
  v_n := impl.aftr_emitir_orden(o.id, auth.uid());
  update pago_qr set estado = 'pagado', nota = null where id = q.id;
  return jsonb_build_object('emitidas', v_n);
end;
$$;
revoke all on function impl.aftr_emitir_orden(uuid, uuid) from public, anon, authenticated;
revoke all on function public.aftr_confirmar_orden(uuid) from public, anon;
grant execute on function public.aftr_confirmar_orden(uuid) to authenticated, service_role;
revoke all on function public.baneco_reservar_qr(uuid, uuid, text), public.baneco_tomar_barrido(text),
  public.baneco_finalizar_barrido(text, uuid, date, int), public.aftr_pago_confirmado(text, jsonb)
  from public, anon, authenticated;
grant execute on function public.baneco_reservar_qr(uuid, uuid, text), public.baneco_tomar_barrido(text),
  public.baneco_finalizar_barrido(text, uuid, date, int), public.aftr_pago_confirmado(text, jsonb) to service_role;
commit;
