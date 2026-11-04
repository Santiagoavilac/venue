-- La comisión del relacionador se fija al comprar, no se recalcula después.
-- aftr_ordenes.referido_rrpp_id existía pero nadie lo escribía: la atribución
-- se deducía en cada consulta a partir de la última visita, así que cambiaba
-- si el cliente volvía a entrar por el enlace de otro relacionador.
-- Acá se sella en el momento de la compra, con la misma regla que ya usaba
-- rrpp_links: la última visita de ese cliente a ese evento. El enlace sólo
-- identifica al relacionador; el jefe de team nunca aparece ni se usa.
create or replace function public.aftr_comprar(p_evento uuid, p_fase uuid, p_cantidad integer)
 returns jsonb
 language plpgsql
 security definer
 set search_path to 'public'
as $function$
declare
  c aftr_clientes := impl.aftr_yo();
  e eventos; f evento_fase; o aftr_ordenes;
  v_precio int; v_quedan int; v_ref uuid;
begin
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
                            vence_at, referido_rrpp_id)
  values (c.user_id, p_evento, 'entrada', case when e.venta_por_fases then f.id end, p_cantidad,
          v_precio, v_precio * p_cantidad,
          least(now() + interval '12 hours', impl.aftr_inicio(e.fecha, e.hora_inicio)), v_ref)
  returning * into o;
  return to_jsonb(o);
end;
$function$;
