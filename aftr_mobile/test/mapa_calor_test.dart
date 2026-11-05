import 'package:aftr_mobile/data/modelos.dart';
import 'package:aftr_mobile/features/mapa/mapa_screen.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  _corrimiento();
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

// El corrimiento de la cámara por la hoja estaba en grados fijos (0,0035°):
// a zoom de ciudad son unos metros y a zoom de calle, 390 m. Por eso al
// acercarse, elegir un boliche mandaba el mapa a cualquier lado.
void _corrimiento() {
  test('el corrimiento de la cámara es el mismo en pantalla a cualquier zoom', () {
    const lat = -17.78, alto = 844.0; // un iPhone de pie
    final px = <double>[];
    for (var z = 11.0; z <= 18.0; z += 1) {
      final grados = gradosDeAlto(alto * 0.18 / 2, z, lat);
      // de vuelta a píxeles: tiene que dar siempre lo mismo
      px.add(grados * 111320 / metrosPorPixel(z, lat));
    }
    for (final p in px) {
      expect(p, closeTo(px.first, 0.001));
    }
    // y en grados cambia muchísimo, que es lo que antes estaba fijo
    expect(gradosDeAlto(76, 11, lat), greaterThan(gradosDeAlto(76, 18, lat) * 100));
  });
}
