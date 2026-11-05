/* Cuenta, saldo persistente y guía. Las fotos se guardan en un bucket privado. */
'use strict';
const fotosFirmadasPerfil = new Map();
async function resolverFotoPerfil(perfil) {
  if (!perfil?.foto_archivo) return;
  try {
    const previa=fotosFirmadasPerfil.get(perfil.foto_archivo);
    if(previa&&previa.vence>Date.now()){perfil.foto_url=previa.url;return;}
    const {data, error} = await sb.storage.from('aftr-perfiles').createSignedUrl(perfil.foto_archivo, 3600);
    if(!error)fotosFirmadasPerfil.set(perfil.foto_archivo,{url:data.signedUrl,vence:Date.now()+3000000});
    perfil.foto_url = error ? null : data.signedUrl;
  } catch { perfil.foto_url = null; }
}
function fotoPerfilHtml(perfil) {
  const url = fotoProducto(perfil?.foto_url);
  return url ? `<img src="${url}" alt="" referrerpolicy="no-referrer">` : esc((perfil?.nombre || '?').slice(0, 1).toUpperCase());
}

let saldoCanal = null, saldoUid = null, saldoEspera = null, saldoVersion = 0;
async function actualizarSaldoFijo() {
  const uid = E.sesion?.user.id, version = ++saldoVersion;
  const el = $('#saldo-fijo');
  if (!uid || !E.perfil) return;
  try {
    const s = await rpc('aftr_pulse');
    if (version === saldoVersion && E.sesion?.user.id === uid) {
      $('span', el).textContent = `${pulseImporte(s.saldo_centavos)} PULSE`;
      el.setAttribute('aria-label', `${pulseImporte(s.saldo_centavos)} PULSE, saldo y recargas`);
    }
  } catch {
    if (version === saldoVersion && E.sesion?.user.id === uid) $('span', el).textContent = 'PULSE · Reintentar';
  }
}
function iniciarSaldoFijo() {
  const uid = E.perfil ? E.sesion?.user.id : null;
  $('#saldo-fijo').hidden = !uid;
  document.body.classList.toggle('con-saldo', !!uid);
  if (saldoUid === uid) return;
  saldoVersion++;
  if (saldoCanal) sb.removeChannel(saldoCanal);
  saldoCanal = null; saldoUid = uid;
  clearTimeout(saldoEspera);
  if (!uid) { $('span', $('#saldo-fijo')).textContent = 'PULSE · …'; return; }
  $('span', $('#saldo-fijo')).textContent = 'PULSE · …';
  actualizarSaldoFijo();
  saldoCanal = sb.channel(`aftr-saldo-fijo-${uid}`);
  for (const table of ['pulse_cuentas', 'pulse_movimientos']) {
    saldoCanal.on('postgres_changes', {event: '*', schema: 'public', table, filter: `cliente_id=eq.${uid}`}, () => {
      clearTimeout(saldoEspera); saldoEspera = setTimeout(actualizarSaldoFijo, 200);
    });
  }
  saldoCanal.subscribe(estado => { if (estado === 'SUBSCRIBED') actualizarSaldoFijo(); });
}
document.addEventListener('visibilitychange', () => { if (!document.hidden && saldoUid) actualizarSaldoFijo(); });
window.addEventListener('focus', () => { if (saldoUid) actualizarSaldoFijo(); });

