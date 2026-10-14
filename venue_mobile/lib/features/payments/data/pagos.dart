import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/networking/supabase.dart';
import '../../authentication/data/sesion.dart';
import '../../clubs/data/clubs.dart';
import '../../events/data/eventos.dart';

const etiquetaPago = {
  'pendiente': 'Pendiente', 'pagado': 'Pagado', 'verificado': 'Verificado',
};

/// Rendición de un relacionador o jefe.
///
/// Estados: pendiente → pagado → verificado. Solo el admin los avanza: que
/// haya una captura adjunta no verifica nada.
class Pago {
  const Pago({
    required this.id,
    required this.rrppId,
    required this.rrppNombre,
    required this.monto,
    required this.concepto,
    required this.estado,
    required this.creado,
    this.nroOperacion,
    this.comprobante,
  });
  final String id;
  final String rrppId;
  final String rrppNombre;
  final num monto;
  final String concepto;
  final String estado;
  final DateTime creado;
  final String? nroOperacion;
  final String? comprobante;

  bool get verificado => estado == 'verificado';

  /// Estado al que lo puede pasar el admin, o null si ya está verificado.
  String? get siguiente =>
      estado == 'pendiente' ? 'pagado' : estado == 'pagado' ? 'verificado' : null;

  factory Pago.desde(Map<String, dynamic> j) => Pago(
        id: j['id'] as String,
        rrppId: j['rrpp_id'] as String,
        rrppNombre: (j['p'] as Map?)?['nombre'] as String? ?? '?',
        monto: j['monto'] as num? ?? 0,
        concepto: j['concepto'] as String? ?? '',
        estado: j['estado'] as String? ?? 'pendiente',
        creado: DateTime.parse(j['created_at'] as String).toLocal(),
        nroOperacion: j['nro_operacion'] as String?,
        comprobante: j['comprobante_url'] as String?,
      );
}

/// Comisión por manilla del relacionador. Es un monto FIJO: el acuerdo
/// propio de la persona, si no el del evento, y solo si faltan ambos la
/// cuenta vieja por porcentajes (misma regla que `cutRrpp` en la web).
num comisionPorManilla({num? cutPersona, num? cutEvento, required num precio,
    required num pctBoliche, required num pctRrpp}) {
  if (cutPersona != null) return cutPersona;
  if (cutEvento != null) return cutEvento;
  return precio * (1 - pctBoliche / 100) * (pctRrpp / 100);
}

/// Cuánto generó, cuánto cobró y cuánto le queda por rendir.
({num genero, num recaudado, num aRendir, num netoPorManilla}) rendicion({
  required int vendidas, required num precio, required num comision, required num yaRendido,
}) {
  final recaudado = vendidas * precio, genero = vendidas * comision;
  final falta = recaudado - genero - yaRendido;
  final neto = precio - comision;
  return (
    genero: genero, recaudado: recaudado,
    aRendir: falta < 0 ? 0 : falta, netoPorManilla: neto < 0 ? 0 : neto,
  );
}

/// Los QR de team se guardan como data-URI (así los escribe la web); los del
/// boliche, como URL. Devuelve los bytes si es data-URI, o null si es URL.
Uint8List? bytesDeDataUri(String? url) {
  if (url == null || !url.startsWith('data:')) return null;
  final i = url.indexOf(',');
  if (i < 0) return null;
  try {
    return base64Decode(url.substring(i + 1));
  } catch (_) {
    return null;
  }
}

class QrCobro {
  const QrCobro({required this.id, required this.nombre, required this.url,
    required this.activo, this.orden = 0});
  final String id;
  final String nombre;
  final String url;
  final bool activo;
  final int orden;

  factory QrCobro.desde(Map<String, dynamic> j) => QrCobro(
        id: j['id'] as String,
        nombre: j['nombre'] as String? ?? '',
        url: j['url'] as String? ?? '',
        activo: j['activo'] != false,
        orden: (j['orden'] as num?)?.toInt() ?? 0,
      );
}

final pagosRepositoryProvider =
    Provider<PagosRepository>((ref) => PagosRepository(ref.watch(supabaseProvider)));

class PagosRepository {
  PagosRepository(this._sb);
  final SupabaseClient _sb;

  /// Pagos del evento que la persona puede ver (RLS: los propios; el jefe,
  /// los de su team; el admin, todos).
  Future<List<Pago>> lista(String eventoId) async {
    final r = await _sb
        .from('pagos')
        .select('*, p:profiles!pagos_rrpp_id_fkey(nombre)')
        .eq('evento_id', eventoId)
        .order('created_at', ascending: false)
        .limit(1000);
    return r.map(Pago.desde).toList();
  }

