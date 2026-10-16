import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/venue_theme.dart';

/// Una opción del tambor.
class OpcionRevolver {
  const OpcionRevolver(this.titulo, this.icono, {this.actual = false});
  final String titulo;
  final IconData icono;
  final bool actual;
}

/// Menú en forma de tambor de revólver: las opciones son cuadrados en un
/// círculo que se gira con el dedo, una vuelta completa. Al soltar, el tambor
/// encastra en la opción más cercana a la posición de arriba, que se ve más
/// grande; tocar cualquier cuadrado (o "Abrir") la elige.
class Revolver extends StatefulWidget {
  const Revolver({super.key, required this.opciones, required this.alElegir});
  final List<OpcionRevolver> opciones;
  final ValueChanged<int> alElegir;

  @override
  State<Revolver> createState() => _RevolverState();
}

class _RevolverState extends State<Revolver> with SingleTickerProviderStateMixin {
  /// Giro del tambor en radianes; 0 = la primera opción arriba.
  double _giro = 0;
  late final AnimationController _anim =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 260));
  Animation<double>? _hacia;

  int get _n => widget.opciones.length;
  double get _paso => 2 * math.pi / _n;

  @override
  void initState() {
    super.initState();
    // arranca con la sección actual arriba, si está en el tambor
    final i = widget.opciones.indexWhere((o) => o.actual);
    if (i > 0) _giro = -i * _paso;
    _anim.addListener(() {
      if (_hacia != null) setState(() => _giro = _hacia!.value);
    });
  }

  @override
  void dispose() {
    _anim.dispose();
    super.dispose();
  }

  /// Índice de la opción que está arriba.
  int get _frente => ((-_giro / _paso).round() % _n + _n) % _n;

  void _encastrar([int? i]) {
    final destino = i == null
        ? (_giro / _paso).round() * _paso
        // el camino más corto hasta dejar la opción [i] arriba
        : _giro + _corto(-i * _paso - _giro);
    _hacia = Tween(begin: _giro, end: destino)
        .animate(CurvedAnimation(parent: _anim, curve: Curves.easeOutBack));
    _anim.forward(from: 0);
  }

  double _corto(double d) {
    final v = (d + math.pi) % (2 * math.pi);
    return (v < 0 ? v + 2 * math.pi : v) - math.pi;
  }

  @override
  Widget build(BuildContext context) {
    final marca = Theme.of(context).colorScheme.primary;
    return LayoutBuilder(builder: (context, c) {
      final lado = math.min(c.maxWidth, 360.0);
      final centro = Offset(lado / 2, lado / 2);
      final radio = lado * .34;

      // los de atrás primero, para que el de adelante quede encima
      final orden = List.generate(_n, (i) => i)
        ..sort((a, b) => math.cos(a * _paso + _giro).compareTo(math.cos(b * _paso + _giro)));

      return Column(mainAxisSize: MainAxisSize.min, children: [
        GestureDetector(
          onPanStart: (_) => _anim.stop(),
          onPanUpdate: (d) {
            // el ángulo que barre el dedo alrededor del centro
            final antes = d.localPosition - d.delta - centro;
            final ahora = d.localPosition - centro;
            setState(() => _giro += _corto(ahora.direction - antes.direction));
          },
          onPanEnd: (_) => _encastrar(),
          child: SizedBox(
            width: lado,
            height: lado,
            child: Stack(children: [
              // el eje del tambor
              Positioned(
                left: centro.dx - radio * .42,
                top: centro.dy - radio * .42,
                child: Container(
                  width: radio * .84,
                  height: radio * .84,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: VenueColors.superficie2,
                    border: Border.all(color: VenueColors.linea),
                  ),
                  alignment: Alignment.center,
                  child: Padding(
                    padding: const EdgeInsets.all(6),
                    child: Text(widget.opciones[_frente].titulo,
                        textAlign: TextAlign.center,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13)),
                  ),
                ),
              ),
              for (final i in orden) _recamara(i, centro, radio, marca),
            ]),
          ),
        ),
        const SizedBox(height: 4),
        FilledButton.icon(
          onPressed: () => widget.alElegir(_frente),
          icon: Icon(widget.opciones[_frente].icono),
          label: Text('Abrir ${widget.opciones[_frente].titulo}'),
        ),
      ]);
    });
  }

  Widget _recamara(int i, Offset centro, double radio, Color marca) {
    // ángulo desde arriba, en sentido horario
    final a = i * _paso + _giro;
    final pos = centro + Offset(math.sin(a), -math.cos(a)) * radio;
    final cercania = (math.cos(a) + 1) / 2; // 1 arriba, 0 abajo
    final lado = 52 + 30 * cercania;
    final o = widget.opciones[i];
    final alFrente = i == _frente;
    return Positioned(
      left: pos.dx - lado / 2,
      top: pos.dy - lado / 2,
      child: GestureDetector(
        onTap: () => alFrente ? widget.alElegir(i) : _encastrar(i),
        child: Opacity(
          opacity: .45 + .55 * cercania,
          child: Container(
            width: lado,
            height: lado,
            decoration: BoxDecoration(
              color: alFrente ? marca.withValues(alpha: .22) : VenueColors.superficieAlta,
              borderRadius: BorderRadius.circular(lado * .24),
              border: Border.all(
                  color: alFrente || o.actual ? marca : VenueColors.linea,
                  width: alFrente ? 2 : 1),
            ),
            child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
              Icon(o.icono, size: lado * .36, color: alFrente ? marca : VenueColors.texto),
              if (lado > 66)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: Text(o.titulo,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700)),
                ),
            ]),
          ),
        ),
      ),
    );
  }
}
