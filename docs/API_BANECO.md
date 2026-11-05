# API de cobro con QR · Banco Económico (API Market 1.3.0)

Referencia técnica de la integración de cobro de VENUE / AFTR con Banco
Económico de Bolivia: qué expone el banco, qué expone nuestra Edge Function,
qué guarda la base, cómo se confirma el dinero y cómo se prueba sin cobrar.

El estado de la habilitación comercial, las credenciales y lo que falta
coordinar con el banco está en [BANECO.md](BANECO.md). Este documento es la
referencia de la API; el otro es la bitácora de la puesta en producción.

Fuentes de verdad en el repositorio:

| Pieza | Archivo |
| --- | --- |
| Cliente del banco (HTTP, cifrado, token) | `db/functions/baneco/bank.ts` |
| Contrato de nuestra función (acciones, permisos) | `db/functions/baneco/handler.ts` |
| Arranque de la función | `db/functions/baneco/index.ts` |
| Nombres de los secretos | `db/functions/baneco/baneco.env.example` |
| Tabla de cobros y emisión de entradas | `db/44-pagos-banco.sql` |
| Reserva, cursor de conciliación y validaciones | `supabase/migrations/20261031172015_baneco_seguro.sql` |
| Recargas PULSE, pedidos de barra y contabilidad | `supabase/migrations/20261031203752_pulse_mesas_pedidos.sql` |
| Cron del barrido | `db/45-baneco-barrido.sql` |
| Limpieza local de pedidos vencidos | `supabase/migrations/20261031223331_pulse_stock_cron.sql` |

---

## 1. Cómo encaja

```
AFTR (móvil / web)                Edge Function `baneco`              Banco Económico
───────────────────               ──────────────────────              ───────────────
crear pedido (RPC) ───────────────────────────────────────────────▶ (no interviene)
    │
    │ POST {accion:"qr"}  +  JWT del usuario
    ├──────────────────────────────▶ valida sesión y propiedad
    │                               reserva en PostgreSQL
    │                               ───────────────────────────────▶ POST generateQR
    │◀── {pago:{qrId, imagen, …}} ◀── guarda qr_id + imagen       ◀── qrId + qrImage
    │
    │ POST {accion:"estado"} cada pocos segundos
    ├──────────────────────────────▶ GET statusQR ──────────────────▶
    │◀── {pago:{estado}, orden} ◀──── si pagó: aftr_pago_confirmado
    │                                 (emite entradas / acredita saldo)
    │
pg_cron cada minuto ──────────────▶ {accion:"barrido"} + x-cron
                                    statusQR de los activos
                                    cancelQR de los vencidos
                                    paidQR del día (conciliación)
```

Reglas que no cambian nunca:

- **El cliente nunca marca un pago.** Solo el banco, respondido a una consulta
  nuestra, mueve un cobro a `pagado`.
- **La emisión tiene un solo camino**: `impl.aftr_emitir_orden`. Lo usa la
  confirmación bancaria y también la confirmación manual del boliche.
- **La función no confía en el cuerpo del webhook**: un aviso solo dispara una
  consulta `statusQR` al banco.
- **Certificación no acredita dinero ni emite productos** en la base real: el
  cobro queda en `revisar` con la nota `CERTIFICACION_SIN_EFECTO_MONETARIO`.

---

## 2. La API del banco

### 2.1 Ambientes

| Ambiente | Host | Base |
| --- | --- | --- |
| Certificación | `apimktdesa.baneco.com.bo` | `https://apimktdesa.baneco.com.bo/ApiGateway` |
| Producción | el que confirme el banco (hoy `apimkt.baneco.com.bo`) | `https://<host>/ApiGateway` |

`configuracion()` (en `bank.ts`) valida la URL antes de cualquier llamada y
falla si no cumple **todo** esto:

- esquema `https:`, sin usuario, contraseña, puerto, query ni fragmento;
- ruta exactamente `/ApiGateway` (con o sin barra final);
- `BANECO_AMBIENTE` igual a `certificacion` o `produccion`;
- en certificación, host igual a `apimktdesa.baneco.com.bo`;
- en producción, `BANECO_PRODUCTION_APPROVED=true`, `BANECO_PRODUCTION_HOST`
  igual al host de la URL, y host distinto del de certificación.

Es decir: **apuntar a producción requiere dos variables de acuerdo entre sí**,
no se llega por accidente cambiando una sola.

### 2.2 Transporte

Toda llamada sale con:

- `Content-Type: application/json` y `Accept: application/json`;
- `Authorization: Bearer <token>` salvo en `authenticate`;
- `AbortSignal.timeout(8000)` — **8 segundos**;
- `redirect: "error"` — un redirect es un fallo, no se sigue.

Una respuesta se acepta solo si es un objeto JSON (no arreglo, no `null`), con
`HTTP 2xx` y `responseCode === 0`. Cualquier otra cosa levanta `ErrorBanco`
con el paso y el código:

