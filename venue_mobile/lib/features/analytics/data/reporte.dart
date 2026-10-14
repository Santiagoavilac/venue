import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/networking/supabase.dart';
import '../../clubs/data/clubs.dart';
import '../../events/data/eventos.dart';
import '../../teams/data/equipo.dart';

/// Parte del boliche sobre las manillas ingresadas (regla de la web).
const pctBolicheManillas = 0.5;

/// Lo que hizo una persona en el evento (v_stats_rrpp + v_stats_mesas + bonos).
class StatsPersona {
  const StatsPersona({
    required this.id, required this.nombre, this.teamId,
    this.anotados = 0, this.ingresaron = 0, this.vendidas = 0, this.usadas = 0,
    this.brutoEntradas = 0, this.comRrpp = 0, this.comJefe = 0,
    this.mesas = 0, this.brutoMesas = 0, this.comRrppMesas = 0, this.comJefeMesas = 0,
    this.bono = 0,
  });
  final String id;
  final String nombre;
  final String? teamId;
  final int anotados, ingresaron, vendidas, usadas, mesas;
  final num brutoEntradas, comRrpp, comJefe, brutoMesas, comRrppMesas, comJefeMesas, bono;

  bool get conActividad => anotados > 0 || vendidas > 0 || mesas > 0 || bono > 0;

  /// Todo lo que hay que pagarle: comisiones de entradas y mesas, más bonos.
  num get aPagar => comRrpp + comJefe + comRrppMesas + comJefeMesas + bono;
}

/// Cierre del evento, con las mismas cuentas que `screenStats` de la web.
class Cierre {
  const Cierre({
    required this.personas,
    required this.listaAnotados, required this.listaIngresaron,
    required this.entVendidas, required this.entUsadas, required this.entBruto,
    required this.mesasN, required this.mesasBruto, required this.mesasComR, required this.mesasComJ,
    required this.porLista,
  });

  /// Solo quienes tuvieron actividad.
  final List<StatsPersona> personas;
  final int listaAnotados, listaIngresaron, entVendidas, entUsadas, mesasN;

  /// Bruto de entradas: solo las que INGRESARON (incluye las de admins).
  final num entBruto, mesasBruto, mesasComR, mesasComJ;
  final List<({String nombre, int anotados, int ingresaron})> porLista;

  num _s(num Function(StatsPersona) f) => personas.fold<num>(0, (a, p) => a + f(p));
  num get comRrpp => _s((p) => p.comRrpp);
  num get comJefe => _s((p) => p.comJefe);
  num get comRrppMesas => _s((p) => p.comRrppMesas);
  num get comJefeMesas => _s((p) => p.comJefeMesas);
  num get bonos => _s((p) => p.bono);
  int get mesasDePersonas => personas.fold(0, (a, p) => a + p.mesas);
  num get brutoMesasDePersonas => _s((p) => p.brutoMesas);

  /// Comisiones (de entradas y de combos) más bonos.
  num get comisionesTotal => comRrpp + comJefe + mesasComR + mesasComJ + bonos;

  /// "Neto por comisiones": bruto menos lo que se lleva cada relacionador.
  /// En mesas se resta la comisión fija del combo, venda quien venda.
  num get neto =>
      (entBruto - comRrpp - comJefe) + mesasBruto - mesasComR - mesasComJ - bonos;

