import 'dart:async';
import 'dart:math' as math;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/theme/aftr_theme.dart';
import '../../core/widgets/logo.dart';

/// Fotos de noche para los destellos: las propias y, si están en caché, los
/// flyers de los próximos eventos que se vieron la última vez.
const fotosNoche = ['assets/splash/noche1.jpg', 'assets/splash/noche2.jpg', 'assets/splash/noche3.jpg'];
const _claveFlyers = 'aftr.splash.flyers';

/// Lo llama Descubrir al cargar, para que el próximo arranque destelle con
/// eventos reales.
Future<void> guardarFlyersParaSplash(List<String> urls) async {
  try {
    final p = await SharedPreferences.getInstance();
    await p.setStringList(_claveFlyers, urls.take(4).toList());
  } catch (_) {}
}

/// Arranque: la A aparece (como la R de Rakuten), destellan fotos de noche
/// detrás (como Pillowtalk), la A hace zoom y se arma AFTR letra por letra.
/// Sale completo en cada arranque en frío; se salta con un toque.
class Splash extends StatefulWidget {
  const Splash({super.key, required this.alTerminar});

  final VoidCallback alTerminar;

  @override
  State<Splash> createState() => _SplashState();
}

class _SplashState extends State<Splash> with SingleTickerProviderStateMixin {
  late AnimationController _c;
  final List<ImageProvider> _fotos = [for (final f in fotosNoche) AssetImage(f)];
  bool _listo = false;
  bool _fuera = false;

  static const _completoMs = 2700;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(vsync: this, duration: const Duration(milliseconds: _completoMs));
    _c.addStatusListener((s) {
      if (s == AnimationStatus.completed) _salir();
    });
    _preparar();
  }

  Future<void> _preparar() async {
    try {
      // las fotos propias se decodifican antes de arrancar: si no, los
      // primeros destellos salen en negro
      await Future.wait([for (final f in List.of(_fotos)) precacheImage(f, context)])
          .timeout(const Duration(milliseconds: 600));
      final p = await SharedPreferences.getInstance();
      for (final u in p.getStringList(_claveFlyers) ?? const <String>[]) {
        if (!mounted) return;
        final img = CachedNetworkImageProvider(u);
        try {
          await precacheImage(img, context).timeout(const Duration(milliseconds: 250));
          _fotos.add(img);
        } catch (_) {}
      }
    } catch (_) {}
    if (!mounted) return;
    setState(() => _listo = true);
    _c.forward();
  }

  void _salir() {
    if (_fuera) return;
    _fuera = true;
    HapticFeedback.lightImpact();
    widget.alTerminar();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  double get _ms => _c.value * _completoMs;

  // tramo [a, b] del reloj -> 0..1 con curva
  double _t(double a, double b, [Curve curva = Curves.easeOutCubic]) =>
      curva.transform(((_ms - a) / (b - a)).clamp(0.0, 1.0));

  @override
  Widget build(BuildContext context) {
    final ancho = MediaQuery.sizeOf(context).width;
    final altoPalabra = math.min(64.0, ancho * 0.13);
    return GestureDetector(
      onTap: _salir,
      child: ColoredBox(
        color: Aftr.fondo,
        child: !_listo
            ? const SizedBox.expand()
            : AnimatedBuilder(
                animation: _c,
                builder: (context, _) {
                  final ms = _ms;
                  // 1) la A entra
                  final entra = _t(0, 380);
                  // 2) destellos: un corte seco cada ~115 ms
                  final enDestellos = ms > 380 && ms < 1060;
                  final idx = enDestellos ? ((ms - 380) ~/ 115) : -1;
                  // 3) la A hace zoom y se va; AFTR se arma
                  final zoom = _t(1060, 1500, Curves.easeInCubic);
                  final letraA = _t(1250, 1650);
                  final letras = [for (var i = 1; i < 4; i++) _t(1420 + i * 110.0, 1780 + i * 110.0)];
                  final lema = _t(1900, 2350);
                  final salida = _t(2450, 2700, Curves.easeIn);

                  return Opacity(
                    opacity: 1 - salida,
                    child: Stack(fit: StackFit.expand, children: [
                      if (idx >= 0) _Destello(foto: _fotos[idx % _fotos.length], n: idx),
                      // la marca
                      Center(
                        child: Opacity(
                          opacity: entra * (1 - zoom),
                          child: Transform.scale(
                            scale: (0.86 + 0.14 * entra) * (1 + 6 * zoom),
                            child: const MarcaAftr(alto: 92),
                          ),
                        ),
                      ),
                      // la palabra
                      Center(
                        child: Column(mainAxisSize: MainAxisSize.min, children: [
                          Transform.scale(
                            scale: 1 + 0.6 * (1 - letraA),
                            alignment: Alignment.centerLeft,
                            child: PalabraAftr(
                              alto: altoPalabra,
                              opacidades: [letraA, ...letras],
                              desplazar: [
                                Offset.zero,
                                for (final l in letras) Offset(26 * (1 - l), 0),
                              ],
                            ),
                          ),
                          SizedBox(height: altoPalabra * 0.42),
                          Opacity(
                            opacity: lema,
                            child: Text(
                              'NIGHTLIFE & EVENTS',
                              style: TextStyle(
                                fontFamily: Aftr.sans,
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                                color: Aftr.texto,
                                letterSpacing: 3 + 3 * lema,
                                decoration: TextDecoration.none,
                              ),
                            ),
                          ),
                        ]),
                      ),
                    ]),
                  );
                },
              ),
      ),
    );
  }
}

/// Una foto a pantalla completa, oscurecida y con grano, que cambia de encuadre
/// en cada corte para que tres fotos parezcan muchas.
class _Destello extends StatelessWidget {
  const _Destello({required this.foto, required this.n});

  final ImageProvider foto;
  final int n;

  @override
  Widget build(BuildContext context) {
    const encuadres = [Alignment.center, Alignment.topCenter, Alignment.bottomCenter, Alignment.centerLeft];
    final bn = n.isOdd;
    return Stack(fit: StackFit.expand, children: [
      Transform.scale(
        scale: 1.08 + 0.06 * (n % 3),
        child: ColorFiltered(
          colorFilter: bn
              ? const ColorFilter.matrix([
                  0.33, 0.59, 0.11, 0, 0, //
                  0.33, 0.59, 0.11, 0, 0,
                  0.33, 0.59, 0.11, 0, 0,
                  0, 0, 0, 1, 0,
                ])
              : const ColorFilter.mode(Colors.transparent, BlendMode.dst),
          child: Image(image: foto, fit: BoxFit.cover, alignment: encuadres[n % encuadres.length], gaplessPlayback: true),
        ),
      ),
      const ColoredBox(color: Color(0x73000000)),
    ]);
  }
}
