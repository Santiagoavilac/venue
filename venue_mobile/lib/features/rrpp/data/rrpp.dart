import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/networking/supabase.dart';
import '../../authentication/data/sesion.dart';

/// Espacio del relacionador: sus boliches, sus solicitudes para sumarse a
/// otros y sus números de todos los eventos. Todo sale de las RPC de
/// db/41-relacionadores.sql, que filtran por quien pregunta.

num _n(Object? v) => v is num ? v : num.tryParse('$v') ?? 0;
int _i(Object? v) => _n(v).toInt();
DateTime _f(Object? v) => DateTime.parse(v as String);

/// Lo que hizo la persona en un evento (rrpp_eventos).
class EventoRrpp {
  const EventoRrpp({
    required this.eventoId, required this.clubId, required this.club, this.logoUrl,
    required this.evento, required this.fecha, required this.estado,
    this.anotados = 0, this.ingresaron = 0, this.entradasVendidas = 0, this.entradasUsadas = 0,
    this.mesasConfirmadas = 0, this.mesasReservadas = 0,
    this.brutoEntradas = 0, this.brutoMesas = 0,
    this.comisionEntradas = 0, this.comisionMesas = 0, this.comisionJefe = 0, this.bono = 0,
    this.comisionTotal = 0, this.porManilla = 0, this.estadoComision = 'estimada', this.pagadoAt,
  });
  final String eventoId, clubId, club, evento, estado, estadoComision;
  final String? logoUrl;
  final DateTime fecha;
  final DateTime? pagadoAt;
  final int anotados, ingresaron, entradasVendidas, entradasUsadas, mesasConfirmadas, mesasReservadas;
  final num brutoEntradas, brutoMesas, comisionEntradas, comisionMesas, comisionJefe, bono,
      comisionTotal, porManilla;

  /// Personas que entraron por esta persona: lista + QR usados.
  int get entraron => ingresaron + entradasUsadas;
  num get ventas => brutoEntradas + brutoMesas;
  bool get pagada => estadoComision == 'pagada';

  factory EventoRrpp.desde(Map<String, dynamic> j) => EventoRrpp(
        eventoId: j['evento_id'] as String,
        clubId: j['club_id'] as String,
        club: j['club'] as String? ?? '',
        logoUrl: j['logo_url'] as String?,
        evento: j['evento'] as String? ?? '',
        fecha: _f(j['fecha']),
        estado: j['estado'] as String? ?? '',
        anotados: _i(j['anotados']),
        ingresaron: _i(j['ingresaron']),
        entradasVendidas: _i(j['entradas_vendidas']),
        entradasUsadas: _i(j['entradas_usadas']),
        mesasConfirmadas: _i(j['mesas_confirmadas']),
        mesasReservadas: _i(j['mesas_reservadas']),
        brutoEntradas: _n(j['bruto_entradas']),
        brutoMesas: _n(j['bruto_mesas']),
        comisionEntradas: _n(j['comision_entradas']),
        comisionMesas: _n(j['comision_mesas']),
        comisionJefe: _n(j['comision_jefe']),
        bono: _n(j['bono']),
        comisionTotal: _n(j['comision_total']),
        porManilla: _n(j['por_manilla']),
        estadoComision: j['estado_comision'] as String? ?? 'estimada',
        pagadoAt: j['pagado_at'] == null ? null : DateTime.parse(j['pagado_at'] as String),
      );
}

/// Un evento que viene (rrpp_proximos).
class Proximo {
  const Proximo({
    required this.eventoId, required this.clubId, required this.club, this.logoUrl,
    required this.evento, required this.fecha, this.hora, this.anotados = 0, this.ingresaron = 0,
    this.entradasVendidas = 0, this.mesas = 0, this.porManilla = 0, this.cupoTotal, this.aftrPublico = false,
  });
  final String eventoId, clubId, club, evento;
  final String? logoUrl, hora;
  final DateTime fecha;
  final int anotados, ingresaron, entradasVendidas, mesas;
  final int? cupoTotal;
  final num porManilla;
  final bool aftrPublico;

