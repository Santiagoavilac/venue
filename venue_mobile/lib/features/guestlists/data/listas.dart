import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/networking/supabase.dart';
import '../../authentication/data/sesion.dart';
import '../../events/data/eventos.dart';
import '../../teams/data/equipo.dart';

/// Una lista del evento ("Invitados", "Free", "Compra en puerta"…).
class ListaTipo {
  const ListaTipo({
    required this.id,
    required this.nombre,
    this.registroDesde,
    this.registroHasta,
    this.ingresoHasta,
  });
  final String id;
  final String nombre;
  final DateTime? registroDesde;
  final DateTime? registroHasta;

  /// Hora tope de ingreso en puerta (HH:MM), si la lista la tiene.
  final String? ingresoHasta;

  /// ¿Se puede anotar ahora? Es solo para avisar en pantalla: el servidor
  /// vuelve a comprobarlo en `registrar_lista`.
  bool abierta(DateTime ahora) =>
      (registroDesde == null || !ahora.isBefore(registroDesde!)) &&
      (registroHasta == null || !ahora.isAfter(registroHasta!));

  factory ListaTipo.desde(Map<String, dynamic> j) => ListaTipo(
        id: j['id'] as String,
        nombre: j['nombre'] as String? ?? '',
        registroDesde:
            DateTime.tryParse(j['registro_desde'] as String? ?? '')?.toLocal(),
        registroHasta:
            DateTime.tryParse(j['registro_hasta'] as String? ?? '')?.toLocal(),
        ingresoHasta: (j['ingreso_hasta'] as String?)?.substring(0, 5),
      );
}

class Invitado {
  const Invitado({
    required this.id,
    required this.listaId,
    required this.nombre,
    required this.rrppId,
    this.rrppNombre = '',
    this.codigo,
    this.ingresoAt,
  });
  final String id;
  final String listaId;
  final String nombre;
  final String rrppId;

  /// Quién lo anotó (viene embebido cuando se trae la lista completa).
  final String rrppNombre;
  final String? codigo;
  final DateTime? ingresoAt;

  Invitado con({DateTime? ingresoAt, bool limpiarIngreso = false, String? codigo}) => Invitado(
        id: id, listaId: listaId, nombre: nombre, rrppId: rrppId, rrppNombre: rrppNombre,
        codigo: codigo ?? this.codigo,
        ingresoAt: limpiarIngreso ? null : (ingresoAt ?? this.ingresoAt),
      );

  bool get ingreso => ingresoAt != null;

  factory Invitado.desde(Map<String, dynamic> j) => Invitado(
        id: j['id'] as String,
        listaId: j['lista_tipo_id'] as String,
        nombre: j['nombre'] as String? ?? '',
        rrppId: j['rrpp_id'] as String,
        rrppNombre: (j['rrpp'] as Map?)?['nombre'] as String? ?? '',
        codigo: j['code'] as String?,
        ingresoAt:
            DateTime.tryParse(j['ingreso_at'] as String? ?? '')?.toLocal(),
      );
}

class ResultadoAnotar {
  const ResultadoAnotar(this.insertados, this.duplicados);
  final int insertados;

  /// Nombres que ya estaban anotados en el evento (se anotan igual; es aviso).
  final List<String> duplicados;
}

/// Un nombre por línea o separados por coma. "Luis +2" queda "Luis": cada
/// persona va con su nombre completo (misma regla que la web).
List<String> separarNombres(String crudo) => crudo
    .split(RegExp(r'[\n,]'))
    .map((s) => s.trim().replaceFirst(RegExp(r'\s*\+\s*\d+$'), '').trim())
    .where((s) => s.isNotEmpty)
    .toList();

final listasRepositoryProvider = Provider<ListasRepository>(
  (ref) => ListasRepository(ref.watch(supabaseProvider)),
);

class ListasRepository {
  ListasRepository(this._sb);
  final SupabaseClient _sb;

