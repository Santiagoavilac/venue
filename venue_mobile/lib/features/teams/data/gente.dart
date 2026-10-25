import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/networking/supabase.dart';
import '../../authentication/data/sesion.dart';
import '../../clubs/data/clubs.dart';

const rolesAsignables = [
  'rrpp', 'jefe', 'portero', 'caja', 'propietario', 'barra', 'deposito', 'admin',
];

class Usuario {
  const Usuario({
    required this.id, required this.usuario, required this.nombre, required this.rol,
    required this.activo, this.teamId, this.clubs = const [], this.adminPrincipal = false,
    this.puedeTickear = false,
  });
  final String id;
  final String usuario;
  final String nombre;

  /// Rol BASE. El rol en cada boliche puede diferir (ver [Membresia]).
  final String rol;
  final bool activo;
  final String? teamId;
  final List<String> clubs;
  final bool adminPrincipal;
  final bool puedeTickear;

  String get rolEtiqueta => Rol.desde(rol)?.etiqueta ?? rol;

  factory Usuario.desde(Map<String, dynamic> j) => Usuario(
        id: j['id'] as String,
        usuario: j['usuario'] as String? ?? '',
        nombre: j['nombre'] as String? ?? '',
        rol: j['rol'] as String? ?? '',
        activo: j['activo'] == true,
        teamId: j['team_id'] as String?,
        clubs: ((j['clubs'] as List?) ?? const []).cast<String>(),
        adminPrincipal: j['admin_principal'] == true,
        puedeTickear: j['puede_tickear'] == true,
      );
}

/// Rol y team de una persona en UN boliche (cuando opera en más de uno).
class Membresia {
  const Membresia({required this.clubId, required this.rol, this.teamId});
  final String clubId;
  final String rol;
  final String? teamId;
}

class TeamInfo {
  const TeamInfo({
    required this.id, required this.nombre, required this.clubs, required this.invitacion,
    this.jefeId, this.activo = true,
  });
  final String id;
  final String nombre;
  final List<String> clubs;
  final String invitacion;
  final String? jefeId;
  final bool activo;

  /// Link que abre el registro en la app con la invitación ya cargada.
  String get link => 'venue://app/registro?invite=$invitacion';

  factory TeamInfo.desde(Map<String, dynamic> j) => TeamInfo(
        id: j['id'] as String,
        nombre: j['nombre'] as String? ?? '',
        clubs: ((j['clubs'] as List?) ?? const []).cast<String>(),
        invitacion: j['invite_code'] as String? ?? '',
        jefeId: j['jefe_id'] as String?,
        activo: j['activo'] != false,
      );
}

/// Texto para mandarle a quien se quiere sumar al team.
String mensajeDeInvitacion(TeamInfo t, String boliche) =>
    'Sumate a ${t.nombre} en $boliche con Venue.\n'
    'Abrí este link desde tu teléfono: ${t.link}\n'
    'Si no abre, entrá a la app → "Tengo un link de invitación" y pegá este código: ${t.invitacion}';

/// Slug de boliche válido (mismo formato que exige la base).
bool slugValido(String s) => RegExp(r'^[a-z0-9][a-z0-9-]{1,29}$').hasMatch(s);
bool colorValido(String s) => RegExp(r'^#[0-9A-Fa-f]{6}$').hasMatch(s);

class RechazoDelServidor implements Exception {
  const RechazoDelServidor(this.motivo);
  final String motivo;
  @override
  String toString() => motivo;
}

final genteRepositoryProvider =
    Provider<GenteRepository>((ref) => GenteRepository(ref.watch(supabaseProvider)));

class GenteRepository {
  GenteRepository(this._sb);
  final SupabaseClient _sb;

  static const _cols =
      'id, usuario, nombre, rol, activo, team_id, clubs, admin_principal, puede_tickear';

  /// Personas del boliche (sin las eliminadas). RLS ya recorta a la gente
  /// con la que se comparte boliche.
  Future<List<Usuario>> usuarios(String clubId) async {
    final r = await _sb.from('profiles').select(_cols)
        .filter('eliminado_at', 'is', null).contains('clubs', [clubId]).order('nombre', ascending: true);
    return r.map(Usuario.desde).toList();
  }

  Future<List<TeamInfo>> teams(String clubId) async {
    final r = await _sb.from('teams')
        .select('id, nombre, clubs, invite_code, jefe_id, activo')
        .contains('clubs', [clubId]).order('nombre', ascending: true);
    return r.map(TeamInfo.desde).toList();
  }

