import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/networking/supabase.dart';
import '../../clubs/data/clubs.dart';
import '../../events/data/eventos.dart';

/// Una persona del boliche con su team EFECTIVO en ese boliche.
class Miembro {
  const Miembro({
    required this.id,
    required this.nombre,
    required this.rol,
    required this.team,
    this.teamId,
  });
  final String id;
  final String nombre;
  final String rol;
  final String team;
  final String? teamId;

  factory Miembro.desde(Map<String, dynamic> j) => Miembro(
        id: (j['user_id'] ?? j['id']) as String,
        nombre: j['nombre'] as String? ?? '',
        rol: j['rol'] as String? ?? '',
        team: j['team'] as String? ?? 'Sin team',
        teamId: j['team_id'] as String?,
      );
}

/// Equipo del boliche activo, indexado por usuario (`teams_efectivos`).
final equipoProvider = FutureProvider<Map<String, Miembro>>((ref) async {
  final club = ref.watch(clubActivoIdProvider);
  if (club == null) return const {};
  final r = await ref
      .watch(supabaseProvider)
      .rpc('teams_efectivos', params: {'p_club': club});
  return {
    for (final x in (r as List? ?? const []))
      (x['user_id'] as String): Miembro.desde(Map<String, dynamic>.from(x as Map)),
  };
});

/// Permisos de la persona en el evento: cortesías y cargar "a nombre de".
final permisosEventoProvider =
    FutureProvider.autoDispose<({bool cortesia, bool aNombreDe})>((ref) async {
  final ev = ref.watch(eventoActivoProvider);
  if (ev == null) return (cortesia: false, aNombreDe: false);
  final r = Map<String, dynamic>.from(await ref
      .watch(supabaseProvider)
      .rpc('mis_permisos_mesa', params: {'p_evento': ev.id}) as Map? ?? const {});
  return (cortesia: r['cortesia'] == true, aNombreDe: r['a_nombre_de'] == true);
});

/// A nombre de quién se puede cargar una venta o un invitado.
final vendedoresProvider = FutureProvider.autoDispose<List<Miembro>>((ref) async {
  final ev = ref.watch(eventoActivoProvider);
  if (ev == null) return const [];
  final r = await ref
      .watch(supabaseProvider)
      .rpc('vendedores_posibles', params: {'p_evento': ev.id});
  return (r as List? ?? const [])
      .map((x) => Miembro.desde(Map<String, dynamic>.from(x as Map)))
      .toList();
});

/// Usuarios cuyas entradas son "de la casa" (sin tope de horario): sus
/// tickets llevan marco dorado para que la puerta las reconozca.
final sinTopeProvider = FutureProvider<Set<String>>((ref) async {
  final club = ref.watch(clubActivoIdProvider);
  if (club == null) return const {};
  final r = await ref
      .watch(supabaseProvider)
      .rpc('usuarios_sin_tope', params: {'p_club': club});
  return {for (final x in (r as List? ?? const [])) x.toString()};
});

/// Trae todas las filas de una consulta paginando de a 1000: PostgREST corta
/// en 1000 sin avisar y cualquier contador sobre el resultado mentiría.
Future<List<Map<String, dynamic>>> traerTodo(
  Future<List<Map<String, dynamic>>> Function(int desde, int hasta) pagina, {
  int tamano = 1000,
  int techo = 20000,
}) async {
  final filas = <Map<String, dynamic>>[];
  for (var d = 0; d < techo; d += tamano) {
    final p = await pagina(d, d + tamano - 1);
    filas.addAll(p);
    if (p.length < tamano) break;
  }
  return filas;
}
