import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:venue_mobile/core/theme/apariencia.dart';
import 'package:venue_mobile/core/theme/venue_theme.dart';

void main() {
  test('sin nada guardado, la app abre en oscuro', () {
    expect(Apariencia.desde(null), Apariencia.oscura);
    expect(Apariencia.desde('cualquiera'), Apariencia.oscura);
    expect(Apariencia.desde('clara'), Apariencia.clara);
    expect(Apariencia.oscura.paleta.brillo, Brightness.dark);
  });

  test('el cromo sobre velo sale de la paleta oscura, no de grises propios', () {
    // Si alguien vuelve a inventar un gris para el ingreso o el tutorial, esto
    // avisa: tienen que ser los mismos colores del modo oscuro.
    expect(Oscuro.fondo, Paleta.oscura.fondo);
    expect(Oscuro.tarjeta, Paleta.oscura.superficie2);
    expect(Oscuro.campo, Paleta.oscura.superficieAlta);
    expect(Oscuro.texto, Paleta.oscura.texto);
    expect(Oscuro.suave, Paleta.oscura.textoSuave);
    expect(Oscuro.mal, Paleta.oscura.mal);
  });
}
