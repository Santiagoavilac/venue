import 'dart:typed_data';
import 'package:aftr_mobile/core/networking/supabase.dart';
import 'package:aftr_mobile/core/routing/router.dart';
import 'package:aftr_mobile/core/theme/aftr_theme.dart';
import 'package:aftr_mobile/data/aftr_repo.dart';
import 'package:aftr_mobile/data/foto_perfil.dart';
import 'package:aftr_mobile/data/modelos.dart';
import 'package:aftr_mobile/data/pulse_repo.dart';
import 'package:aftr_mobile/features/descubrir/descubrir_screen.dart';
import 'package:aftr_mobile/features/guia/guia.dart';
import 'package:aftr_mobile/features/pulse/marco_aftr.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('fechas: 44 puntos, selección y volver a Todo', (tester) async {
    DateTime? seleccion;
    await tester.pumpWidget(
      MaterialApp(
        theme: temaAftr(),
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) => FechasAftr(
              elegida: seleccion,
              onElegir: (d) => setState(() => seleccion = d),
            ),
          ),
        ),
      ),
    );
    expect(tester.getSize(find.byType(FechasAftr)).height, 44);
    await tester.tap(find.text('Hoy'));
    await tester.pump();
    expect(seleccion?.day, DateTime.now().day);
    await tester.tap(find.text('Todo'));
    await tester.pump();
    expect(seleccion, isNull);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'el saldo sigue visible al abrir un evento y permite ir a PULSE',
    (tester) async {
      final router = GoRouter(
        routes: [
          GoRoute(
            path: '/',
            builder: (_, _) => const Scaffold(body: Text('Inicio de prueba')),
          ),
          GoRoute(
            path: '/evento',
            builder: (_, _) => const Scaffold(body: Text('Evento de prueba')),
          ),
          GoRoute(
            path: '/pulse',
            builder: (_, _) =>
                const Scaffold(body: Text('Billetera de prueba')),
          ),
        ],
      );
      addTearDown(router.dispose);
      final container = ProviderContainer(
        overrides: [
          usuarioIdProvider.overrideWithValue('cliente-demo'),
          perfilProvider.overrideWith(
            (ref) async => const Cliente(
              id: 'cliente-demo',
              usuario: 'demo',
              nombre: 'Demo',
            ),
          ),
          pulseSaldoProvider.overrideWith(
            (ref) async => {'saldo_centavos': 12345},
          ),
          routerProvider.overrideWithValue(router),
        ],
      );
      addTearDown(container.dispose);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp.router(
            theme: temaAftr(),
            routerConfig: router,
            builder: (_, child) => MarcoAftr(iniciado: false, child: child!),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('123.45 PULSE'), findsOneWidget);
      router.go('/evento');
      await tester.pumpAndSettle();
      expect(find.text('Evento de prueba'), findsOneWidget);
      expect(find.text('123.45 PULSE'), findsOneWidget);
      await tester.tap(find.text('123.45 PULSE'));
      await tester.pumpAndSettle();
      expect(find.text('Billetera de prueba'), findsOneWidget);
      expect(find.text('123.45 PULSE'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('guía: recorre secciones, permite volver y terminar', (
    tester,
  ) async {
    final rutas = <String>[];
    var terminada = false;
    await tester.pumpWidget(
      MaterialApp(
        theme: temaAftr(),
        home: Scaffold(
          body: GuiaAftr(
            alMostrar: rutas.add,
            alTerminar: () => terminada = true,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('1 de 5'), findsOneWidget);
    for (var i = 0; i < 3; i++) {
      await tester.tap(find.text('Siguiente'));
      await tester.pumpAndSettle();
    }
    expect(find.text('Tu saldo PULSE'), findsOneWidget);
    await tester.tap(find.text('Atrás'));
    await tester.pumpAndSettle();
    expect(find.text('Accesos y mesas'), findsOneWidget);
    await tester.tap(find.text('Siguiente'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Siguiente'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Empezar'));
    await tester.pumpAndSettle();
    expect(terminada, isTrue);
    expect(rutas, containsAll(['/', '/mapa', '/accesos', '/cuenta']));
    expect(tester.takeException(), isNull);
  });

  test('la guía se recuerda por cuenta, no por teléfono compartido', () async {
    SharedPreferences.setMockInitialValues({});
    expect(await guiaVista('uno'), isFalse);
    await guardarGuiaVista('uno');
    expect(await guiaVista('uno'), isTrue);
    expect(await guiaVista('dos'), isFalse);
  });

  test(
    'foto: acepta imágenes y rechaza SVG y archivos que solo se llaman jpg',
    () {
      expect(extensionFoto(Uint8List.fromList([255, 216, 255, 224])), 'jpg');
      expect(
        extensionFoto(Uint8List.fromList([137, 80, 78, 71, 13, 10, 26, 10])),
        'png',
      );
      expect(
        () => extensionFoto(Uint8List.fromList('<svg></svg>'.codeUnits)),
        throwsFormatException,
      );
      expect(
        () => extensionFoto(Uint8List.fromList('archivo.jpg'.codeUnits)),
        throwsFormatException,
      );
    },
  );
}
