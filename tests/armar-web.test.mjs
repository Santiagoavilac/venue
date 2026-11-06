/* Que lo que se publica tenga todo lo que el HTML pide.
 *
 * Qué se rompía: las webs se publicaban subiendo la carpeta entera, así que
 * nadie se enteraba si faltaba un archivo. Ahora tools/armar_web.mjs y
 * aftr_web/armar.mjs copian una lista escrita a mano, y una lista escrita a
 * mano se queda vieja: se agrega un .js al index.html, nadie lo suma a la
 * lista y la web sale sin él. Esto compara las dos cosas.
 */
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { execFileSync } from 'node:child_process';
import { readFileSync, existsSync, readdirSync } from 'node:fs';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';

const raiz = join(dirname(fileURLToPath(import.meta.url)), '..');

// Las referencias locales de un HTML: sin protocolo, sin ancla, sin ruta de ruteo.
function referencias(html) {
  return [...html.matchAll(/(?:src|href)="([^"]+)"/g)]
    .map((m) => m[1])
    .filter((r) => !/^(https?:|\/\/|#|mailto:|data:)/.test(r))
    .map((r) => r.replace(/^\//, '').split(/[?#]/)[0])
    .filter((r) => r !== '');
}

const webs = [
  {
    nombre: 'Venue',
    correr: ['node', ['tools/armar_web.mjs'], raiz],
    dist: join(raiz, 'dist'),
    paginas: ['index.html'],
  },
  {
    nombre: 'AFTR',
    correr: ['node', ['armar.mjs'], join(raiz, 'aftr_web')],
    dist: join(raiz, 'aftr_web', 'dist'),
    paginas: ['index.html', 'terminos.html', 'privacidad.html', 'normas.html'],
  },
];

for (const web of webs) {
  test(`${web.nombre}: lo que se publica tiene todo lo que el HTML pide`, () => {
    const [cmd, args, cwd] = web.correr;
    execFileSync(cmd, args, {
      cwd,
      // Como en Vercel: el config.js sale de las variables, no del archivo local.
      env: { ...process.env, SUPABASE_URL: 'https://p.supabase.co', SUPABASE_ANON_KEY: 'x' },
    });

    for (const pagina of web.paginas) {
      const html = readFileSync(join(web.dist, pagina), 'utf8');
      for (const ref of referencias(html)) {
        // Las rutas sin extensión las resuelve cleanUrls contra el .html.
        const candidatos = /\.[a-z0-9]+$/i.test(ref) ? [ref] : [ref, `${ref}.html`];
        assert.ok(
          candidatos.some((c) => existsSync(join(web.dist, c))),
          `${web.nombre}: ${pagina} carga ${ref} y no se publica. ` +
            'Agregalo a la lista del armador.',
        );
      }
    }
  });

  test(`${web.nombre}: el config.js publicado sale de las variables`, () => {
    const config = readFileSync(join(web.dist, 'config.js'), 'utf8');
    assert.match(config, /SUPABASE_URL:\s*"https:\/\/p\.supabase\.co"/);
    assert.match(config, /SUPABASE_ANON_KEY:\s*"x"/);
  });

  test(`${web.nombre}: no se publica nada del repo que no sea la web`, () => {
    const afuera = ['db', 'docs', 'supabase', 'tests', 'venue_mobile', 'aftr_mobile',
                    'CLAUDE.md', '.env.local', 'vercel.json', 'package.json'];
    const hay = readdirSync(web.dist);
    for (const nombre of afuera) {
      assert.ok(!hay.includes(nombre), `${web.nombre}: se publicaría ${nombre}`);
    }
  });
}
