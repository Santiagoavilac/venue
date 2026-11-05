import 'dart:async';

import 'package:aftr_mobile/data/aftr_repo.dart';
import 'package:aftr_mobile/data/modelos.dart';
import 'package:aftr_mobile/features/evento/pago_qr.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

// PNG de un píxel, sólo para que el widget pueda decodificar la imagen.
const png =
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=';

class RepoSimulado extends AftrRepo {
  RepoSimulado(this.estado)
    : super(
        SupabaseClient(
          'https://example.invalid',
          'clave-simulada',
          authOptions: const AuthClientOptions(autoRefreshToken: false),
        ),
      );
  final String estado;
  String? nota;
  int consultas = 0;
  final resultado = Completer<({String? estado, String? nota, String? orden})>();

  @override
  Future<Map<String, dynamic>> qrDePago(
    String orden, {
    String tipo = 'orden',
  }) async => {
    'estado': estado,
    'monto': 25.50,
    'imagen': png,
    'vence': '2026-11-01',
    if (nota != null) 'nota': nota,
  };

  @override
  Future<({String? estado, String? nota, String? orden})> estadoPago(
    String orden, {
    String tipo = 'orden',
  }) {
    consultas++;
    return resultado.future;
  }
}

void main() {
  test('decodifica el QR base64 del banco sin redondear el importe', () {
    final q = PagoQr.desde({
      'estado': 'activo',
      'monto': '25.50',
      'imagen': png,
    });
    expect(q.monto, 25.50);
    expect(q.imagen, isNotEmpty);
  });

  testWidgets('un cobro en revisión no se presenta como pagable', (
    tester,
  ) async {
    final repo = RepoSimulado('revisar');
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          repoProvider.overrideWithValue(repo),
          accesosProvider.overrideWith((ref) async => const Accesos([])),
        ],
        child: const MaterialApp(
          home: PagoQrScreen(orden: 'orden', titulo: 'Evento'),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Tu pago no se pudo entregar'), findsOneWidget);
    expect(find.text('Escribir por WhatsApp'), findsOneWidget);
    expect(find.text('Guardar QR'), findsNothing);
    expect(repo.consultas, 0);
  });

  testWidgets('el pago fuera de plazo lo dice y ofrece el WhatsApp', (
    tester,
  ) async {
    final repo = RepoSimulado('revisar')..nota = 'PAGADO_FUERA_DE_PLAZO';
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          repoProvider.overrideWithValue(repo),
          accesosProvider.overrideWith((ref) async => const Accesos([])),
        ],
        child: const MaterialApp(
          home: PagoQrScreen(orden: 'orden', titulo: 'Evento'),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Tu pago llegó tarde'), findsOneWidget);
    expect(
      find.textContaining('diez minutos', findRichText: true),
      findsWidgets,
    );
    expect(find.text('Escribir por WhatsApp'), findsOneWidget);
  });

  testWidgets('una consulta lenta no dispara otras en paralelo', (
    tester,
  ) async {
    final repo = RepoSimulado('activo');
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          repoProvider.overrideWithValue(repo),
          accesosProvider.overrideWith((ref) async => const Accesos([])),
        ],
        child: const MaterialApp(
          home: PagoQrScreen(orden: 'orden', titulo: 'Evento'),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(seconds: 4));
    await tester.pump(const Duration(seconds: 8));
    expect(repo.consultas, 1);
    expect(find.text('Bs 25.50'), findsOneWidget);
    repo.resultado.complete((estado: 'pagado', nota: null, orden: 'confirmada'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('Pago confirmado'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });
}
