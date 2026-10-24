import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show PostgrestException;

import '../../../core/networking/supabase.dart';
import '../../../core/theme/venue_theme.dart';
import '../../authentication/data/sesion.dart';

class Club {
  const Club({
    required this.id,
    required this.nombre,
    this.subtitulo,
    this.inicialTexto,
    this.primario,
    this.secundario,
    this.logoUrl,
    this.usaRelacionadores = true,
    this.usaTeams = true,
    this.comisionManillas = true,
    this.comisionCombos = true,
  });

  final String id;
  final String nombre;
  final String? subtitulo;
  final String? inicialTexto;
  final Color? primario;
  final Color? secundario;

  /// Logo cargado por el admin (null: se muestra la inicial).
  final String? logoUrl;

  /// Cómo trabaja con relacionadores (db/33). Sin tocar: como siempre.
  final bool usaRelacionadores, usaTeams, comisionManillas, comisionCombos;

  /// Opciones que cambia el admin, como las guarda la base.
  static const opciones = ['usa_relacionadores', 'usa_teams', 'comision_manillas', 'comision_combos'];

  String get inicial {
    final t = (inicialTexto?.isNotEmpty ?? false) ? inicialTexto! : nombre;
    return t.isEmpty ? '?' : t[0].toUpperCase();
  }

  factory Club.desde(Map<String, dynamic> j) => Club(
        id: j['id'] as String,
        nombre: j['nombre'] as String? ?? j['id'] as String,
        subtitulo: j['subtitulo'] as String?,
        inicialTexto: j['inicial'] as String?,
        primario: colorDesdeHex(j['color_primario'] as String?),
        secundario: colorDesdeHex(j['color_secundario'] as String?),
        logoUrl: j['logo_url'] as String?,
        usaRelacionadores: j['usa_relacionadores'] as bool? ?? true,
        usaTeams: j['usa_teams'] as bool? ?? true,
        comisionManillas: j['comision_manillas'] as bool? ?? true,
        comisionCombos: j['comision_combos'] as bool? ?? true,
      );
}

/// Rol EFECTIVO en un boliche. Lo resuelve el servidor (`rol_en_club`); la
/// app solo lo usa para decidir qué pantallas mostrar. Cada operación vuelve
/// a comprobarse en el servidor.
enum Rol {
  admin('Administrador'),
  jefe('Jefe de team'),
  rrpp('Relacionador'),
  portero('Seguridad'),
  caja('Caja'),
  propietario('Propietario'),
  barra('Barra'),
  deposito('Recepción');

  const Rol(this.etiqueta);
  final String etiqueta;

  static Rol? desde(String? s) {
    for (final r in values) {
      if (r.name == s) return r;
    }
    return null;
  }

  bool get validaIngresos => this == admin || this == portero;
  bool get veEventos => const {admin, jefe, rrpp, portero}.contains(this);
  bool get vende => const {admin, jefe, rrpp}.contains(this);
}

/// Boliches donde la persona tiene algún rol (`mis_clubs` en el servidor).
final clubsProvider = FutureProvider<List<Club>>((ref) async {
  if (ref.watch(usuarioIdProvider) == null) return const [];
  final sb = ref.watch(supabaseProvider);
  final ids = ((await sb.rpc('mis_clubs')) as List).cast<String>();
  if (ids.isEmpty) return const [];
  Future<List<Map<String, dynamic>>> traer(String cols) => sb
      .from('clubs')
      .select(cols)
      .inFilter('id', ids)
      .eq('activo', true)
      .order('nombre', ascending: true);
  const cols = 'id, nombre, subtitulo, inicial, color_primario, color_secundario';
  // la base puede no tener todavía db/33 (opciones) ni db/32 (logo): se pide
  // lo más completo y se va soltando lo que falte
  for (final extra in ['logo_url, ${Club.opciones.join(', ')}', 'logo_url', '']) {
    try {
      return (await traer(extra.isEmpty ? cols : '$cols, $extra')).map(Club.desde).toList();
    } on PostgrestException catch (e) {
      if (e.code != '42703' || extra.isEmpty) rethrow;
    }
  }
  return const [];
});

/// Boliche en el que se está trabajando. Se reinicia al cambiar de cuenta.
class ClubActivo extends Notifier<String?> {
  @override
  String? build() {
    ref.watch(usuarioIdProvider);
    return null;
  }

  void elegir(String? id) => state = id;
}

final clubActivoIdProvider =
    NotifierProvider<ClubActivo, String?>(ClubActivo.new);

final clubActivoProvider = Provider<Club?>((ref) {
  final id = ref.watch(clubActivoIdProvider);
  final lista = ref.watch(clubsProvider).value ?? const <Club>[];
  for (final c in lista) {
    if (c.id == id) return c;
  }
  return null;
});

final rolProvider = FutureProvider<Rol?>((ref) async {
  final club = ref.watch(clubActivoIdProvider);
  if (club == null || ref.watch(usuarioIdProvider) == null) return null;
  final r = await ref
      .watch(supabaseProvider)
      .rpc('rol_en_club', params: {'p_club': club});
  return Rol.desde(r as String?);
});