  factory Proximo.desde(Map<String, dynamic> j) => Proximo(
        eventoId: j['evento_id'] as String,
        clubId: j['club_id'] as String,
        club: j['club'] as String? ?? '',
        logoUrl: j['logo_url'] as String?,
        evento: j['evento'] as String? ?? '',
        fecha: _f(j['fecha']),
        hora: (j['hora_inicio'] as String?)?.substring(0, 5),
        anotados: _i(j['anotados']),
        ingresaron: _i(j['ingresaron']),
        entradasVendidas: _i(j['entradas_vendidas']),
        mesas: _i(j['mesas']),
        porManilla: _n(j['por_manilla']),
        cupoTotal: j['cupo_total'] == null ? null : _i(j['cupo_total']),
        aftrPublico: j['aftr_publico'] as bool? ?? false,
      );
}

/// Un boliche con el que trabaja (o trabajó: activo = false).
class BolicheMio {
  const BolicheMio({required this.id, required this.nombre, this.logoUrl, this.ciudad,
      this.rol, this.team, required this.activo});
  final String id, nombre;
  final String? logoUrl, ciudad, rol, team;
  final bool activo;

  factory BolicheMio.desde(Map<String, dynamic> j) => BolicheMio(
        id: j['id'] as String,
        nombre: j['nombre'] as String? ?? '',
        logoUrl: j['logo_url'] as String?,
        ciudad: j['ciudad'] as String?,
        rol: j['rol'] as String?,
        team: j['team'] as String?,
        activo: j['activo'] as bool? ?? false,
      );
}

class SolicitudMia {
  const SolicitudMia({required this.id, required this.club, this.logoUrl, this.team,
      required this.estado, required this.creada});
  final String id, club, estado;
  final String? logoUrl, team;
  final DateTime creada;
  bool get pendiente => estado == 'pendiente';

  factory SolicitudMia.desde(Map<String, dynamic> j) => SolicitudMia(
        id: j['id'] as String,
        club: j['club'] as String? ?? '',
        logoUrl: j['logo_url'] as String?,
        team: j['team'] as String?,
        estado: j['estado'] as String? ?? '',
        creada: DateTime.parse(j['created_at'] as String),
      );
}

/// Lo que ve el admin o el jefe de cada persona que pide sumarse.
class SolicitudClub {
  const SolicitudClub({required this.id, required this.nombre, required this.usuario, this.email,
      required this.origen, this.teamId, this.team, this.eventosTrabajados = 0});
  final String id, nombre, usuario, origen;
  final String? email, teamId, team;
  final int eventosTrabajados;

  String get origenTexto => switch (origen) {
        'enlace_club' => 'Por el enlace del boliche',
        'enlace_team' => 'Por el enlace de un team',
        _ => 'Solicitud directa',
      };

  factory SolicitudClub.desde(Map<String, dynamic> j) => SolicitudClub(
        id: j['id'] as String,
        nombre: j['nombre'] as String? ?? '',
        usuario: j['usuario'] as String? ?? '',
        email: j['email'] as String?,
        origen: j['origen'] as String? ?? '',
        teamId: j['team_id'] as String?,
        team: j['team'] as String?,
        eventosTrabajados: _i(j['eventos_trabajados']),
      );
}

class BolicheExplorar {
  const BolicheExplorar({required this.id, required this.nombre, this.logoUrl, this.lugar,
      this.yaMiembro = false, this.pendiente = false});
  final String id, nombre;
  final String? logoUrl, lugar;
  final bool yaMiembro, pendiente;

  factory BolicheExplorar.desde(Map<String, dynamic> j) => BolicheExplorar(
        id: j['id'] as String,
        nombre: j['nombre'] as String? ?? '',
        logoUrl: j['logo_url'] as String?,
        lugar: [j['zona'], j['ciudad']].whereType<String>().where((x) => x.isNotEmpty).join(', '),
        yaMiembro: j['ya_miembro'] as bool? ?? false,
        pendiente: j['pendiente'] as bool? ?? false,
      );
}

