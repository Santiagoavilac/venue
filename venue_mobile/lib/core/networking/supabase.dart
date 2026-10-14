import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

final supabaseProvider = Provider<SupabaseClient>(
  (ref) => Supabase.instance.client,
);

/// Sesión actual; emite en cada login, logout o refresco de token.
final sesionProvider = StreamProvider<Session?>((ref) async* {
  final auth = ref.watch(supabaseProvider).auth;
  yield auth.currentSession;
  yield* auth.onAuthStateChange.map((e) => e.session);
});

/// ¿El error es de red (sin señal, timeout) y no una respuesta del servidor?
///
/// La distinción importa en la puerta: un rechazo del servidor es un "NO
/// PASA"; una falla de red es "SIN CONEXIÓN" y no dice nada sobre la entrada.
bool esFallaDeRed(Object e) {
  if (e is PostgrestException || e is AuthApiException) return false;
  if (e is SocketException || e is TimeoutException || e is HandshakeException) {
    return true;
  }
  if (e is AuthRetryableFetchException) return true;
  final s = e.toString().toLowerCase();
  return s.contains('socketexception') ||
      s.contains('clientexception') ||
      s.contains('failed host lookup') ||
      s.contains('connection closed') ||
      s.contains('network is unreachable');
}

/// Mensaje apto para mostrarle a un operador.
String mensajeDeError(Object e) {
  if (esFallaDeRed(e)) return 'Sin conexión. Revisá la señal y probá de nuevo.';
  if (e is PostgrestException) return e.message;
  if (e is AuthException) return e.message;
  if (e is StorageException) return 'No se pudo subir el archivo: ${e.message}';
  if (e is FormatException) return e.message;
  // Lo desconocido se muestra tal cual: "error inesperado" no le sirve a
  // nadie para resolverlo ni para reportarlo.
  final t = e.toString();
  if (t.isNotEmpty && t.length < 180) return t;
  return 'Ocurrió un error inesperado.';
}
