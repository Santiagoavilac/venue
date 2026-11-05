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
  Ingreso(
    this._sb, {
    this.googleIosClientId = Env.googleIosClientId,
    this.googleWebClientId = Env.googleWebClientId,
  });
  final SupabaseClient _sb;
  final String googleIosClientId;
  final String googleWebClientId;
  /// El nonce que quedó activo en el SDK de Google. Es por intento -eso es lo
  /// que ata el token a esta sesión y no a otra- y se guarda sólo porque, si el
  /// SDK se niega a reinicializarse, hay que firmar con el que ya tenía.
  static String? _googleNonceActivo;

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
    if (googleIosClientId.isEmpty) {
      throw const AuthException('El ingreso con Google todavía no está configurado.');
    }
    final g = GoogleSignIn.instance;
    // Un nonce por intento, como el de Apple. Antes era uno fijo por proceso:
    // todos los ingresos de una corrida compartían el mismo, así que el nonce
    // no distinguía un intento de otro.
    final crudo = _nonce();
    var usado = crudo;
    try {
      await g.initialize(
        clientId: googleIosClientId,
        serverClientId: googleWebClientId,
        nonce: sha256.convert(utf8.encode(crudo)).toString(),
      );
    } on Exception {
      // Si el SDK no acepta reinicializarse, se firma con el que ya tiene
      // puesto: mejor eso que no poder entrar. En el primer intento no hay
      // ninguno, y ahí el error sí es un error.
      if (_googleNonceActivo == null) rethrow;
      usado = _googleNonceActivo!;
    }
    _googleNonceActivo = usado;
    final GoogleSignInAccount cuenta;
    try {
      cuenta = await g.authenticate();
    } on GoogleSignInException catch (e) {
      if (e.code == GoogleSignInExceptionCode.canceled) throw IngresoCancelado();
      rethrow;
    }
    final token = cuenta.authentication.idToken;
    if (token == null) throw const AuthException('Google no devolvió el token.');
    await _sb.auth.signInWithIdToken(provider: OAuthProvider.google, idToken: token, nonce: usado);
  }

  /// El nombre que dio el proveedor, para proponerlo en el onboarding.
  String? nombreSugerido() {
    final m = _sb.auth.currentUser?.userMetadata ?? const {};
    final n = (m['full_name'] ?? m['name']) as String?;
    return (n == null || n.trim().isEmpty) ? null : n.trim();
  }

  Future<void> salir() async {
    try {
      if (_googleNonceActivo != null) await GoogleSignIn.instance.signOut();
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
