# Blindar AFTR: plata, marketplace, API y velocidad

## Contexto

AFTR ya mueve plata de verdad: entradas con QR del banco, saldo PULSE, pedidos de
barra y una reventa entre personas. La exploración encontró que lo que falta no
son detalles sueltos sino **tres agujeros por donde hoy se pierde plata o se
filtran datos**, más mucha superficie abierta que nadie mira porque la app nunca
la usa.

Lo más grave, en orden:

1. **Se puede pagar y quedarse sin entrada.** El botón "Cancelar" de Accesos
   llama a `aftr_cancelar_mi_orden` (`db/35-aftr.sql:583`), que cancela la orden
   y libera el cupo **pero no toca el QR del banco**, que sigue cobrable. Si la
   persona paga después, el sistema cobra, no emite nada y deja una incidencia
   que hoy se resuelve a mano por SQL: no existe ninguna pantalla que las muestre.
   La función segura ya existe (`aftr_cancelar_cobro`) y no se usa ahí.
2. **Los datos bancarios de cualquier vendedor se consiguen gratis.** En la
   reventa alcanza con *iniciar* una orden —que no cuesta nada ni exige pagar—
   para ver titular, banco, cuenta y QR de cobro. Con tres órdenes simultáneas
   renovables se junta el mercado entero, y de paso se bloquean ofertas ajenas.
3. **Un `curl` sin sesión enumera los usuarios.** `aftr_historias` y
   `aftr_reventa_ofertas` están concedidas a `anon` y devuelven `autor_id`,
   `vendedor_id` y rutas de storage que contienen el uid.

Sumado: casi no hay límites de uso en AFTR, las órdenes vencen sólo cuando
alguien casualmente llama otra función (el propio código dice "no hay cron"), el
mapa dibuja círculos de medio kilómetro y no se deja arrastrar, la web nunca
muestra la foto de perfil en las historias, y cada historia vuelve a pedir su URL
firmada de a una.

**Decidido con vos:** 10 minutos para pagar y se cancela solo; si la plata llega
tarde **no se entrega la entrada** y se ofrece WhatsApp al **+591 75028040**; en
la reventa el boliche **sólo prende y apaga**; los datos de cobro se muestran
**recién cuando el vendedor acepta**; las listas son de Venue y sus cupos no se
tocan por la API, el QR de invitado se puede inhabilitar (admin, jefe, portero) y
el escáner lleva buscador adentro; las historias no se abren hasta estar
cargadas, con el anillo animado; el círculo del mapa escala con el zoom; y todo
lo sensible pasa por RPC con guarda.

**Regla de orden:** primero la plata, después los datos, después la experiencia.
Cada fase es un commit que deja el sistema andando. Primero el servidor (con
parámetros nuevos `default`), después los clientes: hay apps publicadas llamando
a las RPC viejas, así que **ninguna RPC se borra, se vuelve segura por dentro**.

---

## Fase 1 · Que no se pierda plata

**1.1 Poder generar un QR nuevo.** `pago_qr.orden_id` es `unique`
(`db/44-pagos-banco.sql:15`), así que cuando el QR muera a los 10 minutos la
orden queda sin forma de generar otro. Se reemplaza por un único parcial sobre
los estados vivos (`generando, activo, pagado, revisar`), igual para `recarga_id`
y `pedido_id`. `baneco_reservar_destino` (`20261031203752:382`) pasa a tomar el
último QR (`order by created_at desc limit 1 for update`) y a insertar uno nuevo
si el anterior está anulado. **Sin esto, lo demás de la fase traba al usuario.**

**1.2 Diez minutos.** En `baneco_reservar_destino`, `limite_at = least(vence,
now() + 10 min)`. La pieza que anula ya existe: `handler.ts:142-147` anula en el
banco cuando `limite_at <= now()` y el cron corre cada minuto
(`db/45-baneco-barrido.sql:16`). **No hay que tocar la Edge Function.**
`baneco_qr_anulado` suma la rama de orden: al anularse el cobro, la orden queda
cancelada y se libera el cupo; si es de mesa, `mesa_limpiar`. Volver a comprar
crea una orden nueva, que es más simple que resucitar la vieja.

