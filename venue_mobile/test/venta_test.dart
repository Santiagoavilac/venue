import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:venue_mobile/features/guestlists/data/listas.dart';
import 'package:venue_mobile/features/tickets/data/entradas.dart';
import 'package:venue_mobile/features/tickets/ui/ticket_sheet.dart';
import 'package:venue_mobile/features/access_control/data/qr.dart';

void main() {
  test('separar nombres: líneas, comas y el "+N" se descarta', () {
    expect(separarNombres('Ana Paz\n Jorge Vaca ,Luis +2\n\n'),
        ['Ana Paz', 'Jorge Vaca', 'Luis']);
    expect(separarNombres('  \n , '), isEmpty);
  });

  test('lista abierta según su ventana de registro', () {
    final l = ListaTipo.desde({
      'id': 'l1', 'nombre': 'Free',
      'registro_desde': '2026-10-13T12:00:00Z',
      'registro_hasta': '2026-10-13T20:00:00Z',
      'ingreso_hasta': '00:30:00',
    });
    expect(l.abierta(DateTime.utc(2026, 10, 13, 11).toLocal()), isFalse);
    expect(l.abierta(DateTime.utc(2026, 10, 13, 15).toLocal()), isTrue);
    expect(l.abierta(DateTime.utc(2026, 10, 13, 21).toLocal()), isFalse);
    expect(l.ingresoHasta, '00:30');
    expect(ListaTipo.desde({'id': 'x', 'nombre': 'y'}).abierta(DateTime.now()), isTrue);
  });

  test('el QR que genera la app lo entiende el escáner', () {
    const ev = 'c4405f20-e8c7-46a4-b431-a40b27844d56';
    final e = QrLeido.interpretar(payloadEntrada(ev, 'QHXNG5PZK6'))!;
    expect((e.codigo, e.esLista, e.eventoId), ('QHXNG5PZK6', false, ev));
    final l = QrLeido.interpretar(payloadLista(ev, 'RS7JHPB2H4'))!;
    expect((l.codigo, l.esLista), ('RS7JHPB2H4', true));
  });

  test('entrada e invitado desde el servidor', () {
    final e = Entrada.desde({'id': '1', 'code': 'ABC', 'cliente': 'Ana', 'precio': 100, 'estado': 'valida'});
    expect(e.valida, isTrue);
    final i = Invitado.desde({'id': 'r', 'lista_tipo_id': 'l', 'nombre': 'Luis', 'rrpp_id': 'u', 'ingreso_at': '2026-10-13T23:00:00Z'});
    expect(i.ingreso, isTrue);
    expect(i.codigo, isNull);
  });

  testWidgets('el ticket muestra evento, cliente y código', (t) async {
    const d = TicketDatos(
      payload: 'EVT:ev:ABC123', codigo: 'ABC123', cliente: 'Carlos Roca',
      boliche: 'Aurora Club', evento: 'Noche Aurora', fecha: 'mar 13 oct',
      tipo: 'Entrada prepagada',
    );
    await t.pumpWidget(const MaterialApp(home: Scaffold(body: Center(child: TicketCard(datos: d)))));
    expect(find.text('AURORA CLUB'), findsOneWidget);
    expect(find.text('Noche Aurora'), findsOneWidget);
    expect(find.text('Carlos Roca'), findsOneWidget);
    expect(find.text('Entrada prepagada · #ABC123'), findsOneWidget);
    expect(d.mensaje, contains('Presentá este QR en puerta'));
  });
}
