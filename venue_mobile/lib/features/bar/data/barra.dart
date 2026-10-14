import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/networking/supabase.dart';
import '../../../core/sync/cola_offline.dart';
import '../../clubs/data/clubs.dart';
import '../../events/data/eventos.dart';

typedef Fila = Map<String, dynamic>;

/// Un trago de la carta tal como lo ve el bartender: precio de venta y para
/// cuántos vasos alcanza el stock. Nunca el costo.
class TragoCarta {
  const TragoCarta({required this.id, required this.nombre, required this.precio,
    required this.categoria, required this.alcanzaPara});
  final String id;
  final String nombre;
  final num precio;
  final String categoria;
  final int alcanzaPara;

  factory TragoCarta.desde(Fila j) => TragoCarta(
        id: j['id'] as String,
        nombre: j['nombre'] as String? ?? '',
        precio: j['precio'] as num? ?? 0,
        categoria: j['categoria'] as String? ?? '',
        alcanzaPara: (j['alcanza_para'] as num?)?.toInt() ?? 0,
      );
}

/// Carrito del punto de venta: cuántos vasos de cada trago.
class Carrito {
  final _n = <String, int>{};

  int de(String tragoId) => _n[tragoId] ?? 0;
  bool get vacio => _n.values.every((v) => v <= 0);
  int get vasos => _n.values.fold(0, (a, b) => a + b);

  /// Suma un vaso sin pasarse de lo que alcanza el stock. Devuelve false si
  /// ya no alcanza (la base lo vuelve a comprobar al cobrar).
  bool sumar(TragoCarta t) {
    if (de(t.id) >= t.alcanzaPara) return false;
    _n[t.id] = de(t.id) + 1;
    return true;
  }

  void restar(String tragoId) {
    final v = de(tragoId) - 1;
    v <= 0 ? _n.remove(tragoId) : _n[tragoId] = v;
  }

  void vaciar() => _n.clear();

  num total(Iterable<TragoCarta> carta) =>
      carta.fold<num>(0, (a, t) => a + t.precio * de(t.id));

  /// Renglones para `bar_vender`.
  List<Fila> items() => [
        for (final e in _n.entries)
          if (e.value > 0) {'trago_id': e.key, 'qty': e.value},
      ];
}

/// ml que quedan en un lote a partir de botellas cerradas + lo que queda en
/// la abierta, para el conteo físico de la noche.
num mlContados({required int botellasCerradas, required num mlAbierta, required int volumenMl}) =>
    botellasCerradas * volumenMl + mlAbierta;

String botellasDe(num ml, num volumenMl) =>
    volumenMl <= 0 ? '0' : (ml / volumenMl).toStringAsFixed(1);

final barraRepositoryProvider =
    Provider<BarraRepository>((ref) => BarraRepository(ref.watch(supabaseProvider)));

class BarraRepository {
  BarraRepository(this._sb);
  final SupabaseClient _sb;

  List<Fila> _l(dynamic r) =>
      (r as List? ?? const []).map((x) => Map<String, dynamic>.from(x as Map)).toList();

  // ── catálogo ──
  Future<List<Fila>> categorias() => _sb.from('bar_categorias').select()
      .eq('activo', true).order('orden', ascending: true);

  Future<void> crearCategoria(String nombre, int orden) =>
      _sb.from('bar_categorias').insert({'nombre': nombre, 'orden': orden});

  Future<List<Fila>> barras(String clubId) => _sb.from('barras').select()
      .eq('club_id', clubId).eq('activo', true).order('nombre', ascending: true);

  Future<void> crearBarra(String clubId, String nombre, int planta) =>
      _sb.from('barras').insert({'club_id': clubId, 'nombre': nombre, 'planta': planta});

  Future<List<Fila>> bebidas(String clubId) => _sb.from('bebidas')
      .select('*, c:bar_categorias(nombre)').eq('club_id', clubId).eq('activo', true)
      .order('nombre', ascending: true);

  Future<void> crearBebida(String clubId, {required String nombre, required int volumenMl,
      String? categoriaId, String unidad = 'botella', int? umbralBajo}) =>
      _sb.from('bebidas').insert({
        'club_id': clubId, 'categoria_id': categoriaId, 'nombre': nombre,
        'volumen_ml': volumenMl, 'unidad': unidad, 'umbral_bajo': umbralBajo,
      });

  // ── stock ──
  /// Stock por bebida: ml, botellas equivalentes, valor y si está bajo.
  Future<List<Fila>> stock(String clubId) => _sb.from('v_bar_stock').select()
      .eq('club_id', clubId).order('nombre', ascending: true);

  Future<List<Fila>> lotes(String bebidaId) => _sb.from('lotes').select()
      .eq('bebida_id', bebidaId).gt('ml_actual', 0).order('recibido_at', ascending: true);