**1.3 El pago tardío no emite.** `aftr_pago_confirmado` (`20261031172015:165`)
emite hoy si la orden está `pendiente` **o `vencida`**. Pasa a emitir sólo si está
`pendiente` y dentro de `limite_at + 90 s` de gracia por latencia bancaria. Si
no: `revisar`, nota `PAGADO_FUERA_DE_PLAZO` y fila en `aftr_incidencias` con
monto y `banco_tx`. `impl.aftr_emitir_orden` (`:88`) deja de aceptar `vencida`,
salvo un `p_forzar` nuevo que usa el staff al resolver una incidencia.

**1.4 Que el usuario se entere.** Hoy no ve nada: el QR se queda esperando. Una
RPC chica expone al dueño el estado de su pago cuando quedó en revisión, y en los
tres lugares aparece la tarjeta "Tu pago llegó tarde" con el monto y **un botón a
`https://wa.me/59175028040`** con el caso ya escrito:
`aftr_mobile/lib/features/accesos/accesos_screen.dart` (junto a los botones de
`:336-460`), `aftr_mobile/lib/features/evento/pago_qr.dart` y `aftr_web/aftr.js`
(`:840-870`). En móvil con `url_launcher`, que ya se usa para "Cómo llegar".

**1.5 Un solo camino para cancelar.** `aftr_cancelar_mi_orden` pasa a delegar en
la lógica de `aftr_cancelar_cobro` (`20261031203752:473`): si hay cobro en curso
no cancela nada y deja que el barrido lo anule en el banco. **Se arregla la RPC
antes que los fronts**, para que las apps ya publicadas queden protegidas. Los
botones pasan a decir "Pedir que se cancele" y avisan que si ya pagaste no se
cancela.

**1.6 Los crones que faltan.** `impl.aftr_vencer()` existe y **nadie la llama**
(`db/35-aftr.sql:198`: "no hay cron"). Se agenda cada minuto, con el mismo patrón
de `db/45-baneco-barrido.sql`. Y una `impl.aftr_mesas_vencer()` que libere las
mesas AFTR vencidas salteando las que tengan un QR vivo: hoy sólo se liberan si
alguien de Venue abre el evento, así que una mesa puede quedar muerta toda la
noche.

**1.7 Comprar dos veces no crea dos órdenes.** `aftr_comprar` y
`aftr_reservar_mesa` reciben `client_key` con advisory lock, como ya hacen
`aftr_recargar_pulse` y `aftr_reventa` (`20261101004007:467`). La clave se genera
una vez por hoja de compra, no por toque.

**1.8 Techo a la recarga.** `aftr_recargar_pulse` (`20261031203752:115`) valida
mínimo pero no máximo: tope por recarga y por día.

---

## Fase 2 · Cerrar los datos

**2.1 Cortar la lectura anónima sin perder el vivo.** En vez de revocar entero el
`grant select ... to anon` (`20261101004007:94`) —que dejaría a los visitantes
sin actualizaciones en vivo— se concede **por columnas**: las que no identifican
a nadie. Fuera `autor_id`, `vendedor_id` y `storage_path`. El feed sigue
llegando por su RPC, que ya filtra, y el Realtime sigue andando.

**2.2 Clave opaca y firma en lote.** `aftr_historias` suma `media_key` (y
`aftr_clientes` una `foto_key`); el feed manda esas claves en vez de rutas.
`historias-media` suma una acción que recibe **una lista** de claves, verifica que
sigan vivas y devuelve las URLs con `createSignedUrls` (plural, ya existe en el
SDK). Esto resuelve cuatro cosas de un saque: el uid deja de viajar en la ruta,
**el visitante sin sesión por fin ve la foto de perfil en la web** (hoy firmar
`aftr-perfiles` exige sesión), desaparece el N+1 de una firma por archivo, y
queda una sola función de firma para la app y la web.

**2.3 Buscar usuarios deja de raspar el directorio.** `aftr_buscar_usuario`
escapa `%` y `_`, exige tres caracteres y tiene límite por minuto. Hoy
`aftr_buscar_usuario('%%')` devuelve cuentas arbitrarias.

