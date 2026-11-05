-- Privacidad entre relacionadores, parte 2: cerrar la tabla.
--
-- La parte 1 creó mesas_detalle y la app ya lee de ahí. Recién ahora se
-- pueden sacar las columnas de dinero de la tabla cruda: si se hacía antes,
-- la pantalla de Mesas quedaba en blanco para todo el mundo, porque la app
-- pedía select() de todas las columnas.
--
-- Ojo con el orden: en PostgreSQL un revoke por columna NO hace nada mientras
-- exista el grant de la tabla entera. Hay que quitar primero el permiso de
-- tabla y después conceder columna por columna. Probado: con el revoke solo,
-- information_schema.column_privileges seguía mostrando precio y vendido_por
-- para authenticated.
--
-- Después de esto, un curl a /rest/v1/mesas?select=* ya no trae precio,
-- vendido_por ni cliente. Quien tiene derecho a verlos los recibe por
-- mesas_detalle, fila por fila, según impl.ve_registro.
--
-- El plano sigue visible para todos: etiqueta, posición, estado y capacidad
-- quedan concedidas, así que el relacionador ve qué mesa está libre y el
-- realtime sigue funcionando.
revoke select on public.mesas from authenticated;

grant select (
  id, evento_id, planta, etiqueta, categoria, x, y, w, h,
  team_id, estado, combo_id, combo_qty, botellas, manillas,
  grupo_id, capacidad, barra_id, canal, cortesia, cortesia_por,
  updated_at, pagada_at, reservada_at, reserva_vence_at,
  pago_verificado, verificado_at
) on public.mesas to authenticated;

comment on table public.mesas is
  'Plano y estado de las mesas. Los datos de venta se leen por mesas_detalle: sobre esta tabla no estan concedidos por columna.';
