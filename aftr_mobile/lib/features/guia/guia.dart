import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/theme/aftr_theme.dart';

final destinosGuia = List.generate(4, (_) => GlobalKey());
final pulseGuia = GlobalKey();

Future<bool> guiaVista(String uid) async =>
    (await SharedPreferences.getInstance()).getBool('aftr.guia.v1.$uid') ??
    false;
Future<void> guardarGuiaVista(String uid) async =>
    (await SharedPreferences.getInstance()).setBool('aftr.guia.v1.$uid', true);

class PedidoGuia extends Notifier<int> {
  @override
  int build() => 0;
  void abrir() => state++;
}

final pedidoGuiaProvider = NotifierProvider<PedidoGuia, int>(PedidoGuia.new);

class PasoAftr {
  const PasoAftr(this.titulo, this.texto, this.destino, this.ruta);
  final String titulo, texto, ruta;
  final GlobalKey destino;
}

List<PasoAftr> get pasosAftr => [
  PasoAftr(
    'Descubrir',
    'Buscá eventos por fecha y abrí uno para ver entradas, listas y mesas.',
    destinosGuia[0],
    '/',
  ),
  PasoAftr(
    'Mapa',
    'Encontrá los lugares y eventos cerca tuyo.',
    destinosGuia[1],
    '/mapa',
  ),
  PasoAftr(
    'Accesos y mesas',
    'Tus entradas y QR quedan acá. Desde Mi mesa podés ver la carta y seguir tus pedidos.',
    destinosGuia[2],
    '/accesos',
  ),
  PasoAftr(
    'Tu saldo PULSE',
    'Tu saldo queda siempre a la vista. Tocá acá para recargar o ver tus movimientos. También podés pagar con QR directo.',
    pulseGuia,
    '/accesos',
  ),
  PasoAftr(
    'Cuenta',
    'Cambiá tu foto, consultá tus guardados o volvé a ver esta guía desde Cuenta.',
    destinosGuia[3],
    '/cuenta',
  ),
];

/// Guía sobre los controles reales, con los colores de AFTR y texto sencillo.
class GuiaAftr extends StatefulWidget {
  const GuiaAftr({
    super.key,
    required this.alTerminar,
    required this.alMostrar,
  });
  final VoidCallback alTerminar;
  final ValueChanged<String> alMostrar;
  @override
  State<GuiaAftr> createState() => _GuiaAftrState();
}

class _GuiaAftrState extends State<GuiaAftr> {
  final _pasos = pasosAftr;
  int _paso = 0;
  Rect? _objetivo;
  int _transicion = 0;

  @override
  void initState() {
    super.initState();
    _mostrar(0);
  }

  void _mostrar(int n) {
    final transicion = ++_transicion;
    // Keep the current card and spotlight until the next target is laid out.
    // Clearing the target briefly moved the entire card to the opposite edge.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || transicion != _transicion) return;
      widget.alMostrar(_pasos[n].ruta);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || transicion != _transicion) return;
        final caja =
            _pasos[n].destino.currentContext?.findRenderObject() as RenderBox?;
        final contenedor = context.findRenderObject() as RenderBox?;
        if (caja?.hasSize == true && contenedor?.hasSize == true) {
          setState(
            () {
              _paso = n;
              _objetivo = contenedor!.globalToLocal(caja!.localToGlobal(Offset.zero)) & caja.size;
            },
          );
        } else {
          setState(() => _paso = n);
        }
      });
      WidgetsBinding.instance.scheduleFrame();
    });
    WidgetsBinding.instance.scheduleFrame();
  }

  @override
  Widget build(BuildContext context) => BlockSemantics(
    child: Material(
      color: Colors.transparent,
      child: LayoutBuilder(
        builder: (context, c) {
          final r = _objetivo;
          final arriba = r == null || r.center.dy < c.maxHeight / 2;
          return Stack(
            children: [
              Positioned.fill(
                child: GestureDetector(
                  onTap: () {},
                  child: CustomPaint(painter: _VeloGuia(r)),
                ),
              ),
              Positioned(
                left: 20,
                right: 20,
                top: arriba
                    ? (r?.bottom ?? MediaQuery.paddingOf(context).top) + 16
                    : null,
                bottom: arriba ? null : c.maxHeight - r.top + 16,
                child: ConstrainedBox(
                  constraints: BoxConstraints(maxHeight: c.maxHeight * .65),
                  child: Material(
                    color: Aftr.superficie,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                      side: const BorderSide(color: Aftr.bordeFuerte),
                    ),
                    child: SingleChildScrollView(
                      child: Padding(
                        padding: const EdgeInsets.all(20),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Row(
                              children: [
                                Text(
                                  '${_paso + 1} de ${_pasos.length}',
                                  style: Aftr.cuerpo(12),
                                ),
                                const Spacer(),
                                TextButton(
                                  onPressed: widget.alTerminar,
                                  child: const Text('Omitir'),
                                ),
                              ],
                            ),
                            Text(_pasos[_paso].titulo, style: Aftr.fuerte(21)),
                            const SizedBox(height: 10),
                            Text(
                              _pasos[_paso].texto,
                              style: Aftr.cuerpo(15, c: Aftr.texto2),
                            ),
                            const SizedBox(height: 18),
                            Row(
                              children: [
                                if (_paso > 0)
                                  TextButton(
                                    onPressed: () => _mostrar(_paso - 1),
                                    child: const Text('Atrás'),
                                  ),
                                const Spacer(),
                                TextButton(
                                  onPressed: () => _paso + 1 == _pasos.length
                                      ? widget.alTerminar()
                                      : _mostrar(_paso + 1),
                                  child: Text(
                                    _paso + 1 == _pasos.length
                                        ? 'Empezar'
                                        : 'Siguiente',
                                    style: Aftr.fuerte(15),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    ),
  );
}

class _VeloGuia extends CustomPainter {
  _VeloGuia(this.objetivo);
  final Rect? objetivo;
  @override
  void paint(Canvas canvas, Size size) {
    var p = Path()..addRect(Offset.zero & size);
    if (objetivo != null) {
      p = Path.combine(
        PathOperation.difference,
        p,
        Path()..addRRect(
          RRect.fromRectAndRadius(
            objetivo!.inflate(3),
            const Radius.circular(6),
          ),
        ),
      );
    }
    canvas.drawPath(p, Paint()..color = Colors.black.withValues(alpha: .75));
  }

  @override
  bool shouldRepaint(_VeloGuia oldDelegate) => oldDelegate.objetivo != objetivo;
}
