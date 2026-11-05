import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/sync/tiempo_real.dart';
import '../../events/data/eventos.dart';
import '../../guestlists/data/listas.dart';
import '../../clubs/data/clubs.dart';
import '../../guestlists/ui/listas_screen.dart';
import '../../tickets/data/entradas.dart';
import '../../tickets/ui/entradas_screen.dart';
import 'escaner_screen.dart';
import '../../events/ui/cambiar_evento.dart';
import '../../events/data/gestion.dart';
import '../../dashboard/ui/tutorial.dart';

/// Accesos para quien vende: Listas, Entradas y —para quien valida en la
/// puerta— Escáner. El resumen de números está en la tarjeta del evento.
///
/// El escáner vive acá, junto a las listas y las entradas que valida, en vez
/// de ser una sección aparte. El Historial se sacó: nadie lo usaba.
class AccesosScreen extends ConsumerWidget {
  const AccesosScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final conEscaner = ref.watch(rolProvider).value?.validaIngresos ?? false;
    final ev = ref.watch(eventoActivoProvider);
    if (ev != null) {
      // lo que cambia otro (un ingreso en puerta, una venta) refresca solo
      ref.listen(cambiosEventoProvider(ev.id), (_, c) {
        final t = c.value ?? const <String>{};
        if (t.contains('registros')) ref.invalidate(invitadosProvider);
        if (t.contains('entradas')) {
          ref.invalidate(entradasProvider);
          ref.invalidate(misEntradasProvider);
        }
        // los números del evento, que son los que se ven en el inicio
        ref.invalidate(numerosEventoProvider(ev.id));
      });
    }
    return GuiaDePantalla(
      guia: 'accesos',
      pasos: () => [
        const PasoTutorial(
          icono: Icons.format_list_bulleted_rounded,
          titulo: 'Listas',
          texto: 'Acá anotás invitados y los marcás cuando llegan. Cada lista '
              'tiene su cupo y su hora límite, que pone el boliche.',
          objetivo: _sinFlecha,
        ),
        const PasoTutorial(
          icono: Icons.qr_code_2_rounded,
          titulo: 'Entradas',
          texto: 'Las entradas prepagadas con QR. Desde acá se venden, se '
              'reenvían y se ve cuáles ya se usaron.',
          objetivo: _sinFlecha,
        ),
        if (conEscaner)
          const PasoTutorial(
            icono: Icons.qr_code_scanner_rounded,
            titulo: 'Escáner',
            texto: 'En la puerta, el escáner valida el QR y marca el ingreso. '
                'Un QR ya usado avisa en rojo y no deja pasar dos veces.',
            objetivo: _sinFlecha,
          ),
      ],
      child: DefaultTabController(
      length: conEscaner ? 3 : 2,
      child: Column(
        children: [
          const DeQueEvento(),
          TabBar(
            isScrollable: conEscaner,
            tabAlignment: conEscaner ? TabAlignment.start : null,
            tabs: [
              const Tab(text: 'Listas'),
              const Tab(text: 'Entradas'),
              if (conEscaner) const Tab(text: 'Escáner'),
            ],
          ),
          Expanded(
            child: TabBarView(
              children: [
                const ListasScreen(),
                const EntradasScreen(),
                if (conEscaner) const EscanerScreen(),
              ],
            ),
          ),
        ],
      ),
      ),
    );
  }
}

/// Los pasos que explican una pantalla entera no apuntan a ningún botón.
Rect? _sinFlecha() => null;

/// Un ingreso ya ocurrido, de lista o de entrada, para el Historial.
class Ingreso {
  const Ingreso(this.nombre, this.categoria, this.quien, this.cuando);
  final String nombre;
  final String categoria;
  final String quien;
  final DateTime cuando;
}

/// Une invitados y entradas que ya ingresaron, del más reciente al más viejo.
/// La pestaña Historial se sacó de Accesos porque no se usaba; esto queda
/// porque lo cubre una prueba y sirve para rearmar la vista si hace falta.
List<Ingreso> armarHistorial(
  List<Invitado> invitados,
  List<Entrada> entradas,
  Map<String, String> nombreLista,
) {
  final l = <Ingreso>[
    for (final i in invitados)
      if (i.ingreso)
        Ingreso(
          i.nombre,
          nombreLista[i.listaId] ?? 'Lista',
          i.rrppNombre,
          i.ingresoAt!,
        ),
    for (final e in entradas)
      if (e.estado == 'usada' && e.usedAt != null)
        Ingreso(e.cliente, 'Entradas', e.rrppNombre, e.usedAt!),
  ]..sort((a, b) => b.cuando.compareTo(a.cuando));
  return l;
}

