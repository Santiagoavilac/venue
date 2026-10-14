import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/networking/supabase.dart';
import '../../authentication/data/sesion.dart';
import '../../events/data/eventos.dart';
import '../../teams/data/equipo.dart';

class Entrada {
  const Entrada({
    required this.id,
    required this.codigo,
    required this.cliente,
    required this.precio,
    required this.estado,
    this.rrppId = '',
    this.rrppNombre = '',
    this.faseId,
    this.usedAt,
    this.filtrada = false,
  });
  final String id;
  final String codigo;
  final String cliente;
  final num precio;

  /// valida | usada | anulada
  final String estado;
  final String rrppId;
  final String rrppNombre;
  final String? faseId;
  final DateTime? usedAt;

  /// Marcada "no pasó el control" en la puerta.
  final bool filtrada;

  bool get valida => estado == 'valida';

  factory Entrada.desde(Map<String, dynamic> j) => Entrada(
        id: j['id'] as String,
        codigo: j['code'] as String? ?? '',
        cliente: j['cliente'] as String? ?? '',
        precio: j['precio'] as num? ?? 0,
        estado: j['estado'] as String? ?? '',
        rrppId: j['rrpp_id'] as String? ?? '',
        rrppNombre: (j['rrpp'] as Map?)?['nombre'] as String? ?? '',
        faseId: j['fase_id'] as String?,
        filtrada: j['filtro_at'] != null,
        usedAt: DateTime.tryParse(j['used_at'] as String? ?? '')?.toLocal(),
      );
}

/// Fase de preventa: precio y stock propios.
class Fase {
  const Fase({
    required this.id,
    required this.nombre,
    required this.precio,
    this.cupo,
    this.vendidas,
    this.ticketUrl,
    this.activo = true,
    this.desde,
    this.hasta,
    this.orden = 0,
  });
  final String id;
  final String nombre;
  final num precio;
  final int? cupo;
  final int? vendidas;

  /// Arte propio de la fase; si no tiene, se usa el del evento con un sello.
  final String? ticketUrl;
  final bool activo;
  final DateTime? desde;
  final DateTime? hasta;
  final int orden;

  int? get quedan => cupo == null || vendidas == null ? null : (cupo! - vendidas!).clamp(0, cupo!);

  factory Fase.desde(Map<String, dynamic> j) => Fase(
        id: j['id'] as String,
        nombre: j['nombre'] as String? ?? '',
        precio: j['precio'] as num? ?? 0,
        cupo: (j['cupo'] as num?)?.toInt(),
        vendidas: (j['vendidas'] as num?)?.toInt(),
        ticketUrl: j['ticket_url'] as String?,
        activo: j['activo'] != false,
        desde: DateTime.tryParse(j['desde'] as String? ?? '')?.toLocal(),
        hasta: DateTime.tryParse(j['hasta'] as String? ?? '')?.toLocal(),
        orden: (j['orden'] as num?)?.toInt() ?? 0,
      );
}

/// Texto del QR. Mismo formato que la web: lo lee el escáner de ambas.
String payloadEntrada(String eventoId, String codigo) => 'EVT:$eventoId:$codigo';
String payloadLista(String eventoId, String codigo) => 'LST:$eventoId:$codigo';

final entradasRepositoryProvider = Provider<EntradasRepository>(
  (ref) => EntradasRepository(ref.watch(supabaseProvider)),
);

class EntradasRepository {
  EntradasRepository(this._sb);
  final SupabaseClient _sb;

  /// Entradas prepagadas que vendió la persona (sin las manillas de mesa).
  Future<List<Entrada>> mias(String eventoId, String usuarioId) async {
    final r = await _sb
        .from('entradas')
        .select('id, code, cliente, precio, estado, used_at, rrpp_id, fase_id, filtro_at')
        .eq('evento_id', eventoId)
        .eq('rrpp_id', usuarioId)
        .isFilter('mesa_id', null)
        .order('created_at', ascending: false)
        .limit(1000);
    return r.map(Entrada.desde).toList();
  }

