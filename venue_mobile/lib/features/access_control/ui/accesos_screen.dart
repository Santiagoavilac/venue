import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/networking/supabase.dart';
import '../../../core/sync/tiempo_real.dart';
import '../../../core/theme/venue_theme.dart';
import '../../../core/widgets/estado_vista.dart';
import '../../events/data/eventos.dart';
import '../../guestlists/data/listas.dart';
import '../../clubs/data/clubs.dart';
import '../../guestlists/ui/listas_screen.dart';
import '../../tickets/data/entradas.dart';
import '../../tickets/ui/entradas_screen.dart';
import 'escaner_screen.dart';

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
              _Dato(
                'Adentro ahora',
                '$adentro',
                'Invitados de lista y entradas con QR que ya ingresaron',
                color: VenueColors.ok,
              ),
              Row(
                children: [
                  Expanded(
                    child: _Dato(
                      'Anotados en listas',
                      '${n('anotados')}',
                      '${n('ingresaron')} ingresaron',
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _Dato(
                      'Entradas con QR',
                      '${n('qr_total')}',
                      '${n('qr_usados')} ingresaron',
                    ),
                  ),
                ],
              ),
              Row(
                children: [
                  Expanded(
                    child: _Dato('Prepagadas', '${n('entradas')}', 'vendidas'),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _Dato(
                      'Mesas',
                      '${n('mesas')}',
                      'vendidas o reservadas',
                    ),
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

class _Dato extends StatelessWidget {
  const _Dato(this.titulo, this.valor, this.pie, {this.color});
  final String titulo;
  final String valor;
  final String pie;
  final Color? color;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              titulo,
              style: TextStyle(
                color: VenueColors.textoSuave,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              valor,
              style: TextStyle(
                fontSize: 34,
                fontWeight: FontWeight.w800,
                color: color,
              ),
            ),
            Text(
              pie,
              style: TextStyle(color: VenueColors.textoSuave, fontSize: 12.5),
            ),
          ],
        ),
      ),
    ),
  );
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

