# Banco Económico: operación de VENUE / AFTR

## Estado de esta entrega

Cambios locales probados. No se aplicó la migración ni se publicó la función corregida.
El proyecto configurado es `cxksjarupexptfksnptg`. La cuenta disponible en MCP/CLI no tiene acceso administrativo a él.
El acceso REST local permite verificar tablas y algunos permisos. Se encontró la sesión correcta en el segundo Chrome, perfil Suma (Work), y desde allí se verificaron el cron activo cada minuto, su condición de QR activos, ejecuciones SQL recientes y el nombre del secreto de cron en Vault. No se leyeron valores secretos ni se recuperó la fuente remota completa.

Se cobra en una cuenta bancaria única. La distribución posterior de fondos es manual.

## Qué cambió

- Una reserva en PostgreSQL impide generar simultáneamente dos QR para el mismo pedido.
- Un timeout de generación deja el cobro para revisión; no se vuelve a generar a ciegas.
- La confirmación valida `qrId`, importe, moneda y existencia del número de transacción bancaria.
- `transaction_id` identifica la compra del comercio. `banco_tx` guarda `PaymentQR.transactionId`, que el manual define como transacción bancaria. No tienen que ser iguales.
- Los pagos tardíos sólo emiten si todavía hay cupo. Si no, se conserva el pago en `revisar`.
- `aftr_confirmar_orden` sólo permite reintentar una emisión respaldada por dinero ya confirmado. No confirma pagos por un comprobante.
- El cron consulta estados con rotación por `ultimo_chequeo` y concilia días pendientes mediante un cursor persistente. No depende de tener QR activos para conciliar.
- El webhook está deshabilitado hasta configurar autenticación. Una notificación sólo dispara una consulta al banco.
- AFTR móvil evita consultas superpuestas y conserva los centavos. AFTR web solicita el QR, permite guardarlo y sigue el estado.

## Pruebas sin dinero real

Desde la raíz del repositorio:

```sh
cd db/functions/baneco
deno test --no-remote tests/
deno check --no-remote index.ts
deno lint bank.ts handler.ts index.ts tests/
```

Desde la raíz, `sh tools/test_baneco.sh` crea PostgreSQL temporal por socket, verifica la migración y elimina su propio cluster al terminar. Requiere PostgreSQL 17 ya instalado. No lee `.env.local` ni se conecta al banco.

Pruebas web: `node --test tests/baneco-web.test.mjs`.

En `aftr_mobile`: ejecutar primero el control de almacenamiento y después `flutter analyze --no-pub` y `flutter test --no-pub test/pago_qr_test.dart`. No requieren simulador.

## Orden de publicación pendiente

1. Usar la sesión del segundo Chrome, perfil Suma (Work), o conectar esa cuenta en MCP/CLI. Verificar el identificador exacto antes de toda escritura.
2. Inspeccionar las fuentes de `baneco`, las definiciones actuales de `pago_qr`, `aftr_ordenes`, las funciones modificadas, los grants y las policies. Comparar con esta migración. El acceso REST no prueba equivalencia de fuentes.
3. Revisar cron y sus ejecuciones recientes, logs de función, respuesta de pg_net y advisors. Tomar un respaldo de las definiciones actuales antes del cambio.
4. Aplicar una sola vez `supabase/migrations/20261031172015_baneco_seguro.sql` al proyecto correcto mediante una migración remota. El repositorio histórico usa `db/*.sql`; no ejecutar otra vez todos esos instaladores ni hacer un push indiscriminado de historia.
5. Configurar secretos bancarios vigentes usando `db/functions/baneco/baneco.env.example` como lista de nombres. No copiar secretos al frontend ni a Git.
6. Publicar `baneco` desde la raíz con `supabase functions deploy baneco --project-ref cxksjarupexptfksnptg --use-api`. `supabase/config.toml` apunta a la única fuente en `db/functions/baneco` y declara `verify_jwt = false`. La propia función valida sesión y propiedad, token del cron o token del webhook según la acción.
7. Crear en Vault `baneco_project_url` con la URL del proyecto y `baneco_cron_token` con el mismo secreto aleatorio de al menos 32 caracteres que `BANECO_CRON_TOKEN`. No poner el valor en una migración.
8. Sólo tras la habilitación y configuración, ejecutar `db/45-baneco-barrido.sql`. Sustituye el trabajo antiguo de forma transaccional y elimina la condición que detenía la conciliación al no quedar QR activos.
9. Verificar cron, invocaciones HTTP y avance del cursor en una prueba de certificación autorizada. Publicar los clientes compatibles después de desplegar el backend y probar el flujo completo.

