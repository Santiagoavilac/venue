import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/networking/supabase.dart';
import '../../authentication/data/sesion.dart';
import '../../events/data/eventos.dart';

class Entrada {
  const Entrada({
    required this.id,
    required this.codigo,
    required this.cliente,
    required this.precio,
    required this.estado,
    this.usedAt,
  });
  final String id;
  final String codigo;
  final String cliente;
  final num precio;

  /// valida | usada | anulada
  final String estado;
  final DateTime? usedAt;

  bool get valida => estado == 'valida';

  factory Entrada.desde(Map<String, dynamic> j) => Entrada(
        id: j['id'] as String,
        codigo: j['code'] as String? ?? '',
        cliente: j['cliente'] as String? ?? '',
        precio: j['precio'] as num? ?? 0,
        estado: j['estado'] as String? ?? '',
        usedAt: DateTime.tryParse(j['used_at'] as String? ?? '')?.toLocal(),
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
        .select('id, code, cliente, precio, estado, used_at')
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
}

final misEntradasProvider = FutureProvider.autoDispose<List<Entrada>>((ref) {
  final ev = ref.watch(eventoActivoProvider);
  final uid = ref.watch(usuarioIdProvider);
  if (ev == null || uid == null) return const [];
  return ref.watch(entradasRepositoryProvider).mias(ev.id, uid);
});
