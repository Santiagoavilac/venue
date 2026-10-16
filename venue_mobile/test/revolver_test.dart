import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:venue_mobile/core/widgets/revolver.dart';

void main() {
  testWidgets('la ruleta se dibuja, desliza y da la vuelta completa', (t) async {
    int? elegido;
    await t.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Revolver(
          opciones: const [
            OpcionRevolver('Mesas', Icons.table_bar),
            OpcionRevolver('Reporte', Icons.bar_chart),
            OpcionRevolver('Gente', Icons.people),
          ],
          alElegir: (i) => elegido = i,
        ),
      ),
    ));
    expect(t.takeException(), isNull);
    expect(find.text('Abrir Mesas'), findsOneWidget);

    // tres deslizamientos hacia la izquierda: vuelve a Mesas
    for (var k = 0; k < 3; k++) {
      await t.fling(find.byType(PageView), const Offset(-150, 0), 800);
      await t.pumpAndSettle();
    }
    expect(find.text('Abrir Mesas'), findsOneWidget);

    await t.tap(find.text('Abrir Mesas'));
    expect(elegido, 0);
  });
}
