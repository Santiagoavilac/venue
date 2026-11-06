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

## Lo único que falta, y es un arrastre

**Subir la clave de APNs a los dos proyectos de Firebase.** Sin eso el push
llega a Android pero no a iPhone.

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
