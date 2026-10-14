import 'package:flutter_test/flutter_test.dart';
import 'package:venue_mobile/features/bar/data/barra.dart';

void main() {
  const tonic = TragoCarta(id: 't', nombre: 'Vodka Tonic', precio: 35, categoria: 'x', alcanzaPara: 2);
  const ron = TragoCarta(id: 'r', nombre: 'Ron Cola', precio: 30, categoria: 'x', alcanzaPara: 0);

  test('carrito: suma hasta donde alcanza el stock, resta y calcula el total', () {
    final c = Carrito();
    expect(c.vacio, isTrue);
    expect(c.sumar(tonic), isTrue);
    expect(c.sumar(tonic), isTrue);
    expect(c.sumar(tonic), isFalse); // alcanza para 2
    expect(c.sumar(ron), isFalse);   // sin stock
    expect((c.vasos, c.total([tonic, ron])), (2, 70));
    expect(c.items(), [{'trago_id': 't', 'qty': 2}]);
    c.restar('t');
    expect(c.de('t'), 1);
    c.restar('t');
    expect(c.vacio, isTrue);
    expect(c.items(), isEmpty);
  });

  test('venta: una cortesía nunca viaja como cobro', () {
    final a = BarraRepository.argsDeVenta(
        eventoId: 'e', barraId: 'b', items: const [], cortesiaDe: 'u', forma: 'efectivo', clave: 'k');
    expect((a['p_forma_pago'], a['p_cortesia_de'], a['p_client_key']), ('cortesia', 'u', 'k'));
    expect(BarraRepository.argsDeVenta(eventoId: 'e', barraId: 'b', items: const [], forma: 'qr', clave: 'k')['p_forma_pago'], 'qr');
  });

  test('conteo físico en ml y botellas equivalentes', () {
    expect(mlContados(botellasCerradas: 3, mlAbierta: 200, volumenMl: 750), 2450);
    expect(botellasDe(2900, 750), '3.9');
    expect(botellasDe(100, 0), '0');
  });
}