async function fotoOptimizada(file) {
  if (!file || !['image/jpeg','image/png','image/webp','image/heic','image/heif'].includes(file.type)) throw new Error('Elegí una foto JPG, PNG o WebP.');
  if (file.size > 20 * 1024 * 1024) throw new Error('Elegí una foto de menos de 20 MB.');
  const url = URL.createObjectURL(file);
  try {
    const im = new Image(); im.src = url; await im.decode();
    const escala = Math.min(1, 800 / Math.max(im.naturalWidth, im.naturalHeight));
    const canvas = document.createElement('canvas');
    canvas.width = Math.max(1, Math.round(im.naturalWidth * escala));
    canvas.height = Math.max(1, Math.round(im.naturalHeight * escala));
    const ctx = canvas.getContext('2d'); ctx.fillStyle = '#ffffff'; ctx.fillRect(0,0,canvas.width,canvas.height); ctx.drawImage(im,0,0,canvas.width,canvas.height);
    const blob = await new Promise(resolve => canvas.toBlob(resolve, 'image/jpeg', .82));
    if (!blob || blob.size > 2 * 1024 * 1024) throw new Error('La foto debe pesar menos de 2 MB.');
    return blob;
  } catch (e) {
    if (e.message?.includes('2 MB')) throw e;
    throw new Error('No se pudo abrir esa foto. Probá con un archivo JPG o PNG.');
  } finally { URL.revokeObjectURL(url); }
}
async function editarFotoWeb() {
  if (!await asegurarCuenta()) return;
  const perfil = E.perfil, uid = E.sesion.user.id;
  const c = abrirHoja(`<h2 class="fuerte">Foto de perfil</h2><div class="foto-preview avatar">${fotoPerfilHtml(perfil)}</div>
    <label class="opcion foto-elegir">Elegir de mis fotos<input type="file" accept="image/*" hidden data-archivo></label>
    ${perfil.foto_archivo || perfil.foto_url ? '<button class="opcion" data-quitar>Quitar foto</button>' : ''}
    <p data-error role="status"></p><button class="boton" data-guardar hidden>Guardar foto</button>`);
  let blob = null, preview = null, ocupado = false;
  const limpiarPreview = () => { if (preview) URL.revokeObjectURL(preview); preview = null; };
  alCerrarHoja = limpiarPreview;
  $('[data-archivo]',c).onchange = async ev => {
    const f = ev.target.files[0]; if (!f || ocupado) return;
    $('[data-error]',c).textContent = '';
    try {
      blob = await fotoOptimizada(f); limpiarPreview(); preview = URL.createObjectURL(blob);
      $('.foto-preview',c).innerHTML = `<img src="${preview}" alt="Vista previa de tu foto">`;
      $('[data-guardar]',c).hidden = false;
    } catch(e) { $('[data-error]',c).textContent = mensaje(e); }
  };
  async function guardar(quitar) {
    if (ocupado || E.sesion?.user.id !== uid || (!quitar && !blob)) return;
    ocupado = true;
    let ruta = null, confirmado = false;
    $$('button,input',c).forEach(b=>b.disabled=true);
    $('[data-error]',c).textContent = 'Guardando…';
    try {
      if (!quitar) {
        ruta = `${uid}/${crypto.randomUUID()}.jpg`;
        const {error} = await sb.storage.from('aftr-perfiles').upload(ruta,blob,{contentType:'image/jpeg',cacheControl:'3600'});
        if (error) throw error;
        // Los bytes los mira el servidor: la foto se le muestra ahora a
        // cualquier visitante sin cuenta, y storage no revisa el contenido.
        const {data:rev,error:er} = await sb.functions.invoke('historias-media',{body:{accion:'revisar',bucket:'aftr-perfiles',path:ruta}});
        if (er || rev?.error) throw new Error(rev?.error || 'Elegí una foto JPG, PNG o WebP.');
      }
      await rpc('aftr_cambiar_foto',{p_archivo:ruta}); confirmado = true;
      if (perfil.foto_archivo?.startsWith(`${uid}/`)) await sb.storage.from('aftr-perfiles').remove([perfil.foto_archivo]).catch(()=>{});
      await cargarPerfil(); cerrarHoja(); if (rutaActualCuenta()) pintarCuenta();
    } catch(e) {
      if (ruta && !confirmado) await sb.storage.from('aftr-perfiles').remove([ruta]).catch(()=>{});
      if (c.isConnected) $('[data-error]',c).textContent = mensaje(e);
    } finally { ocupado=false; if(c.isConnected) $$('button,input',c).forEach(b=>b.disabled=false); }
  }
  $('[data-guardar]',c).onclick = () => guardar(false);
  $('[data-quitar]',c)?.addEventListener('click',()=>guardar(true));
}
function rutaActualCuenta() { return ruta().nombre === 'cuenta'; }

