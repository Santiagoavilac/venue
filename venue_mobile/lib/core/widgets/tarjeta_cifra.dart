
import 'package:flutter/material.dart';

import '../theme/tokens.dart';
import '../theme/venue_theme.dart';
import 'patron.dart' show Tono, colorDeTono;

/// Una tarjeta con un número: cuántos entraron, cuánto se vendió, cuánto falta
/// rendir.
///
/// Había cinco de estas, una por pantalla (`Indicador`, `FichaDato`, `_Dato`
/// de Accesos, `_Cifra` del relacionador y la del reporte), cada una con su
/// tamaño de letra, su gris y su relleno. El mismo dato se veía distinto según
/// dónde se mirara. Esta es la única.
///
/// Todo es opcional menos la etiqueta y el valor:
/// - [de] escribe "12 / 40" cuando el número es parte de un total.
/// - [detalle] es la línea de apoyo de abajo.
/// - [icono] y [tono] marcan la fila de la etiqueta; el tono también pinta la
///   cifra, así que no hace falta pasar [color] salvo que sea un color que no
///   significa un estado.
/// - [sobreImagen] la pone sobre la foto de un evento: fondo oscuro y texto
///   claro, porque debajo hay una foto y no el fondo de la app.
class TarjetaCifra extends StatelessWidget {
  const TarjetaCifra({
    super.key,
    required this.etiqueta,
    required this.valor,
    this.de,
    this.sufijo,
    this.detalle,
    this.icono,
    this.tono = Tono.neutro,
    this.color,
    this.sobreImagen = false,
    this.alTocar,
  });

  final String etiqueta;
  final String valor;

  /// El total del que [valor] es parte: "12 / 40".
  final String? de;

  /// Lo que va pegado al número sin ser parte de él: " Bs", " %".
  final String? sufijo;

  /// Línea de apoyo debajo de la cifra.
  final String? detalle;

  /// Ícono chico al lado de la etiqueta.
  final IconData? icono;

  /// Qué significa el número. Pinta el punto y la cifra.
  final Tono tono;

  /// Color de la cifra cuando no es cuestión de estado. Pisa a [tono].
  final Color? color;

  /// Va encima de una foto.
  final bool sobreImagen;

  final VoidCallback? alTocar;

  @override
  Widget build(BuildContext context) {
    final tinta = sobreImagen ? Oscuro.texto : VenueColors.texto;
    final suave = sobreImagen ? Oscuro.suave : VenueColors.textoSuave;
    final tenue = sobreImagen ? Oscuro.suave : VenueColors.textoTenue;
    final deTono = tono == Tono.neutro ? null : colorDeTono(context, tono);
    final cifra = color ?? deTono ?? tinta;

    final contenido = Padding(
      padding: const EdgeInsets.fromLTRB(Esp.lg, Esp.md, Esp.md, Esp.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              if (icono != null) ...[
                Icon(icono, size: 16, color: deTono ?? suave),
                const SizedBox(width: Esp.xs + 2),
              ] else if (deTono != null) ...[
                Container(
                  width: 7,
                  height: 7,
                  decoration: BoxDecoration(
                    color: deTono,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: Esp.xs + 2),
              ],
              Expanded(
                child: Text(
                  etiqueta,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Tipo.apoyo.copyWith(
                    color: suave,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              if (alTocar != null)
                Icon(Icons.chevron_right_rounded, size: 20, color: tenue),
            ],
          ),
          const SizedBox(height: Esp.xs + 2),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text.rich(
              TextSpan(
                children: [
                  TextSpan(text: valor),
                  if (de != null)
                    TextSpan(
                      text: ' / $de',
                      style: Tipo.fila.copyWith(color: tenue),
                    )
                  else if (sufijo != null)
                    TextSpan(
                      text: sufijo,
                      style: Tipo.fila.copyWith(color: tenue),
                    ),
                ],
              ),
              maxLines: 1,
              style: Tipo.cifraChica.copyWith(
                color: cifra,
                letterSpacing: -0.4,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ),
          if (detalle != null) ...[
            const SizedBox(height: Esp.xs),
            Text(
              detalle!,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: Tipo.apoyo.copyWith(fontSize: 12.5, color: tenue),
            ),
          ],
        ],
      ),
    );

    return Container(
      decoration: BoxDecoration(
        color: sobreImagen
            ? Oscuro.fondo.withValues(alpha: .45)
            : VenueColors.superficie,
        borderRadius: BorderRadius.circular(Radio_.tarjeta),
        border: sobreImagen ? null : bordeTarjeta,
        boxShadow: sobreImagen ? const [] : sombraTarjeta,
      ),
      clipBehavior: Clip.antiAlias,
      child: alTocar == null
          ? contenido
          : Material(
              type: MaterialType.transparency,
              child: InkWell(onTap: alTocar, child: contenido),
            ),
    );
  }
}

/// Varias [TarjetaCifra] del mismo ancho, una al lado de la otra. En el
/// teléfono entran dos por fila; en pantallas anchas, hasta [maxColumnas].
class GrillaCifras extends StatelessWidget {
  const GrillaCifras({super.key, required this.children, this.maxColumnas = 4});

  final List<Widget> children;
  final int maxColumnas;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, c) {
      final cols = c.maxWidth >= 1000
          ? maxColumnas
          : c.maxWidth >= 640
          ? (maxColumnas < 3 ? maxColumnas : 3)
          : 2;
      final ancho = (c.maxWidth - Esp.sm * (cols - 1)) / cols;
      return Wrap(
        spacing: Esp.sm,
        runSpacing: Esp.sm,
        children: [for (final k in children) SizedBox(width: ancho, child: k)],
      );
    },
  );
}
