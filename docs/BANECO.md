# Banco Económico: operación de VENUE / AFTR

## Estado de esta entrega

Al 04/11/2026 la integración está operativa en producción. Lo verificado en esta sesión, contra el proyecto `cxksjarupexptfksnptg`:

- La migración `20261031172015_baneco_seguro.sql` **ya está aplicada**: la tabla `baneco_conciliacion`, que solo crea esa migración, existe en la base.
- La función `baneco` **ya está publicada**: ACTIVE, versión 22 del 31/10/2026 22:32, con las marcas de la versión corregida (`BANECO_PRODUCTION_APPROVED`, `BANECO_CREDENTIALS_EXPIRES_AT`, `GENERACION_INCIERTA`, token de cron y de webhook).
- Los diez secretos de producción están cargados y verificados por digest SHA256 desde el CLI.
- `authenticate` contra `apimkt.baneco.com.bo` devuelve token. `paidQR` y `statusQR` responden. El cifrado de la cuenta funciona.
- Un barrido ejecutado con el token de cron devolvió HTTP 200 y `errores: 0`.

Las versiones anteriores de este documento decían que la migración no se había aplicado y que la función corregida no se había publicado. Ambas cosas se hicieron después de escribirlo y quedaron sin registrar, lo que llevó a repetir trabajo ya hecho.

Falta todavía: ejecutar `db/45-baneco-barrido.sql`, confirmar las entradas de Vault `baneco_project_url` y `baneco_cron_token`, y verificar que el cron corra solo. No se ejecutó `generateQR`: sería un cobro real.

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

## Caso 175774: estado consolidado

Juntando lo de sesiones anteriores con lo último del banco, el juego de producción es: usuario `A101332710` (API Market, caso 175774), cuenta de cobro `1031028940`, llave AES de 32 caracteres del caso 175774 y host `apimkt.baneco.com.bo`. Todo eso quedó en `.env.local`, ignorado por Git, con el juego de certificación comentado al lado.

El 04/11/2026 se autenticó correctamente contra producción: **HTTP 200, responseCode 0, token recibido**. La secuencia fue 404 (usuario sin habilitar) → 401 (clave vencida) → 0 (clave nueva de 4 dígitos). Quedan confirmados el usuario, la llave AES de producción y el host `apimkt.baneco.com.bo`. Con `BANECO_PRODUCTION_APPROVED=true` autorizado por el responsable, se verificaron en producción las operaciones de lectura: `paidQR` del día responde correctamente y `statusQR` devuelve 404 ante un `qrId` inexistente, que es la respuesta esperada. El cifrado de la cuenta para `generateQR` también funciona. `generateQR` y `cancelQR` no se ejecutaron: crearían un cobro real.

**Vigencia de la clave: resuelto.** El banco confirmó por WhatsApp el 04/11/2026 que las 48 horas del correo son el plazo para **habilitar** la clave, no su vida útil: "48 horas tiene para habilitarlo, una vez lo habilita, de ahí para adelante esa va a ser su clave". No hay rotación cada 48 horas y no hace falta ningún mecanismo de renovación automática.

Consecuencia práctica: `BANECO_CREDENTIALS_EXPIRES_AT` no debe llevar la fecha del correo. `autenticar()` corta antes de llamar al banco cuando esa fecha pasa, así que poner el 06/11 habría bloqueado la integración por configuración propia mientras la clave seguía siendo válida. Se dejó una fecha a un año como tope de revisión. El banco no comunicó un vencimiento real; si algún día lo comunica, ese valor manda.

El manual v1.3.0 no expone ningún endpoint para cambiar o renovar credenciales; los únicos son `authenticate`, `encrypt`, `decrypt`, los de `qrsimple`, `accounts/history` y `batchPayment/upload`. El token JWT dura 30 minutos, consistente con el caché de la función. El PDF `Documenacion API Market 2026` corresponde al BNB, no a Banco Económico, y su endpoint `UpdateCredentials` no aplica acá.

Los secretos cargados hoy en Supabase son los de **certificación**, no los de producción: se verificó comparando los digests SHA256 del panel contra los valores conocidos. La llave AES del caso 175774 todavía no está cargada ahí.

Falta entonces:

- Cargar el juego de producción como secretos de Supabase. La cuenta del CLI da 403 al listar o escribir secretos en `cxksjarupexptfksnptg`.
- `BANECO_CREDENTIALS_EXPIRES_AT` con la vigencia confirmada, y `BANECO_PRODUCTION_APPROVED=true` recién tras autorización.
La llave AES del caso 175774 es de **producción**, confirmado por el usuario. Certificación conserva su propia llave, la que hoy está en los secretos de Supabase.

## Solicitud 175282: datos concretos que faltan del banco

Certificación se verificó contra el banco desde el adaptador Deno: autenticación correcta, QR de prueba anterior anulado y pagos del día sin error. Las rutas v2 funcionan sin cuerpo GET. No se creó ningún QR nuevo.

Solicitar al ejecutivo la habilitación de API Market para el usuario y la cuenta de cobro, confirmación de que la nueva clave de Banca por Internet/Banca Móvil corresponda también a la API, su vencimiento, llave AES de cada ambiente, URL oficial de producción y permisos para authenticate/generateQR/statusQR/paidQR/cancelQR.

Confirmar también el alcance de unicidad de `PaymentQR.transactionId`, retención histórica de `paidQR`, límites de consultas, expiración del QR por fecha frente al vencimiento por hora del pedido y compatibilidad de autenticación del webhook. El manual no declara que reenviar `generateQR` con el mismo `transactionId` sea idempotente; por eso un resultado incierto se detiene para revisión.

## Incidencias conservadas para revisión

`GENERACION_INCIERTA` no autoriza otra generación automática. `PAGADO_SIN_EMISION` y `PAGADO_CON_PEDIDO_CANCELADO` conservan el número bancario y el registro de pago. Revisarlos por un operador autorizado; si corresponde reintentar emisión con cupo, la función pública existente exige un pago bancario válido registrado. Los reintegros y transferencias no se automatizan.

No se añadió una pantalla nueva de incidencias en Venue. Tampoco se ejecutó una compra completa en certificación o producción. La conciliación se probó con PostgreSQL aislado y respuestas simuladas, no con movimientos reales del banco.
