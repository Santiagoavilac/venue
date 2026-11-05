import 'package:aftr_mobile/core/widgets/teclado.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// El teclado quedaba arriba tapando media pantalla cuando el campo que lo
/// había abierto desaparecía (una hoja que se cierra, un paso atrás mientras se
/// escribía): sin campo enfocado no quedaba dónde tocar para bajarlo.
void main() {
  Widget vista(Widget hijo) => MaterialApp(
    home: MediaQuery(
      // el teclado, levantado
      data: const MediaQueryData(viewInsets: EdgeInsets.only(bottom: 320)),
      child: VigilanteDelTeclado(child: Scaffold(body: hijo)),
    ),
  );

  List<String> metodos(WidgetTester tester) =>
      [for (final c in tester.testTextInput.log) c.method];

  testWidgets('baja el teclado cuando el campo que lo abrió ya no está', (
    tester,
  ) async {
    final nodo = FocusNode();
    addTearDown(nodo.dispose);
    await tester.pumpWidget(vista(TextField(focusNode: nodo)));
    nodo.requestFocus();
    await tester.pump(const Duration(milliseconds: 400));
    expect(tester.testTextInput.isVisible, isTrue);

    await tester.pumpWidget(vista(const Text('sin campo')));
    // lo que manda Flutter al destruir el campo no cuenta: lo que importa es
    // que después alguien cierre el teclado
    await tester.pump(const Duration(milliseconds: 60));
    tester.testTextInput.log.clear();
    await tester.pump(const Duration(milliseconds: 400));
    expect(metodos(tester), contains('TextInput.hide'));
  });

  testWidgets('no molesta mientras alguien está escribiendo', (tester) async {
    final nodo = FocusNode();
    addTearDown(nodo.dispose);
    await tester.pumpWidget(vista(TextField(focusNode: nodo)));
    nodo.requestFocus();
    await tester.pump(const Duration(milliseconds: 60));
    tester.testTextInput.log.clear();
    await tester.pump(const Duration(milliseconds: 600));
    expect(metodos(tester), isNot(contains('TextInput.hide')));
    expect(nodo.hasFocus, isTrue);
  });
}
