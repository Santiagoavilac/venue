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
  });

  final String id;
  final String usuario;
  final String nombre;
  final bool activo;

  String get inicial => nombre.isEmpty ? '?' : nombre[0].toUpperCase();
  String get primerNombre => nombre.split(' ').first;

  factory Perfil.desde(Map<String, dynamic> j) => Perfil(
        id: j['id'] as String,
        usuario: j['usuario'] as String? ?? '',
        nombre: j['nombre'] as String? ?? '',
        activo: j['activo'] as bool? ?? false,
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
      .select('id, usuario, nombre, activo')
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
}
