import 'package:flutter_test/flutter_test.dart';
import 'package:venue_mobile/features/events/data/gestion.dart';

void main() {
  test('validación de evento antes de enviar', () {
    String? v({String n = 'Noche', String f = '2026-12-31', num p = 60, num pct = 50, num c = 15}) =>
        validarEvento(nombre: n, fecha: f, precio: p, pctBoliche: pct, cut: c);
    expect(v(), isNull);
    expect(v(n: '  '), contains('nombre'));
    expect(v(f: '31/12/2026'), contains('Fecha'));
    expect(v(p: -1), contains('precio'));
    expect(v(pct: 120), contains('%'));
    expect(v(c: 70), contains('comisión')); // más que el precio
  });

  test('acciones según el estado del evento', () {
    expect(accionesDeEvento({'publicado': false, 'estado': 'proximo'}).publicar, isTrue);
    expect(accionesDeEvento({'publicado': true, 'estado': 'proximo'}).publicar, isFalse);
    final cerrado = accionesDeEvento({'publicado': true, 'estado': 'cerrado'});
    expect((cerrado.cerrar, cerrado.eliminar), (false, true));
  });
}