| Código de `ErrorBanco` | Significa |
| --- | --- |
| `RED` | no hubo respuesta (timeout, DNS, TLS, redirect) |
| `JSON_INVALIDO` | respondió algo que no es un objeto JSON |
| número HTTP (`401`, `404`, `500`…) | respuesta no 2xx |
| número de `responseCode` | el banco rechazó la operación |
| `CODIGO_INVALIDO` | `responseCode` no numérico |
| `SIN_TOKEN` | autenticó sin devolver token |
| `QR_INCOMPLETO` / `IMAGEN_INVALIDA` | `generateQR` sin `qrId`, sin `qrImage` o con imagen que no es base64 |
| `RESPUESTA_INVALIDA` | `statusQR` sin un `statusQRCode` entre 0, 1 y 9 |
| `IDENTIFICADOR_INVALIDO` | el pago informado no es uno solo para ese `qrId`, o viene sin `transactionId` |
| `LISTA_INVALIDA` | `paidQR` sin `paymentList` |

**`incierto`.** `ErrorBanco` lleva una bandera `incierto` que solo se activa en
`generateQR` y solo cuando el fallo no prueba que el banco no haya creado el QR
(red, JSON inválido, 5xx, `responseCode` no numérico, QR incompleto). Un cobro
incierto **no se vuelve a generar automáticamente**: queda en `revisar` con la
nota `GENERACION_INCIERTA`.

### 2.3 Cifrado (AES-256-CBC)

El banco recibe la contraseña y el número de cuenta cifrados. `cifrar()` hace:

1. La llave es `BANECO_AES_KEY` tal cual, en UTF-8: **exactamente 32 bytes**.
2. IV aleatorio de 16 bytes (`crypto.getRandomValues`).
3. `AES-CBC` sobre el texto en UTF-8.
4. Salida = `base64(IV || cifrado)`, el IV va al principio.

```ts
// db/functions/baneco/bank.ts
export async function cifrar(texto: string, secreto: string) { … }
```

Los endpoints `encrypt` / `decrypt` del manual **no se usan**: cifrar del lado
nuestro evita mandar la contraseña en claro para que el banco la cifre.

### 2.4 `POST /api/authentication/authenticate`

```http
POST /ApiGateway/api/authentication/authenticate
Content-Type: application/json

{ "userName": "<BANECO_USER>", "password": "<base64(IV||AES-CBC(BANECO_PASSWORD))>" }
```

Respuesta esperada: `{ "responseCode": 0, "token": "<JWT>", … }`.

Manejo del token en `Banco.autenticar()`:

- **Vigencia de credenciales.** Si `BANECO_CREDENTIALS_EXPIRES_AT` está vacía
  en producción, o está vencida o no es una fecha válida en cualquier
  ambiente, **no se llama al banco**: `Credenciales bancarias sin vigencia
  confirmada`. Es un corte nuestro, no del banco.
- **Caché.** El token se guarda hasta `exp - 60 s` leído del propio JWT; si el
  token es opaco, 25 minutos (el manual declara 30).
- **Una sola autenticación concurrente**: las llamadas paralelas comparten la
  misma promesa.
- **Reintento por expiración.** Ante `401` o `403` en cualquier operación se
  descarta el token, se autentica otra vez y se reintenta **una** vez.

Códigos vistos en producción durante la habilitación (ver `BANECO.md`):

| `responseCode` | Lectura |
| --- | --- |
| `0` | correcto, viene token |
| `401` | clave vencida |
| `404` | usuario sin habilitar en API Market |

### 2.5 `POST /api/qrsimple/generateQR`

```http
POST /ApiGateway/api/qrsimple/generateQR
Authorization: Bearer <token>

{
  "transactionId": "a1b2c3d4e5f60718293a4b5c6d7e8f", // nuestro id de compra (30)
  "accountCredit": "<base64(IV||AES-CBC(BANECO_ACCOUNT))>",
  "currency": "BOB",
  "amount": 150.00,
  "description": "Entrada AFTR",
  "dueDate": "2026-11-05",                          // fecha, zona America/La_Paz
  "singleUse": true,
  "modifyAmount": false
}
```

| Campo | Origen |
| --- | --- |
| `transactionId` | `pago_qr.transaction_id`: los primeros 30 caracteres del UUID del pedido sin guiones, único |
| `accountCredit` | `BANECO_ACCOUNT` cifrada en el momento |
| `amount` | `pago_qr.monto` (`numeric(12,2)`) |
| `dueDate` | `pago_qr.vence` (date), derivada de `vence_at` del pedido en hora de Bolivia |
| `singleUse` | siempre `true`: un QR, un pago |
| `modifyAmount` | siempre `false`: el pagador no puede cambiar el importe |

Respuesta usada: `qrId` (identificador bancario del QR) y `qrImage` (PNG en
base64, se valida que decodifique).