  /// Registra un pago. [clave] identifica ESTA operación: si el envío se
  /// repite por mala señal, el servidor devuelve el mismo pago en vez de
  /// crear otro. Devuelve el id.
  Future<String> crear({
    required String eventoId, required num monto, required String concepto,
    required String clave, String? nroOperacion, String? comprobante,
  }) async =>
      await _sb.rpc('crear_pago_unico', params: {
        'p_evento': eventoId, 'p_monto': monto, 'p_concepto': concepto,
        'p_clave': clave, 'p_nro': nroOperacion, 'p_comprobante': comprobante,
      }) as String;

  Future<void> adjuntar(String pagoId, String comprobante) => _sb.rpc(
      'adjuntar_comprobante', params: {'p_pago': pagoId, 'p_url': comprobante});

  /// Admin: pendiente → pagado → verificado.
  Future<void> avanzar(String pagoId, String estado) =>
      _sb.rpc('estado_pago', params: {'p_pago': pagoId, 'p_estado': estado});

  Future<String?> qrDelClub(String clubId) async => (await _sb
          .from('clubs').select('qr_cobro_url').eq('id', clubId).maybeSingle())
      ?['qr_cobro_url'] as String?;

  Future<String?> qrDelTeam(String teamId) async => (await _sb
          .from('teams').select('qr_cobro_url').eq('id', teamId).maybeSingle())
      ?['qr_cobro_url'] as String?;

  /// El jefe sube su QR: es el que ven sus relacionadores al rendirle.
  Future<void> guardarQrDeMiTeam(Uint8List jpeg) => _sb.rpc('set_team_qr',
      params: {'p_url': 'data:image/jpeg;base64,${base64Encode(jpeg)}'});

  /// Manillas prepagadas no anuladas que vendió la persona.
  Future<int> misVendidas(String eventoId, String usuarioId) async {
    final r = await _sb
        .from('entradas')
        .select('id')
        .eq('evento_id', eventoId)
        .eq('rrpp_id', usuarioId)
        .isFilter('mesa_id', null)
        .neq('estado', 'anulada')
        .count(CountOption.exact);
    return r.count;
  }

  /// Datos del evento y de la persona para calcular la comisión.
  Future<num> miComision(String eventoId, String usuarioId) async {
    final e = await _sb
        .from('eventos')
        .select('precio_manilla, pct_boliche, pct_rrpp, cut_rrpp')
        .eq('id', eventoId)
        .single();
    final p = await _sb.from('profiles').select('cut_rel').eq('id', usuarioId).single();
    return comisionPorManilla(
      cutPersona: p['cut_rel'] as num?,
      cutEvento: e['cut_rrpp'] as num?,
      precio: e['precio_manilla'] as num? ?? 0,
      pctBoliche: e['pct_boliche'] as num? ?? 0,
      pctRrpp: e['pct_rrpp'] as num? ?? 0,
    );
  }

  // ── QRs de cobro del boliche (admin) ──
  Future<List<QrCobro>> qrs(String clubId) async {
    final r = await _sb.from('qr_cobro').select().eq('club_id', clubId).order('orden');
    return r.map(QrCobro.desde).toList();
  }

  Future<void> crearQr(String clubId, String nombre, String url, int orden) =>
      _sb.from('qr_cobro').insert({
        'club_id': clubId, 'nombre': nombre, 'url': url, 'orden': orden, 'activo': true,
        'created_at': DateTime.now().toUtc().toIso8601String(),
      });

  Future<void> activarQr(String id, bool activo) =>
      _sb.from('qr_cobro').update({'activo': activo}).eq('id', id);

  Future<void> borrarQr(String id) => _sb.from('qr_cobro').delete().eq('id', id);
}

final pagosProvider = FutureProvider.autoDispose<List<Pago>>((ref) {
  final ev = ref.watch(eventoActivoProvider);
  if (ev == null) return const [];
  return ref.watch(pagosRepositoryProvider).lista(ev.id);
});

/// Resumen de rendición de la persona (relacionador o jefe).
final miRendicionProvider = FutureProvider.autoDispose<
    ({num genero, num recaudado, num aRendir, num netoPorManilla, int vendidas, num comision, num yaRendido})?>((ref) async {
  final ev = ref.watch(eventoActivoProvider);
  final uid = ref.watch(usuarioIdProvider);
  final rol = ref.watch(rolProvider).value;
  if (ev == null || uid == null || !(rol == Rol.rrpp || rol == Rol.jefe)) return null;
  final repo = ref.watch(pagosRepositoryProvider);
  final vendidas = await repo.misVendidas(ev.id, uid);
  final comision = await repo.miComision(ev.id, uid);
  final pagos = await ref.watch(pagosProvider.future);
  final ya = pagos.where((p) => p.rrppId == uid).fold<num>(0, (a, p) => a + p.monto);
  final r = rendicion(
      vendidas: vendidas, precio: ev.precioManilla, comision: comision, yaRendido: ya);
  return (
    genero: r.genero, recaudado: r.recaudado, aRendir: r.aRendir,
    netoPorManilla: r.netoPorManilla, vendidas: vendidas, comision: comision, yaRendido: ya,
  );
});