**2.4 Límites de uso, en una pieza sola.** Tabla `aftr_intentos` + helper
`impl.aftr_limite(accion, max, ventana)`, copiando el patrón que ya funciona en
la puerta (`db/19-rpc-guardas.sql:40-49`). Actor = la sesión, o la IP si no hay.
Se aplica a comprar, reservar, recargar, transferir, publicar, iniciar orden,
buscar, crear perfil, invitar a mesa y subir media. Mensajes claros, no errores
crudos. La limpieza va en el cron de 1.6.

**2.5 Topes donde hoy no hay.** `aftr_historias` no valida el tamaño de
`p_datos` (su hermana sí, `:408`) y su feed serializa 300 historias: se agrega el
guard y baja a 120 con paginación. `aftr_eventos` recorta el rango a 90 días y
pone `limit`; `aftr_calor` pasa a leer una caché que refresca el cron. Son las
tres RPC anónimas por las que se tira abajo la base con un `while true; do curl`.

---

## Fase 3 · El marketplace, blindado

**3.1 La plataforma fija las reglas, el boliche prende y apaga.** Tabla única de
política (tope de precio, minutos de pago, de confirmación y de cierre), sólo
escribible por la plataforma. De `aftr_reventa_config` al club le quedan
`habilitada` y `condiciones`; lo demás se ignora y se lee de la política. El
panel del boliche queda con un interruptor y el texto de condiciones, mostrando
los plazos como información fija.

**3.2 El vendedor acepta primero.** Estado nuevo `esperando_vendedor`: iniciar
una orden le avisa al vendedor y **no muestra ningún dato de cobro**; recién
cuando él acepta, la orden pasa a `pendiente_pago`, arranca el plazo y aparecen
titular, banco y QR. `impl.reventa_orden_json` (`:388`) deja de exponer `metodo`
antes de la aceptación. Además: **una** orden abierta por comprador (hoy tres),
tope diario contando también las canceladas y vencidas (el abuso es renovar),
espera de horas antes de reintentar sobre la misma oferta, y cada revelación de
datos queda anotada en el historial para que el vendedor la vea.

**3.3 La oferta reservada no desaparece del mercado.** Sigue bloqueándose
mientras se paga (soltarla invitaría a dos pagos reales por la misma entrada,
que es peor), pero el mercado la muestra como "en pago, vuelve en N minutos" en
vez de ocultarla, y con 3.2 la ventana de daño baja de infinita a diez minutos,
pocas veces por día.

**3.4 El techo de precio, contra lo que se pagó.** Hoy se mide siempre contra el
precio original, así que una cadena de reventas conserva el mismo techo. Se
hereda un `precio_base` al re-emitir y el cálculo queda en una sola función, sin
depender de que centavos y bolivianos coincidan por casualidad.

**3.5 Cerrar la puerta del dispatcher.** `aftr_reventa` está concedida a `anon` y
lo único que separa lo público de lo privado es el orden de los `if`
(`:409-416`): un `p_accion` nuevo puesto arriba abre todo. Se parte en dos
funciones —mercado público y el resto autenticado— y la privada arranca
rechazando sin sesión. Mismo tratamiento para `aftr_historias`.

**3.6 Lo que no se toca.** El bloqueo de la entrada publicada, el índice de
credencial viva, la vista `impl.entradas_vigentes`, la validación en puerta que
devuelve `bloqueada`/`reemplazada` y la re-emisión atómica funcionan y están bien
pensados: se conservan tal cual, con pruebas nuevas para que nadie los rompa.

---

## Fase 4 · El borde: funciones, archivos y la web

**4.1 Secretos separados.** `historias-media` usa el token del banco y lo compara
con `===`; pasa a tener el suyo y a usar la comparación en tiempo constante que ya
está escrita en `db/functions/baneco/handler.ts:25`. Más límite por IP: hoy cada
llamada descarga hasta 30 MB sin freno.

**4.2 Validar los bytes, no el nombre.** `aftr-p2p` (comprobantes de pago) y
`aftr-perfiles` aceptan cualquier contenido con que el cliente declare
`image/jpeg`. Pasan por el mismo validador de magic bytes que ya existe
(`db/functions/historias-media/media.ts`), con borrado del objeto si falla.