  factory Cierre.calcular({
    required List<Map<String, dynamic>> stats,
    required List<Map<String, dynamic>> statsMesas,
    required List<Map<String, dynamic>> bonos,
    required List<Map<String, dynamic>> mesas,
    required List<Map<String, dynamic>> entradas,
    required List<Map<String, dynamic>> registros,
    required Map<String, String> listas,
  }) {
    num n(dynamic v) => v as num? ?? 0;
    final mesasDe = {for (final m in statsMesas) m['rrpp_id'] as String: m};
    final bonoDe = <String, num>{};
    for (final b in bonos) {
      bonoDe[b['user_id'] as String] = (bonoDe[b['user_id']] ?? 0) + n(b['monto']);
    }
    final personas = [
      for (final r in stats)
        StatsPersona(
          id: r['rrpp_id'] as String,
          nombre: r['rrpp'] as String? ?? '',
          teamId: r['team_id'] as String?,
          anotados: n(r['anotados']).toInt(),
          ingresaron: n(r['ingresaron']).toInt(),
          vendidas: n(r['entradas_vendidas']).toInt(),
          usadas: n(r['entradas_usadas']).toInt(),
          brutoEntradas: n(r['bruto_entradas']),
          comRrpp: n(r['comision_rrpp']),
          comJefe: n(r['comision_jefe']),
          mesas: n(mesasDe[r['rrpp_id']]?['mesas_vendidas']).toInt(),
          brutoMesas: n(mesasDe[r['rrpp_id']]?['bruto_mesas']),
          comRrppMesas: n(mesasDe[r['rrpp_id']]?['comision_rrpp_mesas']),
          comJefeMesas: n(mesasDe[r['rrpp_id']]?['comision_jefe_mesas']),
          bono: bonoDe[r['rrpp_id']] ?? 0,
        ),
    ].where((p) => p.conActividad).toList();

    var vend = 0, usad = 0;
    num bruto = 0;
    for (final e in entradas) {
      if (e['estado'] != 'anulada') vend++;
      if (e['estado'] == 'usada') {
        usad++;
        bruto += n(e['precio']);
      }
    }
    var mN = 0;
    num mBs = 0, mR = 0, mJ = 0;
    for (final m in mesas) {
      final q = n(m['combo_qty']) == 0 ? 1 : n(m['combo_qty']);
      final c = m['c'] as Map?;
      mN++;
      mBs += n(m['precio']);
      mR += n(c?['comision_rrpp']) * q;
      mJ += n(c?['comision_jefe']) * q;
    }
    final porL = <String, ({int a, int i})>{};
    var ing = 0;
    for (final r in registros) {
      final entro = r['ingreso_at'] != null;
      if (entro) ing++;
      final k = r['lista_tipo_id'] as String;
      final o = porL[k] ?? (a: 0, i: 0);
      porL[k] = (a: o.a + 1, i: o.i + (entro ? 1 : 0));
    }
    return Cierre(
      personas: personas,
      listaAnotados: registros.length, listaIngresaron: ing,
      entVendidas: vend, entUsadas: usad, entBruto: bruto,
      mesasN: mN, mesasBruto: mBs, mesasComR: mR, mesasComJ: mJ,
      porLista: [
        for (final l in listas.entries)
          if (porL.containsKey(l.key))
            (nombre: l.value, anotados: porL[l.key]!.a, ingresaron: porL[l.key]!.i),
      ],
    );
  }
}

/// "Lo que se debería pagar al boliche": 50 % de las prepagadas ingresadas,
/// más las mesas netas de comisión, menos el 50 % de la Compra en Puerta.
({num prepagadas, num mesas, num puerta, num total}) liquidacion({
  required num brutoPrepagadasIngresadas,
  required num totalMesas,
  required int puertaIngresaron,
  required num puertaPrecio,
}) {
  final pre = brutoPrepagadasIngresadas * pctBolicheManillas;
  final pue = puertaIngresaron * puertaPrecio * pctBolicheManillas;
  return (prepagadas: pre, mesas: totalMesas, puerta: pue, total: pre + totalMesas - pue);
}

/// Texto del cierre para pegar en WhatsApp.
String textoCierre(String evento, String boliche, String fecha, Cierre c) {
  final orden = [...c.personas]
    ..sort((a, b) => (b.usadas + b.mesas).compareTo(a.usadas + a.mesas));
  return '🍾 CIERRE ${evento.toUpperCase()} — $boliche · $fecha\n\n'
      '💰 Para el boliche: ${c.neto} Bs\n'
      '🎟️ Entradas: ${c.entUsadas}/${c.entVendidas} ingresaron · ${c.entBruto} Bs\n'
      '📋 Listas: ${c.listaIngresaron}/${c.listaAnotados} ingresaron\n'
      '🍾 Mesas: ${c.mesasN} · ${c.mesasBruto} Bs\n'
      '🤝 Comisiones + bonos: ${c.comisionesTotal} Bs\n\n'
      '${orden.map((r) => '• ${r.nombre}: ${r.ingresaron}/${r.anotados} lista · ${r.usadas} QR · ${r.mesas} mesas · a pagar ${r.aPagar} Bs').join('\n')}';
}

