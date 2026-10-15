import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/sync/cola_offline.dart';
import '../../../core/theme/venue_theme.dart';
import '../../../core/widgets/avisos.dart';
import '../../../core/widgets/estado_vista.dart';
import '../../../core/widgets/patron.dart';
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
import '../../teams/ui/gente_screen.dart';
import '../../vip_tables/ui/mesas_screen.dart';
import '../../access_control/ui/accesos_screen.dart';
import '../../analytics/ui/reporte_screen.dart';
import 'cuenta_screen.dart';

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
List<_Seccion> _seccionesPara(Rol rol) => [
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
        const _Seccion('Gente', Icons.manage_accounts_outlined,
            Icons.manage_accounts_rounded, GenteScreen(), encabezadoPropio: true),
      if (rol.veEventos)
        _Seccion('Eventos', Icons.event_outlined, Icons.event_rounded,
            rol == Rol.admin ? const GestionEventosScreen() : const EventosScreen(),
            grupo: 'Inicio'),
      const _Seccion('Cuenta', Icons.person_outline_rounded,
          Icons.person_rounded, CuentaScreen(), grupo: 'Perfil'),
    ];

class InicioShell extends ConsumerStatefulWidget {
  const InicioShell({super.key});

  @override
  ConsumerState<InicioShell> createState() => _InicioShellState();
}

class _InicioShellState extends ConsumerState<InicioShell>
    with WidgetsBindingObserver {
  int _i = 0;
  bool _bienvenida = false;
  Timer? _reintento;

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
          WidgetsBinding.instance.addPostFrameCallback(
              (_) => correrBienvenida(context, ref));
        }
        final pendientes = ref.watch(pendientesProvider);
        final secciones = _seccionesPara(r);
        final i = _i.clamp(0, secciones.length - 1);
        final sec = secciones[i];
        final ancho = MediaQuery.sizeOf(context).width >= 1000;
        final iCuenta = secciones.indexWhere((x) => x.pantalla is CuentaScreen);

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
                child: Encabezado(
                  etiqueta: sec.grupo.isEmpty ? null : sec.grupo,
                  titulo: sec.titulo,
                ),
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
          alCuenta: iCuenta < 0 ? null : () => setState(() => _i = iCuenta),
        );

        if (ancho) {
          return Scaffold(
            body: Row(children: [
              _Lateral(
                secciones: secciones,
                actual: i,
                alElegir: (n) => setState(() => _i = n),
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

        // En el teléfono entran cuatro; el resto va detrás de "Más".
        final conMas = secciones.length > 5;
        final enBarra = conMas ? secciones.sublist(0, 4) : secciones;
        return Scaffold(
          body: SafeArea(
            bottom: false,
            child: Column(children: [barra, Expanded(child: contenido)]),
          ),
          bottomNavigationBar: secciones.length < 2
              ? null
              : DecoratedBox(
                  decoration: const BoxDecoration(
                      border: Border(top: BorderSide(color: VenueColors.lineaSuave))),
                  child: NavigationBar(
                    selectedIndex: conMas && i >= 4 ? 4 : i,
                    onDestinationSelected: (n) async {
                      if (!conMas || n < 4) return setState(() => _i = n);
                      final elegido = await showModalBottomSheet<int>(
                        context: context,
                        builder: (c) => SafeArea(
                          child: ListView(
                            shrinkWrap: true,
                            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                            children: [
                              const Padding(
                                padding: EdgeInsets.only(bottom: 10, left: 4),
                                child: Text('Más',
                                    style: TextStyle(fontSize: 19, fontWeight: FontWeight.w700)),
                              ),
                              for (var k = 4; k < secciones.length; k++)
                                Padding(
                                  padding: const EdgeInsets.only(bottom: 8),
                                  child: Material(
                                    color: k == i
                                        ? Theme.of(c).colorScheme.primary.withValues(alpha: .17)
                                        : VenueColors.superficie2,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12),
                                      side: const BorderSide(color: VenueColors.linea),
                                    ),
                                    clipBehavior: Clip.antiAlias,
                                    child: ListTile(
                                      leading: Icon(secciones[k].icono),
                                      title: Text(secciones[k].titulo,
                                          style: const TextStyle(fontWeight: FontWeight.w500)),
                                      trailing: const Icon(Icons.chevron_right_rounded),
                                      onTap: () => Navigator.pop(c, k),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      );
                      if (elegido != null && mounted) setState(() => _i = elegido);
                    },
                    destinations: [
                      for (final s in enBarra)
                        NavigationDestination(
                          icon: Icon(s.icono),
                          selectedIcon: Icon(s.iconoOn),
                          label: s.titulo,
                        ),
                      if (conMas)
                        const NavigationDestination(
                            icon: Icon(Icons.more_horiz_rounded), label: 'Más'),
                    ],
                  ),
                ),
        );
      },
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
                    child: MarcaClub(inicial: cl.inicial, lado: 34),
                  ),
                  title: Text(cl.nombre, style: const TextStyle(fontWeight: FontWeight.w600)),
                  trailing: cl.id == actual ? const Icon(Icons.check_rounded) : null,
                  onTap: () => Navigator.pop(c, cl.id),
                ),
              ),
            ),
        ],
      ),
    ),
  );
  if (elegido != null && elegido != actual) {
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

/// Píldora con borde: el contenedor de boliche y evento en la barra.
class _Pildora extends StatelessWidget {
  const _Pildora({required this.child, this.alTocar});
  final Widget child;
  final VoidCallback? alTocar;

  @override
  Widget build(BuildContext context) => Material(
        color: VenueColors.superficie,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(13),
          side: const BorderSide(color: VenueColors.linea),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: alTocar,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
            child: child,
          ),
        ),
      );
}

