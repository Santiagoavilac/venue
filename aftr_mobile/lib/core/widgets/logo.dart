import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../theme/aftr_theme.dart';

/// El logo vectorizado del original (assets/logo/*.svg, potrace), en piezas
/// para poder animar cada letra por separado.

/// La marca: la A con la curva.
class MarcaAftr extends StatelessWidget {
  const MarcaAftr({super.key, this.alto = 64, this.color = Aftr.texto});

  final double alto;
  final Color color;

  static const proporcion = 496 / 403;

  @override
  Widget build(BuildContext context) => SvgPicture.asset(
        'assets/logo/marca.svg',
        height: alto,
        width: alto * proporcion,
        colorFilter: ColorFilter.mode(color, BlendMode.srcIn),
      );
}

/// Las letras de "AFTR" con su posición en el logotipo original, en unidades
/// de la altura de las letras (151 px en el original).
class LetraAftr {
  const LetraAftr(this.asset, this.x, this.ancho);
  final String asset;
  final double x;
  final double ancho;

  static const alto = 151.0;
  static const anchoTotal = 769.0;
  static const letras = [
    LetraAftr('assets/logo/a.svg', 0, 158),
    LetraAftr('assets/logo/f.svg', 234, 112),
    LetraAftr('assets/logo/t.svg', 418, 137),
    LetraAftr('assets/logo/r.svg', 627, 142),
  ];
}

/// "AFTR" armado, para la barra o el login. Cada letra se puede mover con
/// [desplazar] (0 = en su lugar).
class PalabraAftr extends StatelessWidget {
  const PalabraAftr({super.key, this.alto = 28, this.color = Aftr.texto, this.opacidades, this.desplazar});

  final double alto;
  final Color color;
  final List<double>? opacidades;
  final List<Offset>? desplazar;

  @override
  Widget build(BuildContext context) {
    final k = alto / LetraAftr.alto;
    return SizedBox(
      width: LetraAftr.anchoTotal * k,
      height: alto,
      child: Stack(clipBehavior: Clip.none, children: [
        for (var i = 0; i < LetraAftr.letras.length; i++)
          Positioned(
            left: LetraAftr.letras[i].x * k,
            top: 0,
            child: Transform.translate(
              offset: desplazar?[i] ?? Offset.zero,
              child: Opacity(
                opacity: (opacidades?[i] ?? 1).clamp(0, 1),
                child: SvgPicture.asset(
                  LetraAftr.letras[i].asset,
                  height: alto,
                  width: LetraAftr.letras[i].ancho * k,
                  colorFilter: ColorFilter.mode(color, BlendMode.srcIn),
                ),
              ),
            ),
          ),
      ]),
    );
  }
}
