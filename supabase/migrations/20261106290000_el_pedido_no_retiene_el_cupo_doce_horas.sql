-- Un pedido sin pagar deja de retener el cupo doce horas.
--
-- Qué se rompía: el cobro vive diez minutos (20261106090000) y cuando se anula
-- el pedido se cancela y el cupo vuelve. Pero eso sólo pasa si la persona
-- llegó a pedir el QR. Quien toca "Comprar" y cierra la app antes de abrir el
-- pago **retiene el cupo doce horas**, que es lo que dice `vence_at`. En una
-- fiesta que se llena, diez personas que hacen eso bloquean diez lugares toda
-- la noche sin haber pagado nada.
--
-- Acá el pedido vive treinta minutos. Es suficiente para buscar la tarjeta o
-- abrir la app del banco, y corto para que un cupo abandonado vuelva a la
-- venta la misma noche. El cron `aftr-vencer` ya corre cada minuto, así que no
-- hace falta nada más para que se cancelen solos.
--
-- Y para que el acortar no deje a nadie con un QR de un minuto: al reservar el
-- cobro, el pedido se extiende hasta cubrir los diez minutos del QR. Sin eso,
-- alguien que abre el pago en el minuto 29 recibía un QR que moría al minuto
-- siguiente, porque el plazo del QR es `least(vence del pedido, 10 minutos)`.
-- No es una puerta para retener el cupo indefinidamente: sólo puede haber un
-- cobro vivo por pedido, y cuando ese muere el pedido se cancela.
--
-- Las mesas no entran acá: tienen su propio plazo por boliche
-- (`clubs.horas_reserva`), que es otra decisión y la toma el boliche.

do $migra$
declare v_def text;
begin
  -- se reescribe el cuerpo vigente en vez de copiarlo acá: esta función ya se
  -- tocó tres veces esta semana y copiarla es lo que se desincroniza
  select pg_get_functiondef(p.oid) into v_def
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.proname = 'aftr_comprar';
  if v_def is null then raise exception 'No existe public.aftr_comprar'; end if;
  if position('interval ''12 hours''' in v_def) = 0 then
    raise notice 'aftr_comprar ya no retiene doce horas: no se toca';
  else
    v_def := replace(v_def,
      'least(now() + interval ''12 hours'', impl.aftr_inicio(e.fecha, e.hora_inicio))',
      'least(now() + interval ''30 minutes'', impl.aftr_inicio(e.fecha, e.hora_inicio))');
    execute v_def;
  end if;
end $migra$;

-- ── el QR siempre tiene sus diez minutos ──────────────────────────────
do $migra$
declare v_def text;
begin
  select pg_get_functiondef(p.oid) into v_def
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.proname = 'baneco_reservar_destino';
  if v_def is null then raise exception 'No existe public.baneco_reservar_destino'; end if;
  if position('extender el pedido' in v_def) > 0 then return; end if;
  v_def := replace(v_def,
    '  -- Diez minutos para pagar, o menos si el pedido muere antes. El barrido',
    '  -- extender el pedido: si le quedaban menos de diez minutos, el QR nacía' || chr(10) ||
    '  -- muerto. Sólo puede haber un cobro vivo por pedido, así que esto no' || chr(10) ||
    '  -- sirve para retener el cupo: cuando el cobro muere, el pedido se cae.' || chr(10) ||
    '  if p_tipo = ''orden'' and v_vence < now() + interval ''10 minutes'' then' || chr(10) ||
    '    update aftr_ordenes set vence_at = now() + interval ''10 minutes''' || chr(10) ||
    '     where id = p_id and estado = ''pendiente'' returning vence_at into v_vence;' || chr(10) ||
    '  end if;' || chr(10) || chr(10) ||
    '  -- Diez minutos para pagar, o menos si el pedido muere antes. El barrido');
  if position('extender el pedido' in v_def) = 0 then
    raise exception 'El cuerpo de baneco_reservar_destino cambió: revisar la inyección';
  end if;
  execute v_def;
end $migra$;

notify pgrst,'reload schema';
