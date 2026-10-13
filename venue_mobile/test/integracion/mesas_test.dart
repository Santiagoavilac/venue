import 'package:flutter_test/flutter_test.dart';
import 'package:supabase/supabase.dart';
import 'package:venue_mobile/features/vip_tables/data/mesas.dart';

import 'demo.dart';

void main() {
  late SupabaseClient admin, rrpp, rrpp2, portero;
  late MesasRepository rAdmin, rRrpp;
  late String ev, combo;

  setUpAll(() async {
    if (saltear != null) return;
    admin = await sesionDe('admin.aurora');
    rrpp = await sesionDe('rrpp.aurora');
    rrpp2 = await sesionDe('rrpp2.aurora');
    portero = await sesionDe('portero.aurora');
    rAdmin = MesasRepository(admin);
    rRrpp = MesasRepository(rrpp);
    ev = await eventoDe(admin, 'aurora');
    combo = (await rAdmin.combos('aurora')).firstWhere((c) => c.activo).id;
    // dejar el plano limpio por si una corrida anterior quedó a medias
    for (final m in (await rAdmin.mesas(ev)).where((m) => !m.libre)) {
      await rAdmin.estado(m.id, 'disponible');
    }
    for (final m in (await rAdmin.mesas(ev)).where((m) => m.etiqueta.startsWith('ZZ'))) {
      await rAdmin.borrar(m.id);
    }
    for (final c in (await rAdmin.combos('aurora')).where((c) => c.nombre.startsWith('ZZ'))) {
      await rAdmin.borrarCombo(c.id);
    }
  });

  Future<Mesa> una(String id) async => (await rAdmin.mesas(ev)).firstWhere((m) => m.id == id);
  Future<Mesa> libre() async => (await rAdmin.mesas(ev)).firstWhere((m) => m.libre);

  test('plano, combos y QR de cobro se leen', () async {
    expect((await rRrpp.mesas(ev)).length, greaterThanOrEqualTo(4));
    expect(await rRrpp.combos('aurora'), isNotEmpty);
    expect(await rRrpp.teams('aurora'), isNotEmpty);
    await rRrpp.qrCobro('aurora'); // puede ser null: no hay QR cargado en el demo
  }, skip: saltear);

  test('editor: crear, mover, redimensionar, cambiar de piso y eliminar', () async {
    final n = (await rAdmin.mesas(ev)).length;
    await rAdmin.crear(ev, 'alta', 'lounge', 900);
    var m = (await rAdmin.mesas(ev)).firstWhere((x) => x.etiqueta == 'M900');
    expect((m.esLounge, m.w, m.libre), (true, 18.0, true));

    final p = acotarPosicion(61.3, 33.8, m.w);
    await rAdmin.mover(m.id, p.x, p.y);
    await rAdmin.editarForma(m.id,
        etiqueta: 'ZZ1', categoria: 'mesa', w: 20, h: 30, teamId: null, planta: 'baja');
    m = await una(m.id);
    expect((m.x, m.y, m.w, m.h, m.etiqueta, m.planta, m.categoria),
        (61.5, 34.0, 20.0, 30.0, 'ZZ1', 'baja', 'mesa'));
    expect(pisosDe(await rAdmin.mesas(ev)), contains('baja'));

    await rAdmin.borrar(m.id);
    expect((await rAdmin.mesas(ev)).length, n);
  }, skip: saltear);

  test('solo el admin edita el plano', () async {
    final m = await libre();
    await rRrpp.mover(m.id, 1, 1); // RLS: no afecta ninguna fila
    final igual = await una(m.id);
    expect((igual.x, igual.y), (m.x, m.y));
    await expectLater(rRrpp.crear(ev, 'alta', 'mesa', 901), throwsA(isA<PostgrestException>()));
  }, skip: saltear);

  test('reserva → pago en efectivo → verificación del admin → liberar', () async {
    final m = await libre();
    final v = await rRrpp.vender([m.id],
        DatosVenta(cliente: 'Cliente App', comboId: combo, estado: 'reservada'));
    expect((v.primaria, v.precio), (m.id, 900));
    var x = await una(m.id);
    expect((x.estado, x.cliente, x.vendidoPor), ('reservada', 'Cliente App', rrpp.auth.currentUser!.id));
    expect(x.vence(3), isNotNull);

    // otro relacionador no la paga ni la libera
    await expectLater(MesasRepository(rrpp2).pagar(m.id, efectivo: true),
        throwsA(isA<PostgrestException>()));
    await expectLater(MesasRepository(rrpp2).estado(m.id, 'disponible'),
        throwsA(isA<PostgrestException>()));
    // y nadie la vende dos veces
    await expectLater(
        MesasRepository(rrpp2).vender([m.id],
            DatosVenta(cliente: 'Otro', comboId: combo, estado: 'reservada')),
        throwsA(isA<PostgrestException>()));

    await rRrpp.pagar(m.id, efectivo: true);
    x = await una(m.id);
    expect((x.estado, x.porVerificar, x.metodoPago), ('pagada', true, 'efectivo'));

    // verificar es del admin
    await expectLater(rRrpp.verificar(m.id, true), throwsA(isA<PostgrestException>()));
    await rAdmin.verificar(m.id, true);
    expect((await una(m.id)).pagoVerificado, isTrue);

    await rRrpp.estado(m.id, 'ocupada');
    expect((await una(m.id)).estado, 'ocupada');
    await rRrpp.estado(m.id, 'disponible');
    x = await una(m.id);
    expect(x.libre, isTrue);
    expect(x.cliente, isNull);
  }, skip: saltear);

  test('rechazo del pago: la mesa vuelve a reservada', () async {
    final m = await libre();
    await rRrpp.vender([m.id],
        DatosVenta(cliente: 'Rechazo App', comboId: combo, estado: 'pagada', efectivo: true));
    await rAdmin.verificar(m.id, false);
    expect((await una(m.id)).estado, 'reservada');
    await rAdmin.estado(m.id, 'disponible');
  }, skip: saltear);

  test('venta en grupo: varias mesas, una sola venta; liberar una libera todas', () async {
    final libres = (await rAdmin.mesas(ev)).where((m) => m.libre).take(2).toList();
    final v = await rRrpp.vender(libres.map((m) => m.id).toList(),
        DatosVenta(cliente: 'Grupo App', comboId: combo, estado: 'reservada', cantidad: 2));
    final a = await una(libres[0].id);
    expect(a.grupoId, isNotNull);
    final g = await rRrpp.grupo(a.grupoId!);
    expect(g.length, 2);
    expect(g.every((m) => m.estado == 'reservada' && m.cliente == 'Grupo App'), isTrue);
    expect(v.etiqueta, contains('+'));
    await rRrpp.estado(libres[1].id, 'disponible');
    expect((await rAdmin.mesas(ev)).where((m) => !m.libre), isEmpty);
  }, skip: saltear);

  test('el portero ve las mesas pero no vende', () async {
    final r = MesasRepository(portero);
    expect(await r.mesas(ev), isNotEmpty);
    await expectLater(
        r.vender([(await libre()).id],
            DatosVenta(cliente: 'Intruso', comboId: combo, estado: 'reservada')),
        throwsA(isA<PostgrestException>()));
  }, skip: saltear);

  test('combos: el admin crea, edita y borra; el rrpp no', () async {
    await rAdmin.guardarCombo('aurora',
        const Combo(id: '', nombre: 'ZZ Combo Prueba', precio: 500, categorias: ['lounge']),
        nuevo: true);
    var c = (await rAdmin.combos('aurora')).firstWhere((x) => x.nombre == 'ZZ Combo Prueba');
    expect(c.valePara(['mesa']), isFalse);
    await rAdmin.guardarCombo('aurora',
        Combo(id: c.id, nombre: c.nombre, precio: 650, activo: false));
    c = (await rAdmin.combos('aurora')).firstWhere((x) => x.id == c.id);
    expect((c.precio, c.activo), (650, false));
    expect(c.categorias, isEmpty);
    await rRrpp.borrarCombo(c.id); // RLS: no borra nada
    expect((await rAdmin.combos('aurora')).any((x) => x.id == c.id), isTrue);
    await rAdmin.borrarCombo(c.id);
    expect((await rAdmin.combos('aurora')).any((x) => x.id == c.id), isFalse);
  }, skip: saltear);
}
