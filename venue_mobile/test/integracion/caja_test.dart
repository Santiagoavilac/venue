import 'package:flutter_test/flutter_test.dart';
import 'package:supabase/supabase.dart';
import 'package:venue_mobile/features/access_control/data/persona_puerta.dart';
import 'package:venue_mobile/features/caja/caja.dart';

import 'demo.dart';

void main() {
  test('agrupar por team: orden alfabético y "Sin team" al final', () {
    PersonaCaja p(String n, String t) => PersonaCaja(
        id: n, motivo: 'todos',
        persona: Relacionador(nombre: n, usuario: n, team: t, esJefe: false));
    final g = agruparPorTeam([p('zoe', 'Team Sur'), p('Ana', 'Sin team'), p('beto', 'Team Norte'), p('Ana', 'Team Norte')]);
    expect(g.keys, ['Team Norte', 'Team Sur', 'Sin team']);
    expect(g['Team Norte']!.map((x) => x.persona.nombre), ['Ana', 'beto']);
  });

  late SupabaseClient caja, portero, rrpp, admin, superadmin;
  late String ev;

  setUpAll(() async {
    if (saltear != null) return;
    caja = await sesionDe('caja.aurora');
    portero = await sesionDe('portero.aurora');
    rrpp = await sesionDe('rrpp.aurora');
    admin = await sesionDe('admin.aurora');
    superadmin = await sesionDe('superadmin');
    ev = await eventoDe(caja, 'aurora');
    await CajaRepository(superadmin).activarFiltro(ev, false);
  });

  test('la caja ve la lista y marca a quién atendió; la puerta solo consulta', () async {
    final r = CajaRepository(caja);
    final gente = await r.roster('aurora', ev);
    expect(gente.map((p) => p.persona.usuario), containsAll(['jefe.aurora', 'rrpp.aurora']));
    final mateo = gente.firstWhere((p) => p.persona.usuario == 'rrpp.aurora');

    await r.marcar(ev, mateo.id, true);
    await r.marcar(ev, mateo.id, true); // marcar dos veces no duplica ni falla
    expect(await r.atendidos(ev), contains(mateo.id));
    // la puerta ve la marca pero no la cambia
    expect(await CajaRepository(portero).atendidos(ev), contains(mateo.id));
    await CajaRepository(portero).marcar(ev, mateo.id, false);
    expect(await r.atendidos(ev), contains(mateo.id));
    // un relacionador ni la ve ni la toca
    expect(await CajaRepository(rrpp).atendidos(ev), isEmpty);
    await expectLater(CajaRepository(rrpp).marcar(ev, mateo.id, true),
        throwsA(isA<PostgrestException>()));

    await r.marcar(ev, mateo.id, false);
    expect(await r.atendidos(ev), isNot(contains(mateo.id)));
  }, skip: saltear);

  test('la caja no ve plata ni la operación de puerta', () async {
    expect(await caja.from('entradas').select('id').limit(1), isEmpty);
    expect(await caja.from('pagos').select('id').limit(1), isEmpty);
    expect(await caja.from('mesas').select('id').limit(1), isEmpty);
  }, skip: saltear);

  test('filtro de la lista: solo la cuenta principal; deja a quienes cargaron prepagadas y a los agregados a mano', () async {
    final r = CajaRepository(superadmin);
    // el admin del boliche no lo cambia
    await expectLater(CajaRepository(admin).activarFiltro(ev, true),
        throwsA(isA<PostgrestException>()));
    expect(await r.filtroActivo(ev), isFalse);

    await r.activarFiltro(ev, true);
    var lista = await CajaRepository(caja).roster('aurora', ev);
    // Mateo cargó prepagadas; Renata y el jefe, no
    expect(lista.map((p) => p.persona.usuario), contains('rrpp.aurora'));
    expect(lista.map((p) => p.persona.usuario), isNot(contains('rrpp2.aurora')));

    final renata = (await r.todosLosRelacionadores('aurora'))
        .firstWhere((p) => p.persona.usuario == 'rrpp2.aurora');
    await r.agregarAMano(ev, renata.id, true);
    lista = await CajaRepository(caja).roster('aurora', ev);
    expect(lista.map((p) => p.persona.usuario), contains('rrpp2.aurora'));
    expect(await r.agregadosAMano(ev), {renata.id});

    await r.agregarAMano(ev, renata.id, false);
    await r.activarFiltro(ev, false);
    expect((await CajaRepository(caja).roster('aurora', ev)).map((p) => p.persona.usuario),
        contains('rrpp2.aurora'));
  }, skip: saltear);
}
