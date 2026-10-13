import 'package:flutter/material.dart';

import '../../../core/theme/venue_theme.dart';
import '../data/mesas.dart';

Color colorDeMesa(Mesa m, Color marca) => switch (m.estado) {
      'reservada' => VenueColors.aviso,
      'pagada' => VenueColors.ok,
      'ocupada' => marca,
      _ => VenueColors.textoSuave,
    };

/// Plano de una planta. Las mesas se ubican en porcentajes del lienzo (la
/// misma convención de la web: x, y, w, h), sobre una proporción 1000:420.
///
/// En modo [mover], cada mesa se arrastra; al soltar se informa la posición
/// nueva ya acotada y ajustada a medios puntos.
class Plano extends StatefulWidget {
  const Plano({
    super.key,
    required this.mesas,
    required this.planta,
    required this.alTocar,
    this.fondoUrl,
    this.mover = false,
    this.alMover,
    this.teams = const {},
  });

  final List<Mesa> mesas;
  final String planta;
  final String? fondoUrl;
  final bool mover;
  final ValueChanged<Mesa> alTocar;
  final void Function(Mesa mesa, double x, double y)? alMover;
  final Map<String, String> teams;

  static const proporcion = 1000 / 420;

  @override
  State<Plano> createState() => _PlanoState();
}

class _PlanoState extends State<Plano> {
  /// Posiciones en curso mientras se arrastra (id → x,y en %).
  final _arrastre = <String, Offset>{};

  @override
  Widget build(BuildContext context) {
    final marca = Theme.of(context).colorScheme.primary;
    return AspectRatio(
      aspectRatio: Plano.proporcion,
      child: LayoutBuilder(builder: (context, c) {
        final ancho = c.maxWidth, alto = c.maxHeight;
        return DecoratedBox(
          decoration: BoxDecoration(
            color: const Color(0xFF14141E),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: VenueColors.linea, width: 2),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(14),
            child: Stack(
              children: [
                if (widget.fondoUrl != null)
                  Positioned.fill(
                    child: Image.network(widget.fondoUrl!,
                        fit: BoxFit.fill,
                        errorBuilder: (_, _, _) => const SizedBox.shrink()),
                  )
                else
                  Center(
                    child: Text(
                      (etiquetaPiso[widget.planta] ?? widget.planta).toUpperCase(),
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: .06),
                        fontSize: alto * .22,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                for (final m in widget.mesas)
                  _chip(m, ancho, alto, marca),
              ],
            ),
          ),
        );
      }),
    );
  }

  Widget _chip(Mesa m, double ancho, double alto, Color marca) {
    final pos = _arrastre[m.id] ?? Offset(m.x, m.y);
    final w = ancho * m.w / 100;
    final h = alto * (m.h ?? 21) / 100;
    final color = colorDeMesa(m, marca);
    final nombre = m.libre ? 'Libre' : (m.cliente ?? '').trim();
    final team = widget.teams[m.teamId];

    final cuerpo = Container(
      width: w,
      height: h,
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      decoration: BoxDecoration(
        color: m.libre ? const Color(0xFF1F1F2B) : color.withValues(alpha: .38),
        borderRadius: BorderRadius.circular(m.esLounge ? 14 : 9),
        border: Border.all(
          color: m.porVerificar ? VenueColors.aviso : color.withValues(alpha: m.libre ? .5 : 1),
          width: m.porVerificar ? 2.2 : 1.4,
        ),
      ),
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(m.etiqueta,
                style: const TextStyle(
                    color: Colors.white, fontWeight: FontWeight.w800, fontSize: 13)),
            if (nombre.isNotEmpty)
              Text(nombre,
                  maxLines: 1,
                  style: TextStyle(
                      color: Colors.white.withValues(alpha: m.libre ? .5 : .95),
                      fontSize: 10.5)),
          ],
        ),
      ),
    );

    return Positioned(
      left: ancho * pos.dx / 100,
      top: alto * pos.dy / 100,
      child: Semantics(
        button: true,
        label: '${m.esLounge ? 'Lounge' : 'Mesa'} ${m.etiqueta}, '
            '${etiquetaEstado[m.estado] ?? m.estado}'
            '${nombre.isEmpty || m.libre ? '' : ', $nombre'}',
        child: GestureDetector(
          onTap: () => widget.alTocar(m),
          onPanUpdate: widget.mover
              ? (d) => setState(() {
                    final a = _arrastre[m.id] ?? Offset(m.x, m.y);
                    final p = acotarPosicion(a.dx + d.delta.dx / ancho * 100,
                        a.dy + d.delta.dy / alto * 100, m.w);
                    _arrastre[m.id] = Offset(p.x, p.y);
                  })
              : null,
          onPanEnd: widget.mover
              ? (_) {
                  final p = _arrastre.remove(m.id);
                  if (p != null && (p.dx != m.x || p.dy != m.y)) {
                    widget.alMover?.call(m, p.dx, p.dy);
                  }
                }
              : null,
          child: Stack(clipBehavior: Clip.none, children: [
            cuerpo,
            if (team != null)
              Positioned(
                top: -7,
                left: -6,
                child: CircleAvatar(
                  radius: 9,
                  backgroundColor: VenueColors.aviso,
                  child: Text(
                    team.replaceFirst('Team ', '').characters.first.toUpperCase(),
                    style: const TextStyle(
                        fontSize: 9.5, color: Colors.black, fontWeight: FontWeight.w800),
                  ),
                ),
              ),
          ]),
        ),
      ),
    );
  }
}

class LeyendaPlano extends StatelessWidget {
  const LeyendaPlano({super.key});

  @override
  Widget build(BuildContext context) {
    final marca = Theme.of(context).colorScheme.primary;
    Widget item(String t, Color c) => Row(mainAxisSize: MainAxisSize.min, children: [
          Container(
              width: 12,
              height: 12,
              decoration: BoxDecoration(
                  color: c.withValues(alpha: .5), borderRadius: BorderRadius.circular(3))),
          const SizedBox(width: 5),
          Text(t, style: const TextStyle(fontSize: 12.5, color: VenueColors.textoSuave)),
        ]);
    return Wrap(spacing: 14, runSpacing: 4, children: [
      item('Libre', VenueColors.textoSuave),
      item('Reservada', VenueColors.aviso),
      item('Pagada', VenueColors.ok),
      item('Ocupada', marca),
    ]);
  }
}