> El manual **no** declara que reenviar `generateQR` con el mismo
> `transactionId` sea idempotente. Por eso un resultado incierto se detiene
> para revisión en lugar de reintentarse.

### 2.6 `GET /api/qrsimple/v2/statusQR/{qrId}`

Sin cuerpo. Devuelve el estado del QR y, si está pagado, el pago.

| `statusQRCode` | Significado | Qué hacemos |
| --- | --- | --- |
| `0` | activo, sin pagar | nada; se vuelve a consultar |
| `1` | pagado | `aftr_pago_confirmado` con el objeto `payment` |
| `9` | anulado | `baneco_qr_anulado` |

Tolerancias y validaciones propias:

- se acepta la clave como `statusQRCode`, `statusQrCode` o `statusQRcode`
  (el manual no es consistente); cualquier otro valor es `RESPUESTA_INVALIDA`;
- `payment` puede venir como objeto o como arreglo; tiene que haber
  **exactamente uno** cuyo `qrId` sea el consultado y con `transactionId` no
  vacío, si no `IDENTIFICADOR_INVALIDO`.

Campos del `PaymentQR` que usamos: `qrId`, `amount`, `currency`,
`transactionId`. El objeto completo se guarda en `pago_qr.pago` (jsonb).

> `transactionId` del `PaymentQR` es **el número de la transacción bancaria**,
> no nuestro id de compra. Se guarda aparte, en `pago_qr.banco_tx`. No tienen
> por qué coincidir y no hay unicidad declarada sobre él.

### 2.7 `GET /api/qrsimple/v2/paidQR/{YYYYMMDD}`

Pagos de un día. El día lo decide el cursor de conciliación
(`baneco_conciliacion.dia`, calculado en PostgreSQL con zona
`America/La_Paz`), y antes de llamar se valida con `^\d{4}-\d{2}-\d{2}$` y se
le quitan los guiones. Respuesta usada: `paymentList` (arreglo de
`PaymentQR`); si no es un arreglo, `LISTA_INVALIDA`.

`bank.ts` también exporta `diaBolivia()` (UTC−4) para calcular el día
boliviano desde una marca de tiempo; hoy la usan las pruebas, no el barrido.

Es la red de seguridad: si un `statusQR` se perdió, el pago aparece acá y se
concilia igual.

### 2.8 `DELETE /api/qrsimple/cancelQR`

```http
DELETE /ApiGateway/api/qrsimple/cancelQR
Authorization: Bearer <token>

{ "qrId": "…" }
```

Se usa en el barrido, cuando el pedido ya venció y el QR sigue activo.
**Después de anular se vuelve a consultar el estado**, porque el pago y la
anulación pueden cruzarse: si el banco dice que entró plata, manda el pago.

### 2.9 Lo que el manual expone y no usamos

`encrypt`, `decrypt`, `accounts/history`, `batchPayment/upload`. No hay ningún
endpoint para renovar credenciales: la clave se cambia por los canales del
banco, no por la API.

---

## 3. Nuestra Edge Function `baneco`

```
POST https://<proyecto>.supabase.co/functions/v1/baneco
```

- Solo `POST` (y `OPTIONS` para CORS). Otro método: `405`.
- Cuerpo JSON de hasta **16 384 bytes**; más grande: `413`.
- CORS abierto, con `authorization, apikey, content-type, x-cron, x-baneco-token`.
- `verify_jwt = false` en `supabase/config.toml`: la función valida por sí
  misma sesión y propiedad, token de cron o token de webhook, según la acción.
  El barrido y el webhook no tienen sesión de usuario.

La acción va en el cuerpo:

| `accion` | Quién la llama | Autenticación |
| --- | --- | --- |
| `qr` | la app, para pagar | `Authorization: Bearer <JWT del usuario>` |
| `estado` | la app, mientras espera | `Authorization: Bearer <JWT del usuario>` |
| `barrido` | pg_cron | header `x-cron` = `BANECO_CRON_TOKEN` |
| *(sin `accion`)* | el banco, como webhook | header `x-baneco-token` = `BANECO_WEBHOOK_TOKEN` |

Un `accion` desconocido es `400`. Los tokens se comparan por digest SHA-256 en
tiempo constante y se exige un mínimo de **32 caracteres**: un secreto corto se
considera no configurado.

### 3.1 `tipo`: qué se está pagando

| `tipo` | Tabla del pedido | Columna en `pago_qr` |
| --- | --- | --- |
| `orden` (por omisión) | `aftr_ordenes` | `orden_id` |
| `recarga` | `pulse_recargas` | `recarga_id` |
| `pedido` | `aftr_bar_pedidos` | `pedido_id` |

Cualquier otro valor: `400 Destino inválido`.

### 3.2 `accion: "qr"`

```sh
curl -sS https://<proyecto>.supabase.co/functions/v1/baneco \
  -H "apikey: <anon key>" \
  -H "authorization: Bearer <JWT del usuario>" \
  -H "content-type: application/json" \
  -d '{"accion":"qr","orden":"<uuid del pedido>","tipo":"orden"}'
```

