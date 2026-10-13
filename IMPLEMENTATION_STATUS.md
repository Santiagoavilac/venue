# Venue · estado de implementación

Última actualización: 2026-10-13 · Backend de trabajo: proyecto demo
`cxksjarupexptfksnptg` (sin datos reales).

Solo figura como probado lo que se ejecutó de verdad.

## Fase 1 · Auditoría — parcial

| Qué | Estado |
| --- | --- |
| Revisión de código, esquema, RLS, triggers y Edge Function | hecha |
| Instalación limpia de `db/01…17` en un proyecto vacío | hecha; falló en 2 puntos, corregidos (ver abajo) |
| `docs/RPC_MATRIZ.md` (79 funciones: quién puede llamarlas) | generado desde la matriz que corre en el servidor |
| `docs/INVENTARIO.md`, `docs/ESQUEMA.md`, `docs/PARIDAD.md` | **pendientes** |

Fallos de instalación limpia encontrados y corregidos:
- `02f` usaba `unaccent()` sin activar la extensión → `db/00-extensiones.sql`.
- `02d` insertaba fases de un evento del proyecto de origen que no existe → ahora es condicional.
- El `insert into profiles` del README omitía columnas obligatorias → defaults en `db/26` y README corregido.

## Fase 2 · Seguridad — aplicada y probada en el demo

| Migración | Qué hace |
| --- | --- |
| `18-helpers-permiso` | Rol efectivo **por boliche**, administradores de plataforma, distinción real entre servicio y anónimo |
| `19-rpc-guardas` | 79 RPC con guarda de sesión + rol + boliche (las originales quedan intactas en el esquema interno `impl`); sin acceso anónimo; bloqueo de fila en ventas de mesa; límite de 40 códigos inexistentes cada 5 min en puerta |
| `20-triggers-servicio` | Cuenta protegida, perfiles y membresías: nadie se cambia sus propios permisos |
| `21-rls-por-boliche` | Todas las tablas filtran por boliche; pagos y teléfonos restringidos; vistas de stats respetan RLS |
| `22-codigos-e-invitaciones` | Códigos de entrada de 10 caracteres con generador criptográfico; invitaciones de 128 bits con vencimiento opcional |
| `23-comprobantes-privados` | Bucket privado + URL firmada (la web ya las usa) |
| `25-auditoria` | `audit_log` con quién/cuándo/antes/después en pagos, entradas, invitados, mesas, perfiles, membresías, eventos, teams, boliches y ventas de barra |
| `26-instalacion-limpia` | Defaults y `search_path` fijo |
| Edge Function `crear-usuario` | Desplegada: límite de intentos por IP, invitación con vencimiento, rol validado, crear admins solo plataforma |

### Pruebas ejecutadas

`python3 tests/test_seguridad.py` → **103 de 103 pasan** contra el demo, con
sesiones reales de 13 usuarios en 2 boliches. Cubren: anónimo sin acceso;
RRPP sin funciones administrativas; aislamiento entre boliches (RPC, tablas y
vistas); cuenta protegida; jefe no se asciende; teléfonos solo del team; 6
validaciones simultáneas del mismo QR → entra una; 3 ventas simultáneas de la
misma mesa → se vende una; auditoría; límite de intentos; comprobantes
privados; alta de usuarios.

Verificado en el catálogo: 0 funciones propias ejecutables por anónimos, 0
tablas sin RLS, 0 permisos de tabla para anónimos, esquema interno cerrado.
Asesor de seguridad de Supabase: sin errores.

Antes de aplicar se confirmó el agujero: con solo la anon key,
`eliminar_evento` se ejecutaba.

### Bugs del original encontrados por las pruebas

- **Doble venta de mesa**: dos RRPP podían vender la misma mesa a la vez. Corregido con bloqueo de fila.
- **Un jefe podía ascenderse a admin** editando su propio perfil. Corregido.
- **Cualquiera podía editar su propia membresía de boliche**. Corregido.
- `bar_ventas` no guardaba quién vendió. Ahora sí (`vendido_por`), y el bartender solo anula sus ventas.

### Cambios de comportamiento

- Un admin común administra solo los boliches de `profiles.clubs`. Solo la cuenta `admin_principal` (o `platform_admins`) ve todos, crea boliches y nombra admins.
- `profiles.clubs` vacío = sin acceso (antes = todos los boliches).
- Un usuario creado sin team nace sin boliche; se lo asigna el admin que lo creó.
- El jefe ve solo los teléfonos de su team. El RRPP solo paga/libera mesas que vendió y genera QR de sus invitados.
- Las invitaciones de team existentes se regeneraron (links viejos ya no sirven).

