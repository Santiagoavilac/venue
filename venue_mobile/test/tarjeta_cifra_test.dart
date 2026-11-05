import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:venue_mobile/core/widgets/patron.dart' show Tono;
import 'package:venue_mobile/core/widgets/tarjeta_cifra.dart';

void main() {
  Widget enPantalla(Widget hijo) =>
      MaterialApp(home: Scaffold(body: Center(child: hijo)));

  testWidgets('muestra etiqueta, cifra, total y detalle', (tester) async {
    await tester.pumpWidget(
      enPantalla(
        const TarjetaCifra(
          etiqueta: 'Anotados',
          valor: '12',
          de: '40',
          detalle: 'en tus listas',
          tono: Tono.ok,
        ),
      ),
    );
    expect(find.text('Anotados'), findsOneWidget);
    expect(find.textContaining('12'), findsOneWidget);
    expect(find.textContaining('/ 40'), findsOneWidget);
    expect(find.text('en tus listas'), findsOneWidget);
  });

  testWidgets('el sufijo va pegado al número, no como total', (tester) async {
    await tester.pumpWidget(
      enPantalla(
        const TarjetaCifra(etiqueta: 'Vendido', valor: '1.200', sufijo: ' Bs'),
      ),
    );
    expect(find.textContaining('1.200'), findsOneWidget);
    expect(find.textContaining('Bs'), findsOneWidget);
    expect(find.textContaining('/'), findsNothing);
  });

  testWidgets('sin alTocar no hay flecha; con alTocar se puede tocar', (
    tester,
  ) async {
    await tester.pumpWidget(
      enPantalla(const TarjetaCifra(etiqueta: 'Mesas', valor: '3')),
    );
    expect(find.byIcon(Icons.chevron_right_rounded), findsNothing);

    var tocada = false;
    await tester.pumpWidget(
      enPantalla(
        TarjetaCifra(
          etiqueta: 'Mesas',
          valor: '3',
          alTocar: () => tocada = true,
        ),
      ),
    );
    expect(find.byIcon(Icons.chevron_right_rounded), findsOneWidget);
    await tester.tap(find.byType(TarjetaCifra));
    expect(tocada, isTrue);
  });
}
