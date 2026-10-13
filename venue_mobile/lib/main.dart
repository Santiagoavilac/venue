import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app/app.dart';
import 'core/config/env.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);

  if (!Env.configurado) {
    runApp(const SinConfiguracionApp());
    return;
  }
  // supabase_flutter persiste la sesión y renueva el token solo.
  // PENDIENTE: por defecto la guarda en las preferencias de la app, sin
  // cifrar; hay que pasarla al llavero con flutter_secure_storage.
  await Supabase.initialize(
    url: Env.supabaseUrl,
    publishableKey: Env.supabaseAnonKey,
  );
  runApp(const ProviderScope(child: VenueApp()));
}
