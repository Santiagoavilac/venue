import 'package:flutter_test/flutter_test.dart';
import 'package:supabase/supabase.dart';
import 'package:venue_mobile/features/events/data/gestion.dart';
import 'package:venue_mobile/features/guestlists/data/listas.dart';
import 'package:venue_mobile/features/tickets/data/entradas.dart';

import 'demo.dart';

void main() {
  late SupabaseClient admin, adminN, rrpp, jefe;
  late GestionRepository r;
  String? ev;

  setUpAll(() async {
    if (saltear != null) return;
    admin = await sesionDe('admin.aurora');
    adminN = await sesionDe('admin.nebula');
    rrpp = await sesionDe('rrpp.aurora');
    jefe = await sesionDe('jefe.aurora');
    r = GestionRepository(admin);
    for (final e in (await r.eventos('aurora')).where((e) => '${e['nombre']}'.startsWith('ZZ'))) {
      await r.eliminar(e['id'] as String);
    }
  });

  tearDownAll(() async {
    if (saltear == null && ev != null) await r.eliminar(ev!);
  });

  test('crear evento: nace borrador, con dos listas, y el equipo no lo ve', () async {
    ev = await r.crear('aurora', nombre: 'ZZ Evento App', fecha: '2026-12-31', precio: 80, cut: 20);
    final e = (await r.eventos('aurora')).firstWhere((x) => x['id'] == ev);
    expect((e['publicado'], e['estado'], e['precio_manilla'], e['cut_rrpp']),
        (false, 'proximo', 80, 20));
    expect((await r.listas(ev!)).map((l) => l['nombre']), ['Invitados', 'Free Cover Girls']);
    expect(accionesDeEvento(e).publicar, isTrue);
    // borrador: un relacionador del boliche todavía no lo ve
    expect(await rrpp.from('eventos').select('id').eq('id', ev!), isEmpty);
    // y otro boliche no lo ve nunca
    expect(await adminN.from('eventos').select('id').eq('id', ev!), isEmpty);
  }, skip: saltear);

  test('publicar lo muestra al equipo', () async {
    final p = await r.publicar(ev!);
    expect(p['listas'], 2);
    expect(await rrpp.from('eventos').select('id').eq('id', ev!), isNotEmpty);
  }, skip: saltear);

  test('editar evento y reglas de mesas', () async {
    await r.editar(ev!, {
      'nombre': 'ZZ Evento Editado', 'hora_inicio': '22:00', 'hora_fin': '05:00',
      'permite_reserva': false, 'horas_reserva': 6, 'combo_obligatorio': false,
    });
    final e = (await r.eventos('aurora')).firstWhere((x) => x['id'] == ev);
    expect((e['nombre'], '${e['hora_inicio']}'.substring(0, 5), e['permite_reserva'], e['horas_reserva']),
        ('ZZ Evento Editado', '22:00', false, 6));
    // solo el admin del boliche edita
    await rrpp.from('eventos').update({'nombre': 'pirata'}).eq('id', ev!);
    await adminN.from('eventos').update({'nombre': 'pirata'}).eq('id', ev!);
    expect((await r.eventos('aurora')).firstWhere((x) => x['id'] == ev)['nombre'], 'ZZ Evento Editado');
  }, skip: saltear);

  test('listas: crear, ordenar, editar con cupos y cupo especial por persona', () async {
    await r.crearLista(ev!, {'nombre': 'Compra en puerta', 'cupo_por_rrpp': 1, 'precio': 50}, 2);
    var ls = await r.listas(ev!);
    expect(ls.map((l) => l['nombre']), ['Invitados', 'Free Cover Girls', 'Compra en puerta']);
    await r.intercambiarOrden(ls[2], ls[1]);
    ls = await r.listas(ev!);
    expect(ls[1]['nombre'], 'Compra en puerta');
    final puerta = ls[1]['id'] as String;
    await r.editarLista(puerta, {'cupo_por_rrpp': 2, 'ingreso_hasta': '01:30'});

    final idRrpp = rrpp.auth.currentUser!.id;
    expect((await ListasRepository(rrpp).misCupos(ev!))[puerta], 2);
    await r.fijarCupo(puerta, idRrpp, 7);
    expect((await ListasRepository(rrpp).misCupos(ev!))[puerta], 7);
    expect((await r.cuposDeLista(puerta)).single['cupo'], 7);
    expect((await r.personasConCupo('aurora')).any((p) => p['id'] == idRrpp), isTrue);
    // el relacionador no se sube el cupo solo
    await expectLater(GestionRepository(rrpp).fijarCupo(puerta, idRrpp, 99),
        throwsA(isA<PostgrestException>()));
    await r.quitarCupo(puerta, idRrpp);
    expect((await ListasRepository(rrpp).misCupos(ev!))[puerta], 2);

    // el cupo se respeta al anotar
    await ListasRepository(rrpp).anotar(puerta, ['Uno', 'Dos']);
    await expectLater(ListasRepository(rrpp).anotar(puerta, ['Tres']),
        throwsA(isA<PostgrestException>()));
  }, skip: saltear);

  test('fases: crear, cupo por team y venta con el precio de la fase', () async {
    await r.guardarFase(ev!, nombre: 'Hot Tickets', precio: 50, cupo: 10, orden: 1);
    await r.guardarFase(ev!, nombre: 'Fase 2', precio: 70, orden: 2);
    await r.ventaPorFases(ev!, true);
    var fs = await r.fases(ev!);
    expect(fs.map((f) => '${f['nombre']}:${f['vigente']}'), ['Hot Tickets:true', 'Fase 2:false']);
    final hot = fs.first['id'] as String;
    final equipos = await r.cuposPorTeam(hot);
    final norte = equipos.firstWhere((t) => t['team'] == 'Team Norte');
    await r.fijarCupoTeam(hot, norte['team_id'] as String, 1);

    final e = await EntradasRepository(rrpp).generar(ev!, 'Cliente Fase');
    expect(e.precio, 50);
    // el team agotó su cupo de la fase: ni el relacionador ni su jefe venden más
    await expectLater(EntradasRepository(rrpp).generar(ev!, 'Otro'),
        throwsA(isA<PostgrestException>()));
    await expectLater(EntradasRepository(jefe).generar(ev!, 'Otro'),
        throwsA(isA<PostgrestException>()));
    // una fase con ventas no se puede borrar
    await expectLater(r.borrarFase(hot), throwsA(isA<PostgrestException>()));
    await r.borrarFase(fs[1]['id'] as String);
    fs = await r.fases(ev!);
    expect(fs.length, 1);
    await r.ventaPorFases(ev!, false);
  }, skip: saltear);

  test('horario de venta y excepción para un team', () async {
    final ayer = DateTime.now().subtract(const Duration(days: 1));
    final manana = DateTime.now().add(const Duration(days: 1));
    // la venta cerró ayer: el relacionador no puede generar
    await r.ventanaDeVenta(ev!, null, ayer);
    await expectLater(EntradasRepository(rrpp).generar(ev!, 'Tarde'),
        throwsA(isA<PostgrestException>()));
    // excepción para su team: vuelve a poder
    final team = (await rrpp.from('profiles').select('team_id')
        .eq('id', rrpp.auth.currentUser!.id).single())['team_id'] as String;
    await r.fijarExcepcion(ev!, manana, teamId: team);
    final x = (await r.excepciones(ev!)).single;
    expect((x['tipo'], x['nombre']), ('team', 'Team Norte'));
    final e = await EntradasRepository(rrpp).generar(ev!, 'Con Excepción');
    expect(e.valida, isTrue);
    await r.quitarExcepcion(x['id'] as String);
    await expectLater(EntradasRepository(rrpp).generar(ev!, 'Tarde otra vez'),
        throwsA(isA<PostgrestException>()));
    await r.ventanaDeVenta(ev!, null, null);
  }, skip: saltear);

  test('avisos: se envían, le llegan al equipo una vez y queda quién leyó', () async {
    for (final a in (await r.avisos('aurora')).where((a) => a['titulo'] == 'ZZ Aviso')) {
      await r.borrarAviso(a['id'] as String);
    }
    await r.crearAviso('aurora', titulo: 'ZZ Aviso', mensaje: 'Cierre de venta a las 22');
    final a = (await r.avisos('aurora')).firstWhere((a) => a['titulo'] == 'ZZ Aviso');
    expect(a['leidos'], 0);
    final pend = await rrpp.rpc('avisos_pendientes', params: {'p_club': 'aurora'}) as List;
    expect(pend.any((p) => p['id'] == a['id']), isTrue);
    await rrpp.rpc('marcar_aviso_visto', params: {'p_aviso': a['id']});
    expect((await rrpp.rpc('avisos_pendientes', params: {'p_club': 'aurora'}) as List)
        .any((p) => p['id'] == a['id']), isFalse);
    expect((await r.lectores(a['id'] as String)).length, 1);
    expect((await r.avisos('aurora')).firstWhere((x) => x['id'] == a['id'])['leidos'], 1);
    await expectLater(GestionRepository(rrpp).crearAviso('aurora', titulo: 'x', mensaje: 'x'),
        throwsA(isA<PostgrestException>()));
    await r.borrarAviso(a['id'] as String);
  }, skip: saltear);

  test('cerrar y eliminar: solo el admin del boliche', () async {
    await expectLater(GestionRepository(rrpp).eliminar(ev!), throwsA(isA<PostgrestException>()));
    await expectLater(GestionRepository(adminN).eliminar(ev!), throwsA(isA<PostgrestException>()));
    await r.cerrar(ev!);
    expect((await r.eventos('aurora')).firstWhere((x) => x['id'] == ev)['estado'], 'cerrado');
    await r.eliminar(ev!);
    expect((await r.eventos('aurora')).any((x) => x['id'] == ev), isFalse);
    ev = null;
  }, skip: saltear);
}
