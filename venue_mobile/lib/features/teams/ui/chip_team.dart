import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/venue_theme.dart';
import '../data/gente.dart';

/// Color de cada team, para distinguirlos de un vistazo. Lo elige el admin
/// al editar el team; si no eligió, sale uno fijo de la paleta según el id
/// (siempre el mismo para ese team). La misma paleta que la web.
const coloresTeam = [
  Color(0xFFE5484D), Color(0xFFF76B15), Color(0xFFE2A50E), Color(0xFF30A46C), Color(0xFF12A594),
  Color(0xFF0090FF), Color(0xFF3E63DD), Color(0xFF8E4EC6), Color(0xFFD6409F), Color(0xFF978365),
];

Color colorDeTeam(String id, [String? hex]) {
  if (hex != null && RegExp(r'^#[0-9A-Fa-f]{6}$').hasMatch(hex)) {
    return Color(int.parse('FF${hex.substring(1)}', radix: 16));
  }
  var h = 0;
  for (final c in id.codeUnits) {
    h = (h * 31 + c) & 0xFFFFFFFF;
  }
  return coloresTeam[h % coloresTeam.length];
}

/// '#RRGGBB' para guardar en la base.
String hexDe(Color c) =>
    '#${(c.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase()}';

/// Colores de los teams del boliche activo, por id.
final coloresTeamProvider = Provider.autoDispose<Map<String, Color>>((ref) {
  final teams = ref.watch(teamsInfoProvider).value ?? const <TeamInfo>[];
  return {for (final t in teams) t.id: colorDeTeam(t.id, t.color)};
});

/// El nombre del team en una pastilla de su color. Sin team: gris.
class ChipTeam extends ConsumerWidget {
  const ChipTeam({super.key, required this.teamId, required this.nombre});
  final String? teamId;
  final String nombre;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final id = teamId;
    final c = id == null || id.isEmpty
        ? VenueColors.textoTenue
        : ref.watch(coloresTeamProvider)[id] ?? colorDeTeam(id);
    final sin = id == null || id.isEmpty;
    final oscuro = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: c.withValues(alpha: .14),
        borderRadius: BorderRadius.circular(99),
        border: Border.all(color: c.withValues(alpha: .4)),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Container(width: 8, height: 8, decoration: BoxDecoration(color: c, shape: BoxShape.circle)),
        const SizedBox(width: 6),
        Flexible(
          child: Text(sin ? 'Sin team' : nombre,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: sin ? FontWeight.w500 : FontWeight.w600,
                color: sin ? VenueColors.textoSuave : Color.lerp(c, oscuro ? Colors.white : Colors.black, .18),
              )),
        ),
      ]),
    );
  }
}

/// Fila de colores para elegir el del team.
class SelectorColorTeam extends StatelessWidget {
  const SelectorColorTeam({super.key, required this.valor, required this.alCambiar});
  final Color valor;
  final ValueChanged<Color> alCambiar;

  @override
  Widget build(BuildContext context) => Wrap(spacing: 10, runSpacing: 10, children: [
        for (final c in coloresTeam)
          Semantics(
            button: true,
            selected: c.toARGB32() == valor.toARGB32(),
            label: 'Color ${hexDe(c)}',
            child: GestureDetector(
              onTap: () => alCambiar(c),
              child: Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: c,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: c.toARGB32() == valor.toARGB32()
                        ? Theme.of(context).colorScheme.onSurface
                        : Colors.transparent,
                    width: 3,
                  ),
                ),
              ),
            ),
          ),
      ]);
}
