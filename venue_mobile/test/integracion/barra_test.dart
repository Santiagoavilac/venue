import 'package:flutter_test/flutter_test.dart';
import 'package:supabase/supabase.dart';
import 'package:venue_mobile/core/sync/cola_offline.dart';
import 'package:venue_mobile/features/bar/data/barra.dart';

import 'demo.dart';

void main() {
  late SupabaseClient prop, barra, deposito, rrpp, admin;
  late BarraRepository rP, rB;
  late String ev, barraId, bebida;

  num mlDe(List<Fila> stock) =>
      stock.firstWhere((s) => s['bebida_id'] == bebida)['ml_total'] as num;

  setUpAll(() async {
    if (saltear != null) return;
    prop = await sesionDe('propietario.aurora');
    barra = await sesionDe('barra.aurora');
    deposito = await sesionDe('deposito.aurora');
    rrpp = await sesionDe('rrpp.aurora');
    admin = await sesionDe('admin.aurora');
    rP = BarraRepository(prop);
    rB = BarraRepository(barra);
    ev = await eventoDe(prop, 'aurora');
    barraId = (await rP.barras('aurora')).first['id'] as String;
    bebida = (await rP.bebidas('aurora')).firstWhere((b) => b['nombre'] == 'Vodka Demo')['id'] as String;
    await rP.asignar(ev, barraId, barra.auth.currentUser!.id, true);
  });

  test('recepción: el depósito ingresa mercadería y la ve en "lo mío"', () async {
    final antes = mlDe(await rP.stock('aurora'));
    final r = await BarraRepository(deposito).recibir(bebida, 2, notas: 'prueba app');
    expect((r['botellas'], r['ml']), (2, 1500));
    expect(mlDe(await rP.stock('aurora')), antes + 1500);
    expect((await BarraRepository(deposito).misRecepciones()).first['cant_inicial'], 2);
    // un relacionador no recibe mercadería ni ve el stock
    await expectLater(BarraRepository(rrpp).recibir(bebida, 1), throwsA(isA<PostgrestException>()));
    expect(await BarraRepository(rrpp).stock('aurora'), isEmpty);
  }, skip: saltear);

  test('venta: descuenta el stock de la receta; reenviada con la misma clave no duplica', () async {
    final carta = await rB.carta('aurora', barraId);
    final tonic = carta.firstWhere((t) => t.nombre == 'Vodka Tonic Demo');
    expect(tonic.precio, 35);
    final antes = mlDe(await rP.stock('aurora'));
    final carrito = Carrito()..sumar(tonic)..sumar(tonic)..sumar(tonic);
    final args = BarraRepository.argsDeVenta(
        eventoId: ev, barraId: barraId, items: carrito.items(), clave: nuevoId());
    final a = Map<String, dynamic>.from(await barra.rpc('bar_vender', params: args) as Map);
    final b = Map<String, dynamic>.from(await barra.rpc('bar_vender', params: args) as Map);
    expect((a['total'], a['venta']), (105, b['venta']));
    // 3 vasos × 50 ml, una sola vez
    expect(mlDe(await rP.stock('aurora')), antes - 150);

    // el bartender anula SU venta: el stock vuelve
    final ultima = (await rB.ultimaVentaMia(ev))!;
    expect(ultima['id'], a['venta']);
    await rB.anular(ultima['id'] as String, 'Prueba app');
    expect(mlDe(await rP.stock('aurora')), antes);
    await expectLater(rB.anular(ultima['id'] as String, 'otra vez'),
        throwsA(isA<PostgrestException>()));
  }, skip: saltear);

  test('no se vende más de lo que hay en stock', () async {
    final tonic = (await rB.carta('aurora', barraId)).firstWhere((t) => t.nombre == 'Vodka Tonic Demo');
    final args = BarraRepository.argsDeVenta(eventoId: ev, barraId: barraId,
        items: [{'trago_id': tonic.id, 'qty': tonic.alcanzaPara + 1}], clave: nuevoId());
    await expectLater(barra.rpc('bar_vender', params: args), throwsA(isA<PostgrestException>()));
  }, skip: saltear);

  test('quién vende: solo roles de barra de ese boliche, y el bartender solo en su turno', () async {
    final tonic = (await rB.carta('aurora', barraId)).first;
    Fila args() => BarraRepository.argsDeVenta(eventoId: ev, barraId: barraId,
        items: [{'trago_id': tonic.id, 'qty': 1}], clave: nuevoId());
    await expectLater(rrpp.rpc('bar_vender', params: args()), throwsA(isA<PostgrestException>()));
    await expectLater(admin.from('bebidas').select('id').eq('club_id', 'nebula'), completion(isEmpty));
    await expectLater(BarraRepository(barra).carta('nebula', barraId), throwsA(isA<PostgrestException>()));
    // sin turno asignado, el bartender no tiene barras donde vender
    await rP.asignar(ev, barraId, barra.auth.currentUser!.id, false);
    expect(await rB.misBarras('aurora', ev, soloAsignadas: true), isEmpty);
    await rP.asignar(ev, barraId, barra.auth.currentUser!.id, true);
    expect((await rB.misBarras('aurora', ev, soloAsignadas: true)).single['id'], barraId);
    // el bartender no ve costos ni toca el catálogo
    await expectLater(rB.crearTrago('aurora', 'Pirata', 1), throwsA(isA<PostgrestException>()));
    await expectLater(rB.proyeccion('aurora', 500), throwsA(isA<PostgrestException>()));
  }, skip: saltear);

  test('carta y recetas: el propietario crea un trago, le pone receta y lo activa', () async {
    for (final t in (await rP.tragos('aurora')).where((t) => '${t['nombre']}'.startsWith('ZZ'))) {
      await prop.from('tragos').delete().eq('id', t['id'] as String);
    }
    await rP.crearTrago('aurora', 'ZZ Trago Prueba', 40);
    var t = (await rP.tragos('aurora')).firstWhere((t) => t['nombre'] == 'ZZ Trago Prueba');
    expect(t['activo'], false);
    expect((await rB.carta('aurora', barraId)).any((x) => x.id == t['id']), isFalse);
    await rP.agregarAReceta(t['id'] as String, bebida, 60);
    await rP.editarTrago(t['id'] as String, {'activo': true});
    final enCarta = (await rB.carta('aurora', barraId)).firstWhere((x) => x.id == t['id']);
    expect(enCarta.precio, 40);
    expect(enCarta.alcanzaPara, greaterThan(0));
    t = (await rP.tragos('aurora')).firstWhere((x) => x['id'] == t['id']);
    await rP.quitarDeReceta((t['r'] as List).single['id'] as String);
    await prop.from('tragos').delete().eq('id', t['id'] as String);
  }, skip: saltear);

  test('conteo de la noche: ajusta solo lo contado y no revierte lo demás', () async {
    final pend = await rP.conteoPendiente(ev, 'cierre');
    expect(pend, isNotEmpty);
    final lote = pend.first;
    final sistema = lote['ml_sistema'] as num;
    await rP.grabarConteo(ev, 'cierre', {lote['lote_id'] as String: sistema - 30});
    final despues = await rP.conteoPendiente(ev, 'cierre');
    expect(despues.firstWhere((l) => l['lote_id'] == lote['lote_id'])['ml_sistema'], sistema - 30);
    for (final l in pend.skip(1)) {
      expect(despues.firstWhere((x) => x['lote_id'] == l['lote_id'])['ml_sistema'], l['ml_sistema']);
    }
    // el ajuste queda en los movimientos, con quién lo hizo
    final mov = await rP.movimientos('aurora');
    expect(mov.first['quien'], 'Olga Propietaria');
    // se devuelve al valor anterior para no ensuciar el demo
    await rP.ajustar(lote['lote_id'] as String, sistema, eventoId: ev, motivo: 'fin de prueba');
  }, skip: saltear);

  test('cierre y analítica: lo ve el propietario, no el bartender', () async {
    await barra.rpc('bar_vender', params: BarraRepository.argsDeVenta(eventoId: ev, barraId: barraId,
        items: [{'trago_id': (await rB.carta('aurora', barraId)).first.id, 'qty': 1}], clave: nuevoId()));
    final cierre = await rP.cierre(ev);
    expect(cierre.single['barra'], 'Barra principal');
    expect(cierre.single['bs'] as num, greaterThan(0));
    final a = await rP.analitica(ev);
    expect(a.evento!['ingresos'] as num, greaterThan(0));
    expect(a.margen!['margen_neto'], isNotNull);
    expect(a.top, isNotEmpty);
    expect(await rP.proyeccion('aurora', 500), isNotEmpty);
    expect(await rP.cupoCortesia('aurora'), isA<int>());
    await (await rB.ultimaVentaMia(ev)).let((u) => rB.anular(u!['id'] as String, 'fin de prueba'));
  }, skip: saltear);
}

extension<T> on T {
  R let<R>(R Function(T) f) => f(this);
}
