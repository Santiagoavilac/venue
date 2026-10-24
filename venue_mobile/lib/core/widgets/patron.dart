import 'package:flutter/material.dart';

import '../theme/venue_theme.dart';

/// Piezas del patrón de pantalla: toda sección arranca con un [Encabezado],
/// sigue con [Indicador]es y usa [PillEstado] para los estados.
///
/// Criterio visual (como Fourvenues): superficies planas, sin íconos en
/// recuadros ni brillos. El dato manda: etiqueta chica gris arriba, número
/// grande abajo. El color se reserva para lo que significa algo (estados,
/// lo accionable).

/// Contexto chico en gris (la sección), título y una línea de contexto, con
/// las acciones debajo en el teléfono o a la derecha en pantallas anchas.
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
    final ancho = MediaQuery.sizeOf(context).width >= 760;
    final texto = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (etiqueta != null) ...[
          Text(
            etiqueta!,
            style: TextStyle(
                fontSize: 13, fontWeight: FontWeight.w500, color: VenueColors.textoTenue),
          ),
          const SizedBox(height: 4),
        ],
        Text(
          titulo,
          style: TextStyle(
            fontSize: ancho ? 26 : 22,
            height: 1.2,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.5,
          ),
        ),
        if (contexto != null) ...[
          const SizedBox(height: 4),
          Text(
            contexto!,
            style: TextStyle(fontSize: 14, color: VenueColors.textoSuave, height: 1.4),
          ),
        ],
      ],
    );
    final cuerpo = inicio == null
        ? texto
        : Row(children: [
            inicio!,
            const SizedBox(width: 14),
            Expanded(child: texto),
          ]);
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
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

Color colorDeTono(BuildContext context, Tono t) => switch (t) {
      Tono.ok => VenueColors.ok,
      Tono.aviso => VenueColors.aviso,
      Tono.mal => VenueColors.mal,
      Tono.marca => Theme.of(context).colorScheme.primary,
      Tono.neutro => VenueColors.textoSuave,
    };

/// Ícono de una fila o tarjeta. Va suelto, sin recuadro de color: el
/// recuadro tintado era ruido que competía con el dato.
class IconoRecuadro extends StatelessWidget {
  const IconoRecuadro(this.icono, {super.key, this.tono = Tono.neutro, this.lado = 46});

  final IconData icono;
  final Tono tono;
  final double lado;

  @override
  Widget build(BuildContext context) => SizedBox(
        width: lado * .6,
        height: lado * .6,
        child: Icon(icono, size: lado * .5, color: colorDeTono(context, tono)),
      );
}

/// Indicador: etiqueta chica y el dato grande, en una tarjeta plana. Con
/// [de] se muestra "valor / de" (ingresaron de anotados…). El [icono] se
/// conserva en la firma pero no se dibuja.
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

  /// Sin efecto: se mantiene por compatibilidad.
  final bool? horizontal;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: VenueColors.superficie,
        borderRadius: BorderRadius.circular(radioTarjeta),
        border: bordeTarjeta,
        boxShadow: sombraTarjeta,
      ),
      clipBehavior: Clip.antiAlias,
      child: Material(
      type: MaterialType.transparency,
      child: InkWell(
        onTap: alTocar,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 12, 14),
          child: Row(children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(children: [
                    if (tono != Tono.neutro) ...[
                      Container(
                        width: 7,
                        height: 7,
                        decoration: BoxDecoration(
                            color: colorDeTono(context, tono), shape: BoxShape.circle),
                      ),
                      const SizedBox(width: 6),
                    ],
                    Flexible(
                      child: Text(
                        etiqueta,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            fontSize: 13, fontWeight: FontWeight.w500, color: VenueColors.textoSuave),
                      ),
                    ),
                  ]),
                  const SizedBox(height: 6),
                  Text.rich(
                    TextSpan(children: [
                      TextSpan(text: valor),
                      if (de != null)
                        TextSpan(
                          text: ' / $de',
                          style: TextStyle(
                              fontSize: 15, fontWeight: FontWeight.w500, color: VenueColors.textoTenue),
                        ),
                    ]),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 22,
                      height: 1.1,
                      fontWeight: FontWeight.w600,
                      letterSpacing: -0.4,
                      fontFeatures: [FontFeature.tabularFigures()],
                    ),
                  ),
                  if (detalle != null) ...[
                    const SizedBox(height: 4),
                    Text(detalle!,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 12.5, color: VenueColors.textoTenue)),
                  ],
                ],
              ),
            ),
            if (alTocar != null)
              Icon(Icons.chevron_right_rounded, color: VenueColors.textoTenue, size: 20),
          ]),
        ),
      ),
      ),
    );
  }
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
      const gap = 8.0;
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
    final color = tono == Tono.neutro ? VenueColors.textoTenue : colorDeTono(context, tono);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: tono == Tono.neutro ? VenueColors.superficie2 : color.withValues(alpha: .12),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Container(
          width: 6,
          height: 6,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 6),
        Text(texto, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: color)),
      ]),
    );
  }
}

