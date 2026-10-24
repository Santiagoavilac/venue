import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/venue_theme.dart';
import '../../../core/widgets/estado_vista.dart';
import '../../teams/data/equipo.dart';
import '../data/entradas.dart';

/// Entradas prepagadas del evento agrupadas por team: cuántas vendió cada
/// uno, cuánto suman, en qué fase y a qué precio, y quién de cada team.
/// El admin ve todos los teams; el jefe, solo el suyo ([soloTeam]).
Future<void> mostrarReporteTeams(BuildContext context, WidgetRef ref, {String? soloTeam}) =>
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      useSafeArea: true,
      backgroundColor: VenueColors.superficie,
      builder: (_) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: .85,
        maxChildSize: .95,
        builder: (_, scroll) => _ReporteTeams(scroll: scroll, soloTeam: soloTeam),
      ),
    );

class _Grupo {
  _Grupo(this.nombre);
  final String nombre;
  int vendidas = 0;
  int ingresaron = 0;
  int anuladas = 0;
  num total = 0;

  /// fase (o "Precio único") → (cantidad, precio unitario, total)
  final fases = <String, ({int n, num precio, num total})>{};
  final vendedores = <String, ({int n, num total})>{};

  void sumar(Entrada e, String fase, String vendedor) {
    if (e.estado == 'anulada') {
      anuladas++;
      return;
    }
    vendidas++;
    total += e.precio;
    if (e.estado == 'usada') ingresaron++;
    final f = fases[fase];
    fases[fase] = (n: (f?.n ?? 0) + 1, precio: e.precio, total: (f?.total ?? 0) + e.precio);
    final v = vendedores[vendedor];
    vendedores[vendedor] = (n: (v?.n ?? 0) + 1, total: (v?.total ?? 0) + e.precio);
  }
}

class _ReporteTeams extends ConsumerWidget {
  const _ReporteTeams({required this.scroll, this.soloTeam});
  final ScrollController scroll;
  final String? soloTeam;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final equipo = ref.watch(equipoProvider).value ?? const <String, Miembro>{};
    final fases = {
      for (final f in ref.watch(fasesProvider).value ?? const <Fase>[]) f.id: f.nombre
    };
    return VistaAsync(
      valor: ref.watch(entradasProvider),
      reintentar: () => ref.invalidate(entradasProvider),
      datos: (entradas) {
        final grupos = <String, _Grupo>{};
        final general = _Grupo('Total');
        for (final e in entradas) {
          final m = equipo[e.rrppId];
          final teamId = m?.teamId ?? '';
          if (soloTeam != null && teamId != soloTeam) continue;
          final fase = fases[e.faseId] ?? 'Precio único';
          final vendedor = e.rrppNombre.isNotEmpty ? e.rrppNombre : (m?.nombre ?? '—');
          grupos
              .putIfAbsent(teamId, () => _Grupo(teamId.isEmpty ? 'Sin team' : (m?.team ?? 'Sin team')))
              .sumar(e, fase, vendedor);
          general.sumar(e, fase, vendedor);
        }
        final orden = grupos.values.toList()
          ..sort((a, b) => b.vendidas.compareTo(a.vendidas));

        return ListView(
          controller: scroll,
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
          children: [
            const Text('Entradas por team',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
            const SizedBox(height: 4),
            Text(
              '${general.vendidas} vendidas · ${general.ingresaron} ingresaron · ${general.total} Bs'
              '${general.anuladas > 0 ? ' · ${general.anuladas} anuladas' : ''}',
              style: TextStyle(color: VenueColors.textoSuave),
            ),
            if (general.fases.length > 1) ...[
              const SizedBox(height: 8),
              _Fases(general),
            ],
            const SizedBox(height: 12),
            if (orden.isEmpty)
              Padding(
                padding: EdgeInsets.all(24),
                child: Text('Todavía no hay entradas vendidas.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: VenueColors.textoSuave)),
              ),
            for (final g in orden) _TarjetaTeam(g),
          ],
        );
      },
    );
  }
}

class _TarjetaTeam extends StatelessWidget {
  const _TarjetaTeam(this.g);
  final _Grupo g;

  @override
  Widget build(BuildContext context) {
    final vendedores = g.vendedores.entries.toList()
      ..sort((a, b) => b.value.n.compareTo(a.value.n));
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          tilePadding: const EdgeInsets.symmetric(horizontal: 14),
          childrenPadding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
          title: Row(children: [
            Expanded(
                child: Text(g.nombre,
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800))),
            Text('${g.total} Bs', style: const TextStyle(fontWeight: FontWeight.w800)),
          ]),
          subtitle: Text(
            '${g.vendidas} vendidas · ${g.ingresaron} ingresaron'
            '${g.anuladas > 0 ? ' · ${g.anuladas} anuladas' : ''}',
            style: TextStyle(color: VenueColors.textoSuave, fontSize: 13),
          ),
          children: [
            _Fases(g),
            const SizedBox(height: 10),
            for (final v in vendedores)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: Row(children: [
                  Expanded(child: Text(v.key)),
                  Text('${v.value.n} · ${v.value.total} Bs',
                      style: TextStyle(color: VenueColors.textoSuave)),
                ]),
              ),
          ],
        ),
      ),
    );
  }
}

/// Desglose por fase: "Hot tickets · 12 × 60 Bs = 720 Bs".
class _Fases extends StatelessWidget {
  const _Fases(this.g);
  final _Grupo g;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: VenueColors.superficie2,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: VenueColors.lineaSuave),
        ),
        child: Column(children: [
          for (final f in g.fases.entries)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Row(children: [
                Expanded(
                    child: Text(f.key, style: const TextStyle(fontWeight: FontWeight.w700))),
                Text('${f.value.n} × ${f.value.precio} Bs = ${f.value.total} Bs',
                    style: TextStyle(color: VenueColors.textoSuave)),
              ]),
            ),
        ]),
      );
}
