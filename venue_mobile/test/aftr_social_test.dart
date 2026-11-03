import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:venue_mobile/features/access_control/data/resultado.dart';
import 'package:venue_mobile/features/aftr_social/data/social_aftr.dart';
import 'package:venue_mobile/features/aftr_social/ui/historias_screen.dart';
import 'package:venue_mobile/features/aftr_social/ui/reventa_screen.dart';
import 'package:venue_mobile/features/authentication/data/sesion.dart';
import 'package:venue_mobile/features/clubs/data/clubs.dart';

void main() {
  test('bloqueo de reventa y QR reemplazado rechazan ingreso explícitamente', () {
    for (final estado in ['bloqueada', 'reemplazada']) {
      final r = ResultadoEscaneo.desdeServidor(
        {'resultado': estado, 'cliente': 'Ana'}, codigo: 'OLDQR',
        esLista: false, ahora: DateTime(2026, 10, 31),
      );
      expect(r.veredicto.dejaPasar, isFalse);
      expect(r.veredicto, estado == 'bloqueada' ? Veredicto.bloqueada : Veredicto.reemplazada);
      expect(r.hora, isNull);
      expect(r.detalle, isNotEmpty);
    }
  });

  testWidgets('el boliche ve seguimiento sin el arbitraje de la plataforma', (t) async {
    await t.pumpWidget(ProviderScope(overrides: [
      perfilProvider.overrideWith((ref) async => const Perfil(id: 'staff', usuario: 'club', nombre: 'Club', activo: true)),
      clubActivoProvider.overrideWith((ref) => const Club(id: 'club', nombre: 'Club')),
      reventaGestionProvider(false).overrideWith((ref) async => {
        'config': {'habilitada': true}, 'admin_principal': false,
        'ofertas': [], 'ordenes': [], 'disputas': [{'id': 'private'}],
      }),
    ], child: const MaterialApp(home: Scaffold(body: ReventaScreen()))));
    await t.pumpAndSettle();
    expect(find.text('Reventa habilitada'), findsOneWidget);
    expect(find.text('Operaciones'), findsOneWidget);
    expect(find.text('Disputas'), findsNothing);
    expect(find.text('Todos'), findsNothing);
  });

  testWidgets('el principal tiene acceso explícito a disputas y alcance global', (t) async {
    await t.pumpWidget(ProviderScope(overrides: [
      perfilProvider.overrideWith((ref) async => const Perfil(id: 'root', usuario: 'root', nombre: 'Root', activo: true, adminPrincipal: true)),
      clubActivoProvider.overrideWith((ref) => const Club(id: 'club', nombre: 'Club')),
      reventaGestionProvider(false).overrideWith((ref) async => {
        'config': {}, 'admin_principal': true, 'ofertas': [], 'ordenes': [], 'disputas': [],
      }),
    ], child: const MaterialApp(home: Scaffold(body: ReventaScreen()))));
    await t.pumpAndSettle();
    expect(find.text('Todos'), findsOneWidget);
    expect(find.text('Disputas'), findsOneWidget);
    await t.tap(find.text('Disputas'));
    await t.pumpAndSettle();
    expect(find.text('Sin disputas pendientes'), findsOneWidget);
  });

  testWidgets('historias muestra publicación para RRPP y retiro requiere confirmación', (t) async {
    await t.pumpWidget(ProviderScope(overrides: [
      rolProvider.overrideWith((ref) async => Rol.rrpp),
      historiasGestionProvider.overrideWith((ref) async => {
        'historias': [{
          'id': 'h1', 'nombre': 'Ana', 'evento': 'Noche', 'tipo': 'imagen',
          'vence_at': DateTime.now().add(const Duration(hours: 2)).toIso8601String(),
          'can_retirar': true,
        }], 'reportes': [],
      }),
    ], child: const MaterialApp(home: Scaffold(body: HistoriasScreen()))));
    await t.pumpAndSettle();
    expect(find.text('Nueva historia'), findsOneWidget);
    await t.tap(find.text('Retirar'));
    await t.pumpAndSettle();
    expect(find.text('Retirar historia'), findsOneWidget);
    await t.tap(find.text('Volver'));
    await t.pumpAndSettle();
    expect(find.text('Retirar historia'), findsNothing);
    expect(find.text('Ana'), findsOneWidget);
  });
}
