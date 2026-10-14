import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/networking/supabase.dart';
import '../../clubs/data/clubs.dart';
import '../../events/data/eventos.dart';

const ordenPisos = ['piso1', 'piso2', 'piso3', 'alta', 'baja'];
const etiquetaPiso = {
  'piso1': 'Piso 1', 'piso2': 'Piso 2', 'piso3': 'Piso 3',
  'alta': 'Planta alta', 'baja': 'Planta baja',
};
const etiquetaEstado = {
  'disponible': 'Libre', 'reservada': 'Reservada', 'pagada': 'Pagada', 'ocupada': 'Ocupada',
};

/// Pisos que tienen mesas, en orden. Sin mesas: planta alta y baja.
List<String> pisosDe(Iterable<Mesa> mesas) {
  final hay = mesas.map((m) => m.planta).toSet();
  final p = ordenPisos.where(hay.contains).toList();
  return p.isEmpty ? ['alta', 'baja'] : p;
}

class Mesa {
  const Mesa({
    required this.id,
    required this.eventoId,
    required this.planta,
    required this.etiqueta,
    required this.categoria,
    required this.x,
    required this.y,
    required this.w,
    this.h,
    required this.estado,
    this.cliente,
    this.comboId,
    this.comboQty = 1,
    this.botellas = const [],
    this.manillas = 0,
    this.precio = 0,
    this.vendidoPor,
    this.teamId,
    this.grupoId,
    this.reservadaAt,
    this.reservaVenceAt,
    this.comprobanteUrl,
    this.pagoVerificado = false,
    this.metodoPago,
    this.cortesia = false,
  });

  final String id;
  final String eventoId;
  final String planta;
  final String etiqueta;

  /// mesa | lounge
  final String categoria;

  /// Posición y tamaño en PORCENTAJE del plano (igual que la web).
  final double x, y, w;
  final double? h;
  final String estado;
  final String? cliente;
  final String? comboId;
  final int comboQty;
  final List<String> botellas;
  final int manillas;
  final num precio;
  final String? vendidoPor;
  final String? teamId;
  final String? grupoId;
  final DateTime? reservadaAt;
  final DateTime? reservaVenceAt;
  final String? comprobanteUrl;
  final bool pagoVerificado;
  final String? metodoPago;
  final bool cortesia;

  bool get libre => estado == 'disponible';
  bool get esLounge => categoria == 'lounge';
  bool get porVerificar => estado == 'pagada' && !pagoVerificado && precio > 0;

  /// Cuándo vence la reserva. El vencimiento viaja en la mesa; el respaldo
  /// usa las horas de reserva del evento.
  DateTime? vence(int horasReserva) =>
      reservaVenceAt ?? reservadaAt?.add(Duration(hours: horasReserva));

  Mesa en(double nx, double ny) => Mesa(
        id: id, eventoId: eventoId, planta: planta, etiqueta: etiqueta,
        categoria: categoria, x: nx, y: ny, w: w, h: h, estado: estado,
        cliente: cliente, comboId: comboId, comboQty: comboQty, botellas: botellas,
        manillas: manillas, precio: precio, vendidoPor: vendidoPor, teamId: teamId,
        grupoId: grupoId, reservadaAt: reservadaAt, reservaVenceAt: reservaVenceAt,
        comprobanteUrl: comprobanteUrl, pagoVerificado: pagoVerificado,
        metodoPago: metodoPago, cortesia: cortesia,
      );

  factory Mesa.desde(Map<String, dynamic> j) {
    DateTime? f(String k) => DateTime.tryParse(j[k] as String? ?? '')?.toLocal();
    return Mesa(
      id: j['id'] as String,
      eventoId: j['evento_id'] as String,
      planta: j['planta'] as String? ?? 'alta',
      etiqueta: j['etiqueta'] as String? ?? '',
      categoria: j['categoria'] as String? ?? 'mesa',
      x: (j['x'] as num?)?.toDouble() ?? 0,
      y: (j['y'] as num?)?.toDouble() ?? 0,
      w: (j['w'] as num?)?.toDouble() ?? 14,
      h: (j['h'] as num?)?.toDouble(),
      estado: j['estado'] as String? ?? 'disponible',
      cliente: j['cliente'] as String?,
      comboId: j['combo_id'] as String?,
      comboQty: (j['combo_qty'] as num?)?.toInt() ?? 1,
      botellas: ((j['botellas'] as List?) ?? const []).cast<String>(),
      manillas: (j['manillas'] as num?)?.toInt() ?? 0,
      precio: j['precio'] as num? ?? 0,
      vendidoPor: j['vendido_por'] as String?,
      teamId: j['team_id'] as String?,
      grupoId: j['grupo_id'] as String?,
      reservadaAt: f('reservada_at'),
      reservaVenceAt: f('reserva_vence_at'),
      comprobanteUrl: j['comprobante_url'] as String?,
      pagoVerificado: j['pago_verificado'] == true,
      metodoPago: j['metodo_pago'] as String?,
      cortesia: j['cortesia'] == true,
    );
  }
}

