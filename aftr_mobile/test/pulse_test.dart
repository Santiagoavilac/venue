import 'package:aftr_mobile/data/pulse_repo.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('los importes decimales se convierten sin redondeos binarios', () {
    expect(centavosDe('0.29'), 29);
    expect(centavosDe('123,45'), 12345);
    expect(centavosDe('10.1'), 1010);
    expect(importePulse(12345), '123.45');
    expect(importePulse(-29), '-0.29');
  });
  test(
    'rechaza precisión extra, signos, notación científica y texto ambiguo',
    () {
      for (final s in [
        '1.001',
        '-1',
        '1e3',
        '1,000.00',
        'NaN',
        'Infinity',
        '',
      ]) {
        expect(centavosDe(s), isNull);
      }
    },
  );
  test('las claves de operación son UUID v4 diferentes', () {
    final a = nuevaOperacion(), b = nuevaOperacion();
    expect(a, isNot(b));
    expect(
      a,
      matches(
        RegExp(
          r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
        ),
      ),
    );
  });
}
