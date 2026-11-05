# Plan: rehacer la experiencia de VENUE

## Context

La app de gestión funciona pero cuesta usarla. Lo pedido, en orden de daño:

1. **Privacidad entre relacionadores.** Un rrpp no debería ver los ingresos del boliche, ni lo que gana otro, ni plata de mesas si él no cobra comisión por mesas. Un jefe sí ve lo de su team. Si el boliche no usa jefes, todo sigue simple.
2. **Administración de eventos confusa**: se ve un evento suelto, "Gestionar evento" muestra poca información, los próximos no se ven ni se crean fácil.
3. **La interfaz es fea y difícil**, con tarjetas que ya se habían pedido sacar y bugs visibles.
4. **Faltan tutoriales** en Mesas y para los roles admin, jefe y rrpp.

Decidido: **pantalla por pantalla dejando cada una terminada** (visual + bugs + permisos juntos), **agregando las librerías sugeridas**, y **manteniendo el evento activo** pero haciendo claro el cambio.

Criterios de `deep-research-report (2).md`: sus P0 (contraste 4.5:1, targets 44–48, labels permanentes, feedback inmediato, estados de carga/vacío/error, nada que dependa solo del color) se tratan como bloqueantes.

---

## Hallazgo 1 — Fuga real de datos en Mesas, no es cosa de la interfaz

`db/21-rls-por-boliche.sql:73` deja que **cualquier rrpp del boliche lea todas las mesas de todos los eventos**: precio, quién vendió, cliente, método de pago.

Y la app se lo muestra sin filtro:

- `mesas_screen.dart:202,236` suma y escribe **la recaudación bruta de mesas del boliche** esa noche.
- `mesas_screen.dart:958` pinta el precio en cada mesa del plano.
- `mesa_hojas.dart:784` dice **quién vendió** cada mesa y de qué team.

Esconderlo en Flutter **no alcanza**: con su propia sesión, cualquiera lo saca con un `curl` al endpoint REST.

Lo mismo, aunque hoy la interfaz sí los oculte, pasa con `bonos` (`db/21:78`), `team_reparto` (`db/52:85`), `profiles.cut_rel` (`db/21:152`) y `eventos.pct_boliche` (`db/21:65`).

**Lo bueno:** el patrón de arreglo ya existe y está probado en este repo. `db/47-listas-solo-lo-suyo.sql` y `db/49-teams-separados.sql` hicieron exactamente esto para `registros` y `entradas` con `impl.ve_registro`, que ya resuelve los tres casos (admin y portero todo, jefe su team, rrpp lo suyo). Falta aplicarlo a `mesas` y `bonos`.

**Y la comisión de mesas ya es configurable**: `eventos.comision_mesas` existe y su default es `false` (`db/52:25`). O sea que la condición para decidir si un rrpp ve precios de mesa **ya está en la base**; hoy simplemente no se usa para eso.

## Hallazgo 2 — El "evento activo" elige mal

`eventoActivoProvider` (`lib/features/events/data/eventos.dart:144-156`) cae a **`lista.first`** sobre una lista ascendente sin piso de fecha. Como nada cierra los eventos solos, eso devuelve **el más viejo sin cerrar**. Las pantallas muestran datos de otro evento sin avisar.

Además: la píldora que cambia de evento **se apaga si hay menos de dos** (`inicio_shell.dart:874`), tocar un evento en Gestión **reconfigura el escáner de la puerta**, y la selección se pierde al reiniciar.

## Hallazgo 3 — Dos paletas conviviendo

La app **arranca en claro** (`core/theme/apariencia.dart`), pero mucho cromo tiene los colores oscuros escritos a mano. Por eso la pestaña Catálogo aparece como un bloque gris claro bajo un encabezado oscuro: no está rota, está usando el tema mientras el resto no.

Debajo: **385 `fontSize` literales con 28 valores**, 493 `EdgeInsets` sueltos, 17 radios, **cinco** implementaciones de "tarjeta con un número", **siete** de "badge de estado", 19 `Card` crudos. Y `VenueColors` es estado global mutable fuera de `BuildContext`, lo que obliga a remontar la app entera al cambiar de tema (`app.dart:20`).

---

## Fase 0 · Cimientos (una vez, antes de las pantallas)

Sin esto, cada pantalla rediseñada vuelve a inventar valores.

