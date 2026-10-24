import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:venue_mobile/features/dashboard/ui/tutorial.dart';

void main() {
  testWidgets('tutorial: apunta, avanza y termina', (t) async {
    final abajo = GlobalKey(), arriba = GlobalKey();
    var mostrados = <int>[];
    var termino = false;
    Rect? de(GlobalKey k) {
      final b = k.currentContext!.findRenderObject() as RenderBox;
      return b.localToGlobal(Offset.zero) & b.size;
    }

    await t.pumpWidget(MaterialApp(
      home: Stack(children: [
        Scaffold(
          body: Align(alignment: Alignment.topRight, child: SizedBox(key: arriba, width: 46, height: 46)),
          bottomNavigationBar: SizedBox(key: abajo, height: 70),
        ),
        Positioned.fill(
          child: TutorialGuiado(
            pasos: [
              PasoTutorial(
                  icono: Icons.event, titulo: 'Eventos', texto: 'uno',
                  objetivo: () => de(abajo), alMostrar: () => mostrados.add(0)),
              PasoTutorial(
                  icono: Icons.person, titulo: 'Tu perfil', texto: 'dos',
                  objetivo: () => de(arriba), alMostrar: () => mostrados.add(1)),
            ],
            alTerminar: () => termino = true,
          ),
        ),
      ]),
    ));
    await t.pumpAndSettle();
    expect(find.text('Eventos'), findsOneWidget);
    expect(find.text('1/2'), findsOneWidget);
    expect(mostrados, [0]);
    await t.tap(find.text('Siguiente'));
    await t.pumpAndSettle();
    expect(find.text('Tu perfil'), findsOneWidget);
    expect(mostrados, [0, 1]);
    await t.tap(find.text('Listo'));
    expect(termino, isTrue);
  });
}
