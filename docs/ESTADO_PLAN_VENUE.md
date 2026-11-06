# Estado del plan de Venue

Avance de `PLAN_EXPERIENCIA_VENUE.md`. Se actualiza en el mismo commit que el
trabajo. Última actualización: 2026-11-05.

**Las cuatro fases están cerradas y las migraciones están aplicadas** en el
proyecto `cxksjarupexptfksnptg` (05/11/2026). Lo único que queda es probar la
privacidad con `curl` usando sesiones reales. Está al final, en Pendiente de
verdad.

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
- [ ] **Pendiente de verdad**: probar con `curl`, no con la app. Token de rrpp
      contra `mesas`, `bonos` y `team_reparto`; repetir con un jefe; y un rrpp
      en dos boliches, jefe en uno. Necesita un proyecto real con datos, así
      que no se puede cerrar desde una sesión sin credenciales

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
- [x] Mesas, Accesos, Pagos y Gestión tienen la suya, con los pasos del flujo
      real de cada una. La de Pagos cambia según quien mire: el que rinde ve
      cómo se arma su cuenta; el que cobra, qué verificar antes de marcar
- [x] `RrppShell` tiene la suya: su espacio, los eventos y el enlace, las
      ganancias con sus tres estados, y que el historial es suyo aunque lo
      saquen de un boliche
- [x] Los colores salen de `Oscuro`, no de hexadecimales sueltos (quedó hecho
      al unificar la paleta)

## Fuera del plan, ya hecho

- Teclado que no se bajaba cuando el campo que lo abrió desaparecía: `VigilanteDelTeclado`
  en las dos apps
- AFTR: foto de perfil en las historias, y publicar reventa sin número de cuenta
  cuando hay QR de cobro

## Pendiente de verdad

Nada de esto se puede cerrar sin un proyecto real delante:

1. ~~Aplicar las migraciones en Supabase~~ **Hecho.** Estaban aplicadas todas
   menos tres (`061000`, `070000`, `080000`), que se aplicaron una por una
   verificando antes y después. El historial del proyecto no las tenía
   registradas aunque estuvieran aplicadas, así que también se puso al día con
   `supabase migration repair`: ahora `migration list` dice la verdad.
   Al revisar los permisos apareció un agujero que no estaba en el plan y se
   cerró con `20261105090000`: `mesas_detalle` tenía INSERT/UPDATE/DELETE para
   `authenticated` y, como corre con los permisos de su dueño, cualquiera con
   sesión podía escribir en `mesas` sin pasar por RLS.
2. ~~Probar la privacidad con `curl`~~ **Hecho** (05/11/2026), con las cuentas
   de demo del boliche Aurora y una mesa de prueba vendida por `rrpp.aurora`:
   - `mesas`: un relacionador recibe 403 en `precio`, `cliente`, `vendido_por`,
     `metodo_pago`, `comprobante_url` y en `select=*`; el plano sale igual.
   - `mesas_detalle`: el admin, el jefe del team, el portero y quien la vendió
     ven los 700 Bs; otro relacionador del mismo boliche recibe la fila con
     `precio` y `cliente` en null.
   - Escribir por la vista: `PATCH` y `DELETE` dan 403.
   - `bonos`: sólo el dueño, su jefe y el admin. Otro relacionador, cero filas.
   - `team_reparto`: el admin y los del team; el portero, cero filas.
   - Comisión de jefe por boliche: con el mismo usuario puesto en los dos
     boliches, `rol_en_club` devuelve `jefe` en uno y `rrpp` en el otro, que es
     lo que ahora mira `rrpp_eventos`.

   **Corregido** (migración `20261105110000`): el portero veía los `bonos` de
   los relacionadores y el precio de cada mesa, porque `impl.ve_registro` le da
   todo. Ahora la plata pasa por `impl.ve_plata`, que es lo mismo menos el
   portero; lo operativo —cliente, estado, quién vendió— le queda igual, que
   es de lo que depende la puerta. Probado con las cuentas de Burtown: el
   portero ve el cliente de la mesa y no su precio, y cero bonos.

   La prueba se hizo en el boliche de demo Aurora, que después se borró a
   pedido. Para repetirla hay cuentas de prueba en Burtown: `prueba.admin`,
   `prueba.jefe`, `prueba.rrpp` y `prueba.portero`, todas con la clave de
   siempre y el correo `usuario@plataforma.local`.
