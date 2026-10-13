/// Configuración del backend. Los valores llegan en tiempo de compilación con
/// `--dart-define-from-file=env/dev.json`; nunca se escriben en el código.
///
/// Solo van la URL y la anon key, que son públicas por diseño: lo que protege
/// los datos son las guardas de las RPC y RLS en el servidor.
class Env {
  static const supabaseUrl = String.fromEnvironment('SUPABASE_URL');
  static const supabaseAnonKey = String.fromEnvironment('SUPABASE_ANON_KEY');

  static bool get configurado =>
      supabaseUrl.isNotEmpty && supabaseAnonKey.isNotEmpty;

  /// Las cuentas se crean como `usuario@plataforma.local` (ver la Edge
  /// Function crear-usuario): la persona solo escribe su usuario.
  static const dominioUsuarios = 'plataforma.local';
}
