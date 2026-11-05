import 'package:flutter_test/flutter_test.dart';
import 'package:venue_mobile/features/clubs/data/clubs.dart';

Club club(String logistica, {bool exige = false}) => Club(
  id: 'x',
  nombre: 'X',
  logistica: logistica,
  exigeComprobante: exige,
);

void main() {
  group('las tres formas de trabajar', () {
    test('a mano: el relacionador vende y sube el comprobante', () {
      final c = club('bt', exige: true);
      expect(c.ventaAMano, isTrue);
      expect(c.exigeComprobante, isTrue);
    });

    test('con AFTR: el relacionador sólo comparte su enlace', () {
      for (final l in ['aftr_jefes', 'premium']) {
        expect(club(l).ventaAMano, isFalse, reason: l);
      }
    });

    test('un boliche sin logística guardada trabaja a mano', () {
      // los que ya existían vienen de antes de que esto existiera
      expect(Club.desde({'id': 'x', 'nombre': 'X'}).logistica, 'bt');
      expect(Club.desde({'id': 'x', 'nombre': 'X'}).ventaAMano, isTrue);
    });
  });
}
