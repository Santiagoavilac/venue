import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/venue_theme.dart';
import '../data/mesas.dart';

Color colorDeMesa(Mesa m, Color marca) => switch (m.estado) {
      'reservada' => VenueColors.aviso,
      'pagada' => VenueColors.ok,
      'ocupada' => marca,
      _ => VenueColors.textoSuave,
    };

/// Ancho/alto del fondo de un piso. Con fondo, el plano toma la proporción
/// de la imagen (igual que la web): el dibujo no se estira y las mesas, que
/// van en % del lienzo, caen sobre su lugar. Sin fondo, 1000:420.
final proporcionPlanoProvider =
    FutureProvider.autoDispose.family<double, String?>((ref, url) async {
  if (url == null) return Plano.proporcion;
  final c = Completer<double>();
  final stream = NetworkImage(url).resolve(ImageConfiguration.empty);
  late final ImageStreamListener l;
  l = ImageStreamListener((info, _) {
    final i = info.image;
    if (!c.isCompleted) c.complete(i.height == 0 ? Plano.proporcion : i.width / i.height);
    stream.removeListener(l);
  }, onError: (_, _) {
    if (!c.isCompleted) c.complete(Plano.proporcion);
    stream.removeListener(l);
  });
  stream.addListener(l);
  return c.future;
});

/// Plano de una planta. Las mesas se ubican en porcentajes del lienzo (la
/// misma convención de la web: x, y, w, h), sobre la proporción del fondo o,
/// sin fondo, 1000:420.
///
/// En modo [mover], cada mesa se arrastra sola (solo se redibuja esa mesa) y
/// al soltar queda en su lugar nuevo enseguida, ajustada a medios puntos; si
/// [alMover] devuelve false, vuelve a donde estaba.
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
    this.aspecto = Plano.proporcion,
  });

  final List<Mesa> mesas;
  final String planta;
  final String? fondoUrl;
  final bool mover;
  final ValueChanged<Mesa> alTocar;
  final Future<bool> Function(Mesa mesa, double x, double y)? alMover;
  final Map<String, String> teams;
  final double aspecto;

  static const proporcion = 1000 / 420;

  @override
  State<Plano> createState() => _PlanoState();
}

class _PlanoState extends State<Plano> {
  /// Posición nueva de las mesas recién soltadas, hasta que llegue del
  /// servidor (id → x,y en %). Evita que la mesa vuelva un instante a su
  /// lugar viejo mientras se recargan los datos.
  final _soltadas = <String, Offset>{};

  @override
  void didUpdateWidget(Plano viejo) {
    super.didUpdateWidget(viejo);
    // ya llegó la posición nueva: se suelta la provisoria
    _soltadas.removeWhere((id, p) {
      final m = widget.mesas.where((x) => x.id == id).firstOrNull;
      return m == null || (m.x == p.dx && m.y == p.dy);
    });
  }

  Future<void> _soltar(Mesa m, double x, double y) async {
    setState(() => _soltadas[m.id] = Offset(x, y));
    final ok = await widget.alMover?.call(m, x, y) ?? false;
    if (!ok && mounted) setState(() => _soltadas.remove(m.id));
  }

