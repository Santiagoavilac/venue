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
    this.ventaPorFases = false,
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
  final bool ventaPorFases;

  factory Evento.desde(Map<String, dynamic> j) => Evento(
        id: j['id'] as String,
        nombre: j['nombre'] as String? ?? '',
        fecha: DateTime.parse(j['fecha'] as String),
        horaInicio: (j['hora_inicio'] as String? ?? '21:00').substring(0, 5),
        horaFin: (j['hora_fin'] as String? ?? '06:00').substring(0, 5),
        estado: j['estado'] as String? ?? '',
        ticketUrl: j['ticket_url'] as String?,
        precioManilla: j['precio_manilla'] as num? ?? 0,
        ventaPorFases: j['venta_por_fases'] == true,
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
      .select('id, nombre, fecha, hora_inicio, hora_fin, estado, ticket_url, precio_manilla, venta_por_fases')
      .eq('club_id', club)
      .neq('estado', 'cerrado')
      .order('fecha');
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

/// Evento sobre el que se opera: el elegido; si no, el que está en curso; si
/// no, el primero de la lista.
final eventoActivoProvider = Provider<Evento?>((ref) {
  final lista = ref.watch(eventosProvider).value ?? const <Evento>[];
  if (lista.isEmpty) return null;
  final elegido = ref.watch(eventoElegidoProvider);
  for (final e in lista) {
    if (e.id == elegido) return e;
  }
  final ahora = DateTime.now();
  for (final e in lista) {
    if (e.enCurso(ahora)) return e;
  }
  return lista.first;
});
