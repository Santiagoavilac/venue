import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/routing/secciones.dart';
import '../../../core/sync/cola_offline.dart';
import '../../../core/theme/venue_theme.dart';
import '../../../core/widgets/avisos.dart';
import '../../../core/widgets/estado_vista.dart';
import '../../../core/widgets/foto_persona.dart';
import '../../../core/widgets/patron.dart';
import '../../../core/widgets/revolver.dart';
import '../../authentication/data/sesion.dart';
import '../../events/data/eventos.dart';
import '../../avisos/bienvenida.dart';
import '../../access_control/ui/escaner_screen.dart';
import '../../access_control/ui/lista_puerta_screen.dart';
import '../../access_control/ui/rrpps_screen.dart';
import '../../bar/ui/barra_screens.dart';
import '../../bar/ui/pos_screen.dart';
import '../../caja/caja.dart';
import '../../clubs/data/clubs.dart';
import '../../events/ui/eventos_screen.dart';
import '../../events/ui/gestion_screen.dart';
import '../../payments/ui/pagos_screen.dart';
import '../../teams/data/gente.dart';
import '../../teams/ui/gente_screen.dart';
import '../../vip_tables/ui/mesas_screen.dart';
import '../../access_control/ui/accesos_screen.dart';
import '../../analytics/ui/reporte_screen.dart';
import 'panel_perfil.dart';
import 'tutorial.dart';

class _Seccion {
  const _Seccion(this.titulo, this.icono, this.iconoOn, this.pantalla,
      {this.grupo = '', this.encabezadoPropio = false});
  final String titulo;
  final IconData icono;
  final IconData iconoOn;
  final Widget pantalla;

  /// Etiqueta en mayúsculas sobre el título (Puerta, Barra, Gestión…).
  final String grupo;

  /// La pantalla dibuja su propio [Encabezado]; si no, lo pone el shell.
  final bool encabezadoPropio;
}

/// Secciones disponibles para un rol. La primera es su pantalla de trabajo:
/// el portero abre directo en el escáner, que es lo que hace toda la noche.
/// El perfil y los ajustes no son una sección: van en el panel lateral.
List<_Seccion> _seccionesPara(Rol rol) {
  final l = _secciones(rol);
  if (rol != Rol.admin) return l;
  // el admin tiene a un toque lo de la noche; Accesos, Reporte y Usuarios
  // quedan detrás de "Más"
  const orden = ['Eventos', 'Escáner', 'Mesas', 'Pagos', 'Accesos', 'Reporte', 'Usuarios'];
  int pos(_Seccion s) => orden.contains(s.titulo) ? orden.indexOf(s.titulo) : orden.length;
  return [...l]..sort((a, b) => pos(a).compareTo(pos(b)));
}

