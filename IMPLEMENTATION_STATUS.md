# Venue · estado de implementación

Última actualización: 2026-10-14 · Backend: proyecto Supabase
`cxksjarupexptfksnptg`. **Desde el 2026-10-14 es la base principal** (antes
era solo el demo): la web publicada y la app apuntan ahí.

> Ojo: `tools/seed_demo.py`, `tests/test_seguridad.py` y las pruebas de
> integración de la app **escriben en esta base** (reinician el evento demo,
> crean y borran filas de prueba). Con datos reales no se corren sin antes
> separar un proyecto de pruebas.

Solo figura como probado lo que se ejecutó de verdad.

## Resumen

| Bloque | Estado |
| --- | --- |
| Seguridad del servidor | aplicada y probada en el demo |
| Web | **al día con el servidor**, recorrida con los 9 roles en un navegador real, movimiento con GSAP |
| Paridad web → app (9 etapas) | **todas las pantallas de la web tienen su equivalente en la app** (`docs/PARIDAD.md`) |
| App en iPhone | compila firmada e instalada; **pantallas sin recorrer a mano una por una** |
| App en Android | compiló el APK de depuración con la base de la app; **falta recompilar con todo lo nuevo** |
| CRM, fidelización, notificaciones, WhatsApp Business | **sin empezar** |
| Publicación en tiendas | sin empezar |

## Cómo correr todo

```bash
sh tools/pruebas.sh        # seed + seguridad + análisis + tests de la app, en orden
```

Las pruebas de integración van de a un archivo: en paralelo, Supabase Auth
corta por exceso de logins y la corrida queda esperando.

## Seguridad (`db/18` … `db/28`)

| Migración | Qué hace |
| --- | --- |
| `18-helpers-permiso` | Rol efectivo **por boliche**, administradores de plataforma, distinción real entre servicio y anónimo |
| `19-rpc-guardas` | 79 RPC con guarda de sesión + rol + boliche (las originales intactas en el esquema `impl`); sin acceso anónimo; bloqueo de fila en ventas de mesa; límite de códigos inexistentes en puerta; **cupos de lista y ventana de venta ahora los hace cumplir el servidor** |
| `20-triggers-servicio` | Cuenta protegida, perfiles y membresías: nadie se cambia sus propios permisos |
| `21-rls-por-boliche` | Todas las tablas filtran por boliche; pagos y teléfonos restringidos; **eventos en borrador visibles solo para el admin**; vistas de stats respetan RLS |
| `22-codigos-e-invitaciones` | Códigos de entrada de 10 caracteres con generador criptográfico; invitaciones de 128 bits |
| `23-comprobantes-privados` | Bucket privado + URL firmada (web y app) |
| `24-pagos-idempotencia` | Un pago reenviado no se registra dos veces (`crear_pago_unico`) |
| `25-auditoria` | `audit_log` de pagos, entradas, invitados, mesas, perfiles, membresías, eventos, teams, boliches y ventas de barra |
| `26-instalacion-limpia` | Defaults, `search_path`, membresía sin team |
| `27-realtime` | Mesas, entradas e invitados en tiempo real |
| `28-storage-disenos-lectura` | Permite reemplazar artes, fondos de plano y QRs de cobro |
| `29-auditoria-solo-lectura` | Quita a las personas TRUNCATE/escritura sobre `audit_log` (grants por defecto de Supabase) |
| Edge Function `crear-usuario` | Límite de intentos, invitación con vencimiento, rol validado, crear admins solo plataforma |

Verificado en el catálogo: 0 funciones propias ejecutables por anónimos, 0
tablas sin RLS, esquema interno cerrado, sin el instalador temporal.

### Bugs del original encontrados por las pruebas (corregidos)

- Dos relacionadores podían vender la misma mesa a la vez.
- Un jefe podía ascenderse a admin editando su propio perfil.
- Cualquiera podía editar su propia membresía de boliche.
- `bar_ventas` no guardaba quién vendió.
- Los cupos de lista y la ventana de venta solo los controlaba la pantalla.
- Un evento en borrador lo podía leer todo el equipo por la API.
- Darle a alguien sin team un rol distinto por boliche fallaba.

### Cambios de comportamiento a tener presentes

- Un admin común administra solo los boliches de `profiles.clubs`. Solo la
  cuenta `admin_principal` (o `platform_admins`) ve todos, crea boliches y
  nombra admins.
- `profiles.clubs` vacío = sin acceso.
- El jefe ve solo los teléfonos de su team; el RRPP solo paga/libera mesas
  que vendió.
- Relacionadores y jefes ya no pueden pasarse de su cupo ni vender fuera de
  horario (el admin sí).
- Las invitaciones de team anteriores se regeneraron.

## Web (`index.html`, `app.js`, `motion.js`, `styles.css`)

Puesta al día con el servidor:

- El rol y los boliches de cada persona salen del servidor (`rol_en_club`,
  `mi_team_en_club`, RLS de `clubs`), no de reglas en el navegador.
- "Boliches" y la opción de rol Administrador solo aparecen a la
  plataforma (`es_platform_admin`); el alta sin team queda en el boliche
  actual.
- Los pagos se registran con `crear_pago_unico` y una clave por hoja: un
  doble toque no duplica (verificado: 1 fila).
- Errores legibles (sin permiso, sesión vencida, sin señal) en vez del
  texto crudo de Postgres.
