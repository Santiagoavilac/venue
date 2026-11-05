import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/theme/venue_theme.dart';
import '../../authentication/data/sesion.dart';

/// La burbuja flota sobre el velo, así que es oscura también en modo claro.
const _burbuja = Oscuro.tarjeta;

/// Tutorial guiado del inicio (como el de MD Vinyl): una tarjeta oscura que
/// apunta a cada botón de la barra, con qué es y "Siguiente". Sale una vez
/// por persona en este teléfono; se puede volver a ver desde el perfil.

/// Cada guía se recuerda aparte: la del inicio, la de Mesas, la de Pagos. Si
/// fueran una sola clave, agregar una guía nueva obligaría a repetirle a todo
/// el mundo las que ya vio.
///
/// 'inicio' conserva la clave vieja, sin el nombre, para que a quien ya hizo
/// el recorrido de la barra no se le vuelva a aparecer.
String _clave(String uid, String guia) =>
    guia == 'inicio' ? 'venue.tutorial.v1.$uid' : 'venue.tutorial.v1.$guia.$uid';

Future<bool> tutorialVisto(String uid, [String guia = 'inicio']) async {
  try {
    return (await SharedPreferences.getInstance()).getBool(_clave(uid, guia)) ??
        false;
  } catch (_) {
    // si no se puede leer, mejor no molestar
    return true;
  }
}

Future<void> marcarTutorialVisto(String uid, [String guia = 'inicio']) async {
  try {
    await (await SharedPreferences.getInstance())
        .setBool(_clave(uid, guia), true);
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
  int _transicion = 0;

  @override
  void initState() {
    super.initState();
    _ir(0);
  }

  void _ir(int n) {
    final transicion = ++_transicion;
    // la sección de atrás cambia después de este cuadro, y se mide en el
    // siguiente, ya dibujada
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || transicion != _transicion) return;
      widget.pasos[n].alMostrar?.call();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || transicion != _transicion) return;
        _medir(n);
      });
      WidgetsBinding.instance.scheduleFrame();
    });
    WidgetsBinding.instance.scheduleFrame();
  }

  void _medir(int n) {
    if (!mounted) return;
    final caja = context.findRenderObject() as RenderBox?;
    final r = widget.pasos[n].objetivo();
    if (caja == null || r == null) {
      // un paso que no apunta a nada no puede quedarse con el agujero del
      // anterior: se ilumina lo que no corresponde
      setState(() {
        _n = n;
        _rect = null;
      });
      return;
    }
    final o = caja.globalToLocal(r.topLeft);
    setState(() { _n = n; _rect = o & r.size; });
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
        // la burbuja va sobre el velo: oscura en los dos modos
        color: _burbuja,
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
                    child: Icon(p.icono, size: 19, color: Oscuro.texto),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(p.titulo,
                        style: const TextStyle(
                            color: Oscuro.texto, fontSize: 17, fontWeight: FontWeight.w700)),
                  ),
                  if (!ultimo)
                    TextButton(
                      onPressed: widget.alTerminar,
                      style: TextButton.styleFrom(
                          foregroundColor: Oscuro.suave, minimumSize: const Size(44, 36)),
                      child: const Text('Saltar'),
                    ),
                ]),
                const SizedBox(height: 10),
                Text(p.texto,
                    style: const TextStyle(color: Oscuro.texto, fontSize: 15, height: 1.4)),
                const SizedBox(height: 14),
                Row(children: [
                  Text('${_n + 1}/${widget.pasos.length}',
                      style: const TextStyle(color: Oscuro.suave, fontSize: 13)),
                  const Spacer(),
                  if (_n > 0)
                    TextButton(
                      onPressed: () => _ir(_n - 1),
                      style: TextButton.styleFrom(foregroundColor: Oscuro.suave),
                      child: const Text('Atrás'),
                    ),
                  const SizedBox(width: 4),
                  FilledButton(
                    onPressed: _siguiente,
                    style: FilledButton.styleFrom(
                      backgroundColor: Oscuro.texto,
                      foregroundColor: Oscuro.fondo,
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
        if (r == null)
          // un paso que no apunta a nada igual tiene que verse: antes se
          // dibujaba el velo y la tarjeta no, así que la pantalla quedaba
          // negra y sin salida
          Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: margen),
              child: tarjeta,
            ),
          )
        else ...[
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
    canvas.drawPath(p, Paint()..color = Oscuro.velo);
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
    canvas.drawPath(p, Paint()..color = _burbuja);
  }

  @override
  bool shouldRepaint(_Pico old) => old.hacia != hacia;
}

/// La guía de una pantalla, la primera vez que se entra.
///
/// El tutorial de la app explicaba los cuatro botones de la barra y nada más:
/// quien abría Mesas por primera vez se encontraba un plano con cuadraditos y
/// ninguna pista de que se tocan para vender, ni de qué significan los
/// colores. Y los relacionadores con cuenta propia, que entran por otro
/// camino, no veían ningún tutorial.
///
/// Se envuelve el contenido de la pantalla y listo. Cada guía se recuerda por
/// su nombre, así que agregar una no le repite las otras a nadie.
class GuiaDePantalla extends ConsumerStatefulWidget {
  const GuiaDePantalla({
    super.key,
    required this.guia,
    required this.pasos,
    required this.child,
  });

  /// Nombre con el que se recuerda: 'mesas', 'pagos', 'accesos'…
  final String guia;

  /// Los pasos. Un paso puede no apuntar a nada: la tarjeta queda centrada.
  final List<PasoTutorial> Function() pasos;

  final Widget child;

  @override
  ConsumerState<GuiaDePantalla> createState() => _GuiaDePantallaState();
}

class _GuiaDePantallaState extends ConsumerState<GuiaDePantalla> {
  bool _mostrando = false;
  bool _consultado = false;

  Future<void> _verSiCorresponde(String uid) async {
    if (_consultado) return;
    _consultado = true;
    if (await tutorialVisto(uid, widget.guia)) return;
    if (mounted) setState(() => _mostrando = true);
  }

  @override
  Widget build(BuildContext context) {
    final uid = ref.watch(usuarioIdProvider);
    if (uid != null && !_consultado) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _verSiCorresponde(uid));
    }
    if (!_mostrando) return widget.child;
    final pasos = widget.pasos();
    if (pasos.isEmpty) return widget.child;
    return Stack(
      children: [
        widget.child,
        Positioned.fill(
          child: TutorialGuiado(
            pasos: pasos,
            alTerminar: () async {
              if (uid != null) await marcarTutorialVisto(uid, widget.guia);
              if (mounted) setState(() => _mostrando = false);
            },
          ),
        ),
      ],
    );
  }
}