  Future<TeamInfo?> team(String id) async {
    final r = await _sb.from('teams')
        .select('id, nombre, clubs, invite_code, jefe_id, activo').eq('id', id).maybeSingle();
    return r == null ? null : TeamInfo.desde(r);
  }

  /// Relacionadores del team de la persona en ese boliche.
  Future<List<Usuario>> miTeam(String clubId) async {
    final r = await _sb.rpc('roster_mi_team', params: {'p_club': clubId});
    return (r as List? ?? const [])
        .map((x) => Usuario.desde({...Map<String, dynamic>.from(x as Map), 'rol': 'rrpp'}))
        .toList();
  }

  Future<List<Membresia>> membresias(String usuarioId) async {
    final r = await _sb.from('club_membership')
        .select('club_id, rol, team_id').eq('user_id', usuarioId);
    return [
      for (final x in r)
        Membresia(clubId: x['club_id'] as String, rol: x['rol'] as String, teamId: x['team_id'] as String?),
    ];
  }

  Future<Map<String, dynamic>> _funcion(Map<String, dynamic> cuerpo) async {
    try {
      final r = await _sb.functions.invoke('crear-usuario', body: cuerpo);
      return Map<String, dynamic>.from(r.data as Map? ?? const {});
    } on FunctionException catch (e) {
      final d = e.details;
      throw RechazoDelServidor(
          d is Map && d['error'] is String ? d['error'] as String : 'No se pudo completar.');
    }
  }

  /// Alta de una cuenta. El jefe solo crea relacionadores de su team (lo
  /// fuerza el servidor); crear administradores es de la plataforma.
  /// Devuelve el usuario creado, ya en minúsculas.
  Future<String> crear({
    required String usuario, required String nombre, required String clave,
    String rol = 'rrpp', String? teamId, List<String>? clubs,
  }) async {
    final r = await _funcion({
      'usuario': usuario, 'nombre': nombre, 'clave': clave, 'rol': rol, 'team_id': teamId,
    });
    final u = r['usuario'] as String? ?? usuario.trim().toLowerCase();
    // sin team la cuenta nace sin boliche: se le asignan los elegidos
    if (clubs != null && clubs.isNotEmpty) {
      await _sb.from('profiles').update({'clubs': clubs}).eq('usuario', u);
    }
    return u;
  }

  Future<void> resetearClave(String usuarioId, String clave) =>
      _funcion({'action': 'reset', 'user_id': usuarioId, 'clave': clave});

  Future<void> activar(String usuarioId, bool activo) =>
      _sb.from('profiles').update({'activo': activo}).eq('id', usuarioId);

  /// Edita datos, rol, team y boliches. Si opera en 2 o más boliches y no es
  /// admin, se guarda el rol/team de CADA boliche; si no, se limpian.
  Future<void> editar(
    String usuarioId, {
    required String nombre, required String rol, String? teamId,
    required List<String> clubs, List<Membresia> porBoliche = const [],
  }) async {
    await _sb.from('profiles').update({
      'nombre': nombre, 'rol': rol, 'team_id': teamId, 'clubs': clubs,
    }).eq('id', usuarioId);
    if (clubs.length >= 2 && rol != 'admin') {
      await _sb.from('club_membership').upsert([
        for (final c in clubs)
          {
            'user_id': usuarioId, 'club_id': c,
            'rol': porBoliche.where((m) => m.clubId == c).firstOrNull?.rol ?? rol,
            'team_id': porBoliche.where((m) => m.clubId == c).firstOrNull?.teamId ?? teamId,
          },
      ]);
    } else {
      await _sb.from('club_membership').delete().eq('user_id', usuarioId);
    }
  }

  /// Devuelve 'archivado' (tenía actividad: se conserva su historia) o
  /// 'eliminado'.
  Future<String> eliminar(String usuarioId) async {
    final r = await _sb.rpc('eliminar_usuario', params: {'p_user': usuarioId});
    return (r as Map?)?['modo'] as String? ?? 'eliminado';
  }

  Future<void> crearTeam(String nombre, String clubId) =>
      _sb.from('teams').insert({'nombre': nombre, 'clubs': [clubId], 'activo': true});

  Future<void> editarTeam(String id, String nombre, List<String> clubs) =>
      _sb.from('teams').update({'nombre': nombre, 'clubs': clubs}).eq('id', id);

  /// Elimina el team. Su gente pasa a [destino] o queda sin team.
  Future<int> eliminarTeam(String id, {String? destino}) async {
    final r = await _sb.rpc('eliminar_team', params: {'p_team': id, 'p_destino': destino});
    return ((r as Map?)?['movidos'] as num?)?.toInt() ?? 0;
  }