  /// El servidor decide precio, fase vigente, cupo y ventana de venta.
  Future<Entrada> generar(String eventoId, String cliente) async {
    final r = await _sb.rpc('generar_entrada',
        params: {'p_evento': eventoId, 'p_cliente': cliente.trim()});
    return Entrada.desde(Map<String, dynamic>.from(r as Map));
  }

  Future<void> anular(String entradaId) =>
      _sb.rpc('anular_entrada', params: {'p_entrada': entradaId});

  /// Borra la entrada del todo (el servidor decide quién y cuándo puede).
  Future<void> eliminar(String entradaId) =>
      _sb.rpc('eliminar_entrada', params: {'p_entrada': entradaId});

  /// Todas las prepagadas del evento con su vendedor (jefe y admin).
  Future<List<Entrada>> todas(String eventoId) async {
    final filas = await traerTodo((d, h) => _sb
        .from('entradas')
        .select('id, code, cliente, precio, estado, used_at, rrpp_id, fase_id, filtro_at, '
            'rrpp:profiles!entradas_rrpp_id_fkey(nombre)')
        .eq('evento_id', eventoId)
        .isFilter('mesa_id', null)
        .order('created_at', ascending: false)
        .order('id', ascending: true)
        .range(d, h));
    return filas.map(Entrada.desde).toList();
  }

  Future<List<Fase>> fases(String eventoId) async {
    final r = await _sb
        .from('evento_fase')
        .select('id, nombre, precio, cupo, desde, hasta, orden, activo, ticket_url')
        .eq('evento_id', eventoId)
        .order('orden', ascending: true);
    return r.map(Fase.desde).toList();
  }

  /// Fase en la que se vende ahora, o null si el evento no vende por fases
  /// (o ninguna está abierta).
  Future<Fase?> faseVigente(String eventoId) async {
    final r = await _sb.rpc('fase_vigente', params: {'p_evento': eventoId});
    if (r is! Map) return null;
    return Fase.desde(Map<String, dynamic>.from(r));
  }

  /// Ventana en la que la persona puede vender prepagadas.
  Future<({DateTime? desde, DateTime? hasta})> ventana(
      String eventoId, String usuarioId) async {
    final r = Map<String, dynamic>.from(await _sb.rpc('ventana_venta',
        params: {'p_evento': eventoId, 'p_user': usuarioId}) as Map? ?? const {});
    DateTime? f(String k) => DateTime.tryParse(r[k] as String? ?? '')?.toLocal();
    return (desde: f('desde'), hasta: f('hasta'));
  }
}

final entradasProvider = FutureProvider.autoDispose<List<Entrada>>((ref) {
  final ev = ref.watch(eventoActivoProvider);
  if (ev == null) return const [];
  return ref.watch(entradasRepositoryProvider).todas(ev.id);
});

final fasesProvider = FutureProvider.autoDispose<List<Fase>>((ref) {
  final ev = ref.watch(eventoActivoProvider);
  if (ev == null) return const [];
  return ref.watch(entradasRepositoryProvider).fases(ev.id);
});

final faseVigenteProvider = FutureProvider.autoDispose<Fase?>((ref) async {
  final ev = ref.watch(eventoActivoProvider);
  if (ev == null || !ev.ventaPorFases) return null;
  return ref.watch(entradasRepositoryProvider).faseVigente(ev.id);
});

final ventanaProvider =
    FutureProvider.autoDispose<({DateTime? desde, DateTime? hasta})>((ref) async {
  final ev = ref.watch(eventoActivoProvider);
  final uid = ref.watch(usuarioIdProvider);
  if (ev == null || uid == null) return (desde: null, hasta: null);
  return ref.watch(entradasRepositoryProvider).ventana(ev.id, uid);
});

final misEntradasProvider = FutureProvider.autoDispose<List<Entrada>>((ref) {
  final ev = ref.watch(eventoActivoProvider);
  final uid = ref.watch(usuarioIdProvider);
  if (ev == null || uid == null) return const [];
  return ref.watch(entradasRepositoryProvider).mias(ev.id, uid);
});