3. **Mirar las pantallas en un teléfono.** Todo lo de acá está verificado con
   `flutter analyze`, 140 pruebas y las de base sobre PostgreSQL descartable,
   pero el contraste y los tamaños reales se ven mirando.

---

## 06/11/2026 · Las webs vuelven a publicarse con el push

Las dos webs servían el código del 05/11 a las 03:47: los proyectos de Vercel
no estaban conectados al repo (`link: null`, y todos los despliegues sin commit
asociado). El detalle de por qué y cómo quedó está en `docs/AUTH_URLS.md`.

Hecho:

- `tools/armar_web.mjs` y `aftr_web/armar.mjs` arman la carpeta `dist/` que se
  publica —sólo los archivos de la web, nombre por nombre— y escriben
  `config.js` desde `SUPABASE_URL` y `SUPABASE_ANON_KEY`, ya cargadas en los
  dos proyectos. Sin esas variables usan el `config.js` local, así que
  desplegar a mano desde la máquina sigue funcionando.
- `.vercelignore` en la raíz y en `aftr_web/`.
- `cleanUrls` en `aftr_web/vercel.json`: `/terminos`, `/privacidad` y `/normas`
  contestaban 404.
- `.github/workflows/publicar-webs.yml` publica las dos en cada push a `main`.
- `tests/armar-web.test.mjs`: 6 pruebas que comparan lo que el HTML carga con
  lo que el armador copia, para que la lista no se quede vieja.

Verificado: las dos webs en vivo con el código de ayer
(`subirComprobanteEntrada` y `pase_libre` en venuebol.com, `reventaEnInicio` en
aftrvenue.com), `config.js` servido desde las variables, `/terminos`,
`/privacidad` y `/normas` en 200, y `db/`, `docs/`, `CLAUDE.md` y `.env.local`
en 404. 22 pruebas de web en verde (16 de antes + 6 nuevas) y `node --check` de
los 12 archivos de las dos webs.

**Falta un paso que no puedo hacer yo**: cargar el secreto `VERCEL_TOKEN` en el
repo (GitHub → Settings → Secrets and variables → Actions), con un token del
equipo `venue6`. Hasta que esté, el workflow falla a propósito y lo explica.
Mejor todavía sería la integración de Git de Vercel, que trae previews por
rama; para eso hay que darle acceso de escritura a `venuegestion-lab` sobre
`Santiagoavilac/venue`.

---

## 06/11/2026 · Comprar sin cuenta, y los 18+ en las dos puertas

Pedido: no obligar a nadie a abrir cuenta para comprar, pero sí para PULSE,
mesas, historias, reventa y rachas; y decir siempre que es para mayores de 18
y que se aceptan los términos.

Hecho:

- **Los 18+ y los términos, en una sola casilla y en las dos puertas.**
  `aftr_crear_perfil` recibe `p_acepta` y guarda `mayor_edad` y `acepto_at`.
  Queda opcional a propósito: hay apps publicadas que llaman con dos
  argumentos y si se exigiera, nadie con la app vieja podría abrir cuenta. Lo
  aceptado no se desacepta: una app vieja que manda `false` no borra una
  constancia anterior. En la app la casilla es una sola pieza
  (`casilla_mayor_edad.dart`) que usan el onboarding y la compra sin cuenta;
  en la web es `casillaMayorEdad()`, igual.
- **El formulario de compra sin cuenta en la web**, el mismo que ya estaba en
  la app: nombre, apellido, correo, carnet, celular opcional y la casilla.
  Crea la sesión anónima recién al enviar, y si el formulario no llega a
  guardar la cierra, para no dejar una sesión sin perfil que rompe Accesos.
