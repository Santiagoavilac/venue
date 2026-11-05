import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:venue_mobile/features/payments/data/incidencias.dart';
import 'package:venue_mobile/features/payments/ui/incidencias_screen.dart';

Incidencia _inc({
  bool abierta = true,
  bool puedeEmitir = true,
  String? nota = 'PAGADO_FUERA_DE_PLAZO',
}) => Incidencia(
  id: 'uno',
  detalle: 'El pago llegó después del plazo de diez minutos.',
  monto: 120,
  creado: DateTime(2026, 11, 5, 23, 40),
  abierta: abierta,
  puedeEmitir: puedeEmitir,
  bancoTx: 'BANCO-123',
  notaPago: nota,
  cliente: 'Ana Pérez',
  usuario: 'anaperez',
  evento: 'Noche de jueves',
  cantidad: 2,
  resolucion: abierta ? null : 'devolver: se le devolvió por transferencia',
);

Future<void> _mostrar(WidgetTester t, List<Incidencia> lista) => t.pumpWidget(
  ProviderScope(
    overrides: [
      incidenciasProvider('abierta').overrideWith(
        (ref) async => (abiertas: lista.where((i) => i.abierta).length, lista: lista),
      ),
    ],
    child: const MaterialApp(home: Scaffold(body: IncidenciasScreen())),
  ),
);

void main() {
  testWidgets('un cobro tardío dice cuánto, de quién y qué dijo el banco', (t) async {
    await _mostrar(t, [_inc()]);
    await t.pumpAndSettle();
    expect(find.text('120 Bs · Ana Pérez'), findsOneWidget);
    expect(find.text('Llegó tarde'), findsOneWidget);
    expect(find.textContaining('BANCO-123'), findsOneWidget);
    expect(find.textContaining('@anaperez'), findsOneWidget);
    // las tres salidas, más el WhatsApp para contestarle
    expect(find.text('Emitir'), findsOneWidget);
    expect(find.text('Devolví la plata'), findsOneWidget);
    expect(find.text('Cerrar'), findsOneWidget);
    expect(find.text('Escribirle'), findsOneWidget);
  });

  testWidgets('sin cupo o con el evento terminado no se ofrece emitir', (t) async {
    await _mostrar(t, [_inc(puedeEmitir: false)]);
    await t.pumpAndSettle();
    expect(find.text('Emitir'), findsNothing);
    expect(find.text('Devolví la plata'), findsOneWidget);
  });

  testWidgets('un caso resuelto muestra la nota y ya no ofrece acciones', (t) async {
    await _mostrar(t, [_inc(abierta: false)]);
    await t.pumpAndSettle();
    expect(find.text('Resuelto'), findsOneWidget);
    expect(find.textContaining('se le devolvió por transferencia'), findsOneWidget);
    expect(find.text('Emitir'), findsNothing);
    expect(find.text('Cerrar'), findsNothing);
  });

  testWidgets('sin nada pendiente lo dice en vez de quedar en blanco', (t) async {
    await _mostrar(t, []);
    await t.pumpAndSettle();
    expect(find.text('Ningún cobro pendiente'), findsOneWidget);
    expect(find.text('Nada pendiente'), findsOneWidget);
  });

  testWidgets('la emisión fallida es otro caso, no un pago tardío', (t) async {
    await _mostrar(t, [_inc(nota: 'PAGADO_SIN_EMISION')]);
    await t.pumpAndSettle();
    expect(find.text('Sin emitir'), findsOneWidget);
    expect(find.text('Llegó tarde'), findsNothing);
  });
}
