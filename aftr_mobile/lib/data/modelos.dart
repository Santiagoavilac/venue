import 'dart:ui' show Color;

/// Lo que devuelven las RPC aftr_* (db/35-aftr.sql), ya tipado.

Map<String, dynamic> _m(Object? v) => v is Map ? Map<String, dynamic>.from(v) : const {};
List<Map<String, dynamic>> _l(Object? v) =>
    v is List ? [for (final x in v) if (x is Map) Map<String, dynamic>.from(x)] : const [];
List<String> _ls(Object? v) => v is List ? [for (final x in v) if (x != null) '$x'] : const [];
int? _i(Object? v) => v is num ? v.round() : (v is String ? num.tryParse(v)?.round() : null);
double? _d(Object? v) => v is num ? v.toDouble() : (v is String ? double.tryParse(v) : null);
DateTime? _f(Object? v) => v is String ? DateTime.tryParse(v)?.toLocal() : null;

/// "#7C3AED" -> Color; null si no se entiende.
Color? colorDe(String? hex) {
  final h = (hex ?? '').replaceFirst('#', '');
  if (h.length != 6) return null;
  final n = int.tryParse(h, radix: 16);
  return n == null ? null : Color(0xFF000000 | n);
}

class ClubMini {
  const ClubMini({required this.id, required this.nombre, this.logo, this.zona, this.ciudad, this.lat, this.lng, this.color});

  final String id;
  final String nombre;
  final String? logo;
  final String? zona;
  final String? ciudad;
  final double? lat;
  final double? lng;
  final Color? color;

  bool get ubicado => lat != null && lng != null;

  factory ClubMini.desde(Map<String, dynamic> j) => ClubMini(
        id: '${j['id']}',
        nombre: j['nombre'] as String? ?? '',
        logo: j['logo'] as String?,
        zona: j['zona'] as String?,
        ciudad: j['ciudad'] as String?,
        lat: _d(j['lat']),
        lng: _d(j['lng']),
        color: colorDe(j['color'] as String?),
      );
}

class Evento {
  const Evento({
    required this.id,
    required this.nombre,
    required this.fecha,
    required this.inicio,
    required this.horaInicio,
    required this.horaFin,
    required this.club,
    this.edadMin = 18,
    this.flyer,
    this.descripcion,
    this.generos = const [],
    this.desdePrecio,
    this.tieneLista = false,
    this.mesasLibres = 0,
  });

  final String id;
  final String nombre;
  final DateTime fecha;
  final DateTime inicio;
  final String horaInicio;
  final String horaFin;
  final ClubMini club;
  final int edadMin;
  final String? flyer;
  final String? descripcion;
  final List<String> generos;
  final int? desdePrecio;
  final bool tieneLista;
  final int mesasLibres;

  /// Ya empezó o empieza en menos de 3 horas.
  bool esAhora(DateTime ahora) => inicio.difference(ahora).inMinutes < 180;

  factory Evento.desde(Map<String, dynamic> j) {
    final fecha = DateTime.tryParse('${j['fecha']}') ?? DateTime.now();
    return Evento(
      id: '${j['id']}',
      nombre: j['nombre'] as String? ?? '',
      fecha: DateTime(fecha.year, fecha.month, fecha.day),
      inicio: _f(j['inicio']) ?? fecha,
      horaInicio: j['hora_inicio'] as String? ?? '',
      horaFin: j['hora_fin'] as String? ?? '',
      club: ClubMini.desde(_m(j['club'])),
      edadMin: _i(j['edad_min']) ?? 18,
      flyer: j['flyer'] as String?,
      descripcion: j['descripcion'] as String?,
      generos: _ls(j['generos']),
      desdePrecio: _i(j['desde_precio']),
      tieneLista: j['tiene_lista'] == true,
      mesasLibres: _i(j['mesas_libres']) ?? 0,
    );
  }
}

enum EstadoFase { abierta, proxima, agotada, cerrada }

class Fase {
  const Fase({required this.id, required this.nombre, required this.precio, required this.estado, this.quedan});

  final String id;
  final String nombre;
  final int precio;
  final EstadoFase estado;
  final int? quedan;

  bool get comprable => estado == EstadoFase.abierta;

  factory Fase.desde(Map<String, dynamic> j) => Fase(
        id: '${j['id']}',
        nombre: j['nombre'] as String? ?? '',
        precio: _i(j['precio']) ?? 0,
        estado: EstadoFase.values.firstWhere((e) => e.name == j['estado'], orElse: () => EstadoFase.cerrada),
        quedan: _i(j['quedan']),
      );
}

class Lista {
  const Lista({required this.id, required this.nombre, this.precio, this.hasta, this.abierta = false});

  final String id;
  final String nombre;
  final int? precio;
  final String? hasta;
  final bool abierta;

  factory Lista.desde(Map<String, dynamic> j) => Lista(
        id: '${j['id']}',
        nombre: j['nombre'] as String? ?? '',
        precio: _i(j['precio']),
        hasta: j['hasta'] as String?,
        abierta: j['abierta'] == true,
      );
}

