import 'package:flutter_test/flutter_test.dart';
import 'package:venue_mobile/features/vip_tables/data/mesas.dart';

/// Mesas de la planta baja de SitRoom (x, y, w, h en % del plano).
Mesa _m(String id, double x, double y, double w, double h) => Mesa.desde({
      'id': id,
      'evento_id': 'e',
      'planta': 'baja',
      'etiqueta': id,
      'categoria': 'mesa',
      'x': x,
      'y': y,
      'w': w,
      'h': h,
      'estado': 'disponible',
    });

void main() {
  final m2 = _m('2', 74.5, 81.4, 7, 6);
  final m3 = _m('3', 74.5, 74.9, 7, 6);
  final m4 = _m('4', 74.5, 68.6, 7, 6);
  final m5 = _m('5', 61.1, 66.1, 7, 6);
  final m13 = _m('13', 27.6, 38.4, 9, 15);
  final m14 = _m('14', 12.4, 34.2, 7, 6);
  final m12 = _m('12', 3.1, 83.0, 9, 6);

  test('las mesas pegadas están dentro del radio', () {
    expect(distanciaMesas(m3, m4), lessThan(radioJuntarMesas));
    expect(distanciaMesas(m4, m5), lessThan(radioJuntarMesas));
  });

  test('las separadas por la pista no', () {
    expect(distanciaMesas(m13, m14), greaterThan(radioJuntarMesas));
    expect(distanciaMesas(m2, m12), greaterThan(radioJuntarMesas));
  });

  test('se encadena una fila, pero no se salta a una lejana', () {
    final unidas = mesasEncadenadas(m2, [m3, m4, m5, m12]);
    expect(unidas, containsAll(['3', '4', '5']));
    expect(unidas, isNot(contains('12')));
  });

  test('si se saca la del medio, la que colgaba de ella queda afuera', () {
    expect(distanciaMesas(m2, m5), greaterThan(radioJuntarMesas));
    expect(mesasEncadenadas(m2, [m5]), isEmpty);
  });
}
