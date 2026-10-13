import 'package:flutter_test/flutter_test.dart';
import 'package:supabase/supabase.dart';
import 'package:venue_mobile/features/access_control/data/puerta_repository.dart';
import 'package:venue_mobile/features/access_control/data/resultado.dart';
import 'package:venue_mobile/features/guestlists/data/listas.dart';
import 'package:venue_mobile/features/tickets/data/entradas.dart';

import 'demo.dart';

void main() {
  etapa2();
  late SupabaseClient rrpp, portero;
  late String ev, uid;

  setUpAll(() async {
    if (saltear != null) return;
    rrpp = await sesionDe('rrpp.aurora');
    portero = await sesionDe('portero.aurora');
    ev = await eventoDe(rrpp, 'aurora');
    uid = rrpp.auth.currentUser!.id;
  });

  test('listas, cupo e invitados propios', () async {
    final repo = ListasRepository(rrpp);
    final ls = await repo.listas(ev);
    expect(ls.map((l) => l.nombre), contains('Invitados'));
    expect((await repo.misCupos(ev))[ls.first.id], 50);
    final mios = await repo.misInvitados(ev, uid);
    expect(mios.map((i) => i.nombre), containsAll(['Ana Paz', 'Jorge Vaca']));
  }, skip: saltear);

  test('anotar → QR → el portero lo valida → eliminar', () async {
    final repo = ListasRepository(rrpp);
    final lista = (await repo.listas(ev)).first;
    final r = await repo.anotar(lista.id, ['Prueba App Lista']);
    expect(r.insertados, 1);
    final inv = (await repo.misInvitados(ev, uid))
        .firstWhere((i) => i.nombre == 'Prueba App Lista');
    final codigo = await repo.generarQr(inv.id);
    expect(codigo.length, 10);
    final v = await PuertaRepository(portero)
        .validar(eventoId: ev, crudo: payloadLista(ev, codigo));
    expect(v.veredicto, Veredicto.pasa);
    expect(v.tipo, 'Invitados');
    await PuertaRepository(portero).desmarcarLista(inv.id);
    await repo.eliminar(inv.id);
    expect((await repo.misInvitados(ev, uid)).any((i) => i.id == inv.id), isFalse);
  }, skip: saltear);

  test('generar entrada → aparece en las mías → el portero la valida', () async {
    final repo = EntradasRepository(rrpp);
    final e = await repo.generar(ev, 'Prueba App Entrada');
    expect(e.codigo.length, 10);
    expect(e.valida, isTrue);
    expect((await repo.mias(ev, uid)).any((x) => x.id == e.id), isTrue);
    final v = await PuertaRepository(portero)
        .validar(eventoId: ev, crudo: payloadEntrada(ev, e.codigo));
    expect(v.veredicto, Veredicto.pasa);
    expect(v.nombre, 'Prueba App Entrada');
    await PuertaRepository(portero).desmarcarEntrada(ev, e.codigo);
    await repo.anular(e.id);
    final anulada = await PuertaRepository(portero)
        .validar(eventoId: ev, crudo: e.codigo);
    expect(anulada.veredicto, Veredicto.noValido);
    expect(anulada.tipo, 'Entrada anulada');
  }, skip: saltear);

  test('el portero no genera entradas ni anota en listas', () async {
    await expectLater(EntradasRepository(portero).generar(ev, 'Intruso'),
        throwsA(isA<PostgrestException>()));
    final lista = (await ListasRepository(rrpp).listas(ev)).first;
    await expectLater(ListasRepository(portero).anotar(lista.id, ['Intruso']),
        throwsA(isA<PostgrestException>()));
  }, skip: saltear);
}

/// Etapa 2 completa: lo que ven y hacen jefe y admin, y las fases.
void etapa2() {
  test('la lista completa trae quién anotó a cada invitado', () async {
    final sb = await sesionDe('admin.aurora');
    final ev = await eventoDe(sb, 'aurora');
    final todos = await ListasRepository(sb).todos(ev);
    expect(todos.firstWhere((i) => i.nombre == 'Ana Paz').rrppNombre,
        'Mateo Relaciones');
  }, skip: saltear);

  test('el jefe anota a nombre de un relacionador de su team; el rrpp no puede', () async {
    final jefe = await sesionDe('jefe.aurora');
    final rrpp = await sesionDe('rrpp.aurora');
    final rrpp2 = await sesionDe('rrpp2.aurora');
    final ev = await eventoDe(jefe, 'aurora');
    final lista = (await ListasRepository(jefe).listas(ev)).first;
    final idRrpp = rrpp.auth.currentUser!.id;

    await ListasRepository(jefe).anotar(lista.id, ['Prueba A Nombre De'], aNombreDe: idRrpp);
    final inv = (await ListasRepository(rrpp).misInvitados(ev, idRrpp))
        .firstWhere((i) => i.nombre == 'Prueba A Nombre De');
    expect(inv.rrppId, idRrpp);
    await ListasRepository(rrpp).eliminar(inv.id);

    await expectLater(
        ListasRepository(rrpp2).anotar(lista.id, ['Intruso'], aNombreDe: idRrpp),
        throwsA(isA<PostgrestException>()));
  }, skip: saltear);

  test('el admin ve todas las entradas con su vendedor', () async {
    final sb = await sesionDe('admin.aurora');
    final ev = await eventoDe(sb, 'aurora');
    final todas = await EntradasRepository(sb).todas(ev);
    expect(todas.length, greaterThanOrEqualTo(3));
    expect(todas.firstWhere((e) => e.cliente == 'Carlos Roca').rrppNombre,
        'Mateo Relaciones');
  }, skip: saltear);

  test('fases de preventa: precio y stock de la fase vigente', () async {
    final admin = await sesionDe('admin.aurora');
    final rrpp = await sesionDe('rrpp.aurora');
    final ev = await eventoDe(admin, 'aurora');
    final repo = EntradasRepository(rrpp);
    await admin.rpc('guardar_fase', params: {
      'p_evento': ev, 'p_id': null, 'p_nombre': 'Hot Tickets', 'p_precio': 80,
      'p_cupo': 1, 'p_desde': null, 'p_hasta': null, 'p_orden': 1, 'p_activo': true,
    });
    await admin.rpc('set_venta_por_fases', params: {'p_evento': ev, 'p_on': true});
    try {
      final f = (await repo.faseVigente(ev))!;
      expect((f.nombre, f.precio, f.quedan), ('Hot Tickets', 80, 1));
      final e = await repo.generar(ev, 'Prueba Fase App');
      expect((e.precio, e.faseId), (80, f.id));
      // se agotó el stock de la fase: ya no hay fase vigente ni se puede vender
      expect(await repo.faseVigente(ev), isNull);
      await expectLater(
          repo.generar(ev, 'Sin Stock'), throwsA(isA<PostgrestException>()));
      await EntradasRepository(admin).eliminar(e.id);
    } finally {
      await admin.rpc('set_venta_por_fases', params: {'p_evento': ev, 'p_on': false});
      for (final f in await EntradasRepository(admin).fases(ev)) {
        await admin.rpc('borrar_fase', params: {'p_fase': f.id});
      }
    }
  }, skip: saltear);

  test('ventana de venta del relacionador', () async {
    final rrpp = await sesionDe('rrpp.aurora');
    final ev = await eventoDe(rrpp, 'aurora');
    final v = await EntradasRepository(rrpp).ventana(ev, rrpp.auth.currentUser!.id);
    expect(v.desde, isNull);
  }, skip: saltear);
}
