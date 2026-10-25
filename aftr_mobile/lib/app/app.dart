import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/routing/router.dart';
import '../core/theme/aftr_theme.dart';
import '../features/splash/splash.dart';

class AftrApp extends ConsumerStatefulWidget {
  const AftrApp({super.key});

  @override
  ConsumerState<AftrApp> createState() => _AftrAppState();
}

class _AftrAppState extends ConsumerState<AftrApp> {
  bool _splash = true;
  bool _quitado = false;

  @override
  Widget build(BuildContext context) {
    SystemChrome.setSystemUIOverlayStyle(SystemUiOverlayStyle.light);
    return MaterialApp.router(
      title: 'AFTR',
      debugShowCheckedModeBanner: false,
      theme: temaAftr(),
      darkTheme: temaAftr(),
      themeMode: ThemeMode.dark,
      routerConfig: ref.watch(routerProvider),
      // el arranque va encima de todo y se desvanece cuando termina; la app
      // ya está cargando debajo
      builder: (context, hijo) => Stack(children: [
        ?hijo,
        if (!_quitado)
          IgnorePointer(
            ignoring: !_splash,
            child: AnimatedOpacity(
              opacity: _splash ? 1 : 0,
              duration: const Duration(milliseconds: 380),
              onEnd: () => setState(() => _quitado = true),
              // va encima del Navigator: sin Material el texto sale con el
              // subrayado amarillo de "falta estilo"
              child: Material(
                type: MaterialType.transparency,
                child: Splash(alTerminar: () => setState(() => _splash = false)),
              ),
            ),
          ),
      ]),
    );
  }
}

/// Sin env/dev.json no hay a qué conectarse.
class SinConfiguracionApp extends StatelessWidget {
  const SinConfiguracionApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
        theme: temaAftr(),
        home: const Scaffold(
          body: Center(
            child: Padding(
              padding: EdgeInsets.all(32),
              child: Text(
                'Falta la configuración. Compilá con --dart-define-from-file=env/dev.json',
                textAlign: TextAlign.center,
              ),
            ),
          ),
        ),
      );
}
