import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:venue_mobile/features/events/data/eventos.dart';
import 'package:venue_mobile/features/events/ui/cambiar_evento.dart';

Evento _evento(String nombre, DateTime fecha) => Evento(
  id: 'ev-1',
  nombre: nombre,
  fecha: fecha,
  horaInicio: '22:00',
  horaFin: '05:00',
  estado: 'activo',
);

void main() {
  testWidgets('dice de qué evento son los datos de la pantalla', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          eventoActivoProvider.overrideWithValue(
            _evento('Noche de jueves', DateTime(2026, 11, 5)),
          ),
        ],
        child: const MaterialApp(home: Scaffold(body: DeQueEvento())),
      ),
    );
    expect(find.textContaining('Noche de jueves'), findsOneWidget);
    expect(find.text('Cambiar'), findsOneWidget);
  });

  testWidgets('sin evento activo lo dice, no queda en blanco', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [eventoActivoProvider.overrideWithValue(null)],
        child: const MaterialApp(home: Scaffold(body: DeQueEvento())),
      ),
    );
    expect(find.textContaining('Sin evento'), findsOneWidget);
  });
}