- **Tokens** nuevos en `lib/core/theme/`: escala tipográfica con roles (`display/titulo/subtitulo/cuerpo/etiqueta`) y escala de espaciado 4/8. Reemplazan los literales a medida que se toca cada pantalla, no de golpe.
- **Una sola paleta efectiva.** Elegir modo por defecto y hacer que el cromo hoy hardcodeado (`acceso_oscuro.dart`, colores del tutorial, degradés de `HeroEvento`) lea del tema. Arregla la pantalla gris.
- **Librerías**: `flutter_animate ^4.5.2`, `skeletonizer ^3.0.0`, `lucide_icons_flutter ^4.0.2`. `fl_chart` ya está. Todas compatibles con Dart 3.12. Sumar su declaración al `PrivacyInfo.xcprivacy` antes de enviar a Apple.
- **Componentes**: un único `TarjetaCifra` que reemplace las cinco variantes, y un único badge que reemplace las siete. Borrar lo muerto (`GrillaIndicadores`, `MarcaClub`, y los parámetros ignorados de `Indicador`, `FichaDato` y `AccionRapida`).
- **`EsqueletoLista`** con `skeletonizer`, para reemplazar las 46 ruleditas centradas.
- **Sacar `HeroEvento`** de `gestion_screen.dart:533` a `core/widgets/`.

## Fase 1 · Servidor: privacidad (P0, antes que cualquier interfaz)

Migración nueva, siguiendo el patrón de `db/47` y `db/49`:

- `mesas_leer` pasa a `impl.ve_registro(evento_id, vendido_por)`.
- `bonos` igual.
- `team_reparto`: lectura solo para admin y el jefe del team.
- Revisar `cut_rel` y `pct_boliche`: lo mínimo es no bajarlos en las consultas que usa el rrpp (`eventos.dart:121`, `pagos.dart:191`).
- **Bug aparte**: `rrpp_eventos` (`db/41-relacionadores.sql:705`) decide la comisión de jefe mirando `profiles.rol` **global** en vez de `rol_en_club`. Quien es jefe en un boliche y rrpp en otro ve comisión de jefe en el boliche equivocado. Fuga de dinero entre boliches.
- Registrar en `impl.rpc_permiso` las funciones nuevas que quedaron fuera (`comisiones_mesas`, `opciones_operacion`, `reparto_jefe`, `ranking_teams`), para que vuelva a correr el chequeo de cobertura de `db/19:311-330`.

## Fase 2 · Evento activo

- El fallback deja de ser `lista.first`: pasa a **el próximo por empezar**, y si no hay, el más reciente.
- **Persistir** el evento elegido.
- La píldora **siempre visible**, también con un solo evento, mostrando fecha y estado.
- Tocar un evento en una lista **deja de cambiar el evento global**; para eso está la píldora o un botón explícito.
- En Mesas, Pagos y Accesos, una línea fija arriba con **de qué evento son los datos**.

## Fase 3 · Pantalla por pantalla

Orden por daño. Cada una se cierra completa: tokens, estados, permisos y tutorial de esa pantalla.

1. **Mesas** — la fuga, los precios condicionados a `eventos.comision_mesas`, el plano y el tutorial que hoy no existe.
2. **Eventos / Gestión** — una sola lista con eje temporal (próximos, hoy, pasados), "Crear evento" visible arriba, y que "Gestionar evento" muestre datos reales y no solo cuatro contadores y seis filas. Arreglar el campo `_cut` que se manda sin dibujarse (`gestion_screen.dart:1511,1619`).
3. **Pagos** — hoy no usa ninguna primitiva del sistema.
4. **Accesos** — unificar el duplicado `_Dato` con `TarjetaCifra`.
5. **Reporte** — ya usa bien el patrón; solo tokens y gráficos con `fl_chart`.
6. **Shell del relacionador** — su `_Cifra`, `_Vacio` y `_Estado` propios pasan a los compartidos.

## Fase 4 · Tutoriales

Hoy solo explica los cuatro botones de la barra, se rompe en tablet y **los relacionadores con cuenta propia no tienen ninguno**.

- Guía por pantalla, disparada la primera vez que se entra a cada una, con su propia clave en `SharedPreferences`.
- Cubrir Mesas, Accesos, Pagos y Gestión de evento, con los pasos reales del flujo.
- Llevar el tutorial al `RrppShell`.
- Que use los colores del tema en vez de los fijos (`tutorial.dart:119,172`).

---

## Verificación

- **Privacidad, con `curl` y no con la app**: con el token de sesión de un rrpp, pedir `mesas`, `bonos` y `team_reparto` directo al endpoint REST y confirmar que solo vuelve lo suyo. Es la única prueba que vale: la interfaz ya los ocultaba y el dato salía igual.
- Repetir con un jefe: tiene que ver su team y nada más.
- Un rrpp en dos boliches, jefe en uno: su historial no debe mezclar comisiones.
- **Evento activo**: con un evento viejo sin cerrar y uno futuro, la app debe abrir en el futuro.
- **Reglas del informe**: contraste y tamaño de los controles nuevos, texto al 200 % sin cortes, y que cada acción muestre estado al tocarla.
- `flutter analyze` sin errores ni advertencias y la suite de 106 pruebas verde después de cada pantalla.
- Pruebas nuevas para el fallback del evento activo y para la visibilidad de precios de mesa según `comision_mesas`.
