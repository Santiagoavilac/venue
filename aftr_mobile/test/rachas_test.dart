import 'package:aftr_mobile/data/rachas.dart';
import 'package:aftr_mobile/data/social_repo.dart';
import 'package:aftr_mobile/features/rachas/buscar_amigos.dart';
import 'package:aftr_mobile/features/rachas/rachas_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

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
    child: const MaterialApp(home: RachasScreen()),
  ),
);

void main() {
  _buscador();
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
    expect(find.textContaining('personas te pasan'), findsNothing);
    expect(find.text('Una persona te pasa. Falta una noche.'), findsOneWidget);
    // el 7 sale dos veces: en el podio y en la lista, como cualquier ranking
    expect(find.text('7'), findsWidgets);
    expect(find.text('Ana'), findsWidgets);
  });

  testWidgets('una racha cortada muestra la mejor, no un cero pelado', (t) async {
    await _hoja(t, Rachas(mia: _r('Yo', 0, viva: false, mejor: 6), gente: const []));
    await t.pumpAndSettle();
    expect(find.text('6'), findsOneWidget);
    expect(find.textContaining('Se cortó'), findsOneWidget);
  });

  testWidgets('si no salió esta semana, avisa que tiene hasta el domingo', (t) async {
    await _hoja(t, Rachas(mia: _r('Yo', 4, cerrada: false), gente: const []));
    await t.pumpAndSettle();
    expect(find.textContaining('hasta el domingo'), findsOneWidget);
  });

  testWidgets('sin gente lo explica en vez de dejar un hueco', (t) async {
    await _hoja(t, Rachas(mia: _r('Yo', 1), gente: const []));
    await t.pumpAndSettle();
    expect(find.textContaining('comparten una mesa'), findsOneWidget);
  });
}

// El buscador de amigos: tres letras, el usuario abajo del nombre y el botón
// que cambia según en qué está la amistad.
void _buscador() {
  testWidgets('con menos de tres letras no busca y lo dice', (t) async {
    var veces = 0;
    await t.pumpWidget(
      ProviderScope(
        overrides: [
          socialRepoProvider.overrideWithValue(_RepoFalso(() => veces++)),
        ],
        child: const MaterialApp(home: Scaffold(body: BuscarAmigos())),
      ),
    );
    await t.pumpAndSettle();
    expect(find.textContaining('al menos tres letras'), findsOneWidget);
    await t.enterText(find.byType(TextField), 'ma');
    await t.pump(const Duration(milliseconds: 400));
    expect(veces, 0);
  });

  testWidgets('cada resultado trae nombre, @usuario y el botón que toca', (t) async {
    await t.pumpWidget(
      ProviderScope(
        overrides: [
          socialRepoProvider.overrideWithValue(_RepoFalso(() {}, gente: [
            {'usuario': 'martasosa', 'nombre': 'Marta Sosa', 'amistad': 'no'},
            {'usuario': 'anap', 'nombre': 'Ana Paz', 'amistad': 'pedido'},
            {'usuario': 'beto', 'nombre': 'Beto Ruiz', 'amistad': 'amigos'},
            {'usuario': 'caro', 'nombre': 'Caro Vega', 'amistad': 'te_pidio'},
          ])),
        ],
        child: const MaterialApp(home: Scaffold(body: BuscarAmigos())),
      ),
    );
    await t.pumpAndSettle();
    await t.enterText(find.byType(TextField), 'marta');
    await t.pump(const Duration(milliseconds: 400));
    await t.pumpAndSettle();
    expect(find.text('Marta Sosa'), findsOneWidget);
    expect(find.text('@martasosa'), findsOneWidget);
    expect(find.text('Agregar'), findsOneWidget);
    expect(find.text('Pendiente'), findsOneWidget);
    expect(find.text('Amigos'), findsOneWidget);
    expect(find.text('Aceptar'), findsOneWidget);
  });
}

class _RepoFalso extends SocialRepo {
  _RepoFalso(this.alBuscar, {this.gente = const []})
    : super(SupabaseClient(
        'https://example.invalid',
        'clave-simulada',
        authOptions: const AuthClientOptions(autoRefreshToken: false),
      ));
  final void Function() alBuscar;
  final List<Map<String, dynamic>> gente;

  @override
  Future<List<DatosSocial>> buscarUsuario(String q) async {
    alBuscar();
    return gente;
  }
}
