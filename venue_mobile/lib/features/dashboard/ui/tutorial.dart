import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Tutorial guiado del inicio (como el de MD Vinyl): una tarjeta oscura que
/// apunta a cada botón de la barra, con qué es y "Siguiente". Sale una vez
/// por persona en este teléfono; se puede volver a ver desde el perfil.

String _clave(String uid) => 'venue.tutorial.v1.$uid';

Future<bool> tutorialVisto(String uid) async {
  try {
    return (await SharedPreferences.getInstance()).getBool(_clave(uid)) ?? false;
  } catch (_) {
    // si no se puede leer, mejor no molestar
    return true;
  }
}

Future<void> marcarTutorialVisto(String uid) async {
  try {
    await (await SharedPreferences.getInstance()).setBool(_clave(uid), true);
  } catch (_) {
    // vale igual para esta sesión
  }
}

/// Pedido de volver a ver el tutorial (desde el panel de perfil). Cada
/// pedido suma uno; el shell escucha el cambio.
class TutorialPedido extends Notifier<int> {
  @override
  int build() => 0;

  void pedir() => state++;
}

final tutorialPedidoProvider = NotifierProvider<TutorialPedido, int>(TutorialPedido.new);

/// Un paso: a qué apunta (en coordenadas de pantalla) y qué dice.
class PasoTutorial {
  const PasoTutorial({
    required this.icono,
    required this.titulo,
    required this.texto,
    required this.objetivo,
    this.alMostrar,
  });
  final IconData icono;
  final String titulo;
  final String texto;
  final Rect? Function() objetivo;

  /// Lo que pasa detrás al llegar a este paso (abrir esa sección).
  final VoidCallback? alMostrar;
}

class TutorialGuiado extends StatefulWidget {
  const TutorialGuiado({super.key, required this.pasos, required this.alTerminar});
  final List<PasoTutorial> pasos;
  final VoidCallback alTerminar;

  @override
  State<TutorialGuiado> createState() => _TutorialGuiadoState();
}

class _TutorialGuiadoState extends State<TutorialGuiado> {
  int _n = 0;
  Rect? _rect;

  @override
  void initState() {
    super.initState();
    _ir(0);
  }

