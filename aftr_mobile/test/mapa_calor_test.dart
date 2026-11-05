import 'package:aftr_mobile/data/modelos.dart';
import 'package:aftr_mobile/features/mapa/mapa_screen.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // El radio era 160 + 380 × intensidad metros, así que el que más vendió
  // dibujaba 540 m siempre: una mancha a zoom de ciudad, invisible a zoom de
  // calle. Ahora lo que es constante es lo que se ve en pantalla.
  test('el círculo mide lo mismo en pantalla entre zoom 11 y 17', () {
    const lat = -17.78; // Santa Cruz
    final medidas = <double>[];
    for (var z = 11.0; z <= 17.0; z += 1) {
      final metros = radioDeCalor(z, lat);
      medidas.add(metros / metrosPorPixel(z, lat));
    }
    for (final px in medidas) {
      expect(px, closeTo(medidas.first, 0.001));
    }
    // y en metros sí cambia: a zoom de calle es mucho más chico
    expect(radioDeCalor(17, lat), lessThan(radioDeCalor(11, lat) / 30));
  });

  test('la intensidad va en el color y la opacidad, no en el tamaño', () {
    const lugares = [
      Lugar(id: 'flojo', nombre: 'Flojo', lat: -17.78, lng: -63.18),
      Lugar(id: 'lleno', nombre: 'Lleno', lat: -17.78, lng: -63.18),
    ];
    final c = circulosDeCalor(lugares, {'flojo': 0.1, 'lleno': 1.0}, zoom: 14);
    // dos anillos por lugar, no tres
    expect(c.length, 4);
    double radio(String id) =>
        c.firstWhere((x) => x.circleId.value == 'calor-$id-0').radius;
    expect(radio('flojo'), radio('lleno'));
    double alfa(String id) =>
        c.firstWhere((x) => x.circleId.value == 'calor-$id-0').fillColor.a;
    expect(alfa('lleno'), greaterThan(alfa('flojo')));
  });
}