/// Tarjeta del patrón: blanca con sombra suave en claro, borde fino en oscuro.
class Tarjeta extends StatelessWidget {
  const Tarjeta({super.key, required this.child, this.padding = const EdgeInsets.all(16), this.color});

  final Widget child;
  final EdgeInsets padding;
  final Color? color;

  @override
  Widget build(BuildContext context) => Container(
        padding: padding,
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: color ?? VenueColors.superficie,
          borderRadius: BorderRadius.circular(radioTarjeta),
          border: bordeTarjeta,
          boxShadow: color == null ? sombraTarjeta : null,
        ),
        // las filas tocables de adentro necesitan un Material para el efecto
        child: Material(type: MaterialType.transparency, child: child),
      );
}

/// Título de un bloque dentro de una pantalla ("Personas", "Ventas"…), con
/// una acción opcional a la derecha.
class TituloBloque extends StatelessWidget {
  const TituloBloque(this.texto, {super.key, this.accion, this.verTodo});
  final String texto;
  final Widget? accion;

  /// Agrega el "Ver todo" a la derecha (como las apps de referencia).
  final VoidCallback? verTodo;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(2, 22, 2, 10),
        child: Row(children: [
          Expanded(
            child: Text(texto,
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700, letterSpacing: -0.3)),
          ),
          ?accion,
          if (verTodo != null)
            TextButton(
              onPressed: verTodo,
              style: TextButton.styleFrom(
                  foregroundColor: Theme.of(context).colorScheme.primary,
                  minimumSize: const Size(44, 36),
                  padding: const EdgeInsets.symmetric(horizontal: 8)),
              child: const Text('Ver todo'),
            ),
        ]),
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

/// Logo de un boliche: su imagen si la cargó; si no (o mientras carga), la
/// inicial sobre su color, plano.
class LogoClub extends StatelessWidget {
  const LogoClub({super.key, required this.inicial, this.color, this.url, this.lado = 36});

  final String inicial;
  final Color? color;
  final String? url;
  final double lado;

  @override
  Widget build(BuildContext context) {
    final fondo = color ?? Theme.of(context).colorScheme.primary;
    final radio = BorderRadius.circular(lado * .26);
    final letra = Container(
      width: lado,
      height: lado,
      alignment: Alignment.center,
      decoration: BoxDecoration(color: fondo, borderRadius: radio),
      child: Text(inicial,
          style: TextStyle(
              fontSize: lado * .44,
              fontWeight: FontWeight.w700,
              color: ThemeData.estimateBrightnessForColor(fondo) == Brightness.dark
                  ? Colors.white
                  : Colors.black)),
    );
    if (url == null || url!.isEmpty) return letra;
    return ClipRRect(
      borderRadius: radio,
      child: Container(
        width: lado,
        height: lado,
        color: VenueColors.superficie2,
        child: Image.network(
          url!,
          width: lado,
          height: lado,
          fit: BoxFit.cover,
          cacheWidth: (lado * MediaQuery.devicePixelRatioOf(context)).round(),
          errorBuilder: (_, _, _) => letra,
          frameBuilder: (_, child, frame, sync) => frame == null && !sync ? letra : child,
        ),
      ),
    );
  }
}

/// Marca del boliche activo (usa el color del tema).
class MarcaClub extends StatelessWidget {
  const MarcaClub({super.key, required this.inicial, this.logo, this.lado = 36});

  final String inicial;
  final String? logo;
  final double lado;

  @override
  Widget build(BuildContext context) => LogoClub(inicial: inicial, url: logo, lado: lado);
}

/// Un dato de [TarjetaDatos].
class Dato {
  const Dato(this.etiqueta, this.valor, {this.detalle, this.tono = Tono.neutro});
  final String etiqueta;
  final String valor;
  final String? detalle;
  final Tono tono;
}

