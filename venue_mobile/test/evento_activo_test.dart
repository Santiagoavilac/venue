import 'package:flutter_test/flutter_test.dart';
import 'package:venue_mobile/features/events/data/eventos.dart';

/// Qué evento muestra la app cuando entrás.
///
/// Esto decide lo que ven Mesas, Pagos, Accesos y el escáner de la puerta.
/// Estaba mal: el último recurso era el primero de la lista, y como la lista
/// va de más vieja a más nueva y nada cierra los eventos solos, la app abría
/// en el evento más antiguo que quedó abierto sin avisar.
void main() {
  Evento ev(String id, DateTime fecha, {String hi = '21:00', String hf = '06:00'}) =>
      Evento.desde({
        'id': id,
        'nombre': id,
        'fecha': fecha.toIso8601String().substring(0, 10),
        'hora_inicio': hi,
        'hora_fin': hf,
      });

  final ahora = DateTime(2026, 11, 5, 15);
  final viejo = ev('viejo', DateTime(2026, 10, 10));
  final proximo = ev('proximo', DateTime(2026, 11, 8));
  final lejano = ev('lejano', DateTime(2026, 12, 20));
  // ordenados por fecha, como los entrega el servidor
  final lista = [viejo, proximo, lejano];

  test('con un evento viejo sin cerrar, abre en el próximo', () {
    expect(elegirEventoActivo(lista, null, ahora)?.id, 'proximo');
  });

  test('respeta el que elegiste a mano, aunque sea pasado', () {
    expect(elegirEventoActivo(lista, 'viejo', ahora)?.id, 'viejo');
  });

  test('si hay uno en curso, ese gana', () {
    final hoy = ev('hoy', DateTime(2026, 11, 5));
    final conHoy = [viejo, hoy, proximo];
    expect(elegirEventoActivo(conHoy, null, DateTime(2026, 11, 5, 23))?.id, 'hoy');
  });

  test('un evento de hoy que ya terminó no se considera en curso', () {
    final hoy = ev('hoy', DateTime(2026, 11, 5));
    // 15:00: la fiesta de anoche terminó a las 06:00 y la de hoy no empezó
    expect(elegirEventoActivo([hoy], null, ahora)?.id, 'hoy');
  });

  test('si todos pasaron, toma el más reciente y no el más viejo', () {
    final pasados = [ev('a', DateTime(2026, 9, 1)), ev('b', DateTime(2026, 10, 1))];
    expect(elegirEventoActivo(pasados, null, ahora)?.id, 'b');
  });

  test('sin eventos devuelve null', () {
    expect(elegirEventoActivo(const [], null, ahora), isNull);
  });

  test('el evento de hoy gana al de mañana', () {
    final hoy = ev('hoy', DateTime(2026, 11, 5));
    expect(elegirEventoActivo([hoy, proximo], null, ahora)?.id, 'hoy');
  });
}