  /// Ingresa mercadería. Devuelve botellas y ml recibidos.
  Future<Fila> recibir(String bebidaId, int cantidad,
          {String? codigo, num? costoUnitario, String? notas}) async =>
      Map<String, dynamic>.from(await _sb.rpc('bar_recibir_lote', params: {
        'p_bebida': bebidaId, 'p_cantidad': cantidad, 'p_codigo': codigo,
        'p_costo': costoUnitario, 'p_notas': notas,
      }) as Map);

  /// Lo que recibió la persona (para "Lo mío" del depósito).
  Future<List<Fila>> misRecepciones() => _sb.from('lotes')
      .select('codigo, cant_inicial, recibido_at, b:bebidas(nombre, volumen_ml)')
      .eq('recibido_por', _sb.auth.currentUser!.id)
      .order('recibido_at', ascending: false).limit(60);

  /// Ajuste por conteo físico de UN lote (ml que hay de verdad).
  Future<void> ajustar(String loteId, num mlFisico, {String? eventoId, String? motivo}) =>
      _sb.rpc('bar_ajuste_conteo', params: {
        'p_lote': loteId, 'p_ml_fisico': mlFisico, 'p_evento': eventoId, 'p_motivo': motivo,
      });

  /// Baja de mercadería (rotura, vencimiento…): queda como merma.
  Future<void> baja(String loteId, num ml, String motivo, {String? eventoId}) =>
      _sb.rpc('bar_baja', params: {
        'p_lote': loteId, 'p_ml': ml, 'p_motivo': motivo, 'p_evento': eventoId,
      });

  Future<List<Fila>> movimientos(String clubId) => _sb.from('v_bar_movimientos').select()
      .eq('club_id', clubId).order('created_at', ascending: false).limit(150);

  // ── conteo de la noche ──
  Future<List<Fila>> conteoPendiente(String eventoId, String momento) async => _l(await _sb
      .rpc('bar_conteo_pendiente', params: {'p_evento': eventoId, 'p_momento': momento}));

  /// Graba el conteo. [contado] trae SOLO los lotes que la persona tocó
  /// (lote → ml físicos).
  ///
  /// Lo que se manda es un conteo ABSOLUTO que la base aplica contra el saldo
  /// de ese instante. Por eso, justo antes de grabar se vuelve a leer el
  /// saldo: los lotes que nadie tocó van con ESE número y no con el de
  /// cuando se abrió la pantalla — si no, se revertiría todo lo que la barra
  /// vendió mientras se contaba.
  Future<Fila> grabarConteo(String eventoId, String momento, Map<String, num> contado) async {
    final fresco = await conteoPendiente(eventoId, momento);
    final lineas = [
      for (final f in fresco)
        {
          'lote_id': f['lote_id'],
          'ml_fisico': contado[f['lote_id']] ?? f['ml_sistema'],
        },
    ];
    final r = await _sb.rpc('bar_conteo_masivo',
        params: {'p_evento': eventoId, 'p_momento': momento, 'p_lineas': lineas});
    return r is Map ? Map<String, dynamic>.from(r) : <String, dynamic>{};
  }

  // ── punto de venta ──
  /// Barras donde puede vender la persona en el evento: el bartender, las
  /// que tiene asignadas en el turno; el propietario y el admin, todas.
  Future<List<Fila>> misBarras(String clubId, String eventoId, {required bool soloAsignadas}) async {
    final todas = await barras(clubId);
    if (!soloAsignadas) return todas;
    final st = await _sb.from('bar_staff').select('barra_id')
        .eq('evento_id', eventoId).eq('user_id', _sb.auth.currentUser!.id);
    final ids = {for (final x in st) x['barra_id']};
    return todas.where((b) => ids.contains(b['id'])).toList();
  }

  Future<List<TragoCarta>> carta(String clubId, String barraId) async => _l(await _sb
          .rpc('bar_disponibilidad', params: {'p_club': clubId, 'p_barra': barraId}))
      .map(TragoCarta.desde).toList();

  /// Parámetros de una venta. `p_client_key` identifica ESTA venta: si se
  /// reenvía (cola sin señal), la base devuelve la misma en vez de duplicar.
  static Fila argsDeVenta({required String eventoId, required String barraId,
      required List<Fila> items, String? cortesiaDe, String forma = 'efectivo',
      required String clave}) => {
        'p_evento': eventoId, 'p_barra': barraId, 'p_items': items,
        'p_cortesia_de': cortesiaDe,
        'p_forma_pago': cortesiaDe != null ? 'cortesia' : forma,
        'p_client_key': clave,
      };

  Future<Fila?> ultimaVentaMia(String eventoId) async {
    final r = await _sb.from('bar_ventas').select()
        .eq('evento_id', eventoId).eq('vendido_por', _sb.auth.currentUser!.id)
        .neq('estado', 'anulada').order('created_at', ascending: false).limit(1);
    return r.isEmpty ? null : r.first;
  }

  /// Anula una venta: devuelve el stock y queda auditada.
  Future<void> anular(String ventaId, String motivo) =>
      _sb.rpc('bar_anular_venta', params: {'p_venta': ventaId, 'p_motivo': motivo});

