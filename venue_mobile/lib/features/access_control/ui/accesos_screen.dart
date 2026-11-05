import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/networking/supabase.dart';
import '../../../core/sync/tiempo_real.dart';
import '../../../core/theme/venue_theme.dart';
import '../../../core/widgets/estado_vista.dart';
import '../../../core/widgets/tarjeta_cifra.dart';
import '../../events/data/eventos.dart';
import '../../guestlists/data/listas.dart';
import '../../clubs/data/clubs.dart';
import '../../guestlists/ui/listas_screen.dart';
import '../../tickets/data/entradas.dart';
import '../../tickets/ui/entradas_screen.dart';
import 'escaner_screen.dart';
import '../../events/ui/cambiar_evento.dart';

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
        ref.invalidate(resumenProvider);
      });
    }
    return DefaultTabController(
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
    );
  }
}

final resumenProvider = FutureProvider.autoDispose<Map<String, int>>((
  ref,
) async {
  final ev = ref.watch(eventoActivoProvider);
  if (ev == null) return const {};
  final r = Map<String, dynamic>.from(
    await ref
            .watch(supabaseProvider)
            .rpc('resumen_evento', params: {'p_evento': ev.id})
        as Map,
  );
  return r.map((k, v) => MapEntry(k, (v as num?)?.toInt() ?? 0));
});

/// Quién puede entrar y quién ya entró, en números.
class ResumenView extends ConsumerWidget {
  const ResumenView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final r = ref.watch(resumenProvider);
    return RefreshIndicator(
      onRefresh: () => ref.refresh(resumenProvider.future),
      child: VistaAsync(
        valor: r,
        reintentar: () => ref.invalidate(resumenProvider),
        datos: (d) {
          int n(String k) => d[k] ?? 0;
          final adentro = n('ingresaron') + n('qr_usados');
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              TarjetaCifra(etiqueta: 'Adentro ahora', valor: '$adentro', detalle: 'Invitados de lista y entradas con QR que ya ingresaron', color: VenueColors.ok),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TarjetaCifra(etiqueta: 'Anotados en listas', valor: '${n('anotados')}', detalle: '${n('ingresaron')} ingresaron'),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TarjetaCifra(etiqueta: 'Entradas con QR', valor: '${n('qr_total')}', detalle: '${n('qr_usados')} ingresaron'),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TarjetaCifra(etiqueta: 'Prepagadas', valor: '${n('entradas')}', detalle: 'vendidas'),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TarjetaCifra(etiqueta: 'Mesas', valor: '${n('mesas')}', detalle: 'vendidas o reservadas'),
                  ),
                ],
              ),
            ],
          );
        },
      ),
    );
  }
}

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

