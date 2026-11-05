-- Borrar un evento borra todo lo del evento, de verdad.
--
-- `impl.eliminar_evento` limpiaba entradas, invitados, listas, mesas, pagos,
-- caja, bonos y barra, pero quedaron fuera seis tablas que también apuntan al
-- evento y que no borran en cascada. Con cualquiera de ellas con una fila, el
-- borrado fallaba con el error crudo de Postgres —"violates foreign key
-- constraint ... on table bar_conteos"— y el evento quedaba sin poder
-- borrarse. Alcanza con que la barra haya hecho un conteo, con que alguien
-- haya publicado una historia o con que una entrada haya pasado por reventa.
--
-- Las que faltaban: bar_conteos, aftr_bar_pedidos, aftr_historias y las tres
-- de reventa.
--
-- Con una excepción que no es técnica: una operación de reventa en curso es
-- plata entre dos personas, con un plazo corriendo. Eso no se borra de
-- costado por borrar el evento; el sistema ya piensa así para cerrar una
-- cuenta ("Resolvé tus operaciones..."), y acá hace lo mismo: avisa y no
-- borra nada. Las operaciones terminadas sí se van con el evento, como las
-- entradas.
create or replace function impl.eliminar_evento(p_evento uuid)
returns json
language plpgsql
security definer
set search_path to 'public'
as $function$
declare v_nombre text; v_abiertas int;
begin
  select nombre into v_nombre from eventos where id = p_evento;
  if not found then raise exception 'Evento no encontrado'; end if;

  select count(*) into v_abiertas from aftr_reventa_ordenes
   where evento_id = p_evento
     and estado not in ('completada','confirmada','cancelada','vencida','resuelta');
  if v_abiertas > 0 then
    raise exception 'Este evento tiene % operación(es) de reventa sin terminar. Resolvelas antes de borrarlo.', v_abiertas;
  end if;

  -- lo de AFTR que cuelga del evento
  delete from aftr_reventa_historial where evento_id = p_evento;
  delete from aftr_reventa_ordenes    where evento_id = p_evento;
  delete from aftr_reventa_ofertas    where evento_id = p_evento;
  delete from aftr_historias          where evento_id = p_evento;
  delete from aftr_bar_pedidos        where evento_id = p_evento;

  delete from entradas where evento_id = p_evento;
  delete from registros where evento_id = p_evento;
  delete from cupo_rrpp where lista_tipo_id in (select id from lista_tipos where evento_id = p_evento);
  delete from lista_tipos where evento_id = p_evento;
  delete from mesas where evento_id = p_evento;
  delete from pagos where evento_id = p_evento;
  delete from caja_check where evento_id = p_evento;
  delete from venta_excepcion where evento_id = p_evento;
  delete from bonos where evento_id = p_evento;
  delete from bar_venta_items where venta_id in (select id from bar_ventas where evento_id = p_evento);
  delete from bar_ventas where evento_id = p_evento;
  delete from bar_conteos where evento_id = p_evento;
  delete from stock_mov where evento_id = p_evento;
  delete from bar_staff where evento_id = p_evento;
  delete from evento_fase where evento_id = p_evento;   -- arrastra fase_cupo_team (cascade)
  delete from eventos where id = p_evento;
  return json_build_object('nombre', v_nombre);
end;
$function$;