  /// Quiénes pueden recibir cortesías en el evento y cuánto cupo les queda.
  Future<List<Fila>> cortesias(String eventoId) async =>
      _l(await _sb.rpc('bar_cortesias_evento', params: {'p_evento': eventoId}));

  // ── carta y recetas (propietario) ──
  Future<List<Fila>> tragos(String clubId) => _sb.from('tragos')
      .select('*, r:receta_items(id, ml, bebida_id, b:bebidas(nombre, volumen_ml))')
      .eq('club_id', clubId).order('nombre', ascending: true);

  Future<void> crearTrago(String clubId, String nombre, num precio, {String? barraId}) =>
      _sb.from('tragos').insert({
        'club_id': clubId, 'nombre': nombre, 'precio_venta': precio, 'barra_id': barraId,
      });

  Future<void> editarTrago(String id, Fila campos) =>
      _sb.from('tragos').update(campos).eq('id', id);

  Future<void> agregarAReceta(String tragoId, String bebidaId, num ml) => _sb
      .from('receta_items').insert({'trago_id': tragoId, 'bebida_id': bebidaId, 'ml': ml});

  Future<void> quitarDeReceta(String itemId) =>
      _sb.from('receta_items').delete().eq('id', itemId);

  // ── turno y cortesías ──
  Future<Set<String>> turno(String eventoId) async {
    final r = await _sb.from('bar_staff').select('barra_id, user_id').eq('evento_id', eventoId);
    return {for (final x in r) '${x['barra_id']}|${x['user_id']}'};
  }

  Future<void> asignar(String eventoId, String barraId, String usuarioId, bool asignado) =>
      asignado
          ? _sb.from('bar_staff').upsert(
              {'evento_id': eventoId, 'barra_id': barraId, 'user_id': usuarioId})
          : _sb.from('bar_staff').delete().eq('evento_id', eventoId)
              .eq('barra_id', barraId).eq('user_id', usuarioId);

  Future<List<Fila>> bartenders(String clubId) => _sb.from('profiles')
      .select('id, nombre, usuario').eq('rol', 'barra').eq('activo', true)
      .contains('clubs', [clubId]).order('nombre', ascending: true);

  Future<int> cupoCortesia(String clubId) async =>
      ((await _sb.from('bar_cortesia_config').select('cupo_default')
              .eq('club_id', clubId).maybeSingle())?['cupo_default'] as num?)?.toInt() ?? 0;

  Future<void> fijarCupoCortesia(String clubId, int cupo) =>
      _sb.from('bar_cortesia_config').upsert({
        'club_id': clubId, 'cupo_default': cupo,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      });

  // ── cierre y analítica ──
  Future<List<Fila>> cierre(String eventoId) =>
      _sb.from('v_bar_cierre').select().eq('evento_id', eventoId);

  Future<({Fila? evento, List<Fila> porBarra, Fila? margen, List<Fila> merma, List<Fila> top})>
      analitica(String eventoId) async {
    final r = await Future.wait<dynamic>([
      _sb.from('v_bar_evento').select().eq('evento_id', eventoId).maybeSingle(),
      _sb.from('v_bar_por_barra').select().eq('evento_id', eventoId)
          .order('ingresos', ascending: false),
      _sb.from('v_bar_margen').select().eq('evento_id', eventoId).maybeSingle(),
      _sb.from('v_bar_merma').select().eq('evento_id', eventoId)
          .not('merma_bs', 'is', null).order('merma_bs', ascending: false).limit(8),
      _sb.from('v_bar_top_trago').select().eq('evento_id', eventoId)
          .lte('puesto_evento', 5).order('puesto_evento', ascending: true),
    ]);
    return (
      evento: r[0] as Fila?, porBarra: _l(r[1]), margen: r[2] as Fila?,
      merma: _l(r[3]), top: _l(r[4]),
    );
  }

  Future<List<Fila>> proyeccion(String clubId, int asistentes) async => _l(await _sb.rpc(
      'bar_proyeccion_compra', params: {'p_club': clubId, 'p_asistentes': asistentes}));
}

final stockProvider = FutureProvider.autoDispose<List<Fila>>((ref) async {
  final club = ref.watch(clubActivoIdProvider);
  if (club == null) return const [];
  return ref.watch(barraRepositoryProvider).stock(club);
});

/// Vende tolerando cortes de señal. Si no hay red la venta queda en la cola y
/// se reenvía sola con la MISMA clave: no se duplica.
Future<({bool encolada, Fila? venta})> venderTolerante(WidgetRef ref, Fila args, String etiqueta) async {
  final r = await ref.read(pendientesProvider.notifier).ejecutar('bar_vender', args, etiqueta);
  return (
    encolada: r.encolada,
    venta: r.dato is Map ? Map<String, dynamic>.from(r.dato as Map) : null,
  );
}

/// ¿Hay evento abierto para vender? Lo comparten las pantallas de barra.
final eventoDeBarraProvider = Provider<Evento?>((ref) => ref.watch(eventoActivoProvider));
