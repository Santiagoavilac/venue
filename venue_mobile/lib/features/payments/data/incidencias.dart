import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/networking/supabase.dart';
import '../../clubs/data/clubs.dart';

/// Plata que el banco cobró y que no entregó nada.
///
/// Pasa cuando el pago llega después de los diez minutos del QR, cuando el
/// cobro entra y la emisión falla, o cuando el pedido ya estaba cancelado. El
/// sistema no inventa una entrada ni devuelve plata por su cuenta: anota el
/// caso con el monto y el id del banco, y alguien del boliche lo resuelve.
class Incidencia {
  const Incidencia({
    required this.id,
    required this.detalle,
    required this.monto,
    required this.creado,
    required this.abierta,
    required this.puedeEmitir,
    this.bancoTx,
    this.notaPago,
    this.cliente,
    this.usuario,
    this.evento,
    this.cantidad,
    this.resolucion,
  });

  final String id;
  final String detalle;
  final num monto;
  final DateTime creado;
  final bool abierta;

  /// Se puede emitir la entrada a mano: la orden existe y el evento no terminó.
  final bool puedeEmitir;
  final String? bancoTx;
  final String? notaPago;
  final String? cliente;
  final String? usuario;
  final String? evento;
  final int? cantidad;
  final String? resolucion;

  /// Llegó fuera del plazo de diez minutos. Si no, el cobro entró y la
  /// emisión falló por otra razón.
  bool get tarde => notaPago == 'PAGADO_FUERA_DE_PLAZO';

  factory Incidencia.desde(Map<String, dynamic> j) => Incidencia(
        id: '${j['id']}',
        detalle: j['detalle'] as String? ?? '',
        monto: j['monto'] as num? ?? 0,
        creado: DateTime.parse('${j['created_at']}').toLocal(),
        abierta: j['estado'] == 'abierta',
        puedeEmitir: j['puede_emitir'] == true,
        bancoTx: j['banco_tx'] as String?,
        notaPago: j['nota_pago'] as String?,
        cliente: j['cliente'] as String?,
        usuario: j['usuario'] as String?,
        evento: j['evento'] as String?,
        cantidad: (j['cantidad'] as num?)?.toInt(),
        resolucion: j['resolucion'] as String?,
      );
}

class IncidenciasRepository {
  IncidenciasRepository(this._sb);
  final SupabaseClient _sb;

  Future<({int abiertas, List<Incidencia> lista})> listar(
    String club, {
    String estado = 'abierta',
  }) async {
    final r = Map<String, dynamic>.from(
      await _sb.rpc(
            'aftr_incidencias',
            params: {'p_club': club, 'p_estado': estado},
          )
          as Map,
    );
    return (
      abiertas: (r['abiertas'] as num?)?.toInt() ?? 0,
      lista: [
        for (final x in (r['incidencias'] as List? ?? const []))
          Incidencia.desde(Map<String, dynamic>.from(x as Map)),
      ],
    );
  }

  /// `accion`: emitir, devolver o cerrar. La nota queda en el historial con
  /// quién la escribió: devolver plata se hace en el banco, acá queda dicho.
  Future<int> resolver(String id, String accion, String nota) async {
    final r = Map<String, dynamic>.from(
      await _sb.rpc(
            'aftr_incidencia_resolver',
            params: {'p_id': id, 'p_accion': accion, 'p_nota': nota},
          )
          as Map,
    );
    return (r['emitidas'] as num?)?.toInt() ?? 0;
  }
}

final incidenciasRepositoryProvider = Provider<IncidenciasRepository>(
  (ref) => IncidenciasRepository(ref.watch(supabaseProvider)),
);

final incidenciasProvider =
    FutureProvider.family<({int abiertas, List<Incidencia> lista}), String>((
  ref,
  estado,
) async {
  final club = ref.watch(clubActivoIdProvider);
  if (club == null) return (abiertas: 0, lista: <Incidencia>[]);
  return ref.watch(incidenciasRepositoryProvider).listar(club, estado: estado);
});

/// Para el contador del menú: cuántos cobros esperan resolución.
final incidenciasAbiertasProvider = Provider<int>(
  (ref) => ref.watch(incidenciasProvider('abierta')).value?.abiertas ?? 0,
);
