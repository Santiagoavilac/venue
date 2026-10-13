import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';

/// Datos de un ticket para dibujar y compartir.
class TicketDatos {
  const TicketDatos({
    required this.payload,
    required this.codigo,
    required this.cliente,
    required this.boliche,
    required this.evento,
    required this.fecha,
    required this.tipo,
    this.color,
    this.arteUrl,
    this.fase,
    this.oro = false,
  });

  /// Texto codificado en el QR (`EVT:…` o `LST:…`).
  final String payload;
  final String codigo;
  final String cliente;
  final String boliche;
  final String evento;
  final String fecha;

  /// "Entrada prepagada", nombre de la lista…
  final String tipo;
  final Color? color;

  /// Arte del evento (o de la fase) sobre el que se imprime el QR.
  final String? arteUrl;

  /// Nombre de la fase de preventa, si se vendió en una.
  final String? fase;

  /// Entrada "de la casa": marco dorado.
  final bool oro;

  String get mensaje => '🎟️ $tipo · $boliche — $evento · $fecha\n$cliente\n'
      'Válida para 1 solo ingreso. Presentá este QR en puerta.';
}

final _artes = <String, Future<ui.Image>>{};

/// Descarga y decodifica el arte. Se guarda en memoria: en una tanda de 30
/// entradas la imagen es siempre la misma.
Future<ui.Image> cargarArte(String url) {
  final f = _artes[url] ??= () async {
    final datos = await NetworkAssetBundle(Uri.parse(url)).load(url);
    final codec = await ui.instantiateImageCodec(datos.buffer.asUint8List());
    return (await codec.getNextFrame()).image;
  }();
  f.catchError((Object _) {
    _artes.remove(url); // no dejar guardado un fallo
    return f;
  });
  return f;
}

void _texto(Canvas c, String t, double cx, double lineaBase, double tam,
    FontWeight peso, {Color color = Colors.white, double maxAncho = double.infinity, bool sombra = true}) {
  final p = TextPainter(
    text: TextSpan(
      text: t,
      style: TextStyle(
        color: color, fontSize: tam, fontWeight: peso,
        shadows: sombra
            ? [Shadow(color: Colors.black.withValues(alpha: .9), blurRadius: tam * .25)]
            : null,
      ),
    ),
    textAlign: TextAlign.center,
    textDirection: TextDirection.ltr,
    maxLines: 1,
    ellipsis: '…',
  )..layout(maxWidth: maxAncho);
  final base = p.computeDistanceToActualBaseline(TextBaseline.alphabetic);
  p.paint(c, Offset(cx - p.width / 2, lineaBase - base));
}