/// Límites del arrastre en el editor, iguales a los de la web: la mesa no
/// sale del plano y se ajusta a medios puntos.
({double x, double y}) acotarPosicion(double x, double y, double w) => (
      x: (x.clamp(0.5, 99 - w) * 2).round() / 2,
      y: (y.clamp(0.5, 86.0) * 2).round() / 2,
    );

class Combo {
  const Combo({
    required this.id,
    required this.nombre,
    required this.precio,
    this.descripcion,
    this.productos = const [],
    this.comisionRrpp = 0,
    this.comisionJefe = 0,
    this.incluyeManillas = 0,
    this.activo = true,
    this.categorias = const [],
  });
  final String id;
  final String nombre;
  final num precio;
  final String? descripcion;
  final List<String> productos;
  final num comisionRrpp;
  final num comisionJefe;
  final int incluyeManillas;
  final bool activo;

  /// Tipos de mesa donde se puede vender. Vacío = todos.
  final List<String> categorias;

  /// ¿Sirve para vender estas mesas juntas? Tiene que estar habilitado para
  /// TODOS los tipos del grupo.
  bool valePara(Iterable<String> cats) =>
      categorias.isEmpty || cats.every(categorias.contains);

  factory Combo.desde(Map<String, dynamic> j) => Combo(
        id: j['id'] as String,
        nombre: j['nombre'] as String? ?? '',
        precio: j['precio'] as num? ?? 0,
        descripcion: j['descripcion'] as String?,
        productos: ((j['productos'] as List?) ?? const []).cast<String>(),
        comisionRrpp: j['comision_rrpp'] as num? ?? 0,
        comisionJefe: j['comision_jefe'] as num? ?? 0,
        incluyeManillas: (j['incluye_manillas'] as num?)?.toInt() ?? 0,
        activo: j['activo'] != false,
        categorias: ((j['categorias'] as List?) ?? const []).cast<String>(),
      );

  Map<String, dynamic> aJson(String clubId) => {
        'club_id': clubId, 'nombre': nombre, 'precio': precio,
        'descripcion': descripcion, 'productos': productos,
        'comision_rrpp': comisionRrpp, 'comision_jefe': comisionJefe,
        'incluye_manillas': incluyeManillas, 'activo': activo, 'categorias': categorias,
      };
}

/// Registro de combos en texto, para pegar en WhatsApp (port de
/// `copyRegistroMesas`): precio NETO, ya sin las comisiones.
String registroDeCombos(String evento, String fecha, List<Mesa> vendidas,
    Map<String, Combo> combos) {
  String bs(num n) => n == n.roundToDouble() ? n.toInt().toString() : n.toStringAsFixed(2);
  num neto(Mesa m) {
    final c = combos[m.comboId];
    final com = (c?.comisionRrpp ?? 0) + (c?.comisionJefe ?? 0);
    final v = m.precio - com * m.comboQty;
    return v < 0 ? 0 : v;
  }

  final orden = [...vendidas]..sort((a, b) => a.etiqueta.compareTo(b.etiqueta));
  num total = 0;
  final lineas = <String>[];
  final grupos = <String, ({int n, num sub})>{};
  for (var i = 0; i < orden.length; i++) {
    final m = orden[i];
    final nom = combos[m.comboId]?.nombre ?? 'Combo';
    final p = neto(m);
    total += p;
    lineas.add('${(i + 1).toString().padLeft(2)}. ${m.cliente ?? m.etiqueta} - ${m.comboQty} $nom — ${bs(p)} Bs');
    final g = grupos[nom] ?? (n: 0, sub: 0);
    grupos[nom] = (n: g.n + m.comboQty, sub: g.sub + p);
  }
  final desglose = (grupos.entries.toList()..sort((a, b) => b.value.sub.compareTo(a.value.sub)))
      .map((e) =>
          '•  ${e.value.n} ${e.key} × ${bs(e.value.n == 0 ? 0 : e.value.sub / e.value.n)} Bs = ${bs(e.value.sub)} Bs')
      .join('\n');
  return 'Combos $evento · $fecha\n(precios ya con la comisión descontada)\n\n'
      '${lineas.join('\n')}\n\nTotal: ${bs(total)} Bs\n\nDesglose:\n$desglose';
}

