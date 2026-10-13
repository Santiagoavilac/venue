import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:venue_mobile/core/theme/venue_theme.dart';
import 'package:venue_mobile/features/vip_tables/data/mesas.dart';
import 'package:venue_mobile/features/vip_tables/ui/plano.dart';

Mesa mesa(String et, {String estado = 'disponible', String planta = 'alta',
        String cat = 'mesa', num precio = 0, String? combo, int qty = 1,
        String? cliente, bool verif = false, double x = 10, double y = 20}) =>
    Mesa(id: et, eventoId: 'e', planta: planta, etiqueta: et, categoria: cat,
        x: x, y: y, w: 14, estado: estado, precio: precio, comboId: combo,
        comboQty: qty, cliente: cliente, pagoVerificado: verif);

void main() {
  test('pisos presentes en orden; sin mesas, alta y baja', () {
    expect(pisosDe([mesa('a', planta: 'baja'), mesa('b', planta: 'piso1')]),
        ['piso1', 'baja']);
    expect(pisosDe(const []), ['alta', 'baja']);
  });

  test('el arrastre no saca la mesa del plano y ajusta a medios puntos', () {
    expect(acotarPosicion(-5, -5, 14), (x: 0.5, y: 0.5));
    expect(acotarPosicion(200, 200, 14), (x: 85.0, y: 86.0));
    expect(acotarPosicion(33.26, 41.74, 14), (x: 33.5, y: 41.5));
  });

  test('combo: vale solo si está habilitado para todos los tipos del grupo', () {
    const todos = Combo(id: '1', nombre: 'A', precio: 900);
    const soloLounge = Combo(id: '2', nombre: 'B', precio: 2000, categorias: ['lounge']);
    expect(todos.valePara(['mesa', 'lounge']), isTrue);
    expect(soloLounge.valePara(['lounge']), isTrue);
    expect(soloLounge.valePara(['mesa', 'lounge']), isFalse);
  });

  test('mesa: por verificar y vencimiento de la reserva', () {
    expect(mesa('a', estado: 'pagada', precio: 900).porVerificar, isTrue);
    expect(mesa('a', estado: 'pagada', precio: 900, verif: true).porVerificar, isFalse);
    expect(mesa('a', estado: 'pagada').porVerificar, isFalse); // cortesía: 0 Bs
    final m = Mesa.desde({
      'id': 'm', 'evento_id': 'e', 'estado': 'reservada',
      'reservada_at': '2026-10-13T22:00:00Z',
    });
    expect(m.vence(3), DateTime.utc(2026, 10, 14, 1).toLocal());
    final conVence = Mesa.desde({
      'id': 'm', 'evento_id': 'e', 'estado': 'reservada',
      'reservada_at': '2026-10-13T22:00:00Z', 'reserva_vence_at': '2026-10-14T04:00:00Z',
    });
    // el vencimiento que viaja en la mesa manda sobre las horas del evento
    expect(conVence.vence(3), DateTime.utc(2026, 10, 14, 4).toLocal());
  });

  test('registro de combos: precio neto de comisiones y desglose', () {
    const c = Combo(id: 'c', nombre: 'Combo Vodka', precio: 900, comisionRrpp: 60, comisionJefe: 20);
    final t = registroDeCombos('Noche Aurora', 'mar 13 oct', [
      mesa('A2', estado: 'pagada', precio: 1800, combo: 'c', qty: 2, cliente: 'Luis'),
      mesa('A1', estado: 'pagada', precio: 900, combo: 'c', cliente: 'Ana'),
    ], {'c': c});
    expect(t, contains(' 1. Ana - 1 Combo Vodka — 820 Bs'));
    expect(t, contains(' 2. Luis - 2 Combo Vodka — 1640 Bs'));
    expect(t, contains('Total: 2460 Bs'));
    expect(t, contains('•  3 Combo Vodka × 820 Bs = 2460 Bs'));
  });

  testWidgets('el plano dibuja las mesas de la planta y avisa el toque', (t) async {
    Mesa? tocada;
    await t.pumpWidget(MaterialApp(
      theme: temaVenue(),
      home: Scaffold(
        body: SizedBox(
          width: 800,
          child: Plano(
            planta: 'alta',
            mesas: [
              mesa('A1'),
              mesa('A2', estado: 'pagada', cliente: 'Carlos Roca', x: 40),
            ],
            alTocar: (m) => tocada = m,
          ),
        ),
      ),
    ));
    expect(find.text('A1'), findsOneWidget);
    expect(find.text('Libre'), findsOneWidget);
    expect(find.text('Carlos Roca'), findsOneWidget);
    await t.tap(find.text('A2'));
    expect(tocada?.etiqueta, 'A2');
  });

  testWidgets('en modo mover, arrastrar informa la posición nueva', (t) async {
    (Mesa, double, double)? movida;
    await t.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SizedBox(
          width: 1000, // 1000 x 420: 1 % = 10 px de ancho y 4,2 px de alto
          child: Plano(
            planta: 'alta',
            mover: true,
            mesas: [mesa('A1', x: 10, y: 20)],
            alTocar: (_) {},
            alMover: (m, x, y) => movida = (m, x, y),
          ),
        ),
      ),
    ));
    await t.drag(find.text('A1'), const Offset(200, 42));
    await t.pump();
    expect(movida, isNotNull);
    expect(movida!.$2, closeTo(30, 2.5));
    expect(movida!.$3, closeTo(30, 2.5));
  });
}
