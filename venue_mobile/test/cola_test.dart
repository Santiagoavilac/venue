import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:venue_mobile/core/sync/cola_offline.dart';
import 'package:venue_mobile/features/authentication/data/sesion.dart';

class Memoria implements AlmacenCola {
  String? dato;
  @override
  Future<String?> leer() async => dato;
  @override
  Future<void> guardar(String? json) async => dato = json;
}

Pendiente op(String id, {String usuario = 'u1'}) => Pendiente(
    id: id, rpc: 'checkin_registro', params: {'p_registro': id},
    etiqueta: 'Ingreso $id', usuarioId: usuario, at: DateTime(2026, 10, 13));

void main() {
  test('lo encolado sobrevive a reabrir la app (se relee del almacén)', () async {
    final m = Memoria();
    await ColaOffline(m).encolar(op('a'));
    await ColaOffline(m).encolar(op('b'));
    final l = await ColaOffline(m).leer();
    expect(l.map((p) => p.id), ['a', 'b']);
    expect(l.first.params, {'p_registro': 'a'});
  });

  test('drenar envía en orden y vacía la cola', () async {
    final c = ColaOffline(Memoria());
    await c.encolar(op('a'));
    await c.encolar(op('b'));
    final enviados = <String>[];
    final r = await c.drenar('u1', (p) async => enviados.add(p.id));
    expect(enviados, ['a', 'b']);
    expect((r.enviadas, r.quedan, r.rechazadas.length), (2, 0, 0));
    expect(await c.leer(), isEmpty);
  });

  test('sin señal: se detiene, conserva todo y no pierde el orden', () async {
    final c = ColaOffline(Memoria());
    for (final id in ['a', 'b', 'c']) {
      await c.encolar(op(id));
    }
    var intentos = 0;
    final r = await c.drenar('u1', (p) async {
      intentos++;
      if (p.id == 'b') throw const SocketException('sin red');
    });
    expect(intentos, 2); // no insiste con "c" si ya no hay red
    expect((r.enviadas, r.quedan), (1, 2));
    expect((await c.leer()).map((p) => p.id), ['b', 'c']);
  });

  test('rechazo del servidor: se descarta e informa, no se reintenta', () async {
    final c = ColaOffline(Memoria());
    await c.encolar(op('a'));
    await c.encolar(op('b'));
    final r = await c.drenar('u1', (p) async {
      if (p.id == 'a') throw const PostgrestException(message: 'No autorizado.', code: '42501');
    });
    expect(r.enviadas, 1);
    expect(r.rechazadas.single.op.id, 'a');
    expect(r.rechazadas.single.motivo, 'No autorizado.');
    expect(await c.leer(), isEmpty);
  });

  test('nunca se envía lo de otra cuenta con mi sesión', () async {
    final c = ColaOffline(Memoria());
    await c.encolar(op('mia'));
    await c.encolar(op('ajena', usuario: 'u2'));
    final enviados = <String>[];
    final r = await c.drenar('u1', (p) async => enviados.add(p.id));
    expect(enviados, ['mia']);
    expect(r.quedan, 0);
    expect((await c.leer()).single.id, 'ajena');
  });

  test('vaciar al cerrar sesión', () async {
    final m = Memoria();
    final c = ColaOffline(m);
    await c.encolar(op('a'));
    await c.vaciar();
    expect(m.dato, isNull);
  });

  test('un almacén corrupto no rompe la app', () async {
    final m = Memoria()..dato = '{no es json';
    expect(await ColaOffline(m).leer(), isEmpty);
  });

  test('ids únicos con forma de UUID v4', () {
    final ids = {for (var i = 0; i < 200; i++) nuevoId()};
    expect(ids.length, 200);
    expect(RegExp(r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$')
        .hasMatch(ids.first), isTrue);
  });

  test('código de invitación desde el link o suelto', () {
    expect(codigoDeInvitacion('https://venue.app/?invite=AB12cd34'), 'ab12cd34');
    expect(codigoDeInvitacion('venue://app/registro?x=1&invite=ff00'), 'ff00');
    expect(codigoDeInvitacion('  AB12 '), 'ab12');
  });
}
