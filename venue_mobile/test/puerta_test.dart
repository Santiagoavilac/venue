import 'package:flutter_test/flutter_test.dart';
import 'package:venue_mobile/core/widgets/avisos.dart';
import 'package:venue_mobile/features/access_control/data/persona_puerta.dart';

PersonaPuerta p(String nombre,
        {String? ingreso, String? filtro, bool casa = false, bool entrada = false}) =>
    PersonaPuerta.desde({
      'tipo': entrada ? 'entrada' : 'lista',
      'nombre': nombre,
      'id': nombre,
      'sin_tope': casa,
      'ingreso_at': ingreso,
      'filtro_at': filtro,
    });

void main() {
  test('fila de entrada y de lista desde el servidor', () {
    final e = PersonaPuerta.desde({
      'tipo': 'entrada', 'nombre': 'Ana', 'code': 'ABC', 'lista': 'Mesa B2',
      'estado': 'anulada', 'sin_tope': true,
    });
    expect(e.esEntrada, isTrue);
    expect(e.anulada, isTrue);
    expect(e.sinTope, isTrue);
    expect(e.ingreso, isFalse);
    // las filas de lista no traen code ni estado
    final l = PersonaPuerta.desde({'tipo': 'lista', 'nombre': 'Luis', 'id': 'r1', 'rrpp': 'Mateo'});
    expect(l.esEntrada, isFalse);
    expect(l.codigo, isNull);
    expect(l.anulada, isFalse);
  });

  test('orden: ingresados (reciente primero), pendientes por nombre, filtrados al fondo', () {
    final r = PersonaPuerta.ordenar([
      p('Zoe'),
      p('Filtrado', filtro: '2026-10-13T22:00:00Z'),
      p('Entró temprano', ingreso: '2026-10-13T22:00:00Z'),
      p('ana'),
      p('Entró recién', ingreso: '2026-10-13T23:30:00Z'),
    ]);
    expect(r.map((x) => x.nombre),
        ['Entró recién', 'Entró temprano', 'ana', 'Zoe', 'Filtrado']);
  });

  test('filtro discreto: solo quedan los de la casa', () {
    final filas = [p('Común'), p('De la casa', casa: true, entrada: true)];
    expect(PersonaPuerta.ordenar(filas, discreto: true).map((x) => x.nombre),
        ['De la casa']);
    expect(PersonaPuerta.ordenar(filas).length, 2);
    expect(PersonaPuerta.ordenar([p('Común')], discreto: true), isEmpty);
  });

  test('relacionador', () {
    final r = Relacionador.desde({'nombre': 'Julián', 'usuario': 'jefe.aurora', 'rol': 'jefe', 'team': 'Team Norte'});
    expect(r.esJefe, isTrue);
    expect(Relacionador.desde({'nombre': 'x'}).team, 'Sin team');
  });

  test('normalizar quita tildes para buscar', () {
    expect(normalizar('José Ñandú'), 'jose nandu');
    expect(normalizar('JULIÁN').contains(normalizar('julian')), isTrue);
  });

  test('hora corta', () {
    expect(horaCorta(DateTime(2026, 1, 1, 2, 5)), '02:05');
  });
}
