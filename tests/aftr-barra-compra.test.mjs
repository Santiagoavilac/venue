import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';

/* La barra de "Comprar" tapaba el final de la pantalla del evento.
 *
 * Qué se rompía: #vista reserva abajo el alto de la barra de pestañas
 * (--tabs), pero en un evento las pestañas se esconden y aparece la barra de
 * compra, que es más alta. En escritorio --tabs vale 0, así que la página
 * reservaba 40 px contra una barra de 83: el bloque "Dónde" quedaba abajo de
 * la barra y no había manera de bajar hasta él.
 *
 * Estas pruebas no pueden medir píxeles sin un navegador, pero sí que las dos
 * piezas del arreglo sigan ahí: la regla que reserva el alto de la barra y el
 * medidor que lo calcula. Si alguien borra una de las dos, el bug vuelve y
 * nadie se entera hasta que lo ve en el teléfono.
 */
const css = readFileSync(new URL('../aftr_web/aftr.css', import.meta.url), 'utf8');
const js = readFileSync(new URL('../aftr_web/aftr.js', import.meta.url), 'utf8');

test('con la barra de compra, la página reserva su alto y no el de las pestañas', () => {
  const regla = css.match(/body\.con-compra\s+#vista\s*\{[^}]*\}/);
  assert.ok(regla, 'desapareció la regla que reserva el alto de la barra de compra');
  assert.match(regla[0], /padding-bottom/);
  assert.match(regla[0], /--alto-compra/);
  assert.ok(!/--tabs/.test(regla[0]),
    'vuelve a reservar el alto de las pestañas, que en esa pantalla están escondidas');
});

test('el alto de la barra se mide, no se escribe a mano', () => {
  assert.match(js, /function medirBarraCompra\(\)/);
  assert.match(js, /setProperty\("--alto-compra"/);
  assert.match(js, /\.barra-compra/);
  // y se vuelve a medir si la barra cambia de alto
  assert.match(js, /ResizeObserver/);
});

test('se mide al entrar al evento y se limpia al salir', () => {
  // al entrar: junto con la clase que muestra la barra
  assert.match(js, /classList\.add\("con-compra"\);\s*\n\s*medirBarraCompra\(\);/);
  // al salir: pintar() quita la clase y vuelve a medir, que borra la variable
  assert.match(js, /classList\.remove\("con-compra"\);\s*\n\s*medirBarraCompra\(\);/);
  assert.match(js, /removeProperty\("--alto-compra"\)/);
});
