import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/routing/router.dart';
import '../core/theme/apariencia.dart';
import '../core/theme/venue_theme.dart';
import '../features/clubs/data/clubs.dart';

class VenueApp extends ConsumerWidget {
  const VenueApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final club = ref.watch(clubActivoProvider);
    final paleta = ref.watch(aparienciaProvider).paleta;
    final tema = temaVenue(
        primario: club?.primario, secundario: club?.secundario, paleta: paleta);
    // Los colores de VenueColors se leen al construir cada pantalla: al
    // cambiar de modo se monta todo de nuevo (el router conserva dónde estaba).
    return KeyedSubtree(
      key: ValueKey(paleta.brillo),
      child: MaterialApp.router(
        title: 'Venue',
        debugShowCheckedModeBanner: false,
        theme: tema,
        routerConfig: ref.watch(routerProvider),
        builder: (context, child) => _ConSplash(child: child ?? const SizedBox.shrink()),
      ),
    );
  }
}

/// Ya se mostró en esta apertura (el cambio de modo vuelve a montar la app
/// y no tiene que repetirse).
var _splashVisto = false;

/// Continúa la pantalla de arranque de iOS (fondo negro, logo de Venue en el
/// mismo lugar) y se desvanece hacia la app.
class _ConSplash extends StatefulWidget {
  const _ConSplash({required this.child});
  final Widget child;

  @override
  State<_ConSplash> createState() => _ConSplashState();
}

class _ConSplashState extends State<_ConSplash> {
  bool _visible = !_splashVisto;
  bool _montado = !_splashVisto;

  @override
  void initState() {
    super.initState();
    if (!_montado) return;
    _splashVisto = true;
    Future.delayed(const Duration(milliseconds: 700), () {
      if (mounted) setState(() => _visible = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!_montado) return widget.child;
    return Stack(children: [
      widget.child,
      IgnorePointer(
        ignoring: !_visible,
        child: AnimatedOpacity(
          opacity: _visible ? 1 : 0,
          duration: const Duration(milliseconds: 420),
          curve: Curves.easeOut,
          onEnd: () => setState(() => _montado = false),
          child: const ColoredBox(
            color: Colors.black,
            child: Center(
              child: Image(
                image: AssetImage('assets/splash/venue.png'),
                width: 220,
                height: 190,
                semanticLabel: 'Venue',
              ),
            ),
          ),
        ),
      ),
    ]);
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