/// Datos de a pares en una tarjeta, separados por líneas finas (como los
/// resúmenes de Fourvenues: "Ticket sales | Average ticket").
class TarjetaDatos extends StatelessWidget {
  const TarjetaDatos({super.key, required this.filas});
  final List<List<Dato>> filas;

  @override
  Widget build(BuildContext context) {
    Widget dato(Dato d) => Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(d.etiqueta,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 13, color: VenueColors.textoSuave)),
            const SizedBox(height: 4),
            Text(d.valor,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 19,
                  fontWeight: FontWeight.w600,
                  letterSpacing: -0.3,
                  color: d.tono == Tono.neutro ? null : colorDeTono(context, d.tono),
                  fontFeatures: const [FontFeature.tabularFigures()],
                )),
            if (d.detalle != null) ...[
              const SizedBox(height: 2),
              Text(d.detalle!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 12, color: VenueColors.textoTenue)),
            ],
          ]),
        );
    return Tarjeta(
      padding: EdgeInsets.zero,
      child: Column(children: [
        for (var i = 0; i < filas.length; i++) ...[
          if (i > 0) Divider(height: 1, color: VenueColors.lineaSuave),
          IntrinsicHeight(
            child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              for (var k = 0; k < filas[i].length; k++) ...[
                if (k > 0)
                  VerticalDivider(
                      width: 1, indent: 12, endIndent: 12, color: VenueColors.lineaSuave),
                Expanded(child: dato(filas[i][k])),
              ],
            ]),
          ),
        ],
      ]),
    );
  }
}

/// Filtro activo en forma de chip ("Evento: Nightfall ▾"), como el
/// "Period: Last 30 days" de Fourvenues.
class ChipFiltro extends StatelessWidget {
  const ChipFiltro({super.key, required this.etiqueta, required this.valor, this.alTocar});
  final String etiqueta;
  final String valor;
  final VoidCallback? alTocar;

  @override
  Widget build(BuildContext context) {
    final marca = Theme.of(context).colorScheme.primary;
    return Align(
      alignment: Alignment.centerLeft,
      child: Material(
        color: marca.withValues(alpha: .10),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
          side: BorderSide(color: marca.withValues(alpha: .35)),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: alTocar,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Flexible(
                child: Text.rich(
                  TextSpan(children: [
                    TextSpan(text: '$etiqueta: ', style: TextStyle(color: VenueColors.textoSuave)),
                    TextSpan(text: valor),
                  ]),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w500),
                ),
              ),
              if (alTocar != null) ...[
                const SizedBox(width: 4),
                Icon(Icons.keyboard_arrow_down_rounded, size: 18, color: VenueColors.textoSuave),
              ],
            ]),
          ),
        ),
      ),
    );
  }
}

/// Ficha de número: tinte suave del color que significa, ícono en un
/// círculo, rótulo y el número grande. Van de a cuatro en una fila
/// ([FilaFichas]).
class FichaDato extends StatelessWidget {
  const FichaDato({
    super.key,
    required this.icono,
    required this.etiqueta,
    required this.valor,
    this.color,
    this.sobreImagen = false,
    this.alTocar,
  });

  final IconData icono;
  final String etiqueta;
  final String valor;

  /// null: el de la marca del boliche.
  final Color? color;

  /// Va encima de una foto: fondo oscuro translúcido y texto blanco.
  final bool sobreImagen;
  final VoidCallback? alTocar;

  @override
  Widget build(BuildContext context) {
    final c = color ?? Theme.of(context).colorScheme.primary;
    final base = sobreImagen ? Colors.black.withValues(alpha: .45) : VenueColors.superficie;
    // el número va en el color, aclarado si el fondo es oscuro para que se lea
    final oscuro = sobreImagen || Theme.of(context).brightness == Brightness.dark;
    final tinta = oscuro ? Color.lerp(c, Colors.white, .25)! : c;
    return Material(
      color: Color.alphaBlend(c.withValues(alpha: oscuro ? .16 : .09), base),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: alTocar,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(4, 14, 4, 12),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(color: c.withValues(alpha: .16), shape: BoxShape.circle),
              child: Icon(icono, size: 21, color: tinta),
            ),
            const SizedBox(height: 8),
            Text(etiqueta,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: tinta)),
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(valor,
                  style: TextStyle(
                    fontSize: 28,
                    height: 1.15,
                    fontWeight: FontWeight.w800,
                    color: tinta,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  )),
            ),
          ]),
        ),
      ),
    );
  }
}

