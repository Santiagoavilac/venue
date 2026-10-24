import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/config/env.dart';
import '../../../core/networking/supabase.dart';

class Perfil {
  const Perfil({
    required this.id,
    required this.usuario,
    required this.nombre,
    required this.activo,
    this.puedeTickear = false,
    this.adminPrincipal = false,
    this.contabilidadTotal = false,
    this.fotoUrl,
  });

  final String id;
  final String usuario;
  final String nombre;
  final bool activo;

  /// Puede marcar ingresos a mano desde Listas.
  final bool puedeTickear;

  /// Cuenta principal de la plataforma (ve Historial, crea boliches).
  final bool adminPrincipal;

  /// Puede exportar la contabilidad general del evento.
  final bool contabilidadTotal;

  /// Foto de perfil (db/34). null = se ve la inicial.
  final String? fotoUrl;

  String get inicial => nombre.isEmpty ? '?' : nombre[0].toUpperCase();
  String get primerNombre => nombre.split(' ').first;

  factory Perfil.desde(Map<String, dynamic> j) => Perfil(
        id: j['id'] as String,
        usuario: j['usuario'] as String? ?? '',
        nombre: j['nombre'] as String? ?? '',
        activo: j['activo'] as bool? ?? false,
        puedeTickear: j['puede_tickear'] as bool? ?? false,
        adminPrincipal: j['admin_principal'] as bool? ?? false,
        contabilidadTotal: j['contabilidad_total'] as bool? ?? false,
        fotoUrl: j['foto_url'] as String?,
      );
}

/// Id del usuario con sesión, o null. Los providers de datos dependen de
/// esto: al cambiar de cuenta se recalculan y no queda nada de la anterior.
final usuarioIdProvider = Provider<String?>(
  (ref) => ref.watch(sesionProvider).value?.user.id,
);

final perfilProvider = FutureProvider<Perfil?>((ref) async {
  final uid = ref.watch(usuarioIdProvider);
  if (uid == null) return null;
  final fila = await ref
      .watch(supabaseProvider)
      .from('profiles')
      .select() // todas: foto_url llega con db/34 y así no rompe sin ella
      .eq('id', uid)
      .maybeSingle();
  return fila == null ? null : Perfil.desde(fila);
});

class CuentaDesactivada implements Exception {
  const CuentaDesactivada();
}

final authRepositoryProvider = Provider<AuthRepository>(
  (ref) => AuthRepository(ref.watch(supabaseProvider)),
);

class AuthRepository {
  AuthRepository(this._sb);
  final SupabaseClient _sb;

  static String emailDe(String usuario) =>
      '${usuario.trim().toLowerCase()}@${Env.dominioUsuarios}';

  /// Inicia sesión. Una cuenta desactivada no queda con sesión abierta.
  Future<void> ingresar(String usuario, String clave) async {
    final r = await _sb.auth.signInWithPassword(
      email: emailDe(usuario),
      password: clave,
    );
    final uid = r.user?.id;
    if (uid == null) return;
    final p = await _sb
        .from('profiles')
        .select('activo')
        .eq('id', uid)
        .maybeSingle();
    if (p == null || p['activo'] != true) {
      await _sb.auth.signOut();
      throw const CuentaDesactivada();
    }
  }

  Future<void> salir() => _sb.auth.signOut();

  /// Alta de relacionador con el link de invitación de un team. La cuenta la
  /// crea la Edge Function `crear-usuario` (valida la invitación y limita
  /// los intentos); después se inicia sesión normalmente.
  /// Devuelve el nombre del team.
  Future<String> registrarse({
    required String invitacion,
    required String nombre,
    required String usuario,
    required String clave,
  }) async {
    final u = usuario.trim().toLowerCase().replaceAll(RegExp(r'\s'), '');
    try {
      final r = await _sb.functions.invoke('crear-usuario', body: {
        'action': 'registro',
        'invite': codigoDeInvitacion(invitacion),
        'nombre': nombre.trim(),
        'usuario': u,
        'clave': clave,
      });
      await ingresar(u, clave);
      return (r.data as Map?)?['team'] as String? ?? '';
    } on FunctionException catch (e) {
      final d = e.details;
      throw RegistroRechazado(
          d is Map && d['error'] is String ? d['error'] as String : 'No se pudo registrar.');
    }
  }
}

class RegistroRechazado implements Exception {
  const RegistroRechazado(this.motivo);
  final String motivo;
}

/// Acepta el link completo (`…?invite=abc`) o el código solo.
String codigoDeInvitacion(String texto) {
  final t = texto.trim();
  final m = RegExp(r'[?&]invite=([A-Za-z0-9]+)').firstMatch(t);
  return (m?.group(1) ?? t).toLowerCase();
}
