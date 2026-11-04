/* El enlace del relacionador es lo único que ata una compra de AFTR a su
   comisión. Si el validador de ?ref= rechaza un código, la venta se atribuye
   a nadie y no hay error visible, así que se prueba sobre el archivo real. */
import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';

/* Se extrae el bloque REF de aftr.js y se evalúa tal cual está escrito: así
   la prueba falla si alguien cambia la expresión regular en el archivo. */
function leerRef() {
  const src = readFileSync(new URL('../aftr_web/aftr.js', import.meta.url), 'utf8');
  const m = src.match(/const REF = \(\(\) => \{[\s\S]*?\n\}\)\(\);/);
  assert.ok(m, 'no se encontró el bloque REF en aftr_web/aftr.js');
  return m[0];
}

function conUrl(busqueda) {
  const guardado = {};
  const cuerpo = leerRef().replace('const REF =', 'globalThis.__REF =');
  const fn = new Function('location', 'sessionStorage', 'URLSearchParams', cuerpo + '\nreturn globalThis.__REF;');
  return fn({search: busqueda}, {
    getItem: k => (k in guardado ? guardado[k] : null),
    setItem: (k, v) => { guardado[k] = v; },
  }, URLSearchParams);
}

test('acepta el enlace con nombre del relacionador', () => {
  assert.equal(conUrl('?ref=genjiro-sasamoto'), 'genjiro-sasamoto');
  assert.equal(conUrl('?ref=analia-lopez'), 'analia-lopez');
  assert.equal(conUrl('?ref=rolando-franco-2'), 'rolando-franco-2');
});

test('sigue aceptando los enlaces viejos con ?r= y código aleatorio', () => {
  assert.equal(conUrl('?r=a3f91c2d'), 'a3f91c2d');
});

test('normaliza a minúsculas para que coincida con ref_code', () => {
  assert.equal(conUrl('?ref=Genjiro-Sasamoto'), 'genjiro-sasamoto');
});

test('descarta lo que no puede ser un código', () => {
  for (const malo of ['?ref=ab', '?ref=-malo-', '?ref=mal--doble', '?ref=con%20espacio', '?ref=' + 'x'.repeat(61)]) {
    assert.equal(conUrl(malo), null, `debería rechazar ${malo}`);
  }
  assert.equal(conUrl(''), null);
});

test('?ref= tiene prioridad sobre el ?r= viejo', () => {
  assert.equal(conUrl('?r=a3f91c2d&ref=genjiro-sasamoto'), 'genjiro-sasamoto');
});
