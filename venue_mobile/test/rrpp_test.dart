import 'package:flutter_test/flutter_test.dart';
import 'package:venue_mobile/features/rrpp/data/rrpp.dart';

EventoRrpp ev(String fecha, {String club = 'a', num com = 0, String estado = 'estimada', int usadas = 0,
        int ingresaron = 0, int anotados = 0, int vendidas = 0, int mesas = 0, num bruto = 0}) =>
    EventoRrpp(
      eventoId: fecha, clubId: club, club: club, evento: 'Ev $fecha', fecha: DateTime.parse(fecha), estado: '',
      comisionTotal: com, estadoComision: estado, entradasUsadas: usadas, ingresaron: ingresaron,
      anotados: anotados, entradasVendidas: vendidas, mesasConfirmadas: mesas, brutoEntradas: bruto);

void main() {
  final hoy = DateTime(2026, 10, 29);

  test('períodos', () {
    expect(Periodo.semana.desde(hoy), DateTime(2026, 10, 23));
    expect(Periodo.mes.desde(hoy), DateTime(2026, 10, 1));
    expect(Periodo.anio.desde(hoy), DateTime(2026, 1, 1));
    expect(Periodo.todo.desde(hoy), isNull);
  });

  test('filtra por período y boliche', () {
    final l = [ev('2026-10-20'), ev('2026-09-30'), ev('2026-10-05', club: 'b')];
    expect(delPeriodo(l, Periodo.mes, null, hoy: hoy).length, 2);
    expect(delPeriodo(l, Periodo.mes, 'b', hoy: hoy).length, 1);
    expect(delPeriodo(l, Periodo.todo, null, hoy: hoy).length, 3);
  });

  test('totales: pagado y por cobrar no se mezclan; ventas no son ganancia', () {
    final t = Totales.de([
      ev('2026-10-01', com: 100, estado: 'pagada', bruto: 1000),
      ev('2026-10-02', com: 50, estado: 'confirmada'),
      ev('2026-10-03', com: 30),
    ]);
    expect(t.comision, 180);
    expect(t.pagado, 100);
    expect(t.pendiente, 80);
    expect(t.confirmado, 50);
    expect(t.estimado, 30);
    expect(t.ventas, 1000);
  });

  test('asistencia efectiva = lista que entró + QR usados', () {
    final t = Totales.de([ev('2026-10-01', ingresaron: 8, anotados: 10, usadas: 5)]);
    expect(t.entraron, 13);
    expect(t.asistencia, 80);
  });

  test('récords salen de los datos y sin datos no aparecen', () {
    expect(records(const []), isEmpty);
    final r = records([ev('2026-09-01', com: 10, usadas: 3), ev('2026-10-01', com: 40, usadas: 1)]);
    final com = r.firstWhere((x) => x.titulo.startsWith('Comisión'));
    expect(com.valor, 40);
    expect(com.evento!.eventoId, '2026-10-01');
    expect(r.firstWhere((x) => x.titulo.startsWith('Mejor mes')).mes, DateTime(2026, 10));
    expect(r.firstWhere((x) => x.titulo == 'Eventos trabajados').valor, 2);
    expect(r.any((x) => x.titulo.startsWith('Mesas')), isFalse);
  });

  test('código de un enlace', () {
    expect(codigoDeUnion('https://venue-web-amber.vercel.app/?unirse=ABC123def'), 'abc123def');
    expect(codigoDeUnion('venue://app/registro?invite=f00d'), 'f00d');
    expect(codigoDeUnion('  abc-123 '), 'abc123');
  });
}
