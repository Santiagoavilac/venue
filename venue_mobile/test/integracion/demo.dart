import 'package:supabase/supabase.dart';
import 'package:venue_mobile/core/config/env.dart';
import 'package:venue_mobile/features/authentication/data/sesion.dart';

/// Utilidades para los tests que hablan con el proyecto DEMO real.
///
///   flutter test test/integracion --dart-define-from-file=env/dev.json
///
/// Usan los usuarios de `tools/seed_demo.py`. Sin `--dart-define-from-file`
/// se saltean solos.
const claveDemo = 'Venue2026!';

String? get saltear =>
    Env.configurado ? null : 'sin --dart-define-from-file=env/dev.json';

Future<SupabaseClient> sesionDe(String usuario) async {
  final sb = SupabaseClient(Env.supabaseUrl, Env.supabaseAnonKey);
  await sb.auth.signInWithPassword(
      email: AuthRepository.emailDe(usuario), password: claveDemo);
  return sb;
}

Future<String> eventoDe(SupabaseClient sb, String club) async {
  final r = await sb.from('eventos').select('id').eq('club_id', club).limit(1);
  return r.first['id'] as String;
}