**4.3 CORS y cabeceras.** Las dos Edge Functions tienen `CORS *`: se acotan a los
dominios propios. Y la web no tiene **ninguna** cabecera de seguridad mientras
carga JS de tres CDNs en la misma página donde vive la sesión
(`aftr_web/index.html:61-69`): CSP, `nosniff`, `Referrer-Policy`,
`frame-ancestors`, y los tres scripts bajados a `vendor/` con versión fija (o al
menos SRI). Antes de la CSP hay que barrer los `style=` inline de los templates.

**4.4 Nonce por intento en Google.** `ingreso.dart:28` usa uno estático por
proceso; el de Apple ya es por intento.

---

## Fase 5 · Las incidencias, con pantalla

Todo lo de la Fase 1 genera incidencias en vez de cobros silenciosos; sin
pantalla eso sólo mueve el problema de lugar. Dos RPC nuevas —listar y resolver—
entrando por la matriz de guardas (`impl.rpc_permiso`), admin del club, **portero
afuera** (coherente con lo que ya hicimos en `ve_plata`). Panel en Venue con
contador en el menú: quién, cuánto, cuándo, qué dijo el banco, y tres acciones
—emitir, devolver, cerrar— más el botón de WhatsApp para contestarle al cliente.

---

## Fase 6 · Listas y puerta (Venue)

**6.1 Los cupos, sólo de quien corresponde.** Repaso de `jefe_fijar_cupos`
(`db/48-jefe-cupos.sql:60`) y de todo lo que toca cupos: admin del club y jefe de
su team, nadie más, ni por API ni por tabla. Si el boliche no usa jefes, el admin
fija cuántos invitados anota cada relacionador. Se prueba con `curl` usando
`prueba.rrpp` intentando subirse el cupo.

**6.2 Inhabilitar el QR de un invitado.** La columna `registros.qr_anulado`
existe desde `db/13-registros-qr-anulado.sql` pero **nadie la escribe y la
validación no la mira**: hoy no hay forma de frenar a alguien que usa el QR de
otro. RPC para anular y reactivar con registro de quién y cuándo, la validación
de puerta la respeta y muestra "QR anulado". Pueden hacerlo admin, jefe y portero.

**6.3 Buscador dentro del escáner.** El buscador por nombre ya existe, pero en
otra pestaña (`lista_puerta_screen.dart`), y el guardia que escanea no lo tiene a
mano. Se suma al escáner reutilizando ese repositorio y sus piezas: buscar,
marcar ingreso, ver quién lo trajo, marcar que no pasó el filtro y anular el QR
ahí mismo.

---

## Fase 7 · Historias como Instagram

**7.1 No se entra hasta que esté lista.** El círculo pasa a animar su anillo
(gradiente girando) mientras firma y descarga; recién cuando la primera historia
está decodificada se abre el visor, que ya recibe la imagen o el video listo. Si
falla, el anillo se detiene y se avisa: nunca se abre un visor vacío. Igual en la
web, donde además **desaparece el "Cargando historia…"**
(`aftr_web/social-core.js:146`).

**7.2 Las firmas dejan de vencerse antes de usarse.** Hoy se cachean URLs de 60
segundos sin vencimiento (`historias.dart:132,180`), así que pasado el minuto la
imagen se rompe; y en la web una firma fallida se cachea **para siempre**, ni
después de loguearte reintenta (`social-core.js:100`). Caché con vencimiento
real, re-firma al 80 % del plazo, y sólo se guardan los éxitos. Con el lote de
2.2, las URLs pasan a durar diez minutos.

**7.3 Se precargan las dos siguientes**, videos incluidos (hoy sólo imágenes).

**7.4 El visor deja de repintarse 20 veces por segundo.** El
`Timer.periodic(50 ms)` con `setState` (`historias.dart:145-155`) reconstruye
todo el visor; pasa a un `AnimationController` que sólo repinta la barra.

---

## Fase 8 · Mapa