Consultas de diagnóstico que no devuelven secretos ni información de pagadores:

```sql
select jobname, schedule, active from cron.job where jobname = 'baneco-barrido';
select status, start_time, end_time
from cron.job_run_details
where jobid in (select jobid from cron.job where jobname = 'baneco-barrido')
order by start_time desc limit 5;
select ambiente, dia, ultimo_intento, ultimo_exito, errores from public.baneco_conciliacion;
select estado, ambiente, count(*) from public.pago_qr group by estado, ambiente;
select id, status_code, timed_out from net._http_response order by id desc limit 5;
```

Un resultado exitoso de `cron.job_run_details` sólo prueba que PostgreSQL envió la solicitud, no que la función confirmó pagos. Revisar también pg_net y el cursor.

## Credenciales y habilitación bancaria

- Las credenciales anteriores vencían el 30/10/2026 según el contexto entregado. No se reutilizaron. Posteriormente se hizo un único intento de producción con la clave nueva suministrada por el usuario: HTTP 200, responseCode 404, sin token. No se reemplazaron secretos del servidor.
- En producción, `BANECO_CREDENTIALS_EXPIRES_AT` debe contener una fecha ISO 8601 vigente confirmada por el banco. Si falta o venció, el código no intenta autenticarse. En certificación la fecha es opcional si el banco no comunicó vencimiento; una fecha configurada sí se respeta.
- Certificación usa el host documentado `https://apimktdesa.baneco.com.bo/ApiGateway/`.
- Para producción, exigir confirmación del banco sobre URL, usuario habilitado, cuenta, llave AES y vigencia. Además de `BANECO_AMBIENTE=produccion`, la función exige `BANECO_PRODUCTION_APPROVED=true` y `BANECO_PRODUCTION_HOST` igual al host confirmado. Estos flags no reemplazan la autorización bancaria.
- No se debe probar `generateQR` en producción ni efectuar pagos reales sin autorización explícita.
- El manual no especifica firma del webhook ni cómo enviar cabeceras adicionales. Coordinar con el banco el uso de `x-baneco-token` antes de habilitarlo. Mientras tanto, usar consultas y conciliación.

## Solicitud 175282: datos concretos que faltan del banco

Certificación se verificó contra el banco desde el adaptador Deno: autenticación correcta, QR de prueba anterior anulado y pagos del día sin error. Las rutas v2 funcionan sin cuerpo GET. No se creó ningún QR nuevo.

Solicitar al ejecutivo la habilitación de API Market para el usuario y la cuenta de cobro, confirmación de que la nueva clave de Banca por Internet/Banca Móvil corresponda también a la API, su vencimiento, llave AES de cada ambiente, URL oficial de producción y permisos para authenticate/generateQR/statusQR/paidQR/cancelQR.

Confirmar también el alcance de unicidad de `PaymentQR.transactionId`, retención histórica de `paidQR`, límites de consultas, expiración del QR por fecha frente al vencimiento por hora del pedido y compatibilidad de autenticación del webhook. El manual no declara que reenviar `generateQR` con el mismo `transactionId` sea idempotente; por eso un resultado incierto se detiene para revisión.

## Incidencias conservadas para revisión

`GENERACION_INCIERTA` no autoriza otra generación automática. `PAGADO_SIN_EMISION` y `PAGADO_CON_PEDIDO_CANCELADO` conservan el número bancario y el registro de pago. Revisarlos por un operador autorizado; si corresponde reintentar emisión con cupo, la función pública existente exige un pago bancario válido registrado. Los reintegros y transferencias no se automatizan.

No se añadió una pantalla nueva de incidencias en Venue. Tampoco se ejecutó una compra completa en certificación o producción. La conciliación se probó con PostgreSQL aislado y respuestas simuladas, no con movimientos reales del banco.