/// Lo que hay detrás de un enlace de invitación.
class Invitacion {
  const Invitacion({required this.code, this.team, required this.clubs});
  final String code;
  final String? team;
  final List<({String id, String nombre, String? logo})> clubs;
}

// ── período y cálculos (funciones puras: se prueban sin red) ───────────

enum Periodo {
  semana('7 días', 'los últimos 7 días'),
  mes('Este mes', 'este mes'),
  trimestre('3 meses', 'los últimos 3 meses'),
  anio('Este año', 'este año'),
  todo('Todo', 'todo tu historial');

  const Periodo(this.corto, this.largo);
  final String corto, largo;

  /// Primer día que entra; null = sin límite.
  DateTime? desde(DateTime hoy) {
    final d = DateTime(hoy.year, hoy.month, hoy.day);
    return switch (this) {
      semana => d.subtract(const Duration(days: 6)),
      mes => DateTime(d.year, d.month),
      trimestre => DateTime(d.year, d.month - 3, d.day),
      anio => DateTime(d.year),
      todo => null,
    };
  }
}

List<EventoRrpp> delPeriodo(List<EventoRrpp> l, Periodo p, String? club, {DateTime? hoy}) {
  final d = p.desde(hoy ?? DateTime.now());
  return l.where((e) => (d == null || !e.fecha.isBefore(d)) && (club == null || e.clubId == club)).toList();
}

class Totales {
  int eventos = 0, entradas = 0, manillas = 0, mesas = 0, anotados = 0, ingresaron = 0, entraron = 0;
  num comision = 0, pendiente = 0, pagado = 0, estimado = 0, confirmado = 0, ventas = 0;

  int get asistencia => anotados == 0 ? 0 : (ingresaron * 100 / anotados).round();
  num get promedio => eventos == 0 ? 0 : comision / eventos;

  static Totales de(Iterable<EventoRrpp> l) {
    final t = Totales();
    for (final e in l) {
      t.eventos++;
      t.comision += e.comisionTotal;
      if (e.pagada) {
        t.pagado += e.comisionTotal;
      } else {
        t.pendiente += e.comisionTotal;
      }
      if (e.estadoComision == 'estimada') t.estimado += e.comisionTotal;
      if (e.estadoComision == 'confirmada') t.confirmado += e.comisionTotal;
      t.ventas += e.ventas;
      t.entradas += e.entradasVendidas;
      t.manillas += e.entradasUsadas;
      t.mesas += e.mesasConfirmadas;
      t.anotados += e.anotados;
      t.ingresaron += e.ingresaron;
      t.entraron += e.entraron;
    }
    return t;
  }
}

/// Un récord: el mejor valor, y de qué evento (o mes) salió.
class Record {
  const Record(this.titulo, this.valor, {this.evento, this.mes, this.plata = false});
  final String titulo;
  final num valor;
  final EventoRrpp? evento;
  final DateTime? mes;
  final bool plata;
}

/// Récords sobre todo el historial; los que no tienen datos no aparecen.
List<Record> records(List<EventoRrpp> l) {
  Record? mejor(String t, num Function(EventoRrpp) f, {bool plata = false}) {
    EventoRrpp? top;
    for (final e in l) {
      if (top == null || f(e) > f(top)) top = e;
    }
    return top != null && f(top) > 0 ? Record(t, f(top), evento: top, plata: plata) : null;
  }

  final meses = <DateTime, num>{};
  for (final e in l) {
    final k = DateTime(e.fecha.year, e.fecha.month);
    meses[k] = (meses[k] ?? 0) + e.comisionTotal;
  }
  final mm = meses.entries.isEmpty ? null : meses.entries.reduce((a, b) => b.value > a.value ? b : a);
  return [
    mejor('Entradas vendidas en una noche', (e) => e.entradasVendidas),
    mejor('Manillas en un evento', (e) => e.entradasUsadas),
    mejor('Mesas confirmadas en un evento', (e) => e.mesasConfirmadas),
    mejor('Asistentes efectivos en una noche', (e) => e.entraron),
    mejor('Comisión en un evento', (e) => e.comisionTotal, plata: true),
    mejor('Ventas generadas en un evento', (e) => e.ventas, plata: true),
    if (mm != null && mm.value > 0) Record('Mejor mes en ganancias', mm.value, mes: mm.key, plata: true),
    if (l.isNotEmpty) Record('Eventos trabajados', l.length),
  ].whereType<Record>().toList();
}