```json
{
  "pago": {
    "estado": "activo",
    "qrId": "123456789",
    "imagen": "<PNG en base64>",
    "monto": 150.00,
    "moneda": "BOB",
    "vence": "2026-11-05"
  }
}
```

Secuencia interna:

1. **Sesión y propiedad.** Sin `Authorization`: `401`. El id tiene que ser un
   UUID y el pedido tiene que ser del usuario; si no, `404 Pedido no
   encontrado` (no se distingue "no existe" de "no es tuyo").
2. **Mismo ambiente.** Un cobro de certificación no se puede continuar en
   producción ni al revés: `409`.
3. **QR ya emitido.** Si ya hay `qr_id`, se devuelve ese mismo QR — la llamada
   es idempotente. Solo si el QR está `activo` y el pedido ya no está
   `pendiente` o venció, responde `409 Este pedido ya no está disponible para
   pagar`.
4. **Credenciales antes de reservar.** Se cifra la cuenta y se autentica
   *antes* de tocar la base, para no dejar una reserva colgada si falta un
   secreto o la habilitación.
5. **Reserva en PostgreSQL** (`baneco_reservar_destino`): inserta o reutiliza
   la fila, la deja en `generando` con un `generacion_id` nuevo. Dos pedidos
   simultáneos del mismo pedido no generan dos QR: el segundo recibe
   `reservado: false` y, o devuelve el QR existente, o responde `409` con
   "El QR se está preparando" o "El cobro necesita revisión. No vuelvas a
   pagar".
6. **`generateQR`.** Si falla: `revisar` + `GENERACION_INCIERTA` cuando el
   resultado es dudoso, `fallido` + `GENERACION_RECHAZADA` cuando el banco
   rechazó claramente. El `UPDATE` exige `estado = 'generando'` **y** el mismo
   `generacion_id`: una ejecución vieja no puede pisar una nueva.
7. **Guardado.** `estado = 'activo'`, `qr_id`, `qr_imagen`. Se guarda incluso
   si el pedido se canceló durante la llamada: el identificador bancario no se
   pierde nunca.

### 3.3 `accion: "estado"`

```sh
curl -sS … -d '{"accion":"estado","orden":"<uuid>","tipo":"orden"}'
```

```json
{ "pago": { "estado": "pagado", "qrId": "123456789", "monto": 150.00, "moneda": "BOB", "vence": "2026-11-05" },
  "orden": "confirmada" }
```

- Sin cobro todavía: `{"pago": null, "orden": "<estado del pedido>"}`.
- **La imagen no se repite** en esta respuesta (solo la trae `qr`).
- Consulta al banco como máximo **una vez cada 4 segundos** por cobro
  (`ultimo_chequeo`), aunque la app pregunte más seguido.
- Si el banco dice pagado, confirma *dentro de esta misma llamada*: la app ve
  `pago.estado = "pagado"` y el pedido ya `confirmada`.

### 3.4 `accion: "barrido"`

```sh
curl -sS https://<proyecto>.supabase.co/functions/v1/baneco \
  -H "x-cron: <BANECO_CRON_TOKEN>" -H "content-type: application/json" \
  -d '{"accion":"barrido"}'
```

```json
{ "revisados": 7, "confirmados": 1, "anulados": 2, "errores": 0, "conciliados": 3 }
```

o `{"ocupado": true}` si otra ejecución tiene el lease.

Qué hace, en orden:

1. `baneco_tomar_barrido` toma un **lease de 90 segundos** por ambiente y
   devuelve el **día del cursor** de conciliación. Si hay otro corriendo,
   devuelve `null` → `{"ocupado": true}`.
   De paso, marca como `revisar` + `GENERACION_INCIERTA` todo lo que quedó en
   `generando` hace más de 2 minutos (una ejecución que murió generando).
2. `baneco_liberar_sin_qr` libera pedidos de barra vencidos **sin** generación
   bancaria en curso.
3. Hasta **100 cobros activos** con `qr_id`, ordenados por `ultimo_chequeo`
   (los nunca consultados primero), y para cada uno `statusQR`. Corta a los
   **24 segundos** para dejar tiempo a la conciliación.
   - pagado → `aftr_pago_confirmado`;
   - anulado → `baneco_qr_anulado`;
   - activo pero vencido (por `limite_at`, o por el estado y `vence_at` del
     pedido) → `cancelQR` y **vuelve a consultar** el estado.
   - Un error no corta el barrido: suma `intentos`, actualiza `ultimo_chequeo`
     y sigue con el siguiente.
4. `paidQR` del día del cursor. Cada pago cuyo `qrId` esté en `pago_qr` y no
   esté ya `pagado` pasa por `aftr_pago_confirmado`. Corta a los **42
   segundos**.
5. `baneco_finalizar_barrido` suelta el lease y **avanza el cursor un día**
   solo si el día se procesó completo, sin pasar de hoy.