final reporteRepositoryProvider =
    Provider<ReporteRepository>((ref) => ReporteRepository(ref.watch(supabaseProvider)));

class ReporteRepository {
  ReporteRepository(this._sb);
  final SupabaseClient _sb;

  Future<Cierre> cierre(String eventoId) async {
    final r = await Future.wait<List<Map<String, dynamic>>>([
      _sb.from('v_stats_rrpp').select().eq('evento_id', eventoId),
      _sb.from('v_stats_mesas').select().eq('evento_id', eventoId),
      _sb.from('bonos').select('user_id, monto').eq('evento_id', eventoId),
      _sb.from('mesas').select('precio, combo_qty, c:combos(comision_rrpp,comision_jefe)')
          .eq('evento_id', eventoId).neq('estado', 'disponible'),
      traerTodo((d, h) => _sb.from('entradas').select('precio, estado')
          .eq('evento_id', eventoId).isFilter('mesa_id', null).order('id').range(d, h)),
      traerTodo((d, h) => _sb.from('registros').select('ingreso_at, lista_tipo_id')
          .eq('evento_id', eventoId).order('id').range(d, h)),
      _sb.from('lista_tipos').select('id, nombre').eq('evento_id', eventoId).order('orden'),
    ]);
    return Cierre.calcular(
      stats: r[0], statsMesas: r[1], bonos: r[2], mesas: r[3], entradas: r[4],
      registros: r[5],
      listas: {for (final l in r[6]) l['id'] as String: l['nombre'] as String},
    );
  }

  /// Liquidación del servidor (admin).
  Future<Map<String, dynamic>> liquidacion(String eventoId) async =>
      Map<String, dynamic>.from(
          await _sb.rpc('liquidacion_evento', params: {'p_evento': eventoId}) as Map);

  /// Lista de "Compra en puerta" (se reconoce por el nombre): cuántos
  /// ingresaron y a qué precio.
  Future<({String? nombre, int ingresaron, num precio})> puerta(String eventoId) async {
    final ls = await _sb.from('lista_tipos').select('id, nombre, precio').eq('evento_id', eventoId);
    final lp = ls.where((l) => RegExp('puerta', caseSensitive: false)
        .hasMatch(l['nombre'] as String? ?? '')).firstOrNull;
    if (lp == null) return (nombre: null, ingresaron: 0, precio: 0);
    final c = await _sb.from('registros').select('id')
        .eq('evento_id', eventoId).eq('lista_tipo_id', lp['id'] as String)
        .not('ingreso_at', 'is', null).count(CountOption.exact);
    return (nombre: lp['nombre'] as String?, ingresaron: c.count, precio: lp['precio'] as num? ?? 0);
  }

  Future<void> manillasExternas(String eventoId, int cantidad) => _sb.rpc(
      'set_manillas_externas', params: {'p_evento': eventoId, 'p_cant': cantidad});

  Future<Map<String, dynamic>> fases(String eventoId) async => Map<String, dynamic>.from(
      await _sb.rpc('reporte_fases', params: {'p_evento': eventoId}) as Map);

  Future<List<Map<String, dynamic>>> historico(String clubId) async =>
      ((await _sb.rpc('historico_eventos', params: {'p_club': clubId})) as List)
          .map((x) => Map<String, dynamic>.from(x as Map)).toList();

  Future<List<Map<String, dynamic>>> ranking(String clubId, DateTime desde) async =>
      ((await _sb.rpc('ranking_rrpp', params: {
        'p_club': clubId, 'p_desde': desde.toIso8601String().substring(0, 10),
      })) as List).map((x) => Map<String, dynamic>.from(x as Map)).toList();

