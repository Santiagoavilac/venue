import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app/app.dart';
import 'core/config/env.dart';
import 'core/notificaciones.dart';
import 'core/security/llavero.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);

  if (!Env.configurado) {
    runApp(const SinConfiguracionApp());
    return;
  }
  await Supabase.initialize(
    url: Env.supabaseUrl,
    publishableKey: Env.supabaseAnonKey,
    authOptions: FlutterAuthClientOptions(localStorage: LlaveroStorage()),
  );
  // Firebase arranca acá y no cuando se pide el permiso: si falla -falta la
  // configuración, o el teléfono no tiene servicios de Google- la app sigue
  // andando sin notificaciones, que es mejor que no abrir.
  await Notificaciones.arrancar();
  runApp(const ProviderScope(child: AftrApp()));
}
