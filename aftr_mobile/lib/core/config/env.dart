/// Configuración del backend (el mismo proyecto de Supabase que Venue). Los
/// valores llegan con `--dart-define-from-file=env/dev.json`; nunca se
/// escriben en el código.
///
/// La URL y la anon key son públicas por diseño: lo que protege los datos son
/// las RPC aftr_* y RLS en el servidor.
class Env {
  static const supabaseUrl = String.fromEnvironment('SUPABASE_URL');
  static const supabaseAnonKey = String.fromEnvironment('SUPABASE_ANON_KEY');

  /// IDs de cliente OAuth de Google (iOS y web). Sin ellos el botón de Google
  /// avisa que falta configurarlo en vez de fallar.
  static const googleIosClientId = String.fromEnvironment('GOOGLE_IOS_CLIENT_ID');
  static const googleWebClientId = String.fromEnvironment('GOOGLE_WEB_CLIENT_ID');

  static bool get configurado =>
      supabaseUrl.isNotEmpty && supabaseAnonKey.isNotEmpty;
}