List<_Seccion> _secciones(Rol rol) => [
      // los que venden arrancan en Eventos, con el resumen de la noche
      if (rol.vende)
        _Seccion('Eventos', Icons.event_outlined, Icons.event_rounded,
            rol == Rol.admin ? const GestionEventosScreen() : const EventosScreen(),
            grupo: 'Inicio', encabezadoPropio: true),
      // módulo barra: pestañas propias, no ven nada de puerta
      if (rol == Rol.propietario) ...const [
        _Seccion('Inventario', Icons.inventory_2_outlined, Icons.inventory_2_rounded,
            InventarioScreen(), grupo: 'Barra'),
        _Seccion('Vender', Icons.local_bar_outlined, Icons.local_bar_rounded, PosScreen(),
            grupo: 'Barra'),
        _Seccion('Cierre', Icons.receipt_long_outlined, Icons.receipt_long_rounded,
            CierreBarraScreen(), grupo: 'Barra'),
        _Seccion('Analítica', Icons.insights_outlined, Icons.insights_rounded,
            AnaliticaBarraScreen(), grupo: 'Barra'),
        _Seccion('Movimientos', Icons.swap_vert_rounded, Icons.swap_vert_rounded,
            MovimientosScreen(), grupo: 'Barra'),
      ],
      if (rol == Rol.deposito) ...const [
        _Seccion('Registrar', Icons.download_outlined, Icons.download_rounded,
            RecepcionScreen(), grupo: 'Depósito'),
        _Seccion('Lo mío', Icons.history_rounded, Icons.history_rounded,
            MisRecepcionesScreen(), grupo: 'Depósito'),
      ],
      if (rol == Rol.barra)
        const _Seccion('Vender', Icons.local_bar_outlined, Icons.local_bar_rounded,
            PosScreen(), grupo: 'Barra'),
      if (rol == Rol.caja)
        const _Seccion('Relacionadores', Icons.fact_check_outlined,
            Icons.fact_check_rounded, CajaScreen(), grupo: 'Caja'),
      if (rol.vende)
        const _Seccion('Accesos', Icons.how_to_reg_outlined,
            Icons.how_to_reg_rounded, AccesosScreen(), grupo: 'Puerta'),
      if (rol.validaIngresos)
        const _Seccion('Escáner', Icons.qr_code_scanner_rounded,
            Icons.qr_code_scanner_rounded, EscanerScreen(), grupo: 'Puerta'),
      if (rol == Rol.portero)
        const _Seccion('Puerta', Icons.checklist_rounded,
            Icons.checklist_rounded, ListaPuertaScreen(), grupo: 'Puerta'),
      if (rol == Rol.portero)
        const _Seccion('RRPPs', Icons.groups_outlined, Icons.groups_rounded,
            RrppsScreen(), grupo: 'Puerta'),
      if (rol.vende)
        const _Seccion('Pagos', Icons.payments_outlined, Icons.payments_rounded,
            PagosScreen(), grupo: 'Caja'),
      if (rol.veEventos)
        const _Seccion('Mesas', Icons.table_bar_outlined,
            Icons.table_bar_rounded, MesasScreen(), grupo: 'Salón'),
      if (rol.vende)
        _Seccion(rol == Rol.admin ? 'Reporte' : 'Stats', Icons.bar_chart_outlined,
            Icons.bar_chart_rounded, const ReporteScreen(), encabezadoPropio: true),
      if (rol == Rol.jefe)
        const _Seccion('Mi team', Icons.groups_outlined, Icons.groups_rounded,
            MiTeamScreen(), grupo: 'Team'),
      if (rol == Rol.admin)
        const _Seccion('Usuarios', Icons.manage_accounts_outlined,
            Icons.manage_accounts_rounded, GenteScreen(), encabezadoPropio: true),
      if (rol.veEventos && !rol.vende)
        const _Seccion('Eventos', Icons.event_outlined, Icons.event_rounded,
            EventosScreen(), grupo: 'Inicio', encabezadoPropio: true),
    ];

/// Pestaña abierta. Vive fuera del widget para sobrevivir al cambio de modo
/// claro/oscuro (que vuelve a montar la app); se reinicia al cambiar de
/// boliche o de cuenta.
class _SeccionActual extends Notifier<int> {
  @override
  int build() {
    ref.watch(clubActivoIdProvider);
    ref.watch(usuarioIdProvider);
    return 0;
  }

  void ir(int i) => state = i;
}

final _seccionActualProvider = NotifierProvider<_SeccionActual, int>(_SeccionActual.new);

class InicioShell extends ConsumerStatefulWidget {
  const InicioShell({super.key});

  @override
  ConsumerState<InicioShell> createState() => _InicioShellState();
}