El cron manda `timeout_milliseconds := 55000`: los cortes de 24 s y 42 s están
para que la función termine y suelte el lease antes de que pg_net la abandone.

### 3.5 Webhook (cuerpo sin `accion`)

Deshabilitado mientras no exista `BANECO_WEBHOOK_TOKEN`: responde `404
Notificaciones no habilitadas`. Con el secreto configurado:

```http
POST /functions/v1/baneco
x-baneco-token: <BANECO_WEBHOOK_TOKEN>

{ "Payment": { "qrId": "123456789", … } }
```

```json
{ "responseCode": 0, "message": "" }
```

- Acepta `Payment` o `payment`; necesita `qrId`; si no, `400`.
- **El cuerpo no se usa para confirmar nada.** Se busca el cobro por `qrId` y,
  si no está `pagado`, se consulta `statusQR` al banco. Un aviso falso no mueve
  plata.
- El manual no documenta firma ni cabeceras del webhook; `x-baneco-token` es
  una convención nuestra que hay que acordar con el banco antes de habilitarlo.

### 3.6 Errores de la función

| HTTP | Cuerpo | Cuándo |
| --- | --- | --- |
| `400` | `JSON inválido.` / `Solicitud inválida.` / `Acción desconocida.` / `Destino inválido.` / `Notificación inválida.` | cuerpo mal formado o acción/destino que no existe |
| `401` | `Iniciá sesión.` / `No autorizado.` | sin JWT, JWT inválido, o token de cron/webhook que no coincide |
| `404` | `Pedido no encontrado.` / `Notificaciones no habilitadas.` | id que no es UUID, pedido ajeno o inexistente, webhook sin secreto |
| `405` | `Método no permitido.` | no es POST |
| `409` | `Este pedido venció o ya fue resuelto.` · `Este pedido ya no está disponible para pagar.` · `Este pedido corresponde a otro ambiente de cobro.` · `El QR se está preparando. Volvé a intentar en unos segundos.` · `El cobro necesita revisión. No vuelvas a pagar.` | conflicto de estado |
| `413` | `Solicitud demasiado grande.` | cuerpo de más de 16 KiB |
| `502` | `No pudimos verificar el cobro con el banco. Volvé a intentar.` | `ErrorBanco` |
| `503` | `El cobro no está disponible. Tu pedido quedó guardado.` | cualquier otro error interno |

Los mensajes son para mostrarse tal cual al usuario. Los detalles técnicos
(paso y código del banco) van a los logs como JSON, nunca a la respuesta.

---

## 4. Base de datos

### 4.1 `pago_qr`

Un cobro por pedido. `check (num_nonnulls(orden_id, recarga_id, pedido_id) = 1)`:
exactamente un destino.

| Columna | Tipo | Notas |
| --- | --- | --- |
| `id` | uuid | |
| `orden_id` / `recarga_id` / `pedido_id` | uuid único | el destino; uno solo, no nulo |
| `proveedor` | text | `baneco` |
| `ambiente` | text | `certificacion` o `produccion`; separa los dos mundos |
| `transaction_id` | text único | nuestro id de compra, 30 caracteres del UUID |
| `qr_id` | text único | identificador del banco; nulo hasta que `generateQR` responde |
| `qr_imagen` | text | PNG en base64 |
| `monto` | numeric(12,2) | `> 0` |
| `moneda` | text | `BOB` |
| `vence` | date | `dueDate` que recibió el banco |
| `limite_at` | timestamptz | vencimiento real del pedido (hora, no día) |
| `estado` | text | ver abajo |
| `pago` | jsonb | el `PaymentQR` completo que devolvió el banco |
| `banco_tx` | text | `PaymentQR.transactionId`, el número bancario |
| `pagado_at` | timestamptz | |
| `nota` | text | la incidencia, si hay |
| `intentos` | int | errores acumulados en el barrido |
| `ultimo_chequeo` | timestamptz | ordena la rotación del barrido y limita las consultas |
| `generacion_id` | uuid | identifica el intento de generación en curso |
| `generacion_iniciada_at` | timestamptz | para detectar generaciones abandonadas |
| `created_at` | timestamptz | |

Estados y transiciones:

```
                   ┌───────────────────────── reserva ─────────────────────────┐
                   ▼                                                           │
(sin fila) ──▶ generando ──▶ activo ──▶ pagado                                 │
                   │            │                                              │
                   │            ├──▶ anulado   (statusQR = 9 / cancelQR)       │
                   │            └──▶ vencido                                   │
                   ├──▶ fallido  (el banco rechazó; se puede regenerar) ───────┘
                   └──▶ revisar  (nunca se regenera solo)
```

- `fallido` es el **único** estado desde el que se vuelve a generar.
- `revisar` siempre pide una persona. Las notas se listan en §6.