- **La puerta del invitado, del lado del servidor.** Ayer puse la línea de
  "cuenta real" en trece RPC y me faltaron nueve: `aftr_pulse` y
  `aftr_mis_mesas` contestaban **200** a una sesión anónima. Cerradas también
  `aftr_carta_mesa`, `aftr_mis_pedidos_mesa`, `aftr_mesa_retirar`,
  `aftr_reservar_historia`, `aftr_guardar`, `aftr_seguir` y
  `aftr_cambiar_foto`.
- **Y una guarda que no se ejecutaba.** En `aftr_reservar_historia` la línea
  estaba en el cuerpo, pero el `declare` llamaba a
  `impl.historia_atribucion(...)`, y el declare corre antes del primer
  `begin`: a un invitado le contestaba "La historia ya no está disponible" en
  vez de pedirle cuenta. Revisadas las 22 funciones con guarda; era la única.
- **Del lado del cliente, que no vea botones que fallan.** `asegurarCuenta`
  rechaza al invitado y le abre el ingreso explicando por qué;
  `asegurarParaComprar` es la única que no pide cuenta. El acceso fijo a
  PULSE no se le muestra, el método de pago le va derecho al QR, y en Cuenta
  ve qué es ser invitado y un botón para pasar a tener cuenta. Ese botón usa
  `linkIdentity`, que engancha la cuenta a la sesión que ya tiene en vez de
  abrir otra: si no, las entradas compradas de invitado quedan colgadas de un
  usuario al que nadie vuelve a entrar. Para eso hubo que prender
  `security_manual_linking_enabled` en el proyecto.
- Y cerrar sesión siendo invitado ahora avisa: no hay cuenta a la que volver,
  así que es perder las entradas.

Verificado:

- `tests/test_invitado.py` contra el REST de producción, **31/31**: lo público
  abierto sin sesión, el invitado deja sus datos y le sirven `aftr_mi_perfil`
  y `aftr_mis_accesos`, y **17 RPC** le piden cuenta con el mensaje de la app.
  Se borra sola lo que crea.
- 39 pruebas de base sobre PostgreSQL descartable (33 de antes y 6 nuevas: los
  18+ al abrir cuenta, la app vieja de dos argumentos, que lo aceptado no se
  desacepta, que la sesión anónima se reconoce, que `aftr_cuenta_real` la
  rechaza, y que el formulario exige los 18 y un correo).
- 34 pruebas de web (28 de antes y 6 nuevas de la puerta del invitado), 46 de
  AFTR en Flutter (41 y 5 nuevas de la casilla y del onboarding), 159 de
  Venue, `flutter analyze` sin errores ni advertencias en las dos, y
  `tests/rpc_con_guarda.py` en verde.
- Y en el navegador de verdad sobre `www.aftrvenue.com`: el formulario abre,
  tocar Continuar sin marcar la casilla **no crea ninguna sesión** y muestra
  el aviso, y no hay errores en consola. Ahí se vio y se arregló que todos los
  campos salían en rojo antes de escribir nada
  (`:invalid:not(:placeholder-shown)` marca los vacíos cuando no hay
  `placeholder`; va `:user-invalid`).

Queda: instalar la app nueva en el teléfono (la última es anterior a todo
esto), y probar `linkIdentity` con una cuenta de Google de verdad, que es lo
único que no se puede probar sin pasar por el ingreso del proveedor.

---

## 06/11/2026 · Probar las dos pasarelas nuevas (y de paso, una por boliche)

**Lo que se pidió fue probar si sirven las dos pasarelas nuevas. La respuesta
está al final: el banco las rechaza.** Lo de abajo -que cada boliche pueda
cobrar a su propia cuenta- salió de esa prueba y es más de lo que se pidió:
queda apagado, sin ningún boliche ni evento apuntado a ninguna pasarela, así
que todo cobra a la cuenta de la plataforma exactamente como antes.

