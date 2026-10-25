import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/config/env.dart';
import '../../core/networking/supabase.dart';

/// La persona cerró la hoja de Apple o Google: no es un error que mostrar.
class IngresoCancelado implements Exception {}

/// Ingreso con Apple o Google: el token del proveedor se cambia por una
/// sesión de Supabase (signInWithIdToken). No hay contraseñas en AFTR.
class Ingreso {
  Ingreso(this._sb);
  final SupabaseClient _sb;
  bool _googleListo = false;

  static String _nonce([int largo = 32]) {
    const c = '0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._';
    final r = Random.secure();
    return List.generate(largo, (_) => c[r.nextInt(c.length)]).join();
  }

  Future<void> conApple() async {
    final crudo = _nonce();
    final AuthorizationCredentialAppleID cred;
    try {
      cred = await SignInWithApple.getAppleIDCredential(
        scopes: [AppleIDAuthorizationScopes.fullName],
        nonce: sha256.convert(utf8.encode(crudo)).toString(),
      );
    } on SignInWithAppleAuthorizationException catch (e) {
      if (e.code == AuthorizationErrorCode.canceled) throw IngresoCancelado();
      rethrow;
    }
    final token = cred.identityToken;
    if (token == null) throw const AuthException('Apple no devolvió el token.');
    await _sb.auth.signInWithIdToken(provider: OAuthProvider.apple, idToken: token, nonce: crudo);
    // Apple da el nombre solo la primera vez: se guarda para el onboarding
    final nombre = [cred.givenName, cred.familyName].whereType<String>().join(' ').trim();
    if (nombre.isNotEmpty) {
      await _sb.auth.updateUser(UserAttributes(data: {'full_name': nombre}));
    }
  }

  Future<void> conGoogle() async {
    if (Env.googleIosClientId.isEmpty) {
      throw const AuthException('El ingreso con Google todavía no está configurado.');
    }
    final g = GoogleSignIn.instance;
    if (!_googleListo) {
      await g.initialize(clientId: Env.googleIosClientId, serverClientId: Env.googleWebClientId);
      _googleListo = true;
    }
    final GoogleSignInAccount cuenta;
    try {
      cuenta = await g.authenticate();
    } on GoogleSignInException catch (e) {
      if (e.code == GoogleSignInExceptionCode.canceled) throw IngresoCancelado();
      rethrow;
    }
    final token = cuenta.authentication.idToken;
    if (token == null) throw const AuthException('Google no devolvió el token.');
    await _sb.auth.signInWithIdToken(provider: OAuthProvider.google, idToken: token);
  }

  /// El nombre que dio el proveedor, para proponerlo en el onboarding.
  String? nombreSugerido() {
    final m = _sb.auth.currentUser?.userMetadata ?? const {};
    final n = (m['full_name'] ?? m['name']) as String?;
    return (n == null || n.trim().isEmpty) ? null : n.trim();
  }

  Future<void> salir() async {
    try {
      if (_googleListo) await GoogleSignIn.instance.signOut();
    } catch (_) {}
    await _sb.auth.signOut();
  }
}

final ingresoProvider = Provider<Ingreso>((ref) => Ingreso(ref.watch(supabaseProvider)));

/// Propuesta de @usuario a partir del nombre: "Ana María" -> "anamaria".
String usuarioDesde(String nombre) {
  const de = 'áéíóúüñ';
  const a = 'aeiouun';
  var s = nombre.toLowerCase();
  for (var i = 0; i < de.length; i++) {
    s = s.replaceAll(de[i], a[i]);
  }
  s = s.replaceAll(RegExp(r'[^a-z0-9_.]'), '');
  return s.length > 24 ? s.substring(0, 24) : s;
}

final usuarioValido = RegExp(r'^[a-z0-9_.]{3,24}$');
