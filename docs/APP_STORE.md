# App Store: estado y notas de revisión

Preparación de **AFTR** (app pública) y **VENUE** (gestión) para la App Store,
siguiendo `GUIA_MAESTRA_APPLE_APP_STORE_2026.md`.

## AFTR · estado al 05/11/2026

Los cinco bloqueantes de la auditoría inicial están resueltos y en producción.

| Requisito | Estado | Dónde |
|---|---|---|
| Bloquear usuarios (1.2) | Hecho | Menú del visor de historias; lista en Cuenta → Ajustes → Cuentas bloqueadas |
| Reportar contenido (1.2) | Ya existía | Menú del visor |
| Normas de comunidad (1.2) | Hecho | `aftrvenue.com/normas` |
| Política de privacidad (5.1.1) | Hecho | `aftrvenue.com/privacidad` |
| Términos | Hecho | `aftrvenue.com/terminos` |
| Canal de soporte | Hecho | `soporte.aftrvenue@aftrvenue.com`, en Ajustes |
| Eliminación de cuenta (5.1.1(v)) | Ya existía | Cuenta → Ajustes → Eliminar cuenta |
| `PrivacyInfo.xcprivacy` | Hecho | `ios/Runner/PrivacyInfo.xcprivacy` |
| Sign in with Apple (4.8) | Ya existía | Botón primario, con nonce seguro |
| Apple Maps en "Cómo llegar" | Ya existía | Universal link HTTPS |
| Xcode 26+ / SDK 26+ | Verificado | Xcode 27.1 |
| Target iOS 13+ | Cumple | iOS 15 |

Pendiente: cuentas demo, cuestionario de edad y envío.

## Por qué AFTR no necesita In-App Purchase

Es la pregunta que más probablemente haga el revisor, porque la app muestra un
monedero. La respuesta corta: **todo lo que se compra se consume
presencialmente en el local** (Guideline 3.1.3(e)).

| Qué se compra | Dónde se consume | Cómo se paga |
|---|---|---|
| Entrada a evento | Puerta del boliche | QR bancario o saldo PULSE |
| Reserva de mesa | Local | QR bancario o saldo PULSE |
| Pedido de barra | Barra, bebida física | QR bancario o saldo PULSE |

**PULSE es saldo prepago en bolivianos**, no una moneda digital: 1 PULSE = Bs 1.
`db/35-aftr.sql:101` limita las órdenes a `entrada` y `mesa` por constraint, así
que no existe forma de comprar un bien digital con ese saldo. No hay
suscripciones, desbloqueos, destacados pagos ni contenido premium, y no hay
ningún SDK de compras in-app en el repositorio.

La **reventa entre personas** tampoco pasa por AFTR: es una transferencia
bancaria directa entre comprador y vendedor, con comprobante. AFTR registra la
operación e invalida la entrada original, pero no toca ese dinero.

El cobro lo procesa **Banco Económico** por QR interoperable: la persona escanea
con la app de su propio banco.

## Review Notes · AFTR

> **App Review Information — AFTR**
>
> **Purpose:** AFTR is a nightlife app for Santa Cruz de la Sierra, Bolivia.
> People browse clubs and events, buy entry tickets with a QR code, book tables
> and order at the bar. Tickets are scanned at the venue door.
>
> **Demo login:** no demo account is needed, and none is provided on purpose.
> AFTR has **no passwords**: the only ways in are Sign in with Apple and Google.
> The app is **fully browsable without an account** — events, venues, map,
> stories and the start of the purchase flow all work logged out. To test the
> account features, please sign in with your own Apple ID using the
> "Continuar con Apple" button; it takes one tap and you can delete the account
> afterwards from Cuenta → Ajustes → Eliminar cuenta.
> An account is only required to: buy a ticket, post a story, report or block,
> and follow a venue.
>
> **About completing a purchase:** tickets are paid with an interoperable bank
> QR code that the buyer scans with their own Bolivian banking app, so the
> payment itself cannot be completed from outside Bolivia. The reviewer can see
> the whole flow up to the generated QR code, which is where our responsibility
> ends and the bank's begins. If you need to see a paid ticket, please ask and
> we will record a video of a real purchase.
>
> **Main features and paths:**
> 1. Browse events → Home tab
> 2. Venue page and directions → tap any venue → "Cómo llegar" (opens Apple Maps)
> 3. Buy a ticket → open an event → "Comprar" → a bank QR is shown
> (there is a live event priced at 1 Bs for testing)
> 4. Stories (user content) → tap a story ring on Home
> 5. Report a story → open a story → "..." → "Reportar historia"
> 6. Block a user → open a story → "..." → "Bloquear a esta persona"
> 7. Unblock → Cuenta → Ajustes → Cuentas bloqueadas
> 8. Account deletion → Cuenta → Ajustes → Eliminar cuenta
> 9. Privacy, Terms and Community Guidelines → Cuenta → Ajustes → Ayuda y legales
>
> **Payments and IAP:** AFTR does not use In-App Purchase. Everything sold is a
> physical good or service consumed in person at the venue (event entry, table
> booking, bar drinks), under Guideline 3.1.3(e). Payment is made with an
> interoperable bank QR processed by Banco Económico; the user scans it with
> their own banking app. "PULSE" is prepaid balance in local currency
> (1 PULSE = 1 Bolivian boliviano) that can only be spent on those same
> in-person items. There are no digital goods, subscriptions or unlockables.
>
> **User content:** users can post photos and videos ("historias") that expire
> after 24 hours. Reporting and blocking are available from the story viewer,
> community guidelines are published at aftrvenue.com/normas, and reports are
> answered within 48 hours at soporte.aftrvenue@aftrvenue.com.
>
> **Third-party services:** Supabase (database, auth, storage), Vercel (web
> hosting), Apple and Google (sign-in), Banco Económico (payment QR),
> Apple Maps (directions).
>
> **Regional restrictions:** the venues are in Bolivia, but the app is
> browsable from anywhere.
>
> The backend and the demo account will remain available during the review.

