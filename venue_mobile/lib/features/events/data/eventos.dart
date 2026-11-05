import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/networking/supabase.dart';
import '../../clubs/data/clubs.dart';

class Evento {
  const Evento({
    required this.id,
    required this.nombre,
    required this.fecha,
    required this.horaInicio,
    required this.horaFin,
    required this.estado,
    this.ticketUrl,
    this.precioManilla = 0,
    this.pctBoliche = 0,
    this.ventaPorFases = false,
    this.permiteReserva = true,
    this.horasReserva = 3,
    this.permiteAgrupar = true,
    this.comboObligatorio = true,
    this.comboPorMesa = false,
    this.configV2 = false,
    this.modoComision = 'jefes',
    this.comisionManillas = true,
    this.comisionMesas = false,
  });

  final String id;
  final String nombre;
  final DateTime fecha;
  final String horaInicio;
  final String horaFin;
  final String estado;

  /// Arte sobre el que se imprime el QR de las entradas.
  final String? ticketUrl;
  final num precioManilla;

  /// Parte del boliche en cada manilla (%); el resto es la comisión del team.
  final num pctBoliche;
  final bool ventaPorFases;

  // reglas de venta de mesas del evento
  final bool permiteReserva;
  final int horasReserva;
  final bool permiteAgrupar;
  final bool comboObligatorio;
  final bool comboPorMesa;

  /// Operación de comisiones del evento (db/52). Los eventos anteriores
  /// siguen con la cuenta vieja (configV2 = false).
  final bool configV2;
  final String modoComision;
  final bool comisionManillas;

  /// Si las mesas pagan comisión a quien las vende (db/52, por defecto no).
  /// Cuando no pagan, la plata de una mesa es del boliche y no tiene por qué
  /// aparecerle al relacionador: él no cobra nada de ahí.
  final bool comisionMesas;

  /// Parte del boliche sobre cada manilla, de 0 a 1: la del evento; la cuenta
  /// vieja usa el 50 % de siempre y, sin comisión, la manilla es del boliche.
  num get pctBolicheManillas => !configV2
      ? 0.5
      : (modoComision == 'ninguno' || !comisionManillas)
          ? 1
          : pctBoliche / 100;

  factory Evento.desde(Map<String, dynamic> j) => Evento(
        id: j['id'] as String,
        nombre: j['nombre'] as String? ?? '',
        fecha: DateTime.parse(j['fecha'] as String),
        horaInicio: (j['hora_inicio'] as String? ?? '21:00').substring(0, 5),
        horaFin: (j['hora_fin'] as String? ?? '06:00').substring(0, 5),
        estado: j['estado'] as String? ?? '',
        ticketUrl: j['ticket_url'] as String?,
        precioManilla: j['precio_manilla'] as num? ?? 0,
        pctBoliche: j['pct_boliche'] as num? ?? 0,
        ventaPorFases: j['venta_por_fases'] == true,
        permiteReserva: j['permite_reserva'] != false,
        horasReserva: (j['horas_reserva'] as num?)?.toInt() ?? 3,
        permiteAgrupar: j['permite_agrupar'] != false,
        comboObligatorio: j['combo_obligatorio'] != false,
        comboPorMesa: j['combo_por_mesa'] == true,
        configV2: j['config_v2'] == true,
        modoComision: j['modo_comision'] as String? ?? 'jefes',
        comisionManillas: j['comision_manillas'] != false,
        comisionMesas: j['comision_mesas'] == true,
      );

  /// ¿Está en curso ahora? Contempla el cruce de medianoche (21:00 → 06:00).
  bool enCurso(DateTime ahora) {
    if (estado == 'cerrado') return false;
    DateTime a(String hhmm) {
      final p = hhmm.split(':');
      return DateTime(
          fecha.year, fecha.month, fecha.day, int.parse(p[0]), int.parse(p[1]));
    }

    final inicio = a(horaInicio);
    var fin = a(horaFin);
    if (!fin.isAfter(inicio)) fin = fin.add(const Duration(days: 1));
    return !ahora.isBefore(inicio) && !ahora.isAfter(fin);
  }

  bool esHoy(DateTime ahora) =>
      fecha.year == ahora.year &&
      fecha.month == ahora.month &&
      fecha.day == ahora.day;

  static const _dias = ['lun', 'mar', 'mié', 'jue', 'vie', 'sáb', 'dom'];
  static const _meses = [
    'ene', 'feb', 'mar', 'abr', 'may', 'jun',
    'jul', 'ago', 'sep', 'oct', 'nov', 'dic',
  ];
  String get fechaCorta =>
      '${_dias[fecha.weekday - 1]} ${fecha.day} ${_meses[fecha.month - 1]}';
}

/// Eventos abiertos del boliche activo, del más próximo al más lejano.
final eventosProvider = FutureProvider<List<Evento>>((ref) async {
  final club = ref.watch(clubActivoIdProvider);
  if (club == null) return const [];
  final filas = await ref
      .watch(supabaseProvider)
      .from('eventos')
      .select('id, nombre, fecha, hora_inicio, hora_fin, estado, ticket_url, precio_manilla, pct_boliche, venta_por_fases, permite_reserva, horas_reserva, permite_agrupar, combo_obligatorio, combo_por_mesa, config_v2, modo_comision, comision_manillas, comision_mesas')
      .eq('club_id', club)
      .neq('estado', 'cerrado')
      .order('fecha', ascending: true);
  return filas.map(Evento.desde).toList();
});

/// Evento elegido a mano; null = el que la app propone.
class EventoElegido extends Notifier<String?> {
  @override
  String? build() {
    ref.watch(clubActivoIdProvider);
    return null;
  }

  void elegir(String id) => state = id;
}

final eventoElegidoProvider =
    NotifierProvider<EventoElegido, String?>(EventoElegido.new);

/// Cuál de los eventos abiertos es "el de ahora".
///
/// Está aparte del provider para poder probarlo: es la regla que decide qué
/// ve toda la app, y antes estaba mal. El último recurso era el primero de la
/// lista, y como la lista va de más vieja a más nueva y nada cierra los
/// eventos solos, devolvía el evento más antiguo que quedó abierto. La app
/// decía "tu evento" y mostraba uno de hace semanas, con sus mesas y sus
/// pagos, sin avisar nada.
///
/// El orden ahora es: el que elegiste, el que está en curso, el próximo por
/// empezar, y recién si todos pasaron, el más reciente.
Evento? elegirEventoActivo(
  List<Evento> lista,
  String? elegido,
  DateTime ahora,
) {
  if (lista.isEmpty) return null;
  for (final e in lista) {
    if (e.id == elegido) return e;
  }
  for (final e in lista) {
    if (e.enCurso(ahora)) return e;
  }
  final hoy = DateTime(ahora.year, ahora.month, ahora.day);
  for (final e in lista) {
    if (!e.fecha.isBefore(hoy)) return e;
  }
  return lista.last;
}

/// Evento sobre el que se opera.
final eventoActivoProvider = Provider<Evento?>((ref) => elegirEventoActivo(
      ref.watch(eventosProvider).value ?? const <Evento>[],
      ref.watch(eventoElegidoProvider),
      DateTime.now(),
    ));