**RLS.** `pago_qr` tiene RLS y una sola política de lectura: el dueño del
pedido puede leer la fila de su `orden_id`. **No hay políticas de escritura**:
solo la función, con `service_role`. Los cobros de recargas y pedidos de barra
no son legibles desde el cliente; su estado se consulta con `accion: "estado"`.

### 4.2 `baneco_conciliacion`

Cursor y lease del barrido, una fila por ambiente. Sin acceso para
`authenticated` ni `anon`; solo `service_role`.

| Columna | Para qué |
| --- | --- |
| `ambiente` | clave primaria |
| `dia` | día que falta conciliar (cursor persistente) |
| `lease`, `lease_hasta` | un solo barrido a la vez, 90 segundos |
| `ultimo_intento`, `ultimo_exito` | diagnóstico |
| `errores` | errores de la última corrida |

El cursor arranca en el día del `pago_qr` más antiguo del ambiente. Si el
servicio estuvo caído tres días, los tres se concilian uno por corrida; no se
saltean.

### 4.3 Funciones

Todas `security definer`. Las que mueven dinero están **revocadas** para
`public`, `anon` y `authenticated`, y concedidas solo a `service_role`.

| Función | Llamada por | Qué hace |
| --- | --- | --- |
| `baneco_reservar_destino(p_tipo, p_id, p_cliente, p_ambiente)` | función | bloquea el pedido, crea o reutiliza el cobro y lo deja en `generando` con `generacion_id` nuevo. Valida estado, vencimiento, total > 0, propiedad y ambiente |
| `baneco_reservar_qr(p_orden, p_cliente, p_ambiente)` | función | atajo histórico: `baneco_reservar_destino('orden', …)` |
| `aftr_pago_confirmado(p_qr, p_pago)` | función | **el único lugar donde un pago se vuelve dinero**; ver §4.4 |
| `aftr_pago_confirmado_entradas(p_qr, p_pago)` | la anterior | la parte de entradas y mesas |
| `baneco_qr_anulado(p_qr)` | función | marca `anulado` y libera el pedido de barra o cancela la recarga. No toca nada si el cobro está `pagado`, en `revisar` o ya tiene `banco_tx` |
| `baneco_tomar_barrido(p_ambiente)` | función | lease + día del cursor + marcado de generaciones abandonadas |
| `baneco_finalizar_barrido(p_ambiente, p_token, p_dia_ok, p_errores)` | función | suelta el lease y avanza el cursor |
| `baneco_liberar_sin_qr()` | función y cron | libera pedidos de barra vencidos sin generación bancaria |
| `aftr_cancelar_cobro(p_tipo, p_id)` | el cliente | cancela lo suyo; si ya hay QR activo, adelanta `limite_at` para que el barrido lo anule en el banco. Se niega si hay `banco_tx` o el cobro está `pagado`, en `revisar` o `generando` |
| `aftr_confirmar_orden(p_orden)` | staff del boliche | reintento manual de la **emisión**, solo con dinero ya confirmado por el banco |
| `aftr_pagar_pulse(p_orden)` | el cliente | paga con saldo PULSE; se niega si el pedido ya tiene un QR vivo |
| `impl.aftr_emitir_orden(p_orden, p_por)` | las dos anteriores | emite entradas o cierra la mesa. Revocada a todo el mundo |

### 4.4 `aftr_pago_confirmado`: las validaciones que importan

Con la fila de `pago_qr` y el pedido **bloqueados** (`for update`), en este
orden:

1. Si el cobro ya está `pagado`: devuelve `{"estado":"pagado","nuevo":false}` y
   no emite otra vez. **Idempotente**: reintentos, consultas dobles y avisos
   repetidos no duplican entradas.
2. Compara contra lo que pedimos. Tienen que coincidir **las cuatro**:
   `qrId`, `amount` (`numeric`, con el texto no numérico tratado como nulo),
   `currency` en mayúsculas, y `transactionId` no vacío. Si falla alguna:
   `revisar` + `DATOS_BANCARIOS_NO_COINCIDEN`, y no se emite nada.
3. **Certificación corta acá**: `revisar` +
   `CERTIFICACION_SIN_EFECTO_MONETARIO`. La plata de prueba no emite productos
   reales.
4. Marca `pagado`, guarda `pago`, `banco_tx` y `pagado_at`.
5. Según el destino:
   - **orden**: emite por `impl.aftr_emitir_orden` y registra la venta del
     boliche (`impl.aftr_venta`, método `qr`). Si el pedido ya estaba
     `confirmada` (lo confirmó el boliche a mano), **registra el dinero sin
     emitir de nuevo**.
   - **recarga**: acredita saldo PULSE (`impl.pulse_mover`) y marca la recarga
     `confirmada`.
   - **pedido de barra**: `impl.aftr_bar_emitir`.
6. **Pago tardío.** Un pedido `vencida` se emite igual, pero
   `impl.aftr_emitir_orden` vuelve a mirar el cupo de la fase: si la reserva
   vencida ya liberó lugares y no quedan, falla y el cobro queda en `revisar`
   con `PAGADO_SIN_EMISION`. No se sobrevende.
