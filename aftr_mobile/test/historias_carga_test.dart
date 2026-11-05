import 'package:aftr_mobile/data/firmas.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

SupabaseClient _cliente() => SupabaseClient(
  'https://example.invalid',
  'clave-simulada',
  authOptions: const AuthClientOptions(autoRefreshToken: false),
);

void main() {
  // Lo que hace que el visor no abra en negro: la URL de la primera historia
  // se resuelve antes, y las de la misma tanda viajan en una sola llamada.
  test('abrir un grupo y precargar dos no son tres llamadas', () async {
    var llamadas = 0;
    final f = Firmas(
      _cliente(),
      pedir: (claves) async {
        llamadas++;
        return {
          'urls': {for (final c in claves) c: 'https://firmada/$c'},
          'vence_en': 600,
        };
      },
    );
    // el círculo pide la primera; el visor, las dos que siguen
    final r = await Future.wait([f.url('h1'), f.url('h2'), f.url('h3')]);
    expect(r.whereType<String>().length, 3);
    expect(llamadas, 1);
    // y volver atrás no pide nada
    expect(f.enCache('h1'), isNotNull);
    await f.url('h1');
    expect(llamadas, 1);
  });

  test('si la firma no vuelve, no hay URL con la que abrir el visor', () async {
    final f = Firmas(
      _cliente(),
      pedir: (claves) async => {'urls': const <String, dynamic>{}, 'vence_en': 600},
    );
    expect(await f.url('h1'), isNull);
  });
}