/// Fichas en una fila, todas del mismo ancho.
class FilaFichas extends StatelessWidget {
  const FilaFichas({super.key, required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Row(children: [
        for (var i = 0; i < children.length; i++) ...[
          if (i > 0) const SizedBox(width: 8),
          Expanded(child: children[i]),
        ],
      ]);
}


/// Saludo de arriba de la pantalla de inicio: "Hola, André".
class Saludo extends StatelessWidget {
  const Saludo({super.key, required this.nombre, this.detalle});
  final String nombre;
  final String? detalle;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(nombre.isEmpty ? 'Hola' : 'Hola, $nombre',
              style: const TextStyle(fontSize: 30, fontWeight: FontWeight.w800, letterSpacing: -0.6)),
          if (detalle != null) ...[
            const SizedBox(height: 2),
            Text(detalle!, style: TextStyle(fontSize: 16, color: VenueColors.textoSuave)),
          ],
        ]),
      );
}

/// Acceso rápido: ícono en un círculo teñido, título, una línea de qué
/// hace y la flecha a la derecha. Es para ACCIONES (no para números).
class AccionRapida extends StatelessWidget {
  const AccionRapida({
    super.key,
    required this.icono,
    required this.titulo,
    this.detalle,
    this.color,
    required this.alTocar,
  });

  final IconData icono;
  final String titulo;
  final String? detalle;
  final Color? color;
  final VoidCallback? alTocar;

  @override
  Widget build(BuildContext context) {
    final c = color ?? Theme.of(context).colorScheme.primary;
    final claro = Theme.of(context).brightness == Brightness.light;
    return Container(
      decoration: BoxDecoration(
        // un tinte muy suave del color, como las tarjetas de "Quick Access"
        color: Color.alphaBlend(c.withValues(alpha: claro ? .07 : .12), VenueColors.superficie),
        borderRadius: BorderRadius.circular(radioTarjeta),
        border: bordeTarjeta,
        boxShadow: sombraTarjeta,
      ),
      clipBehavior: Clip.antiAlias,
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          onTap: alTocar,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 6, 12),
            child: Row(children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(color: c.withValues(alpha: .16), shape: BoxShape.circle),
                child: Icon(icono, size: 22, color: c),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(titulo,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
                  if (detalle != null)
                    Text(detalle!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 12.5, color: VenueColors.textoSuave)),
                ]),
              ),
              Icon(Icons.chevron_right_rounded, size: 22, color: VenueColors.textoTenue),
            ]),
          ),
        ),
      ),
    );
  }
}

/// Accesos rápidos de a dos (o tres en pantallas anchas).
class GrillaAcciones extends StatelessWidget {
  const GrillaAcciones({super.key, required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => LayoutBuilder(builder: (context, c) {
        final cols = c.maxWidth >= 640 ? 3 : 2;
        const gap = 10.0;
        final ancho = (c.maxWidth - gap * (cols - 1)) / cols;
        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: [for (final k in children) SizedBox(width: ancho, child: k)],
        );
      });
}

/// Avance "x de y" con su barra: ingresaron de anotados, usadas de vendidas.
class BarraProgreso extends StatelessWidget {
  const BarraProgreso({
    super.key,
    required this.etiqueta,
    required this.valor,
    required this.de,
    this.color,
    this.detalle,
  });

  final String etiqueta;
  final int valor;
  final int de;
  final Color? color;
  final String? detalle;

  @override
  Widget build(BuildContext context) {
    final c = color ?? Theme.of(context).colorScheme.primary;
    final f = de <= 0 ? 0.0 : (valor / de).clamp(0.0, 1.0);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Expanded(
            child: Text(etiqueta,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w500)),
          ),
          Text.rich(
            TextSpan(children: [
              TextSpan(text: '$valor', style: const TextStyle(fontWeight: FontWeight.w700)),
              TextSpan(text: ' / $de', style: TextStyle(color: VenueColors.textoTenue)),
            ]),
            style: const TextStyle(fontSize: 14.5, fontFeatures: [FontFeature.tabularFigures()]),
          ),
        ]),
        const SizedBox(height: 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(99),
          child: LinearProgressIndicator(
            value: f,
            minHeight: 8,
            color: c,
            backgroundColor: c.withValues(alpha: .14),
          ),
        ),
        if (detalle != null) ...[
          const SizedBox(height: 4),
          Text(detalle!, style: TextStyle(fontSize: 12, color: VenueColors.textoTenue)),
        ],
      ]),
    );
  }
}
