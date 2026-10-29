import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/networking/supabase.dart';
import 'modelos.dart';

/// Todas las llamadas de AFTR. Pasan solo por las RPC aftr_* (db/35): el
/// cliente nunca toca tablas de Venue directo.
class AftrRepo {
  AftrRepo(this._sb);
  final SupabaseClient _sb;

  Future<Object?> _rpc(String fn, [Map<String, dynamic>? p]) => _sb.rpc(fn, params: p ?? const {});

  String _dia(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  Future<List<Evento>> eventos({DateTime? desde, DateTime? hasta}) async {
    final r = await _rpc('aftr_eventos', {
      'p_desde': desde == null ? null : _dia(desde),
      'p_hasta': hasta == null ? null : _dia(hasta),
    });
    return [for (final x in (r as List? ?? const [])) Evento.desde(Map<String, dynamic>.from(x as Map))];
  }

  Future<EventoDetalle?> evento(String id) async {
    final r = await _rpc('aftr_evento', {'p_id': id});
    return r is Map ? EventoDetalle.desde(Map<String, dynamic>.from(r)) : null;
  }

  Future<List<Lugar>> lugares() async {
    final r = await _rpc('aftr_lugares');
    return [for (final x in (r as List? ?? const [])) Lugar.desde(Map<String, dynamic>.from(x as Map))];
  }

  /// Dónde se están vendiendo entradas: boliche → intensidad de 0 a 1
  /// (relativa al que más vendió). La base nunca manda el número de entradas.
  Future<Map<String, double>> calor() async {
    final r = await _rpc('aftr_calor');
    return {
      for (final x in (r as List? ?? const []))
        (x as Map)['club_id'] as String: ((x['intensidad'] as num?) ?? 0).toDouble(),
    };
  }

  Future<Lugar?> lugar(String id) async {
    final r = await _rpc('aftr_lugar', {'p_id': id});
    return r is Map ? Lugar.desde(Map<String, dynamic>.from(r)) : null;
  }

  Future<Cliente?> miPerfil() async {
    final r = await _rpc('aftr_mi_perfil');
    return r is Map ? Cliente.desde(Map<String, dynamic>.from(r)) : null;
  }

  Future<Cliente> crearPerfil(String usuario, String nombre) async {
    final r = await _rpc('aftr_crear_perfil', {'p_usuario': usuario, 'p_nombre': nombre});
    return Cliente.desde(Map<String, dynamic>.from(r as Map));
  }

  Future<List<Cliente>> buscarUsuario(String q) async {
    final r = await _rpc('aftr_buscar_usuario', {'p_q': q});
    return [for (final x in (r as List? ?? const [])) Cliente.desde(Map<String, dynamic>.from(x as Map))];
  }

  Future<void> eliminarCuenta() => _rpc('aftr_eliminar_cuenta');

  Future<bool> seguir(String club) async => (await _rpc('aftr_seguir', {'p_club': club})) == true;

  Future<bool> guardar(String evento) async => (await _rpc('aftr_guardar', {'p_evento': evento})) == true;

  Future<({List<Evento> eventos, List<Lugar> lugares})> misGuardados() async {
    final r = Map<String, dynamic>.from(await _rpc('aftr_mis_guardados') as Map);
    return (
      eventos: [for (final x in (r['eventos'] as List? ?? const [])) Evento.desde(Map<String, dynamic>.from(x as Map))],
      lugares: [for (final x in (r['lugares'] as List? ?? const [])) Lugar.desde(Map<String, dynamic>.from(x as Map))],
    );
  }

  /// Crea el pedido; el boliche lo confirma desde Venue y ahí salen los QR.
  Future<void> comprar(String evento, String? fase, int cantidad) =>
      _rpc('aftr_comprar', {'p_evento': evento, 'p_fase': fase, 'p_cantidad': cantidad});

  Future<void> reservarMesa(String evento, String mesa, String? combo) =>
      _rpc('aftr_reservar_mesa', {'p_evento': evento, 'p_mesa': mesa, 'p_combo': combo});

  Future<String> anotarmeLista(String evento, String lista) async {
    final r = Map<String, dynamic>.from(await _rpc('aftr_anotarme_lista', {'p_evento': evento, 'p_lista': lista}) as Map);
    return r['qr'] as String;
  }

  Future<void> cancelarPedido(String orden) => _rpc('aftr_cancelar_mi_orden', {'p_orden': orden});

  Future<Accesos> misAccesos() async =>
      Accesos.desde(Map<String, dynamic>.from(await _rpc('aftr_mis_accesos') as Map));

  Future<String> transferir(String entrada, String usuario) async {
    final r = Map<String, dynamic>.from(await _rpc('aftr_transferir', {'p_entrada': entrada, 'p_usuario': usuario}) as Map);
    return r['nombre'] as String? ?? usuario;
  }
}

final repoProvider = Provider<AftrRepo>((ref) => AftrRepo(ref.watch(supabaseProvider)));

/// Rango de fechas de Descubrir.
enum Cuando { hoy, manana, finde, todo }

({DateTime desde, DateTime hasta}) rangoDe(Cuando c, DateTime ahora) {
  final hoy = DateTime(ahora.year, ahora.month, ahora.day);
  return switch (c) {
    Cuando.hoy => (desde: hoy, hasta: hoy),
    Cuando.manana => (desde: hoy.add(const Duration(days: 1)), hasta: hoy.add(const Duration(days: 1))),
    // de viernes a domingo; si ya es finde, desde hoy
    Cuando.finde => () {
        final aViernes = (DateTime.friday - hoy.weekday) % 7;
        final desde = hoy.weekday >= DateTime.friday ? hoy : hoy.add(Duration(days: aViernes));
        final hasta = hoy.add(Duration(days: (DateTime.sunday - hoy.weekday) % 7));
        return (desde: desde, hasta: hasta);
      }(),
    Cuando.todo => (desde: hoy, hasta: hoy.add(const Duration(days: 60))),
  };
}

final eventosProvider = FutureProvider<List<Evento>>((ref) => ref.watch(repoProvider).eventos());

final lugaresProvider = FutureProvider<List<Lugar>>((ref) => ref.watch(repoProvider).lugares());

final calorProvider = FutureProvider.autoDispose<Map<String, double>>((ref) => ref.watch(repoProvider).calor());

final eventoProvider = FutureProvider.autoDispose.family<EventoDetalle?, String>((ref, id) {
  ref.watch(usuarioIdProvider); // "guardado" depende de quién mira
  return ref.watch(repoProvider).evento(id);
});

final lugarProvider = FutureProvider.autoDispose.family<Lugar?, String>((ref, id) {
  ref.watch(usuarioIdProvider);
  return ref.watch(repoProvider).lugar(id);
});

/// El perfil AFTR de quien está logueado; null sin sesión o sin perfil todavía.
final perfilProvider = FutureProvider<Cliente?>((ref) async {
  final uid = ref.watch(usuarioIdProvider);
  if (uid == null) return null;
  return ref.watch(repoProvider).miPerfil();
});

/// La billetera. Se recarga sola cuando Venue confirma un pedido o la puerta
/// marca un QR como usado (realtime con RLS: solo llegan las filas propias).
final accesosProvider = FutureProvider<Accesos>((ref) async {
  final uid = ref.watch(usuarioIdProvider);
  if (uid == null) return const Accesos([]);
  final sb = ref.watch(supabaseProvider);
  Timer? espera;
  final canal = sb.channel('aftr-accesos-$uid');
  for (final t in ['entradas', 'registros', 'mesas', 'aftr_ordenes']) {
    canal.onPostgresChanges(
      event: PostgresChangeEvent.all,
      schema: 'public',
      table: t,
      filter: PostgresChangeFilter(type: PostgresChangeFilterType.eq, column: 'cliente_id', value: uid),
      callback: (_) {
        espera?.cancel();
        espera = Timer(const Duration(milliseconds: 600), ref.invalidateSelf);
      },
    );
  }
  canal.subscribe();
  ref.onDispose(() {
    espera?.cancel();
    sb.removeChannel(canal);
  });
  return ref.watch(repoProvider).misAccesos();
});

final guardadosProvider = FutureProvider.autoDispose((ref) {
  if (ref.watch(usuarioIdProvider) == null) {
    return Future.value((eventos: const <Evento>[], lugares: const <Lugar>[]));
  }
  return ref.watch(repoProvider).misGuardados();
});
