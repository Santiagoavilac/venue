import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../core/theme/aftr_theme.dart';

/// Dibuja los pines del mapa como imágenes (Apple Maps solo acepta bitmaps):
/// círculo oscuro con la inicial del lugar en la serif del logo; con evento
/// hoy, anillo dorado con halo; elegido, blanco y más grande.
class Pines {
  Pines(this.escala);
  final double escala;
  final _cache = <String, Uint8List>{};

  Future<Uint8List> pin(String inicial, {required bool hoy, required bool elegido, required bool apagado}) async {
    final clave = '$inicial|$hoy|$elegido|$apagado';
    final hecho = _cache[clave];
    if (hecho != null) return hecho;

    final lado = (elegido ? 52.0 : 40.0);
    final halo = hoy || elegido ? 10.0 : 4.0;
    final total = (lado + halo * 2) * escala;
    final rec = ui.PictureRecorder();
    final c = Canvas(rec)..scale(escala);
    final centro = Offset(lado / 2 + halo, lado / 2 + halo);

    if (hoy || elegido) {
      c.drawCircle(
        centro,
        lado / 2 + halo * 0.6,
        Paint()
          ..color = (elegido ? Aftr.texto : Aftr.acento).withValues(alpha: 0.28)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6),
      );
    }
    c.drawCircle(centro, lado / 2, Paint()..color = elegido ? Aftr.texto : const Color(0xFF111114));
    c.drawCircle(
      centro,
      lado / 2 - 1,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = elegido ? Aftr.texto : (hoy ? Aftr.acento : (apagado ? Aftr.bordeFuerte : Aftr.texto.withValues(alpha: 0.85))),
    );
    final tp = TextPainter(
      text: TextSpan(
        text: inicial,
        style: TextStyle(
          fontFamily: Aftr.serif,
          fontSize: lado * 0.5,
          color: elegido ? Aftr.fondo : (apagado ? Aftr.texto3 : Aftr.texto),
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(c, centro - Offset(tp.width / 2, tp.height / 2));

    final img = await rec.endRecording().toImage(total.ceil(), total.ceil());
    final bytes = (await img.toByteData(format: ui.ImageByteFormat.png))!.buffer.asUint8List();
    return _cache[clave] = bytes;
  }
}
