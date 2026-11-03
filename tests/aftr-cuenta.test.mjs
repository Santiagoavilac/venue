import test from 'node:test';
import assert from 'node:assert/strict';
import vm from 'node:vm';
import {readFileSync} from 'node:fs';
function entorno() {
  const texto = {textContent:''};
  const saldo = {hidden:true, setAttribute(){}};
  const E = {sesion:{user:{id:'uno'}},perfil:{nombre:'Uno'}};
  const canal = {on(){return this;},subscribe(){}};
  const c = vm.createContext({
    E, console, setTimeout, clearTimeout,
    document:{addEventListener(){},body:{classList:{toggle(){}}}},
    window:{addEventListener(){}},
    $:sel=>sel==='span'?texto:saldo,
    esc:s=>String(s??''),
    sb:{channel:()=>canal,removeChannel(){},storage:{from:()=>({createSignedUrl:async()=>({data:{signedUrl:'https://example.invalid/foto-firmada'},error:null})})}},
    rpc:async()=>({saldo_centavos:12345}),
  });
  vm.runInContext(readFileSync(new URL('../aftr_web/pulse.js',import.meta.url),'utf8'),c);
  vm.runInContext(readFileSync(new URL('../aftr_web/cuenta-ui.js',import.meta.url),'utf8'),c);
  return {c,E,texto,saldo};
}
test('saldo: conserva centavos y responde a una nueva consulta', async()=>{
  const {c,texto}=entorno();
  await c.actualizarSaldoFijo(); assert.equal(texto.textContent,'123.45 PULSE');
  c.rpc=async()=>({saldo_centavos:29}); await c.actualizarSaldoFijo(); assert.equal(texto.textContent,'0.29 PULSE');
});
test('saldo: ignora respuestas atrasadas de otra cuenta', async()=>{
  const {c,E,texto}=entorno(); let resolver;
  c.rpc=()=>new Promise(r=>resolver=r);
  const pendiente=c.actualizarSaldoFijo(); E.sesion={user:{id:'dos'}};
  resolver({saldo_centavos:99999}); await pendiente; assert.equal(texto.textContent,'');
});
test('saldo: la respuesta más reciente prevalece y al salir se oculta',async()=>{
  const {c,E,texto,saldo}=entorno(); const resolver=[];
  c.rpc=()=>new Promise(r=>resolver.push(r));
  const a=c.actualizarSaldoFijo(), b=c.actualizarSaldoFijo();
  resolver[1]({saldo_centavos:200}); await b;
  resolver[0]({saldo_centavos:100}); await a;
  assert.equal(texto.textContent,'2.00 PULSE');
  E.sesion=null; E.perfil=null; c.iniciarSaldoFijo(); assert.equal(saldo.hidden,true);
});
test('foto privada: resuelve una URL firmada y conserva el perfil si falla',async()=>{
  const {c}=entorno(); const p={nombre:'Demo',foto_archivo:'uno/foto.jpg'};
  await c.resolverFotoPerfil(p); assert.equal(p.foto_url,'https://example.invalid/foto-firmada');
  c.sb.storage.from=()=>({createSignedUrl:async()=>({error:new Error('red')})});
  await c.resolverFotoPerfil(p); assert.equal(p.nombre,'Demo'); assert.equal(p.foto_url,'https://example.invalid/foto-firmada');
  p.foto_archivo='uno/otra-foto.jpg';
  await c.resolverFotoPerfil(p); assert.equal(p.foto_url,null);
});
