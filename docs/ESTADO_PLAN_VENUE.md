# Estado del plan de Venue

Avance de `PLAN_EXPERIENCIA_VENUE.md`. Se actualiza en el mismo commit que el
trabajo. Última actualización: 2026-11-05.

## Fase 0 · Cimientos

- [x] Librerías: `flutter_animate`, `skeletonizer`, `lucide_icons_flutter` en `pubspec.yaml`
- [x] `venue_mobile/lib/core/theme/tokens.dart` (tipografía y espaciado)
- [x] Una sola paleta efectiva: `Oscuro` en `venue_theme.dart` es el cromo que va
      sobre algo negro (ingreso sobre el video, velo del tutorial, foto del
      evento) y sale de la paleta oscura. La app arranca en oscuro, que es lo
      que arregla la pestaña gris clara bajo el encabezado oscuro.
      Prueba: `test/tema_test.dart`
- [x] `TarjetaCifra` único (`core/widgets/tarjeta_cifra.dart`) con su `GrillaCifras`.
      Reemplazó a `Indicador`, `FichaDato`, `Kpi`, `_Dato` de Accesos y `_Cifra`
      del relacionador: 45 llamadas migradas. Prueba: `test/tarjeta_cifra_test.dart`
- [x] `Insignia` único (`core/widgets/insignia.dart`), con `Insignia.texto` sin
      fondo para las listas densas de la puerta. Reemplazó a `PillEstado`,
      `_ChipPagado` y `_Estado` de Pagos, `_Estado` del relacionador,
      `_Etiqueta` de Eventos y los dos `_EstadoTexto`. El dorado de las
      cortesías pasó a `VenueColors.cortesia`. Prueba: `test/insignia_test.dart`
- [x] `EsqueletoLista`, `EsqueletoResumen` y `EsqueletoBloque` con `skeletonizer`
      (`core/widgets/esqueleto.dart`). `VistaAsync` ya no muestra una ruedita:
      por defecto pinta el esqueleto de la lista, y cada pantalla puede pasar el
      suyo con `cargando:`. Eso cubre sus 22 usos de una; además se cambiaron
      a mano los de Inicio, el relacionador, Listas, POS, Barra AFTR, reventa e
      historias. Quedan a propósito las ruleditas chicas de botones y recuadros.
      Prueba: `test/esqueleto_test.dart`
- [ ] Sacar `HeroEvento` de `gestion_screen.dart` a `core/widgets/`
- [~] Borrar lo muerto: ya salieron `Indicador`, `GrillaIndicadores`, `FichaDato`
      y `Kpi` con sus parámetros ignorados (`horizontal`, `color` de ficha).
      **`MarcaClub` no está muerto**: el de `patron.dart` lo usan `inicio_shell`
      (tres veces) y el de `selector_club_screen` es otro, con otra firma.
      Falta el `color` ignorado de `AccionRapida`

## Fase 1 · Privacidad en el servidor

- [x] `mesas`: columnas de dinero fuera de la tabla cruda, la app lee `mesas_detalle`
      (migraciones `…060000` y `…061000`)
- [x] `bonos` y `team_reparto` con el criterio de `db/47` y `db/49`
- [x] `pct_boliche` solo para admin y jefe (`eventoConComisionProvider`)
- [x] `miComision` sin el respaldo que bajaba `pct_boliche` y `cut_rel` al rrpp
- [x] `rrpp_eventos`: comisión de jefe por `rol_en_club`, no por `profiles.rol`
      global (migración `…080000`)
- [ ] Registrar en `impl.rpc_permiso` las cuatro que quedaron fuera de la matriz:
      `comisiones_mesas`, `opciones_operacion`, `reparto_jefe`, `ranking_teams`.
      Las cuatro ya llaman a `impl.exigir` adentro, así que es el invariante de
      `db/19:311-330` lo que falta, no una fuga
- [ ] Probar con `curl`, no con la app: token de rrpp contra `mesas`, `bonos` y
      `team_reparto`; repetir con un jefe; y un rrpp en dos boliches, jefe en uno

## Fase 2 · Evento activo

- [x] El fallback es el próximo por empezar, no `lista.first`
- [x] El evento elegido se persiste
- [x] La píldora siempre visible, también con un solo evento
- [x] Tocar un evento en una lista ya no cambia el evento global
- [x] Prueba `venue_mobile/test/evento_activo_test.dart`
- [ ] Línea fija arriba en Mesas, Pagos y Accesos con de qué evento son los datos

## Fase 3 · Pantalla por pantalla

- [~] **Mesas** — la fuga cerrada y la app leyendo `mesas_detalle`. Falta precios
      condicionados a `eventos.comision_mesas`, el plano y el tutorial
- [ ] **Eventos / Gestión** — una sola lista con eje temporal, "Crear evento"
      arriba, datos reales en Gestionar evento, arreglar el campo `_cut` que se
      manda sin dibujarse (`gestion_screen.dart:1511,1619`)
- [ ] **Pagos** — hoy no usa ninguna primitiva del sistema
- [ ] **Accesos** — unificar `_Dato` con `TarjetaCifra`
- [ ] **Reporte** — tokens y gráficos con `fl_chart`
- [ ] **Shell del relacionador** — `_Cifra`, `_Vacio` y `_Estado` a los compartidos

## Fase 4 · Tutoriales

- [ ] Guía por pantalla, con su clave en `SharedPreferences`
- [ ] Cubrir Mesas, Accesos, Pagos y Gestión de evento
- [ ] Tutorial en `RrppShell` (hoy los relacionadores no tienen ninguno)
- [ ] Que use los colores del tema (`tutorial.dart:119,172`)

## Fuera del plan, ya hecho

- Teclado que no se bajaba cuando el campo que lo abrió desaparecía: `VigilanteDelTeclado`
  en las dos apps
- AFTR: foto de perfil en las historias, y publicar reventa sin número de cuenta
  cuando hay QR de cobro
