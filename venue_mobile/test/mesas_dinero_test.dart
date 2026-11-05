import 'package:flutter_test/flutter_test.dart';
import 'package:venue_mobile/features/vip_tables/data/mesas.dart';

void main() {
  group('a quién le corresponde ver plata de mesas', () {
    test('el admin siempre: es su recaudación', () {
      expect(
        veDineroDeMesas(esAdmin: true, esPortero: false, comisionMesas: false),
        isTrue,
      );
    });

    test('el relacionador sólo si el evento paga comisión por mesa', () {
      expect(
        veDineroDeMesas(esAdmin: false, esPortero: false, comisionMesas: true),
        isTrue,
      );
      // sin comisión, lo que entra por mesas es del boliche: mostrarle un
      // total "tuyo" sería mentirle
      expect(
        veDineroDeMesas(esAdmin: false, esPortero: false, comisionMesas: false),
        isFalse,
      );
    });

    test('el portero nunca: en la puerta no se maneja plata', () {
      expect(
        veDineroDeMesas(esAdmin: false, esPortero: true, comisionMesas: true),
        isFalse,
      );
    });
  });
}
