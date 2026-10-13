import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

import '../../../core/theme/venue_theme.dart';
import '../../../core/widgets/avisos.dart';
import '../data/ticket_imagen.dart';

export '../data/ticket_imagen.dart' show TicketDatos;

Future<XFile> _archivo(TicketDatos d) async {
  final f = File('${Directory.systemTemp.path}/entrada-${d.codigo}.png');
  await f.writeAsBytes(await dibujarTicket(d));
  return XFile(f.path, mimeType: 'image/png');
}

/// Comparte varias entradas juntas (la "tanda" de la web): una imagen por
/// persona y un solo mensaje con los nombres. Se abre la hoja de compartir
/// del sistema; la app no accede al WhatsApp de nadie.
Future<void> compartirTanda(BuildContext context, List<TicketDatos> tickets) async {
  if (tickets.isEmpty) return;
  try {
    final archivos = <XFile>[];
    for (final t in tickets) {
      archivos.add(await _archivo(t));
    }
    final p = tickets.first;
    await SharePlus.instance.share(ShareParams(
      files: archivos,
      text: tickets.length == 1
          ? p.mensaje
          : '🎟️ ${tickets.length} entradas · ${p.boliche} — ${p.evento} · ${p.fecha}\n'
              '${tickets.map((t) => t.cliente).join('\n')}\n'
              'Cada QR vale para 1 solo ingreso.',
    ));
  } catch (_) {
    if (context.mounted) {
      avisar(context, 'No se pudieron compartir las entradas', tipo: TipoAviso.aviso);
    }
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
  late final Future<Uint8List> _png = dibujarTicket(widget.datos);
  bool _compartiendo = false;

  @override
  Widget build(BuildContext context) {
    final alto = MediaQuery.of(context).size.height;
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ConstrainedBox(
              constraints: BoxConstraints(maxHeight: alto * .58),
              child: FutureBuilder(
                future: _png,
                builder: (context, s) => s.hasData
                    ? ClipRRect(
                        borderRadius: BorderRadius.circular(18),
                        child: Image.memory(s.data!, fit: BoxFit.contain),
                      )
                    : const SizedBox(
                        height: 260,
                        child: Center(child: CircularProgressIndicator())),
              ),
            ),
            const SizedBox(height: 18),
            FilledButton.icon(
              onPressed: _compartiendo
                  ? null
                  : () async {
                      setState(() => _compartiendo = true);
                      await compartirTanda(context, [widget.datos]);
                      if (mounted) setState(() => _compartiendo = false);
                    },
              icon: const Icon(Icons.ios_share_rounded),
              label: const Text('Compartir entrada'),
            ),
            const SizedBox(height: 10),
            OutlinedButton.icon(
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: widget.datos.codigo));
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
