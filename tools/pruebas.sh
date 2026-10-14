#!/bin/sh
# Corre todas las pruebas de Venue contra el proyecto de .env.local (DEMO).
#
# Las de integración van de a un archivo: cada una abre varias sesiones y,
# en paralelo, Supabase Auth corta por exceso de logins (429) y la corrida
# queda esperando.
set -e
cd "$(dirname "$0")/.."
python3 tools/seed_demo.py >/dev/null
python3 tests/test_seguridad.py | tail -1
cd venue_mobile
flutter analyze | tail -1
flutter test | tail -1
for f in test/integracion/*_test.dart; do
  printf '%s: ' "$(basename "$f" _test.dart)"
  flutter test "$f" --timeout 60s --dart-define-from-file=env/dev.json | tail -1
done
