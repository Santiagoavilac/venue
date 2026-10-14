import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/networking/supabase.dart';
import '../../clubs/data/clubs.dart';

typedef Fila = Map<String, dynamic>;

/// Qué se le puede hacer a un evento según su estado (para la pantalla).
({bool publicar, bool cerrar, bool eliminar}) accionesDeEvento(Fila e) => (
      publicar: e['publicado'] == false && e['estado'] != 'cerrado',
      cerrar: e['estado'] != 'cerrado',
      eliminar: true,
    );

/// Valida lo mínimo de un evento antes de mandarlo. Devuelve el problema o
/// null. El servidor valida igual; esto es para avisar sin ir a la red.
String? validarEvento({required String nombre, required String fecha,
    required num precio, required num pctBoliche, required num cut}) {
  if (nombre.trim().isEmpty) return 'Poné el nombre del evento';
  if (DateTime.tryParse(fecha) == null) return 'Fecha inválida';
  if (precio < 0) return 'El precio no puede ser negativo';
  if (pctBoliche < 0 || pctBoliche > 100) return 'El % del boliche va de 0 a 100';
  if (cut < 0 || cut > precio) return 'La comisión por manilla va de 0 al precio';
  return null;
}

final gestionRepositoryProvider =
    Provider<GestionRepository>((ref) => GestionRepository(ref.watch(supabaseProvider)));

/// Administración de eventos: lo que en la web es el "Inicio" del admin.
class GestionRepository {
  GestionRepository(this._sb);
  final SupabaseClient _sb;

  /// Eventos del boliche, también borradores y cerrados (admin).
  Future<List<Fila>> eventos(String clubId) =>
      _sb.from('eventos').select().eq('club_id', clubId).order('fecha', ascending: false).limit(60);

  /// Crea el evento como BORRADOR, con dos listas por defecto y los cupos
  /// especiales heredados del evento anterior (igual que la web).
  Future<String> crear(String clubId, {required String nombre, required String fecha,
      num precio = 60, num pctBoliche = 50, num cut = 15}) async {
    final e = await _sb.from('eventos').insert({
      'club_id': clubId, 'nombre': nombre.trim(), 'fecha': fecha,
      'precio_manilla': precio, 'pct_boliche': pctBoliche, 'cut_rrpp': cut,
    }).select('id').single();
    final id = e['id'] as String;
    final ls = await _sb.from('lista_tipos').insert([
      {'evento_id': id, 'nombre': 'Invitados', 'orden': 0},
      {'evento_id': id, 'nombre': 'Free Cover Girls', 'orden': 1},
    ]).select('id');
    for (final l in ls) {
      await _sb.rpc('heredar_cupos_lista', params: {'p_lista': l['id']});
    }
    return id;
  }

  Future<void> editar(String id, Fila campos) =>
      _sb.from('eventos').update(campos).eq('id', id);

  /// Lo hace visible para el equipo. Devuelve cuántas listas y mesas tiene.
  Future<Fila> publicar(String id) async =>
      Map<String, dynamic>.from(await _sb.rpc('publicar_evento', params: {'p_evento': id}) as Map);

  Future<void> cerrar(String id) =>
      _sb.from('eventos').update({'estado': 'cerrado'}).eq('id', id);

  /// Borra el evento con TODO: entradas, invitados, mesas, pagos, ventas.
  Future<void> eliminar(String id) => _sb.rpc('eliminar_evento', params: {'p_evento': id});

  // ── listas ──
  Future<List<Fila>> listas(String eventoId) =>
      _sb.from('lista_tipos').select().eq('evento_id', eventoId).order('orden', ascending: true);

  Future<void> crearLista(String eventoId, Fila campos, int orden) async {
    final l = await _sb.from('lista_tipos')
        .insert({...campos, 'evento_id': eventoId, 'orden': orden}).select('id').single();
    await _sb.rpc('heredar_cupos_lista', params: {'p_lista': l['id']});
  }

  Future<void> editarLista(String id, Fila campos) =>
      _sb.from('lista_tipos').update(campos).eq('id', id);

  Future<void> borrarLista(String id) => _sb.from('lista_tipos').delete().eq('id', id);

  Future<void> intercambiarOrden(Fila a, Fila b) async {
    await _sb.from('lista_tipos').update({'orden': b['orden']}).eq('id', a['id'] as String);
    await _sb.from('lista_tipos').update({'orden': a['orden']}).eq('id', b['id'] as String);
  }

  // ── cupos especiales por persona ──
  Future<List<Fila>> cuposDeLista(String listaId) =>
      _sb.from('cupo_rrpp').select('user_id, cupo').eq('lista_tipo_id', listaId);

  Future<List<Fila>> personasConCupo(String clubId) async =>
      ((await _sb.rpc('roster_cupos', params: {'p_club': clubId})) as List)
          .map((x) => Map<String, dynamic>.from(x as Map)).toList();

