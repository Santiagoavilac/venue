import 'package:aftr_mobile/data/social_repo.dart';
import 'package:aftr_mobile/features/descubrir/descubrir_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

// La reventa vivía detrás de un botón de texto arriba de Accesos: escondida
// para quien no fue a buscarla. Estas pruebas son de que esté en el inicio.
Future<void> _inicio(WidgetTester t, Object? ofertas) => t.pumpWidget(
  ProviderScope(
    overrides: [
      mercadoProvider.overrideWith((ref) async => {'ofertas': ofertas ?? []}),
    ],
    child: const MaterialApp(home: Scaffold(body: ReventaEnInicio())),
  ),
);

void main() {
  testWidgets('con entradas en venta, el inicio las muestra', (t) async {
    await _inicio(t, [
      {
        'id': 'uno',
        'evento_id': 'ev',
        'evento': 'Noche de jueves',
        'club': 'Burtown',
        'precio_centavos': 12000,
        'vendedor': 'anaperez',
        'estado': 'publicada',
      },
    ]);
    await t.pumpAndSettle();
    expect(find.text('Reventa oficial'), findsOneWidget);
    expect(find.text('Ver todo'), findsOneWidget);
    expect(find.text('Noche de jueves'), findsOneWidget);
    expect(find.text('Bs 120.00'), findsOneWidget);
    expect(find.textContaining('anaperez'), findsOneWidget);
  });

  testWidgets('la oferta en operación se muestra, no se esconde', (t) async {
    await _inicio(t, [
      {
        'id': 'uno',
        'evento_id': 'ev',
        'evento': 'Noche',
        'club': 'Burtown',
        'precio_centavos': 9000,
        'vendedor': 'anaperez',
        'estado': 'reservada',
      },
    ]);
    await t.pumpAndSettle();
    expect(find.textContaining('En pago'), findsOneWidget);
    expect(find.textContaining('anaperez'), findsNothing);
  });

  testWidgets('sin nada en venta, igual se llega a publicar la tuya', (t) async {
    await _inicio(t, []);
    await t.pumpAndSettle();
    expect(find.text('Reventa oficial'), findsOneWidget);
    expect(find.textContaining('vendé tu entrada'), findsOneWidget);
  });
}