class _InicioShellState extends ConsumerState<InicioShell>
    with WidgetsBindingObserver {
  int get _i => ref.read(_seccionActualProvider);
  set _i(int v) => ref.read(_seccionActualProvider.notifier).ir(v);
  bool _bienvenida = false;
  Timer? _reintento;
  final _andamio = GlobalKey<ScaffoldState>();
  final _claveBarra = GlobalKey();
  final _claveAvatar = GlobalKey();
  bool _tutorial = false;

  void _abrirPerfil() => _andamio.currentState?.openEndDrawer();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Lo que quedó sin enviar se reintenta solo: al abrir, al volver a la
    // app y cada 20 s mientras haya algo pendiente.
    _reintento = Timer.periodic(const Duration(seconds: 20), (_) {
      if (ref.read(pendientesProvider) > 0) _drenar();
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => _drenar());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _reintento?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _drenar();
  }

  Future<void> _drenar({bool avisarSiNada = false}) async {
    final r = await ref.read(pendientesProvider.notifier).drenar();
    if (!mounted || r == null) return;
    if (r.enviadas > 0) avisar(context, '${r.enviadas} pendiente(s) enviados');
    for (final x in r.rechazadas) {
      avisar(context, '${x.op.etiqueta} no se registró: ${x.motivo}',
          tipo: TipoAviso.aviso);
    }
    if (avisarSiNada && r.enviadas == 0 && r.quedan > 0) {
      avisar(context, 'Todavía sin señal', tipo: TipoAviso.aviso);
    }
  }

  @override
  Widget build(BuildContext context) {
    final rol = ref.watch(rolProvider);
    ref.watch(_seccionActualProvider);
    return rol.when(
      loading: () =>
          const Scaffold(body: Center(child: CircularProgressIndicator())),
      error: (e, _) => Scaffold(
        body: VistaAsync(
          valor: rol,
          datos: (_) => const SizedBox.shrink(),
          reintentar: () => ref.invalidate(rolProvider),
        ),
      ),
      data: (r) {
        if (r == null) {
          return Scaffold(
            body: MensajeVista(
              icono: Icons.lock_outline_rounded,
              titulo: 'Sin acceso a este boliche',
              detalle: 'Tu cuenta ya no tiene un rol acá.',
              accion: 'Elegir otro boliche',
              alTocar: () =>
                  ref.read(clubActivoIdProvider.notifier).elegir(null),
            ),
          );
        }
        if (!_bienvenida) {
          _bienvenida = true;
          WidgetsBinding.instance.addPostFrameCallback((_) async {
            await correrBienvenida(context, ref);
            // después de los avisos, el tutorial (una sola vez)
            final uid = ref.read(usuarioIdProvider);
            if (uid != null && mounted && !await tutorialVisto(uid) && mounted) {
              setState(() => _tutorial = true);
            }
          });
        }
        final pendientes = ref.watch(pendientesProvider);
        final secciones = _seccionesPara(r);
        // otra pantalla pidió ir a una sección (accesos rápidos del inicio)
        ref.listen(seccionPedidaProvider, (_, t) {
          if (t == null) return;
          final k = secciones.indexWhere((x) => x.titulo == t);
          if (k >= 0) setState(() => _i = k);
          ref.read(seccionPedidaProvider.notifier).atendida();
        });
        ref.listen(tutorialPedidoProvider, (_, _) => setState(() => _tutorial = true));
        final i = _i.clamp(0, secciones.length - 1);
        final sec = secciones[i];
        final ancho = MediaQuery.sizeOf(context).width >= 1000;

        // Lo que se ve debajo de la barra superior: aviso de cola sin
        // enviar, encabezado (si la pantalla no trae el suyo) y la pantalla.
        // Solo se monta la sección visible: la cámara del escáner se apaga
        // al salir de su pestaña.
        final contenido = Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (pendientes > 0) _AvisoCola(pendientes: pendientes, alTocar: () => _drenar(avisarSiNada: true)),
            if (!sec.encabezadoPropio)
              Padding(
                padding: EdgeInsets.fromLTRB(ancho ? 32 : 16, ancho ? 28 : 18, ancho ? 32 : 16, 0),
                child: Encabezado(titulo: sec.titulo),
              ),
            Expanded(
              child: ancho && sec.encabezadoPropio
                  ? Padding(padding: const EdgeInsets.symmetric(horizontal: 16), child: sec.pantalla)
                  : sec.pantalla,
            ),
          ],
        );

        final barra = _BarraSuperior(
          ancho: ancho,
          alCuenta: _abrirPerfil,
          claveAvatar: _claveAvatar,
        );

        if (ancho) {
          return Scaffold(
            key: _andamio,
            endDrawer: const PanelPerfil(),
            body: Row(children: [
              _Lateral(
                secciones: secciones,
                actual: i,
                alElegir: (n) => setState(() => _i = n),
                alPerfil: _abrirPerfil,
                rol: r,
              ),
              Expanded(
                child: SafeArea(
                  left: false,
                  child: Column(children: [barra, Expanded(child: contenido)]),
                ),
              ),
            ]),
          );
        }

        // En el teléfono entran cuatro y "Más" a la derecha: con más de
        // cinco botones quedan chicos para el dedo.
        const enLaBarra = 4;
        final conMas = secciones.length > enLaBarra;
        final enBarra = conMas ? secciones.sublist(0, enLaBarra) : secciones;
        Future<void> elegirEnBarra(int n) async {
          if (!conMas || n < enLaBarra) return setState(() => _i = n);
          final elegido = await showModalBottomSheet<int>(
            context: context,
            isScrollControlled: true,
            // el dedo gira el tambor: arrastrar no cierra la hoja
            enableDrag: false,
            showDragHandle: true,
            builder: (c) => SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  const Text('Más', style: TextStyle(fontSize: 19, fontWeight: FontWeight.w700)),
                  Text('Deslizá hacia los costados y tocá la que quieras',
                      style: TextStyle(color: VenueColors.textoSuave, fontSize: 13)),
                  Revolver(
                    opciones: [
                      for (var k = enLaBarra; k < secciones.length; k++)
                        OpcionRevolver(secciones[k].titulo, secciones[k].iconoOn, actual: k == i),
                    ],
                    alElegir: (n) => Navigator.pop(c, n + enLaBarra),
                  ),
                ]),
              ),
            ),
          );
          if (elegido != null && mounted) setState(() => _i = elegido);
        }

        final andamio = Scaffold(
          key: _andamio,
          endDrawer: const PanelPerfil(),
          body: SafeArea(
            bottom: false,
            child: Column(children: [barra, Expanded(child: contenido)]),
          ),
          // barra flotante: tarjeta redondeada separada de los bordes
          bottomNavigationBar: secciones.length < 2
              ? null
              : SafeArea(
                  top: false,
                  minimum: const EdgeInsets.only(bottom: 8),
                  child: Container(
                  key: _claveBarra,
                  margin: const EdgeInsets.fromLTRB(12, 4, 12, 0),
                  clipBehavior: Clip.antiAlias,
                  decoration: BoxDecoration(
                    color: VenueColors.superficie,
                    borderRadius: BorderRadius.circular(24),
                    border: bordeTarjeta,
                    boxShadow: const [
                      BoxShadow(color: Color(0x1A101828), blurRadius: 24, offset: Offset(0, 8)),
                    ],
                  ),
                  child: Material(
                    type: MaterialType.transparency,
                    child: SizedBox(
                    height: 70,
                    child: Row(children: [
                      for (var n = 0; n < enBarra.length + (conMas ? 1 : 0); n++)
                        Expanded(
                          child: _BotonBarra(
                            icono: n < enBarra.length ? enBarra[n].icono : Icons.more_horiz_rounded,
                            iconoOn: n < enBarra.length ? enBarra[n].iconoOn : Icons.more_horiz_rounded,
                            texto: n < enBarra.length ? enBarra[n].titulo : 'Más',
                            activo: n == (conMas && i >= enLaBarra ? enLaBarra : i),
                            alTocar: () => elegirEnBarra(n),
                          ),
                        ),
                    ]),
                  ),
                  ),
                ),
                ),
        );
        if (!_tutorial || secciones.length < 2) return andamio;

        // rectángulo del botón n de la barra de abajo
        final total = enBarra.length + (conMas ? 1 : 0);
        Rect? boton(int n) {
          final b = _claveBarra.currentContext?.findRenderObject() as RenderBox?;
          if (b == null || !b.hasSize) return null;
          final o = b.localToGlobal(Offset.zero);
          final w = b.size.width / total;
          return Rect.fromLTWH(o.dx + w * n, o.dy, w, b.size.height);
        }

        Rect? avatar() {
          final b = _claveAvatar.currentContext?.findRenderObject() as RenderBox?;
          if (b == null || !b.hasSize) return null;
          return b.localToGlobal(Offset.zero) & b.size;
        }

        final pasos = [
          for (final (n, s) in enBarra.indexed)
            PasoTutorial(
              icono: s.iconoOn,
              titulo: s.titulo,
              texto: _queEs(s.titulo, r),
              objetivo: () => boton(n),
              alMostrar: () => setState(() => _i = n),
            ),
          if (conMas)
            PasoTutorial(
              icono: Icons.more_horiz_rounded,
              titulo: 'Más',
              texto: 'Acá están ${_enLista([for (final s in secciones.skip(enLaBarra)) s.titulo])}. '
                  'Se eligen girando la ruleta.',
              objetivo: () => boton(enLaBarra),
            ),
          PasoTutorial(
            icono: Icons.person_rounded,
            titulo: 'Tu perfil',
            texto: 'Tocá tu inicial para editar tu perfil, cambiar a modo oscuro'
                '${r == Rol.admin ? ', elegir los colores y el logo del boliche' : ''} o cerrar sesión. '
                'Desde ahí también podés ver este tutorial de nuevo.',
            objetivo: avatar,
            alMostrar: () => setState(() => _i = 0),
          ),
        ];
        return Stack(children: [
          andamio,
          Positioned.fill(
            child: TutorialGuiado(
              pasos: pasos,
              alTerminar: () {
                final uid = ref.read(usuarioIdProvider);
                if (uid != null) marcarTutorialVisto(uid);
                setState(() {
                  _tutorial = false;
                  _i = 0;
                });
              },
            ),
          ),
        ]);
      },
    );
  }
}

