import 'dart:io';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'networking/supabase.dart';

/// Las notificaciones de Venue.
///
/// El permiso no se pide al abrir la app: se pide cuando ya hay trabajo que
/// seguir. Pedirlo en la primera pantalla es la forma más rápida de que te
/// lo nieguen para siempre, porque en iOS la negativa es definitiva y no se
/// vuelve a preguntar.
///
/// El token se guarda sólo si hay sesión. Si no, se guarda en cuanto entra:
/// el aparato queda atado a una cuenta, no al aire.
class Notificaciones {
  Notificaciones(this._sb);

  final SupabaseClient _sb;
  static const _app = 'venue';
  String? _ultimo;

  static bool _arrancado = false;

  /// Arranca Firebase una sola vez. Si falla -falta la configuración, el
  /// teléfono no tiene servicios de Google- la app sigue andando sin
  /// notificaciones, que es mejor que no abrir.
  static Future<void> arrancar() async {
    if (_arrancado) return;
    try {
      await Firebase.initializeApp();
      _arrancado = true;
    } catch (e) {
      debugPrint('Notificaciones: no arrancó Firebase ($e)');
    }
  }

  bool get listo => _arrancado;

  /// Si ya se decidió antes, no se vuelve a preguntar.
  Future<bool> yaDecidido() async {
    if (!_arrancado) return true;
    final s = await FirebaseMessaging.instance.getNotificationSettings();
    return s.authorizationStatus != AuthorizationStatus.notDetermined;
  }

  /// Pide el permiso y, si lo dan, registra el aparato.
  Future<bool> pedirPermiso() async {
    if (!_arrancado) return false;
    try {
      final r = await FirebaseMessaging.instance.requestPermission();
      final ok = r.authorizationStatus == AuthorizationStatus.authorized ||
          r.authorizationStatus == AuthorizationStatus.provisional;
      if (ok) await registrar();
      return ok;
    } catch (e) {
      debugPrint('Notificaciones: no se pudo pedir el permiso ($e)');
      return false;
    }
  }

  /// Guarda el token de este aparato, si hay permiso y hay sesión.
  Future<void> registrar() async {
    if (!_arrancado || _sb.auth.currentUser == null) return;
    try {
      final s = await FirebaseMessaging.instance.getNotificationSettings();
      if (s.authorizationStatus != AuthorizationStatus.authorized &&
          s.authorizationStatus != AuthorizationStatus.provisional) {
        return;
      }
      final token = await FirebaseMessaging.instance.getToken();
      if (token == null || token == _ultimo) return;
      await _sb.rpc('registrar_dispositivo', params: {
        'p_token': token,
        'p_app': _app,
        'p_plataforma': Platform.isIOS ? 'ios' : 'android',
      });
      _ultimo = token;
    } catch (e) {
      // que no se pueda registrar no rompe nada: se reintenta la próxima vez
      debugPrint('Notificaciones: no se pudo registrar el aparato ($e)');
    }
  }

  /// Firebase rota el token solo; hay que volver a guardarlo cuando pasa.
  void escucharCambios() {
    if (!_arrancado) return;
    FirebaseMessaging.instance.onTokenRefresh.listen((_) => registrar());
  }
}

final notificacionesProvider = Provider<Notificaciones>(
  (ref) => Notificaciones(ref.watch(supabaseProvider)),
);
