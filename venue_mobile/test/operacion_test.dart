import 'package:flutter_test/flutter_test.dart';
import 'package:venue_mobile/features/analytics/data/reporte.dart';
import 'package:venue_mobile/features/events/data/eventos.dart';

Evento _ev(Map<String, dynamic> extra) => Evento.desde({
      'id': 'e', 'nombre': 'N', 'fecha': '2026-11-06', 'estado': 'proximo',
      'precio_manilla': 60, 'pct_boliche': 40, ...extra,
    });

void main() {
  test('parte del boliche por manilla según la operación del evento', () {
    // cuenta vieja: el 50 % de siempre, aunque el evento diga otra cosa
    expect(_ev({}).pctBolicheManillas, 0.5);
    // operación nueva: el % del evento
    expect(_ev({'config_v2': true, 'modo_comision': 'jefes'}).pctBolicheManillas, 0.4);
    // sin comisión por manillas o sin comisiones: la manilla es del boliche
    expect(_ev({'config_v2': true, 'comision_manillas': false}).pctBolicheManillas, 1);
    expect(_ev({'config_v2': true, 'modo_comision': 'ninguno'}).pctBolicheManillas, 1);
  });

  test('la liquidación usa la parte del boliche que se le pasa', () {
    final l = liquidacion(
      brutoPrepagadasIngresadas: 600, totalMesas: 100, puertaIngresaron: 2, puertaPrecio: 50,
      pctBoliche: 0.4,
    );
    expect((l.prepagadas, l.puerta, l.total), (240, 40, 300));
    // sin pasarla, el 50 % de siempre
    expect(liquidacion(brutoPrepagadasIngresadas: 600, totalMesas: 0, puertaIngresaron: 0, puertaPrecio: 0).total, 300);
  });
}
