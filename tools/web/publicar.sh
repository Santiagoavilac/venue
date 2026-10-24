#!/bin/sh
# Publica la web en Vercel (proyecto venue-web) desde una carpeta limpia:
# solo los archivos públicos, nunca .env.local, db/, tools/ ni la app móvil.
# config.js lleva la clave anon (pública por diseño); se verifica abajo.
set -e
cd "$(dirname "$0")/../.."
D="$(mktemp -d)/venue-web"; mkdir -p "$D"
cp index.html app.js motion.js styles.css rediseno.css reporte-escritorio.js contabilidad.js config.js sw.js \
   icon-512.png icon.svg manifest.webmanifest tools/web/vercel.json "$D/"
if grep -qi 'service_role' "$D"/*; then echo "Hay una clave privilegiada en los archivos: no se publica." >&2; exit 1; fi
python3 - "$D/config.js" <<'PY'
import base64, json, re, sys
t = re.search(r'eyJ[\w-]+\.([\w-]+)\.', open(sys.argv[1]).read()).group(1)
rol = json.loads(base64.urlsafe_b64decode(t + '=' * (-len(t) % 4)))['role']
sys.exit(0 if rol == 'anon' else f'config.js no tiene la clave anon (tiene {rol}): no se publica.')
PY
cd "$D" && vercel deploy --prod --yes
