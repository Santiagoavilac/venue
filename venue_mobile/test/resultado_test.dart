import 'package:flutter_test/flutter_test.dart';
import 'package:venue_mobile/features/access_control/data/resultado.dart';

ResultadoEscaneo r(Map<String, dynamic> j, {bool lista = false}) =>
    ResultadoEscaneo.desdeServidor(j,
        codigo: 'ABC123', esLista: lista, ahora: DateTime(2026, 10, 13, 23, 5));

void main() {
  test('válida → PASA con relacionador y team', () {
    final x = r({
      'resultado': 'valida', 'cliente': 'Carlos Roca', 'code': 'ABC123',
      'rrpp': 'Mateo', 'team': 'AQ', 'mesa': null, 'sin_tope': false,
    });
    expect(x.veredicto, Veredicto.pasa);
    expect(x.veredicto.dejaPasar, isTrue);
    expect(x.nombre, 'Carlos Roca');
    expect(x.tipo, 'Entrada prepagada');
    expect(x.quien, 'Mateo · Team AQ');
    expect(x.hora, DateTime(2026, 10, 13, 23, 5));
  });

  test('válida de mesa y de la casa', () {
    expect(r({'resultado': 'valida', 'mesa': 'A4'}).tipo,
        'Manilla de combo · Mesa A4');
    final casa = r({'resultado': 'valida', 'sin_tope': true});
    expect(casa.tipo, 'Entrada de la casa');
    expect(casa.detalle, 'Sin tope de horario');
  });

  test('usada → YA INGRESÓ con la hora del ingreso anterior', () {
    final x = r({
      'resultado': 'usada', 'cliente': 'Ana', 'used_at': '2026-10-14T02:10:00Z',
    });
    expect(x.veredicto, Veredicto.yaIngreso);
    expect(x.veredicto.dejaPasar, isFalse);
    expect(x.hora, DateTime.utc(2026, 10, 14, 2, 10).toLocal());
  });

  test('anulada → NO VÁLIDO', () {
    final x = r({'resultado': 'anulada', 'cliente': 'Ana'});
    expect(x.veredicto, Veredicto.noValido);
    expect(x.tipo, 'Entrada anulada');
  });

  test('fuera de hora, entrada y lista', () {
    expect(r({'resultado': 'fuera_hora'}).veredicto, Veredicto.fueraDeHorario);
    final l = r({
      'resultado': 'fuera_horario', 'lista_nombre': 'Free', 'limite': '00:30',
    }, lista: true);
    expect(l.veredicto, Veredicto.fueraDeHorario);
    expect(l.tipo, 'Free cerrada');
    expect(l.detalle, 'Entraba hasta 00:30');
  });

  test('lista válida muestra el nombre de la lista', () {
    final x = r({'resultado': 'valida', 'lista_nombre': 'Invitados'}, lista: true);
    expect(x.tipo, 'Invitados');
  });

  test('no existe, o una respuesta desconocida, nunca deja pasar', () {
    for (final j in [
      {'resultado': 'no_existe'},
      {'resultado': 'algo_nuevo'},
      <String, dynamic>{},
    ]) {
      final x = r(j);
      expect(x.veredicto, Veredicto.noValido);
      expect(x.veredicto.dejaPasar, isFalse);
    }
  });

  test('solo PASA deja pasar', () {
    expect(Veredicto.values.where((v) => v.dejaPasar), [Veredicto.pasa]);
  });
}