String _enLista(List<String> l) => l.length < 2
    ? l.join()
    : '${l.sublist(0, l.length - 1).join(', ')} y ${l.last}';

/// Qué es cada sección, en una o dos líneas para el tutorial.
String _queEs(String titulo, Rol rol) => switch (titulo) {
      'Eventos' => rol == Rol.admin
          ? 'Tu evento de la noche con sus números. Desde "Gestionar evento" lo editás, '
              'armás las listas y las fases, y creás eventos nuevos.'
          : 'El evento de la noche con sus números y tus accesos rápidos.',
      'Escáner' => 'Escaneá los QR en la puerta. Cada entrada vale para un solo ingreso.',
      'Mesas' => 'El plano del boliche: qué mesas están libres, vender y reservar.',
      'Pagos' => 'Lo que se cobró y lo que falta, por team y por persona.',
      'Accesos' => 'Anotá invitados en las listas y vendé entradas con QR.',
      'Reporte' => 'El cierre del evento: la plata, la asistencia, los mejores relacionadores y cada team.',
      'Stats' => 'Tus números del evento: cuántos entraron por vos y tu comisión.',
      'Mi team' => 'Tu team y lo que vendió cada uno.',
      'Usuarios' => 'Tu gente agrupada por team: roles, permisos y altas.',
      'Puerta' => 'La lista de invitados para marcar quién entra.',
      'RRPPs' => 'Los relacionadores de la noche y sus invitados.',
      'Vender' => 'Cobrá en la barra.',
      'Relacionadores' => 'Lo que hay que pagarle a cada relacionador.',
      _ => 'Tocá aquí para abrir $titulo.',
    };


