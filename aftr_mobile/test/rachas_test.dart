import 'package:aftr_mobile/data/rachas.dart';
import 'package:aftr_mobile/features/rachas/rachas.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

Racha _r(String nombre, int semanas, {bool viva = true, int mejor = 0, bool cerrada = true}) =>
    Racha(
      usuario: nombre.toLowerCase(),
      nombre: nombre,
      semanas: semanas,
      viva: viva,
      mejor: mejor == 0 ? semanas : mejor,
      cerrada: cerrada,
    );

Future<void> _hoja(WidgetTester t, Rachas r) => t.pumpWidget(
  ProviderScope(
    overrides: [rachasProvider.overrideWith((ref) async => r)],
    child: const MaterialApp(home: Scaffold(body: HojaDeRachas())),
  ),
);

void main() {
  test('la racha de una semana suelta no es la mejor de otra persona', () {
    final r = Rachas(mia: _r('Yo', 2), gente: [_r('Ana', 5), _r('Beto', 1)]);
    // sólo Ana le pasa
    expect(r.porDelante, 1);
  });

  test('sin gente no hay con quién compararse', () {
    expect(Rachas(mia: _r('Yo', 3), gente: const []).porDelante, 0);
  });

  testWidgets('la hoja pone la propia arriba y ordena por semanas', (t) async {
    await _hoja(t, Rachas(mia: _r('Yo', 3), gente: [_r('Ana', 7), _r('Beto', 1)]));
    await t.pumpAndSettle();
    expect(find.text('Vos'), findsOneWidget);
    expect(find.text('Una persona de tu gente te pasa'), findsOneWidget);
    expect(find.text('7'), findsOneWidget);
    expect(find.text('Ana'), findsOneWidget);
  });

  testWidgets('una racha cortada muestra la mejor, no un cero pelado', (t) async {
    await _hoja(t, Rachas(mia: _r('Yo', 0, viva: false, mejor: 6), gente: const []));
    await t.pumpAndSettle();
    expect(find.text('6'), findsOneWidget);
    expect(find.textContaining('su mejor fue 6'), findsOneWidget);
  });

  testWidgets('si no salió esta semana, avisa que tiene hasta el domingo', (t) async {
    await _hoja(t, Rachas(mia: _r('Yo', 4, cerrada: false), gente: const []));
    await t.pumpAndSettle();
    expect(find.textContaining('hasta el domingo'), findsOneWidget);
  });

  testWidgets('sin gente lo explica en vez de dejar un hueco', (t) async {
    await _hoja(t, Rachas(mia: _r('Yo', 1), gente: const []));
    await t.pumpAndSettle();
    expect(find.textContaining('compartiste una mesa'), findsOneWidget);
  });
}
