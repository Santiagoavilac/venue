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

## VENUE · pendiente

Auditoría en curso. Puntos que ya se sabe que hay que resolver:

- Cómo accede el revisor: la app sirve a personal de boliches, así que hay que
  darle una cuenta demo con datos de ejemplo y, si hay roles, una por rol.
- Verificar si se pueden crear cuentas y, en ese caso, que exista eliminación.
- Riesgo 4.2.6 / 4.3: es **una sola app que sirve a muchos boliches**, no una
  plantilla replicada por cliente. Eso es el patrón correcto, pero conviene
  dejarlo dicho en las notas.