class Mesa {
  const Mesa({required this.id, required this.etiqueta, required this.categoria, this.planta});

  final String id;
  final String etiqueta;
  final String categoria;
  final String? planta;

  factory Mesa.desde(Map<String, dynamic> j) => Mesa(
        id: '${j['id']}',
        etiqueta: j['etiqueta'] as String? ?? '',
        categoria: j['categoria'] as String? ?? '',
        planta: j['planta'] as String?,
      );
}

class Combo {
  const Combo({required this.id, required this.nombre, required this.precio, this.descripcion, this.productos = const [], this.manillas = 0, this.categorias = const []});

  final String id;
  final String nombre;
  final int precio;
  final String? descripcion;
  final List<String> productos;
  final int manillas;
  final List<String> categorias;

  bool sirvePara(Mesa m) => categorias.isEmpty || categorias.contains(m.categoria);

  factory Combo.desde(Map<String, dynamic> j) => Combo(
        id: '${j['id']}',
        nombre: j['nombre'] as String? ?? '',
        precio: _i(j['precio']) ?? 0,
        descripcion: j['descripcion'] as String?,
        productos: _ls(j['productos']),
        manillas: _i(j['manillas']) ?? 0,
        categorias: _ls(j['categorias']),
      );
}

class EventoDetalle {
  const EventoDetalle({
    required this.evento,
    this.ventaPorFases = false,
    this.precio = 0,
    this.ventaAbierta = false,
    this.fases = const [],
    this.listas = const [],
    this.mesas = const [],
    this.combos = const [],
    this.comboObligatorio = false,
    this.guardado = false,
  });

  final Evento evento;
  final bool ventaPorFases;
  final int precio;
  final bool ventaAbierta;
  final List<Fase> fases;
  final List<Lista> listas;
  final List<Mesa> mesas;
  final List<Combo> combos;
  final bool comboObligatorio;
  final bool guardado;

  /// La fase que se compra ahora (la primera abierta).
  Fase? get faseActual => fases.where((f) => f.comprable).firstOrNull;

  bool get seVende => ventaPorFases ? faseActual != null : ventaAbierta;

  int get precioActual => ventaPorFases ? (faseActual?.precio ?? 0) : precio;

  factory EventoDetalle.desde(Map<String, dynamic> j) => EventoDetalle(
        evento: Evento.desde(j),
        ventaPorFases: j['venta_por_fases'] == true,
        precio: _i(j['precio']) ?? 0,
        ventaAbierta: j['venta_abierta'] == true,
        fases: [for (final f in _l(j['fases'])) Fase.desde(f)],
        listas: [for (final l in _l(j['listas'])) Lista.desde(l)],
        mesas: [for (final m in _l(j['mesas'])) Mesa.desde(m)],
        combos: [for (final c in _l(j['combos'])) Combo.desde(c)],
        comboObligatorio: j['combo_obligatorio'] == true,
        guardado: j['guardado'] == true,
      );
}

class Lugar {
  const Lugar({
    required this.id,
    required this.nombre,
    this.subtitulo,
    this.logo,
    this.fotos = const [],
    this.zona,
    this.ciudad,
    this.direccion,
    this.descripcion,
    this.lat,
    this.lng,
    this.color,
    this.siguiendo = false,
    this.proximo,
    this.eventos = const [],
  });

  final String id;
  final String nombre;
  final String? subtitulo;
  final String? logo;
  final List<String> fotos;
  final String? zona;
  final String? ciudad;
  final String? direccion;
  final String? descripcion;
  final double? lat;
  final double? lng;
  final Color? color;
  final bool siguiendo;
  final Evento? proximo;
  final List<Evento> eventos;

  bool get ubicado => lat != null && lng != null;
  String? get portada => fotos.isNotEmpty ? fotos.first : (proximo?.flyer ?? logo);

  factory Lugar.desde(Map<String, dynamic> j) => Lugar(
        id: '${j['id']}',
        nombre: j['nombre'] as String? ?? '',
        subtitulo: j['subtitulo'] as String?,
        logo: j['logo'] as String?,
        fotos: _ls(j['fotos']),
        zona: j['zona'] as String?,
        ciudad: j['ciudad'] as String?,
        direccion: j['direccion'] as String?,
        descripcion: j['descripcion'] as String?,
        lat: _d(j['lat']),
        lng: _d(j['lng']),
        color: colorDe(j['color'] as String?),
        siguiendo: j['siguiendo'] == true,
        proximo: j['proximo'] is Map ? Evento.desde(_m(j['proximo'])) : null,
        eventos: [for (final e in _l(j['eventos'])) Evento.desde(e)],
      );
}

class Cliente {
  const Cliente({required this.id, required this.usuario, required this.nombre, this.foto});

  final String id;
  final String usuario;
  final String nombre;
  final String? foto;

