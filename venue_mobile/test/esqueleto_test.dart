import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:venue_mobile/core/widgets/esqueleto.dart';
import 'package:venue_mobile/core/widgets/estado_vista.dart';

void main() {
  testWidgets('mientras carga se ve la forma de la lista, no una ruedita', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: VistaAsync<int>(valor: AsyncValue.loading(), datos: _nunca),
        ),
      ),
    );
    expect(find.byType(EsqueletoLista), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });

  testWidgets('cada pantalla puede poner el esqueleto que le corresponde', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: VistaAsync<int>(
            valor: AsyncValue.loading(),
            datos: _nunca,
            cargando: EsqueletoResumen(),
          ),
        ),
      ),
    );
    expect(find.byType(EsqueletoResumen), findsOneWidget);
    expect(find.byType(EsqueletoLista), findsNothing);
  });

  testWidgets('con datos, el esqueleto desaparece', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: VistaAsync<int>(
            valor: const AsyncValue.data(7),
            datos: (n) => Text('$n'),
          ),
        ),
      ),
    );
    expect(find.text('7'), findsOneWidget);
    expect(find.byType(EsqueletoLista), findsNothing);
  });
}

Widget _nunca(int _) => const SizedBox.shrink();
