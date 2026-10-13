import 'package:flutter_test/flutter_test.dart';
import 'package:supabase/supabase.dart';
import 'package:venue_mobile/features/access_control/data/puerta_repository.dart';
import 'package:venue_mobile/features/access_control/data/resultado.dart';
import 'package:venue_mobile/features/guestlists/data/listas.dart';
import 'package:venue_mobile/features/tickets/data/entradas.dart';

import 'demo.dart';

void main() {
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
