import 'package:flutter_test/flutter_test.dart';
import 'package:supabase/supabase.dart';
import 'package:venue_mobile/features/access_control/data/puerta_repository.dart';
import 'package:venue_mobile/features/access_control/data/qr.dart';
import 'package:venue_mobile/features/access_control/data/resultado.dart';

import 'demo.dart';

void main() {
  late SupabaseClient portero, rrpp;
  late PuertaRepository repo;
  late String ev;

  setUpAll(() async {
    if (saltear != null) return;
    portero = await sesionDe('portero.aurora');
    rrpp = await sesionDe('rrpp.aurora');
    repo = PuertaRepository(portero);
    ev = await eventoDe(portero, 'aurora');
  });

  test('buscar por nombre trae invitados y entradas', () async {
    final r = await repo.buscar(ev, 'ana');
    expect(r.any((p) => p.nombre == 'Ana Paz' && !p.esEntrada), isTrue);
    final e = await repo.buscar(ev, 'carlos');
    expect(e.any((p) => p.esEntrada && p.codigo != null), isTrue);
    expect(await repo.buscar(ev, 'zzzzzz'), isEmpty);
  }, skip: saltear);

  test('ingreso de lista: entra una vez, se puede desmarcar', () async {
    final ana = (await repo.buscar(ev, 'ana paz')).first;
    if (ana.ingreso) await repo.desmarcarLista(ana.id!);
    expect(await repo.ingresoDeLista(ana.id!), isTrue);
    expect(await repo.ingresoDeLista(ana.id!), isFalse);
    expect((await repo.buscar(ev, 'ana paz')).first.ingreso, isTrue);
    await repo.desmarcarLista(ana.id!);
    expect((await repo.buscar(ev, 'ana paz')).first.ingreso, isFalse);
  }, skip: saltear);

  test('marca de filtro: se pone y se quita', () async {
    final j = (await repo.buscar(ev, 'jorge')).first;
    final a = await repo.alternarFiltro(ev, j);
    final b = await repo.alternarFiltro(ev, j);
    expect(a.marcado, isNot(b.marcado));
    if (b.marcado) await repo.alternarFiltro(ev, j); // dejarlo sin marca
    expect((await repo.buscar(ev, 'jorge')).first.filtrada, isFalse);
  }, skip: saltear);

  test('entrada por código: PASA, después YA INGRESÓ', () async {
    final e = (await repo.buscar(ev, 'luis')).firstWhere((p) => p.esEntrada);
    if (e.ingreso) await repo.desmarcarEntrada(ev, e.codigo!);
    final a = await repo.validar(eventoId: ev, crudo: 'EVT:$ev:${e.codigo}');
    expect(a.veredicto, Veredicto.pasa);
    expect(a.nombre, 'Luis Méndez');
    final b = await repo.validar(eventoId: ev, crudo: e.codigo!);
    expect(b.veredicto, Veredicto.yaIngreso);
    await repo.desmarcarEntrada(ev, e.codigo!);
  }, skip: saltear);

  test('modo filtro sobre un QR no lo consume', () async {
    final e = (await repo.buscar(ev, 'valeria')).firstWhere((p) => p.esEntrada);
    final qr = QrLeido(codigo: e.codigo!, esLista: false);
    final f = await repo.marcarFiltroQr(eventoId: ev, qr: qr);
    expect(f['resultado'], 'ok');
    expect((await repo.buscar(ev, 'valeria')).first.ingreso, isFalse);
    if (f['marcado'] == true) await repo.marcarFiltroQr(eventoId: ev, qr: qr);
  }, skip: saltear);

  test('otro evento y código inexistente', () async {
    expect((await repo.validar(eventoId: ev, crudo: 'EVT:otro:ABC')).veredicto,
        Veredicto.eventoIncorrecto);
    expect((await repo.validar(eventoId: ev, crudo: 'NOEXISTE1')).veredicto,
        Veredicto.noValido);
  }, skip: saltear);

  test('aforo y relacionadores', () async {
    final a = await repo.aforo(ev);
    expect(a.total, greaterThanOrEqualTo(3));
    final r = await repo.relacionadores('aurora', ev);
    expect(r.any((g) => g.usuario == 'jefe.aurora' && g.esJefe), isTrue);
  }, skip: saltear);

  test('un rrpp no valida ingresos: SIN PERMISO', () async {
    final r = await PuertaRepository(rrpp).validar(eventoId: ev, crudo: 'ABCDEF');
    expect(r.veredicto, Veredicto.sinPermiso);
  }, skip: saltear);
}
