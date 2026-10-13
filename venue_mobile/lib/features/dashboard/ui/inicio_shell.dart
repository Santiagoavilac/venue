import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/sync/cola_offline.dart';
import '../../../core/theme/venue_theme.dart';
import '../../../core/widgets/avisos.dart';
import '../../../core/widgets/estado_vista.dart';
import '../../avisos/bienvenida.dart';
import '../../access_control/ui/escaner_screen.dart';
import '../../access_control/ui/lista_puerta_screen.dart';
import '../../access_control/ui/rrpps_screen.dart';
import '../../clubs/data/clubs.dart';
import '../../events/ui/eventos_screen.dart';
import '../../access_control/ui/accesos_screen.dart';
import 'cuenta_screen.dart';

class _Seccion {
  const _Seccion(this.titulo, this.icono, this.iconoOn, this.pantalla);
  final String titulo;
  final IconData icono;
  final IconData iconoOn;
  final Widget pantalla;
}

/// Secciones disponibles para un rol. La primera es su pantalla de trabajo:
/// el portero abre directo en el escáner, que es lo que hace toda la noche.
List<_Seccion> _seccionesPara(Rol rol) => [
      if (rol.vende)
        const _Seccion('Accesos', Icons.how_to_reg_outlined,
            Icons.how_to_reg_rounded, AccesosScreen()),
      if (rol.validaIngresos)
        const _Seccion('Escáner', Icons.qr_code_scanner_rounded,
            Icons.qr_code_scanner_rounded, EscanerScreen()),
      if (rol == Rol.portero)
        const _Seccion('Puerta', Icons.checklist_rounded,
            Icons.checklist_rounded, ListaPuertaScreen()),
      if (rol == Rol.portero)
        const _Seccion('RRPPs', Icons.groups_outlined, Icons.groups_rounded,
            RrppsScreen()),
      if (rol.veEventos)
        const _Seccion('Eventos', Icons.event_outlined, Icons.event_rounded,
            EventosScreen()),
      const _Seccion('Cuenta', Icons.person_outline_rounded,
          Icons.person_rounded, CuentaScreen()),
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
    final club = ref.watch(clubActivoProvider);

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
        return Scaffold(
          appBar: AppBar(
            title: Text(secciones[i].titulo),
            actions: [
              if (club != null)
                Padding(
                  padding: const EdgeInsets.only(right: 16),
                  child: Center(
                    child: Text(
                      club.nombre,
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                    ),
                  ),
                ),
            ],
          ),
          // Solo se monta la sección visible: la cámara del escáner se
          // apaga al salir de su pestaña.
          body: SafeArea(
            child: Column(
              children: [
                // Aviso fijo: la persona tiene que saber que está trabajando
                // sin señal y que hay cosas por enviar.
                if (pendientes > 0)
                  Material(
                    color: VenueColors.aviso,
                    child: InkWell(
                      onTap: () => _drenar(avisarSiNada: true),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 10),
                        child: Row(
                          children: [
                            const Icon(Icons.cloud_off_rounded,
                                color: Colors.black, size: 20),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                '$pendientes sin enviar · se reintenta solo',
                                style: const TextStyle(
                                    color: Colors.black,
                                    fontWeight: FontWeight.w700),
                              ),
                            ),
                            const Text('Reintentar',
                                style: TextStyle(
                                    color: Colors.black,
                                    fontWeight: FontWeight.w800)),
                          ],
                        ),
                      ),
                    ),
                  ),
                Expanded(child: secciones[i].pantalla),
              ],
            ),
          ),
          bottomNavigationBar: secciones.length < 2
              ? null
              : NavigationBar(
                  selectedIndex: i,
                  onDestinationSelected: (n) => setState(() => _i = n),
                  destinations: [
                    for (final s in secciones)
                      NavigationDestination(
                        icon: Icon(s.icono),
                        selectedIcon: Icon(s.iconoOn),
                        label: s.titulo,
                      ),
                  ],
                ),
        );
      },
    );
  }
}
