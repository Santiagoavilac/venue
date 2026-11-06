import test from 'node:test';
import assert from 'node:assert/strict';
import vm from 'node:vm';
import {readFileSync} from 'node:fs';

/* Comprar sin cuenta, sin que lo demás se le ofrezca al invitado.
 *
 * Qué se rompía: quien compra sin cuenta tiene una sesión anónima con perfil,
 * y las pantallas sólo preguntaban `if (!E.sesion)`. Con eso el invitado
 * entraba a PULSE, a mesas y al método de pago con PULSE, y el servidor
 * -que sí lo rechaza, impl.aftr_cuenta_real- contestaba un error crudo en vez
 * de una pantalla que diga qué hacer. Estas pruebas son de que la puerta esté
 * del lado del cliente también, para que el invitado no vea botones que
 * fallan.
 */
function entorno({anonimo, conPerfil = true} = {}) {
  const pasos = [];
  const texto = {textContent: ''};
  const saldo = {hidden: false, setAttribute() {}};
  const E = {
    sesion: {user: {id: 'uno', is_anonymous: anonimo}},
    perfil: conPerfil ? {nombre: 'Uno', usuario: 'uno'} : null,
  };
  const canal = {on() { return this; }, subscribe() {}};
  const c = vm.createContext({
    E, console, setTimeout, clearTimeout, Promise,
    crypto: {randomUUID: () => 'clave'},
    document: {addEventListener() {}, body: {classList: {toggle() {}}}},
    window: {addEventListener() {}},
    $: (sel) => (sel === 'span' ? texto : saldo),
    $$: () => [],
    esc: (s) => String(s ?? ''),
    sb: {channel: () => canal, removeChannel() {}},
    // lo define aftr.js, que en el navegador ya está cargado cuando esto corre
    esAnonimo: () => E.sesion?.user?.is_anonymous === true,
    rpc: async (f) => { pasos.push(['rpc', f]); return {saldo_centavos: 100, movimientos: []}; },
    avisar: (t) => pasos.push(['avisar', t]),
    mensaje: (e) => String(e?.message ?? e),
    ruta: () => ({nombre: 'pulse'}),
    vista: {innerHTML: ''},
    abrirHoja: (html) => { pasos.push(['abrirHoja', html]); return {isConnected: true}; },
    cerrarHoja() { pasos.push(['cerrarHoja']); },
    hojaPago: (...a) => pasos.push(['hojaPago', ...a]),
    pulseImporte: (n) => String(n),
    // asegurarCuenta de verdad vive en aftr.js; acá se reproduce su respuesta:
    // al invitado le dice que no y le abre el ingreso
    asegurarCuenta: async () => {
      if (E.sesion?.user?.is_anonymous) { pasos.push(['abrirIngreso']); return false; }
      return true;
    },
  });
  vm.runInContext(readFileSync(new URL('../aftr_web/pulse.js', import.meta.url), 'utf8'), c);
  vm.runInContext(readFileSync(new URL('../aftr_web/cuenta-ui.js', import.meta.url), 'utf8'), c);
  return {c, E, pasos, saldo};
}

test('al invitado no se le muestra el acceso fijo a PULSE', () => {
  const invitado = entorno({anonimo: true});
  invitado.c.iniciarSaldoFijo();
  assert.equal(invitado.saldo.hidden, true, 'el invitado vería un PULSE que no puede usar');

  const conCuenta = entorno({anonimo: false});
  conCuenta.c.iniciarSaldoFijo();
  assert.equal(conCuenta.saldo.hidden, false, 'a quien tiene cuenta no se le puede esconder');
});

test('PULSE no se abre para el invitado: se le pide cuenta', async () => {
  const {c, pasos} = entorno({anonimo: true});
  await c.pintarPulse();
  assert.deepEqual(pasos, [['abrirIngreso']]);
  assert.ok(!pasos.some(([k, f]) => k === 'rpc' && f === 'aftr_pulse'),
    'se llamó a aftr_pulse con una sesión anónima');
});

test('mis mesas tampoco: es de lo que necesita cuenta', async () => {
  const {c, pasos} = entorno({anonimo: true});
  await c.pintarMisMesas();
  assert.deepEqual(pasos, [['abrirIngreso']]);
});

test('con cuenta, PULSE se abre como siempre', async () => {
  const {c, pasos} = entorno({anonimo: false});
  await c.pintarPulse(false);
  assert.ok(pasos.some(([k, f]) => k === 'rpc' && f === 'aftr_pulse'));
});

test('al invitado el pago va derecho al QR, sin ofrecerle PULSE', async () => {
  const {c, pasos} = entorno({anonimo: true});
  await c.hojaMetodoPago('orden-1', 'Noche de jueves');
  assert.deepEqual(pasos, [['hojaPago', 'orden-1', 'Noche de jueves']]);
  assert.ok(!pasos.some(([k]) => k === 'abrirHoja'),
    'se le ofreció pagar con PULSE a alguien que no tiene PULSE');
});

test('con cuenta, el pago sigue ofreciendo PULSE y QR', async () => {
  const {c, pasos} = entorno({anonimo: false});
  await c.hojaMetodoPago('orden-1', 'Noche de jueves');
  const hoja = pasos.find(([k]) => k === 'abrirHoja');
  assert.ok(hoja, 'desapareció la elección de método de pago');
  assert.match(hoja[1], /Pagar con PULSE/);
  assert.match(hoja[1], /Pagar con QR/);
});
