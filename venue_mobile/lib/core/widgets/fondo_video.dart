import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';


/// Video de fondo en bucle, sin sonido y sin cortar la música que esté
/// sonando. Cubre todo sin deformarse; mientras carga (o si falla) queda el
/// fondo negro de siempre. El degradé de abajo es para que se lea el texto.
class FondoVideo extends StatefulWidget {
  const FondoVideo(this.asset, {super.key, required this.child});
  final String asset;
  final Widget child;

  @override
  State<FondoVideo> createState() => _FondoVideoState();
}

class _FondoVideoState extends State<FondoVideo> with WidgetsBindingObserver {
  late final VideoPlayerController _c = VideoPlayerController.asset(
    widget.asset,
    videoPlayerOptions: VideoPlayerOptions(mixWithOthers: true),
  );
  bool _listo = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _c.setLooping(true);
    _c.setVolume(0);
    _c.initialize().then((_) {
      if (!mounted) return;
      setState(() => _listo = true);
      _c.play();
    }, onError: (_) {});
  }

  // en segundo plano no gasta batería
  @override
  void didChangeAppLifecycleState(AppLifecycleState s) {
    if (!_listo) return;
    s == AppLifecycleState.resumed ? _c.play() : _c.pause();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => _FondoConDegrade(
        fondo: AnimatedOpacity(
          opacity: _listo ? 1 : 0,
          duration: const Duration(milliseconds: 400),
          child: _listo
              ? FittedBox(
                  fit: BoxFit.cover,
                  clipBehavior: Clip.hardEdge,
                  child: SizedBox(width: _c.value.size.width, height: _c.value.size.height, child: VideoPlayer(_c)),
                )
              : const SizedBox.expand(),
        ),
        child: widget.child,
      );
}

class _FondoConDegrade extends StatelessWidget {
  const _FondoConDegrade({required this.fondo, required this.child});
  final Widget fondo;
  final Widget child;

  @override
  Widget build(BuildContext context) => ColoredBox(
        color: const Color(0xFF16181C),
        child: Stack(fit: StackFit.expand, children: [
          RepaintBoundary(child: fondo),
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                stops: [0, .22, .5, .78, 1],
                colors: [Color(0x99000000), Color(0x33000000), Color(0x44000000), Color(0xD9000000), Color(0xFF000000)],
              ),
            ),
          ),
          child,
        ]),
      );
}
