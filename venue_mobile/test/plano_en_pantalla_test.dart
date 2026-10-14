import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:venue_mobile/features/vip_tables/data/mesas.dart';
import 'package:venue_mobile/features/vip_tables/ui/plano.dart';

/// El plano va dentro de una lista con zoom. Sin un alto propio quedaba
/// invisible en el teléfono: esta prueba lo monta igual que la pantalla.
void main() {
  testWidgets('el plano se ve dentro de la lista, en ancho de teléfono', (t) async {
    t.view.physicalSize = const Size(390 * 3, 844 * 3);
    t.view.devicePixelRatio = 3;
    addTearDown(t.view.reset);
    const ancho = 640.0;
    await t.pumpWidget(MaterialApp(
      home: Scaffold(
        body: ListView(padding: const EdgeInsets.all(16), children: [
          const Text('0 de 1 vendidas'),
          SizedBox(
            height: ancho / Plano.proporcion,
            child: InteractiveViewer(
              constrained: false,
              child: SizedBox(
                width: ancho,
                child: Plano(
                  planta: 'alta',
                  mesas: const [
                    Mesa(id: 'm', eventoId: 'e', planta: 'alta', etiqueta: 'A1',
                        categoria: 'mesa', x: 10, y: 20, w: 14, estado: 'disponible'),
                  ],
                  alTocar: (_) {},
                ),
              ),
            ),
          ),
        ]),
      ),
    ));
    expect(t.takeException(), isNull);
    expect(find.text('A1'), findsOneWidget);
    final caja = t.getSize(find.byType(Plano));
    expect(caja.width, ancho);
    expect(caja.height, closeTo(ancho / Plano.proporcion, .5));
  });

  test('un piso recién agregado aparece aunque todavía no tenga mesas', () {
    const mesas = [
      Mesa(id: 'm', eventoId: 'e', planta: 'alta', etiqueta: 'A1',
          categoria: 'mesa', x: 1, y: 1, w: 14, estado: 'disponible'),
    ];
    final conMesas = pisosDe(mesas);
    List<String> pisos(String? elegido) =>
        ordenPisos.where((p) => conMesas.contains(p) || p == elegido).toList();
    expect(pisos(null), ['alta']);
    expect(pisos('piso1'), ['piso1', 'alta']);
  });
}
