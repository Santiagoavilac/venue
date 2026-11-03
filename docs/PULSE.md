# PULSE y pedidos AFTR

1 PULSE = Bs 1. Todos los movimientos se guardan en centavos. Las recargas no son ventas de un boliche; las compras generan el saldo por liquidar, sin comisiones nuevas. Las transferencias se hacen fuera del sistema y se registran manualmente por la administración de plataforma.

## Instalación aplicada el 31 de octubre de 2026

Proyecto: cxksjarupexptfksnptg, organización venues. Se aplicaron transaccionalmente las migraciones baneco_seguro y pulse_mesas_pedidos mediante SQL Editor. Baneco se publicó desde el panel usando un archivo único generado de bank.ts, handler.ts e index.ts, con SDK 2.118.0. No se modificaron credenciales bancarias. El proyecto histórico usa instaladores db/*.sql: no hacer un push indiscriminado de historia ni reaplicar estas migraciones.

El trabajo cron aftr-stock-liberar quedó creado con frecuencia de un minuto (id devuelto 2). Solo libera pedidos vencidos sin generación bancaria activa o incierta. La consulta bancaria conserva el mecanismo existente y exige su secreto configurado.

## Operación

AFTR: Cuenta → PULSE para saldo, movimientos y recargas. Accesos → Mis mesas para invitaciones, catálogo y pedidos. Cada invitado paga con su propia cuenta. Comprar con PULSE y QR directo son alternativas. Un pedido que ya generó QR debe resolverse bancariamente antes de iniciar otra compra.

VENUE móvil: sección AFTR para pedidos, asignaciones, catálogo y liquidaciones. Barra ve su turno y su barra. Administradores y propietarios configuran horarios, roles, envases, recetas, fotos y precios. La capacidad física no deriva de las manillas. Los invitados a mesa no reciben entradas automáticamente.

Los 15 productos base por boliche son borradores. Nueve fotos se guardaron una sola vez en bar-catalogo/base y se reutilizan. Los envases se cargan con volumen pendiente, sin stock ni precio: confirmar su volumen real en Bebidas base, ingresar mercadería con las herramientas de inventario, completar receta, foto, presentación y precio y recién entonces publicar. 37 Lenguas queda pendiente de identificar. El catálogo base no sobrescribe ediciones del boliche.

No se pueden rechazar ni anular desde POS ventas AFTR ya pagadas. Las incidencias conservan el historial. Una corrección de saldo requiere RPC venue_corregir_pulse, administrador de plataforma, motivo e idempotencia; se registra como un movimiento adicional inmutable.

## Verificación

28 casos PostgreSQL descartable: saldo, idempotencia, stock/POS concurrentes, reservas QR, invitados, permisos, liquidaciones, correcciones y borradores. 29 pruebas Deno de banco/handler. 6 web de QR. AFTR: analyze limpio y 6 pruebas. VENUE: analyze limpio y 100 pruebas; 67 integraciones omitidas sin entorno de integración. No hubo pagos reales ni saldo de prueba en la base real.

La certificación nunca acredita PULSE ni emite productos reales en esta base. Los recorridos con pagos simulados se prueban solamente en PostgreSQL descartable. La habilitación bancaria de producción y una conciliación real siguen pendientes; los pedidos a mesa permanecen desactivados hasta configurar el piloto.

Las interfaces móviles están implementadas en fuente y verificadas, sin generar ni distribuir una nueva APK/IPA. La operación de barra y catálogo nueva está en VENUE móvil; la web VENUE conserva su operación anterior con estados visuales sin cápsulas.
