import 'package:flutter/material.dart';

import '../theme/venue_theme.dart';

/// Piezas del patrón de pantalla, las mismas que en la web (pgHead, kpi,
/// pillEst en app.js): toda sección arranca con un [Encabezado], sigue con
/// [Indicador]es y usa [PillEstado] para los estados.

/// Etiqueta de sección en mayúsculas con el color del boliche, título grande,
/// una línea de contexto y las acciones (debajo en el teléfono, a la derecha
/// en pantallas anchas).
class Encabezado extends StatelessWidget {
  const Encabezado({
    super.key,
    this.etiqueta,
    required this.titulo,
    this.contexto,
    this.acciones = const [],
    this.inicio,
  });

  final String? etiqueta;
  final String titulo;
  final String? contexto;
  final List<Widget> acciones;

  /// Algo a la izquierda del texto (por ejemplo, la inicial de una persona).
  final Widget? inicio;

  @override
  Widget build(BuildContext context) {
    final marca = Theme.of(context).colorScheme.secondary;
    final ancho = MediaQuery.sizeOf(context).width >= 760;
    final texto = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (etiqueta != null) ...[
          Text(
            etiqueta!.toUpperCase(),
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w600,
              letterSpacing: 1.1,
              color: marca,
            ),
          ),
          const SizedBox(height: 6),
        ],
        Text(
          titulo,
          style: TextStyle(
            fontSize: ancho ? 30 : 26,
            height: 1.12,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.8,
          ),
        ),
        if (contexto != null) ...[
          const SizedBox(height: 6),
          Text(
            contexto!,
            style: const TextStyle(
                fontSize: 14.5, color: VenueColors.textoSuave, height: 1.4),
          ),
        ],
      ],
    );
    final cuerpo = inicio == null
        ? texto
        : Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
            inicio!,
            const SizedBox(width: 14),
            Expanded(child: texto),
          ]);
    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: ancho && acciones.isNotEmpty
          ? Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(child: cuerpo),
                const SizedBox(width: 16),
                Wrap(spacing: 10, runSpacing: 10, children: acciones),
              ],
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                cuerpo,
                if (acciones.isNotEmpty) ...[
                  const SizedBox(height: 14),
                  Row(children: [
                    for (var i = 0; i < acciones.length; i++) ...[
                      if (i > 0) const SizedBox(width: 10),
                      // la principal (la última, como en la web) ocupa el resto
                      if (i == acciones.length - 1)
                        Expanded(child: acciones[i])
                      else
                        acciones[i],
                    ],
                  ]),
                ],
              ],
            ),
    );
  }
}

/// Tono de un indicador o de un estado.
enum Tono { neutro, marca, ok, aviso, mal }

/// Recuadro con un ícono adentro: la marca visual de las tarjetas.
class IconoRecuadro extends StatelessWidget {
  const IconoRecuadro(this.icono, {super.key, this.tono = Tono.neutro, this.lado = 46});

  final IconData icono;
  final Tono tono;
  final double lado;

  @override
  Widget build(BuildContext context) {
    final marca = Theme.of(context).colorScheme.primary;
    final (fondo, borde, color) = switch (tono) {
      Tono.marca => (
          marca.withValues(alpha: .18),
          marca.withValues(alpha: .30),
          Theme.of(context).colorScheme.secondary
        ),
      Tono.ok => (VenueColors.ok.withValues(alpha: .14), Colors.transparent, VenueColors.ok),
      Tono.aviso => (
          VenueColors.aviso.withValues(alpha: .13),
          VenueColors.aviso.withValues(alpha: .32),
          VenueColors.aviso
        ),
      Tono.mal => (
          VenueColors.mal.withValues(alpha: .13),
          VenueColors.mal.withValues(alpha: .32),
          VenueColors.mal
        ),
      Tono.neutro => (VenueColors.superficie2, VenueColors.linea, VenueColors.textoSuave),
    };
    return Container(
      width: lado,
      height: lado,
      decoration: BoxDecoration(
        color: fondo,
        borderRadius: BorderRadius.circular(lado * .27),
        border: Border.all(color: borde),
      ),
      child: Icon(icono, size: lado * .46, color: color),
    );
  }
}

/// Indicador: el dato con su ícono en un recuadro. Con [de] se muestra
/// "valor / de" (ingresaron de anotados, usadas de vendidas…).
class Indicador extends StatelessWidget {
  const Indicador({
    super.key,
    required this.icono,
    required this.etiqueta,
    required this.valor,
    this.de,
    this.detalle,
    this.tono = Tono.neutro,
    this.alTocar,
    this.horizontal,
  });

  final IconData icono;
  final String etiqueta;
  final String valor;
  final String? de;
  final String? detalle;
  final Tono tono;
  final VoidCallback? alTocar;

