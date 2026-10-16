import 'package:flutter/material.dart';

import '../theme/venue_theme.dart';

/// Una opción de la ruleta.
class OpcionRevolver {
  const OpcionRevolver(this.titulo, this.icono, {this.actual = false});
  final String titulo;
  final IconData icono;
  final bool actual;
}

/// Ruleta horizontal, como cuando se abre una caja en CS:GO: los ítems pasan
/// de costado al deslizar, la línea del centro marca el elegido, y la tira
/// da la vuelta completa (después del último vuelve el primero).
class Revolver extends StatefulWidget {
  const Revolver({super.key, required this.opciones, required this.alElegir});
  final List<OpcionRevolver> opciones;
  final ValueChanged<int> alElegir;

  @override
  State<Revolver> createState() => _RevolverState();
}

class _RevolverState extends State<Revolver> {
  // muchas vueltas hacia cada lado: en la práctica, una tira sin fin
  static const _vueltas = 1000;
  late final int _n = widget.opciones.length;
  late final PageController _c = PageController(
    viewportFraction: .34,
    initialPage: _n * _vueltas + widget.opciones.indexWhere((o) => o.actual).clamp(0, _n - 1).toInt(),
  );
  late int _pagina = _c.initialPage;

  int get _centro => _pagina % _n;

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final marca = Theme.of(context).colorScheme.primary;
    final o = widget.opciones[_centro];
    return Column(mainAxisSize: MainAxisSize.min, children: [
      const SizedBox(height: 14),
      SizedBox(
        height: 150,
        child: Stack(alignment: Alignment.center, children: [
          PageView.builder(
            controller: _c,
            onPageChanged: (p) => setState(() => _pagina = p),
            itemBuilder: (context, p) {
              final i = p % _n;
              return AnimatedBuilder(
                animation: _c,
                builder: (context, _) {
                  final actual = _c.hasClients && _c.position.haveDimensions
                      ? _c.page ?? _pagina.toDouble()
                      : _pagina.toDouble();
                  final lejos = (actual - p).abs().clamp(0.0, 1.0);
                  return Center(
                    child: Transform.scale(
                      scale: 1 - .22 * lejos,
                      child: Opacity(
                        opacity: 1 - .45 * lejos,
                        child: _item(widget.opciones[i], lejos < .5, marca, () {
                          if (p == _pagina) {
                            widget.alElegir(i);
                          } else {
                            _c.animateToPage(p,
                                duration: const Duration(milliseconds: 280),
                                curve: Curves.easeOutCubic);
                          }
                        }),
                      ),
                    ),
                  );
                },
              );
            },
          ),
          // la línea del centro, como la de la caja
          IgnorePointer(
            child: Column(children: [
              Icon(Icons.arrow_drop_down_rounded, color: marca, size: 30),
              Expanded(child: Container(width: 2, color: marca.withValues(alpha: .8))),
              Icon(Icons.arrow_drop_up_rounded, color: marca, size: 30),
            ]),
          ),
        ]),
      ),
      const SizedBox(height: 10),
      FilledButton.icon(
        onPressed: () => widget.alElegir(_centro),
        icon: Icon(o.icono),
        label: Text('Abrir ${o.titulo}'),
      ),
    ]);
  }

  Widget _item(OpcionRevolver o, bool alCentro, Color marca, VoidCallback alTocar) =>
      GestureDetector(
        onTap: alTocar,
        child: Container(
          width: 108,
          height: 108,
          decoration: BoxDecoration(
            color: alCentro ? marca.withValues(alpha: .22) : VenueColors.superficieAlta,
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: alCentro ? marca : VenueColors.linea, width: alCentro ? 2 : 1),
            boxShadow: alCentro
                ? [BoxShadow(color: marca.withValues(alpha: .35), blurRadius: 18)]
                : null,
          ),
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            Icon(o.icono, size: 38, color: alCentro ? marca : VenueColors.texto),
            const SizedBox(height: 6),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6),
              child: Text(o.titulo,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
            ),
          ]),
        ),
      );
}
