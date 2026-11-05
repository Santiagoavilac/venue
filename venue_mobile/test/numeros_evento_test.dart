import 'package:flutter_test/flutter_test.dart';
import 'package:venue_mobile/features/events/data/gestion.dart';

void main() {
  test('adentro es la gente de lista que entró más los QR usados', () {
    const n = (
      anotados: 120,
      ingresaron: 80,
      entradas: 50,
      qrUsados: 30,
      mesas: 12,
    );
    expect(adentroDe(n), 110);
  });

  test('sin nadie adentro da cero, no null ni "…"', () {
    const n = (anotados: 0, ingresaron: 0, entradas: 0, qrUsados: 0, mesas: 0);
    expect(adentroDe(n), 0);
  });
}