  /// Ícono a la izquierda del texto (null: según el ancho disponible).
  final bool? horizontal;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, c) {
      final enFila = horizontal ?? c.maxWidth >= 220;
      final textos = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            etiqueta,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
                fontSize: 13.5, fontWeight: FontWeight.w500, color: VenueColors.textoSuave),
          ),
          const SizedBox(height: 4),
          Text.rich(
            TextSpan(children: [
              TextSpan(text: valor),
              if (de != null)
                TextSpan(
                  text: ' / $de',
                  style: const TextStyle(
                      fontSize: 20, fontWeight: FontWeight.w500, color: VenueColors.textoTenue),
                ),
            ]),
            style: const TextStyle(
              fontSize: 26,
              height: 1.1,
              fontWeight: FontWeight.w700,
              letterSpacing: -0.5,
              fontFeatures: [FontFeature.tabularFigures()],
            ),
          ),
          if (detalle != null) ...[
            const SizedBox(height: 4),
            Text(detalle!,
                style: const TextStyle(fontSize: 12.5, color: VenueColors.textoTenue)),
          ],
        ],
      );
      final icono_ = tono == Tono.ok
          ? const _PuntoOk()
          : IconoRecuadro(icono, tono: tono, lado: enFila ? 46 : 40);
      return Material(
        color: VenueColors.superficie,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: VenueColors.linea),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: alTocar,
          child: Padding(
            padding: EdgeInsets.all(enFila ? 18 : 15),
            child: enFila
                ? Row(children: [
                    icono_,
                    const SizedBox(width: 14),
                    Expanded(child: textos),
                    if (alTocar != null)
                      const Icon(Icons.chevron_right_rounded, color: VenueColors.textoTenue),
                  ])
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(children: [
                        icono_,
                        const Spacer(),
                        if (alTocar != null)
                          const Icon(Icons.chevron_right_rounded,
                              color: VenueColors.textoTenue, size: 20),
                      ]),
                      const SizedBox(height: 12),
                      textos,
                    ],
                  ),
          ),
        ),
      );
    });
  }
}

class _PuntoOk extends StatelessWidget {
  const _PuntoOk();

  @override
  Widget build(BuildContext context) => SizedBox(
        width: 40,
        height: 40,
        child: Center(
          child: Container(
            width: 12,
            height: 12,
            decoration: BoxDecoration(
              color: VenueColors.ok,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(color: VenueColors.ok.withValues(alpha: .25), spreadRadius: 5),
              ],
            ),
          ),
        ),
      );
}

/// Grilla de indicadores: dos columnas en el teléfono, hasta [maxColumnas]
/// en pantallas anchas.
class GrillaIndicadores extends StatelessWidget {
  const GrillaIndicadores({super.key, required this.children, this.maxColumnas = 4});

  final List<Widget> children;
  final int maxColumnas;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, c) {
      final cols = c.maxWidth >= 1000
          ? maxColumnas
          : c.maxWidth >= 640
              ? (maxColumnas < 3 ? maxColumnas : 3)
              : 2;
      const gap = 10.0;
      final ancho = (c.maxWidth - gap * (cols - 1)) / cols;
      return Wrap(
        spacing: gap,
        runSpacing: gap,
        children: [for (final k in children) SizedBox(width: ancho, child: k)],
      );
    });
  }
}

/// Estado con punto de color: Activo, Pendiente de cierre, Pausado…
class PillEstado extends StatelessWidget {
  const PillEstado(this.texto, {super.key, this.tono = Tono.ok});

  final String texto;
  final Tono tono;

  @override
  Widget build(BuildContext context) {
    final color = switch (tono) {
      Tono.ok => VenueColors.ok,
      Tono.aviso => VenueColors.aviso,
      Tono.mal => VenueColors.mal,
      Tono.marca => Theme.of(context).colorScheme.secondary,
      Tono.neutro => VenueColors.textoTenue,
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
      decoration: BoxDecoration(
        color: tono == Tono.neutro ? VenueColors.superficie2 : color.withValues(alpha: .13),
        borderRadius: BorderRadius.circular(tono == Tono.aviso ? 99 : 9),
        border: Border.all(
            color: tono == Tono.neutro ? VenueColors.linea : color.withValues(alpha: .24)),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Container(
          width: 7,
          height: 7,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 7),
        Text(texto,
            style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: color)),
      ]),
    );
  }
}

/// Tarjeta con borde fino del patrón.
class Tarjeta extends StatelessWidget {
  const Tarjeta({super.key, required this.child, this.padding = const EdgeInsets.all(20), this.color});

  final Widget child;
  final EdgeInsets padding;
  final Color? color;

  @override
  Widget build(BuildContext context) => Container(
        padding: padding,
        decoration: BoxDecoration(
          color: color ?? VenueColors.superficie,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: VenueColors.linea),
        ),
        child: child,
      );
}

/// Inicial de una persona en un círculo con un tono propio por nombre (el
/// mismo cálculo que la web, para que alguien tenga el mismo color en las dos).
class Inicial extends StatelessWidget {
  const Inicial(this.nombre, {super.key, this.lado = 42});

  final String nombre;
  final double lado;

  static const _tintes = [
    Color(0xFF7A3B2E), Color(0xFF2F3F6B), Color(0xFF4B2F6B), Color(0xFF2E5A4B),
    Color(0xFF6B5A2F), Color(0xFF5A2F4B), Color(0xFF2F5A6B),
  ];

  static Color tinte(String nm) {
    var h = 0;
    for (final c in nm.runes) {
      h = (h * 31 + c) & 0xFFFFFFFF;
    }
    return _tintes[h % _tintes.length];
  }

  @override
  Widget build(BuildContext context) {
    final t = nombre.trim();
    return Container(
      width: lado,
      height: lado,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: Color.lerp(tinte(t), Colors.black, .15),
        shape: BoxShape.circle,
      ),
      child: Text(
        t.isEmpty ? '·' : t.characters.first.toUpperCase(),
        style: TextStyle(fontSize: lado * .4, fontWeight: FontWeight.w700, color: Colors.white),
      ),
    );
  }
}

/// Marca del boliche: cuadrado redondeado con degradé de sus dos colores.
class MarcaClub extends StatelessWidget {
  const MarcaClub({super.key, required this.inicial, this.lado = 36});

  final String inicial;
  final double lado;

  @override
  Widget build(BuildContext context) {
    final esq = Theme.of(context).colorScheme;
    return Container(
      width: lado,
      height: lado,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(lado * .28),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [esq.secondary, esq.primary],
        ),
      ),
      child: Text(inicial,
          style: TextStyle(
              fontSize: lado * .45, fontWeight: FontWeight.w700, color: Colors.white)),
    );
  }
}
