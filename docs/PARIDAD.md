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
| 0 | Registro por invitación (`?invite=`) | `authentication/ui/registro_screen.dart` | hecho · rechazo probado contra el demo |
| 0 | Avisos al entrar y pedido de WhatsApp (`mostrarAvisos`, `pedirTelefono`) | `avisos/bienvenida.dart` | hecho · RPC probadas contra el demo |
| 0 | Sesión en el llavero | `core/security/llavero.dart` | hecho (se prueba en dispositivo) |
| 0 | Cola sin señal (`colaPuerta`, `ingresoResiliente`) | `core/sync/cola_offline.dart` | hecho · 8 tests |
| 0 | Tiempo real (`subRealtime`) | `core/sync/tiempo_real.dart` | hecho · probado contra el demo |
| 0 | Caché de pantallas (`conDatos`) | providers de Riverpod | hecho (cada lectura queda en memoria y se invalida al escribir) |
| 1 | Escáner (`validar`, `pintarRes`) | `access_control/ui/escaner_screen.dart` | hecho · probado contra el demo |
| 1 | Modo filtro y bandera en el escáner | ídem | hecho · probado contra el demo |
| 1 | Lista en puerta (`screenListaPuerta`) | `access_control/ui/lista_puerta_screen.dart` | hecho · probado contra el demo |
| 1 | RRPPs en puerta (`screenRrppsPuerta`) | `access_control/ui/rrpps_screen.dart` | hecho · probado contra el demo |
| 1 | Mesas en modo seguridad (`sheetMesaSeguridad`) | `vip_tables/ui/mesa_hojas.dart` | hecho |
| 2 | Accesos con pestañas (`screenAccesos`) | `access_control/ui/accesos_screen.dart` | hecho |
| 2 | Resumen (`accResumen`) | ídem · `ResumenView` | hecho |
| 2 | Listas completas (`screenListas`): todos los anotados, buscador global, filtros por team y relacionador, "a nombre de", cupos, tickear con cola sin señal, quitar, QR, envío en tanda | `guestlists/ui/listas_screen.dart` | hecho · probado contra el demo |
| 2 | Entradas (`screenEntradas`): generar, fases de preventa, ventana de venta, mías / mi team / todas, buscador, anular, eliminar, envío en tanda, entradas de la casa | `tickets/ui/entradas_screen.dart` | hecho · probado contra el demo |
| 2 | Ticket con el arte del evento o de la fase, sello de fase y marco dorado (`ticketImage`) | `tickets/data/ticket_imagen.dart` | hecho · el dibujo se prueba sin arte; con arte real falta verlo en dispositivo |
| 2 | Historial (`accHistorial`) | `access_control/ui/accesos_screen.dart` · `HistorialView` | hecho |
| 2 | Editar una lista desde Listas (menú ⋮ del admin) | — | pendiente (va con Eventos) |
| 3 | Plano por planta con fondo, estados, team asignado, zoom y tiempo real (`screenMesas`) | `vip_tables/ui/mesas_screen.dart`, `plano.dart` | hecho · datos probados contra el demo |
| 3 | Vender / reservar: combo por tipo de mesa, cantidad, unir mesas, botellas, manillas con QR, a nombre de, cortesía, efectivo o transferencia con comprobante y QR de cobro (`sheetMesa`) | `vip_tables/ui/mesa_hojas.dart` | hecho · probado contra el demo |
| 3 | Mesa vendida: detalle, manillas, editar, marcar pagada, verificar/rechazar, ocupada, liberar | ídem | hecho · probado contra el demo |
| 3 | Reservas con vencimiento y barrido automático (`barrerReservasVencidas`) | `vip_tables/data/mesas.dart` | hecho |
| 3 | Editor de plano: crear mesa/lounge, mover arrastrando, redimensionar, cambiar de piso, asignar team, eliminar, fondo, copiar de otro evento (`sheetMesaEdit`, `dragMesa`, `nuevaMesa`, `sheetCopiar`) | `mesas_screen.dart`, `mesa_hojas.dart` | hecho · probado contra el demo (subir fondo: sin probar) |
| 3 | Combos (`sheetCombos`) | `mesa_hojas.dart` | hecho · probado contra el demo |
| 3 | Confirmar pagos de mesas (`sheetContabilidad`) | ídem | hecho · probado contra el demo |
| 3 | Registro de combos en texto y guardar el plano como imagen (`copyRegistroMesas`, `guardarPlano`) | `mesas_screen.dart` | hecho |
| 4 | Pagos | — | pendiente |
| 5 | Reporte, stats, liquidación, contabilidad Excel | — | pendiente |
| 6 | Mi team, Gente, boliches | — | pendiente |
| 7 | Eventos (admin), listas, fases, avisos | — | pendiente |
| 8 | Caja | — | pendiente |
| 9 | Barra, inventario, POS, cierre, analítica | — | pendiente |

## Qué ve hoy cada rol en la app

| Rol | Secciones |
| --- | --- |
| Seguridad | Escáner · Puerta · RRPPs · Mesas · Eventos · Cuenta |
| Administrador | Accesos (Listas, Entradas, Resumen, Historial) · Escáner · Mesas · Eventos · Cuenta |
| Jefe, Relacionador | Accesos (Listas, Entradas, Resumen) · Mesas · Eventos · Cuenta |
| Caja, Propietario, Barra, Recepción | Cuenta |

Con esto, **el rol Seguridad ya tiene en la app todo lo que tiene en la web
salvo la vista de mesas**.