7. Si no se pudo emitir, además de la nota se abre una incidencia en
   `aftr_incidencias` para los pedidos de barra.

---

## 5. Flujos

### 5.1 Compra que sale bien

1. La app crea el pedido (`aftr_comprar`, `aftr_reservar_mesa`,
   `aftr_recargar_pulse`, pedido de barra…). El pedido tiene `vence_at`.
2. `accion: "qr"` → la app muestra la imagen y el importe.
3. La persona paga desde su banco.
4. `accion: "estado"` cada pocos segundos → el primer `statusQR` que diga
   pagado emite y la app pasa a "Pago confirmado".
5. Si la app se cerró, el barrido confirma igual en menos de un minuto.

### 5.2 El QR vence sin pago

El barrido ve el pedido vencido, llama `cancelQR`, vuelve a consultar y marca
`anulado`. El pedido de barra se libera y la recarga se cancela.

### 5.3 Pago justo cuando se anula

Se anula y se vuelve a consultar en la misma pasada. Si el banco informa el
pago, gana el pago: se emite (con el control de cupo) o queda en `revisar`.

### 5.4 El `statusQR` se perdió

Al día siguiente —o cuando el servicio vuelva— `paidQR` del día del cursor
trae el pago y se concilia. Por eso el cursor es persistente y el cron corre
también sin QR activos, mirando los últimos 2 días.

### 5.5 Dos pagos simultáneos del mismo pedido

La reserva en PostgreSQL bloquea el pedido: solo una ejecución queda
`reservado: true`. La otra recibe el QR existente o un `409` que pide esperar.

---

## 6. Incidencias: qué significa cada nota

| `nota` | Estado | Qué pasó | Qué hacer |
| --- | --- | --- | --- |
| `GENERACION_INCIERTA` | `revisar` | `generateQR` no respondió con certeza; el banco pudo haber creado el QR | consultar en el banco por `transaction_id`; **no** regenerar a ciegas |
| `GENERACION_RECHAZADA` | `fallido` | el banco rechazó claramente | se puede volver a pedir el QR |
| `DATOS_BANCARIOS_NO_COINCIDEN` | `revisar` | importe, moneda, `qrId` o número bancario no cuadran | revisar contra el banco antes de entregar nada |
| `CERTIFICACION_SIN_EFECTO_MONETARIO` | `revisar` | pago en certificación | normal en pruebas; no requiere acción |
| `PAGADO_SIN_EMISION` | `revisar` | entró la plata y la emisión falló (sin cupo, mesa liberada, etc.) | resolver con el cliente; si corresponde, `aftr_confirmar_orden` reintenta la emisión |
| `PAGADO_CON_PEDIDO_CANCELADO` | `revisar` | pagó un pedido ya cancelado | devolución manual |

Los reintegros y transferencias **no están automatizados**.

---

## 7. Configuración

### 7.1 Secretos de la función

Nombres en `db/functions/baneco/baneco.env.example`. Los valores van **solo**
en los secretos de Supabase: nunca en Git, nunca en el frontend.

| Variable | Obligatoria | Qué es |
| --- | --- | --- |
| `BANECO_AMBIENTE` | sí | `certificacion` o `produccion` |
| `BANECO_BASE_URL` | sí | `https://<host>/ApiGateway/` |
| `BANECO_USER` | sí | usuario de API Market |
| `BANECO_PASSWORD` | sí | se manda cifrada |
| `BANECO_AES_KEY` | sí | **32 bytes exactos**; es distinta por ambiente |
| `BANECO_ACCOUNT` | sí | cuenta de cobro; se manda cifrada |
| `BANECO_CREDENTIALS_EXPIRES_AT` | en producción | ISO 8601; vencida o inválida = no se llama al banco |
| `BANECO_CRON_TOKEN` | sí | ≥32 caracteres; habilita `accion: "barrido"` |
| `BANECO_WEBHOOK_TOKEN` | no | ≥32 caracteres; sin esto el webhook responde 404 |
| `BANECO_PRODUCTION_APPROVED` | en producción | `true` solo con autorización del responsable |
| `BANECO_PRODUCTION_HOST` | en producción | igual al host de `BANECO_BASE_URL` |

Las inyecta Supabase: `SUPABASE_URL` y `SUPABASE_SERVICE_ROLE_KEY`.

### 7.2 Vault (para el cron)

| Secreto | Valor |
| --- | --- |
| `baneco_project_url` | `https://<proyecto>.supabase.co` |
| `baneco_cron_token` | **el mismo** valor que `BANECO_CRON_TOKEN` |

### 7.3 Cron