  factory Cliente.desde(Map<String, dynamic> j) => Cliente(
        id: '${j['user_id'] ?? ''}',
        usuario: j['usuario'] as String? ?? '',
        nombre: j['nombre'] as String? ?? '',
        foto: (j['foto_url'] ?? j['foto']) as String?,
      );
}

enum TipoAcceso { entrada, lista, mesa, pedido }

enum EstadoAcceso { pendiente, valida, usada, anulada }

/// Una tarjeta de la billetera: entrada, lugar en lista, mesa o pedido
/// esperando que el boliche lo confirme.
class Acceso {
  const Acceso({
    required this.id,
    required this.tipo,
    required this.estado,
    required this.evento,
    required this.titulo,
    this.detalle,
    this.qr,
    this.code,
    this.transferible = false,
    this.total,
  });

  final String id;
  final TipoAcceso tipo;
  final EstadoAcceso estado;
  final Evento evento;
  final String titulo;
  final String? detalle;
  final String? qr;
  final String? code;
  final bool transferible;
  final int? total;

  bool get tieneQr => qr != null && estado == EstadoAcceso.valida;

  static EstadoAcceso _estado(Object? v) => switch (v) {
        'valida' => EstadoAcceso.valida,
        'usada' => EstadoAcceso.usada,
        'anulada' => EstadoAcceso.anulada,
        _ => EstadoAcceso.pendiente,
      };
}

class Accesos {
  const Accesos(this.todos);

  final List<Acceso> todos;

  /// Lo que todavía sirve: pedidos pendientes y QR válidos de eventos que no
  /// terminaron, el más cercano primero.
  List<Acceso> proximos(DateTime ahora) => todos
      .where((a) =>
          (a.estado == EstadoAcceso.valida || a.estado == EstadoAcceso.pendiente) &&
          !a.evento.fecha.isBefore(DateTime(ahora.year, ahora.month, ahora.day).subtract(const Duration(days: 1))))
      .toList()
    ..sort((a, b) => a.evento.inicio.compareTo(b.evento.inicio));

  List<Acceso> pasados(DateTime ahora) {
    final p = proximos(ahora).toSet();
    return todos.where((a) => !p.contains(a)).toList()..sort((a, b) => b.evento.inicio.compareTo(a.evento.inicio));
  }

  factory Accesos.desde(Map<String, dynamic> j) {
    final out = <Acceso>[];
    for (final x in _l(j['ordenes'])) {
      final mesa = x['tipo'] == 'mesa';
      final n = _i(x['cantidad']) ?? 1;
      out.add(Acceso(
        id: '${x['id']}',
        tipo: TipoAcceso.pedido,
        estado: EstadoAcceso.pendiente,
        evento: Evento.desde(_m(x['evento'])),
        titulo: mesa ? 'Mesa ${x['mesa'] ?? ''}'.trim() : (n == 1 ? '1 entrada' : '$n entradas'),
        detalle: mesa ? 'Reserva esperando confirmación' : (x['fase'] as String? ?? 'Esperando confirmación'),
        total: _i(x['total']),
      ));
    }
    for (final x in _l(j['entradas'])) {
      final mesa = x['mesa'] as String?;
      out.add(Acceso(
        id: '${x['id']}',
        tipo: TipoAcceso.entrada,
        estado: Acceso._estado(x['estado']),
        evento: Evento.desde(_m(x['evento'])),
        titulo: mesa != null ? 'Manilla · Mesa $mesa' : 'Entrada',
        detalle: x['fase'] as String?,
        qr: x['qr'] as String?,
        code: x['code'] as String?,
        transferible: x['transferible'] == true,
      ));
    }
    for (final x in _l(j['listas'])) {
      final hasta = x['hasta'] as String?;
      out.add(Acceso(
        id: '${x['id']}',
        tipo: TipoAcceso.lista,
        estado: Acceso._estado(x['estado']),
        evento: Evento.desde(_m(x['evento'])),
        titulo: x['lista'] as String? ?? 'Lista',
        detalle: hasta != null ? 'Entrás hasta las $hasta' : null,
        qr: x['qr'] as String?,
        code: x['code'] as String?,
      ));
    }
    for (final x in _l(j['mesas'])) {
      final estado = x['estado'];
      out.add(Acceso(
        id: '${x['id']}',
        tipo: TipoAcceso.mesa,
        estado: estado == 'reservada' ? EstadoAcceso.pendiente : (estado == 'disponible' ? EstadoAcceso.anulada : EstadoAcceso.valida),
        evento: Evento.desde(_m(x['evento'])),
        titulo: 'Mesa ${x['etiqueta'] ?? ''}'.trim(),
        detalle: [x['categoria'], x['combo']].whereType<String>().where((s) => s.isNotEmpty).join(' · '),
        total: _i(x['precio']),
      ));
    }
    // la mesa confirmada ya aparece como sus manillas; la reserva pendiente,
    // como pedido: no se repite
    out.removeWhere((a) => a.tipo == TipoAcceso.mesa && a.estado == EstadoAcceso.pendiente);
    return Accesos(out);
  }
}
