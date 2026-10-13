import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/venue_theme.dart';
import '../../../core/widgets/avisos.dart';
import '../../../core/widgets/estado_vista.dart';
import '../../clubs/data/clubs.dart';
import '../../events/data/eventos.dart';
import '../data/persona_puerta.dart';
import '../data/puerta_repository.dart';

final _rosterProvider = FutureProvider.autoDispose<List<Relacionador>>((ref) {
  final club = ref.watch(clubActivoIdProvider);
  if (club == null) return const [];
  final ev = ref.watch(eventoActivoProvider);
  return ref.watch(puertaRepositoryProvider).relacionadores(club, ev?.id);
});

/// Consulta de relacionadores para la puerta: el guardia busca a quien llega
/// y ve de qué team es. Solo lectura; marcar quién pasó es de la caja.
class RrppsScreen extends ConsumerStatefulWidget {
  const RrppsScreen({super.key});

  @override
  ConsumerState<RrppsScreen> createState() => _RrppsScreenState();
}

class _RrppsScreenState extends ConsumerState<RrppsScreen> {
  String _q = '';

  @override
  Widget build(BuildContext context) {
    final roster = ref.watch(_rosterProvider);
    return VistaAsync(
      valor: roster,
      reintentar: () => ref.invalidate(_rosterProvider),
      datos: (gente) {
        final q = normalizar(_q.trim());
        final visibles = q.length < 2
            ? gente
            : gente
                .where((g) => normalizar('${g.nombre} ${g.usuario}').contains(q))
                .toList();
        final porTeam = <String, List<Relacionador>>{};
        for (final g in visibles) {
          porTeam.putIfAbsent(g.team, () => []).add(g);
        }
        final teams = porTeam.keys.toList()
          ..sort((a, b) => a == 'Sin team'
              ? 1
              : b == 'Sin team'
                  ? -1
                  : a.toLowerCase().compareTo(b.toLowerCase()));
        for (final t in teams) {
          porTeam[t]!.sort(
              (a, b) => a.nombre.toLowerCase().compareTo(b.nombre.toLowerCase()));
        }

        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
              child: TextField(
                autocorrect: false,
                onChanged: (v) => setState(() => _q = v),
                decoration: InputDecoration(
                  hintText: 'Buscar relacionador…',
                  prefixIcon: const Icon(Icons.search_rounded),
                  suffixText: '${gente.length}',
                ),
              ),
            ),
            Expanded(
              child: visibles.isEmpty
                  ? MensajeVista(
                      icono: Icons.group_off_outlined,
                      titulo: gente.isEmpty
                          ? 'No hay relacionadores en la lista'
                          : 'Sin resultados',
                    )
                  : RefreshIndicator(
                      onRefresh: () => ref.refresh(_rosterProvider.future),
                      child: ListView(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                        children: [
                          for (final t in teams) ...[
                            Padding(
                              padding: const EdgeInsets.fromLTRB(2, 14, 2, 6),
                              child: Text(
                                '${t.toUpperCase()} · ${porTeam[t]!.length}',
                                style: const TextStyle(
                                  color: VenueColors.textoSuave,
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: .6,
                                ),
                              ),
                            ),
                            for (final g in porTeam[t]!)
                              ListTile(
                                dense: true,
                                contentPadding:
                                    const EdgeInsets.symmetric(horizontal: 4),
                                leading: CircleAvatar(
                                  backgroundColor: VenueColors.superficieAlta,
                                  child: Text(
                                    g.nombre.isEmpty
                                        ? '?'
                                        : g.nombre[0].toUpperCase(),
                                    style: const TextStyle(
                                        fontWeight: FontWeight.w800),
                                  ),
                                ),
                                title: Text(g.nombre,
                                    style: const TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.w600)),
                                subtitle: Text('@${g.usuario}'),
                                trailing: g.esJefe
                                    ? Text(
                                        'JEFE',
                                        style: TextStyle(
                                          color: Theme.of(context)
                                              .colorScheme
                                              .primary,
                                          fontWeight: FontWeight.w800,
                                          fontSize: 12,
                                        ),
                                      )
                                    : null,
                              ),
                          ],
                        ],
                      ),
                    ),
            ),
          ],
        );
      },
    );
  }
}
