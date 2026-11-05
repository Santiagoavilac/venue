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
- [x] `HeroEvento` sale de `gestion_screen.dart` (3410 → 3142 líneas) a
      `features/events/ui/hero_evento.dart`, junto con `NumerosEvento`.
      **No fue a `core/widgets/`**: lee `numerosEventoProvider`, y core no puede
      depender de los providers de una feature
- [x] Borrar lo muerto: ya salieron `Indicador`, `GrillaIndicadores`, `FichaDato`
      y `Kpi` con sus parámetros ignorados (`horizontal`, `color` de ficha).
      **`MarcaClub` no está muerto**: el de `patron.dart` lo usan `inicio_shell`
      (tres veces) y el de `selector_club_screen` es otro, con otra firma.
      El `color` ignorado de `AccionRapida` también salió, con sus 17 argumentos

## Fase 1 · Privacidad en el servidor

- [x] `mesas`: columnas de dinero fuera de la tabla cruda, la app lee `mesas_detalle`
      (migraciones `…060000` y `…061000`)
- [x] `bonos` y `team_reparto` con el criterio de `db/47` y `db/49`
- [x] `pct_boliche` solo para admin y jefe (`eventoConComisionProvider`)
- [x] `miComision` sin el respaldo que bajaba `pct_boliche` y `cut_rel` al rrpp
- [x] `rrpp_eventos`: comisión de jefe por `rol_en_club`, no por `profiles.rol`
      global (migración `…080000`)
- [x] Cobertura de guardas, resuelta de otra forma que la del plan. **No son
      cuatro las que quedaron fuera de la matriz: son 119.** Todo lo que se
      escribió después de `db/19` (AFTR, PULSE, relacionadores, credenciales)
      comprueba adentro con `impl.exigir` o `rol_en_club` en vez de pasar por
      `impl.rpc_permiso`. Son dos estilos válidos y el chequeo de `db/19`
      conocía uno solo. Meter las cuatro en la matriz no arreglaba nada: el
      chequeo seguiría fallando por las otras 115, y envolver las 119 sería
      reescribir toda la API a ciegas.
      En su lugar, `tests/rpc_con_guarda.py` comprueba lo que importa: que cada
      función `security definer` de `public` esté en la matriz, compruebe
      adentro, o sea una excepción con el motivo escrito. Hoy da 79 / 104 / 10
      y ninguna sin control. Las cuatro del plan comprueban adentro: revisadas
      una por una
- [ ] Probar con `curl`, no con la app: token de rrpp contra `mesas`, `bonos` y
      `team_reparto`; repetir con un jefe; y un rrpp en dos boliches, jefe en uno

## Fase 2 · Evento activo

- [x] El fallback es el próximo por empezar, no `lista.first`
- [x] El evento elegido se persiste
- [x] La píldora siempre visible, también con un solo evento
- [x] Tocar un evento en una lista ya no cambia el evento global
- [x] Prueba `venue_mobile/test/evento_activo_test.dart`
- [x] `DeQueEvento` arriba de Mesas, Pagos y Accesos: de qué evento son los
      datos y el toque para cambiarlo. El selector salió de `inicio_shell` a
      `features/events/ui/cambiar_evento.dart` para que lo usen las dos.
      Prueba: `test/de_que_evento_test.dart`

## Fase 3 · Pantalla por pantalla

- [~] **Mesas** — la fuga cerrada, la app leyendo `mesas_detalle` y el total en
      plata condicionado a `eventos.comision_mesas` (`veDineroDeMesas`, con
      prueba en `test/mesas_dinero_test.dart`) y el plano: lo que se toca mide
      44 como mínimo aunque la mesa se dibuje más chica, y cada estado lleva su
      ícono además del color, en las mesas y en la leyenda
      (`test/plano_test.dart`). Falta el tutorial, que sale con la Fase 4
- [~] **Eventos / Gestión** — hecho: el campo `_cut` que se mandaba sin estar
      dibujado (con un evento gratis, "Crear evento" fallaba sin salida),
      "Crear evento" siempre arriba, y la lista agrupada por tramo
      (`agruparPorTramo`: hoy, próximos del más cercano, pasados del más
      reciente), y los números de a pares desde `resumen_evento` en una sola
      consulta en vez de cuatro conteos sueltos. "Gestionar evento" abre con
      la plata de la noche (`liquidacion_evento`, sólo admin), que antes había
      que ir a buscar al Reporte
- [x] **Pagos** — pasa a las piezas compartidas: `_Caja` (la sexta "tarjeta con
      un número", que se me había escapado) es `TarjetaCifra`, los títulos son
      `TituloBloque`, las tarjetas son `Tarjeta` y los tamaños salen de `Tipo`.
      Ya tenía `DeQueEvento` y las insignias de estado
- [x] **Accesos** — `_Dato` ya es `TarjetaCifra`; además se fue `ResumenView`
      entera, que no la usaba nadie desde que los números viven en el inicio, y
      el refresco en vivo pasó a invalidar `numerosEventoProvider`, que es lo
      que de verdad se está mirando
- [x] **Reporte** — ya tenía su gráfico con `fl_chart` (la dona de composición).
      21 de los 32 tamaños de letra sueltos pasan a los roles de `Tipo`, con un
      redondeo de medio punto a un punto. Los 11 que quedan son a propósito:
      los que cambian según el ancho (`angosto ? 14.5 : 17`) y la cifra grande
      del cierre, que es su propio rol
- [ ] **Shell del relacionador** — `_Cifra`, `_Vacio` y `_Estado` a los compartidos

## Fase 4 · Tutoriales

- [x] `GuiaDePantalla`: se envuelve una pantalla y su guía sale la primera vez
      que se entra, con su propia clave (`venue.tutorial.v1.<guia>.<uid>`). La
      del inicio conserva la clave vieja para no repetírsela a quien ya la vio.
      Dos arreglos que hacían falta para esto: un paso sin objetivo dejaba la
      pantalla negra (se dibujaba el velo y no la tarjeta) y además se quedaba
      con el agujero del paso anterior
- [~] Mesas ya tiene la suya (el plano, qué significa cada ícono, acomodar el
      plano si es admin, y mirar de qué evento son las mesas). Faltan Accesos,
      Pagos y Gestión de evento
- [ ] Tutorial en `RrppShell` (hoy los relacionadores no tienen ninguno)
- [x] Los colores salen de `Oscuro`, no de hexadecimales sueltos (quedó hecho
      al unificar la paleta)

## Fuera del plan, ya hecho

- Teclado que no se bajaba cuando el campo que lo abrió desaparecía: `VigilanteDelTeclado`
  en las dos apps
- AFTR: foto de perfil en las historias, y publicar reventa sin número de cuenta
  cuando hay QR de cobro
