/* Arma la carpeta que se publica de la web de Venue (la raíz del repo).
 *
 * Qué se rompía: los dos proyectos de Vercel no estaban conectados al repo
 * —`link: null`, y todos los despliegues sin commit asociado—, así que
 * `git push` no publicaba nada. venuebol.com y aftrvenue.com quedaron
 * sirviendo el código del 05/11 a las 03:47 mientras la base ya tenía todo
 * lo nuevo. No se podían conectar por dos razones concretas:
 *
 *  1. `config.js` —la URL y la anon key de Supabase— está en .gitignore, así
 *     que un build desde el repo lo dejaría afuera y la web arrancaría sin
 *     base. Acá se escribe desde las variables del proyecto en Vercel
 *     (SUPABASE_URL y SUPABASE_ANON_KEY). La anon key es pública: viaja al
 *     navegador igual y lo que protege los datos es RLS.
 *
 *  2. Publicar la raíz del repo publicaría también db/, docs/, supabase/,
 *     tests/ y las dos apps Flutter en texto plano. Acá se copia sólo lo que
 *     la web necesita, nombre por nombre: lo que no está en la lista no se
 *     publica, y si algo de la lista falta el build falla en vez de publicar
 *     una web a medias.
 *
 * La de AFTR tiene el suyo en aftr_web/armar.mjs, porque su proyecto de
 * Vercel tiene esa carpeta como raíz y no ve ésta.
 */
import { cp, mkdir, rm, writeFile, readFile, access } from 'node:fs/promises';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';

const raiz = join(dirname(fileURLToPath(import.meta.url)), '..');
const dist = join(raiz, 'dist');

// El index.html de la raíz carga dos archivos de aftr_web (social.css y
// social-core.js), así que van con su misma ruta.
const archivos = [
  'index.html', 'privacidad.html',
  'app.js', 'motion.js', 'relacionador.js', 'contabilidad.js',
  'reporte-escritorio.js', 'social-venue.js', 'sw.js',
  'styles.css', 'rediseno.css', 'social-venue.css',
  'manifest.webmanifest', 'icon.svg', 'icon-512.png',
  'aftr_web/social.css', 'aftr_web/social-core.js',
];

await rm(dist, { recursive: true, force: true });
await mkdir(dist, { recursive: true });

for (const f of archivos) {
  const desde = join(raiz, f);
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
  config = '/* Generado por tools/armar_web.mjs desde las variables del proyecto. */\n'
    + 'window.CONFIG = {\n'
    + `  SUPABASE_URL: ${JSON.stringify(url)},\n`
    + `  SUPABASE_ANON_KEY: ${JSON.stringify(key)}\n};\n`;
} else {
  // Despliegue a mano desde esta máquina: vale el config.js local.
  try {
    config = await readFile(join(raiz, 'config.js'), 'utf8');
    console.warn('sin SUPABASE_URL/SUPABASE_ANON_KEY: se usa el config.js local');
  } catch {
    console.error('no hay SUPABASE_URL ni SUPABASE_ANON_KEY, y tampoco config.js local:');
    console.error('la web saldría sin base. Cargá las variables en el proyecto de Vercel.');
    process.exit(1);
  }
}
await writeFile(join(dist, 'config.js'), config);
console.log('dist/ armado para Venue');
