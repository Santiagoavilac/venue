import 'package:flutter_test/flutter_test.dart';
import 'package:supabase/supabase.dart';
import 'package:venue_mobile/features/access_control/data/puerta_repository.dart';
import 'package:venue_mobile/features/analytics/data/contabilidad.dart';
import 'package:venue_mobile/features/analytics/data/reporte.dart';

import 'demo.dart';

void main() {
  late SupabaseClient superadmin, admin, jefe, rrpp, portero, adminN;
  late String ev;
  final ingresados = <String>[];
  String? invitado;

  setUpAll(() async {
    if (saltear != null) return;
    superadmin = await sesionDe('superadmin');
    admin = await sesionDe('admin.aurora');
    jefe = await sesionDe('jefe.aurora');
    rrpp = await sesionDe('rrpp.aurora');
    portero = await sesionDe('portero.aurora');
    adminN = await sesionDe('admin.nebula');
    ev = await eventoDe(admin, 'aurora');
    // dos entradas y un invitado de Mateo ingresan de verdad, por el escáner
    final puerta = PuertaRepository(portero);
    for (final n in ['carlos', 'valeria']) {
      final e = (await puerta.buscar(ev, n)).firstWhere((p) => p.esEntrada);
      if (!e.ingreso) await puerta.validar(eventoId: ev, crudo: e.codigo!);
      ingresados.add(e.codigo!);
    }
    final ana = (await puerta.buscar(ev, 'ana paz')).first;
    if (!ana.ingreso) await puerta.ingresoDeLista(ana.id!);
    invitado = ana.id;
  });

  tearDownAll(() async {
    if (saltear != null) return;
    final puerta = PuertaRepository(portero);
    for (final c in ingresados) {
      await puerta.desmarcarEntrada(ev, c);
    }
    if (invitado != null) await puerta.desmarcarLista(invitado!);
  });

  test('cierre con datos reales: lo que ingresó y lo que se le paga a Mateo', () async {
    final c = await ReporteRepository(admin).cierre(ev);
    expect(c.entUsadas, 2);
    expect(c.entBruto, 200);
    expect(c.listaIngresaron, 1);
    final mateo = c.personas.firstWhere((p) => p.nombre == 'Mateo Relaciones');
    expect((mateo.usadas, mateo.ingresaron), (2, 1));
    expect(mateo.aPagar, greaterThanOrEqualTo(0));
  }, skip: saltear);

  test('liquidación: solo el admin del boliche', () async {
    final l = await ReporteRepository(admin).liquidacion(ev);
    expect(l['manillas_usadas'], 2);
    expect(l['precio_manilla'], 100);
    for (final sb in [rrpp, jefe, adminN]) {
      await expectLater(ReporteRepository(sb).liquidacion(ev), throwsA(isA<PostgrestException>()));
    }
  }, skip: saltear);

  test('contabilidad: total para la cuenta marcada, su team para el jefe, nadie más', () async {
    Future<DatosContables> pedir(SupabaseClient sb) async => DatosContables.desde(
        Map<String, dynamic>.from(
            await sb.rpc('contabilidad_evento', params: {'p_evento': ev}) as Map),
        0);
    final total = await pedir(superadmin);
    expect(total.alcance, 'total');
    expect(total.totalPrepagadas, 2);
    expect(total.totalLista, 1);
    expect(total.rendicion, 2 * 100 * .5);
    final norte = total.teams.firstWhere((t) => t.nombre == 'Team Norte');
    expect(norte.jefe, 'Julián Jefe');
    expect(norte.rrpps.single.nombre, 'Mateo Relaciones');

    final delJefe = await pedir(jefe);
    expect((delJefe.alcance, delJefe.teamNombre), ('team', 'Team Norte'));
    expect(delJefe.teams.map((t) => t.nombre), ['Team Norte']);

    // el libro sale con esos mismos números
    final libro = construirLibro('Noche Aurora', DateTime(2026, 10, 13), 'Aurora Club', total);
    // con un solo team: TOTAL en la fila 14, rendición en la 20
    expect(libro.hojas.first.formulaDe('E20'), r'MAX(C14-E17,0)*\$C\$9*\$E\$9'.replaceAll(r'\', ''));
    expect(libro.hojas.first.valorDe('E20'), 100);
    expect(libro.bytes().length, greaterThan(2000));

    // un admin sin la marca y un relacionador no exportan
    for (final sb in [admin, rrpp, adminN]) {
      await expectLater(pedir(sb), throwsA(isA<PostgrestException>()));
    }
  }, skip: saltear);

  test('bonos: los carga el admin y suman a lo que se paga; el rrpp no puede', () async {
    final r = ReporteRepository(admin);
    final idMateo = rrpp.auth.currentUser!.id;
    for (final b in (await r.bonos(ev)).where((b) => b['motivo'] == 'Prueba app')) {
      await r.borrarBono(b['id'] as String);
    }
    final antes = (await r.cierre(ev)).personas.firstWhere((p) => p.id == idMateo).aPagar;
    await r.crearBono(ev, idMateo, 70, 'Prueba app');
    final c = await r.cierre(ev);
    expect(c.personas.firstWhere((p) => p.id == idMateo).aPagar, antes + 70);
    expect(c.bonos, greaterThanOrEqualTo(70));
    await expectLater(ReporteRepository(rrpp).crearBono(ev, idMateo, 999, 'pirata'),
        throwsA(isA<PostgrestException>()));
    final b = (await r.bonos(ev)).firstWhere((b) => b['motivo'] == 'Prueba app');
    await r.borrarBono(b['id'] as String);
    expect((await r.cierre(ev)).personas.firstWhere((p) => p.id == idMateo).aPagar, antes);
  }, skip: saltear);

  test('comisión acordada con una persona: la fija el admin y cambia lo que cobra', () async {
    final r = ReporteRepository(admin);
    final idMateo = rrpp.auth.currentUser!.id;
    await r.fijarComision(idMateo, 10);
    try {
      final con10 = (await r.cierre(ev)).personas.firstWhere((p) => p.id == idMateo).comRrpp;
      await r.fijarComision(idMateo, 30);
      expect((await r.comisionesPropias([idMateo]))[idMateo], 30);
      final con30 = (await r.cierre(ev)).personas.firstWhere((p) => p.id == idMateo).comRrpp;
      // la comisión la calcula el servidor: es proporcional a los Bs acordados
      expect(con10, greaterThan(0));
      expect(con30, con10 * 3);
      // nadie se sube su propia comisión
      await expectLater(ReporteRepository(rrpp).fijarComision(idMateo, 99),
          throwsA(isA<PostgrestException>()));
    } finally {
      await r.fijarComision(idMateo, null);
    }
  }, skip: saltear);

  test('histórico, ranking, fases, filtro y teléfonos responden al admin', () async {
    final r = ReporteRepository(admin);
    expect((await r.historico('aurora')).first['nombre'], 'Noche Aurora');
    expect(await r.ranking('aurora', DateTime(2000)), isNotEmpty);
    expect((await r.fases(ev))['usa_fases'], false);
    expect(await r.filtro(ev), isA<List>());
    expect((await r.telefonos('aurora')).length, greaterThan(5));
    await expectLater(ReporteRepository(rrpp).historico('aurora'), throwsA(isA<PostgrestException>()));
    await expectLater(ReporteRepository(adminN).telefonos('aurora'), throwsA(isA<PostgrestException>()));
  }, skip: saltear);

  test('nombre por nombre de un relacionador y sus eventos pasados', () async {
    final r = ReporteRepository(rrpp);
    final d = await r.detalle(ev, rrpp.auth.currentUser!.id);
    expect(d.registros.map((x) => x['nombre']), contains('Ana Paz'));
    expect(d.entradas.length, greaterThanOrEqualTo(3));
    expect((await r.eventosPasados('aurora')).map((e) => e.nombre), contains('Noche Aurora'));
  }, skip: saltear);
}