/// Dibuja el ticket y lo devuelve como PNG.
///
/// Con arte del evento reproduce la composición de la web (`ticketImage` en
/// app.js): el QR en un recuadro blanco del 52 % del ancho a 29 % del alto,
/// y debajo el código y el nombre. Así un ticket emitido desde la app es
/// igual al emitido desde la web. Sin arte, se dibuja un fondo propio con el
/// color del boliche.
Future<Uint8List> dibujarTicket(TicketDatos d) async {
  ui.Image? arte;
  if (d.arteUrl != null && d.arteUrl!.isNotEmpty) {
    try {
      arte = await cargarArte(d.arteUrl!);
    } catch (_) {
      arte = null; // sin red o imagen rota: se usa el diseño propio
    }
  }
  final w = arte?.width.toDouble() ?? 1080.0;
  final h = arte?.height.toDouble() ?? 1620.0;
  final rec = ui.PictureRecorder();
  final c = Canvas(rec, Rect.fromLTWH(0, 0, w, h));

  if (arte != null) {
    c.drawImage(arte, Offset.zero, Paint());
  } else {
    final marca = d.color ?? const Color(0xFF7C3AED);
    c.drawRect(
      Rect.fromLTWH(0, 0, w, h),
      Paint()
        ..shader = ui.Gradient.linear(Offset.zero, Offset(w, h), [
          Color.lerp(marca, Colors.black, .55)!,
          const Color(0xFF07070A),
          Color.lerp(marca, Colors.black, .78)!,
        ], [0, .55, 1]),
    );
    _texto(c, d.boliche.toUpperCase(), w / 2, h * .09, w * .038, FontWeight.w800,
        color: Color.lerp(marca, Colors.white, .45)!, maxAncho: w * .9, sombra: false);
    _texto(c, d.evento, w / 2, h * .165, w * .074, FontWeight.w800, maxAncho: w * .9);
    _texto(c, d.fecha, w / 2, h * .215, w * .04, FontWeight.w500,
        color: const Color(0xFFC9C9D6), maxAncho: w * .9);
  }

  // recuadro blanco + QR
  final caja = w * .52, bx = (w - caja) / 2, by = h * .29;
  c.drawRRect(
      RRect.fromRectAndRadius(Rect.fromLTWH(bx, by, caja, caja), Radius.circular(caja * .07)),
      Paint()..color = Colors.white);
  final margen = caja * .06, lado = caja - 2 * margen;
  c.save();
  c.translate(bx + margen, by + margen);
  QrPainter(
    data: d.payload,
    version: QrVersions.auto,
    errorCorrectionLevel: QrErrorCorrectLevel.M,
    gapless: true,
    eyeStyle: const QrEyeStyle(eyeShape: QrEyeShape.square, color: Colors.black),
    dataModuleStyle:
        const QrDataModuleStyle(dataModuleShape: QrDataModuleShape.square, color: Colors.black),
  ).paint(c, Size(lado, lado));
  c.restore();

  // código y nombre, pegados debajo del QR
  final yCodigo = by + caja + h * .055;
  _texto(c, '#${d.codigo}', w / 2, yCodigo, w * .078, FontWeight.w700, maxAncho: w * .92);
  _texto(c, d.cliente, w / 2, yCodigo + w * .075, w * .042, FontWeight.w500, maxAncho: w * .9);
  if (arte == null) {
    _texto(c, d.tipo, w / 2, yCodigo + w * .14, w * .034, FontWeight.w600,
        color: const Color(0xFFC9C9D6), maxAncho: w * .9, sombra: false);
    _texto(c, 'Válida para 1 solo ingreso', w / 2, h * .955, w * .03, FontWeight.w600,
        color: const Color(0xFF9A9AAC), sombra: false);
  }

  // sello de la fase (la tanda es parte de lo que el cliente compró)
  if (d.fase != null && d.fase!.isNotEmpty) {
    final t = TextPainter(
      text: TextSpan(
          text: d.fase!.toUpperCase(),
          style: TextStyle(color: Colors.white, fontSize: w * .032, fontWeight: FontWeight.w800)),
      textDirection: TextDirection.ltr,
    )..layout();
    final pw = t.width + w * .07, ph = w * .068;
    final r = RRect.fromRectAndRadius(
        Rect.fromLTWH((w - pw) / 2, h * (arte == null ? .885 : .925) - ph / 2, pw, ph),
        Radius.circular(ph / 2));
    c.drawRRect(r, Paint()..color = Colors.black.withValues(alpha: .55));
    c.drawRRect(
        r,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = w * .0025
          ..color = Colors.white.withValues(alpha: .5));
    t.paint(c, Offset((w - t.width) / 2, r.center.dy - t.height / 2));
  }

  // marco dorado: entrada de la casa
  if (d.oro) {
    final m = w * .022;
    c.drawRRect(
      RRect.fromRectAndRadius(
          Rect.fromLTWH(m, m, w - 2 * m, h - 2 * m), Radius.circular(w * .035)),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = w * .016
        ..shader = ui.Gradient.linear(Offset.zero, Offset(w, h), const [
          Color(0xFFFFE9A3), Color(0xFFE8B530), Color(0xFFFFDF7A),
        ], [0, .5, 1]),
    );
  }

  final imagen = await rec.endRecording().toImage(w.round(), h.round());
  final png = await imagen.toByteData(format: ui.ImageByteFormat.png);
  return png!.buffer.asUint8List();
}
