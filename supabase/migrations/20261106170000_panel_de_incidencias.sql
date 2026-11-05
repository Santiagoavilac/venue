-- Las incidencias, con pantalla.
--
-- Todo lo de la Fase 1 -el pago que llega tarde, el que se cobra y no emite, el
-- pedido que se canceló con el cobro en curso- deja una fila en
-- `aftr_incidencias` en vez de un cobro silencioso. Sin pantalla eso sólo mueve
-- el problema de lugar: antes se resolvía a mano con SQL y nadie se enteraba.
--
-- Dos RPC: listar y resolver. Las dos son del administrador del boliche, y el
-- portero queda afuera, igual que con `impl.ve_plata`: un portero no tiene por
-- qué ver cuánto pagó quién.
--
-- El permiso se comprueba adentro y no por la matriz de db/19. La matriz se
-- genera con un bloque `do` de cien líneas que vive en un archivo de historia;
-- copiarlo acá para dos funciones nuevas es justo lo que se desincroniza
-- después. Son dos de las 104 que ya comprueban adentro, y
-- `tests/rpc_con_guarda.py` las ve igual.

create or replace function impl.incidencias_admin(p_club text) returns void
language plpgsql stable security definer set search_path = public as $$
begin
  if es_platform_admin() then return; end if;
  if p_club is null or coalesce(rol_en_club(p_club), '') not in ('admin', 'propietario') then
    raise exception 'Solo el administrador del boliche ve los cobros a resolver.' using errcode = '42501';
  end if;
end $$;

-- ── listar ────────────────────────────────────────────────────────────
create or replace function public.aftr_incidencias(p_club text, p_estado text default 'abierta')
returns jsonb language plpgsql stable security definer set search_path = public as $$
begin
  perform impl.incidencias_admin(p_club);
  if p_estado is null or p_estado not in ('abierta', 'resuelta', 'todas') then
    raise exception 'Estado no válido.';
  end if;
  return jsonb_build_object(
    'abiertas', (select count(*) from aftr_incidencias
                  where (p_club is null or club_id = p_club) and estado = 'abierta'),
    'incidencias', coalesce((select jsonb_agg(jsonb_build_object(
        'id', i.id, 'estado', i.estado, 'detalle', i.detalle, 'monto', i.monto,
        'banco_tx', i.banco_tx, 'created_at', i.created_at,
        'resolucion', i.resolucion, 'resuelta_at', i.resuelta_at,
        'nota_pago', q.nota, 'pagado_at', q.pagado_at,
        'orden_id', i.orden_id, 'pedido_id', i.pedido_id, 'recarga_id', i.recarga_id,
        -- quién pagó, para poder escribirle
        'cliente', coalesce(c.nombre, 'Alguien sin perfil'),
        'usuario', c.usuario,
        'evento', e.nombre, 'fecha', e.fecha,
        'cantidad', o.cantidad, 'tipo', o.tipo, 'orden_estado', o.estado,
        -- se puede emitir si la orden sigue existiendo y el evento no terminó
        'puede_emitir', o.id is not null and o.estado <> 'confirmada'
                        and impl.aftr_fin(e.fecha, e.hora_inicio, e.hora_fin) > now())
      order by i.created_at desc)
      from aftr_incidencias i
      left join pago_qr q on q.id = i.pago_id
      left join aftr_ordenes o on o.id = i.orden_id
      left join eventos e on e.id = o.evento_id
      left join aftr_clientes c on c.user_id = coalesce(o.cliente_id,
        (select cliente_id from pulse_recargas where id = i.recarga_id),
        (select cliente_id from aftr_bar_pedidos where id = i.pedido_id))
      where (p_club is null or i.club_id = p_club)
        and (p_estado = 'todas' or i.estado = p_estado)
        and i.created_at > now() - interval '180 days'
      limit 200), '[]'::jsonb),
    'ahora', now());
end $$;
revoke all on function public.aftr_incidencias(text, text) from public, anon;
grant execute on function public.aftr_incidencias(text, text) to authenticated, service_role;

-- ── resolver ──────────────────────────────────────────────────────────
-- Tres salidas, y ninguna mueve plata por su cuenta: devolver un pago se hace
-- en el banco, acá queda escrito que se hizo y quién lo hizo. Emitir sí emite,
-- porque es lo único que el sistema puede hacer solo.
create or replace function public.aftr_incidencia_resolver(p_id uuid, p_accion text, p_nota text)
returns jsonb language plpgsql security definer set search_path = public as $$
declare i aftr_incidencias; v_n int; v_texto text := trim(coalesce(p_nota, ''));
begin
  select * into i from aftr_incidencias where id = p_id for update;
  if not found then raise exception 'Ese cobro no existe.'; end if;
  perform impl.incidencias_admin(i.club_id);
  if i.estado = 'resuelta' then
    raise exception 'Este cobro ya se resolvió: %', coalesce(i.resolucion, 'sin nota');
  end if;
  if p_accion not in ('emitir', 'devolver', 'cerrar') then raise exception 'Acción no válida.'; end if;
  if length(v_texto) < 5 then raise exception 'Escribí qué se hizo, para que quede en el historial.'; end if;
  if p_accion = 'emitir' then
    if i.orden_id is null then raise exception 'Este cobro no es de una compra de entradas.'; end if;
    v_n := impl.aftr_emitir_orden_forzado(i.orden_id, auth.uid());
    update pago_qr set estado = 'pagado', nota = null where id = i.pago_id;
  end if;
  update aftr_incidencias set estado = 'resuelta', resuelta_por = auth.uid(), resuelta_at = now(),
         resolucion = p_accion || ': ' || v_texto
   where id = i.id returning * into i;
  return jsonb_build_object('ok', true, 'emitidas', coalesce(v_n, 0), 'resolucion', i.resolucion);
end $$;
revoke all on function public.aftr_incidencia_resolver(uuid, text, text) from public, anon;
grant execute on function public.aftr_incidencia_resolver(uuid, text, text) to authenticated, service_role;

notify pgrst,'reload schema';
