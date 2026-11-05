import 'package:aftr_mobile/core/networking/supabase.dart';
import 'package:aftr_mobile/data/social_repo.dart';
import 'package:aftr_mobile/features/historias/historias.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// Al terminar la última historia la pantalla quedaba negra: el visor se
/// cerraba una vez por cada latido del reloj de 50 ms mientras se iba, así que
/// después de cerrarse se llevaba también la pantalla de abajo.
void main() {
  DatosSocial historiaVencida(String id) => {
    'id': id,
    'tipo': 'imagen',
    'storage_path': '$id.jpg',
    'nombre': 'Alguien',
    'autor_id': 'otro',
    // vencida: el reloj del visor pasa a la siguiente en el primer latido
    'vence_at': DateTime.now()
        .toUtc()
        .subtract(const Duration(minutes: 1))
        .toIso8601String(),
  };

  Future<void> abrirVisor(WidgetTester t, List<List<DatosSocial>> grupos) async {
    await t.pumpWidget(
      ProviderScope(
        overrides: [
          usuarioIdProvider.overrideWithValue('yo'),
          historiasProvider.overrideWith((ref) async => <String, dynamic>{
            'historias': [for (final g in grupos) ...g],
          }),
        ],
        child: MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: TextButton(
                  onPressed: () => Navigator.of(context).push<void>(
                    MaterialPageRoute(
                      builder: (_) =>
                          HistoriasVisor(grupos: grupos, grupoInicial: 0),
                    ),
                  ),
                  child: const Text('pantalla de abajo'),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await t.tap(find.text('pantalla de abajo'));
    await t.pump();
  }

  testWidgets('al terminar las historias vuelve a la pantalla de abajo', (
    t,
  ) async {
    await abrirVisor(t, [
      [historiaVencida('h1')],
      [historiaVencida('h2')],
    ]);
    // el reloj late varias veces mientras la pantalla se va
    await t.pump(const Duration(milliseconds: 60));
    await t.pump(const Duration(milliseconds: 60));
    await t.pump(const Duration(milliseconds: 60));
    await t.pumpAndSettle();
    expect(find.text('pantalla de abajo'), findsOneWidget);
    expect(find.byType(HistoriasVisor), findsNothing);
  });
}
