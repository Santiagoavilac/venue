import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:supabase/supabase.dart';
import 'package:venue_mobile/core/sync/cola_offline.dart';
import 'package:venue_mobile/features/payments/data/pagos.dart';

import 'demo.dart';

// único por corrida: los pagos verificados no se borran del demo
final concepto = 'Prueba app ${DateTime.now().millisecondsSinceEpoch}';

void main() {
  late SupabaseClient admin, jefe, rrpp, rrpp2, portero, adminN;
  late String ev;

  setUpAll(() async {
    if (saltear != null) return;
    admin = await sesionDe('admin.aurora');
    jefe = await sesionDe('jefe.aurora');
    rrpp = await sesionDe('rrpp.aurora');
    rrpp2 = await sesionDe('rrpp2.aurora');
    portero = await sesionDe('portero.aurora');
    adminN = await sesionDe('admin.nebula');
    ev = await eventoDe(admin, 'aurora');
  });

  test('el mismo pago enviado dos veces (o a la vez) se registra una sola', () async {
    final repo = PagosRepository(rrpp);
    final clave = nuevoId();
    Future<String> enviar() => repo.crear(
        eventoId: ev, monto: 135, concepto: concepto, clave: clave);
    final ids = await Future.wait([enviar(), enviar(), enviar()]);
    final otra = await enviar();
    expect({...ids, otra}.length, 1);
    final mios = (await repo.lista(ev)).where((p) => p.concepto == concepto);
    expect(mios.length, 1);
    expect((mios.first.estado, mios.first.monto), ('pendiente', 135));
  }, skip: saltear);

  test('quién ve qué: el rrpp lo suyo, el jefe su team, el admin todo', () async {
    final delRrpp = await PagosRepository(rrpp).lista(ev);
    expect(delRrpp, isNotEmpty);
    expect(delRrpp.every((p) => p.rrppId == rrpp.auth.currentUser!.id), isTrue);
    expect((await PagosRepository(rrpp2).lista(ev))
        .any((p) => p.concepto == concepto), isFalse);
    expect((await PagosRepository(jefe).lista(ev))
        .any((p) => p.concepto == concepto), isTrue);
    expect((await PagosRepository(admin).lista(ev))
        .any((p) => p.concepto == concepto), isTrue);
    expect(await PagosRepository(portero).lista(ev), isEmpty);
    expect(await PagosRepository(adminN).lista(ev), isEmpty);
  }, skip: saltear);

  test('solo el admin avanza el estado; adjuntar una captura no verifica', () async {
    final p = (await PagosRepository(rrpp).lista(ev))
        .firstWhere((p) => p.concepto == concepto);
    await PagosRepository(rrpp).adjuntar(p.id, 'https://x/storage/v1/object/public/comprobantes/u/captura.jpg');
    var x = (await PagosRepository(admin).lista(ev)).firstWhere((q) => q.id == p.id);
    expect((x.estado, x.comprobante != null), ('pendiente', true));

    for (final sb in [rrpp, jefe]) {
      await expectLater(PagosRepository(sb).avanzar(p.id, 'verificado'),
          throwsA(isA<PostgrestException>()));
    }
    await expectLater(PagosRepository(adminN).avanzar(p.id, 'verificado'),
        throwsA(isA<PostgrestException>()));

    await PagosRepository(admin).avanzar(p.id, 'pagado');
    await PagosRepository(admin).avanzar(p.id, 'verificado');
    x = (await PagosRepository(admin).lista(ev)).firstWhere((q) => q.id == p.id);
    expect(x.verificado, isTrue);
    // verificado: ya no se le cambia la captura
    await expectLater(PagosRepository(rrpp).adjuntar(p.id, 'otra'),
        throwsA(isA<PostgrestException>()));
  }, skip: saltear);

  test('rendición del relacionador con datos reales', () async {
    final repo = PagosRepository(rrpp);
    final uid = rrpp.auth.currentUser!.id;
    final vendidas = await repo.misVendidas(ev, uid);
    expect(vendidas, greaterThanOrEqualTo(3));
    final comision = await repo.miComision(ev, uid);
    final r = rendicion(vendidas: vendidas, precio: 100, comision: comision, yaRendido: 135);
    expect(r.recaudado, vendidas * 100);
    expect(r.aRendir, vendidas * 100 - vendidas * comision - 135);
  }, skip: saltear);

  test('el portero y un monto inválido no registran pagos', () async {
    await expectLater(
        PagosRepository(portero).crear(eventoId: ev, monto: 50, concepto: 'x', clave: nuevoId()),
        throwsA(isA<PostgrestException>()));
    await expectLater(
        PagosRepository(rrpp).crear(eventoId: ev, monto: 0, concepto: 'x', clave: nuevoId()),
        throwsA(isA<PostgrestException>()));
  }, skip: saltear);

  test('QR de cobro: el jefe sube el de su team y su relacionador lo ve; un rrpp no puede', () async {
    final img = Uint8List.fromList([0xff, 0xd8, 0xff, 0xd9]);
    await PagosRepository(jefe).guardarQrDeMiTeam(img);
    final team = (await rrpp.from('profiles').select('team_id')
        .eq('id', rrpp.auth.currentUser!.id).single())['team_id'] as String;
    expect(bytesDeDataUri(await PagosRepository(rrpp).qrDelTeam(team)), img);
    await expectLater(PagosRepository(rrpp).guardarQrDeMiTeam(img),
        throwsA(isA<PostgrestException>()));
  }, skip: saltear);

  test('QRs del boliche: los administra solo el admin', () async {
    final r = PagosRepository(admin);
    for (final q in (await r.qrs('aurora')).where((q) => q.nombre.startsWith('ZZ'))) {
      await r.borrarQr(q.id);
    }
    await r.crearQr('aurora', 'ZZ Cuenta Prueba', 'https://example.com/qr.jpg', 9);
    var q = (await r.qrs('aurora')).firstWhere((q) => q.nombre == 'ZZ Cuenta Prueba');
    await r.activarQr(q.id, false);
    q = (await r.qrs('aurora')).firstWhere((x) => x.id == q.id);
    expect(q.activo, isFalse);
    await expectLater(
        PagosRepository(rrpp).crearQr('aurora', 'pirata', 'https://x', 1),
        throwsA(isA<PostgrestException>()));
    await r.borrarQr(q.id);
    expect((await r.qrs('aurora')).any((x) => x.id == q.id), isFalse);
  }, skip: saltear);
}