  @override
  Widget build(BuildContext context) {
    final marca = Theme.of(context).colorScheme.primary;
    final oscuro = Theme.of(context).brightness == Brightness.dark;
    return AspectRatio(
      aspectRatio: widget.aspecto,
      child: LayoutBuilder(builder: (context, c) {
        final ancho = c.maxWidth, alto = c.maxHeight;
        return DecoratedBox(
          decoration: BoxDecoration(
            color: oscuro ? VenueColors.superficie2 : const Color(0xFFF2F4F7),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: VenueColors.lineaSuave),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(15),
            child: Stack(
              children: [
                if (widget.fondoUrl != null)
                  // el dibujo del local es claro con líneas oscuras: en modo
                  // claro queda tenue; en oscuro se invierte
                  Positioned.fill(
                    child: RepaintBoundary(
                      child: Opacity(
                        opacity: oscuro ? .35 : .55,
                        child: ColorFiltered(
                          colorFilter: oscuro ? _invertirGris : _gris,
                          child: Image.network(widget.fondoUrl!,
                              fit: BoxFit.fill,
                              gaplessPlayback: true,
                              errorBuilder: (_, _, _) => const SizedBox.shrink()),
                        ),
                      ),
                    ),
                  )
                else
                  Center(
                    child: Text(
                      nombrePiso(widget.planta).toUpperCase(),
                      style: TextStyle(
                        color: VenueColors.texto.withValues(alpha: .05),
                        fontSize: alto * .22,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                for (final m in widget.mesas)
                  _MesaEnPlano(
                    key: ValueKey(m.id),
                    mesa: m,
                    posicion: _soltadas[m.id] ?? Offset(m.x, m.y),
                    ancho: ancho,
                    alto: alto,
                    marca: marca,
                    team: widget.teams[m.teamId],
                    mover: widget.mover,
                    alTocar: widget.alTocar,
                    alSoltar: _soltar,
                  ),
              ],
            ),
          ),
        );
      }),
    );
  }
}

const _gris = ColorFilter.matrix(<double>[
  .33, .33, .33, 0, 0, //
  .33, .33, .33, 0, 0, //
  .33, .33, .33, 0, 0, //
  0, 0, 0, 1, 0,
]);
const _invertirGris = ColorFilter.matrix(<double>[
  -.33, -.33, -.33, 0, 255, //
  -.33, -.33, -.33, 0, 255, //
  -.33, -.33, -.33, 0, 255, //
  0, 0, 0, 1, 0,
]);

/// Una mesa del plano. Mientras se arrastra solo se mueve ella (con
/// Transform, sin recalcular el resto) y sigue al dedo sin saltos; el ajuste
/// a la grilla se hace al soltar.
class _MesaEnPlano extends StatefulWidget {
  const _MesaEnPlano({
    super.key,
    required this.mesa,
    required this.posicion,
    required this.ancho,
    required this.alto,
    required this.marca,
    required this.mover,
    required this.alTocar,
    required this.alSoltar,
    this.team,
  });

  final Mesa mesa;
  final Offset posicion;
  final double ancho, alto;
  final Color marca;
  final String? team;
  final bool mover;
  final ValueChanged<Mesa> alTocar;
  final void Function(Mesa mesa, double x, double y) alSoltar;

  @override
  State<_MesaEnPlano> createState() => _MesaEnPlanoState();
}

class _MesaEnPlanoState extends State<_MesaEnPlano> {
  Offset _d = Offset.zero; // desplazamiento en píxeles mientras se arrastra
  bool _arrastrando = false;

  Offset _acotar(Offset d) {
    final m = widget.mesa, p = widget.posicion;
    final minX = (0.5 - p.dx) / 100 * widget.ancho, maxX = (99 - m.w - p.dx) / 100 * widget.ancho;
    final minY = (0.5 - p.dy) / 100 * widget.alto, maxY = (86 - p.dy) / 100 * widget.alto;
    return Offset(d.dx.clamp(minX, maxX < minX ? minX : maxX), d.dy.clamp(minY, maxY < minY ? minY : maxY));
  }

  @override
  Widget build(BuildContext context) {
    final m = widget.mesa;
    final w = widget.ancho * m.w / 100;
    final h = widget.alto * (m.h ?? 21) / 100;
    final estado = m.libre ? null : colorDeMesa(m, widget.marca);
    final nombre = m.libre ? 'Libre' : (m.cliente ?? '').trim();
    final team = widget.team;

    final cuerpo = AnimatedContainer(
      duration: const Duration(milliseconds: 120),
      width: w,
      height: h,
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      decoration: BoxDecoration(
        color: estado == null
            ? VenueColors.superficie.withValues(alpha: .9)
            : Color.alphaBlend(estado.withValues(alpha: .15), VenueColors.superficie),
        borderRadius: BorderRadius.circular(m.esLounge ? 14 : 10),
        border: Border.all(
          color: m.porVerificar ? VenueColors.aviso : estado ?? VenueColors.linea,
          width: estado == null ? 1.2 : 1.6,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: _arrastrando ? .28 : .10),
            blurRadius: _arrastrando ? 22 : 8,
            offset: Offset(0, _arrastrando ? 10 : 3),
          ),
          if (_arrastrando) BoxShadow(color: widget.marca, spreadRadius: 2),
        ],
      ),
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(m.etiqueta,
                style: TextStyle(
                    color: VenueColors.texto, fontWeight: FontWeight.w800, fontSize: 15, height: 1.1)),
            if (nombre.isNotEmpty)
              Text(nombre,
                  maxLines: 1,
                  style: TextStyle(
                      color: m.libre ? VenueColors.textoSuave : VenueColors.texto,
                      fontWeight: m.libre ? FontWeight.w500 : FontWeight.w600,
                      fontSize: 10.5)),
          ],
        ),
      ),
    );

    return Positioned(
      left: widget.ancho * widget.posicion.dx / 100,
      top: widget.alto * widget.posicion.dy / 100,
      child: Transform.translate(
        offset: _d,
        child: Semantics(
          button: true,
          label: '${m.tipo.nombre} ${m.etiqueta}, '
              '${etiquetaEstado[m.estado] ?? m.estado}'
              '${nombre.isEmpty || m.libre ? '' : ', $nombre'}',
          child: GestureDetector(
            // cuenta desde donde se apoyó el dedo: si no, la mesa queda atrás
            // del dedo lo que tarda en reconocerse el arrastre
            dragStartBehavior: DragStartBehavior.down,
            onTap: () => widget.alTocar(m),
            onPanStart: widget.mover ? (_) => setState(() => _arrastrando = true) : null,
            onPanUpdate: widget.mover ? (d) => setState(() => _d = _acotar(_d + d.delta)) : null,
            onPanEnd: widget.mover
                ? (_) {
                    final d = _d;
                    setState(() {
                      _d = Offset.zero;
                      _arrastrando = false;
                    });
                    if (d == Offset.zero) return;
                    final p = acotarPosicion(widget.posicion.dx + d.dx / widget.ancho * 100,
                        widget.posicion.dy + d.dy / widget.alto * 100, m.w);
                    if (p.x != m.x || p.y != m.y) widget.alSoltar(m, p.x, p.y);
                  }
                : null,
            onPanCancel: widget.mover
                ? () => setState(() {
                      _d = Offset.zero;
                      _arrastrando = false;
                    })
                : null,
            child: Stack(clipBehavior: Clip.none, children: [
              RepaintBoundary(child: cuerpo),
              if (team != null)
                Positioned(
                  top: -7,
                  left: -6,
                  child: CircleAvatar(
                    radius: 9,
                    backgroundColor: VenueColors.aviso,
                    child: Text(
                      team.replaceFirst('Team ', '').characters.first.toUpperCase(),
                      style: const TextStyle(fontSize: 9.5, color: Colors.black, fontWeight: FontWeight.w800),
                    ),
                  ),
                ),
            ]),
          ),
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
          Text(t, style: TextStyle(fontSize: 12.5, color: VenueColors.textoSuave)),
        ]);
    return Wrap(spacing: 14, runSpacing: 4, children: [
      item('Libre', VenueColors.textoSuave),
      item('Reservada', VenueColors.aviso),
      item('Pagada', VenueColors.ok),
      item('Ocupada', marca),
    ]);
  }
}