  Future<List<Map<String, dynamic>>> filtro(String eventoId) async =>
      ((await _sb.rpc('reporte_filtro', params: {'p_evento': eventoId})) as List)
          .map((x) => Map<String, dynamic>.from(x as Map)).toList();

  // ── bonos (admin) ──
  Future<List<Map<String, dynamic>>> bonos(String eventoId) => _sb.from('bonos')
      .select('*, p:profiles!bonos_user_id_fkey(nombre)')
      .eq('evento_id', eventoId).order('created_at', ascending: false);

  Future<void> crearBono(String eventoId, String usuarioId, num monto, String? motivo) =>
      _sb.from('bonos').insert({
        'evento_id': eventoId, 'user_id': usuarioId, 'monto': monto, 'motivo': motivo,
      });

  Future<void> borrarBono(String id) => _sb.from('bonos').delete().eq('id', id);

  /// Bs por manilla acordados con una persona (null = el del evento).
  Future<void> fijarComision(String usuarioId, num? cut) =>
      _sb.from('profiles').update({'cut_rel': cut}).eq('id', usuarioId);

  Future<Map<String, num?>> comisionesPropias(Iterable<String> ids) async {
    if (ids.isEmpty) return const {};
    final r = await _sb.from('profiles').select('id, cut_rel').inFilter('id', ids.toList());
    return {for (final x in r) x['id'] as String: x['cut_rel'] as num?};
  }

  // ── teléfonos ──
  Future<List<Map<String, dynamic>>> telefonos(String clubId) async =>
      ((await _sb.rpc('telefonos_equipo', params: {'p_club': clubId})) as List)
          .map((x) => Map<String, dynamic>.from(x as Map)).toList();

  Future<void> guardarTelefonoDe(String usuarioId, String telefono) => _sb.rpc(
      'guardar_telefono_de', params: {'p_tel': telefono, 'p_user': usuarioId});

  /// Eventos del boliche, también los cerrados (para "Eventos pasados").
  Future<List<Evento>> eventosPasados(String clubId) async {
    final r = await _sb.from('eventos')
        .select('id, nombre, fecha, hora_inicio, hora_fin, estado, precio_manilla')
        .eq('club_id', clubId).order('fecha', ascending: false).limit(40);
    return r.map(Evento.desde).toList();
  }

  /// Nombre por nombre de una persona en un evento: listas y entradas.
  Future<({List<Map<String, dynamic>> registros, List<Map<String, dynamic>> entradas})>
      detalle(String eventoId, String usuarioId) async {
    final r = await Future.wait<List<Map<String, dynamic>>>([
      _sb.from('registros').select('nombre, ingreso_at, lista_tipo_id, l:lista_tipos(nombre)')
          .eq('evento_id', eventoId).eq('rrpp_id', usuarioId).order('nombre').limit(1000),
      _sb.from('entradas').select('cliente, code, estado, used_at, mesa_id')
          .eq('evento_id', eventoId).eq('rrpp_id', usuarioId).order('cliente').limit(1000),
    ]);
    return (registros: r[0], entradas: r[1]);
  }
}

final cierreProvider = FutureProvider.autoDispose<Cierre>((ref) async {
  final ev = ref.watch(eventoActivoProvider);
  if (ev == null) throw StateError('Sin evento');
  return ref.watch(reporteRepositoryProvider).cierre(ev.id);
});

final liquidacionProvider = FutureProvider.autoDispose<
    ({Map<String, dynamic> servidor, ({String? nombre, int ingresaron, num precio}) puerta})?>((ref) async {
  final ev = ref.watch(eventoActivoProvider);
  if (ev == null || ref.watch(rolProvider).value != Rol.admin) return null;
  final repo = ref.watch(reporteRepositoryProvider);
  final r = await Future.wait([repo.liquidacion(ev.id), repo.puerta(ev.id)]);
  return (
    servidor: r[0] as Map<String, dynamic>,
    puerta: r[1] as ({String? nombre, int ingresaron, num precio}),
  );
});