  // ── boliches (plataforma) ──
  /// Crea el boliche con cómo trabaja ([opciones]). Si la base todavía no
  /// tiene db/33, se crea igual con la configuración de siempre y devuelve
  /// false para avisar.
  Future<bool> crearClub({
    required String id, required String nombre, String? subtitulo,
    required String primario, required String secundario, required String acento,
    Map<String, bool> opciones = const {},
  }) async {
    final fila = {
      'id': id, 'nombre': nombre, 'subtitulo': subtitulo, 'color_primario': primario,
      'color_secundario': secundario, 'color_accent': acento,
      'inicial': nombre.isEmpty ? null : nombre[0].toUpperCase(),
    };
    try {
      await _sb.from('clubs').insert({...fila, ...opciones});
      return true;
    } on PostgrestException catch (e) {
      if (e.code != '42703' && e.code != 'PGRST204') rethrow;
      await _sb.from('clubs').insert(fila);
      return false;
    }
  }

  /// Cómo trabaja el boliche con relacionadores y comisiones (db/33).
  Future<void> fijarOpciones(String clubId, Map<String, bool> opciones) =>
      _sb.from('clubs').update(opciones).eq('id', clubId);

  /// Lo que el jefe le da a cada relacionador por manilla y por combo
  /// (null = la regla de siempre). Tira si la base no tiene db/33.
  Future<({num? porManilla, num? porCombo})> reparto(String teamId) async {
    final r = await _sb.from('teams').select('rrpp_por_manilla, rrpp_por_combo').eq('id', teamId).single();
    return (porManilla: r['rrpp_por_manilla'] as num?, porCombo: r['rrpp_por_combo'] as num?);
  }

  Future<void> fijarReparto(String teamId, {num? porManilla, num? porCombo}) =>
      _sb.rpc('fijar_reparto_team',
          params: {'p_team': teamId, 'p_por_manilla': porManilla, 'p_por_combo': porCombo});

  Future<void> editarClub(String id, {
    required String nombre, String? subtitulo, required String primario,
    required String secundario, required String acento,
  }) =>
      _sb.from('clubs').update({
        'nombre': nombre, 'subtitulo': subtitulo, 'color_primario': primario,
        'color_secundario': secundario, 'color_accent': acento,
        'inicial': nombre.isEmpty ? null : nombre[0].toUpperCase(),
      }).eq('id', id);

  /// Colores de la app para este boliche (los demás datos no se tocan).
  Future<void> fijarColores(String clubId, {required String primario, required String secundario}) =>
      _sb.from('clubs').update({'color_primario': primario, 'color_secundario': secundario}).eq('id', clubId);

  /// Guarda (o con null, quita) el logo del boliche.
  Future<void> fijarLogo(String clubId, String? url) =>
      _sb.from('clubs').update({'logo_url': url}).eq('id', clubId);

  /// Dónde queda el boliche (db/35). Con esto aparece en el mapa de AFTR.
  Future<void> fijarUbicacion(String clubId,
          {required double lat, required double lng, String? direccion, String? zona, String? ciudad}) =>
      _sb.from('clubs').update({
        'lat': lat, 'lng': lng, 'direccion': direccion, 'zona': zona, 'ciudad': ciudad,
      }).eq('id', clubId);

  Future<void> desactivarClub(String id) =>
      _sb.from('clubs').update({'activo': false}).eq('id', id);

  Future<bool> soyDePlataforma() async => await _sb.rpc('es_platform_admin') == true;
}

final usuariosProvider = FutureProvider.autoDispose<List<Usuario>>((ref) async {
  final club = ref.watch(clubActivoIdProvider);
  if (club == null) return const [];
  return ref.watch(genteRepositoryProvider).usuarios(club);
});

final teamsInfoProvider = FutureProvider.autoDispose<List<TeamInfo>>((ref) async {
  final club = ref.watch(clubActivoIdProvider);
  if (club == null) return const [];
  return ref.watch(genteRepositoryProvider).teams(club);
});

final miTeamProvider = FutureProvider.autoDispose<List<Usuario>>((ref) async {
  final club = ref.watch(clubActivoIdProvider);
  if (club == null) return const [];
  return ref.watch(genteRepositoryProvider).miTeam(club);
});

final plataformaProvider = FutureProvider<bool>((ref) {
  ref.watch(usuarioIdProvider); // se recalcula al cambiar de cuenta
  return ref.watch(genteRepositoryProvider).soyDePlataforma();
});
