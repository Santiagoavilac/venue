/* PULSE y mesas. Reutiliza sesión, RPC, modal y tema de AFTR. */
"use strict";
function pulseImporte(v) { const n=Number(v||0); return `${n<0?'-':''}${Math.trunc(Math.abs(n)/100)}.${String(Math.abs(n)%100).padStart(2,'0')}`; }
function pulseCentavos(s) { s=String(s).trim().replace(',','.');if(!/^\d{1,10}(\.\d{1,2})?$/.test(s))return null;const [a,b='']=s.split('.');return Number(a)*100+Number(b.padEnd(2,'0')); }
function fotoProducto(url) { try { const u=new URL(url);return u.protocol==='https:'?esc(u.href):''; } catch { return ''; } }
function escucharPulse(tablas,fn) {
 const uid=E.sesion?.user?.id;if(!uid)return;
 const canal=sb.channel(`aftr-pulse-${crypto.randomUUID()}`);let espera;
 for(const tabla of tablas)canal.on('postgres_changes',{event:'*',schema:'public',table:tabla,filter:`cliente_id=eq.${uid}`},()=>{clearTimeout(espera);espera=setTimeout(()=>fn().catch(e=>avisar(mensaje(e))),300);});
 canal.subscribe();limpiar=()=>{clearTimeout(espera);sb.removeChannel(canal);};
}
async function hojaMetodoPago(orden,titulo) {
 // El invitado no tiene PULSE y no puede recargarlo: ofrecérselo es ofrecerle
 // un botón que falla. Va derecho al QR del banco, que es lo que sí puede.
 if(esAnonimo())return hojaPago(orden,titulo);
 const c=abrirHoja(`<h2 class="fuerte">${esc(titulo)}</h2><p data-saldo>Consultando saldo…</p><button class="boton" data-pulse>Pagar con PULSE</button><button class="boton sec" data-qr style="margin-top:12px">Pagar con QR</button><a class="opcion" href="#/pulse" data-recargar>Recargar PULSE</a>`);
 rpc('aftr_pulse').then(s=>{if(c.isConnected)$('[data-saldo]',c).textContent=`Tu saldo: ${pulseImporte(s.saldo_centavos)} PULSE`;}).catch(()=>{$('[data-saldo]',c).textContent='Tu saldo se verifica al pagar.';});
 $('[data-pulse]',c).onclick=async()=>{const boton=$('[data-pulse]',c);boton.disabled=true;try{await rpc('aftr_pagar_pulse',{p_orden:orden});cerrarHoja();avisar('Compra confirmada. Revisá tus accesos.');await cargarAccesos();pintar();}catch(e){avisar(mensaje(e));}finally{boton.disabled=false;}};
 $('[data-qr]',c).onclick=()=>hojaPago(orden,titulo);
 $('[data-recargar]',c).onclick=cerrarHoja;
}
async function pintarPulse(iniciar=true) {
 if(!(await asegurarCuenta()))return;
 const s=await rpc('aftr_pulse');if(ruta().nombre!=='pulse')return;
 vista.innerHTML=`<div class="pagina pulse-pagina"><p class="etq">AFTR WALLET</p><h1 class="titular pulse-saldo">${pulseImporte(s.saldo_centavos)}</h1><p>PULSE</p><p class="suave">1 PULSE = Bs 1</p>
 <form id="recarga-pulse"><label for="importe-pulse">Importe en Bs</label><input id="importe-pulse" name="importe" inputmode="decimal" placeholder="100.00" required><p class="tenue" style="margin:6px 0 0;font-size:12px">Hasta Bs 300 por semana</p><button class="boton" type="submit">Recargar con QR</button></form>
 ${(s.recargas||[]).map(r=>`<button class="opcion" data-recarga="${esc(r.id)}">Recarga pendiente · ${pulseImporte(r.importe_centavos)} PULSE</button>`).join('')}
 <h2 class="fuerte">Movimientos</h2>${s.movimientos.length?s.movimientos.map(m=>`<div class="pulse-mov"><div>${esc(m.concepto)}<p class="tenue">${esc(new Date(m.created_at).toLocaleString())}</p></div><strong>${m.importe_centavos>0?'+':''}${pulseImporte(m.importe_centavos)}</strong></div>`).join(''):'<p class="suave">Todavía no tenés movimientos.</p>'}</div>`;
 let clave=crypto.randomUUID();$('#recarga-pulse').onsubmit=async ev=>{ev.preventDefault();const n=pulseCentavos($('#importe-pulse').value);if(n===null||n<100)return avisar('La recarga mínima es Bs 1. Usá hasta dos decimales.');const boton=$('button[type=submit]',ev.target);boton.disabled=true;try{const r=await rpc('aftr_recargar_pulse',{p_centavos:n,p_client_key:clave});clave=crypto.randomUUID();hojaPago(r.id,'Recarga PULSE','recarga');}catch(e){avisar(mensaje(e));}finally{boton.disabled=false;}};
 $$('[data-recarga]').forEach(b=>b.onclick=()=>hojaPago(b.dataset.recarga,'Recarga PULSE','recarga'));
 if(iniciar)escucharPulse(['pulse_cuentas','pulse_movimientos','pulse_recargas'],()=>pintarPulse(false));
}
async function pintarMisMesas(iniciar=true) {
 if(!(await asegurarCuenta()))return;
 const d=await rpc('aftr_mis_mesas');if(ruta().nombre!=='mis-mesas')return;
 vista.innerHTML=`<div class="pagina pulse-pagina"><h1 class="titular">Mis mesas</h1>${d.mesas.length?d.mesas.map(m=>`<section class="pulse-mesa"><h2 class="fuerte">${esc(m.etiqueta)}</h2><p>${esc(m.evento)} · ${esc(m.club)}</p><p class="suave">${esc(m.fecha)} · Planta ${esc(m.planta)}</p>
 ${m.mi_estado==='invitado'?`<button class="texto-accion" data-aceptar="${esc(m.id)}">Aceptar invitación</button><button class="texto-accion" data-declinar="${esc(m.id)}">Declinar</button>`:`<a class="boton sec" href="#/mi-mesa/${esc(m.id)}">Ver mi mesa</a>`}</section>`).join(''):'<p class="suave">Tus mesas e invitaciones aparecerán acá.</p>'}
 <h2 class="fuerte">Novedades</h2>${(d.avisos||[]).slice(0,10).map(a=>`<p class="suave">${esc(a.texto)}</p>`).join('')}</div>`;
 for(const [atributo,aceptar] of [['data-aceptar',true],['data-declinar',false]])$$(`[${atributo}]`).forEach(b=>b.onclick=async()=>{b.disabled=true;try{await rpc('aftr_mesa_responder',{p_mesa:b.getAttribute(atributo),p_aceptar:aceptar});await pintarMisMesas(false);}catch(e){avisar(mensaje(e));b.disabled=false;}});
 if(iniciar)escucharPulse(['aftr_mesa_miembros','aftr_avisos'],()=>pintarMisMesas(false));
}
const carritosMesa=new Map();
async function pintarMiMesa(id,iniciar=true) {
 if(!(await asegurarCuenta()))return;
 const [mis,carta,pedidos]=await Promise.all([rpc('aftr_mis_mesas'),rpc('aftr_carta_mesa',{p_mesa:id}),rpc('aftr_mis_pedidos_mesa',{p_mesa:id})]);
 if(ruta().nombre!=='mi-mesa'||ruta().id!==id)return;
 const m=mis.mesas.find(x=>x.id===id);if(!m)throw new Error('Esta mesa no está disponible.');
 if(!carritosMesa.has(id))carritosMesa.set(id,{items:{},nota:'',buscar:'',clave:crypto.randomUUID(),ocupado:false});const estado=carritosMesa.get(id);
 const render=()=>{
 const total=carta.productos.reduce((s,p)=>s+p.precio_centavos*(estado.items[p.id]||0),0);
 vista.innerHTML=`<div class="pagina pulse-pagina"><a class="texto-accion" href="#/mis-mesas">Mis mesas</a><h1 class="titular">${esc(m.etiqueta)}</h1><p>${esc(m.evento)} · ${esc(m.club)}</p><p class="suave">Planta ${esc(m.planta)} · Capacidad ${m.capacidad??'por configurar'}</p>
 ${m.titular?`<form id="invitar-mesa"><label for="invitado-mesa">Invitar cuenta AFTR</label><input id="invitado-mesa" placeholder="Usuario sin @" required><button class="texto-accion" type="submit">Invitar</button></form>${(m.miembros||[]).map(i=>`<div class="pulse-mov"><span>${esc(i.nombre)} · ${esc(i.estado)}</span><button class="texto-accion" data-retirar="${esc(i.cliente_id)}">Retirar</button></div>`).join('')}`:''}
 <h2 class="fuerte">Carta</h2><p class="suave">${carta.abierto?'Pedidos disponibles':'Pedidos no disponibles en este momento'}</p><input id="buscar-carta" aria-label="Buscar bebidas o tragos" placeholder="Buscar bebidas o tragos" value="${esc(estado.buscar)}">
 <div class="pulse-productos">${carta.productos.filter(p=>`${p.nombre} ${p.categoria}`.toLowerCase().includes(estado.buscar.toLowerCase())).map(p=>`<article><div class="pulse-foto">${fotoProducto(p.foto_url)?`<img loading="lazy" src="${fotoProducto(p.foto_url)}" alt="${esc(p.nombre)}">`:''}</div><h3>${esc(p.nombre)}</h3><p class="suave">${esc(p.presentacion)}</p><strong>Bs ${pulseImporte(p.precio_centavos)}</strong>
 ${p.disponibles>0?`<div class="pulse-cantidad"><button aria-label="Quitar ${esc(p.nombre)}" data-menos="${p.id}" ${estado.ocupado?'disabled':''}>−</button><span>${estado.items[p.id]||0}</span><button aria-label="Agregar ${esc(p.nombre)}" data-mas="${p.id}" ${!carta.abierto||estado.ocupado||(estado.items[p.id]||0)>=p.disponibles?'disabled':''}>+</button></div>`:'<p class="tenue">Agotado</p>'}</article>`).join('')}</div>
 ${total?`<section class="pulse-carrito"><h2 class="fuerte">Total · Bs ${pulseImporte(total)}</h2><label for="nota-pedido">Observaciones</label><input id="nota-pedido" maxlength="300" value="${esc(estado.nota)}"><button class="boton" data-comprar-pulse ${!carta.abierto||estado.ocupado?'disabled':''}>Comprar con PULSE</button><button class="boton sec" data-comprar-qr ${!carta.abierto||estado.ocupado?'disabled':''}>Pagar con QR</button><a class="texto-accion" href="#/pulse">Recargar PULSE</a></section>`:''}
 <h2 class="fuerte">Mis pedidos</h2>${pedidos.length?pedidos.map(p=>`<section class="pulse-mesa"><h3>${esc(p.estado.replaceAll('_',' '))}</h3>${(p.items||[]).map(i=>`<p>${i.qty} × ${esc(i.nombre)}</p>`).join('')}<p>Bs ${pulseImporte(p.total_centavos)} · ${esc(p.metodo.toUpperCase())}</p>${p.estado==='pendiente'?`<button class="texto-accion" data-pendiente="${esc(p.id)}">Continuar pago QR</button><button class="texto-accion" data-cancelar-pedido="${esc(p.id)}">Solicitar cancelación</button>`:''}</section>`).join(''):'<p class="suave">Todavía no hiciste pedidos.</p>'}</div>`;
 $('#buscar-carta').oninput=e=>{const pos=e.target.selectionStart;estado.buscar=e.target.value;render();$('#buscar-carta').focus();$('#buscar-carta').setSelectionRange(pos,pos);};
 $('#nota-pedido')?.addEventListener('input',e=>estado.nota=e.target.value);
 for(const [atributo,delta] of [['data-menos',-1],['data-mas',1]])$$(`[${atributo}]`).forEach(b=>b.onclick=()=>{const k=b.getAttribute(atributo);estado.items[k]=Math.max(0,(estado.items[k]||0)+delta);if(!estado.items[k])delete estado.items[k];estado.clave=crypto.randomUUID();render();});
 for(const [selector,metodo] of [['[data-comprar-pulse]','pulse'],['[data-comprar-qr]','qr']])$(selector)?.addEventListener('click',async()=>{if(estado.ocupado)return;estado.ocupado=true;render();try{const p=await rpc('aftr_pedir_mesa',{p_mesa:id,p_items:Object.entries(estado.items).map(([trago_id,qty])=>({trago_id,qty,revision:carta.productos.find(p=>p.id===trago_id)?.revision})),p_metodo:metodo,p_client_key:estado.clave,p_observaciones:estado.nota});estado.items={};estado.nota='';estado.clave=crypto.randomUUID();if(metodo==='qr')hojaPago(p.id,`Pedido · ${m.etiqueta}`,'pedido');else avisar('Pedido pagado y recibido por la barra.');}catch(e){avisar(mensaje(e));}finally{estado.ocupado=false;if(ruta().nombre==='mi-mesa'&&ruta().id===id)await pintarMiMesa(id,false);}});
 $$('[data-pendiente]').forEach(b=>b.onclick=()=>hojaPago(b.dataset.pendiente,'Pedido de bebidas','pedido'));
 $$('[data-cancelar-pedido]').forEach(b=>b.onclick=async()=>{try{await rpc('aftr_cancelar_cobro',{p_tipo:'pedido',p_id:b.dataset.cancelarPedido});avisar('Cancelación solicitada. La reserva se libera cuando el banco la confirme.');await pintarMiMesa(id,false);}catch(e){avisar(mensaje(e));}});
 $('#invitar-mesa')?.addEventListener('submit',async e=>{e.preventDefault();try{await rpc('aftr_mesa_invitar',{p_mesa:id,p_usuario:$('#invitado-mesa').value});await pintarMiMesa(id,false);}catch(err){avisar(mensaje(err));}});
 $$('[data-retirar]').forEach(b=>b.onclick=async()=>{try{await rpc('aftr_mesa_retirar',{p_mesa:id,p_cliente:b.dataset.retirar});await pintarMiMesa(id,false);}catch(e){avisar(mensaje(e));}});
 };render();if(iniciar)escucharPulse(['aftr_bar_pedidos','aftr_mesa_miembros','aftr_avisos'],()=>pintarMiMesa(id,false));
}
