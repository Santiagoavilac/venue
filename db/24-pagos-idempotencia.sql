-- SEGURIDAD (8/…) · un pago no se registra dos veces.
--
-- crear_pago insertaba una fila por llamada. Con señal mala, la app reintenta
-- el envío y el mismo pago quedaba duplicado (y la rendición, descuadrada).
--
-- crear_pago_unico recibe una clave generada en el teléfono para ESA
-- operación: si la clave ya existe, devuelve el pago ya registrado en vez de
-- crear otro. La web sigue usando crear_pago sin cambios.
--
-- Registrar un pago NO lo verifica: nace 'pendiente' y solo el admin lo
-- avanza (estado_pago), haya o no captura adjunta.
-- Re-ejecutable.

alter table pagos add column if not exists idempotency_key uuid;
create unique index if not exists pagos_idempotencia_unica
  on pagos (idempotency_key) where idempotency_key is not null;

create or replace function crear_pago_unico(
  p_evento uuid, p_monto numeric, p_concepto text, p_clave uuid,
  p_nro text default null, p_comprobante text default null)
returns uuid
language plpgsql volatile security definer set search_path = public
as $$
declare v_id uuid;
begin
  perform impl.exigir(impl.club_de('evento', p_evento), '{admin,jefe,rrpp}'::text[]);
  if p_clave is null then
    raise exception 'Falta la clave de la operación.';
  end if;
  if p_monto is null or p_monto <= 0 then
    raise exception 'Monto inválido';
  end if;
  -- la clave es de quien la generó: no sirve para "encontrar" pagos ajenos
  select id into v_id from pagos
   where idempotency_key = p_clave and rrpp_id = auth.uid();
  if found then return v_id; end if;
  begin
    insert into pagos (id, evento_id, rrpp_id, monto, concepto, estado,
                       nro_operacion, comprobante_url, created_at, idempotency_key)
    values (gen_random_uuid(), p_evento, auth.uid(), p_monto,
            coalesce(nullif(trim(p_concepto), ''), 'Pago'), 'pendiente',
            nullif(trim(coalesce(p_nro, '')), ''), p_comprobante, now(), p_clave)
    returning id into v_id;
  exception when unique_violation then
    -- dos envíos simultáneos del mismo pago: gana uno, el otro lo recibe
    select id into v_id from pagos
     where idempotency_key = p_clave and rrpp_id = auth.uid();
    if v_id is null then raise exception 'No autorizado.' using errcode = '42501'; end if;
  end;
  return v_id;
end;
$$;
comment on function crear_pago_unico(uuid, numeric, text, uuid, text, text) is 'venue:guarda';
revoke execute on function crear_pago_unico(uuid, numeric, text, uuid, text, text) from public, anon;
grant  execute on function crear_pago_unico(uuid, numeric, text, uuid, text, text) to authenticated;
