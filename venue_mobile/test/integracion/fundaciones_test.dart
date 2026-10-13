import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:supabase/supabase.dart';
import 'package:venue_mobile/features/guestlists/data/listas.dart';

import 'demo.dart';

void main() {
  test('registro con invitación inventada: lo rechaza el servidor', () async {
    final sb = SupabaseClient(const String.fromEnvironment('SUPABASE_URL'),
        const String.fromEnvironment('SUPABASE_ANON_KEY'));
    try {
      await sb.functions.invoke('crear-usuario', body: {
        'action': 'registro', 'invite': 'noexiste', 'nombre': 'X',
        'usuario': 'intruso.app', 'clave': 'secreta1',
      });
      fail('debía rechazar');
    } on FunctionException catch (e) {
      expect(e.status, anyOf(400, 429));
      expect((e.details as Map)['error'], isA<String>());
    }
  }, skip: saltear);

  test('avisos pendientes y teléfono propio responden para un rrpp', () async {
    final sb = await sesionDe('rrpp2.aurora');
    expect(await sb.rpc('avisos_pendientes', params: {'p_club': 'aurora'}), isA<List>());
    await sb.rpc('guardar_telefono', params: {'p_tel': '70000099'});
    expect(await sb.rpc('mi_telefono'), '59170000099');
  }, skip: saltear);

  test('tiempo real: el portero recibe el cambio que hace el rrpp', () async {
    final portero = await sesionDe('portero.aurora');
    final rrpp = await sesionDe('rrpp.aurora');
    final ev = await eventoDe(rrpp, 'aurora');
    final llego = Completer<String>();
    final canal = portero.channel('rt-prueba').onPostgresChanges(
        event: PostgresChangeEvent.all, schema: 'public', table: 'registros',
        filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq, column: 'evento_id', value: ev),
        callback: (p) {
          if (!llego.isCompleted) llego.complete(p.table);
        });
    final suscripto = Completer<void>();
    canal.subscribe((estado, _) {
      if (estado == RealtimeSubscribeStatus.subscribed && !suscripto.isCompleted) {
        suscripto.complete();
      }
    });
    await suscripto.future.timeout(const Duration(seconds: 15));
    // El canal avisa "suscripto" un instante antes de que el servidor
    // empiece a reenviar cambios de la base.
    await Future<void>.delayed(const Duration(seconds: 4));

    final repo = ListasRepository(rrpp);
    final lista = (await repo.listas(ev)).first;
    await repo.anotar(lista.id, ['Prueba Tiempo Real']);
    expect(await llego.future.timeout(const Duration(seconds: 15)), 'registros');

    final inv = (await repo.misInvitados(ev, rrpp.auth.currentUser!.id))
        .firstWhere((i) => i.nombre == 'Prueba Tiempo Real');
    await repo.eliminar(inv.id);
    await portero.removeChannel(canal);
  }, skip: saltear, timeout: const Timeout(Duration(seconds: 60)));
}
