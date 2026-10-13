import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/routing/router.dart';
import '../core/theme/venue_theme.dart';
import '../features/clubs/data/clubs.dart';

class VenueApp extends ConsumerWidget {
  const VenueApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final club = ref.watch(clubActivoProvider);
    return MaterialApp.router(
      title: 'Venue',
      debugShowCheckedModeBanner: false,
      theme: temaVenue(primario: club?.primario, secundario: club?.secundario),
      routerConfig: ref.watch(routerProvider),
    );
  }
}

/// Se muestra si la app se compiló sin `--dart-define-from-file`.
class SinConfiguracionApp extends StatelessWidget {
  const SinConfiguracionApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: temaVenue(),
      home: const Scaffold(
        body: Center(
          child: Padding(
            padding: EdgeInsets.all(32),
            child: Text(
              'Falta la configuración de Supabase.\n\n'
              'Compilá con:\n--dart-define-from-file=env/dev.json',
              textAlign: TextAlign.center,
            ),
          ),
        ),
      ),
    );
  }
}
