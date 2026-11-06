import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/theme/aftr_theme.dart';
import '../cuenta/cuenta_screen.dart' show aftrTerminos;

/// Los 18+ y los términos, en una sola casilla.
///
/// Una sola para las dos cosas porque las dos son obligatorias: separarlas es
/// pedir dos toques para lo mismo. Está acá y no copiada en cada pantalla
/// porque la ven las dos puertas de entrada -abrir cuenta y comprar sin
/// cuenta- y tienen que decir exactamente lo mismo.
class CasillaMayorEdad extends StatelessWidget {
  const CasillaMayorEdad({
    super.key,
    required this.valor,
    required this.alCambiar,
    this.activa = true,
  });

  final bool valor;
  final ValueChanged<bool> alCambiar;
  final bool activa;

  /// Lo que se le dice a alguien que tocó continuar sin marcarla.
  static const falta = 'Para continuar tenés que ser mayor de 18 y aceptar los términos.';

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: activa ? () => alCambiar(!valor) : null,
    borderRadius: BorderRadius.circular(12),
    child: Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Checkbox(
          value: valor,
          onChanged: activa ? (v) => alCambiar(v ?? false) : null,
          side: const BorderSide(color: Aftr.bordeFuerte, width: 1.6),
          activeColor: Aftr.acento,
          checkColor: Aftr.fondo,
        ),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Text.rich(
              TextSpan(children: [
                TextSpan(
                  text: 'Soy mayor de 18 años y acepto los ',
                  style: Aftr.cuerpo(13, c: Aftr.texto),
                ),
                TextSpan(
                  text: 'términos y condiciones',
                  style: Aftr.cuerpo(13, c: Aftr.acento, w: FontWeight.w600),
                ),
                TextSpan(text: ' de AFTR.', style: Aftr.cuerpo(13, c: Aftr.texto)),
              ]),
            ),
          ),
        ),
        IconButton(
          tooltip: 'Leer los términos',
          onPressed: () => launchUrl(
            Uri.parse(aftrTerminos),
            mode: LaunchMode.externalApplication,
          ),
          icon: const Icon(Icons.open_in_new_rounded, size: 18, color: Aftr.texto3),
        ),
      ]),
    ),
  );
}
