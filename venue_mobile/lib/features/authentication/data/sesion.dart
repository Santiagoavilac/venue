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
    this.rol = '',
    this.puedeTickear = false,
    this.adminPrincipal = false,
    this.contabilidadTotal = false,
    this.fotoUrl,
  });

  final String id;
  final String usuario;
  final String nombre;
  final bool activo;

  /// Rol base de la cuenta (el de cada boliche lo da rol_en_club).
  final String rol;

  /// Relacionadores y jefes entran por "Relacionadores" y usan su espacio
  /// personal; el resto del personal entra por "Boliches".
  bool get esRelacionador => (rol == 'rrpp' || rol == 'jefe') && !adminPrincipal;

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
        rol: j['rol'] as String? ?? '',
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

/// La cuenta existe pero entra por la otra opción de la bienvenida.
class OtraPuerta implements Exception {
  const OtraPuerta({required this.esRelacionador});
  final bool esRelacionador;
  String get mensaje => esRelacionador
      ? 'Esta cuenta es de relacionador: entrá por Relacionadores.'
      : 'Esta cuenta es del personal de un boliche: entrá por Boliches.';
}

/// Vuelta de los enlaces de correo y de Google/Apple a la app.
const redireccionApp = 'venue://login-callback';

final authRepositoryProvider = Provider<AuthRepository>(
  (ref) => AuthRepository(ref.watch(supabaseProvider)),
);

class AuthRepository {
  AuthRepository(this._sb);
  final SupabaseClient _sb;

  static String emailDe(String usuario) =>
      '${usuario.trim().toLowerCase()}@${Env.dominioUsuarios}';

  /// Ingreso por "Boliches" (usuario + contraseña). Una cuenta
  /// desactivada o de relacionador no queda con sesión abierta.
  Future<void> ingresar(String usuario, String clave) async {
    // con usuario se arma el correo interno; quien cargó su correo entra con él
    final u = usuario.trim().toLowerCase();
    final r = await _sb.auth.signInWithPassword(
      email: u.contains('@') ? u : emailDe(u),
      password: clave,
    );
    await _revisar(r.user?.id, relacionador: false);
  }

  /// Ingreso por "Relacionadores": correo, o el usuario de siempre para
  /// los que ya trabajaban en VENUE.
  Future<void> ingresarRelacionador(String correoOUsuario, String clave) async {
    final t = correoOUsuario.trim().toLowerCase();
    final r = await _sb.auth.signInWithPassword(
      email: t.contains('@') ? t : emailDe(t),
      password: clave,
    );
    await _revisar(r.user?.id, relacionador: true);
  }

  Future<void> _revisar(String? uid, {required bool relacionador}) async {
    if (uid == null) return;
    final p = await _sb
        .from('profiles')
        .select('activo, rol, admin_principal')
        .eq('id', uid)
        .maybeSingle();
    // relacionador nuevo sin perfil: completa el nombre después
    if (p == null && relacionador) return;
    if (p == null || p['activo'] != true) {
      await _sb.auth.signOut();
      throw const CuentaDesactivada();
    }
    final esRel = (p['rol'] == 'rrpp' || p['rol'] == 'jefe') && p['admin_principal'] != true;
    if (esRel != relacionador) {
      await _sb.auth.signOut();
      throw OtraPuerta(esRelacionador: esRel);
    }
  }

  /// Cuenta nueva de relacionador. Devuelve true si ya quedó con sesión
  /// (false: tiene que confirmar el correo primero).
  Future<bool> crearCuenta({required String nombre, required String correo, required String clave}) async {
    final r = await _sb.auth.signUp(
      email: correo.trim().toLowerCase(),
      password: clave,
      emailRedirectTo: redireccionApp,
      data: {'nombre': nombre.trim()},
    );
    return r.session != null;
  }

  Future<void> recuperar(String correo) =>
      _sb.auth.resetPasswordForEmail(correo.trim().toLowerCase(), redirectTo: redireccionApp);

  /// Google o Apple: se abre el navegador y la sesión vuelve por el enlace
  /// venue://login-callback.
  Future<void> conProveedor(OAuthProvider p) =>
      _sb.auth.signInWithOAuth(p, redirectTo: redireccionApp);

  /// Crea el perfil de relacionador (sin boliches: no da acceso a nada).
  Future<void> completarCuenta(String nombre) =>
      _sb.rpc('rrpp_crear_cuenta', params: {'p_nombre': nombre.trim()});

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
