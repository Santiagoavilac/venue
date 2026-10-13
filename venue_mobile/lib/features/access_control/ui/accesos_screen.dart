import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/networking/supabase.dart';
import '../../../core/sync/tiempo_real.dart';
import '../../../core/theme/venue_theme.dart';
import '../../../core/widgets/avisos.dart';
import '../../../core/widgets/estado_vista.dart';
import '../../authentication/data/sesion.dart';
import '../../events/data/eventos.dart';
import '../../guestlists/data/listas.dart';
import '../../guestlists/ui/listas_screen.dart';
import '../../tickets/data/entradas.dart';
import '../../tickets/ui/entradas_screen.dart';

/// Accesos para quien vende: Resumen, Listas, Entradas y —solo la cuenta
/// principal— Historial. Es la misma sección de la web, con las mismas
/// pestañas.
class AccesosScreen extends ConsumerWidget {
  const AccesosScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final conHistorial = ref.watch(perfilProvider).value?.adminPrincipal ?? false;
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
      length: conHistorial ? 4 : 3,
      child: Column(
        children: [
          TabBar(
            isScrollable: conHistorial,
            tabAlignment: conHistorial ? TabAlignment.start : null,
            tabs: [
              const Tab(text: 'Listas'),
              const Tab(text: 'Entradas'),
              const Tab(text: 'Resumen'),
              if (conHistorial) const Tab(text: 'Historial'),
            ],
          ),
          Expanded(
            child: TabBarView(
              children: [
                const ListasScreen(),
                const EntradasScreen(),
                const ResumenView(),
                if (conHistorial) const HistorialView(),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

final resumenProvider = FutureProvider.autoDispose<Map<String, int>>((ref) async {
  final ev = ref.watch(eventoActivoProvider);
  if (ev == null) return const {};
  final r = Map<String, dynamic>.from(await ref
      .watch(supabaseProvider)
      .rpc('resumen_evento', params: {'p_evento': ev.id}) as Map);
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
              _Dato('Adentro ahora', '$adentro',
                  'Invitados de lista y entradas con QR que ya ingresaron',
                  color: VenueColors.ok),
              Row(children: [
                Expanded(child: _Dato('Anotados en listas', '${n('anotados')}',
                    '${n('ingresaron')} ingresaron')),
                const SizedBox(width: 12),
                Expanded(child: _Dato('Entradas con QR', '${n('qr_total')}',
                    '${n('qr_usados')} ingresaron')),
              ]),
              Row(children: [
                Expanded(child: _Dato('Prepagadas', '${n('entradas')}', 'vendidas')),
                const SizedBox(width: 12),
                Expanded(child: _Dato('Mesas', '${n('mesas')}', 'vendidas o reservadas')),
              ]),
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
                Text(titulo,
                    style: const TextStyle(
                        color: VenueColors.textoSuave, fontWeight: FontWeight.w600)),
                const SizedBox(height: 4),
                Text(valor,
                    style: TextStyle(
                        fontSize: 34, fontWeight: FontWeight.w800, color: color)),
                Text(pie,
                    style: const TextStyle(
                        color: VenueColors.textoSuave, fontSize: 12.5)),
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
List<Ingreso> armarHistorial(List<Invitado> invitados, List<Entrada> entradas,
    Map<String, String> nombreLista) {
  final l = <Ingreso>[
    for (final i in invitados)
      if (i.ingreso)
        Ingreso(i.nombre, nombreLista[i.listaId] ?? 'Lista', i.rrppNombre, i.ingresoAt!),
    for (final e in entradas)
      if (e.estado == 'usada' && e.usedAt != null)
        Ingreso(e.cliente, 'Entradas', e.rrppNombre, e.usedAt!),
  ]..sort((a, b) => b.cuando.compareTo(a.cuando));
  return l;
}

class HistorialView extends ConsumerStatefulWidget {
  const HistorialView({super.key});

  @override
  ConsumerState<HistorialView> createState() => _HistorialViewState();
}

class _HistorialViewState extends ConsumerState<HistorialView> {
  String? _cat;

  @override
  Widget build(BuildContext context) {
    final invitados = ref.watch(invitadosProvider);
    final entradas = ref.watch(entradasProvider);
    final listas = ref.watch(listasProvider).value ?? const <ListaTipo>[];
    return VistaAsync(
      valor: invitados,
      reintentar: () => ref.invalidate(invitadosProvider),
      datos: (inv) {
        final todos = armarHistorial(inv, entradas.value ?? const [],
            {for (final l in listas) l.id: l.nombre});
        final porCat = <String, int>{};
        for (final i in todos) {
          porCat[i.categoria] = (porCat[i.categoria] ?? 0) + 1;
        }
        final filas = _cat == null ? todos : todos.where((i) => i.categoria == _cat).toList();
        if (todos.isEmpty) {
          return const MensajeVista(
              icono: Icons.history_rounded, titulo: 'Todavía no ingresó nadie');
        }
        return ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
          children: [
            Wrap(spacing: 8, runSpacing: 4, children: [
              ChoiceChip(
                label: Text('Todos (${todos.length})'),
                selected: _cat == null,
                onSelected: (_) => setState(() => _cat = null),
              ),
              for (final c in porCat.entries)
                ChoiceChip(
                  label: Text('${c.key} (${c.value})'),
                  selected: _cat == c.key,
                  onSelected: (_) => setState(() => _cat = c.key),
                ),
            ]),
            const SizedBox(height: 8),
            for (final i in filas)
              ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                title: Text(i.nombre,
                    style: const TextStyle(fontSize: 15.5, fontWeight: FontWeight.w600)),
                subtitle: Text(
                    [i.categoria, if (i.quien.isNotEmpty) i.quien].join(' · ')),
                trailing: Text(horaCorta(i.cuando),
                    style: const TextStyle(fontWeight: FontWeight.w700)),
              ),
          ],
        );
      },
    );
  }
}
