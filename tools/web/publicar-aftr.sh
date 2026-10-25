#!/bin/sh
# Publica la web de AFTR en Vercel (proyecto aftr-web) desde una carpeta
# limpia: solo aftr_web/, nunca .env.local, db/, tools/ ni las apps.
# config.js lleva la clave anon (pública por diseño); se verifica abajo.
set -e
cd "$(dirname "$0")/../.."
D="$(mktemp -d)/aftr-web"; mkdir -p "$D"
cp -R aftr_web/. "$D/"
cp tools/web/vercel.json "$D/"
# el mapa pide la ubicación de quien mira: se habilita solo para esta web
sed -i '' 's/geolocation=()/geolocation=(self)/' "$D/vercel.json"
if grep -rqi 'service_role' "$D"; then echo "Hay una clave privilegiada en los archivos: no se publica." >&2; exit 1; fi
python3 - "$D/config.js" <<'PY'
import base64, json, re, sys
t = re.search(r'eyJ[\w-]+\.([\w-]+)\.', open(sys.argv[1]).read()).group(1)
rol = json.loads(base64.urlsafe_b64decode(t + '=' * (-len(t) % 4)))['role']
sys.exit(0 if rol == 'anon' else f'config.js no tiene la clave anon (tiene {rol}): no se publica.')
PY
cd "$D" && vercel deploy --prod --yes
