import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Guarda la sesión de Supabase en el llavero del sistema (Keychain en iOS,
/// Keystore en Android) en lugar de las preferencias de la app, que no están
/// cifradas. El token de refresco permite seguir logueado: no puede quedar
/// legible en un respaldo del teléfono.
class LlaveroStorage extends LocalStorage {
  LlaveroStorage();

  static const _clave = 'venue.sesion';
  static const _llavero = FlutterSecureStorage(
    iOptions: IOSOptions(accessibility: KeychainAccessibility.first_unlock_this_device),
  );

  @override
  Future<void> initialize() async {}

  @override
  Future<String?> accessToken() => _llavero.read(key: _clave);

  @override
  Future<bool> hasAccessToken() => _llavero.containsKey(key: _clave);

  @override
  Future<void> persistSession(String persistSessionString) =>
      _llavero.write(key: _clave, value: persistSessionString);

  @override
  Future<void> removePersistedSession() => _llavero.delete(key: _clave);
}