/// Un botón de la barra de abajo: el activo en el color del boliche y con
/// un punto debajo.
class _BotonBarra extends StatelessWidget {
  const _BotonBarra({
    required this.icono, required this.iconoOn, required this.texto,
    required this.activo, required this.alTocar,
  });
  final IconData icono, iconoOn;
  final String texto;
  final bool activo;
  final VoidCallback alTocar;

  @override
  Widget build(BuildContext context) {
    final c = activo ? Theme.of(context).colorScheme.primary : VenueColors.textoTenue;
    return Semantics(
      button: true,
      selected: activo,
      label: texto,
      excludeSemantics: true,
      child: InkWell(
        onTap: alTocar,
        borderRadius: BorderRadius.circular(16),
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(activo ? iconoOn : icono, size: 26, color: c),
          const SizedBox(height: 3),
          Text(texto,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                  fontSize: 12.5, fontWeight: activo ? FontWeight.w700 : FontWeight.w500, color: c)),
          const SizedBox(height: 3),
          Container(
            width: 5,
            height: 5,
            decoration: BoxDecoration(
                color: activo ? c : Colors.transparent, shape: BoxShape.circle),
          ),
        ]),
      ),
    );
  }
}

/// Aviso fijo: la persona tiene que saber que está trabajando sin señal y
/// que hay cosas por enviar.
class _AvisoCola extends StatelessWidget {
  const _AvisoCola({required this.pendientes, required this.alTocar});
  final int pendientes;
  final VoidCallback alTocar;