### Cada boliche puede cobrar a su propia cuenta (apagado)

Llegaron dos cuentas más del Banco Económico (de André, para SitRoom) y había
una sola pasarela para toda la plataforma: todo lo cobrado con QR caía en la
misma cuenta, la que se configuró primero. Con dos boliches más, la plata de
uno terminaría en la cuenta del otro.

Cómo quedó. La pasarela es un nombre corto —`sitroom`, `sitcom`— y es lo único
que viaja por la base. Las credenciales siguen en los secretos de la Edge
Function, con ese nombre como prefijo:

    BANECO_SITROOM_USER, BANECO_SITROOM_ACCOUNT,
    BANECO_SITROOM_AES_KEY, BANECO_SITROOM_PASSWORD

y lo que un boliche no defina se toma del `BANECO_` de siempre, que pasa a ser
el de la plataforma. **Ningún número de cuenta ni ninguna llave entra en la
base**, que es la razón por la que estaban en los secretos desde el principio.
Un boliche sin pasarela cobra exactamente como hasta ahora.

El evento puede tener la suya, igual que `logistica`: una fiesta de terceros en
un boliche propio cobra aparte. Vacío = la del boliche. Las recargas de PULSE
son de la plataforma siempre, no de un boliche.

Lo que hubo que mover:

- `pago_qr.pasarela`: el cobro recuerda con qué cuenta se generó, igual que
  `ambiente`. Sin eso, un boliche que cambia de cuenta deja sus QR viejos sin
  nadie que los consulte ni los anule.
- El cursor de conciliación era por ambiente y ahora es por ambiente y
  pasarela: cada cuenta tiene su propia lista de pagados en el banco.
- El barrido corre una vez por pasarela.

Probado en producción: dos eventos de SitRoom, uno heredando la cuenta del
boliche y el otro con la de Sitcom, comprando como invitado y pidiendo el QR a
la Edge Function. **El camino funciona**: con la pasarela de la plataforma el
QR sale (se generó, se verificó y se anuló en el banco al terminar). Con
`sitroom` y `sitcom` llega a autenticar con esas credenciales y el banco las
rechaza —ver abajo—, que es justamente la prueba de que no está usando la de
la plataforma.

Verificado además: 23 pruebas de base de baneco sobre PostgreSQL descartable
(16 de antes y 7 nuevas), 37 de la Edge Function en Deno (32 y 5 nuevas), 39 de
base social, 28 de web y `tests/rpc_con_guarda.py` en verde.

### Bloqueado: el banco rechaza las dos credenciales nuevas

    usuario adicional A… (cuenta de SitRoom) → 401 "Credenciales de autenticacion no validas."
    usuario adicional B… (cuenta de Sitcom)  → 401 "Credenciales de autenticacion no validas."

Los usuarios, las cuentas y las llaves no se escriben acá: están en los
secretos de Supabase y en el chat con el banco.

Probado con el mismo cliente y el mismo cifrado AES que usa la pasarela que sí
funciona, contra `apimkt.baneco.com.bo`. Se probó **una vez cada una** y se
paró ahí: insistir con contraseñas distintas bloquea el usuario en el banco.

Los secretos ya están cargados con lo que mandó el banco, así que cuando se
aclare la contraseña es cambiar un valor y nada más. Lo que hay que preguntarle
a Rebeca (Banco Económico):

1. El código de 4 dígitos que mandaron por cada cuenta, ¿es la contraseña de
   APIMARKET del usuario adicional, o sólo el código de la cuenta? En la
   pasarela que ya funciona la contraseña también es de 4 dígitos, por eso se
   probó así.
2. El primero figura en el correo como "usuario adicional **de consulta**";
   sólo del segundo dice que se lo habilitó para APIMARKET. ¿Están los dos
   habilitados para el sistema?
3. ¿Hace falta una primera activación del usuario adicional antes de que la API
   lo acepte?

La clave de banca por internet del titular no se usó ni se va a usar: la API
tiene sus propios usuarios.
