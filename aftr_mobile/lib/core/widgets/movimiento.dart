import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/aftr_theme.dart';

/// Entra con fundido y un desplazamiento corto hacia arriba. `orden` escalona
/// los elementos de una lista para que no aparezcan todos de golpe.
class Aparecer extends StatefulWidget {
  const Aparecer({super.key, required this.child, this.orden = 0, this.desde = 18});

  final Widget child;
  final int orden;
  final double desde;

  @override
  State<Aparecer> createState() => _AparecerState();
}

class _AparecerState extends State<Aparecer> with SingleTickerProviderStateMixin {
  late final _c = AnimationController(vsync: this, duration: Aftr.lento);
  late final _t = CurvedAnimation(parent: _c, curve: Aftr.curva);

  @override
  void initState() {
    super.initState();
    Future.delayed(Duration(milliseconds: 45 * widget.orden.clamp(0, 10)), () {
      if (mounted) _c.forward();
    });
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: _t,
        builder: (_, child) => Opacity(
          opacity: _t.value,
          child: Transform.translate(offset: Offset(0, widget.desde * (1 - _t.value)), child: child),
        ),
        child: widget.child,
      );
}

/// Se achica un poco al tocar, como las tarjetas de Resy.
class Presionable extends StatefulWidget {
  const Presionable({super.key, required this.child, this.onTap, this.escala = 0.97});

  final Widget child;
  final VoidCallback? onTap;
  final double escala;

  @override
  State<Presionable> createState() => _PresionableState();
}

class _PresionableState extends State<Presionable> {
  bool _abajo = false;

  void _set(bool v) {
    if (widget.onTap != null && v != _abajo) setState(() => _abajo = v);
  }

  @override
  Widget build(BuildContext context) => GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (_) => _set(true),
        onTapUp: (_) => _set(false),
        onTapCancel: () => _set(false),
        onTap: widget.onTap == null
            ? null
            : () {
                HapticFeedback.selectionClick();
                widget.onTap!();
              },
        child: AnimatedScale(
          scale: _abajo ? widget.escala : 1,
          duration: Aftr.rapido,
          curve: Aftr.curva,
          child: widget.child,
        ),
      );
}

/// Bloque gris con un brillo que lo recorre, mientras carga.
class Esqueleto extends StatefulWidget {
  const Esqueleto({super.key, this.alto = 16, this.ancho, this.radio = 10});

  final double alto;
  final double? ancho;
  final double radio;

  @override
  State<Esqueleto> createState() => _EsqueletoState();
}

class _EsqueletoState extends State<Esqueleto> with SingleTickerProviderStateMixin {
  late final _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1300))..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: _c,
        builder: (_, _) => Container(
          height: widget.alto,
          width: widget.ancho,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(widget.radio),
            gradient: LinearGradient(
              begin: Alignment(-1.6 + 3.2 * _c.value, 0),
              end: Alignment(-0.6 + 3.2 * _c.value, 0),
              colors: const [Aftr.superficie2, Aftr.superficie3, Aftr.superficie2],
            ),
          ),
        ),
      );
}
