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
    // un evento gratis es válido, pero sólo si la comisión por manilla
    // también baja: con el 15 fijo de antes, "Crear evento" fallaba y el
    // campo para corregirlo ni siquiera estaba dibujado
    expect(v(p: 0, c: 15), contains('comisión'));
    expect(v(p: 0, c: 0), isNull);
  });

  test('los eventos se agrupan por tramo y en el orden en que se buscan', () {
    final ahora = DateTime(2026, 11, 5, 23);
    Map<String, dynamic> e(String id, String fecha) => {
      'id': id,
      'fecha': fecha,
    };
    final g = agruparPorTramo([
      e('viejo', '2026-10-01'),
      e('lejano', '2026-12-20'),
      e('hoy', '2026-11-05'),
      e('anteayer', '2026-11-03'),
      e('mañana', '2026-11-06'),
    ], ahora);

    expect(g.map((x) => x.tramo).toList(), [
      TramoEvento.hoy,
      TramoEvento.proximo,
      TramoEvento.pasado,
    ]);
    expect(g[0].eventos.map((x) => x['id']), ['hoy']);
    // los que vienen, del más cercano al más lejano
    expect(g[1].eventos.map((x) => x['id']), ['mañana', 'lejano']);
    // los pasados, del más reciente al más viejo
    expect(g[2].eventos.map((x) => x['id']), ['anteayer', 'viejo']);
  });

  test('un evento de hoy no es pasado aunque ya haya empezado', () {
    final ahora = DateTime(2026, 11, 5, 23, 59);
    expect(tramoDeEvento(DateTime(2026, 11, 5), ahora), TramoEvento.hoy);
    expect(tramoDeEvento(DateTime(2026, 11, 4), ahora), TramoEvento.pasado);
    expect(tramoDeEvento(DateTime(2026, 11, 6), ahora), TramoEvento.proximo);
  });

  test('sin eventos de un tramo, ese tramo no aparece', () {
    final g = agruparPorTramo([
      {'id': 'a', 'fecha': '2026-12-01'},
    ], DateTime(2026, 11, 5));
    expect(g.length, 1);
    expect(g.single.tramo, TramoEvento.proximo);
  });

  test('acciones según el estado del evento', () {
    expect(accionesDeEvento({'publicado': false, 'estado': 'proximo'}).publicar, isTrue);
    expect(accionesDeEvento({'publicado': true, 'estado': 'proximo'}).publicar, isFalse);
    final cerrado = accionesDeEvento({'publicado': true, 'estado': 'cerrado'});
    expect((cerrado.cerrar, cerrado.eliminar), (false, true));
  });
}
