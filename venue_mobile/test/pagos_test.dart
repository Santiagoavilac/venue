import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:venue_mobile/features/payments/data/pagos.dart';

void main() {
  test('comisión por manilla: acuerdo propio, si no el del evento, si no porcentajes', () {
    expect(comisionPorManilla(cutPersona: 20, cutEvento: 15, precio: 60, pctBoliche: 50, pctRrpp: 50), 20);
    expect(comisionPorManilla(cutEvento: 15, precio: 60, pctBoliche: 50, pctRrpp: 50), 15);
    expect(comisionPorManilla(precio: 100, pctBoliche: 50, pctRrpp: 50), 25);
    // el acuerdo propio puede ser 0: sigue mandando sobre el del evento
    expect(comisionPorManilla(cutPersona: 0, cutEvento: 15, precio: 60, pctBoliche: 50, pctRrpp: 50), 0);
  });

  test('rendición: cobrado − comisión − ya rendido, nunca negativa', () {
    final r = rendicion(vendidas: 10, precio: 60, comision: 15, yaRendido: 200);
    expect((r.recaudado, r.genero, r.aRendir, r.netoPorManilla), (600, 150, 250, 45));
    expect(rendicion(vendidas: 2, precio: 60, comision: 15, yaRendido: 500).aRendir, 0);
    expect(rendicion(vendidas: 0, precio: 60, comision: 80, yaRendido: 0).netoPorManilla, 0);
  });

  test('estados: solo avanzan pendiente → pagado → verificado', () {
    Pago p(String e) => Pago.desde({
          'id': '1', 'rrpp_id': 'u', 'monto': 100, 'estado': e,
          'created_at': '2026-10-13T22:00:00Z', 'p': {'nombre': 'Mateo'},
        });
    expect(p('pendiente').siguiente, 'pagado');
    expect(p('pagado').siguiente, 'verificado');
    expect(p('verificado').siguiente, isNull);
    expect(p('verificado').verificado, isTrue);
    expect(p('pendiente').rrppNombre, 'Mateo');
  });

  test('QR de team guardado como data-URI', () {
    final bytes = [1, 2, 3, 250];
    expect(bytesDeDataUri('data:image/jpeg;base64,${base64Encode(bytes)}'), bytes);
    expect(bytesDeDataUri('https://x/qr.jpg'), isNull);
    expect(bytesDeDataUri('data:roto'), isNull);
    expect(bytesDeDataUri(null), isNull);
  });
}