class DatosVenta {
  const DatosVenta({
    required this.cliente,
    required this.comboId,
    required this.estado,
    this.cantidad = 1,
    this.botellas = const [],
    this.manillasExtra = 0,
    this.comprobante,
    this.efectivo = false,
    this.aNombreDe,
    this.cortesia = false,
  });
  final String cliente;
  final String? comboId;

  /// reservada | pagada
  final String estado;
  final int cantidad;
  final List<String> botellas;
  final int manillasExtra;
  final String? comprobante;
  final bool efectivo;
  final String? aNombreDe;
  final bool cortesia;

  Map<String, dynamic> _params() => {
        'p_cliente': cliente, 'p_combo': comboId, 'p_botellas': botellas,
        'p_manillas': manillasExtra, 'p_estado': estado, 'p_cantidad': cantidad,
        'p_comprobante': comprobante, 'p_efectivo': efectivo,
        'p_a_nombre_de': aNombreDe, 'p_cortesia': cortesia,
      };
}

final mesasRepositoryProvider =
    Provider<MesasRepository>((ref) => MesasRepository(ref.watch(supabaseProvider)));

class MesasRepository {
  MesasRepository(this._sb);
  final SupabaseClient _sb;

  /// Libera las reservas vencidas y devuelve las etiquetas de las que eran
  /// de la persona (para avisarle). Si falla, el plano carga igual.
  Future<List<String>> barrerVencidas(String eventoId) async {
    try {
      final r = await _sb.rpc('liberar_reservas_vencidas', params: {'p_evento': eventoId});
      final uid = _sb.auth.currentUser?.id;
      return [
        for (final x in ((r as Map?)?['liberadas'] as List? ?? const []))
          if (x['vendido_por'] == uid) x['etiqueta'] as String,
      ];
    } catch (_) {
      return const [];
    }
  }

  Future<List<Mesa>> mesas(String eventoId) async {
    final r = await _sb.from('mesas').select().eq('evento_id', eventoId).order('etiqueta', ascending: true);
    return r.map(Mesa.desde).toList();
  }

  Future<List<Mesa>> grupo(String grupoId) async {
    final r = await _sb.from('mesas').select().eq('grupo_id', grupoId).order('etiqueta', ascending: true);
    return r.map(Mesa.desde).toList();
  }

  Future<List<Combo>> combos(String clubId) async {
    final r = await _sb.from('combos').select().eq('club_id', clubId).order('nombre', ascending: true);
    return r.map(Combo.desde).toList();
  }

  /// Fondo del plano por planta.
  Future<Map<String, String>> fondos(String clubId) async {
    final r = await _sb.from('plano_fondos').select('planta, url').eq('club_id', clubId);
    return {for (final x in r) x['planta'] as String: x['url'] as String};
  }

  /// Teams que operan en el boliche (para asignarle una mesa a un team).
  Future<Map<String, String>> teams(String clubId) async {
    final r = await _sb.from('teams').select('id, nombre, clubs').eq('activo', true);
    return {
      for (final x in r)
        if (x['clubs'] == null || (x['clubs'] as List).contains(clubId))
          x['id'] as String: x['nombre'] as String,
    };
  }

  /// QR de cobro vigente del boliche (el primero activo), o null.
  Future<({String nombre, String url})?> qrCobro(String clubId) async {
    final r = await _sb
        .from('qr_cobro')
        .select('nombre, url')
        .eq('club_id', clubId)
        .eq('activo', true)
        .order('orden', ascending: true)
        .limit(1);
    if (r.isEmpty) return null;
    return (nombre: r.first['nombre'] as String? ?? '', url: r.first['url'] as String);
  }

  /// Vende o reserva. Con varias mesas las une en un grupo. Devuelve la mesa
  /// primaria (la que lleva el combo y las manillas), la etiqueta y el precio.
  Future<({String primaria, String etiqueta, num precio})> vender(
      List<String> mesaIds, DatosVenta d) async {
    if (mesaIds.length > 1) {
      final r = Map<String, dynamic>.from(await _sb.rpc('vender_mesa_grupo',
          params: {'p_mesas': mesaIds, ...d._params()}) as Map);
      return (
        primaria: r['primaria'] as String,
        etiqueta: ((r['mesas'] as List?) ?? const []).join(' + '),
        precio: r['precio'] as num? ?? 0,
      );
    }
    final r = Map<String, dynamic>.from(await _sb
        .rpc('vender_mesa', params: {'p_mesa': mesaIds.single, ...d._params()}) as Map);
    return (
      primaria: mesaIds.single,
      etiqueta: r['etiqueta'] as String? ?? '',
      precio: r['precio'] as num? ?? 0,
    );
  }

