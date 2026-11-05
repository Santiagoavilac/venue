import 'package:flutter_test/flutter_test.dart';
import 'package:venue_mobile/core/widgets/avisos.dart';
import 'package:venue_mobile/features/access_control/data/persona_puerta.dart';
import 'package:venue_mobile/features/access_control/data/resultado.dart';

PersonaPuerta p(String nombre,
        {String? ingreso, String? filtro, bool casa = false, bool entrada = false}) =>
    PersonaPuerta.desde({
      'tipo': entrada ? 'entrada' : 'lista',
      'nombre': nombre,
      'id': nombre,
      'sin_tope': casa,
      'ingreso_at': ingreso,
      'filtro_at': filtro,
    });

void main() {
  _qrInhabilitado();
  test('fila de entrada y de lista desde el servidor', () {
    final e = PersonaPuerta.desde({
      'tipo': 'entrada', 'nombre': 'Ana', 'code': 'ABC', 'lista': 'Mesa B2',
      'estado': 'anulada', 'sin_tope': true,
    });
    expect(e.esEntrada, isTrue);
    expect(e.anulada, isTrue);
    expect(e.sinTope, isTrue);
    expect(e.ingreso, isFalse);
    // las filas de lista no traen code ni estado
    final l = PersonaPuerta.desde({'tipo': 'lista', 'nombre': 'Luis', 'id': 'r1', 'rrpp': 'Mateo'});
    expect(l.esEntrada, isFalse);
    expect(l.codigo, isNull);
    expect(l.anulada, isFalse);
  });

  test('orden: ingresados (reciente primero), pendientes por nombre, filtrados al fondo', () {
    final r = PersonaPuerta.ordenar([
      p('Zoe'),
      p('Filtrado', filtro: '2026-10-13T22:00:00Z'),
      p('Entró temprano', ingreso: '2026-10-13T22:00:00Z'),
      p('ana'),
      p('Entró recién', ingreso: '2026-10-13T23:30:00Z'),
    ]);
    expect(r.map((x) => x.nombre),
        ['Entró recién', 'Entró temprano', 'ana', 'Zoe', 'Filtrado']);
  });

  test('filtro discreto: solo quedan los de la casa', () {
    final filas = [p('Común'), p('De la casa', casa: true, entrada: true)];
    expect(PersonaPuerta.ordenar(filas, discreto: true).map((x) => x.nombre),
        ['De la casa']);
    expect(PersonaPuerta.ordenar(filas).length, 2);
    expect(PersonaPuerta.ordenar([p('Común')], discreto: true), isEmpty);
  });

  test('relacionador', () {
    final r = Relacionador.desde({'nombre': 'Julián', 'usuario': 'jefe.aurora', 'rol': 'jefe', 'team': 'Team Norte'});
    expect(r.esJefe, isTrue);
    expect(Relacionador.desde({'nombre': 'x'}).team, 'Sin team');
  });

  test('normalizar quita tildes para buscar', () {
    expect(normalizar('José Ñandú'), 'jose nandu');
    expect(normalizar('JULIÁN').contains(normalizar('julian')), isTrue);
  });

  test('hora corta', () {
    expect(horaCorta(DateTime(2026, 1, 1, 2, 5)), '02:05');
  });
}

// ── El QR de un invitado se puede inhabilitar ────────────────────────
// La columna registros.qr_anulado existía desde db/13 y nadie la escribía: no
// había forma de frenar a quien entra con el QR de otro.
void _qrInhabilitado() {
  test('el QR de invitado inhabilitado no deja pasar y dice por qué', () {
    final r = ResultadoEscaneo.desdeServidor(
      {
        'resultado': 'anulada',
        'cliente': 'Ana',
        'lista': true,
        'lista_nombre': 'Invitados',
        'motivo': 'Entró otra persona con este QR',
        'rrpp': 'Juan',
      },
      codigo: 'ZZTEST1',
      esLista: true,
      ahora: DateTime(2026, 11, 5),
    );
    expect(r.veredicto.dejaPasar, isFalse);
    expect(r.tipo, 'QR inhabilitado');
    expect(r.detalle, contains('Entró otra persona'));
  });

  test('la entrada anulada por el vendedor sigue diciendo lo suyo', () {
    final r = ResultadoEscaneo.desdeServidor(
      {'resultado': 'anulada', 'cliente': 'Ana'},
      codigo: 'ABC123',
      esLista: false,
      ahora: DateTime(2026, 11, 5),
    );
    expect(r.veredicto.dejaPasar, isFalse);
    expect(r.tipo, 'Entrada anulada');
    expect(r.detalle, contains('vendedor'));
  });

  test('una fila de puerta con el QR inhabilitado se lee como anulada', () {
    final p = PersonaPuerta.desde({
      'id': 'uno',
      'tipo': 'lista',
      'nombre': 'Ana',
      'lista': 'Invitados',
      'qr_anulado': true,
      'qr_anulado_motivo': 'lo usó otro',
    });
    expect(p.qrAnulado, isTrue);
    expect(p.anulada, isTrue);
    expect(p.qrAnuladoMotivo, 'lo usó otro');
    // y sin la bandera, nada cambia
    final otra = PersonaPuerta.desde({'id': 'dos', 'tipo': 'lista', 'nombre': 'Beto'});
    expect(otra.qrAnulado, isFalse);
    expect(otra.anulada, isFalse);
  });
}