  void _ir(int n) {
    setState(() {
      _n = n;
      _rect = null;
    });
    // la sección de atrás cambia después de este cuadro, y se mide en el
    // siguiente, ya dibujada
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      widget.pasos[n].alMostrar?.call();
      WidgetsBinding.instance.addPostFrameCallback((_) => _medir());
    });
  }

  void _medir() {
    if (!mounted) return;
    final caja = context.findRenderObject() as RenderBox?;
    final r = widget.pasos[_n].objetivo();
    if (caja == null || r == null) return;
    final o = caja.globalToLocal(r.topLeft);
    setState(() => _rect = o & r.size);
  }

  void _siguiente() => _n + 1 < widget.pasos.length ? _ir(_n + 1) : widget.alTerminar();

  @override
  Widget build(BuildContext context) {
    final p = widget.pasos[_n];
    final marca = Theme.of(context).colorScheme.primary;
    final ultimo = _n == widget.pasos.length - 1;
    return LayoutBuilder(builder: (context, c) {
      final r = _rect;
      // la tarjeta va del lado donde hay lugar
      final abajo = r != null && r.center.dy > c.maxHeight / 2;
      const margen = 16.0, pico = 10.0;

      final tarjeta = Material(
        color: const Color(0xF21B2230),
        borderRadius: BorderRadius.circular(20),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 14, 14, 14),
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 180),
            child: Column(
              key: ValueKey(_n),
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  Container(
                    width: 34,
                    height: 34,
                    decoration: BoxDecoration(color: marca, shape: BoxShape.circle),
                    child: Icon(p.icono, size: 19, color: Colors.white),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(p.titulo,
                        style: const TextStyle(
                            color: Colors.white, fontSize: 17, fontWeight: FontWeight.w700)),
                  ),
                  if (!ultimo)
                    TextButton(
                      onPressed: widget.alTerminar,
                      style: TextButton.styleFrom(
                          foregroundColor: Colors.white70, minimumSize: const Size(44, 36)),
                      child: const Text('Saltar'),
                    ),
                ]),
                const SizedBox(height: 10),
                Text(p.texto,
                    style: TextStyle(
                        color: Colors.white.withValues(alpha: .86), fontSize: 15, height: 1.4)),
                const SizedBox(height: 14),
                Row(children: [
                  Text('${_n + 1}/${widget.pasos.length}',
                      style: const TextStyle(color: Colors.white54, fontSize: 13)),
                  const Spacer(),
                  if (_n > 0)
                    TextButton(
                      onPressed: () => _ir(_n - 1),
                      style: TextButton.styleFrom(foregroundColor: Colors.white70),
                      child: const Text('Atrás'),
                    ),
                  const SizedBox(width: 4),
                  // colores fijos: el tema pinta los botones para fondo claro
                  FilledButton(
                    onPressed: _siguiente,
                    style: FilledButton.styleFrom(
                      backgroundColor: Colors.white,
                      foregroundColor: const Color(0xFF1B2230),
                      shape: const StadiumBorder(),
                      minimumSize: const Size(0, 44),
                      padding: const EdgeInsets.symmetric(horizontal: 22),
                    ),
                    child: Text(ultimo ? 'Listo' : 'Siguiente',
                        style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                  ),
                ]),
              ],
            ),
          ),
        ),
      );

      // el piquito apunta al centro del botón
      final xPico = r == null
          ? c.maxWidth / 2
          : r.center.dx.clamp(margen + 24, c.maxWidth - margen - 24).toDouble();
      final piquito = Positioned(
        left: xPico - pico,
        top: r == null || abajo ? null : r.bottom + 6,
        bottom: r != null && abajo ? c.maxHeight - r.top + 6 : null,
        child: CustomPaint(
          size: const Size(pico * 2, pico),
          painter: _Pico(hacia: abajo ? AxisDirection.down : AxisDirection.up),
        ),
      );

      return Stack(children: [
        // todo oscurecido menos el botón del paso; los toques no pasan
        Positioned.fill(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () {},
            child: CustomPaint(painter: _Velo(r)),
          ),
        ),
        if (r != null) ...[
          piquito,
          Positioned(
            left: margen,
            right: margen,
            top: abajo ? null : r.bottom + 6 + pico - 1,
            bottom: abajo ? c.maxHeight - r.top + 6 + pico - 1 : null,
            child: tarjeta,
          ),
        ],
      ]);
    });
  }
}

class _Velo extends CustomPainter {
  _Velo(this.hueco);
  final Rect? hueco;

  @override
  void paint(Canvas canvas, Size size) {
    final todo = Path()..addRect(Offset.zero & size);
    final p = hueco == null
        ? todo
        : Path.combine(
            PathOperation.difference,
            todo,
            Path()..addRRect(RRect.fromRectAndRadius(hueco!.inflate(4), const Radius.circular(16))),
          );
    canvas.drawPath(p, Paint()..color = Colors.black.withValues(alpha: .62));
  }

  @override
  bool shouldRepaint(_Velo old) => old.hueco != hueco;
}

class _Pico extends CustomPainter {
  _Pico({required this.hacia});
  final AxisDirection hacia;

  @override
  void paint(Canvas canvas, Size s) {
    final p = hacia == AxisDirection.down
        ? (Path()
          ..moveTo(0, 0)
          ..lineTo(s.width, 0)
          ..lineTo(s.width / 2, s.height)
          ..close())
        : (Path()
          ..moveTo(0, s.height)
          ..lineTo(s.width, s.height)
          ..lineTo(s.width / 2, 0)
          ..close());
    canvas.drawPath(p, Paint()..color = const Color(0xF21B2230));
  }

  @override
  bool shouldRepaint(_Pico old) => old.hacia != hacia;
}
