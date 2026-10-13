import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';

import '../../../core/theme/venue_theme.dart';
import '../../../core/widgets/avisos.dart';

/// Datos de un ticket para mostrar y compartir.
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

  String get mensaje => '🎟️ $tipo · $boliche — $evento · $fecha\n$cliente\n'
      'Válida para 1 solo ingreso. Presentá este QR en puerta.';
}

/// La imagen del ticket. Fondo propio (no depende del tema) porque se
/// comparte fuera de la app y tiene que verse igual en cualquier chat.
class TicketCard extends StatelessWidget {
  const TicketCard({super.key, required this.datos});
  final TicketDatos datos;

  @override
  Widget build(BuildContext context) {
    final d = datos;
    final marca = d.color ?? VenueColors.marcaPorDefecto;
    return Container(
      width: 340,
      decoration: BoxDecoration(
        color: const Color(0xFF0B0B10),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: marca.withValues(alpha: .7), width: 1.5),
      ),
      padding: const EdgeInsets.fromLTRB(22, 22, 22, 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            d.boliche.toUpperCase(),
            style: TextStyle(
              color: marca,
              fontSize: 13,
              fontWeight: FontWeight.w800,
              letterSpacing: 3,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            d.evento,
            textAlign: TextAlign.center,
            style: const TextStyle(
                color: Colors.white, fontSize: 22, fontWeight: FontWeight.w800),
          ),
          Text(d.fecha,
              style: const TextStyle(color: Color(0xFFA2A2B4), fontSize: 14)),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
            ),
            child: QrImageView(
              data: d.payload,
              size: 228,
              padding: EdgeInsets.zero,
              errorCorrectionLevel: QrErrorCorrectLevel.M,
            ),
          ),
          const SizedBox(height: 14),
          Text(
            d.cliente,
            textAlign: TextAlign.center,
            style: const TextStyle(
                color: Colors.white, fontSize: 20, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 2),
          Text(
            '${d.tipo} · #${d.codigo}',
            style: const TextStyle(color: Color(0xFFA2A2B4), fontSize: 13.5),
          ),
          const SizedBox(height: 10),
          const Text(
            'Válida para 1 solo ingreso',
            style: TextStyle(
                color: Color(0xFFA2A2B4),
                fontSize: 12,
                fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}

/// Muestra el ticket con las acciones de compartir.
Future<void> mostrarTicket(BuildContext context, TicketDatos datos) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    backgroundColor: VenueColors.superficie,
    builder: (_) => _TicketSheet(datos: datos),
  );
}

class _TicketSheet extends StatefulWidget {
  const _TicketSheet({required this.datos});
  final TicketDatos datos;

  @override
  State<_TicketSheet> createState() => _TicketSheetState();
}

class _TicketSheetState extends State<_TicketSheet> {
  final _clave = GlobalKey();
  bool _compartiendo = false;

  Future<void> _compartir() async {
    setState(() => _compartiendo = true);
    try {
      final limite =
          _clave.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final imagen = await limite.toImage(pixelRatio: 3);
      final png = await imagen.toByteData(format: ui.ImageByteFormat.png);
      final archivo = File(
          '${Directory.systemTemp.path}/entrada-${widget.datos.codigo}.png');
      await archivo.writeAsBytes(png!.buffer.asUint8List());
      // Se abre la hoja de compartir del sistema: la persona elige WhatsApp
      // (u otra app) y el contacto. La app no accede a su WhatsApp.
      await SharePlus.instance.share(ShareParams(
        files: [XFile(archivo.path, mimeType: 'image/png')],
        text: widget.datos.mensaje,
      ));
    } catch (e) {
      if (mounted) {
        avisar(context, 'No se pudo compartir la entrada', tipo: TipoAviso.aviso);
      }
    }
    if (mounted) setState(() => _compartiendo = false);
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            RepaintBoundary(key: _clave, child: TicketCard(datos: widget.datos)),
            const SizedBox(height: 18),
            FilledButton.icon(
              onPressed: _compartiendo ? null : _compartir,
              icon: const Icon(Icons.ios_share_rounded),
              label: const Text('Compartir entrada'),
            ),
            const SizedBox(height: 10),
            OutlinedButton.icon(
              onPressed: () async {
                await Clipboard.setData(
                    ClipboardData(text: widget.datos.codigo));
                if (context.mounted) avisar(context, 'Código copiado');
              },
              icon: const Icon(Icons.copy_rounded),
              label: Text('Copiar código #${widget.datos.codigo}'),
            ),
          ],
        ),
      ),
    );
  }
}