  @override
  Widget build(BuildContext context) => Material(
        color: VenueColors.aviso,
        child: InkWell(
          onTap: alTocar,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            child: Row(children: [
              const Icon(Icons.cloud_off_rounded, color: Colors.black, size: 20),
              const SizedBox(width: 10),
              Expanded(
                child: Text('$pendientes sin enviar · se reintenta solo',
                    style: const TextStyle(color: Colors.black, fontWeight: FontWeight.w700)),
              ),
              const Text('Reintentar',
                  style: TextStyle(color: Colors.black, fontWeight: FontWeight.w800)),
            ]),
          ),
        ),
      );
}

/// Elegir otro boliche: los mismos que ofrece el selector del inicio.
Future<void> _cambiarClub(BuildContext context, WidgetRef ref) async {
  final clubs = ref.read(clubsProvider).value ?? const <Club>[];
  final actual = ref.read(clubActivoIdProvider);
  final elegido = await showModalBottomSheet<String>(
    context: context,
    builder: (c) => SafeArea(
      child: ListView(
        shrinkWrap: true,
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        children: [
          const Padding(
            padding: EdgeInsets.only(bottom: 10, left: 4),
            child: Text('Cambiar local', style: TextStyle(fontSize: 19, fontWeight: FontWeight.w700)),
          ),
          for (final cl in clubs)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Material(
                color: VenueColors.superficie2,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                  side: BorderSide(
                      color: cl.id == actual ? (cl.primario ?? VenueColors.linea) : VenueColors.linea),
                ),
                clipBehavior: Clip.antiAlias,
                child: ListTile(
                  leading: Theme(
                    data: Theme.of(c).copyWith(
                      colorScheme: Theme.of(c).colorScheme.copyWith(
                            primary: cl.primario ?? VenueColors.marcaPorDefecto,
                            secondary: cl.secundario ?? cl.primario ?? VenueColors.marcaPorDefecto,
                          ),
                    ),
                    child: MarcaClub(inicial: cl.inicial, logo: cl.logoUrl, lado: 34),
                  ),
                  title: Text(cl.nombre, style: const TextStyle(fontWeight: FontWeight.w600)),
                  trailing: cl.id == actual ? const Icon(Icons.check_rounded) : null,
                  onTap: () => Navigator.pop(c, cl.id),
                ),
              ),
            ),
          const SizedBox(height: 4),
          OutlinedButton.icon(
            onPressed: () => Navigator.pop(c, ''),
            icon: const Icon(Icons.storefront_outlined),
            label: const Text('Ver todos los boliches'),
          ),
        ],
      ),
    ),
  );
  // '' es la pantalla con todos los boliches (y "Nuevo boliche")
  if (elegido == '') {
    ref.read(clubActivoIdProvider.notifier).elegir(null);
  } else if (elegido != null && elegido != actual) {
    ref.read(clubActivoIdProvider.notifier).elegir(elegido);
  }
}

/// Elegir el evento de trabajo (el resto de la app opera sobre ese).
Future<void> _cambiarEvento(BuildContext context, WidgetRef ref) async {
  final eventos = ref.read(eventosProvider).value ?? const <Evento>[];
  final actual = ref.read(eventoActivoProvider)?.id;
  if (eventos.length < 2) return;
  final elegido = await showModalBottomSheet<String>(
    context: context,
    builder: (c) => SafeArea(
      child: ListView(
        shrinkWrap: true,
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        children: [
          const Padding(
            padding: EdgeInsets.only(bottom: 10, left: 4),
            child: Text('Evento', style: TextStyle(fontSize: 19, fontWeight: FontWeight.w700)),
          ),
          for (final e in eventos)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Material(
                color: VenueColors.superficie2,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                  side: BorderSide(
                      color: e.id == actual ? Theme.of(c).colorScheme.primary : VenueColors.linea),
                ),
                clipBehavior: Clip.antiAlias,
                child: ListTile(
                  leading: const Icon(Icons.calendar_today_outlined),
                  title: Text(e.nombre, style: const TextStyle(fontWeight: FontWeight.w600)),
                  subtitle: Text(e.fechaCorta),
                  trailing: e.id == actual ? const Icon(Icons.check_rounded) : null,
                  onTap: () => Navigator.pop(c, e.id),
                ),
              ),
            ),
        ],
      ),
    ),
  );
  if (elegido != null) ref.read(eventoElegidoProvider.notifier).elegir(elegido);
}

