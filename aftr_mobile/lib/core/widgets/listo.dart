import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/aftr_theme.dart';
import 'movimiento.dart';
import 'piezas.dart';

/// El check que se dibuja solo (como el "Confirmed" de Resy): primero el
/// círculo, después la marca, con un pulso al final.
class CheckAnimado extends StatefulWidget {
  const CheckAnimado({super.key, this.tam = 84, this.color = Aftr.vivo});

  final double tam;
  final Color color;

  @override
  State<CheckAnimado> createState() => _CheckAnimadoState();
}

class _CheckAnimadoState extends State<CheckAnimado> with SingleTickerProviderStateMixin {
  late final _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 900))..forward();

  @override
  void initState() {
    super.initState();
    HapticFeedback.mediumImpact();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: _c,
        builder: (_, _) {
          final pulso = Curves.easeOut.transform(((_c.value - 0.75) / 0.25).clamp(0, 1));
          return Transform.scale(
            scale: 1 + 0.08 * math.sin(pulso * math.pi),
            child: CustomPaint(size: Size.square(widget.tam), painter: _Check(_c.value, widget.color)),
          );
        },
      );
}

class _Check extends CustomPainter {
  _Check(this.t, this.color);
  final double t;
  final Color color;

  @override
  void paint(Canvas canvas, Size s) {
    final p = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = s.width * 0.06
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final circulo = Curves.easeOutCubic.transform((t / 0.55).clamp(0, 1));
    canvas.drawArc(Offset.zero & s, -math.pi / 2, 2 * math.pi * circulo, false, p);
    final marca = Curves.easeOutCubic.transform(((t - 0.45) / 0.4).clamp(0, 1));
    if (marca <= 0) return;
    final camino = Path()
      ..moveTo(s.width * 0.28, s.height * 0.52)
      ..lineTo(s.width * 0.44, s.height * 0.67)
      ..lineTo(s.width * 0.73, s.height * 0.37);
    for (final m in camino.computeMetrics()) {
      canvas.drawPath(m.extractPath(0, m.length * marca), p);
    }
  }

  @override
  bool shouldRepaint(_Check old) => old.t != t;
}

/// Contenido de hoja "listo": check, título, texto y botones.
class HojaListo extends StatelessWidget {
  const HojaListo({super.key, required this.titulo, required this.texto, required this.accion, required this.onAccion, this.onCerrar});

  final String titulo;
  final String texto;
  final String accion;
  final VoidCallback onAccion;
  final VoidCallback? onCerrar;

  @override
  Widget build(BuildContext context) => Padding(
        padding: EdgeInsets.fromLTRB(24, 36, 24, 20 + MediaQuery.paddingOf(context).bottom),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const CheckAnimado(),
          const SizedBox(height: 22),
          Aparecer(orden: 6, child: Text(titulo, textAlign: TextAlign.center, style: Aftr.fuerte(24))),
          const SizedBox(height: 10),
          Aparecer(orden: 7, child: Text(texto, textAlign: TextAlign.center, style: Aftr.cuerpo(15))),
          const SizedBox(height: 28),
          BotonAftr(accion, onTap: onAccion),
          if (onCerrar != null) ...[
            const SizedBox(height: 8),
            TextButton(onPressed: onCerrar, child: Text('Listo', style: Aftr.cuerpo(15, c: Aftr.texto))),
          ],
        ]),
      );
}

/// Manija de las hojas.
class Manija extends StatelessWidget {
  const Manija({super.key});

  @override
  Widget build(BuildContext context) => Center(
        child: Container(
          margin: const EdgeInsets.only(top: 10, bottom: 6),
          width: 38,
          height: 5,
          decoration: BoxDecoration(color: Aftr.bordeFuerte, borderRadius: BorderRadius.circular(3)),
        ),
      );
}