### Pendiente de seguridad

- **Estados de pago e idempotencia** (`24`): pagos parciales, anticipos, devoluciones, clave de idempotencia en `crear_pago`. Sin hacer. La barra ya tenía idempotencia (`client_key`).
- **La web no se volvió a recorrer a mano** tras las migraciones: `node --check` pasa y las RPC que usa responden, pero falta un recorrido por rol en el navegador.
- Decisión de negocio abierta: el RRPP sigue leyendo todos los invitados y entradas de su boliche (lo usan Listas y Reporte), y RRPP/jefes con `puede_tickear` pueden marcar el ingreso de sus invitados.
- Flujo de barra (recibir lote → vender → stock) sin test automatizado.
- Avisos menores del asesor: `unaccent` en `public`; protección de contraseñas filtradas desactivada (se activa en el panel de Auth).
- Rotar la service role key del demo (quedó pegada en el chat).

## Fase 3 · App móvil (`venue_mobile/`) — base hecha

Flutter 3.44 · Riverpod 3 · go_router · supabase_flutter · mobile_scanner.

| Qué | Estado |
| --- | --- |
| Tema oscuro con acento por boliche, estados de carga/vacío/error | hecho |
| Login, sesión persistida, selector de boliche, rol desde el servidor, eventos | hecho; las llamadas al backend se verificaron por API con 3 roles |
| Escáner de puerta (cámara, linterna, háptica, código manual, aforo, 7 veredictos) | hecho; **sin probar en el teléfono con un QR real** |
| `flutter analyze` / `flutter test` | sin problemas / 23 tests pasan |
| Build iOS firmado (equipo `734M3ZA484`, `app.venue.venueMobile`) | compila; instalado una vez en el iPhone, **antes** de que existiera el backend |
| Android | sin compilar todavía |

Pendiente en lo ya escrito: guardar la sesión en el llavero
(`flutter_secure_storage`); registro por invitación y recuperación de clave
dentro de la app.

Compilar: `cd venue_mobile && flutter run --dart-define-from-file=env/dev.json`

## Paridad web → app (en curso)

Plan por etapas y detalle pantalla por pantalla en `docs/PARIDAD.md`.

- **Etapa 1 · Puerta: hecha.** Escáner con modo filtro y bandera, lista en
  puerta (buscar, marcar y desmarcar ingreso, filtro) y consulta de RRPPs.
  Falta: mesas en modo seguridad (va con Mesas).
- **Etapa 2 · Listas y entradas: parcial.** El relacionador ya anota
  invitados, ve su cupo, genera entradas, las anula y comparte el QR. Falta
  lo de jefe/admin (ver todo, filtros, "a nombre de", tickear, QR masivo),
  fases a la vista, envío en tanda, el arte del evento en el ticket, Resumen
  e Historial.
- **Etapa 0 (fundaciones):** faltan sesión en el llavero, registro por
  invitación, avisos, pedido de WhatsApp, realtime y cola offline.
- **Etapas 3 a 9** (mesas y plano, pagos, reporte, equipo, eventos, caja,
  barra): sin empezar.

Pruebas: 34 tests unitarios/widget y 12 de integración contra el demo pasan
(`flutter test test/integracion --dart-define-from-file=env/dev.json`). Los
de integración recorren el circuito real: el RRPP genera una entrada o anota
un invitado desde la app y el portero la valida con el escáner de la app.
Nada de esto se probó todavía a mano en un teléfono.

## Fases 4–8 — sin empezar

Listas, entradas, RRPP/teams, eventos y admin, mesas y pagos, caja, barra/POS,
comisiones y reportes en la app · CRM · WhatsApp Business, push, campañas,
dashboard · offline y sincronización · publicación en tiendas.

## Datos de demostración

`python3 tools/seed_demo.py` crea 2 boliches (Aurora Club, Nebula), 14
usuarios (contraseña `Venue2026!`), un evento por boliche abierto todo el
día, lista de invitados, entradas, 4 mesas, un combo y una barra.

## Necesita al propietario

Cuenta Apple Developer / Google Play para publicar · proyecto Firebase y clave
APNs (push) · cuenta WhatsApp Business de Meta · proveedor de QR bancario si
se quiere verificación automática · logo por boliche · más espacio en disco
para compilar Android (quedan ~6 GB).

## Próximo paso técnico

Probar el escáner en el iPhone con una entrada real del demo y seguir con la
Fase 4 por la puerta (búsqueda por nombre y check-in de lista) y RRPP
(listas y entradas).
