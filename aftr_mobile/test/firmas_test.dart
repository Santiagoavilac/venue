import 'package:aftr_mobile/data/firmas.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

SupabaseClient _cliente() => SupabaseClient(
  'https://example.invalid',
  'clave-simulada',
  authOptions: const AuthClientOptions(autoRefreshToken: false),
);

void main() {
  test('las claves pedidas juntas viajan en una sola llamada', () async {
    final llamadas = <List<String>>[];
    final f = Firmas(
      _cliente(),
      pedir: (claves) async {
        llamadas.add(claves);
        return {
          'urls': {for (final c in claves) c: 'https://firmada/$c'},
          'vence_en': 600,
        };
      },
    );
    final r = await Future.wait([f.url('a'), f.url('b'), f.url('c')]);
    expect(r, ['https://firmada/a', 'https://firmada/b', 'https://firmada/c']);
    expect(llamadas.length, 1);
    expect(llamadas.first, ['a', 'b', 'c']);
  });

  test('una clave ya firmada no se vuelve a pedir', () async {
    var veces = 0;
    final f = Firmas(
      _cliente(),
      pedir: (claves) async {
        veces++;
        return {
          'urls': {for (final c in claves) c: 'https://firmada/$c'},
          'vence_en': 600,
        };
      },
    );
    await f.url('a');
    await f.url('a');
    expect(veces, 1);
    expect(f.enCache('a'), 'https://firmada/a');
  });

  test('una firma que falla no queda en caché', () async {
    var veces = 0;
    final f = Firmas(
      _cliente(),
      pedir: (claves) async {
        veces++;
        // la primera vuelta no resuelve nada, la segunda sí
        return veces == 1
            ? {'urls': const <String, dynamic>{}, 'vence_en': 600}
            : {
                'urls': {for (final c in claves) c: 'https://firmada/$c'},
                'vence_en': 600,
              };
      },
    );
    expect(await f.url('a'), isNull);
    expect(f.enCache('a'), isNull);
    expect(await f.url('a'), 'https://firmada/a');
    expect(veces, 2);
  });

  test('la firma se da por vencida antes de que se venza de verdad', () async {
    final f = Firmas(
      _cliente(),
      pedir: (claves) async => {
        'urls': {for (final c in claves) c: 'https://firmada/$c'},
        // un plazo corto: se guarda el 80 %, o sea nada
        'vence_en': 0,
      },
    );
    await f.url('a');
    await Future<void>.delayed(const Duration(milliseconds: 5));
    expect(f.enCache('a'), isNull);
  });

  test('un error de red no deja esperando a nadie', () async {
    final f = Firmas(
      _cliente(),
      pedir: (claves) async => throw Exception('sin red'),
    );
    expect(await f.url('a'), isNull);
  });
}