/// Barra superior: boliche, evento y cuenta. La misma que la web.
class _BarraSuperior extends ConsumerWidget {
  const _BarraSuperior({required this.ancho, this.alCuenta});
  final bool ancho;
  final VoidCallback? alCuenta;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final club = ref.watch(clubActivoProvider);
    final ev = ref.watch(eventoActivoProvider);
    final perfil = ref.watch(perfilProvider).value;
    final varios = (ref.watch(clubsProvider).value?.length ?? 0) > 1;
    final variosEv = (ref.watch(eventosProvider).value?.length ?? 0) > 1;
    final marca = Theme.of(context).colorScheme.primary;

    final pClub = _Pildora(
      alTocar: varios ? () => _cambiarClub(context, ref) : null,
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        MarcaClub(inicial: club?.inicial ?? '·', lado: 32),
        if (ancho) ...[
          const SizedBox(width: 10),
          Text(club?.nombre ?? '', style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
          if (varios) ...[
            const SizedBox(width: 8),
            const Icon(Icons.keyboard_arrow_down_rounded, size: 20, color: VenueColors.textoTenue),
          ],
        ],
      ]),
    );
    final pEv = _Pildora(
      alTocar: variosEv ? () => _cambiarEvento(context, ref) : null,
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        const Icon(Icons.calendar_today_outlined, size: 19, color: VenueColors.textoSuave),
        const SizedBox(width: 10),
        Flexible(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(ev?.nombre ?? 'Sin evento',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w600, height: 1.2)),
              if (ev != null)
                Text(ev.fechaCorta,
                    style: const TextStyle(fontSize: 12, color: VenueColors.textoTenue, height: 1.25)),
            ],
          ),
        ),
        if (variosEv) ...[
          const SizedBox(width: 8),
          const Icon(Icons.keyboard_arrow_down_rounded, size: 20, color: VenueColors.textoTenue),
        ],
      ]),
    );
    final avatar = Material(
      color: Color.alphaBlend(marca.withValues(alpha: .22), VenueColors.superficie2),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: marca.withValues(alpha: .4)),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: alCuenta,
        child: SizedBox(
          width: 46,
          height: 46,
          child: Center(
            child: Text(perfil?.inicial ?? '·',
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
          ),
        ),
      ),
    );

    return Container(
      padding: EdgeInsets.symmetric(horizontal: ancho ? 28 : 14, vertical: ancho ? 14 : 10),
      decoration: const BoxDecoration(
        color: VenueColors.fondo,
        border: Border(bottom: BorderSide(color: VenueColors.lineaSuave)),
      ),
      child: Row(children: [
        pClub,
        const SizedBox(width: 10),
        if (ancho) pEv else Expanded(child: Align(alignment: Alignment.centerLeft, child: pEv)),
        if (ancho) const Spacer(),
        const SizedBox(width: 10),
        avatar,
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
    required this.rol,
  });
  final List<_Seccion> secciones;
  final int actual;
  final ValueChanged<int> alElegir;
  final Rol rol;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final club = ref.watch(clubActivoProvider);
    final perfil = ref.watch(perfilProvider).value;
    final varios = (ref.watch(clubsProvider).value?.length ?? 0) > 1;
    final esq = Theme.of(context).colorScheme;
    final iCuenta = secciones.indexWhere((x) => x.pantalla is CuentaScreen);

    Widget item(int k) {
      final s = secciones[k];
      final on = k == actual;
      return Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: Material(
          color: on ? esq.primary.withValues(alpha: .17) : Colors.transparent,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(11)),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: () => alElegir(k),
            child: Container(
              height: 46,
              padding: const EdgeInsets.symmetric(horizontal: 14),
              child: Row(children: [
                Icon(on ? s.iconoOn : s.icono,
                    size: 21, color: on ? esq.secondary : VenueColors.textoSuave),
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
      decoration: const BoxDecoration(
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
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
                side: const BorderSide(color: VenueColors.linea),
              ),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: varios ? () => _cambiarClub(context, ref) : null,
                child: Padding(
                  padding: const EdgeInsets.all(11),
                  child: Row(children: [
                    MarcaClub(inicial: club?.inicial ?? '·', lado: 40),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(club?.nombre ?? '',
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                        Text(varios ? 'Cambiar local' : rol.etiqueta,
                            style: const TextStyle(fontSize: 12.5, color: VenueColors.textoTenue)),
                      ]),
                    ),
                    if (varios)
                      const Icon(Icons.keyboard_arrow_down_rounded, color: VenueColors.textoTenue),
                  ]),
                ),
              ),
            ),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              children: [
                for (var k = 0; k < secciones.length; k++)
                  if (k != iCuenta) item(k),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
            decoration: const BoxDecoration(
                border: Border(top: BorderSide(color: VenueColors.lineaSuave))),
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: iCuenta < 0 ? null : () => alElegir(iCuenta),
              child: Padding(
                padding: const EdgeInsets.all(8),
                child: Row(children: [
                  CircleAvatar(
                    radius: 21,
                    backgroundColor: VenueColors.superficie2,
                    child: Text(perfil?.inicial ?? '·',
                        style: const TextStyle(fontWeight: FontWeight.w700, color: VenueColors.texto)),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(perfil?.nombre ?? '',
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                      Text(rol.etiqueta,
                          style: const TextStyle(fontSize: 12.5, color: VenueColors.textoTenue)),
                    ]),
                  ),
                  const Icon(Icons.chevron_right_rounded, color: VenueColors.textoTenue),
                ]),
              ),
            ),
          ),
        ]),
      ),
    );
  }
}