- Campo de código de la puerta para códigos de 10 caracteres.
- **Auditoría** nueva en el ⋯ del Reporte: quién cambió qué y cuándo, con
  filtro por tipo. La lee solo el admin del boliche (RLS; un RRPP que la
  pide por la API recibe 0 filas).

Interfaz: GSAP 3.13 + ScrollTrigger (jsDelivr, versión fija) y todo el
movimiento en `motion.js`: entrada del login letra por letra, selector de
boliche escalonado, entrada de cada sección, filas que aparecen al bajar
(`ScrollTrigger.batch`, tope 150), topbar que se compacta con línea de
progreso, conteo en KPIs, barras del Reporte, plano de mesas desde el
centro y latido cuando una mesa cambia en vivo, veredicto del escáner,
hojas y avisos. En puerta, caja y barra el movimiento es mínimo. Con
"reducir movimiento" no se anima nada, y si GSAP no carga la web funciona
igual. Pulido visual al final de `styles.css` (incluye el hueco que quedaba
entre la barra lateral y el contenido en escritorio).

Verificado con Chrome real (`tools/web/recorrer.mjs`, `tools/web/flujos.mjs`):
9 roles × celular (390 px) y escritorio (1440 px), todas las secciones
cargan, cero errores de consola, ningún ScrollTrigger huérfano al cambiar
de sección; con movimiento reducido no queda ninguno. Flujos: clave
incorrecta, código inexistente en el escáner, pago con comprobante (doble
toque), Auditoría con filtro, RLS de la auditoría.

Publicada en Vercel (proyecto `venue-web`, contra la base principal):
https://venue-web-amber.vercel.app — se vuelve a publicar con
`sh tools/web/publicar.sh`. Recorrida ahí con los 9 roles: cero errores.

No verificado en la web: escanear con la cámara real, anotar invitados,
generar entradas y vender mesas desde la web (esas operaciones están
probadas contra el servidor en las pruebas de la app, no clic a clic en la
web).

## App móvil (`venue_mobile/`)

Flutter 3.44 · Riverpod 3 · go_router · supabase_flutter · mobile_scanner.

Por rol, lo mismo que en la web:

| Rol | Secciones |
| --- | --- |
| Administrador | Accesos · Escáner · Pagos · Mesas · Reporte · Gente · Eventos · Cuenta |
| Jefe | Accesos · Pagos · Mesas · Stats · Mi team · Eventos · Cuenta |
| Relacionador | Accesos · Pagos · Mesas · Stats · Eventos · Cuenta |
| Seguridad | Escáner · Puerta · RRPPs · Mesas · Eventos · Cuenta |
| Caja | Relacionadores · Eventos · Cuenta |
| Propietario | Inventario · Vender · Cierre · Analítica · Movimientos · Cuenta |
| Bartender | Vender · Cuenta |
| Recepción | Registrar · Lo mío · Cuenta |

Fundaciones: sesión en el llavero, cola sin señal con reintento automático e
idempotencia, tiempo real, registro por invitación, avisos y pedido de
WhatsApp.

### Lo que NO está verificado

- **Recorrido manual en el teléfono.** Lo probado es la capa de datos
  contra el servidor y piezas de interfaz en tests. El plano de mesas tuvo un
  defecto que solo se vio en el teléfono (ya corregido): puede haber otros de
  ese tipo.
- Subir imágenes desde el teléfono (comprobantes, fondo del plano, arte del
  ticket, QR de cobro): la subida se probó por API, no desde la cámara o la
  galería.
- El ticket con arte real del evento (el dibujo se prueba sin arte).
- El libro de contabilidad en Excel o Numbers reales (abre con openpyxl).
- Los links `venue://` de invitación.
- Android con todo lo nuevo.

## Pendiente

- CRM (perfiles de cliente, segmentación), fidelización, campañas.
- Notificaciones push (requiere proyecto Firebase y clave APNs).
- Envío automático de entradas por WhatsApp Business API (requiere cuenta de
  Meta, número y plantillas aprobadas).
- Estados de pago nuevos: parciales, anticipos y devoluciones.
- Recuperación de contraseña dentro de la app (hoy la restablece el jefe o el
  admin).
- `docs/INVENTARIO.md`, `docs/ESQUEMA.md`.
- Publicación: iconos, splash, políticas de privacidad, fichas de tienda.

## Necesita al propietario

- **Rotar la service role key del demo**: se hace desde el panel de Supabase
  (Settings → API). Quedó pegada en el chat. Verificado: no está en ningún
  commit; solo en `.env.local`, que git ignora.
- Activar "protección de contraseñas filtradas" en el panel de Auth.
- Liberar espacio en disco: la Mac se llenó durante el trabajo y hubo que
  borrar cachés para seguir (quedan ~5 GB).
- Cuentas Apple Developer / Google Play, Firebase, Meta (WhatsApp Business).

## Datos de demostración

`python3 tools/seed_demo.py` crea 2 boliches (Aurora Club, Nebula), 14
usuarios (contraseña `Venue2026!`), un evento por boliche con fecha de hoy,
lista de invitados, entradas, 4 mesas, un combo, y en Aurora una barra con
stock, un trago con receta y el bartender asignado al turno. Se puede volver
a correr cualquier día: trae el evento a la fecha actual.
