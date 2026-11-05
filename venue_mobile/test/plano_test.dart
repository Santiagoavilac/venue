import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:venue_mobile/features/vip_tables/data/mesas.dart';
import 'package:venue_mobile/features/vip_tables/ui/plano.dart';

Mesa _mesa(String id, String estado, {double x = 10, double y = 10}) => Mesa(
  id: id,
  eventoId: 'ev',
  planta: 'baja',
  etiqueta: id,
  categoria: 'mesa',
  x: x,
  y: y,
  w: 6,
  h: 12,
  estado: estado,
);

void main() {
  testWidgets('una mesa chica se puede tocar igual: 44 como mínimo', (
    tester,
  ) async {
    Mesa? tocada;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 360,
            child: Plano(
              mesas: [_mesa('M1', 'disponible')],
              planta: 'baja',
              alTocar: (m) => tocada = m,
            ),
          ),
        ),
      ),
    );
    // 6 % de 360 son 21 px de ancho: lo que se toca tiene que ser mayor
    final caja = tester.getSize(
      find.ancestor(
        of: find.text('M1'),
        matching: find.byType(SizedBox),
      ).last,
    );
    expect(caja.width, greaterThanOrEqualTo(44));
    expect(caja.height, greaterThanOrEqualTo(44));

    await tester.tap(find.text('M1'));
    expect(tocada?.id, 'M1');
  });

  testWidgets('el estado no se cuenta solo con el color', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 360,
            child: Plano(
              mesas: [
                _mesa('A', 'reservada'),
                _mesa('B', 'pagada', x: 40),
                _mesa('C', 'ocupada', x: 70),
              ],
              planta: 'baja',
              alTocar: (_) {},
            ),
          ),
        ),
      ),
    );
    expect(find.byIcon(Icons.schedule_rounded), findsOneWidget);
    expect(find.byIcon(Icons.check_circle_rounded), findsOneWidget);
    expect(find.byIcon(Icons.person_rounded), findsOneWidget);
  });
}