**8.1 El círculo escala con el zoom.** Hoy el radio es `160 + 380 × intensidad`
metros (`mapa_screen.dart:456`), así que el que más vendió dibuja siempre 540 m:
una mancha enorme a zoom de ciudad e invisible a zoom de calle. Pasa a calcularse
desde el zoom para ocupar siempre lo mismo en pantalla, con la intensidad
quedando en el color y la opacidad, que es lo que debía comunicar. De tres
círculos por lugar a dos. El recálculo va en `onCameraIdle`, no por frame.

**8.2 Que el mapa se deje arrastrar.** Son cuatro competidores por el mismo
gesto: al `AppleMap` no se le pasan `gestureRecognizers` (el plugin los soporta),
el `GestureDetector` global de toda la app (`app.dart:35`) compite por cada
toque, la hoja arrastrable ocupa el 34 % de abajo siempre, y adentro hay un
carrusel horizontal. Se le pasan los recognizers al mapa, el detector global pasa
a no entrar en la disputa, y la hoja baja a ~18 % para que quede mapa libre de
verdad.

**8.3 Un build por frame de arrastre.** `mapa_screen.dart:56` hace `setState` en
cada tick del arrastre, re-filtrando eventos, regenerando pines y recalculando el
encuadre. Pasa a un `ValueNotifier` que sólo repinta lo que depende de la altura.

**8.4 Android queda anotado.** El mapa es sólo iOS (`:115`); el fallback de lista
está bien. Se deja escrito que la alternativa es cambiar el plugin detrás de la
misma interfaz, que ya es agnóstica.

---

## Fase 9 · Que vuele

Pedir sólo lo que se muestra (`eventosProvider` trae hoy todos los eventos sin
rango), sacar `elegido` de la clave de caché de los pines para que cambiar de
selección no regenere bitmaps, dejar el `BackdropFilter` sólo donde está sobre el
mapa, `cacheKey` en `ImagenRed` (`piezas.dart:64`) copiando el truco que ya está
en `avatar.dart:21`, y paginar las listas largas apoyándose en los topes del
servidor de 2.5.

---

## Verificación

- **Pagos**: con las cuentas de `burtown`, generar un QR, cancelar desde Accesos y
  ver que el cobro queda en anulación en vez de liberarse; dejar vencer y
  comprobar que a los diez minutos el QR está anulado y el cupo libre; forzar un
  pago fuera de plazo y verificar que **no** emite, que queda la incidencia y que
  la app ofrece el WhatsApp. Prueba de no regresión: dentro de los diez minutos,
  emite.
- **Reventa**: con dos cuentas, iniciar una orden y comprobar por `curl` que
  `metodo` viene vacío hasta que el vendedor acepta; intentar varias órdenes el
  mismo día; publicar por encima del tope en una cadena de reventas.
- **Datos**: `curl` sin sesión contra `aftr_historias` y `aftr_reventa_ofertas` →
  sin `autor_id` ni rutas; `aftr_buscar_usuario('%%')` → vacío; superar cada
  límite y ver el mensaje claro; `tests/rpc_con_guarda.py` sin ninguna RPC sin
  control.
- **Listas y puerta**: `prueba.rrpp` intentando cambiar su cupo → rechazado;
  anular un QR de invitado y que la puerta lo rechace; buscar, marcar y anular
  desde el escáner.
- **Historias y mapa**: con la red frenada a 3G, tocar un círculo y ver el anillo
  girando sin "Cargando historia"; prueba unitaria de que el radio del círculo
  por el zoom da constante entre zoom 11 y 17; prueba de widget de que el mapa
  recibe sus recognizers y de que arrastrar la hoja no dispara más de un build.
- **Siempre**: `flutter analyze` sin errores ni advertencias en las dos apps, las
  140 pruebas de Venue y las 19 de AFTR en verde, `node --check` de la web,
  `deno test` de las Edge Functions, y pruebas nuevas por cada arreglo que se
  pueda probar sin red.
- Las migraciones se aplican una por una con `supabase db query --linked -f`,
  verificando el efecto, y se registran con `supabase migration repair --status
  applied`, como las anteriores.

**Las fases 1 a 6 se pueden desplegar sin tocar las apps publicadas**: las RPC
viejas quedan seguras por dentro y los parámetros nuevos llevan `default`.