/// Suma por mes (los últimos 12 con datos), para los gráficos.
List<({DateTime mes, num valor})> porMes(List<EventoRrpp> l, num Function(EventoRrpp) f) {
  final g = <DateTime, num>{};
  for (final e in l) {
    final k = DateTime(e.fecha.year, e.fecha.month);
    g[k] = (g[k] ?? 0) + f(e);
  }
  final claves = g.keys.toList()..sort();
  return [for (final k in claves.skip(claves.length > 12 ? claves.length - 12 : 0)) (mes: k, valor: g[k]!)];
}

/// Acepta un enlace (…?unirse=abc o …?invite=abc) o el código solo.
String codigoDeUnion(String texto) {
  final t = texto.trim();
  final m = RegExp(r'[?&](?:unirse|invite|code)=([A-Za-z0-9]+)').firstMatch(t);
  return (m?.group(1) ?? t.replaceAll(RegExp(r'[^A-Za-z0-9]'), '')).toLowerCase();
}

// ── repositorio ─────────────────────────────────────────────────────────

final rrppRepositoryProvider = Provider<RrppRepository>((ref) => RrppRepository(ref.watch(supabaseProvider)));

class RrppRepository {
  RrppRepository(this._sb);
  final SupabaseClient _sb;

  Future<List<Map<String, dynamic>>> _lista(String fn, [Map<String, dynamic>? p]) async =>
      ((await _sb.rpc(fn, params: p ?? const {})) as List? ?? const [])
          .map((x) => Map<String, dynamic>.from(x as Map))
          .toList();

  Future<List<EventoRrpp>> eventos() async => (await _lista('rrpp_eventos')).map(EventoRrpp.desde).toList();
  Future<List<Proximo>> proximos() async => (await _lista('rrpp_proximos')).map(Proximo.desde).toList();
  Future<List<BolicheMio>> boliches() async => (await _lista('mis_establecimientos')).map(BolicheMio.desde).toList();
  Future<List<SolicitudMia>> solicitudes() async => (await _lista('mis_solicitudes')).map(SolicitudMia.desde).toList();

  Future<void> crearCuenta(String nombre) => _sb.rpc('rrpp_crear_cuenta', params: {'p_nombre': nombre});

  Future<Invitacion?> verInvitacion(String code) async {
    final r = await _sb.rpc('ver_invitacion', params: {'p_code': code});
    if (r == null) return null;
    final m = Map<String, dynamic>.from(r as Map);
    return Invitacion(
      code: code,
      team: (m['team'] as Map?)?['nombre'] as String?,
      clubs: [
        for (final c in (m['clubs'] as List? ?? const []).cast<Map>())
          (id: c['id'] as String, nombre: c['nombre'] as String? ?? '', logo: c['logo_url'] as String?),
      ],
    );
  }

  Future<void> solicitar(String? club, {String? code}) =>
      _sb.rpc('solicitar_union', params: {'p_club': club, 'p_code': code});
  Future<void> cancelar(String id) => _sb.rpc('cancelar_solicitud', params: {'p_id': id});
  Future<List<BolicheExplorar>> explorar(String q) async =>
      (await _lista('explorar_boliches', {'p_q': q.isEmpty ? null : q})).map(BolicheExplorar.desde).toList();

