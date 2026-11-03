#!/bin/sh
# Publica la web en Vercel (proyecto venue-web) desde una carpeta limpia:
# solo los archivos públicos, nunca .env.local, db/, tools/ ni la app móvil.
# config.js lleva la clave anon (pública por diseño); se verifica abajo.
set -e
cd "$(dirname "$0")/../.."
# control de espacio en disco (ayudante local opcional)
g=/Users/user/.codex/helpers/storage_guard.py; [ ! -f "$g" ] || python3 "$g" --check-heavy
DEPLOY_TMP="$(mktemp -d)"
trap 'rm -rf -- "$DEPLOY_TMP"' EXIT HUP INT TERM
D="$DEPLOY_TMP/venue-web"; mkdir -p "$D"
cp index.html privacidad.html app.js relacionador.js motion.js styles.css rediseno.css reporte-escritorio.js contabilidad.js config.js sw.js \
   icon-512.png icon.svg manifest.webmanifest tools/web/vercel.json "$D/"
cp social-venue.js social-venue.css "$D/"
mkdir -p "$D/aftr_web"
cp aftr_web/social-core.js aftr_web/social.css "$D/aftr_web/"
if grep -rqi 'service_role' "$D"; then echo "Hay una clave privilegiada en los archivos: no se publica." >&2; exit 1; fi
python3 - "$D/config.js" <<'PY'
import base64, json, re, sys
t = re.search(r'eyJ[\w-]+\.([\w-]+)\.', open(sys.argv[1]).read()).group(1)
rol = json.loads(base64.urlsafe_b64decode(t + '=' * (-len(t) % 4)))['role']
sys.exit(0 if rol == 'anon' else f'config.js no tiene la clave anon (tiene {rol}): no se publica.')
PY
cd "$D" && vercel deploy --prod --yes --scope santiago-avilas-projects --project prj_7vVOjLy8SxnXcUU4gvgl92gaQxTS "$@"