  Future<List<ListaTipo>> listas(String eventoId) async {
    final r = await _sb
        .from('lista_tipos')
        .select('id, nombre, registro_desde, registro_hasta, ingreso_hasta')
        .eq('evento_id', eventoId)
        .order('orden');
    return r.map(ListaTipo.desde).toList();
  }

  /// Cupo propio por lista: id de lista → cupo. Sin entrada = sin tope.
  Future<Map<String, int>> misCupos(String eventoId) async {
    final r = await _sb.rpc('mis_cupos', params: {'p_evento': eventoId});
    return {
      for (final x in (r as List? ?? const []))
        if (x['cupo'] != null)
          x['lista_tipo_id'] as String: (x['cupo'] as num).toInt(),
    };
  }

  Future<List<Invitado>> misInvitados(String eventoId, String usuarioId) async {
    final r = await _sb
        .from('registros')
        .select('id, lista_tipo_id, nombre, rrpp_id, code, ingreso_at')
        .eq('evento_id', eventoId)
        .eq('rrpp_id', usuarioId)
        .order('created_at', ascending: false)
        .limit(1000);
    return r.map(Invitado.desde).toList();
  }

  /// Todos los invitados del evento, con quién los anotó. Paginado: una
  /// noche grande pasa las 1000 filas.
  Future<List<Invitado>> todos(String eventoId) async {
    final filas = await traerTodo((d, h) => _sb
        .from('registros')
        .select('id, lista_tipo_id, nombre, rrpp_id, code, ingreso_at, '
            'rrpp:profiles!registros_rrpp_id_fkey(nombre)')
        .eq('evento_id', eventoId)
        .order('created_at', ascending: false)
        .order('id')
        .range(d, h));
    return filas.map(Invitado.desde).toList();
  }

  /// [aNombreDe]: usuario al que se le atribuyen (solo jefe/admin; el
  /// servidor lo vuelve a comprobar).
  Future<ResultadoAnotar> anotar(String listaId, List<String> nombres,
      {String? aNombreDe}) async {
    final r = Map<String, dynamic>.from(await _sb.rpc('registrar_lista', params: {
      'p_lista': listaId,
      'p_nombres': nombres,
      'p_a_nombre_de': aNombreDe,
    }) as Map);
    return ResultadoAnotar(
      (r['insertados'] as num?)?.toInt() ?? 0,
      ((r['duplicados'] as List?) ?? const []).cast<String>(),
    );
  }

  Future<void> eliminar(String registroId) =>
      _sb.rpc('eliminar_registro', params: {'p_registro': registroId});

  /// Genera (o devuelve) el código QR de un invitado.
  Future<String> generarQr(String registroId) async {
    final r = Map<String, dynamic>.from(await _sb
        .rpc('generar_qr_lista', params: {'p_registro': registroId}) as Map);
    return r['code'] as String;
  }
}

final listasProvider = FutureProvider.autoDispose<List<ListaTipo>>((ref) {
  final ev = ref.watch(eventoActivoProvider);
  if (ev == null) return const [];
  return ref.watch(listasRepositoryProvider).listas(ev.id);
});

final misCuposProvider = FutureProvider.autoDispose<Map<String, int>>((ref) {
  final ev = ref.watch(eventoActivoProvider);
  if (ev == null) return const {};
  return ref.watch(listasRepositoryProvider).misCupos(ev.id);
});

final invitadosProvider = FutureProvider.autoDispose<List<Invitado>>((ref) {
  final ev = ref.watch(eventoActivoProvider);
  if (ev == null) return const [];
  return ref.watch(listasRepositoryProvider).todos(ev.id);
});

final misInvitadosProvider = FutureProvider.autoDispose<List<Invitado>>((ref) {
  final ev = ref.watch(eventoActivoProvider);
  final uid = ref.watch(usuarioIdProvider);
  if (ev == null || uid == null) return const [];
  return ref.watch(listasRepositoryProvider).misInvitados(ev.id, uid);
});
