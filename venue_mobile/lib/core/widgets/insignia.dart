import 'package:flutter/material.dart';

import '../theme/tokens.dart';
import '../theme/venue_theme.dart';
import 'patron.dart' show Tono, colorDeTono;

// Quien usa una insignia necesita el tono para decir qué significa.
export 'patron.dart' show Tono;

/// El estado de algo en una palabra: Pagado, Por cobrar, Activo, Cerrado.
///
/// Había siete de estas, una por pantalla, con cuatro radios distintos, tres
/// tamaños de letra y dos pesos. Dos de ellas ni siquiera eran una insignia
/// sino texto de color suelto, así que el mismo "Pagado" era una píldora en
/// una pantalla y un texto en otra.
///
/// Esta es la única, con dos formas:
/// - la normal, una píldora con el color apenas teñido de fondo;
/// - [Insignia.texto], sin fondo, para las listas densas de la puerta, donde
///   una píldora por fila tapa más de lo que ayuda.
///
/// El color nunca va solo: la píldora lleva un punto y el texto dice qué pasa,
/// porque hay gente que no distingue el verde del rojo y en la puerta no se
/// puede adivinar.
class Insignia extends StatelessWidget {
  const Insignia(this.texto, {super.key, this.tono = Tono.ok, this.color})
    : plana = false;

  /// Sin fondo: solo el texto en color. Para filas de una lista larga.
  const Insignia.texto(this.texto, {super.key, this.tono = Tono.neutro, this.color})
    : plana = true;

  final String texto;

  /// Qué significa el estado.
  final Tono tono;

  /// Un color propio cuando el estado no entra en los tonos (el de la marca,
  /// por ejemplo). Pisa a [tono].
  final Color? color;

  final bool plana;

  @override
  Widget build(BuildContext context) {
    final c = color ??
        (tono == Tono.neutro ? VenueColors.textoSuave : colorDeTono(context, tono));
    final estilo = TextStyle(
      color: c,
      fontSize: 12,
      fontWeight: FontWeight.w600,
      height: 1.3,
    );
    if (plana) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Text(texto, style: estilo),
      );
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: Esp.sm, vertical: Esp.xs),
      decoration: BoxDecoration(
        color: tono == Tono.neutro && color == null
            ? VenueColors.superficie2
            : c.withValues(alpha: .14),
        borderRadius: BorderRadius.circular(Radio_.pildora),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(color: c, shape: BoxShape.circle),
          ),
          const SizedBox(width: Esp.xs + 2),
          Text(texto, style: estilo),
        ],
      ),
    );
  }
}
