import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:venue_mobile/core/widgets/insignia.dart';

void main() {
  Widget enPantalla(Widget hijo) =>
      MaterialApp(home: Scaffold(body: Center(child: hijo)));

  testWidgets('la insignia dice qué pasa, no solo lo pinta', (tester) async {
    // En la puerta hay gente que no distingue el verde del rojo: el estado
    // tiene que leerse, y además lleva un punto que no depende del color.
    await tester.pumpWidget(enPantalla(const Insignia('Pagado')));
    expect(find.text('Pagado'), findsOneWidget);
    expect(find.byType(Container), findsWidgets);
  });

  testWidgets('la plana es solo texto, para las listas densas', (tester) async {
    await tester.pumpWidget(
      enPantalla(const Insignia.texto('no pasó filtro', tono: Tono.mal)),
    );
    expect(find.text('no pasó filtro'), findsOneWidget);
    // sin píldora: ningún Container decorado alrededor del texto
    expect(
      tester.widgetList<Container>(find.byType(Container)).where(
        (c) => c.decoration != null,
      ),
      isEmpty,
    );
  });
}
