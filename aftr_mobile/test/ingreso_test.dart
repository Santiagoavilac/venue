import 'dart:convert';
import 'dart:io';

import 'package:aftr_mobile/features/auth/ingreso.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
// Reemplaza solo el puente nativo del SDK instalado.
import 'package:google_sign_in_platform_interface/google_sign_in_platform_interface.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class GoogleNativo extends GoogleSignInPlatform {
  InitParameters? parametros;
  int inicializaciones = 0;

  @override
  Future<void> init(InitParameters params) async {
    parametros = params;
    inicializaciones++;
  }

  @override
  Future<AuthenticationResults> authenticate(AuthenticateParameters params) async =>
      AuthenticationResults(
        user: const GoogleSignInUserData(email: 'demo@example.invalid', id: 'demo'),
        authenticationTokens: AuthenticationTokenData(
          idToken: 'cabecera.${base64Url.encode(utf8.encode(jsonEncode({'nonce': parametros!.nonce})))}.firma',
        ),
      );

  @override
  Stream<AuthenticationEvent>? get authenticationEvents => null;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  test('Google envía hash al SDK y nonce original a Supabase, también al reintentar', () async {
    final google = GoogleNativo();
    GoogleSignInPlatform.instance = google;
    final servidor = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final peticiones = <Map<String, dynamic>>[];
    servidor.listen((req) async {
      peticiones.add(jsonDecode(await utf8.decoder.bind(req).join()) as Map<String, dynamic>);
      req.response.statusCode = 400;
      req.response.headers.contentType = ContentType.json;
      req.response.write(jsonEncode({'msg': 'Servidor simulado, sin sesión real'}));
      await req.response.close();
    });
    final sb = SupabaseClient(
      'http://127.0.0.1:${servidor.port}', 'clave-de-prueba',
      authOptions: const AuthClientOptions(autoRefreshToken: false),
    );
    addTearDown(() async {
      await sb.dispose();
      await servidor.close(force: true);
    });

    // Una nueva instancia del repositorio no debe reinicializar el SDK nativo.
    for (var i = 0; i < 2; i++) {
      await expectLater(Ingreso(sb, googleIosClientId: 'ios-cliente-de-prueba', googleWebClientId: 'web-cliente-de-prueba').conGoogle(), throwsA(isA<AuthException>()));
    }
    expect(google.inicializaciones, 1);
    expect(peticiones, hasLength(2));
    for (final cuerpo in peticiones) {
      expect(cuerpo['provider'], 'google');
      final nonce = cuerpo['nonce'] as String;
      expect(nonce.length, greaterThanOrEqualTo(32));
      final token = cuerpo['id_token'] as String;
      final claims = jsonDecode(utf8.decode(base64Url.decode(base64Url.normalize(token.split('.')[1]))));
      expect(claims['nonce'], sha256.convert(utf8.encode(nonce)).toString());
    }
  });
}
