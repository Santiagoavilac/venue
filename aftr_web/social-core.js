/* Historias y reventa: controles compartidos por las dos webs. La autorización y
 * cada transición de dinero/entradas se resuelven exclusivamente en las RPC. */
(function (root) {
  'use strict';
  const html = value => String(value ?? '').replace(/[&<>"']/g, c => ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
  function centavos(value) {
    const s = String(value).trim().replace(',', '.');
    if (!/^\d{1,8}(\.\d{1,2})?$/.test(s)) return null;
    const [a,b=''] = s.split('.'); const n = Number(a)*100+Number(b.padEnd(2,'0'));
    return Number.isSafeInteger(n) && n > 0 ? n : null;
  }
  const dinero = n => `Bs ${(Number(n || 0)/100).toLocaleString('es-BO',{minimumFractionDigits:2,maximumFractionDigits:2})}`;
  const etiquetas = {esperando_vendedor:'Esperando al vendedor',pendiente_pago:'Esperando pago',pago_informado:'Pago informado',completada:'Completada',cancelada:'Cancelada',vencida:'Vencida',en_disputa:'En disputa',publicada:'Publicada',reservada:'Reservada',retirada:'Retirada'};
  const estado = s => etiquetas[s] || String(s || '').replaceAll('_',' ');
  const fecha = d => d ? new Date(d).toLocaleString('es-BO',{day:'numeric',month:'short',hour:'2-digit',minute:'2-digit'}) : '';
  const nombre = x => typeof x === 'object' && x ? x.nombre || x.evento || '' : x || '';
  const restante = (hasta, ahora) => Math.max(0,Math.ceil((Date.parse(hasta)-ahora)/1000));
  const reloj = s => `${Math.floor(s/60).toString().padStart(2,'0')}:${(s%60).toString().padStart(2,'0')}`;
  /* La oferta en operación sigue a la vista: vuelve sola en minutos. Soltarla
     mientras se paga invitaría a dos pagos reales por la misma entrada. */
  const enPago = hasta => {
    const s = restante(hasta, Date.now());
    return s ? `En pago · vuelve en ${Math.ceil(s/60)} min` : 'En pago';
  };
  function agrupar(historias, ahora = Date.now()) {
    const grupos = new Map();
    for (const h of historias.filter(h => Date.parse(h.vence_at)>ahora).sort((a,b)=>Date.parse(a.created_at)-Date.parse(b.created_at))) {
      // `grupo` lo arma el servidor y no dice quién es el autor: sin sesión
      // autor_id ya no viaja, justamente para que no se puedan enumerar.
      const k = h.grupo || (h.identidad==='club' ? `club:${h.club_id}` : `${h.identidad}:${h.autor_id}`);
      if (!grupos.has(k)) grupos.set(k,[]); grupos.get(k).push(h);
    }
    return [...grupos.values()];
  }
  function create(op) {
    const sb = op.client;
    let pageClean = null, modalClean = null, dialog = null, feedRefresh = null, serverOffset = 0;
    const q = (s,r=document) => r.querySelector(s);
    const qa = (s,r=document) => [...r.querySelectorAll(s)];
    const now = () => Date.now()+serverOffset;
    const uid = () => op.user()?.id || null;
    const notify = e => op.notice(typeof e==='string' ? e : e?.message || 'No se pudo completar. Revisá la conexión y reintentá.');
    async function rpc(fn, accion, datos={}) {
      const {data,error} = await sb.rpc(fn,{p_accion:accion,p_datos:datos});
      if (error) throw error;
      if (data?.ahora) serverOffset=Date.parse(data.ahora)-Date.now();
      return data;
    }
    const stories = (a,d) => rpc('aftr_historias',a,d);
    const resale = (a,d) => rpc('aftr_reventa',a,d);
    const auth = async () => uid() ? true : await op.login?.();
    function close() {
      modalClean?.();modalClean=null;
      if (dialog) { dialog.close(); dialog.remove(); dialog=null; }
    }
    function modal(title, content='', wide=false) {
      close();
      dialog=document.createElement('dialog');dialog.className=`social social-dialog${wide?' social-wide':''}`;
      dialog.innerHTML=`<header class="so-modal-head"><div><span class="so-eyebrow">${op.staff?'VENUE / AFTR':'AFTR'}</span><h2>${html(title)}</h2></div><button type="button" class="so-icon" data-so-close aria-label="Cerrar">×</button></header><div class="so-modal-body">${content}</div>`;
      document.body.append(dialog);const d=dialog;
      q('[data-so-close]',d).onclick=close;
      d.addEventListener('cancel',e=>{e.preventDefault();close();});
      d.addEventListener('click',e=>{if(e.target===d){const r=d.getBoundingClientRect();if(e.clientX<r.left||e.clientX>r.right||e.clientY<r.top||e.clientY>r.bottom)close();}});
      d.showModal();return q('.so-modal-body',d);
    }
    function bind(container, selector, fn) {
      qa(selector,container).forEach(b=>b.addEventListener('click',async e=>{
        if(b.disabled)return;b.disabled=true;
        try {await fn(b,e);}catch(error){notify(error);}finally{if(b.isConnected)b.disabled=false;}
      }));
    }
    function watch(tables, fn, periodic=0) {
      let disposed=false, timer, running=false, again=false;
      async function refresh(){if(disposed)return;if(running){again=true;return;}running=true;try{await fn();}catch(e){if(!disposed)notify(e);}finally{running=false;if(again&&!disposed){again=false;void refresh();}}}
      const channel=sb.channel(`social-${crypto.randomUUID()}`);
      for(const t of tables)channel.on('postgres_changes',{event:'*',schema:'public',table:t},()=>{clearTimeout(timer);timer=setTimeout(refresh,180);});
      channel.subscribe(status=>{if(status==='SUBSCRIBED')void refresh();});
      const visible=()=>{if(document.visibilityState==='visible')void refresh();};
      document.addEventListener('visibilitychange',visible);window.addEventListener('online',visible);
      const poll=periodic?setInterval(refresh,periodic):null;
      return ()=>{disposed=true;clearTimeout(timer);clearInterval(poll);document.removeEventListener('visibilitychange',visible);window.removeEventListener('online',visible);sb.removeChannel(channel);};
    }
    async function sign(bucket,path,ttl=60) {
      if(!path)return null;
      const {data,error}=await sb.storage.from(bucket).createSignedUrl(path,ttl);if(error)throw error;return data.signedUrl;
    }
    /* Las claves opacas se cambian por URL firmadas en el servidor, todas
       juntas. Antes se firmaba de a una contra storage -una llamada por
       historia y otra por foto de perfil-, y el visitante sin cuenta no podía
       firmar nada: la política de lectura llama a es_platform_admin(), que anon
       no puede ejecutar, así que las historias no se veían sin entrar.
       La URL se guarda hasta el 80 % de su plazo, para volver a firmar antes de
       que se venza; sólo se guardan los éxitos, porque antes una firma fallida
       quedaba cacheada para siempre y ni después de loguearte reintentaba. */
    const firmadas = new Map();
    let juntando = null, pendientes = new Set();
    function firmar(clave) {
      if(!clave)return Promise.resolve(null);
      const guardada = firmadas.get(clave);
      if(guardada && guardada.hasta > Date.now())return Promise.resolve(guardada.url);
      firmadas.delete(clave);
      pendientes.add(clave);
      juntando ||= new Promise(listo => setTimeout(async () => {
        const claves = [...pendientes].slice(0,60);
        pendientes = new Set([...pendientes].slice(60));
        juntando = null;
        try {
          const {data} = await sb.functions.invoke('historias-media',{body:{accion:'firmar',claves}});
          const plazo = Number(data?.vence_en || 600)*800;
          for(const [k,url] of Object.entries(data?.urls || {})) firmadas.set(k,{url,hasta:Date.now()+plazo});
        } catch { /* sin firma: se reintenta la próxima vez que se pida */ }
        listo();
      },40));
      return juntando.then(() => firmadas.get(clave)?.url ?? null);
    }
    async function upload(file,bucket,validar=false) {
      if(!file)throw new Error('Elegí un archivo.');
      if(file.size>(validar?30:8)*1024*1024)throw new Error(`El archivo supera ${validar?30:8} MB.`);
      const allowed=validar?['image/jpeg','image/png','image/webp','video/mp4','video/quicktime']:['image/jpeg','image/png','image/webp'];
      if(!allowed.includes(file.type))throw new Error('Formato no compatible. Usá JPG, PNG, WebP o video MP4/MOV.');
      const extension=({'image/jpeg':'jpg','image/png':'png','image/webp':'webp','video/mp4':'mp4','video/quicktime':'mov'})[file.type];
      const path=`${uid()}/${crypto.randomUUID()}.${extension}`;
      const {error}=await sb.storage.from(bucket).upload(path,file,{contentType:file.type,upsert:false});if(error)throw error;
      // El servidor mira los bytes, no el content-type que declaró el cliente:
      // storage acepta cualquier contenido con que digas image/jpeg. Para las
      // historias valida y registra; para los comprobantes sólo valida, y
      // borra el objeto si no es una imagen de verdad.
      const cuerpo=validar?{path}:{accion:'revisar',bucket,path};
      try {const {data,error:e}=await sb.functions.invoke('historias-media',{body:cuerpo});if(e)throw new Error(e.context ? 'No se pudo validar el archivo. Revisá que el video no supere 30 segundos.' : e.message);if(data?.error)throw new Error(data.error);}
      catch(e){await sb.storage.from(bucket).remove([path]);throw e;}
      return path;
    }
    // La foto de perfil del autor de una historia. Viene como URL (logo del
    // boliche) o como ruta del bucket privado, que se firma una sola vez por
    // ruta y se reusa en todo el feed.
    const fotosDeAutor=new Map();
    function fotoDeAutor(h) {
      if(h?.foto)return Promise.resolve(h.foto);
      if(h?.foto_key)return firmar(h.foto_key);
      const ruta=h?.foto_archivo;if(!ruta)return Promise.resolve(null);
      if(!fotosDeAutor.has(ruta))fotosDeAutor.set(ruta,sign('aftr-perfiles',ruta,3600).catch(()=>null));
      return fotosDeAutor.get(ruta);
    }
    // Pinta la foto sobre el círculo donde ya está la inicial: si no hay foto o
    // falla la firma, la inicial queda como estaba.
    async function pintarFoto(el,h) {
      if(!el)return;
      const url=await fotoDeAutor(h);
      if(!url||!el.isConnected)return;
      el.style.backgroundImage=`url("${encodeURI(url)}")`;el.classList.add('so-con-foto');
    }
    const errorBox = (text,action='Reintentar') => `<div class="so-empty"><span class="so-empty-icon">↻</span><p>${html(text)}</p><button class="so-btn so-secondary" data-retry>${action}</button></div>`;
    const heading = (over,title,sub='') => `<div class="so-heading"><span class="so-eyebrow">${html(over)}</span><h1>${html(title)}</h1>${sub?`<p>${html(sub)}</p>`:''}</div>`;
    const cardOrder = o => `<button type="button" class="so-order-card" data-order="${html(o.id)}"><div><span class="so-state ${html(o.estado)}">${html(estado(o.estado))}</span><h3>${html(nombre(o.evento))}</h3><small>${html(o.vendedor||o.comprador||fecha(o.created_at))}</small></div><div><strong>${dinero(o.precio_centavos)}</strong><span>Ver operación ↗</span></div></button>`;
    /* Firma y deja decodificada una historia. Devuelve la URL o null: así
       quien la llama decide, en vez de abrir un visor vacío. */
    async function preparar(h) {
      try {
        const url=h?.media_key?await firmar(h.media_key):await sign('aftr-historias',h?.storage_path);
        if(!url)return null;
        if(h.tipo!=='video')await new Promise((listo,falla)=>{
          const i=new Image();i.onload=()=>listo();i.onerror=falla;i.src=url;
        });
        return url;
      } catch { return null; }
    }
    // Las dos que siguen, mientras se mira la actual. Los videos también: con
    // preload="auto" el navegador empieza a bajarlo sin que se vea.
    function precargar(grupos,gi,si) {
      let g=gi,i=si;
      for(let n=0;n<2;n++){
        const grupo=grupos[g];if(!grupo)return;
        if(i+1<grupo.length){i++;}else{g++;i=0;}
        const h=grupos[g]?.[i];if(!h)return;
        void (async()=>{
          const url=await preparar(h);
          if(url&&h.tipo==='video'){const v=document.createElement('video');v.preload='auto';v.src=url;}
        })();
      }
    }
    async function mountFeed(container) {
      if(!container)return;
      const refresh=async()=>{
        if(!container.isConnected)return;
        try {
          const d=await stories('feed');if(!container.isConnected)return;
          const groups=agrupar(d.historias||[],now());
          container.innerHTML=`<div class="social so-feed"><button type="button" class="so-story-add" data-create-story><span>+</span><small>Tu historia</small></button>${groups.map((g,i)=>`<button type="button" class="so-story-author" data-group="${i}"><span class="so-ring"><span>${html((g[0].nombre||g[0].autor||'?').slice(0,2).toUpperCase())}</span></span><small>${html(g[0].nombre||g[0].autor)}</small>${g[0].identidad!=='usuario'?`<i>${g[0].identidad==='club'?'Boliche':'RRPP'}</i>`:''}</button>`).join('')}${!groups.length?'<p class="so-feed-empty">La noche empieza acá.<br><span>Compartí tu primera historia.</span></p>':''}</div>`;
          bind(container,'[data-create-story]',async()=>{if(await auth())await composer();});
          // No se abre el visor hasta que la primera historia está lista:
          // antes se abría con un "Cargando historia…" y ahí adentro firmaba
          // y descargaba, que es la parte que se siente lenta.
          bind(container,'[data-group]',async b=>{
            if(b.dataset.cargando)return;
            b.dataset.cargando='1';b.classList.add('so-cargando');
            try {
              const url=await preparar(groups[Number(b.dataset.group)][0]);
              if(!url){notify('No pudimos abrir esta historia. Probá de nuevo.');return;}
              viewer(groups,Number(b.dataset.group),url);
            } finally { delete b.dataset.cargando;b.classList.remove('so-cargando'); }
          });
          container.querySelectorAll('[data-group]').forEach(b=>void pintarFoto(b.querySelector('.so-ring>span'),groups[Number(b.dataset.group)][0]));
        }catch(e){if(container.isConnected){container.innerHTML=`<div class="social so-feed-error">Historias no disponibles <button data-retry>Reintentar</button></div>`;bind(container,'[data-retry]',refresh);}}
      };
      feedRefresh=refresh;await refresh();
      pageClean?.();pageClean=watch(['aftr_historias'],refresh,30000);
    }
    async function viewer(groups,gi=0,urlInicial=null) {
      const box=modal('Historias','',true);const d=dialog;d.classList.add('so-viewer-dialog');
      let si=0,frame,loadVersion=0,progress=0,last=0,held=false,buffering=true,disposed=false,video=null,startX=0,startY=0,pressAt=0;
      let current=null;
      const stop=()=>{disposed=true;cancelAnimationFrame(frame);video?.pause();document.removeEventListener('visibilitychange',visibility);d.removeEventListener('keydown',keys);};
      modalClean=stop;
      const paused=()=>held||buffering||document.hidden;
      const visibility=()=>{if(document.hidden)video?.pause();else if(!held&&!buffering)video?.play().catch(()=>{});last=performance.now();};
      const keys=e=>{if(e.key==='ArrowRight'){e.preventDefault();next();}if(e.key==='ArrowLeft'){e.preventDefault();prev();}};
      document.addEventListener('visibilitychange',visibility);d.addEventListener('keydown',keys);
      function next(){if(si+1<groups[gi].length){si++;void draw();}else if(gi+1<groups.length){gi++;si=0;void draw();}else close();}
      function prev(){if(progress>0.15){void draw();return;}if(si>0){si--;void draw();}else if(gi>0){gi--;si=groups[gi].length-1;void draw();}}
      async function draw(){
        const version=++loadVersion;cancelAnimationFrame(frame);video?.pause();video=null;progress=0;buffering=true;last=performance.now();
        current=groups[gi]?.[si];if(!current){close();return;}
        if(Date.parse(current.vence_at)<=now()){notify('Esta historia ya venció.');next();return;}
        box.innerHTML=`<div class="so-story-stage"><div class="so-story-media"></div><div class="so-story-top"><div class="so-segments">${groups[gi].map((_,i)=>`<span><i style="transform:scaleX(${i<si?1:0})" data-segment="${i}"></i></span>`).join('')}</div><div class="so-story-id"><span class="so-avatar">${html((current.nombre||current.autor||'?').slice(0,2))}</span><div><strong>${html(current.nombre||current.autor)}</strong><small>${html(fecha(current.created_at))}</small></div><button type="button" class="so-icon" data-story-pause aria-label="Pausar historia">Ⅱ</button>${current.tipo==='video'?'<button type="button" class="so-icon" data-sound aria-label="Activar sonido">♫</button>':''}<button type="button" class="so-icon" data-story-menu aria-label="Opciones de historia">⋯</button></div></div><div class="so-story-foot">${current.evento_id?`<p>${html(nombre(current.evento))}</p>`:''}${current.cta?`<button class="so-btn" data-story-cta>${current.cta==='mesa'?'Reservar mesa':'Comprar entradas'} ↗</button>`:''}</div></div>`;
        const stage=q('.so-story-stage',box);const media=q('.so-story-media',box);
        void pintarFoto(q('.so-avatar',box),current);
        bind(box,'[data-story-pause]',b=>{held=!held;b.textContent=held?'▶':'Ⅱ';if(video){if(held)video.pause();else video.play().catch(()=>{});}});
        bind(box,'[data-sound]',b=>{if(video){video.muted=!video.muted;b.textContent=video.muted?'♫':'♪';b.setAttribute('aria-label',video.muted?'Activar sonido':'Silenciar');}});
        bind(box,'[data-story-menu]',async()=>{
          held=true;video?.pause();
          if(uid()===current.autor_id||op.canModerate?.(current)){
            if(confirm('¿Retirar esta historia?')){await stories('retirar',{id:current.id});notify('Historia retirada.');close();await feedRefresh?.();return;}
          }else if(await auth()){
            const motivo=prompt('¿Por qué querés reportar esta historia?');if(motivo?.trim()){await stories('reportar',{id:current.id,motivo:motivo.trim()});notify('Reporte enviado a AFTR.');}
          }
          held=false;if(video)video.play().catch(()=>{});
        });
        bind(box,'[data-story-cta]',async()=>{const h=current;close();await op.storyCTA?.(h);});
        stage.addEventListener('pointerdown',e=>{if(e.target.closest('button'))return;pressAt=performance.now();startX=e.clientX;startY=e.clientY;held=true;video?.pause();stage.setPointerCapture(e.pointerId);});
        stage.addEventListener('pointerup',e=>{if(e.target.closest('button'))return;held=false;const dx=e.clientX-startX,dy=e.clientY-startY;if(Math.abs(dy)>90&&dy>0){close();return;}if(Math.abs(dx)>65){dx<0?next():prev();return;}if(performance.now()-pressAt<220){e.clientX<stage.getBoundingClientRect().left+stage.clientWidth*.35?prev():next();return;}video?.play().catch(()=>{});});
        stage.addEventListener('pointercancel',()=>{held=false;video?.play().catch(()=>{});});
        try {
          // la primera ya viene lista del círculo; las que siguen, de la precarga
          const url=(version===1&&urlInicial)||(current.media_key ? await firmar(current.media_key) : await sign('aftr-historias',current.storage_path));
          if(disposed||version!==loadVersion)return;
          if(!url)throw new Error('No pudimos abrir esta historia.');
          if(current.tipo==='video'){
            video=document.createElement('video');video.src=url;video.playsInline=true;video.muted=true;video.preload='auto';
            video.addEventListener('waiting',()=>buffering=true);video.addEventListener('playing',()=>{buffering=false;last=performance.now();});
            video.addEventListener('ended',next);video.addEventListener('error',()=>failed());
            media.replaceChildren(video);await video.play().catch(()=>{buffering=true;const b=document.createElement('button');b.className='so-btn so-play';b.textContent='Reproducir';b.onclick=()=>{b.remove();video.play().catch(notify);};media.append(b);});
          }else{
            const image=new Image();image.alt=`Historia de ${current.nombre||current.autor}`;image.onload=()=>{if(version===loadVersion){buffering=false;last=performance.now();}};image.onerror=failed;image.src=url;media.replaceChildren(image);
          }
          frame=requestAnimationFrame(tick);
          precargar(groups,gi,si);
        }catch(e){if(!disposed&&version===loadVersion)failed();}
      }
      function failed(){buffering=true;const m=q('.so-story-media',box);if(m){m.innerHTML=errorBox('No se pudo cargar esta historia.');bind(m,'[data-retry]',draw);}}
      function tick(t){if(disposed)return;const delta=Math.min(t-last,250);last=t;if(Date.parse(current.vence_at)<=now()){next();return;}
        if(!paused()){progress=video&&Number.isFinite(video.duration)&&video.duration>0?Math.min(1,video.currentTime/video.duration):progress+delta/5000;const segment=q(`[data-segment="${si}"]`,box);if(segment)segment.style.transform=`scaleX(${Math.min(1,progress)})`;if(progress>=1){next();return;}}
        frame=requestAnimationFrame(tick);
      }
      await draw();
    }
    async function composer() {
      if(!(await auth()))return;
      const events=await op.events();
      const clubId=op.club?.();
      const identity=op.staff?(op.identity?.()||'rrpp'):'usuario';
      const box=modal('Una historia para esta noche',`<p class="so-muted">Visible durante 24 horas. Fotos, videos de hasta 30 segundos o el arte de tu evento.</p><form data-story-form class="so-form"><label>Contenido<input type="file" accept="image/jpeg,image/png,image/webp,video/mp4,video/quicktime" data-media></label><div data-preview class="so-preview" hidden></div><label>Evento<select name="evento_id"><option value="">Sin evento</option>${events.map(e=>`<option value="${html(e.id)}">${html(e.nombre||e.evento)}</option>`).join('')}</select></label><button type="button" class="so-link" data-use-art>Usar arte del evento</button><label>Botón<select name="cta"><option value="">Sin botón</option><option value="entrada">Comprar entradas</option><option value="mesa">Reservar mesa</option></select></label><p class="so-muted">Publicás ${identity==='club'?'como boliche':identity==='rrpp'?'como relacionador':'con tu perfil AFTR'}. ${identity==='rrpp'?'Las compras iniciadas desde tu historia se atribuyen a tu cuenta.':''}</p><div class="so-form-error" role="alert" data-form-error></div><button class="so-btn" type="submit">Publicar historia</button><button type="button" class="so-link" data-mine-stories>Mis historias</button></form>`);
      const form=q('form',box);let selected=null,objectURL=null,uploaded=null;
      function preview(file){if(objectURL)URL.revokeObjectURL(objectURL);selected=file;uploaded=null;objectURL=URL.createObjectURL(file);const p=q('[data-preview]',box);p.hidden=false;p.innerHTML=file.type.startsWith('video/')?`<video controls playsinline src="${html(objectURL)}"></video>`:`<img src="${html(objectURL)}" alt="Vista previa">`;}
      modalClean=()=>{if(objectURL)URL.revokeObjectURL(objectURL);q('video',box)?.pause();};
      q('[data-media]',box).onchange=e=>{const file=e.target.files[0];if(file)preview(file);};
      bind(box,'[data-use-art]',async()=>{const e=events.find(e=>e.id===form.elements.evento_id.value);const url=e?.flyer||e?.flyer_url;if(!url)throw new Error('Elegí un evento con arte disponible.');const res=await fetch(url);if(!res.ok)throw new Error('No se pudo cargar el arte. Seleccionalo desde tu galería.');const blob=await res.blob();preview(new File([blob],'arte.jpg',{type:blob.type||'image/jpeg'}));});
      bind(box,'[data-mine-stories]',mineStories);
      form.onsubmit=async e=>{e.preventDefault();const b=q('[type=submit]',form);if(b.disabled)return;b.disabled=true;q('[data-form-error]',box).textContent='';
        try {if(!selected)throw new Error('Elegí una foto, un video o el arte del evento.');if(selected.type.startsWith('video/')){const v=q('video',box);if(!Number.isFinite(v.duration)||v.duration>30.05)throw new Error('El video debe durar como máximo 30 segundos.');}
          const evento=form.elements.evento_id.value;const cta=form.elements.cta.value;if(cta&&!evento)throw new Error('Elegí un evento para agregar un botón.');
          uploaded ||= await upload(selected,'aftr-historias',true);
          await stories('publicar',{identidad:identity,club_id:clubId||undefined,storage_path:uploaded,evento_id:evento||null,cta:cta||null});close();notify('Tu historia está publicada por 24 horas.');await feedRefresh?.();
        }catch(err){q('[data-form-error]',box).textContent=err.message||'No se pudo publicar.';}finally{if(b.isConnected)b.disabled=false;}
      };
    }
    async function mineStories() {
      if(!(await auth()))return;
      const box=modal(op.staff?'Historias del boliche':'Tus historias','<p class="so-muted">Cargando historias…</p>');
      const load=async()=>{const d=await stories(op.staff?'gestion':'mias',op.club?.()?{club_id:op.club()}:{});if(!box.isConnected)return;
        box.innerHTML=`<div class="so-toolbar"><p class="so-muted">Las historias vencen a las 24 horas.</p><button class="so-btn so-small" data-create>Crear historia</button></div>${(d.historias||[]).map(h=>`<article class="so-panel"><span class="so-eyebrow">${html(h.identidad)}</span><h3>${html(h.nombre||h.autor)}</h3><p>${html(nombre(h.evento))}</p><small>${html(fecha(h.created_at))} · ${Date.parse(h.vence_at)>now()?'Vence '+html(fecha(h.vence_at)):'Vencida'}</small><div class="so-actions"><button class="so-link" data-view="${html(h.id)}">Ver</button><button class="so-link so-danger" data-remove="${html(h.id)}">Retirar</button></div></article>`).join('')||'<div class="so-empty"><p>Todavía no publicaste historias.</p></div>'}${(d.reportes||[]).length?`<h3>Reportes</h3>${d.reportes.map(r=>`<article class="so-panel"><p>${html(r.motivo)}</p><small>${html(fecha(r.created_at))}</small><button class="so-link so-danger" data-remove="${html(r.historia_id)}">Retirar historia reportada</button></article>`).join('')}`:''}`;
        bind(box,'[data-create]',composer);bind(box,'[data-view]',b=>viewer([[d.historias.find(h=>h.id===b.dataset.view)]]));bind(box,'[data-remove]',async b=>{if(confirm('¿Retirar esta historia?')){await stories('retirar',{id:b.dataset.remove});await load();await feedRefresh?.();}});
      };await load();
    }
    async function market(container,eventoId=null) {
      cleanup();let generation=0;
      const load=async()=>{const v=++generation;
        const d=await resale('mercado',eventoId?{evento_id:eventoId}:{});if(v!==generation||!container.isConnected)return;
        container.innerHTML=`<div class="social so-page">${heading('REVENTA OFICIAL','La noche cambia de manos','Entradas verificadas. Pagás al vendedor y recibís un QR nuevo al confirmarse la operación.')}<div class="so-toolbar"><a href="#/" class="so-link">← Descubrir</a><button class="so-btn so-secondary so-small" data-mine>Mis operaciones</button></div><div class="so-market-grid">${(d.ofertas||[]).map(o=>`<article class="so-offer"><div class="so-offer-top"><span class="so-eyebrow">${html(nombre(o.club))}</span><span class="so-verified">✓ Entrada oficial</span></div><h2>${html(nombre(o.evento))}</h2><p>${html(o.fecha?fecha(o.fecha):'')}</p><div class="so-offer-bottom"><div><small>${html(o.vendedor)}</small><strong>${dinero(o.precio_centavos)}</strong></div>${o.estado==='reservada'?`<span class="so-state reservada">${html(enPago(o.vuelve_at))}</span>`:`<button class="so-btn so-small" data-buy="${html(o.id)}">Comprar ↗</button>`}</div></article>`).join('')||'<div class="so-empty"><span class="so-empty-icon">↗</span><h3>Todo listo para la próxima oportunidad</h3><p>No hay entradas publicadas para este evento en este momento.</p></div>'}</div></div>`;
        bind(container,'[data-mine]',mineResale);
        bind(container,'[data-buy]',async b=>{if(!(await auth()))return;if(!confirm('Se le pide la entrada al vendedor. Cuando acepte vas a ver sus datos de cobro y tenés unos minutos para pagarle. ¿Enviar el pedido?'))return;const o=await resale('comprar',{oferta_id:b.dataset.buy,client_key:crypto.randomUUID()});await order(o.id);await load();});
      };
      container.innerHTML=`<div class="social so-page">${heading('REVENTA OFICIAL','Buscando tu próxima noche')}<div class="so-loading">Cargando entradas…</div></div>`;
      try{await load();pageClean=watch(['aftr_reventa_ofertas','aftr_reventa_ordenes'],load,30000);}catch(e){container.innerHTML=`<div class="social so-page">${errorBox(e.message)}</div>`;bind(container,'[data-retry]',()=>market(container,eventoId));}
    }
    async function mineResale() {
      if(!(await auth()))return;
      const box=modal('Tus operaciones','<div class="so-loading">Cargando…</div>');
      const load=async()=>{const d=await resale('mias');if(!box.isConnected)return;
        box.innerHTML=`<div class="so-toolbar"><p class="so-muted">El historial queda guardado en tu cuenta.</p><button class="so-btn so-small" data-sell>Vender una entrada</button></div>${d.ordenes?.length?`<h3>Operaciones</h3>${d.ordenes.map(cardOrder).join('')}`:'<div class="so-empty"><p>Todavía no tenés operaciones.</p></div>'}${d.ofertas?.length?`<h3>Tus publicaciones</h3>${d.ofertas.map(o=>`<article class="so-panel"><span class="so-state ${html(o.estado)}">${html(estado(o.estado))}</span><h3>${html(nombre(o.evento))}</h3><strong>${dinero(o.precio_centavos)}</strong>${o.estado==='publicada'?`<button class="so-link so-danger" data-cancel-offer="${html(o.id)}">Retirar de la venta</button>`:''}</article>`).join('')}`:''}`;
        bind(box,'[data-order]',b=>order(b.dataset.order));bind(box,'[data-sell]',()=>sell(d.entradas||[]));bind(box,'[data-cancel-offer]',async b=>{if(confirm('¿Retirar la publicación y desbloquear tu entrada?')){await resale('cancelar',{oferta_id:b.dataset.cancelOffer});await load();op.walletRefresh?.();}});
      };
      await load();modalClean=watch(['aftr_reventa_ordenes','aftr_reventa_ofertas'],load,30000);
    }
    async function sell(entries=null,selectedId=null) {
      if(!(await auth()))return;
      if(!entries)entries=(await resale('mias')).entradas||[];
      const box=modal('Vendé tu entrada',`<p class="so-muted">Al publicarla, tu entrada queda bloqueada para ingreso y transferencias. Podés retirarla mientras nadie la haya reservado.</p>${!entries.length?'<div class="so-empty"><p>No tenés entradas habilitadas para reventa. El boliche debe permitirla y la entrada debe estar pagada y sin uso.</p></div>':`<form class="so-form" data-sell-form><label>Entrada<select name="entrada_id">${entries.map(e=>`<option value="${html(e.id)}" ${e.id===selectedId?'selected':''}>${html(nombre(e.evento))} · ${html(e.code||e.id.slice(0,8))}</option>`).join('')}</select></label><label>Precio de venta (Bs)<input name="precio" inputmode="decimal" placeholder="100.00" required></label><h3>¿Dónde te pagan?</h3><label>Titular de la cuenta<input name="titular" autocomplete="name" maxlength="100" required></label><label>Banco<input name="banco" maxlength="100" required></label><label>Número de cuenta (opcional si adjuntás tu QR)<input name="cuenta" inputmode="numeric" maxlength="60"></label><label>QR de cobro<input type="file" data-bank-qr accept="image/jpeg,image/png,image/webp"></label><p class="so-muted">Los datos de cobro se muestran únicamente al comprador que reserve la entrada. AFTR no cobra comisión por esta reventa.</p><label class="so-check"><input type="checkbox" required> Entiendo que debo confirmar el dinero recibido para entregar la entrada.</label><div class="so-form-error" role="alert" data-error></div><button class="so-btn">Publicar entrada</button></form>`}`);
      if(!entries.length)return;
      const form=q('form',box),key=crypto.randomUUID();let qrPath=null;
      q('[data-bank-qr]',box).onchange=()=>qrPath=null;
      form.onsubmit=async e=>{e.preventDefault();const b=q('button',form);if(b.disabled)return;b.disabled=true;
        try {const price=centavos(form.elements.precio.value);if(price===null)throw new Error('Ingresá un precio válido con hasta dos decimales.');const f=q('[data-bank-qr]',form).files[0];
          // con el QR adjunto ya hay cómo pagar: el número de cuenta solo es
          // obligatorio cuando no hay QR
          if(!form.elements.cuenta.value.trim()&&!f&&!qrPath)throw new Error('Poné el número de cuenta o adjuntá tu QR de cobro.');
          if(f&&!qrPath)qrPath=await upload(f,'aftr-p2p');
          await resale('publicar',{entrada_id:form.elements.entrada_id.value,precio_centavos:price,metodo:{titular:form.elements.titular.value.trim(),banco:form.elements.banco.value.trim(),cuenta:form.elements.cuenta.value.trim(),qr_path:qrPath},client_key:key});notify('Entrada publicada. El QR está bloqueado mientras esté en venta.');await op.walletRefresh?.();await mineResale();
        }catch(err){q('[data-error]',form).textContent=err.message;}finally{if(b.isConnected)b.disabled=false;}
      };
    }
    async function proof(box,o) {
      const form=document.createElement('form');form.className='so-form so-payment-proof';
      form.innerHTML='<h3>Informar el pago</h3><p class="so-muted">Comprobá el titular y el importe antes de pagar. Un comprobante no confirma la recepción del dinero.</p><label>Referencia de transferencia<input name="referencia" maxlength="120" required></label><label>Comprobante<input name="archivo" type="file" accept="image/jpeg,image/png,image/webp" required></label><div class="so-form-error" role="alert"></div><button class="so-btn">Ya pagué, enviar comprobante</button>';
      box.append(form);let path=null;form.elements.archivo.onchange=()=>path=null;
      form.onsubmit=async e=>{e.preventDefault();const b=q('button',form);if(b.disabled)return;b.disabled=true;
        try {path ||= await upload(form.elements.archivo.files[0],'aftr-p2p');await resale('informar_pago',{id:o.id,comprobante_path:path,referencia:form.elements.referencia.value.trim()});notify('Pago informado. El vendedor debe confirmar la recepción.');await order(o.id);}
        catch(err){q('[role=alert]',form).textContent=err.message;}finally{if(b.isConnected)b.disabled=false;}
      };
    }
    async function order(id) {
      const box=modal('Operación P2P','<div class="so-loading">Consultando operación…</div>');let record,expiryTimer,refreshing=false;
      const load=async()=>{if(refreshing||!box.isConnected)return;refreshing=true;try{
        const o=await resale('orden',{id});record=o;if(!box.isConnected)return;
        const buyer=uid()===o.comprador_id,seller=uid()===o.vendedor_id,active=['esperando_vendedor','pendiente_pago','pago_informado','en_disputa'].includes(o.estado);
        const espera=o.estado==='esperando_vendedor';
        box.innerHTML=`<div class="so-order-hero"><span class="so-state ${html(o.estado)}">${html(estado(o.estado))}</span><h2>${html(nombre(o.evento))}</h2><strong>${dinero(o.precio_centavos)}</strong><p class="so-muted">Operación ${html(o.id.slice(0,8))}</p>${['esperando_vendedor','pendiente_pago','pago_informado'].includes(o.estado)?`<div class="so-countdown"><span>${espera?'Tiempo del vendedor para responder':o.estado==='pendiente_pago'?'Tiempo para pagar':'Tiempo para confirmar recepción'}</span><b data-countdown></b></div>`:''}</div>
          ${o.estado==='completada'?`<div class="so-callout so-success">${buyer?'Tu entrada nueva ya está en Accesos. El QR anterior quedó invalidado.':'La entrada fue entregada con un QR nuevo.'}</div>`:''}
          ${['vencida','cancelada'].includes(o.estado)?'<div class="so-callout">El plazo terminó. No realices una transferencia. Si ya pagaste, abrí una disputa.</div>':''}
          ${espera?`<div class="so-callout">${buyer?'El vendedor tiene que aceptar antes de que veas sus datos de cobro. No transfieras nada todavía.':'Alguien quiere tu entrada. Si aceptás, se le muestran tus datos de cobro y tiene unos minutos para pagarte.'}</div>`:''}
          ${seller&&espera?'<div class="so-actions"><button class="so-btn" data-accept>Aceptar y mostrar mis datos</button><button class="so-link so-danger" data-reject>Rechazar el pedido</button></div>':''}
          ${o.estado==='en_disputa'?'<div class="so-callout">La entrada permanece bloqueada. Solo la administración de AFTR puede resolver esta disputa. Adjuntá los datos necesarios en el historial.</div>':''}
          ${o.metodo?`<section class="so-panel"><span class="so-eyebrow">${buyer?'PAGÁ DIRECTAMENTE AL VENDEDOR':'DATOS DE COBRO'}</span><dl><dt>Titular</dt><dd>${html(o.metodo.titular)}</dd><dt>Banco</dt><dd>${html(o.metodo.banco)}</dd>${o.metodo.cuenta?`<dt>Cuenta</dt><dd>${html(o.metodo.cuenta)}</dd>`:''}</dl>${o.metodo.qr_path?'<button class="so-btn so-secondary" data-bank-image>Ver QR de cobro</button>':''}</section>`:''}
          ${seller&&o.estado==='pago_informado'?'<p class="so-muted">Verificá el abono en tu banco. Confirmar entrega la entrada de forma definitiva.</p><button class="so-btn" data-confirm>Confirmar dinero recibido y entregar</button>':''}
          <div class="so-actions">${buyer&&['vencida','cancelada'].includes(o.estado)&&!o.resolucion?'<button class="so-link so-danger" data-dispute>Pagué fuera de plazo · Abrir disputa</button>':''}${(buyer&&['esperando_vendedor','pendiente_pago'].includes(o.estado))?'<button class="so-link so-danger" data-cancel>Cancelar operación</button>':''}${(buyer||seller)&&['pago_informado','pendiente_pago'].includes(o.estado)?'<button class="so-link" data-dispute>Abrir disputa</button>':''}${o.comprobante_path?'<button class="so-link" data-proof>Ver comprobante</button>':''}</div><div data-proof-form></div>
          <h3 class="so-section-title">Historial de la operación</h3><div class="so-timeline">${(o.historial||[]).map(h=>`<article><span class="so-timeline-dot"></span><div><small>${html(h.autor||'AFTR')} · ${html(fecha(h.created_at))}</small><p>${html(h.texto||estado(h.tipo))}</p>${h.archivo_path?`<button class="so-link" data-file="${html(h.archivo_path)}">Ver archivo adjunto</button>`:''}</div></article>`).join('')||'<p class="so-muted">Operación creada.</p>'}</div>${active&&(buyer||seller||o.puede_resolver)?'<form class="so-form" data-message-form><label>Agregar información<textarea name="texto" rows="2" maxlength="1000" required placeholder="Dejá un mensaje para los participantes y AFTR"></textarea></label><label>Archivo adjunto (opcional)<input name="archivo" type="file" accept="image/jpeg,image/png,image/webp"></label><button class="so-btn so-secondary">Enviar al historial</button></form>':''}
          ${o.puede_resolver&&o.estado==='en_disputa'?'<section class="so-panel so-admin-panel"><span class="so-eyebrow">ARBITRAJE AFTR</span><p>Verificá las pruebas antes de resolver. Cancelar no transfiere ni devuelve dinero.</p><form data-resolve class="so-form"><label>Resolución<select name="resolucion"><option value="entregar">Entregar entrada al comprador</option><option value="cancelar">Cancelar y devolver entrada al vendedor</option></select></label><label>Motivo y evidencia<textarea name="motivo" minlength="10" maxlength="1000" required></textarea></label><button class="so-btn">Resolver disputa</button></form></section>':''}`;
        if(buyer&&o.estado==='pendiente_pago')await proof(q('[data-proof-form]',box),o);
        const attachment=async path=>{const url=await sign('aftr-p2p',path);const w=window.open(url,'_blank','noopener,noreferrer');if(!w)notify('Permití abrir otra pestaña para ver el archivo.');};
        bind(box,'[data-bank-image]',()=>attachment(o.metodo.qr_path));bind(box,'[data-proof]',()=>attachment(o.comprobante_path));bind(box,'[data-file]',b=>attachment(b.dataset.file));
        bind(box,'[data-accept]',async()=>{await resale('aceptar',{id});notify('Aceptaste. El comprador ya ve tus datos y tiene unos minutos para pagar.');await loadAgain();});
        bind(box,'[data-reject]',async()=>{if(confirm('¿Rechazar el pedido? Tu entrada vuelve al mercado.')){await resale('rechazar',{id});await loadAgain();}});
        bind(box,'[data-confirm]',async()=>{if(confirm('¿Confirmás que recibiste el importe completo en tu banco? La entrega es definitiva.')){await resale('confirmar',{id});notify('Pago confirmado. Entrada entregada.');await op.walletRefresh?.();await loadAgain();}});
        bind(box,'[data-cancel]',async()=>{if(confirm('¿Cancelar? Si ya pagaste, abrí una disputa en lugar de cancelar.')){await resale('cancelar',{id});await loadAgain();}});
        bind(box,'[data-dispute]',async()=>{const motivo=prompt('Describí el problema. AFTR revisará esta operación.');if(motivo?.trim()){await resale('disputar',{id,motivo:motivo.trim()});await loadAgain();}});
        const mf=q('[data-message-form]',box);if(mf)mf.onsubmit=async e=>{e.preventDefault();const b=q('button',mf);b.disabled=true;try{const f=mf.elements.archivo.files[0];const path=f?await upload(f,'aftr-p2p'):null;await resale('mensaje',{id,texto:mf.elements.texto.value.trim(),archivo_path:path});await loadAgain();}catch(err){notify(err);}finally{if(b.isConnected)b.disabled=false;}};
        const rf=q('[data-resolve]',box);if(rf)rf.onsubmit=async e=>{e.preventDefault();if(!confirm('¿Aplicar esta resolución definitiva?'))return;const b=q('button',rf);b.disabled=true;try{await resale('resolver',{id,resolucion:rf.elements.resolucion.value,motivo:rf.elements.motivo.value.trim()});await loadAgain();}catch(err){notify(err);}finally{if(b.isConnected)b.disabled=false;}};
        tick();
      }finally{refreshing=false;}};
      const loadAgain=async()=>{refreshing=false;await load();};
      let expiredRequested=false;
      function tick(){const node=q('[data-countdown]',box);if(!node||!record)return;const deadline=record.estado==='pago_informado'?record.confirmar_hasta:record.vence_at;const secs=restante(deadline,now());node.textContent=reloj(secs);node.classList.toggle('so-urgent',secs<60);if(secs===0&&!expiredRequested){expiredRequested=true;void loadAgain().catch(notify);}}
      await load();expiryTimer=setInterval(tick,1000);const stop=watch(['aftr_reventa_ordenes','aftr_reventa_historial'],async()=>{expiredRequested=false;await load();},30000);modalClean=()=>{clearInterval(expiryTimer);stop();};
    }
    /* Las reglas de la reventa son de la plataforma: el boliche las ve, no las
       escribe. Iguales en todos, para que el público sepa a qué atenerse. */
    function reglasDeAftr(p) {
      const filas = [
        ['El vendedor acepta', `tiene ${p.aceptacion_minutos??30} min para responder`],
        ['Luego el comprador paga', `tiene ${p.pago_minutos??15} min`],
        ['Y el vendedor confirma', `tiene ${p.confirmacion_minutos??30} min`],
        ['Operaciones por persona', `${p.max_abiertas??1} a la vez · ${p.max_dia??5} por día`],
      ];
      return `<div class="so-panel"><span class="so-eyebrow">LOS PLAZOS LOS PONE AFTR</span><p class="so-muted">El precio lo decidís vos, arriba. Los datos de cobro del vendedor no se muestran hasta que acepta el pedido.</p><dl>${filas.map(([k,v])=>`<dt>${html(k)}</dt><dd>${html(v)}</dd>`).join('')}</dl></div>`;
    }
    async function gestion(global=false) {
      const clubId=global?null:op.club?.();const box=modal('Reventa oficial','<div class="so-loading">Cargando gestión…</div>');
      const load=async()=>{const d=await resale('gestion',clubId?{club_id:clubId}:{});if(!box.isConnected)return;
        const c=d.config||{};
        box.innerHTML=`${d.admin_principal&&clubId?'<button class="so-btn so-secondary" data-global>Ver toda la plataforma y disputas</button>':''}${clubId?`<form class="so-form so-panel" data-config><span class="so-eyebrow">REVENTA EN TU BOLICHE</span><label class="so-check"><input name="habilitada" type="checkbox" ${c.habilitada?'checked':''}> Habilitar reventa oficial</label><label>Precio máximo (% de lo que pagó quien revende)<input name="max_precio_pct" type="number" min="100" max="1000" step="1" value="${html(c.max_precio_pct??'')}" placeholder="Vacío: precio libre"></label>${reglasDeAftr(d.politica||{})}<label>Condiciones adicionales<textarea name="condiciones" rows="3" maxlength="2000">${html(c.condiciones||'')}</textarea></label><div class="so-form-error" role="alert"></div><button class="so-btn">Guardar</button></form>`:''}<h3>Operaciones${d.admin_principal?' de la plataforma':''}</h3>${(d.ordenes||[]).map(cardOrder).join('')||'<p class="so-muted">No hay operaciones todavía.</p>'}${d.disputas?.length?`<h3>Disputas ${d.admin_principal?'por resolver':''}</h3>${d.disputas.map(cardOrder).join('')}`:''}${d.ofertas?.length?`<h3>Ofertas activas</h3>${d.ofertas.map(o=>`<article class="so-panel"><h3>${html(nombre(o.evento))}</h3><p>${html(o.vendedor)} · ${dinero(o.precio_centavos)}</p><button class="so-link so-danger" data-retire="${html(o.id)}">Retirar oferta</button></article>`).join('')}`:''}<p class="so-muted">Solo AFTR puede arbitrar disputas. Los datos bancarios y comprobantes son privados.</p>`;
        bind(box,'[data-global]',()=>gestion(true));bind(box,'[data-order]',b=>order(b.dataset.order));bind(box,'[data-retire]',async b=>{const motivo=prompt('Motivo de retirada de la oferta:');if(motivo?.trim()){await resale('retirar_oferta',{oferta_id:b.dataset.retire,motivo:motivo.trim()});await load();}});
        const f=q('[data-config]',box);if(f)f.onsubmit=async e=>{e.preventDefault();const b=q('button',f);b.disabled=true;try{await resale('configurar',{club_id:clubId,habilitada:f.elements.habilitada.checked,max_precio_pct:f.elements.max_precio_pct.value?Number(f.elements.max_precio_pct.value):null,condiciones:f.elements.condiciones.value.trim()});notify('Guardado.');await load();}catch(err){q('[role=alert]',f).textContent=err.message;}finally{if(b.isConnected)b.disabled=false;}};
      };await load();modalClean=watch(['aftr_reventa_ofertas','aftr_reventa_ordenes'],load,30000);
    }
    function cleanup(){pageClean?.();pageClean=null;feedRefresh=null;}
    return {mountFeed,viewer,composer,mineStories,market,mineResale,sell,order,gestion,cleanup,close,upload};
  }
  root.AftrSocial={create,centavos,dinero,agrupar,restante,reloj};
  if(typeof module!=='undefined'&&module.exports)module.exports=root.AftrSocial;
})(typeof window==='undefined'?globalThis:window);
