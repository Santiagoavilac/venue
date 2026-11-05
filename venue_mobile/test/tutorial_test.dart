import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:venue_mobile/features/authentication/data/sesion.dart';
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

  testWidgets('un paso que no apunta a nada no se queda con el agujero del anterior', (t) async {
    final abajo = GlobalKey();
    Rect? de(GlobalKey k) {
      final b = k.currentContext!.findRenderObject() as RenderBox;
      return b.localToGlobal(Offset.zero) & b.size;
    }

    await t.pumpWidget(
      MaterialApp(
        home: Stack(
          children: [
            Scaffold(bottomNavigationBar: SizedBox(key: abajo, height: 70)),
            Positioned.fill(
              child: TutorialGuiado(
                pasos: [
                  PasoTutorial(
                    icono: Icons.event,
                    titulo: 'La barra',
                    texto: 'uno',
                    objetivo: () => de(abajo),
                  ),
                  PasoTutorial(
                    icono: Icons.table_bar_outlined,
                    titulo: 'El plano',
                    texto: 'dos',
                    objetivo: () => null,
                  ),
                ],
                alTerminar: () {},
              ),
            ),
          ],
        ),
      ),
    );
    await t.pumpAndSettle();
    expect(find.text('La barra'), findsOneWidget);
    await t.tap(find.text('Siguiente'));
    await t.pumpAndSettle();
    expect(find.text('El plano'), findsOneWidget);
    // si el agujero quedara pegado, la burbuja seguiría acomodada contra la
    // barra de abajo en vez de quedar centrada
    final caja = t.getRect(find.text('dos'));
    expect(caja.center.dy, lessThan(600));
  });

  test('cada guía se recuerda con su propia clave', () async {
    // la del inicio conserva la clave vieja, sin nombre, para no repetirle el
    // recorrido de la barra a quien ya lo hizo
    expect(await tutorialVisto('sin-prefs-uid', 'mesas'), isA<bool>());
  });

  testWidgets('la guía de una pantalla sale una vez y se puede saltar', (
    t,
  ) async {
    SharedPreferences.setMockInitialValues({});
    await t.pumpWidget(
      ProviderScope(
        overrides: [usuarioIdProvider.overrideWithValue('uid-1')],
        child: MaterialApp(
          home: Scaffold(
            body: GuiaDePantalla(
              guia: 'mesas',
              pasos: () => const [
                PasoTutorial(
                  icono: Icons.table_bar_outlined,
                  titulo: 'El plano',
                  texto: 'cada cuadrado es una mesa',
                  objetivo: _sinObjetivo,
                ),
              ],
              child: const Text('la pantalla'),
            ),
          ),
        ),
      ),
    );
    await t.pumpAndSettle();
    expect(find.text('la pantalla'), findsOneWidget);
    expect(find.text('El plano'), findsOneWidget);

    await t.tap(find.text('Listo'));
    await t.pumpAndSettle();
    expect(find.text('El plano'), findsNothing);
    expect(await tutorialVisto('uid-1', 'mesas'), isTrue);
    // la del inicio sigue sin verse: cada guía se recuerda aparte
    expect(await tutorialVisto('uid-1'), isFalse);
  });
}

Rect? _sinObjetivo() => null;