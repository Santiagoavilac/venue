# Paridad web → app móvil

Cada pantalla de la web y su estado en `venue_mobile/`. "Hecho" significa
escrito, con tests, y —donde dice "probado contra el demo"— ejecutado contra
el backend real con los usuarios de `tools/seed_demo.py`. Ninguna pantalla
fue probada todavía a mano en un teléfono.

| Etapa | Web (`app.js`) | App | Estado |
| --- | --- | --- | --- |
| 0 | Login | `authentication/ui/login_screen.dart` | hecho |
| 0 | Selector de boliche, tema por boliche | `clubs/` | hecho · probado contra el demo |
| 0 | Selector de evento | `events/ui/eventos_screen.dart` | hecho · probado contra el demo |
| 0 | Registro por invitación, avisos, pedir WhatsApp | — | pendiente |
| 0 | Sesión en el llavero, realtime, caché, cola offline | — | pendiente |
| 1 | Escáner (`validar`, `pintarRes`) | `access_control/ui/escaner_screen.dart` | hecho · probado contra el demo |
| 1 | Modo filtro y bandera en el escáner | ídem | hecho · probado contra el demo |
| 1 | Lista en puerta (`screenListaPuerta`) | `access_control/ui/lista_puerta_screen.dart` | hecho · probado contra el demo |
| 1 | RRPPs en puerta (`screenRrppsPuerta`) | `access_control/ui/rrpps_screen.dart` | hecho · probado contra el demo |
| 1 | Mesas en modo seguridad (`sheetMesaSeguridad`) | — | pendiente (va con Mesas) |
| 2 | Resumen, Listas, Entradas, ticket e Historial | — | pendiente |
| 3 | Mesas, plano y editor | — | pendiente |
| 4 | Pagos | — | pendiente |
| 5 | Reporte, stats, liquidación, contabilidad Excel | — | pendiente |
| 6 | Mi team, Gente, boliches | — | pendiente |
| 7 | Eventos (admin), listas, fases, avisos | — | pendiente |
| 8 | Caja | — | pendiente |
| 9 | Barra, inventario, POS, cierre, analítica | — | pendiente |

## Qué ve hoy cada rol en la app

| Rol | Secciones |
| --- | --- |
| Seguridad | Escáner · Lista · RRPPs · Eventos · Cuenta |
| Administrador | Escáner · Lista · Eventos · Cuenta |
| Jefe, Relacionador | Eventos · Cuenta |
| Caja, Propietario, Barra, Recepción | Cuenta |

Con esto, **el rol Seguridad ya tiene en la app todo lo que tiene en la web
salvo la vista de mesas**.
