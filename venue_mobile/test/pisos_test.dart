import 'package:flutter_test/flutter_test.dart';
import 'package:venue_mobile/features/vip_tables/data/mesas.dart';

Mesa _m(String planta, [String cat = 'mesa']) => Mesa.desde({
      'id': '$planta-$cat', 'evento_id': 'e', 'planta': planta, 'etiqueta': 'M1', 'categoria': cat,
    });

void main() {
  test('pisos: primero los de siempre, después los propios por nombre', () {
    expect(pisosDe([_m('baja'), _m('Terraza'), _m('alta')], extra: ['Rooftop']),
        ['alta', 'baja', 'Rooftop', 'Terraza']);
  });
  test('sin mesas ni pisos: planta alta y baja', () {
    expect(pisosDe(const []), ['alta', 'baja']);
  });
  test('un piso escrito con el nombre de uno de siempre vuelve a su id', () {
    expect(idDePiso(' planta alta '), 'alta');
    expect(idDePiso('Terraza'), 'Terraza');
    expect(nombrePiso('piso2'), 'Piso 2');
  });
  test('tipos: VIP y box se dibujan como lounge, mesa alta como mesa', () {
    expect(_m('alta', 'vip').esLounge, isTrue);
    expect(_m('alta', 'box').esLounge, isTrue);
    expect(_m('alta', 'mesa_alta').esLounge, isFalse);
    expect(_m('alta', 'algo_raro').tipo.nombre, 'algo_raro');
  });
}