  Future<void> fijarCupo(String listaId, String usuarioId, int cupo) => _sb
      .from('cupo_rrpp').upsert({'lista_tipo_id': listaId, 'user_id': usuarioId, 'cupo': cupo});

  Future<void> quitarCupo(String listaId, String usuarioId) => _sb
      .from('cupo_rrpp').delete().eq('lista_tipo_id', listaId).eq('user_id', usuarioId);

  // ── fases de preventa ──
  Future<List<Fila>> fases(String eventoId) async =>
      ((await _sb.rpc('fases_evento', params: {'p_evento': eventoId})) as List)
          .map((x) => Map<String, dynamic>.from(x as Map)).toList();

  Future<void> ventaPorFases(String eventoId, bool activa) =>
      _sb.rpc('set_venta_por_fases', params: {'p_evento': eventoId, 'p_on': activa});

  Future<void> guardarFase(String eventoId, {String? id, required String nombre,
      required num precio, int? cupo, DateTime? desde, DateTime? hasta, int orden = 0}) =>
      _sb.rpc('guardar_fase', params: {
        'p_evento': eventoId, 'p_id': id, 'p_nombre': nombre.trim(), 'p_precio': precio,
        'p_cupo': cupo, 'p_desde': desde?.toUtc().toIso8601String(),
        'p_hasta': hasta?.toUtc().toIso8601String(), 'p_orden': orden, 'p_activo': true,
      });

  Future<void> borrarFase(String id) => _sb.rpc('borrar_fase', params: {'p_fase': id});

  Future<void> arteDeFase(String id, String url) =>
      _sb.rpc('fase_arte', params: {'p_fase': id, 'p_url': url});

  Future<List<Fila>> cuposPorTeam(String faseId) async =>
      ((await _sb.rpc('cupos_fase', params: {'p_fase': faseId})) as List)
          .map((x) => Map<String, dynamic>.from(x as Map)).toList();

  Future<void> fijarCupoTeam(String faseId, String teamId, int cupo) => _sb.rpc(
      'guardar_cupo_team', params: {'p_fase': faseId, 'p_team': teamId, 'p_cupo': cupo});

  // ── ventana y excepciones de venta ──
  Future<void> ventanaDeVenta(String eventoId, DateTime? desde, DateTime? hasta) =>
      _sb.from('eventos').update({
        'manilla_desde': desde?.toUtc().toIso8601String(),
        'manilla_hasta_ts': hasta?.toUtc().toIso8601String(),
      }).eq('id', eventoId);

  Future<List<Fila>> excepciones(String eventoId) async =>
      ((await _sb.rpc('excepciones_venta', params: {'p_evento': eventoId})) as List)
          .map((x) => Map<String, dynamic>.from(x as Map)).toList();

  /// Un team o una persona que puede vender más tarde. Reemplaza la que
  /// ya tuviera para este evento.
  Future<void> fijarExcepcion(String eventoId, DateTime hasta,
      {String? teamId, String? usuarioId}) async {
    assert((teamId == null) != (usuarioId == null));
    final previa = _sb.from('venta_excepcion').delete().eq('evento_id', eventoId);
    await (teamId != null ? previa.eq('team_id', teamId) : previa.eq('user_id', usuarioId!));
    await _sb.from('venta_excepcion').insert({
      'evento_id': eventoId, 'hasta_ts': hasta.toUtc().toIso8601String(),
      'team_id': teamId, 'user_id': usuarioId,
    });
  }

  Future<void> quitarExcepcion(String id) =>
      _sb.from('venta_excepcion').delete().eq('id', id);

  // ── avisos al equipo ──
  Future<List<Fila>> avisos(String clubId) async =>
      ((await _sb.rpc('avisos_admin', params: {'p_club': clubId})) as List)
          .map((x) => Map<String, dynamic>.from(x as Map)).toList();

  Future<void> crearAviso(String clubId, {required String titulo, required String mensaje,
      String destino = 'todos', String? teamId, DateTime? hasta}) =>
      _sb.from('avisos').insert({
        'titulo': titulo.trim(), 'mensaje': mensaje.trim(), 'destino': destino,
        'club_id': clubId, 'team_id': destino == 'team' ? teamId : null,
        'hasta_ts': hasta?.toUtc().toIso8601String(),
      });

  Future<void> activarAviso(String id, bool activo) =>
      _sb.from('avisos').update({'activo': activo}).eq('id', id);

  Future<void> borrarAviso(String id) => _sb.from('avisos').delete().eq('id', id);

  Future<List<Fila>> lectores(String avisoId) async =>
      ((await _sb.rpc('aviso_lectores', params: {'p_aviso': avisoId})) as List)
          .map((x) => Map<String, dynamic>.from(x as Map)).toList();
}

final eventosGestionProvider = FutureProvider.autoDispose<List<Fila>>((ref) async {
  final club = ref.watch(clubActivoIdProvider);
  if (club == null) return const [];
  return ref.watch(gestionRepositoryProvider).eventos(club);
});
