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

/// El id de quien está logueado, o null para quien mira sin cuenta.
final usuarioIdProvider = Provider<String?>(
  (ref) => ref.watch(sesionProvider).value?.user.id,
);

/// La sesión es anónima: la que se crea sola al comprar sin cuenta. Sirve para
/// que la entrada tenga dueño y el QR aparezca en Accesos, pero se pierde con
/// el teléfono, así que PULSE, mesas, historias, reventa y rachas piden una
/// cuenta de verdad.
final esAnonimoProvider = Provider<bool>(
  (ref) => ref.watch(sesionProvider).value?.user.isAnonymous ?? false,
);

/// Hay cuenta de verdad: alguien entró con Google o Apple.
final conCuentaProvider = Provider<bool>(
  (ref) => ref.watch(usuarioIdProvider) != null && !ref.watch(esAnonimoProvider),
);

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

/// Mensaje apto para mostrarle a la persona.
String mensajeDeError(Object e) {
  if (esFallaDeRed(e)) return 'Sin conexión. Revisá la señal y probá de nuevo.';
  // la base todavía no tiene db/35-aftr.sql
  if (e is PostgrestException && e.code == 'PGRST202') return 'AFTR todavía no está activado en la base.';
  if (e is PostgrestException) return e.message;
  if (e is AuthException) return e.message;
  if (e is FormatException) return e.message;
  final t = e.toString();
  if (t.isNotEmpty && t.length < 180) return t;
  return 'Ocurrió un error inesperado.';
}
