import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/widgets/estado_vista.dart';
import '../../access_control/ui/escaner_screen.dart';
import '../../access_control/ui/lista_puerta_screen.dart';
import '../../access_control/ui/rrpps_screen.dart';
import '../../clubs/data/clubs.dart';
import '../../events/ui/eventos_screen.dart';
import '../../guestlists/ui/listas_screen.dart';
import '../../tickets/ui/entradas_screen.dart';
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
        const _Seccion('Listas', Icons.list_alt_outlined,
            Icons.list_alt_rounded, ListasScreen()),
      if (rol.vende)
        const _Seccion('Entradas', Icons.qr_code_2_outlined,
            Icons.qr_code_2_rounded, EntradasScreen()),
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

class _InicioShellState extends ConsumerState<InicioShell> {
  int _i = 0;

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
          body: SafeArea(child: secciones[i].pantalla),
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
