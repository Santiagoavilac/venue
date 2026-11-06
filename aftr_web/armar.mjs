/* Arma la carpeta que se publica de AFTR.
 *
 * Mismo problema y misma razón que tools/armar_web.mjs (leer el comentario de
 * arriba de ese archivo): el proyecto de Vercel no estaba conectado al repo y
 * `config.js` no se versiona. Este vive acá porque el proyecto de AFTR tiene
 * esta carpeta como raíz y no ve la del repo.
 */
import { cp, mkdir, rm, writeFile, readFile, access } from 'node:fs/promises';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';

const aqui = dirname(fileURLToPath(import.meta.url));
const dist = join(aqui, 'dist');

const archivos = [
  'index.html', 'privacidad.html', 'terminos.html', 'normas.html',
  'aftr.js', 'social.js', 'social-core.js', 'pulse.js', 'cuenta-ui.js',
  'aftr.css', 'social.css', 'pulse.css',
  'img',
];

await rm(dist, { recursive: true, force: true });
await mkdir(dist, { recursive: true });

for (const f of archivos) {
  const desde = join(aqui, f);
  try { await access(desde); } catch {
    console.error(`falta ${f}: la web no se publica a medias`);
    process.exit(1);
  }
  const hasta = join(dist, f);
  await mkdir(dirname(hasta), { recursive: true });
  await cp(desde, hasta, { recursive: true });
}

const url = process.env.SUPABASE_URL;
const key = process.env.SUPABASE_ANON_KEY;
let config;
if (url && key) {
  config = '/* Generado por aftr_web/armar.mjs desde las variables del proyecto. */\n'
    + 'window.CONFIG = {\n'
    + `  SUPABASE_URL: ${JSON.stringify(url)},\n`
    + `  SUPABASE_ANON_KEY: ${JSON.stringify(key)}\n};\n`;
} else {
  try {
    config = await readFile(join(aqui, 'config.js'), 'utf8');
    console.warn('sin SUPABASE_URL/SUPABASE_ANON_KEY: se usa el config.js local');
  } catch {
    console.error('no hay SUPABASE_URL ni SUPABASE_ANON_KEY, y tampoco config.js local:');
    console.error('la web saldría sin base. Cargá las variables en el proyecto de Vercel.');
    process.exit(1);
  }
}
await writeFile(join(dist, 'config.js'), config);
console.log('dist/ armado para AFTR');
