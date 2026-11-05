import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import vm from 'node:vm';
import { fileURLToPath } from 'node:url';

const archivo = process.env.BANECO_WEB_SOURCE || fileURLToPath(new URL('../aftr_web/aftr.js', import.meta.url));
const fuente = readFileSync(archivo, 'utf8');
const codigo = fuente.slice(fuente.indexOf('async function cobroBanco('), fuente.indexOf('function hojaMesa('));
function escenario(invoke) {
  const c = { innerHTML: '' }, timers = [], llamadas = [], botones = new Map();
  let cerrar;
  const contexto = vm.createContext({
    sb: { functions: { invoke: async (_, p) => { llamadas.push(p.body); return await invoke(p.body); } } },
    abrirHoja: (html, cb) => { c.innerHTML = html; cerrar = cb; return c; },
    cerrarHoja: () => cerrar?.(),
    $: (selector) => { if (!botones.has(selector)) botones.set(selector, {}); return botones.get(selector); },
    esc: (s) => String(s ?? '').replaceAll('<','&lt;'), mensaje: (e) => e.message,
    listo: (a,b) => a+' '+b, ligarListo: () => {}, cargarAccesos: () => Promise.resolve(), location: {},
    setTimeout: (cb, ms) => { const t = { cb, ms }; timers.push(t); return t; },
    clearTimeout: (t) => { if(t) t.cancelado=true; },
  });
  vm.runInContext(codigo, contexto);
  contexto.hojaPago('orden', 'Evento');
  return { c, timers, llamadas, cerrar: () => cerrar?.() };
}
const tick = () => new Promise(setImmediate);
const qr = { data: { pago: { estado: 'activo', imagen: 'aW1hZ2Vu', monto: 25.5, vence: '2026-11-01' } } };
test('la web solicita el QR sin enviar un importe del cliente', async () => {
  const s=escenario(async()=>qr); await tick();
  assert.deepEqual(JSON.parse(JSON.stringify(s.llamadas)),[{accion:'qr',orden:'orden',tipo:'orden'}]);
  assert.match(s.c.innerHTML,/Bs 25.50/); assert.match(s.c.innerHTML,/Guardar QR/); assert.equal(s.timers[0].ms,4000);
});
test('revisión no muestra QR pagable ni un éxito', async () => {
  const s=escenario(async()=>({data:{pago:{estado:'revisar',monto:25.5}}})); await tick();
  assert.match(s.c.innerHTML,/Tu pago no se pudo entregar/); assert.doesNotMatch(s.c.innerHTML,/Guardar QR|Pago confirmado/);
});
test('el pago fuera de plazo lo dice y ofrece el WhatsApp de soporte', async () => {
  const s=escenario(async()=>({data:{pago:{estado:'revisar',monto:25.5,nota:'PAGADO_FUERA_DE_PLAZO'}}})); await tick();
  assert.match(s.c.innerHTML,/Tu pago llegó tarde/);
  assert.match(s.c.innerHTML,/diez minutos/);
  assert.match(s.c.innerHTML,/wa\.me\/59175028040/);
  assert.doesNotMatch(s.c.innerHTML,/Guardar QR/);
});
test('la consulta siguiente se agenda recién al terminar la anterior', async () => {
  let liberar;
  const s=escenario(async(p)=>p.accion==='qr'?qr:await new Promise(r=>liberar=r)); await tick();
  const esperando=s.timers[0].cb(); await tick();
  assert.equal(s.llamadas.length,2); assert.equal(s.timers.length,1);
  liberar({data:{pago:{estado:'activo'},orden:'pendiente'}}); await esperando;
  assert.equal(s.timers.length,2);
});
test('cerrar la hoja cancela el seguimiento', async () => {
  const s=escenario(async()=>qr); await tick(); s.cerrar();
  assert.equal(s.timers[0].cancelado,true);
  await s.timers[0].cb(); assert.equal(s.llamadas.length,1);
});
test('la web exige pago y orden confirmados para mostrar éxito', async () => {
  const s=escenario(async(p)=>p.accion==='qr'?qr:{data:{pago:{estado:'pagado'},orden:'confirmada'}});
  await tick(); await s.timers[0].cb(); assert.match(s.c.innerHTML,/Pago confirmado/);
});
test('un error conserva el acceso al pedido sin generar otra compra', async () => {
  const s=escenario(async()=>({error:new Error('fallo simulado')})); await tick();
  assert.match(s.c.innerHTML,/pedido quedó guardado/); assert.equal(s.llamadas.length,1);
});
