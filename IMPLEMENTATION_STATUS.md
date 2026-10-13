# Venue · estado de implementación

Última actualización: 2026-10-13

Plan completo: ver el plan aprobado (fases 1–8). Este archivo dice qué está
hecho **y ejecutado de verdad**, y qué no.

## Hecho

| Qué | Estado |
| --- | --- |
| Repositorio git inicializado, primer commit con la web intacta | hecho |
| `.gitignore` (credenciales, builds) · `config.js` y `.env.local` apuntando al proyecto demo `cxksjarupexptfksnptg` | hecho |
| Proyecto demo verificado vacío (0 tablas, 0 usuarios) | verificado por REST |
| Herramientas: Flutter 3.44.2, Dart 3.12.2, Xcode 26.5, Android SDK 36.1, CocoaPods 1.17 (`flutter doctor` sin problemas) | verificado |
| Servidor MCP `supabase-venue` agregado para el proyecto demo | agregado, **falta autorizarlo** |
| `db/18-helpers-permiso.sql` — rol efectivo por boliche, platform admins, `es_servicio()` | **escrito, sin ejecutar** |
| `db/19-rpc-guardas.sql` — matriz de permisos de 76 RPC + generador de guardas + `revoke` a anónimos | **escrito, sin ejecutar** |
| `db/20-triggers-servicio.sql` — triggers de cuenta protegida, perfil y membresía | **escrito, sin ejecutar** |

## App móvil (`venue_mobile/`) · Fase 3 empezada

Flutter 3.44 · Riverpod 3 · go_router · supabase_flutter · mobile_scanner.

| Qué | Estado |
| --- | --- |
| Estructura por features, tema oscuro con acento por boliche, estados de carga/vacío/error | hecho |
| Login usuario/clave, sesión persistida, cuenta desactivada | escrito; **sin probar contra el backend** (la base demo está vacía) |
| Selector de boliche (`mis_clubs`) y rol efectivo desde el servidor (`rol_en_club`) | escrito; depende de aplicar `db/18` |
| Eventos del boliche y evento de trabajo | escrito; sin probar contra el backend |
| Escáner de puerta: cámara nativa, linterna, háptica, código manual, aforo, últimos escaneos, 7 veredictos | escrito; sin probar en dispositivo |
| `flutter analyze` | sin problemas |
| `flutter test` | 23 tests pasan (parser de QR, veredictos, rutas, roles, tema, tarjeta) |
| `flutter build ios --release --no-codesign` | compila (Runner.app 18 MB) |
| Instalación en iPhone | instalada y lanzada en "Santiago Avila (2)" (iPhone 16 Pro); pantallas sin verificar a mano |

Pendiente conocido en lo ya escrito: la sesión se guarda sin cifrar
(preferencias de la app); pasarla al llavero con `flutter_secure_storage`.
Sin validación de QR offline: sin señal el escáner responde SIN CONEXIÓN y
no deja pasar.

Compilar: `cd venue_mobile && flutter run --dart-define-from-file=env/dev.json`

## Pruebas ejecutadas

Ninguna sobre las migraciones nuevas: todavía no hay forma de correr SQL
contra el proyecto demo (ver "Bloqueos"). `node --check` de `app.js` y
`contabilidad.js`: OK.

## Hallazgos nuevos durante la Fase 2

- Un **jefe podía ascenderse a admin**: la política de RLS le deja actualizar
  las filas de su team (incluida la suya) y `perfil_update_guard` dejaba
  pasar todo cuando la persona editaba su propia fila. Corregido en `20-…`.
- `club_membership`: quien editaba su propia fila pasaba sin control.
  Corregido en `20-…`.
- `bar_ventas` no guarda qué usuario hizo la venta: no se puede auditar ni
  limitar la anulación al bartender que la hizo. Pendiente para `25-auditoria`.
- En la web, RRPP y jefes pueden marcar el ingreso de sus propios invitados
  (`puede_tickear`), lo que infla sus "ingresaron" para comisión. Se conserva
  la regla (no se quitan funciones) pero queda señalado como riesgo de negocio.

## Cambios de comportamiento que traen las migraciones

- `profiles.clubs` vacío deja de significar "todos los boliches".
- Un admin común solo es admin en los boliches de `profiles.clubs`; solo un
  platform admin (`admin_principal` o tabla `platform_admins`) ve todos, crea
  boliches y nombra otros admins.
- El jefe ve solo los teléfonos de su team (`telefonos_equipo`).
- El RRPP solo paga/libera mesas que vendió y solo genera QR de sus invitados.

## Bloqueos (necesitan al propietario)

1. **Autorizar el MCP**: `/mcp` → `supabase-venue` → autenticar. Sin eso no
   se pueden aplicar `db/01…20` ni correr los tests de permisos.
2. **Firma de iOS**: resuelto. Se firma con el equipo de Sebastian Vaca Diez (`734M3ZA484`), bundle id `app.venue.venueMobile`; instalada y abierta en el iPhone "Santiago Avila (2)". Lo que sigue describía el intento anterior:
   ("login details were rejected"). Volver a iniciar sesión en
   Xcode → Settings → Accounts. El proyecto ya apunta al equipo `ANTK9WLN9M`
   con bundle id `app.venue.venueMobile`.
3. **Liberar disco**: quedan ~6,6 GB (eran 2 GB). Los builds de Flutter
   (Gradle, CocoaPods) necesitan al menos 15 GB.

## Pendiente (en orden)

- Fase 1: `docs/INVENTARIO.md`, `docs/ESQUEMA.md`, `docs/PARIDAD.md`,
  `docs/RPC_MATRIZ.md` (se genera desde `impl.rpc_permiso`), tests de
  caracterización.
- Fase 2: aplicar y probar 18–20; escribir 21 (RLS por boliche), 22
  (tokens de QR e invitación, límite de intentos), 23 (comprobantes
  privados), 24 (idempotencia y estados de pago), 25 (auditoría), 26
  (instalación limpia + README); `tests/seguridad/`; ajustes en `app.js`.
- Fases 3–8: sin empezar.

## Credenciales y configuración que faltan

Cuenta Apple Developer · Google Play Console · proyecto Firebase y clave APNs
· cuenta WhatsApp Business (Meta Cloud API) · proveedor de QR bancario (si se
quiere verificación automática de pagos) · logo por boliche.

La service role key del demo quedó pegada en el chat: conviene rotarla al
terminar las pruebas.

## Próximo paso técnico

Con el MCP autorizado: aplicar `db/01…17` en el demo, registrar qué falla en
instalación limpia, aplicar 18–20 y correr la matriz de permisos (anónimo +
8 roles × 2 boliches).
