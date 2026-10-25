import '../../data/modelos.dart';

/// Filtros del mapa (los chips de arriba, como los de Resy).
enum FiltroMapa { hoy, mesas, listas, gratis }

extension FiltroMapaTexto on FiltroMapa {
  String get texto => switch (this) {
        FiltroMapa.hoy => 'Hoy',
        FiltroMapa.mesas => 'Con mesas',
        FiltroMapa.listas => 'Listas',
        FiltroMapa.gratis => 'Gratis',
      };
}

bool _esHoy(Evento e, DateTime ahora) =>
    e.fecha.year == ahora.year && e.fecha.month == ahora.month && e.fecha.day == ahora.day;

/// Los eventos que pasan los filtros y la búsqueda.
List<Evento> filtrarEventos(List<Evento> eventos, Set<FiltroMapa> filtros, String q, DateTime ahora) {
  final t = q.trim().toLowerCase();
  return eventos.where((e) {
    if (filtros.contains(FiltroMapa.hoy) && !_esHoy(e, ahora)) return false;
    if (filtros.contains(FiltroMapa.mesas) && e.mesasLibres == 0) return false;
    if (filtros.contains(FiltroMapa.listas) && !e.tieneLista) return false;
    if (filtros.contains(FiltroMapa.gratis) && !(e.desdePrecio == 0 || e.tieneLista)) return false;
    if (t.isNotEmpty &&
        !e.nombre.toLowerCase().contains(t) &&
        !e.club.nombre.toLowerCase().contains(t) &&
        !(e.club.zona ?? '').toLowerCase().contains(t) &&
        !e.generos.any((g) => g.toLowerCase().contains(t))) {
      return false;
    }
    return true;
  }).toList()
    ..sort((a, b) => a.inicio.compareTo(b.inicio));
}

/// Un pin por lugar: el próximo evento que pasó los filtros. Sin filtros ni
/// búsqueda también aparecen los lugares sin eventos (pin apagado).
class PinLugar {
  const PinLugar(this.lugar, this.evento);
  final Lugar lugar;
  final Evento? evento;

  bool esHoy(DateTime ahora) => evento != null && _esHoy(evento!, ahora);
}

List<PinLugar> pinesPara(List<Lugar> lugares, List<Evento> filtrados, {required bool todos}) {
  final primero = <String, Evento>{};
  for (final e in filtrados) {
    primero.putIfAbsent(e.club.id, () => e);
  }
  final out = <PinLugar>[];
  for (final l in lugares.where((l) => l.ubicado)) {
    final e = primero[l.id];
    if (e != null || todos) out.add(PinLugar(l, e));
  }
  // los que tienen algo hoy primero, después por fecha del evento
  out.sort((a, b) {
    if (a.evento == null) return b.evento == null ? a.lugar.nombre.compareTo(b.lugar.nombre) : 1;
    if (b.evento == null) return -1;
    return a.evento!.inicio.compareTo(b.evento!.inicio);
  });
  return out;
}

/// Centro y "zoom" que abarcan todos los pines.
({double lat, double lng, double zoom}) encuadre(List<PinLugar> pines) {
  if (pines.isEmpty) return (lat: -17.7833, lng: -63.1821, zoom: 12.5); // Santa Cruz
  var minLa = 90.0, maxLa = -90.0, minLo = 180.0, maxLo = -180.0;
  for (final p in pines) {
    minLa = p.lugar.lat! < minLa ? p.lugar.lat! : minLa;
    maxLa = p.lugar.lat! > maxLa ? p.lugar.lat! : maxLa;
    minLo = p.lugar.lng! < minLo ? p.lugar.lng! : minLo;
    maxLo = p.lugar.lng! > maxLo ? p.lugar.lng! : maxLo;
  }
  final span = [maxLa - minLa, maxLo - minLo].reduce((a, b) => a > b ? a : b);
  final zoom = span < 0.005 ? 15.0 : (span < 0.02 ? 14.0 : (span < 0.06 ? 13.0 : (span < 0.2 ? 11.5 : 10.0)));
  return (lat: (minLa + maxLa) / 2, lng: (minLo + maxLo) / 2, zoom: zoom);
}