  Future<List<SolicitudClub>> solicitudesClub(String club) async =>
      (await _lista('solicitudes_club', {'p_club': club})).map(SolicitudClub.desde).toList();
  Future<void> resolver(String id, bool aprobar, {String? team}) =>
      _sb.rpc('resolver_solicitud', params: {'p_id': id, 'p_aprobar': aprobar, 'p_team': team});
  Future<void> revocar(String user, String club) =>
      _sb.rpc('revocar_acceso', params: {'p_user': user, 'p_club': club});

  Future<({String code, bool activo, bool publicas})> invitacionClub(String club) async {
    final m = Map<String, dynamic>.from(await _sb.rpc('invitacion_club', params: {'p_club': club}) as Map);
    return (code: m['code'] as String, activo: m['activo'] as bool? ?? true, publicas: m['publicas'] as bool? ?? false);
  }

  Future<void> regenerar(String club) => _sb.rpc('regenerar_invitacion_club', params: {'p_club': club});
  Future<void> configurar(String club, {bool? activo, bool? publicas}) => _sb.rpc('config_solicitudes_club',
      params: {'p_club': club, 'p_invite_activo': activo, 'p_publicas': publicas});

  Future<String> miRef() async => await _sb.rpc('rrpp_mi_ref') as String;

  Future<List<({String nombre, int eventos})>> recurrentes(String? club) async => [
        for (final r in await _lista('rrpp_recurrentes', {'p_club': club}))
          (nombre: r['nombre'] as String? ?? '', eventos: _i(r['eventos'])),
      ];

  Future<({int visitas, int clientes, int compras})> links(DateTime? desde) async {
    final l = await _lista('rrpp_links', {'p_desde': desde?.toIso8601String().substring(0, 10)});
    var v = 0, c = 0, k = 0;
    for (final r in l) {
      v += _i(r['visitas']);
      c += _i(r['clientes']);
      k += _i(r['compras']);
    }
    return (visitas: v, clientes: c, compras: k);
  }
}

// ── providers ───────────────────────────────────────────────────────────

final rrppEventosProvider = FutureProvider<List<EventoRrpp>>((ref) {
  ref.watch(usuarioIdProvider);
  return ref.watch(rrppRepositoryProvider).eventos();
});
final rrppProximosProvider = FutureProvider<List<Proximo>>((ref) {
  ref.watch(usuarioIdProvider);
  return ref.watch(rrppRepositoryProvider).proximos();
});
final misBolichesProvider = FutureProvider<List<BolicheMio>>((ref) {
  ref.watch(usuarioIdProvider);
  return ref.watch(rrppRepositoryProvider).boliches();
});
final misSolicitudesProvider = FutureProvider<List<SolicitudMia>>((ref) {
  ref.watch(usuarioIdProvider);
  return ref.watch(rrppRepositoryProvider).solicitudes();
});

/// Vuelve a pedir todo lo del espacio (después de aprobar, cancelar, etc.).
void refrescarRrpp(WidgetRef ref) {
  ref.invalidate(rrppEventosProvider);
  ref.invalidate(rrppProximosProvider);
  ref.invalidate(misBolichesProvider);
  ref.invalidate(misSolicitudesProvider);
}

class _Valor<T> extends Notifier<T> {
  _Valor(this._inicial);
  final T _inicial;
  @override
  T build() => _inicial;
  void poner(T v) => state = v;
}

final periodoProvider = NotifierProvider<_Valor<Periodo>, Periodo>(() => _Valor(Periodo.mes));
final filtroClubProvider = NotifierProvider<_Valor<String?>, String?>(() => _Valor(null));

/// Código de un enlace de invitación que llegó (deep link o pegado) y
/// todavía no se mandó como solicitud.
final unirsePendienteProvider = NotifierProvider<_Valor<String?>, String?>(() => _Valor(null));

/// Cómo eligió entrar la persona en la bienvenida: 'boliche' o 'rel'.
final modoAccesoProvider = NotifierProvider<_Valor<String?>, String?>(() => _Valor(null));