/// Píldora del evento de trabajo en la barra.
class _Pildora extends StatelessWidget {
  const _Pildora({required this.child, this.alTocar});
  final Widget child;
  final VoidCallback? alTocar;

  @override
  Widget build(BuildContext context) => Container(
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: VenueColors.superficie,
          borderRadius: BorderRadius.circular(16),
          border: bordeTarjeta,
          boxShadow: sombraTarjeta,
        ),
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            onTap: alTocar,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              child: child,
            ),
          ),
        ),
      );
}

/// Barra superior: boliche, evento y cuenta. La misma que la web.
class _BarraSuperior extends ConsumerWidget {
  const _BarraSuperior({required this.ancho, this.alCuenta, this.claveAvatar});
  final bool ancho;
  final VoidCallback? alCuenta;

  /// Para que el tutorial sepa dónde está la inicial.
  final Key? claveAvatar;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final club = ref.watch(clubActivoProvider);
    final ev = ref.watch(eventoActivoProvider);
    final perfil = ref.watch(perfilProvider).value;
    // con un boliche solo no hay nada que cambiar, salvo el superadmin, que
    // desde la lista da de alta boliches nuevos
    final varios = (ref.watch(clubsProvider).value?.length ?? 0) > 1 ||
        (ref.watch(plataformaProvider).value ?? false);
    final variosEv = (ref.watch(eventosProvider).value?.length ?? 0) > 1;

    // boliche como en Fourvenues: logo y "Club / Nombre ▾"
    final pClub = InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: varios ? () => _cambiarClub(context, ref) : null,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 2),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          MarcaClub(inicial: club?.inicial ?? '·', logo: club?.logoUrl, lado: 46),
          const SizedBox(width: 12),
          Flexible(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Club', style: TextStyle(fontSize: 13, color: VenueColors.textoSuave, height: 1.1)),
                Row(mainAxisSize: MainAxisSize.min, children: [
                  Flexible(
                    child: Text(club?.nombre ?? '',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w800, height: 1.2)),
                  ),
                  if (varios)
                    Icon(Icons.keyboard_arrow_down_rounded, size: 20, color: VenueColors.textoSuave),
                ]),
              ],
            ),
          ),
        ]),
      ),
    );
    final textoEv = Text.rich(
      TextSpan(children: [
        TextSpan(text: ev?.nombre ?? 'Sin evento', style: const TextStyle(fontWeight: FontWeight.w600)),
        if (ev != null)
          TextSpan(text: '  ·  ${ev.fechaCorta}', style: TextStyle(color: VenueColors.textoSuave)),
      ]),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: const TextStyle(fontSize: 15),
    );
    final pEv = _Pildora(
      alTocar: variosEv ? () => _cambiarEvento(context, ref) : null,
      child: Row(mainAxisSize: ancho ? MainAxisSize.min : MainAxisSize.max, children: [
        Icon(Icons.calendar_today_outlined, size: 20, color: Theme.of(context).colorScheme.primary),
        const SizedBox(width: 12),
        ancho ? Flexible(child: textoEv) : Expanded(child: textoEv),
        if (variosEv) ...[
          const SizedBox(width: 6),
          Icon(Icons.chevron_right_rounded, size: 22, color: VenueColors.textoSuave),
        ],
      ]),
    );
    // la inicial abre el panel de perfil y ajustes
    final avatar = Semantics(
      key: claveAvatar,
      button: true,
      label: 'Perfil y ajustes',
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: alCuenta,
        child: FotoPersona(nombre: perfil?.nombre ?? '·', url: perfil?.fotoUrl, tam: 46),
      ),
    );

    return Container(
      padding: EdgeInsets.fromLTRB(ancho ? 28 : 16, ancho ? 14 : 8, ancho ? 28 : 16, 10),
      color: VenueColors.fondo,
      child: ancho
          ? Row(children: [pClub, const SizedBox(width: 16), pEv, const Spacer(), avatar])
          : Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Row(children: [Expanded(child: Align(alignment: Alignment.centerLeft, child: pClub)), avatar]),
              const SizedBox(height: 12),
              pEv,
            ]),
    );
  }
}