let guiaActual = null;
const guiasOfrecidas = new Set();
function ofrecerGuia() {
  const uid = E.sesion?.user.id;
  if (!uid || !E.perfil || guiaActual || guiasOfrecidas.has(uid)) return;
  try { if (localStorage.getItem(`aftr.guia.v1.${uid}`)) return; } catch {}
  guiasOfrecidas.add(uid);
  // El splash se quita al terminar su animación; no se monta la guía debajo.
  const splash = $('#splash');
  if (splash) {
    const obs = new MutationObserver(() => { if (!splash.isConnected) { obs.disconnect(); if(E.sesion?.user.id===uid) abrirGuiaAftr(); } });
    obs.observe(document.body,{childList:true});
  } else abrirGuiaAftr();
}
function abrirGuiaAftr() {
  if (!E.perfil || !E.sesion || guiaActual) return;
  cerrarHoja();
  const uid = E.sesion.user.id, anterior = document.activeElement;
  const d = document.createElement('div'); d.className='guia-aftr';
  d.setAttribute('role','dialog'); d.setAttribute('aria-modal','true'); d.setAttribute('aria-labelledby','guia-titulo');
  document.body.append(d); guiaActual=d;
  let paso=0;
  const pasos=[
    ['Descubrir','Buscá eventos por fecha y abrí uno para ver entradas, listas y mesas.','descubrir','#/'],
    ['Mapa','Encontrá los lugares y eventos cerca tuyo.','mapa','#/mapa'],
    ['Accesos y mesas','Tus entradas y QR quedan acá. Desde Mi mesa podés ver la carta y seguir tus pedidos.','accesos','#/accesos'],
    ['Tu saldo PULSE','Tu saldo queda siempre a la vista. Tocá acá para recargar o ver tus movimientos. También podés pagar con QR directo.','pulse','#/accesos'],
    ['Cuenta','Cambiá tu foto, consultá tus guardados o volvé a ver esta guía desde Cuenta.','cuenta','#/cuenta'],
  ];
  function posicionar() {
    const destino=pasos[paso][2];
    const el=destino==='pulse'?$('#saldo-fijo'):destino==='cuenta'&&innerWidth>=900?$('#avatar'):$(innerWidth>=900?`.nav-escritorio [data-tab="${destino}"]`:`#tabs [data-tab="${destino}"]`);
    const r=el?.getBoundingClientRect(), tarjeta=$('.guia-tarjeta',d), foco=$('.guia-foco',d);
    if (!r || !r.width) { foco.hidden=true; tarjeta.style.top='25%'; tarjeta.style.bottom='auto'; return; }
    Object.assign(foco.style,{left:`${r.left-3}px`,top:`${r.top-3}px`,width:`${r.width+6}px`,height:`${r.height+6}px`}); foco.hidden=false;
    const abajo=r.top>innerHeight/2;
    Object.assign(tarjeta.style,{top:abajo?'auto':`${r.bottom+16}px`,bottom:abajo?`${innerHeight-r.top+16}px`:'auto'});
  }
  function cerrar() {
    try { localStorage.setItem(`aftr.guia.v1.${uid}`,'1'); } catch {}
    d.remove(); guiaActual=null; window.removeEventListener('resize',posicionar); document.removeEventListener('keydown',tecla);
    if(anterior?.isConnected) anterior.focus();
  }
  let versionGuia=0;
  function mostrar() {
    const version=++versionGuia;
    const anteriorTarjeta=$('.guia-tarjeta',d)?.style.cssText;
    const anteriorFoco=$('.guia-foco',d)?.style.cssText;
    const p=pasos[paso];
    location.hash=p[3];
    d.innerHTML=`<div class="guia-foco"></div><section class="guia-tarjeta"><div class="guia-arriba"><span>${paso+1} de ${pasos.length}</span><button data-omitir>Omitir</button></div>
      <h2 id="guia-titulo">${p[0]}</h2><p>${p[1]}</p><div class="guia-acciones">${paso?'<button data-atras>Atrás</button>':''}<button data-siguiente>${paso===pasos.length-1?'Empezar':'Siguiente'}</button></div></section>`;
    if(anteriorTarjeta)$('.guia-tarjeta',d).style.cssText=anteriorTarjeta;
    if(anteriorFoco)$('.guia-foco',d).style.cssText=anteriorFoco;
    $('[data-omitir]',d).onclick=cerrar;
    $('[data-atras]',d)?.addEventListener('click',()=>{paso--;mostrar();});
    $('[data-siguiente]',d).onclick=()=>{if(paso===pasos.length-1)cerrar();else{paso++;mostrar();}};
    requestAnimationFrame(()=>requestAnimationFrame(()=>{if(version===versionGuia&&d.isConnected)posicionar();})); $('[data-siguiente]',d).focus();
  }
  function tecla(e) {
    if(e.key==='Escape'){e.preventDefault();cerrar();}
    if(e.key==='Tab'){
      const botones=$$('button',d), primero=botones[0], ultimo=botones.at(-1);
      if(e.shiftKey&&document.activeElement===primero){e.preventDefault();ultimo.focus();}
      else if(!e.shiftKey&&document.activeElement===ultimo){e.preventDefault();primero.focus();}
    }
  }
  d.addEventListener('cerrar-guia',cerrar,{once:true});
  document.addEventListener('keydown',tecla); window.addEventListener('resize',posicionar); mostrar();
}