## Cuestionario de edad

Responder **desde cero**, sin copiar de otra app. Lo que corresponde a AFTR:

- Contenido generado por usuarios: **sí** (historias, con reporte y bloqueo).
- Alcohol, tabaco o drogas: **referencias frecuentes** — son eventos de vida
  nocturna.
- Controles parentales: **no**. No marcar que sí: eso provocó un rechazo real.
- La app es para mayores de 18, como dicen los términos.

## VENUE · estado al 05/11/2026

Auditada y con sus bloqueantes resueltos.

| Requisito | Estado | Dónde |
|---|---|---|
| Eliminación de cuenta (5.1.1(v)) | **Hecho** | Cuenta → Eliminar mi cuenta, en el shell del relacionador y en el panel de perfil |
| Privacidad, términos, normas y soporte | **Hecho** | Cuenta → Ayuda y legales |
| `PrivacyInfo.xcprivacy` | **Hecho** | `ios/Runner/PrivacyInfo.xcprivacy` |
| Cuentas demo | **Hecho** | `applereview` y `reviewrrpp`, en Burtown |
| Purpose strings | Ya estaban bien | Los tres coinciden con el uso real |
| `ITSAppUsesNonExemptEncryption` | Ya estaba | `false` |
| Target iOS 13+ | Cumple | iOS 15 |

### Lo que hace `venue_eliminar_mi_cuenta()`

Reusa `impl.eliminar_usuario`, que ya decidía entre borrar y archivar según
hubiera actividad. Lo que agrega: cuando el perfil queda archivado para la
contabilidad del boliche, se borran igual nombre, foto, teléfono y cupos, y en
todos los casos se elimina el usuario de `auth` para que el acceso se corte.

Si la persona es **administradora principal** de un boliche, la función se
niega y le pide pasar la administración primero. Sin ese freno, un dueño podía
dejar su club sin administrador.

### Pendientes menores de VENUE

- `Info.plist` declara landscape mientras `main.dart` fuerza vertical.
- Sin Associated Domains, los enlaces `venuebol.com/?invite=…` no abren la app;
  solo funciona el esquema `venue://`.
- Subir el build number antes de cada envío.
- Sign in with Apple va por OAuth web, sin capability declarada. Si el proveedor
  no está habilitado en Supabase, el botón falla y eso es rechazo por bug:
  **probarlo antes de enviar**.

## Review Notes · VENUE

> **App Review Information — VENUE**
>
> **Purpose:** VENUE is the staff-side tool for nightclubs in Bolivia. Club
> managers and promoters use it to run an event night: guest lists, QR ticket
> sales, table bookings, door scanning and settlements. The public-facing app
> is a separate one called AFTR.
>
> **Demo login:** open the app, choose the **"Boliches"** door and sign in with
> username and password.
> Username: `applereview` — Password: `[en App Store Connect]`
> This is an admin account for the demo club "Burtown", with events, tables and
> lists already loaded.
> A second account shows the promoter side: `reviewrrpp` (same door).
>
> **Why a demo account is required:** a newly registered account belongs to no
> club until a club approves it, so it would show an empty screen.
>
> **Main features and paths:**
> 1. Event management → Eventos → "Gestionar evento"
> 2. Guest lists and QR tickets → Accesos
> 3. Door scanner → Accesos → Escáner (needs a ticket QR; ask us for a test one)
> 4. Tables → Mesas
> 5. Account deletion → Cuenta → Eliminar mi cuenta
> 6. Privacy, Terms and Community Guidelines → Cuenta → Ayuda y legales
>
> **Not a template app:** this is a single app serving many clubs, not one
> rebranded app per client. Each club is a tenant inside the same app
> (Guideline 4.2.6 / 4.3).
>
> **User content:** staff can publish 24-hour stories that appear in the public
> AFTR app, and they receive and act on reports from AFTR users. Community
> guidelines are at aftrvenue.com/normas.
>
> **Third-party services:** Supabase (database, auth, storage), Apple Maps
> (venue location), Banco Económico (payment QR shown to customers).
>
> The backend and both demo accounts will remain available during the review.