  Future<void> editarVenta(String mesaId, String cliente, String? comboId) => _sb.rpc(
      'editar_mesa',
      params: {'p_mesa': mesaId, 'p_cliente': cliente, 'p_combo': comboId});

  /// Marca la mesa como pagada. Queda "por verificar" hasta que el admin
  /// confirme que la plata entró (salvo que la cobre el propio admin).
  Future<void> pagar(String mesaId, {String? comprobante, bool efectivo = false}) =>
      _sb.rpc('pagar_mesa',
          params: {'p_mesa': mesaId, 'p_url': comprobante, 'p_efectivo': efectivo});

  /// ocupada | disponible (liberar: borra la venta de la mesa o del grupo)
  Future<void> estado(String mesaId, String estado) =>
      _sb.rpc('estado_mesa', params: {'p_mesa': mesaId, 'p_estado': estado});

  /// Admin: confirma que el pago entró, o lo rechaza (vuelve a reservada).
  Future<void> verificar(String mesaId, bool ok) =>
      _sb.rpc('verificar_mesa', params: {'p_mesa': mesaId, 'p_ok': ok});

  // ── editor de plano (admin) ───────────────────────────────────────
  Future<void> crear(String eventoId, String planta, String categoria, int n) =>
      _sb.from('mesas').insert({
        'evento_id': eventoId, 'planta': planta, 'etiqueta': 'M$n',
        'categoria': categoria, 'x': 42, 'y': 45, 'w': categoria == 'lounge' ? 18 : 14,
        'estado': 'disponible', 'botellas': <String>[], 'manillas': 0, 'combo_qty': 1,
        'pago_verificado': false, 'cortesia': false,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      });

  Future<void> mover(String mesaId, double x, double y) =>
      _sb.from('mesas').update({'x': x, 'y': y}).eq('id', mesaId);

  Future<void> editarForma(String mesaId,
          {required String etiqueta, required String categoria, required int w,
          int? h, String? teamId, required String planta}) =>
      _sb.from('mesas').update({
        'etiqueta': etiqueta, 'categoria': categoria, 'w': w, 'h': h,
        'team_id': teamId, 'planta': planta,
      }).eq('id', mesaId);

  Future<void> borrar(String mesaId) => _sb.from('mesas').delete().eq('id', mesaId);

  Future<void> guardarFondo(String clubId, String planta, String url) => _sb
      .from('plano_fondos')
      .upsert({'club_id': clubId, 'planta': planta, 'url': url,
        'updated_at': DateTime.now().toUtc().toIso8601String()});

  /// Trae al evento el plano del evento anterior del boliche.
  Future<void> heredar(String eventoId) =>
      _sb.rpc('heredar_mesas', params: {'p_hacia': eventoId});

  Future<void> copiar(String desde, String hacia) =>
      _sb.rpc('copiar_mesas', params: {'p_desde': desde, 'p_hacia': hacia});

  Future<void> guardarCombo(String clubId, Combo c, {bool nuevo = false}) => nuevo
      ? _sb.from('combos').insert(c.aJson(clubId))
      : _sb.from('combos').update(c.aJson(clubId)).eq('id', c.id);

  Future<void> borrarCombo(String id) => _sb.from('combos').delete().eq('id', id);
}

/// Mesas del evento activo (antes barre las reservas vencidas).
final mesasProvider = FutureProvider.autoDispose<List<Mesa>>((ref) async {
  final ev = ref.watch(eventoActivoProvider);
  if (ev == null) return const [];
  return ref.watch(mesasRepositoryProvider).mesas(ev.id);
});

final combosProvider = FutureProvider.autoDispose<List<Combo>>((ref) async {
  final club = ref.watch(clubActivoIdProvider);
  if (club == null) return const [];
  return ref.watch(mesasRepositoryProvider).combos(club);
});

final fondosProvider = FutureProvider.autoDispose<Map<String, String>>((ref) async {
  final club = ref.watch(clubActivoIdProvider);
  if (club == null) return const {};
  return ref.watch(mesasRepositoryProvider).fondos(club);
});

final teamsClubProvider = FutureProvider.autoDispose<Map<String, String>>((ref) async {
  final club = ref.watch(clubActivoIdProvider);
  if (club == null) return const {};
  return ref.watch(mesasRepositoryProvider).teams(club);
});