/// Barra lateral de pantallas anchas (tablet, escritorio): boliche arriba,
/// secciones con la activa teñida, cuenta abajo.
class _Lateral extends ConsumerWidget {
  const _Lateral({
    required this.secciones,
    required this.actual,
    required this.alElegir,
    required this.alPerfil,
    required this.rol,
  });
  final List<_Seccion> secciones;
  final int actual;
  final ValueChanged<int> alElegir;
  final VoidCallback alPerfil;
  final Rol rol;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final club = ref.watch(clubActivoProvider);
    final perfil = ref.watch(perfilProvider).value;
    final varios = (ref.watch(clubsProvider).value?.length ?? 0) > 1;
    final esq = Theme.of(context).colorScheme;
    Widget item(int k) {
      final s = secciones[k];
      final on = k == actual;
      return Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: Material(
          color: on ? VenueColors.superficie2 : Colors.transparent,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(11)),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: () => alElegir(k),
            child: Container(
              height: 46,
              padding: const EdgeInsets.symmetric(horizontal: 14),
              child: Row(children: [
                Icon(on ? s.iconoOn : s.icono,
                    size: 21, color: on ? esq.primary : VenueColors.textoSuave),
                const SizedBox(width: 14),
                Expanded(
                  child: Text(s.titulo,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontSize: 15,
                          fontWeight: on ? FontWeight.w600 : FontWeight.w500,
                          color: on ? VenueColors.texto : VenueColors.textoSuave)),
                ),
              ]),
            ),
          ),
        ),
      );
    }

    return Container(
      width: 256,
      decoration: BoxDecoration(
        color: VenueColors.lateral,
        border: Border(right: BorderSide(color: VenueColors.lineaSuave)),
      ),
      child: SafeArea(
        right: false,
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 16, 14, 12),
            child: Material(
              color: VenueColors.superficie,
              elevation: elevacionTarjeta,
              shadowColor: const Color(0x29101828),
              shape: formaTarjeta,
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: varios ? () => _cambiarClub(context, ref) : null,
                child: Padding(
                  padding: const EdgeInsets.all(11),
                  child: Row(children: [
                    MarcaClub(inicial: club?.inicial ?? '·', logo: club?.logoUrl, lado: 40),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(club?.nombre ?? '',
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                        Text(varios ? 'Cambiar local' : rol.etiqueta,
                            style: TextStyle(fontSize: 12.5, color: VenueColors.textoTenue)),
                      ]),
                    ),
                    if (varios)
                      Icon(Icons.keyboard_arrow_down_rounded, color: VenueColors.textoTenue),
                  ]),
                ),
              ),
            ),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              children: [
                for (var k = 0; k < secciones.length; k++) item(k),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
            decoration: BoxDecoration(
                border: Border(top: BorderSide(color: VenueColors.lineaSuave))),
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: alPerfil,
              child: Padding(
                padding: const EdgeInsets.all(8),
                child: Row(children: [
                  CircleAvatar(
                    radius: 21,
                    backgroundColor: VenueColors.superficie2,
                    child: Text(perfil?.inicial ?? '·',
                        style: TextStyle(fontWeight: FontWeight.w700, color: VenueColors.texto)),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(perfil?.nombre ?? '',
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                      Text(rol.etiqueta,
                          style: TextStyle(fontSize: 12.5, color: VenueColors.textoTenue)),
                    ]),
                  ),
                  Icon(Icons.chevron_right_rounded, color: VenueColors.textoTenue),
                ]),
              ),
            ),
          ),
        ]),
      ),
    );
  }
}