| Job | Cada | Qué hace |
| --- | --- | --- |
| `baneco-barrido` | 1 minuto | `POST /functions/v1/baneco` con `{"accion":"barrido"}`, `x-cron` desde Vault, `timeout_milliseconds := 55000`. Solo si hay cobros `activo`/`generando` o creados en los últimos 2 días |
| `aftr-stock-liberar` | 1 minuto | `select public.baneco_liberar_sin_qr();` — limpieza local, no depende del banco |

### 7.4 Publicar

```sh
# la migración primero, una sola vez
supabase db push            # o aplicar 20261031172015_baneco_seguro.sql al proyecto correcto

# la función (config.toml ya apunta a db/functions/baneco y declara verify_jwt = false)
supabase functions deploy baneco --project-ref <ref> --use-api

# recién con secretos cargados y la función publicada
psql "<conexión>" -f db/45-baneco-barrido.sql
```

---

## 8. Pruebas sin dinero real

```sh
# adaptador del banco y contrato de la función (Deno, sin red)
cd db/functions/baneco && deno test --no-remote tests/
deno check --no-remote index.ts
deno lint bank.ts handler.ts index.ts tests/

# reserva, confirmación y cursor sobre PostgreSQL descartable
sh tools/test_baneco.sh          # crea y borra su propio cluster; requiere PostgreSQL 17

# cliente web
node --test tests/baneco-web.test.mjs

# cliente móvil
cd aftr_mobile && flutter analyze --no-pub && flutter test --no-pub test/pago_qr_test.dart
```

Ninguna de estas pruebas llama al banco ni lee `.env.local`.

**Nunca** ejecutar `generateQR` en producción para probar: es un cobro real.
`statusQR` y `paidQR` son de lectura y sí se pueden verificar (un `qrId`
inexistente devuelve 404, que es la respuesta esperada).

---

## 9. Diagnóstico

```sql
-- el cron existe y está activo
select jobname, schedule, active from cron.job where jobname = 'baneco-barrido';

-- últimas corridas (que PostgreSQL mandó el pedido, no que haya confirmado pagos)
select status, start_time, end_time
  from cron.job_run_details
 where jobid in (select jobid from cron.job where jobname = 'baneco-barrido')
 order by start_time desc limit 5;

-- cursor de conciliación: el día tiene que avanzar
select ambiente, dia, ultimo_intento, ultimo_exito, errores from public.baneco_conciliacion;

-- panorama de cobros
select estado, ambiente, count(*) from public.pago_qr group by estado, ambiente;

-- lo que necesita una persona
select id, ambiente, estado, nota, monto, created_at
  from public.pago_qr where estado = 'revisar' order by created_at desc;

-- respuestas HTTP de pg_net (timeouts incluidos)
select id, status_code, timed_out from net._http_response order by id desc limit 5;
```

Un `succeeded` en `cron.job_run_details` solo prueba que PostgreSQL envió la
solicitud. Para saber si el barrido hizo algo, mirar `net._http_response`, el
avance de `baneco_conciliacion.dia` y los logs de la función.

Los logs de la función son JSON de una línea, sin datos del pagador:

```json
{"evento":"barrido_qr","paso":"/api/qrsimple/v2/statusQR/123","codigo":500}
```

`evento` puede ser `barrido_qr`, `conciliacion` o `solicitud`; `codigo` es
`ERROR_INTERNO` cuando el fallo no viene del banco.

---

## 10. Clientes

| Cliente | Dónde | Qué hace |
| --- | --- | --- |
| AFTR móvil | `aftr_mobile/lib/data/aftr_repo.dart` (`qrDePago`, `estadoPago`) | pide el QR, consulta el estado sin superponer llamadas y conserva los centavos del importe |
| AFTR web | `aftr_web/aftr.js` (`cobroBanco`, `hojaPago`) | pide el QR, permite guardar la imagen y sigue el estado; muestra el mensaje de error que manda la función |

Las dos invocan la función con el SDK (`functions.invoke('baneco', …)`), que ya
manda la sesión del usuario. Ninguna conoce las credenciales del banco ni lee
`pago_qr` para decidir si algo está pagado.

---

## 11. Límites conocidos y preguntas abiertas

- **Una sola cuenta de cobro.** Todo entra a la cuenta de
  `BANECO_ACCOUNT`; la distribución a los boliches es manual.
- **Webhook sin especificación.** El manual no define firma ni cabeceras:
  queda deshabilitado hasta acordarlo. Mientras tanto alcanzan `statusQR` y la
  conciliación.
- **Idempotencia de `generateQR`** no declarada por el banco: por eso un
  resultado incierto se detiene.
- **Alcance de unicidad de `PaymentQR.transactionId`**, retención histórica de
  `paidQR` y límites de consultas: sin confirmar. No se creó unicidad sobre
  `banco_tx` por eso.
- **Expiración del QR.** `dueDate` es una fecha; el pedido vence a una hora.
  El barrido usa `limite_at` (hora) para anular, no la fecha del banco.
- **No hay pantalla de incidencias** en Venue: los cobros en `revisar` se
  miran por SQL.
