import 'package:flutter_test/flutter_test.dart';
import 'package:venue_mobile/features/access_control/data/qr.dart';

void main() {
  const ev = '4a2a7564-0ccf-40dc-bef9-c027cf140792';

  test('entrada con prefijo EVT', () {
    final q = QrLeido.interpretar('EVT:$ev:a2f9b1')!;
    expect(q.codigo, 'A2F9B1');
    expect(q.esLista, isFalse);
    expect(q.eventoId, ev);
    expect(q.esDeOtroEvento(ev), isFalse);
  });

  test('invitado de lista con separador |', () {
    final q = QrLeido.interpretar('LST|$ev|0C11FE')!;
    expect(q.esLista, isTrue);
    expect(q.codigo, '0C11FE');
  });

  test('QR de otro evento', () {
    final q = QrLeido.interpretar('EVT:otro-evento:ABC123')!;
    expect(q.esDeOtroEvento(ev), isTrue);
  });

  test('el id del evento se compara sin importar mayúsculas', () {
    final q = QrLeido.interpretar('EVT:${ev.toUpperCase()}:ABC123')!;
    expect(q.esDeOtroEvento(ev), isFalse);
  });

  test('código suelto tipeado, con # y espacios', () {
    final q = QrLeido.interpretar('  #a2f9b1 ')!;
    expect(q.codigo, 'A2F9B1');
    expect(q.eventoId, isNull);
    expect(q.esDeOtroEvento(ev), isFalse);
  });

  test('vacío o solo # no es un código', () {
    expect(QrLeido.interpretar(''), isNull);
    expect(QrLeido.interpretar('   '), isNull);
    expect(QrLeido.interpretar('#'), isNull);
    expect(QrLeido.interpretar(null), isNull);
  });
}
