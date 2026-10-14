# Venue · estado de implementación

Última actualización: 2026-10-14 · Backend de trabajo: proyecto demo
`cxksjarupexptfksnptg` (sin datos reales).

Solo figura como probado lo que se ejecutó de verdad.

## Resumen

| Bloque | Estado |
| --- | --- |
| Seguridad del servidor | aplicada y probada en el demo |
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
- La **web** no se volvió a recorrer en el navegador tras las migraciones.

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
