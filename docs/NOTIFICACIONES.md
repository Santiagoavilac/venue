# Notificaciones push · lo que ya está y lo que falta

Dos proyectos de Firebase, uno por app, para que una no pueda mandarle
notificaciones a los usuarios de la otra:

| | AFTR | Venue |
|---|---|---|
| Proyecto | `aftr-6d08d` | `venue-f1156` |
| App de iOS | `app.venue.aftr` | `app.venue.venueMobile` |
| App de Android | `app.aftr.aftr_mobile` | `app.venue.venue_mobile` |
| Plan | Spark (sin costo) | Spark (sin costo) |

Los dos quedaron **sin Google Analytics y sin Gemini**: ninguno hace falta para
mandar notificaciones, y los dos traen su propio procesamiento de datos de la
gente que usa la app. Se pueden prender después si alguna vez sirven.

## Los archivos de configuración, en el repo

    aftr_mobile/ios/Runner/GoogleService-Info.plist
    aftr_mobile/android/app/google-services.json
    venue_mobile/ios/Runner/GoogleService-Info.plist
    venue_mobile/android/app/google-services.json

No son secretos: viajan dentro de la app y las claves que traen están atadas al
identificador de cada app. Van al repo a propósito, para que compilar no
dependa de que alguien se acuerde de bajarlos.

## Los secretos, en Supabase

| Secreto | Qué es |
|---|---|
| `FCM_AFTR`, `FCM_VENUE` | La cuenta de servicio de cada proyecto, en una línea. Es con lo que el servidor manda las notificaciones (FCM HTTP v1). |
| `FCM_AFTR_PROJECT`, `FCM_VENUE_PROJECT` | El id del proyecto, que va en la URL de la API. |
| `APNS_KEY`, `APNS_KEY_ID`, `APNS_TEAM_ID` | La clave de push de Apple. Una sola para las dos apps: es del equipo, no de la app. |

Las cuentas de servicio **se borraron del disco** después de cargarlas: Google
no las vuelve a mostrar, así que si alguna vez se pierden se genera una nueva
desde la consola y se reemplaza el secreto.

La clave de Apple quedó además en `~/Documents/venue-claves/`, porque Apple la
deja bajar **una sola vez**. No está en el repo ni va a estarlo.

## Cómo funciona de punta a punta

    la app pide el permiso  ->  guarda su token en `dispositivos`
    algo pasa en la base    ->  impl.avisar() encola en `avisos_push`
    el cron, cada minuto    ->  la Edge Function `push` entrega por FCM

Se guarda **el aparato y no la persona**: una fila por token, con de qué app
es. Un teléfono puede tener las dos apps y la misma persona puede entrar desde
varios teléfonos, así que atarlo a la persona perdería aparatos. Si el mismo
token vuelve —reinstalación, o un teléfono prestado— cambia de dueño en vez de
duplicarse.

Cada app manda con **su propia cuenta de servicio**: que una no pueda
notificarle a los usuarios de la otra no depende de que nadie se olvide, son
credenciales distintas.

Un token que FCM da por muerto se borra en el mismo paso, y si todos los
aparatos de un aviso están muertos el aviso se cierra en vez de reintentarse.

### El permiso se pide tarde, a propósito

En AFTR, recién cuando la persona ya tiene una entrada que esperar. En Venue,
en la pantalla de inicio, cuando ya hay trabajo que seguir. **En iOS negar el
permiso es definitivo**: el sistema no vuelve a preguntar. Pedirlo en la
primera pantalla, antes de que se entienda para qué sirve, es la forma más
rápida de perderlo para siempre.

Para probar: `python3 tests/test_push.py` (11 comprobaciones; habla con Google
de verdad y no deja residuo).

## Lo único que falta, y es un arrastre

~~Subir la clave de APNs a los dos proyectos de Firebase.~~ **Hecho el
06/11/2026**, en las cuatro ranuras: desarrollo y producción de los dos
proyectos.

    Firebase → Configuración del proyecto → Cloud Messaging
      → Configuración de la app para Apple → Clave de autenticación de APNS
      → Subir

Pide tres cosas:

    el archivo   ~/Documents/venue-claves/AuthKey_93Y9DFJPLG.p8
    ID de clave  93Y9DFJPLG
    ID de equipo WYCP7K767H

Hay que hacerlo en los dos proyectos, AFTR y Venue. Es el mismo archivo y los
mismos dos números en los dos.

Por qué no quedó hecho: el campo de ese diálogo sólo acepta un arrastre de
verdad o el selector de archivos del sistema, y rechaza el archivo cuando se le
suelta por programa ("Tipo de archivo no compatible"). Es el único paso de todo
esto que necesita una mano.

---

# Wallet

## Apple Wallet · listo para firmar

| | |
|---|---|
| Pass Type ID | `pass.app.venue.aftr` |
| Team | `WYCP7K767H` |
| Certificado | emitido por Apple WWDR G4, vence **06/12/2027** |

El certificado se pidió sin pasar por Llavero: la solicitud se generó con
`openssl`, se subió al portal y se bajó el certificado. La llave privada nunca
salió de esta máquina.

Los tres pedazos están como secretos en Supabase —`WALLET_CERT`, `WALLET_WWDR`
y `WALLET_KEY`, más `WALLET_PASS_TYPE` y `WALLET_TEAM`— y una copia de trabajo
en `~/Documents/venue-claves/wallet/`. **No van al repo.**

Verificado: un `.pkpass` armado con este certificado pasa
`openssl smime -verify` **contra la raíz de Apple**, que es exactamente lo que
hace el iPhone antes de dejar instalar un pase.

**El certificado vence el 06/12/2027.** Cuando se acerque hay que pedir uno
nuevo con la misma llave (`pase.key`) y reemplazar `WALLET_CERT`.

## Google Wallet · listo para emitir

| | |
|---|---|
| Merchant | `BCR2DN6DZL5N3TSV` |
| Entidad emisora | `3388000000023222198` (`WALLET_GOOGLE_ISSUER`) |
| API | habilitada en el proyecto `aftr-6d08d` |
| Quién firma | la cuenta de servicio de FCM, con acceso de Desarrollador |

Se reusa la cuenta de servicio de `FCM_AFTR` en vez de crear otra: es la misma
identidad y una llave menos que cuidar.

Falta pedir **acceso de publicación** en la consola de Google Pay (son 2 o 3
días y pide completar el perfil de empresa). Hasta entonces los pases funcionan
en modo demo, que alcanza para probar.
