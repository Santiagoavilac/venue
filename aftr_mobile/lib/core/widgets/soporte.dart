import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../theme/aftr_theme.dart';
import 'piezas.dart';

/// El WhatsApp al que escribe quien pagó y no recibió nada. Es una persona, no
/// un bot: se le manda el caso ya escrito para que no tenga que contarlo.
const soporteWhatsapp = '59175028040';

Future<void> escribirASoporte(String mensaje) => launchUrl(
      Uri.parse('https://wa.me/$soporteWhatsapp?text=${Uri.encodeComponent(mensaje)}'),
      mode: LaunchMode.externalApplication,
    );

/// El cobro con QR vive diez minutos. Si la plata llega después, el cupo ya
/// volvió al evento y pudo venderse, así que no se entrega la entrada: queda
/// una incidencia para que el boliche devuelva la plata. Lo peor que se puede
/// hacer acá es no decir nada, que es lo que pasaba antes: el QR se quedaba
/// esperando para siempre.
class AvisoPagoTarde extends StatelessWidget {
  const AvisoPagoTarde({
    super.key,
    required this.monto,
    this.tarde = true,
    this.resuelta = false,
    this.evento,
  });

  final int monto;

  /// Llegó fuera del plazo. Si no, el cobro entró pero la emisión falló.
  final bool tarde;
  final bool resuelta;
  final String? evento;

  String get _mensaje => [
        'Hola, pagué Bs $monto por AFTR',
        if (evento != null) ' para $evento',
        tarde
            ? ' y el pago llegó tarde, así que no recibí la entrada.'
            : ' y no recibí la entrada.',
        ' Quisiera resolverlo.',
      ].join();

  @override
  Widget build(BuildContext context) {
    final color = resuelta ? Aftr.vivo : Aftr.alerta;
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Aftr.superficie2,
        borderRadius: BorderRadius.circular(Aftr.radio),
        border: Border.all(color: color.withValues(alpha: 0.45)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                resuelta ? Icons.check_circle_outline_rounded : Icons.error_outline_rounded,
                color: color,
                size: 20,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  resuelta
                      ? 'Tu pago se está resolviendo'
                      : (tarde ? 'Tu pago llegó tarde' : 'Tu pago no se pudo entregar'),
                  style: Aftr.fuerte(16),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            resuelta
                ? 'El boliche ya vio los Bs $monto y lo está resolviendo. Si en un rato no tenés novedades, escribinos.'
                : (tarde
                    ? 'El QR se cobra hasta diez minutos después de generarse. Los Bs $monto entraron después, así que el lugar ya se liberó y la entrada no se emitió. Escribinos y te lo devolvemos.'
                    : 'Los Bs $monto se cobraron pero la entrada no se pudo emitir. Escribinos y lo resolvemos.'),
            style: Aftr.cuerpo(14),
          ),
          if (evento != null) ...[
            const SizedBox(height: 6),
            Text(evento!, style: Aftr.cuerpo(13, c: Aftr.texto3)),
          ],
          const SizedBox(height: 14),
          BotonAftr(
            'Escribir por WhatsApp',
            secundario: true,
            icono: const Icon(Icons.chat_bubble_outline_rounded, size: 18, color: Aftr.texto),
            onTap: () => escribirASoporte(_mensaje),
          ),
        ],
      ),
    );
  }
}
