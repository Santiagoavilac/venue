/* ===================================================================
   VENUE · RELACIONADORES
   El acceso propio (correo, Google o Apple, con registro abierto), las
   solicitudes para sumarse a un boliche y el espacio personal del
   relacionador: Inicio, Eventos, Estadísticas, Ganancias y Perfil.

   Se carga después de app.js y usa sus globales (sb, me, club, ev, $, qsa,
   esc, sheet, closeSheet, toast, confirmar, fmtBs, fmtF, ico, inicial,
   irATab, applyClubRole, loadEventos, buildTabbar, header, logout…).
   Los permisos los decide la base (db/41-relacionadores.sql): acá solo se
   muestra lo que las RPC devuelven para quien está mirando.
   =================================================================== */
(() => {
  const AFTR_URL = "https://aftr-web.vercel.app/";
  const FLECHA = '<svg viewBox="0 0 24 24" class="ic mas-chev"><path d="M9 6l6 6-6 6"/></svg>';
  const volverA = () => location.origin + location.pathname;

  Object.assign(TAB_ICONS, {
    rinicio: '<path d="M3 10.5L12 3l9 7.5"/><path d="M5.5 9.5V20h13V9.5"/>',
    reventos: '<rect x="3.5" y="5" width="17" height="15" rx="2"/><path d="M3.5 10h17M8 3v4M16 3v4"/>',
    rstats: '<path d="M4 20V10M10 20V4M16 20v-8M20 20H4"/>',
    rganancias: '<rect x="3" y="6" width="18" height="13" rx="2"/><path d="M3 10h18M16 15h2"/>',
    rperfil: '<circle cx="12" cy="8" r="3.6"/><path d="M5 20c1-4 3.6-6 7-6s6 2 7 6"/>'
  });

  /* ── iconos de marca (Google y Apple piden sus logos) ─────────────── */
  const LOGO_GOOGLE = `<svg viewBox="0 0 24 24" class="rl-logo" aria-hidden="true">
    <path fill="#4285F4" d="M22.6 12.3c0-.8-.1-1.5-.2-2.3H12v4.3h5.9a5 5 0 0 1-2.2 3.3v2.7h3.6c2-1.9 3.3-4.7 3.3-8z"/>
    <path fill="#34A853" d="M12 23c3 0 5.5-1 7.3-2.7l-3.6-2.7c-1 .7-2.2 1.1-3.7 1.1-2.9 0-5.3-1.9-6.2-4.5H2.1v2.8A11 11 0 0 0 12 23z"/>
    <path fill="#FBBC05" d="M5.8 14.2a6.6 6.6 0 0 1 0-4.3V7.1H2.1a11 11 0 0 0 0 9.9z"/>
    <path fill="#EA4335" d="M12 5.4c1.6 0 3.1.6 4.2 1.7l3.2-3.2A11 11 0 0 0 2.1 7.1l3.7 2.8C6.7 7.3 9.1 5.4 12 5.4z"/></svg>`;
  const LOGO_APPLE = `<svg viewBox="0 0 24 24" class="rl-logo" aria-hidden="true"><path fill="currentColor" d="M16.4 12.6c0-2.6 2.1-3.8 2.2-3.9a4.8 4.8 0 0 0-3.8-2c-1.6-.2-3.1.9-3.9.9-.8 0-2-.9-3.4-.9a5 5 0 0 0-4.2 2.6c-1.8 3.1-.5 7.7 1.3 10.2.8 1.2 1.8 2.6 3.1 2.5 1.2 0 1.7-.8 3.2-.8 1.5 0 1.9.8 3.2.8 1.3 0 2.2-1.2 3-2.4a10 10 0 0 0 1.4-2.8 4.3 4.3 0 0 1-2.1-4.2zM13.9 5c.7-.8 1.1-1.9 1-3-1 0-2.1.7-2.8 1.5-.6.7-1.2 1.8-1 2.9 1.1.1 2.1-.6 2.8-1.4z"/></svg>`;

  /* ================================================================
     ACCESO
     ================================================================ */
  let accModo = "entrar";   // entrar | crear | recuperar
  let invitacion = null;    // lo que hay detrás de un ?unirse= (para el cartel)

  async function cargarInvitacion() {
    const code = unirsePendiente();
    if (!code || (invitacion && invitacion.code === code)) return;
    const { data } = await sb.rpc("ver_invitacion", { p_code: code });
    invitacion = data ? { ...data, code } : { code, invalida: true };
    if (!$("#lgRel").classList.contains("hidden")) pintarAcceso();
  }
  const nombreInvitacion = i => i?.team ? `${i.team.nombre} · ${i.clubs.map(c => c.nombre).join(", ")}`
    : (i?.clubs?.[0]?.nombre || "");

  function pintarAcceso() {
    cargarInvitacion();
    const crear = accModo === "crear", recup = accModo === "recuperar";
    $("#lgRel").innerHTML = `
      <div class="l2-top"><button type="button" class="l2-volver" id="rlVolver" aria-label="Volver"><svg viewBox="0 0 24 24" class="ic"><path d="M15 5l-7 7 7 7"/></svg></button></div>
      <div class="l2-cuerpo">
        ${invitacion && !invitacion.invalida ? `<div class="rl-inv">Te invitan a sumarte a <b>${esc(nombreInvitacion(invitacion))}</b>. Entrá o creá tu cuenta para mandar la solicitud.</div>` : ""}
        <h1>${recup ? "Recuperar contraseña" : "Relacionadores"}</h1>
        <p class="l2-sub">${recup ? "Te mandamos un enlace a tu correo para elegir una nueva."
          : "Una sola cuenta para todos los boliches con los que trabajes."}</p>
        ${recup ? "" : `<div class="rl-seg" role="tablist">
          <button type="button" data-rm="entrar" class="${crear ? "" : "on"}">Entrar</button>
          <button type="button" data-rm="crear" class="${crear ? "on" : ""}">Crear cuenta</button>
        </div>`}
        <form id="rlForm" autocomplete="on" novalidate>
          ${crear ? `<label class="l2-rot" for="rlNom">NOMBRE Y APELLIDO</label>
          <input id="rlNom" autocomplete="name" enterkeyhint="next">` : ""}
          <label class="l2-rot" for="rlMail" style="margin-top:${crear ? 14 : 0}px">${crear || recup ? "CORREO" : "CORREO O USUARIO"}</label>
          <input id="rlMail" type="${crear || recup ? "email" : "text"}" autocomplete="${crear ? "email" : "username"}" autocapitalize="none" autocorrect="off" spellcheck="false" enterkeyhint="next">
          ${recup ? "" : `<label class="l2-rot" for="rlPass" style="margin-top:14px">CONTRASEÑA</label>
          <div class="l2-campo pw-wrap"><input id="rlPass" type="password" autocomplete="${crear ? "new-password" : "current-password"}" enterkeyhint="go"></div>
          ${crear ? `<p class="l2-nota" style="margin-top:8px">Mínimo 8 caracteres.</p>` : ""}`}
          <div id="rlErr" class="l2-err"></div>
          <button class="l2-boton" id="rlGo" style="margin-top:18px">${recup ? "Mandar enlace" : crear ? "Crear cuenta" : "Entrar"}</button>
        </form>
        ${accModo === "entrar" ? `<button type="button" class="l2-link" id="rlOlvide">Olvidé mi contraseña</button>` : ""}
        ${recup ? "" : `<div class="rl-o"><span>o</span></div>
        <button type="button" class="rl-oauth" data-prov="google">${LOGO_GOOGLE}Continuar con Google</button>
        <button type="button" class="rl-oauth" data-prov="apple">${LOGO_APPLE}Continuar con Apple</button>
        <p class="l2-nota">Si ya trabajás con un boliche en VENUE, entrá con tu mismo usuario y contraseña.</p>`}
      </div>`;
    $("#rlVolver").onclick = () => {
      if (accModo === "recuperar") { accModo = "entrar"; return pintarAcceso(); }
      mostrarAcceso("inicio");
    };
    qsa("#lgRel [data-rm]").forEach(b => b.onclick = () => { accModo = b.dataset.rm; pintarAcceso(); });
    $("#rlOlvide") && ($("#rlOlvide").onclick = () => { accModo = "recuperar"; pintarAcceso(); });
    qsa("#lgRel [data-prov]").forEach(b => b.onclick = () => oauth(b.dataset.prov));
    $("#rlForm").onsubmit = e => { e.preventDefault(); enviar(); };
    setTimeout(() => ($("#rlNom") || $("#rlMail"))?.focus(), 60);
  }

  const errAcc = m => { const el = $("#rlErr"); if (el) el.textContent = m; };
  function errorAcceso(msg) { accModo = "entrar"; pintarAcceso(); errAcc(msg); }

  async function enviar() {
    const b = $("#rlGo"), mail = ($("#rlMail").value || "").trim().toLowerCase();
    errAcc("");
    if (accModo === "recuperar") {
      if (!/^\S+@\S+\.\S+$/.test(mail)) return errAcc("Escribí el correo de tu cuenta.");
      b.disabled = true;
      const { error } = await sb.auth.resetPasswordForEmail(mail, { redirectTo: volverA() });
      b.disabled = false;
      if (error) return errAcc(mensajeAuth(error));
      $("#lgRel .l2-cuerpo").innerHTML = `<h1>Revisá tu correo</h1>
        <p class="l2-sub">Si ${esc(mail)} tiene una cuenta, te llegó un enlace para elegir una contraseña nueva.</p>`;
      return;
    }
    const pass = $("#rlPass").value;
    if (accModo === "crear") {
      const nombre = ($("#rlNom").value || "").trim();
      if (nombre.length < 2) return errAcc("Poné tu nombre y apellido.");
      if (!/^\S+@\S+\.\S+$/.test(mail)) return errAcc("Ese correo no parece válido.");
      if (pass.length < 8) return errAcc("La contraseña tiene que tener al menos 8 caracteres.");
      b.disabled = true; b.textContent = "Creando…";
      const { data, error } = await sb.auth.signUp({
        email: mail, password: pass,
        options: { emailRedirectTo: volverA(), data: { nombre } }
      });
      b.disabled = false; b.textContent = "Crear cuenta";
      if (error) return errAcc(mensajeAuth(error));
      // con confirmación de correo activada no hay sesión todavía
      if (!data.session) {
        $("#lgRel .l2-cuerpo").innerHTML = `<h1>Confirmá tu correo</h1>
          <p class="l2-sub">Te mandamos un enlace a <b>${esc(mail)}</b>. Abrilo desde este mismo dispositivo y tu cuenta queda lista.</p>
          <button class="l2-link" id="rlYa">Ya lo confirmé, entrar</button>`;
        $("#rlYa").onclick = () => { accModo = "entrar"; pintarAcceso(); $("#rlMail").value = mail; };
        return;
      }
      return boot();
    }
    if (!mail || !pass) return errAcc("Completá tu correo (o usuario) y la contraseña.");
    // los relacionadores de antes entran con su usuario de siempre
    const email = mail.includes("@") ? mail : `${mail}@plataforma.local`;
    b.disabled = true; b.textContent = "Entrando…";
    const { error } = await sb.auth.signInWithPassword({ email, password: pass });
    b.disabled = false; b.textContent = "Entrar";
    if (error) return errAcc(mensajeAuth(error));
    boot();
  }

  function mensajeAuth(e) {
    const m = (e?.message || "").toLowerCase();
    if (/fetch|network/.test(m)) return "Sin conexión. Revisá la señal y probá de nuevo.";
    if (/invalid login|invalid credentials/.test(m)) return "El correo (o usuario) o la contraseña no coinciden.";
    if (/not confirmed/.test(m)) return "Todavía no confirmaste tu correo. Buscá el enlace que te mandamos.";
    if (/already registered|already exists/.test(m)) return "Ya hay una cuenta con ese correo. Entrá con ella.";
    if (/rate limit|too many/.test(m)) return "Demasiados intentos. Esperá un momento y probá de nuevo.";
    if (/password/.test(m)) return "Esa contraseña no sirve: probá con una más larga.";
    if (/provider is not enabled|unsupported provider/.test(m)) return "Ese método todavía no está habilitado. Usá tu correo.";
    return e?.message || "No se pudo completar. Probá de nuevo.";
  }

  async function oauth(prov) {
    errAcc("");
    try { sessionStorage.setItem(MODO_ACCESO, "rel"); } catch { /* sin storage */ }
    const { error } = await sb.auth.signInWithOAuth({ provider: prov, options: { redirectTo: volverA() } });
    if (error) errAcc(mensajeAuth(error));
  }

  /* Cuenta nueva (por correo, Google o Apple) sin perfil: falta el nombre.
     Crear el perfil NO da acceso a ningún boliche. */
  async function completarCuenta(user) {
    const meta = user?.user_metadata || {};
    const sugerido = (meta.nombre || meta.full_name || meta.name || "").trim();
    $("#lgRel").innerHTML = `
      <div class="l2-top"><span class="l2-marca">VENUE</span></div>
      <div class="l2-cuerpo">
        <h1>Un último paso</h1>
        <p class="l2-sub">¿Cómo te llamás? Así te van a ver los boliches cuando pidas sumarte.</p>
        <label class="l2-rot" for="rlNom2">NOMBRE Y APELLIDO</label>
        <input id="rlNom2" autocomplete="name" value="${esc(sugerido)}">
        <div id="rlErr" class="l2-err"></div>
        <button class="l2-boton" id="rlCrear" style="margin-top:18px">Continuar</button>
        <button class="l2-link" id="rlOtra">Usar otra cuenta</button>
      </div>`;
    $("#rlOtra").onclick = async () => { await sb.auth.signOut(); mostrarAcceso("rel"); };
    $("#rlCrear").onclick = async () => {
      const nombre = $("#rlNom2").value.trim();
      if (nombre.length < 2) return errAcc("Poné tu nombre y apellido.");
      $("#rlCrear").disabled = true;
      const { error } = await sb.rpc("rrpp_crear_cuenta", { p_nombre: nombre });
      $("#rlCrear").disabled = false;
      if (error) return errAcc(error.message);
      boot();
    };
    $("#rlNom2").focus();
  }

  // vuelta del enlace de "olvidé mi contraseña": elegir una nueva
  sb?.auth.onAuthStateChange(evento => {
    if (evento !== "PASSWORD_RECOVERY") return;
    const abrir = () => {
      if ($("#app").classList.contains("hidden")) return setTimeout(abrir, 300);
      sheet(`<div class="sh-h">Elegí una contraseña nueva</div>
        <div class="field"><label>Contraseña nueva (mín. 8)</label><input id="rcP1" type="password" autocomplete="new-password"></div>
        <div class="field"><label>Repetila</label><input id="rcP2" type="password" autocomplete="new-password"></div>
        <button class="btn primary" id="rcGo">Guardar</button>`);
      $("#rcGo").onclick = async () => {
        const a = $("#rcP1").value, b = $("#rcP2").value;
        if (a.length < 8) return toast("Mínimo 8 caracteres", "warn");
        if (a !== b) return toast("No coinciden", "warn");
        const { error } = await sb.auth.updateUser({ password: a });
        if (error) return toast(mensajeAuth(error), "warn");
        closeSheet(); toast("Contraseña actualizada");
      };
    };
    abrir();
  });

  /* ================================================================
     DATOS DEL ESPACIO PERSONAL
     ================================================================ */
  const PERIODOS = [["7d", "7 días"], ["mes", "Este mes"], ["3m", "3 meses"], ["anio", "Este año"], ["todo", "Todo"]];
  const NOMBRE_PER = { "7d": "los últimos 7 días", mes: "este mes", "3m": "los últimos 3 meses", anio: "este año", todo: "todo tu historial" };
  let per = "mes", fClub = "", evSub = "proximos", serie = "comision";
  let cache = { t: 0, eventos: null, proximos: null, boliches: null, solicitudes: null };

  const hoyISO = () => new Date().toLocaleDateString("sv-SE");
  function desdeDe(p) {
    const d = new Date();
    if (p === "7d") d.setDate(d.getDate() - 6);
    else if (p === "mes") d.setDate(1);
    else if (p === "3m") d.setMonth(d.getMonth() - 3);
    else if (p === "anio") { d.setMonth(0); d.setDate(1); }
    else return null;
    return d.toLocaleDateString("sv-SE");
  }

  async function datos(forzar) {
    if (!forzar && cache.eventos && Date.now() - cache.t < 60000) return cache;
    const [e, p, b, s] = await Promise.all([
      sb.rpc("rrpp_eventos", {}), sb.rpc("rrpp_proximos", {}),
      sb.rpc("mis_establecimientos"), sb.rpc("mis_solicitudes")
    ]);
    const err = e.error || p.error || b.error || s.error;
    if (err) throw err;
    cache = { t: Date.now(), eventos: e.data || [], proximos: p.data || [], boliches: b.data || [], solicitudes: s.data || [] };
    return cache;
  }
  const invalidar = () => { cache.t = 0; };

  const n = v => +v || 0;
  const entraron = e => n(e.ingresaron) + n(e.entradas_usadas);
  const delPeriodo = (lista, p = per, c = fClub) => {
    const d = desdeDe(p);
    return lista.filter(e => (!d || e.fecha >= d) && (!c || e.club_id === c));
  };
  function totales(l) {
    const t = { eventos: l.length, com: 0, pend: 0, pag: 0, est: 0, conf: 0, bruto: 0, ent: 0, man: 0, mes: 0, an: 0, ing: 0, entr: 0 };
    l.forEach(e => {
      const c = n(e.comision_total);
      t.com += c;
      if (e.estado_comision === "pagada") t.pag += c; else t.pend += c;
      if (e.estado_comision === "estimada") t.est += c;
      if (e.estado_comision === "confirmada") t.conf += c;
      t.bruto += n(e.bruto_entradas) + n(e.bruto_mesas);
      t.ent += n(e.entradas_vendidas); t.man += n(e.entradas_usadas);
      t.mes += n(e.mesas_confirmadas); t.an += n(e.anotados); t.ing += n(e.ingresaron);
      t.entr += entraron(e);
    });
    return t;
  }
  const bs = v => `Bs ${fmtBs(Math.round(n(v)))}`;
  const pct = (a, b) => b ? Math.round(a / b * 100) : 0;
  const mesDe = f => f.slice(0, 7);
  const nombreMes = ym => new Date(ym + "-15T12:00").toLocaleDateString("es-BO", { month: "short", year: "2-digit" });

  /* ── récords: siempre sobre todo el historial ── */
  function records(l) {
    const mejor = (f, et) => {
      let top = null;
      l.forEach(e => { if (!top || f(e) > f(top)) top = e; });
      return top && f(top) > 0 ? { e: top, v: f(top), et } : null;
    };
    const meses = {};
    l.forEach(e => { meses[mesDe(e.fecha)] = (meses[mesDe(e.fecha)] || 0) + n(e.comision_total); });
    const mm = Object.entries(meses).sort((a, b) => b[1] - a[1])[0];
    return [
      mejor(e => n(e.entradas_vendidas), "Entradas vendidas en una noche"),
      mejor(e => n(e.entradas_usadas), "Manillas en un evento"),
      mejor(e => n(e.mesas_confirmadas), "Mesas confirmadas en un evento"),
      mejor(entraron, "Asistentes efectivos en una noche"),
      mejor(e => n(e.comision_total), "Comisión en un evento"),
      mejor(e => n(e.bruto_entradas) + n(e.bruto_mesas), "Ventas generadas en un evento"),
      mm && mm[1] > 0 ? { mes: mm[0], v: mm[1], et: "Mejor mes en ganancias" } : null,
      l.length ? { v: l.length, et: "Eventos trabajados", total: true } : null
    ].filter(Boolean);
  }
  const fmtRecord = r => /Comisión|Ventas|Mejor mes/.test(r.et) ? bs(r.v) : fmtBs(r.v);

  /* ── piezas visuales ── */
  const pills = () => `<div class="rx-pills" role="tablist">${PERIODOS.map(([k, l]) =>
    `<button type="button" data-per="${k}" class="${per === k ? "on" : ""}">${l}</button>`).join("")}</div>`;
  const selClub = bols => bols.length > 1 ? `<select class="rx-sel" id="rxClub" aria-label="Boliche">
      <option value="">Todos los boliches</option>
      ${bols.map(b => `<option value="${esc(b.id)}"${fClub === b.id ? " selected" : ""}>${esc(b.nombre)}</option>`).join("")}
    </select>` : "";
  const cifra = (k, v, sub = "", tono = "") => `<div class="rx-cifra ${tono}"><span class="rx-k">${k}</span><b>${v}</b>${sub ? `<small>${sub}</small>` : ""}</div>`;
  const vacio = (t, d = "", acc = "") => `<div class="rx-vacio"><b>${t}</b>${d ? `<p>${d}</p>` : ""}${acc}</div>`;
  const fechaCorta = f => new Date(f + "T12:00").toLocaleDateString("es-BO", { day: "numeric", month: "short" });
  const diaBloque = f => { const d = new Date(f + "T12:00");
    return `<span class="rx-dia"><b>${d.getDate()}</b><small>${d.toLocaleDateString("es-BO", { month: "short" })}</small></span>`; };
  const ESTADO = { pagada: ["Pagada", "ok"], confirmada: ["Por cobrar", "warn"], estimada: ["Estimada", ""] };
  const estadoPill = s => { const [t, c] = ESTADO[s] || [s, ""]; return `<span class="rx-est ${c}">${t}</span>`; };

  function conectarFiltros(repintar) {
    qsa("#main [data-per]").forEach(b => b.onclick = () => { per = b.dataset.per; repintar(); });
    $("#rxClub") && ($("#rxClub").onchange = e => { fClub = e.target.value; repintar(); });
  }

  /* barras simples en SVG: una serie por mes */
  function barras(puntos, fmt = v => fmtBs(Math.round(v))) {
    if (!puntos.length || puntos.every(p => !p.v)) return vacio("Sin datos en este período");
    const W = 640, H = 180, pad = 22, max = Math.max(...puntos.map(p => p.v)) || 1;
    const bw = Math.min(46, (W - pad * 2) / puntos.length * .62), paso = (W - pad * 2) / puntos.length;
    return `<svg class="rx-graf" viewBox="0 0 ${W} ${H + 34}" role="img" aria-label="Evolución">
      <line x1="${pad}" x2="${W - pad}" y1="${H}" y2="${H}" class="rx-eje"/>
      ${puntos.map((p, i) => {
        const h = Math.max(p.v ? 3 : 0, p.v / max * (H - 26)), x = pad + paso * i + (paso - bw) / 2;
        return `<g><title>${esc(p.label)}: ${fmt(p.v)}</title>
          <rect x="${x}" y="${H - h}" width="${bw}" height="${h}" rx="5" class="rx-barra${i === puntos.length - 1 ? " ult" : ""}"/>
          ${p.v ? `<text x="${x + bw / 2}" y="${H - h - 6}" class="rx-val">${fmt(p.v)}</text>` : ""}
          <text x="${x + bw / 2}" y="${H + 20}" class="rx-lbl">${esc(p.label)}</text></g>`;
      }).join("")}
    </svg>`;
  }
  function porMes(l, f) {
    const g = {};
    l.forEach(e => { const k = mesDe(e.fecha); g[k] = (g[k] || 0) + f(e); });
    const claves = Object.keys(g).sort().slice(-12);
    return claves.map(k => ({ label: nombreMes(k), v: g[k] }));
  }

  /* ================================================================
     INICIO
     ================================================================ */
  async function pInicio() {
    const d = await datos();
    if (unirsePendiente()) abrirUnirse(unirsePendiente());
    const l = delPeriodo(d.eventos), t = totales(l), activos = d.boliches.filter(b => b.activo);
    const pendientes = d.solicitudes.filter(s => s.estado === "pendiente");
    const recs = records(d.eventos), ult = d.eventos[0];
    const noche = recs.find(r => r.et.startsWith("Asistentes"));
    let destacado = "";
    if (noche && ult && ult.evento_id !== noche.e.evento_id) {
      const falta = noche.v - entraron(ult) + 1;
      destacado = `<div class="rx-record-dest"><span class="rx-k">Tu mejor noche</span>
        <b>${fmtBs(noche.v)} personas</b><small>${esc(noche.e.evento)} · ${esc(noche.e.club)} · ${fechaCorta(noche.e.fecha)}</small>
        <p>Te faltan <b>${fmtBs(falta)}</b> para superarla.</p></div>`;
    } else if (noche) {
      destacado = `<div class="rx-record-dest"><span class="rx-k">Tu mejor noche</span>
        <b>${fmtBs(noche.v)} personas</b><small>${esc(noche.e.evento)} · ${fechaCorta(noche.e.fecha)}</small>
        <p>Es tu último evento: estás en tu mejor momento.</p></div>`;
    }
    $("#main").innerHTML = `
      <div class="rx">
        <div class="rx-hola">Hola, ${esc((me.nombre || "").split(" ")[0])}</div>
        ${!activos.length ? sinBoliches(pendientes) : ""}
        <div class="rx-filtros">${pills()}${selClub(activos.length ? d.boliches : [])}</div>
        <section class="rx-hero">
          <span class="rx-k">Ganaste en ${NOMBRE_PER[per]}</span>
          <div class="rx-grande">${bs(t.com)}</div>
          <small>${t.eventos} ${t.eventos === 1 ? "evento" : "eventos"}${fClub ? ` en ${esc(d.boliches.find(b => b.id === fClub)?.nombre || "")}` : ""}</small>
        </section>
        <div class="rx-cifras">
          ${cifra("Por cobrar", bs(t.pend), "estimado + confirmado", t.pend ? "warn" : "")}
          ${cifra("Cobrado", bs(t.pag), "marcado como pagado", "ok")}
          ${cifra("Entraron", fmtBs(t.entr), `${fmtBs(t.ing)} de lista · ${fmtBs(t.man)} con QR`)}
          ${cifra("Mesas", fmtBs(t.mes), "confirmadas")}
        </div>
        ${pendientes.length && activos.length ? `<button class="rx-aviso" data-go="rperfil">${pendientes.length === 1 ? "1 solicitud pendiente" : `${pendientes.length} solicitudes pendientes`}${FLECHA}</button>` : ""}
        <div class="rx-tit"><h2>Próximos eventos</h2>${d.proximos.length > 3 ? `<button data-go="reventos">Ver todos</button>` : ""}</div>
        ${d.proximos.length ? `<div class="rx-lista">${d.proximos.slice(0, 3).map(filaProximo).join("")}</div>`
          : vacio("No tenés eventos próximos", activos.length ? "Cuando tus boliches publiquen uno, aparece acá." : "")}
        ${destacado ? `<div class="rx-tit"><h2>Récords</h2><button data-go="rstats">Ver todos</button></div>${destacado}` : ""}
      </div>`;
    conectarFiltros(pInicio);
    conectarComunes(d);
  }

  function sinBoliches(pend) {
    return `<div class="rx-bienvenida">
      <b>${pend.length ? "Tu solicitud está en camino" : "Sumate a tu primer boliche"}</b>
      <p>${pend.length ? `Esperando que ${esc(pend.map(s => s.club).join(", "))} te apruebe. Mientras tanto podés pedir sumarte a otros.`
        : "Buscá el boliche con el que trabajás y pedí sumarte, o abrí el enlace que te pasaron."}</p>
      <div class="rx-btns"><button class="btn primary" data-act="explorar">Explorar boliches</button>
      <button class="btn ghost2" data-act="codigo">Tengo un enlace</button></div>
    </div>`;
  }

  const filaProximo = e => `<button class="rx-fila" data-prox="${e.evento_id}">
      ${diaBloque(e.fecha)}
      <span class="rx-fila-tx"><b>${esc(e.evento)}</b><small>${esc(e.club)}${e.hora_inicio ? ` · ${e.hora_inicio.slice(0, 5)}` : ""}</small></span>
      <span class="rx-fila-num">${fmtBs(n(e.anotados))}<small>anotados</small></span>
    </button>`;

  function conectarComunes(d) {
    qsa("#main [data-go]").forEach(b => b.onclick = () => irATab(b.dataset.go));
    qsa("#main [data-prox]").forEach(b => b.onclick = () => sheetProximo(d.proximos.find(e => e.evento_id === b.dataset.prox)));
    qsa("#main [data-pas]").forEach(b => b.onclick = () => sheetPasado(d.eventos.find(e => e.evento_id === b.dataset.pas)));
    qsa("#main [data-act='explorar']").forEach(b => b.onclick = sheetExplorar);
    qsa("#main [data-act='codigo']").forEach(b => b.onclick = sheetCodigo);
  }

  /* ================================================================
     EVENTOS
     ================================================================ */
  async function pEventos() {
    const d = await datos();
    const pasados = delPeriodo(d.eventos, "todo");
    const prox = d.proximos.filter(e => !fClub || e.club_id === fClub);
    $("#main").innerHTML = `
      <div class="rx">
        <h1 class="rx-h1">Eventos</h1>
        <div class="rx-filtros">
          <div class="rx-pills"><button data-sub="proximos" class="${evSub === "proximos" ? "on" : ""}">Próximos</button>
            <button data-sub="pasados" class="${evSub === "pasados" ? "on" : ""}">Trabajados</button></div>
          ${selClub(d.boliches)}
        </div>
        ${evSub === "proximos"
          ? (prox.length ? `<div class="rx-lista">${prox.map(filaProximo).join("")}</div>`
            : vacio("No hay eventos próximos", "Los eventos de tus boliches aparecen acá apenas se crean."))
          : (pasados.length ? `<div class="rx-lista">${pasados.map(e => `<button class="rx-fila" data-pas="${e.evento_id}">
              ${diaBloque(e.fecha)}
              <span class="rx-fila-tx"><b>${esc(e.evento)}</b><small>${esc(e.club)} · ${fmtBs(entraron(e))} entraron${n(e.mesas_confirmadas) ? ` · ${e.mesas_confirmadas} mesas` : ""}</small></span>
              <span class="rx-fila-num">${bs(e.comision_total)}${estadoPill(e.estado_comision)}</span>
            </button>`).join("")}</div>`
            : vacio("Todavía no trabajaste ningún evento", "Cuando anotes invitados o vendas, tu historial se arma solo."))}
      </div>`;
    qsa("#main [data-sub]").forEach(b => b.onclick = () => { evSub = b.dataset.sub; pEventos(); });
    conectarFiltros(pEventos);
    conectarComunes(d);
  }

  let miRef = null;
  async function linkVenta(e) {
    if (!miRef) { const { data, error } = await sb.rpc("rrpp_mi_ref"); if (error) throw error; miRef = data; }
    return `${AFTR_URL}?r=${miRef}#/evento/${e.evento_id}`;
  }

  async function sheetProximo(e) {
    if (!e) return;
    const ok = !!e.aftr_publico;
    sheet(`<div class="sh-h">${esc(e.evento)}<span class="r-sub">${esc(e.club)} · ${fmtF(e.fecha)}${e.hora_inicio ? ` · ${e.hora_inicio.slice(0, 5)}` : ""}</span></div>
      <div class="rx-cifras rx-cifras-sh">
        ${cifra("Anotados", fmtBs(n(e.anotados)), e.cupo_total ? `de ${fmtBs(e.cupo_total)} de cupo` : "en tus listas")}
        ${cifra("Entradas QR", fmtBs(n(e.entradas_vendidas)), "vendidas")}
        ${cifra("Mesas", fmtBs(n(e.mesas)), "a tu nombre")}
        ${cifra("Por manilla", n(e.por_manilla) ? bs(e.por_manilla) : "—", "comisión estimada")}
      </div>
      ${n(e.por_manilla) && n(e.entradas_vendidas) ? `<p class="hint">Si entran todas tus entradas, serían unos <b>${bs(n(e.por_manilla) * n(e.entradas_vendidas))}</b> por manillas (sin contar mesas ni bonos).</p>` : ""}
      <div class="rx-tit"><h2>Vender</h2></div>
      ${ok ? `<div class="rx-btns"><button class="btn primary" id="pxWa">Compartir por WhatsApp</button>
        <button class="btn ghost2" id="pxCopiar">Copiar mi enlace</button></div>
        <p class="hint">El enlace lleva tu código: cada visita y compra que llega por él queda a tu nombre.</p>`
        : `<p class="hint">Este evento no está a la venta en AFTR, así que no tiene enlace público.</p>`}
      <div class="rx-tit"><h2>Herramientas</h2></div>
      <div class="mas-lista">
        <button class="mas-op" data-herr="accesos" data-sub="invitados">${ico("usuario")}<span>Listas e invitados</span>${FLECHA}</button>
        <button class="mas-op" data-herr="accesos" data-sub="entradas">${ico("qr")}<span>Entradas QR</span>${FLECHA}</button>
        <button class="mas-op" data-herr="mesas">${ico("sofa")}<span>Mesas y reservas</span>${FLECHA}</button>
      </div>`);
    const compartir = async wa => {
      try {
        const url = await linkVenta(e);
        if (wa) window.open(`https://wa.me/?text=${encodeURIComponent(`${e.evento} en ${e.club}, ${fmtF(e.fecha)}. Sacá tu entrada acá: ${url}`)}`, "_blank", "noopener");
        else { await copyText(url); toast("Enlace copiado"); }
      } catch (err) { fail(err); }
    };
    $("#pxWa") && ($("#pxWa").onclick = () => compartir(true));
    $("#pxCopiar") && ($("#pxCopiar").onclick = () => compartir(false));
    qsa("#sheetBody [data-herr]").forEach(b => b.onclick = () => irAHerramienta(e.club_id, e.evento_id, b.dataset.herr, b.dataset.sub));
  }

  /* abre una herramienta de siempre (listas, entradas, mesas) con el
     boliche y el evento ya elegidos */
  async function irAHerramienta(clubId, eventoId, t, sub) {
    closeSheet();
    if (club !== clubId) {
      club = clubId;
      renderClubMenu(myClubs());
      await applyClubRole();
      buildTabbar();
    }
    await loadEventos();
    const e = eventos.find(x => x.id === eventoId);
    if (e) { ev = e; try { await loadListaTipos(); } catch { listaTipos = []; } }
    header();
    if (sub) accSub = sub;
    irATab(t);
  }

  function sheetPasado(e) {
    if (!e) return;
    const filas = [
      n(e.comision_entradas) ? [`Entradas${n(e.por_manilla) ? ` (${bs(e.por_manilla)} c/u)` : ""}`, bs(e.comision_entradas)] : null,
      n(e.comision_mesas) ? ["Mesas", bs(e.comision_mesas)] : null,
      n(e.comision_jefe) ? ["Comisión de jefe (tu team)", bs(e.comision_jefe)] : null,
      n(e.bono) ? ["Bonos", bs(e.bono)] : null
    ].filter(Boolean);
    sheet(`<div class="sh-h">${esc(e.evento)}<span class="r-sub">${esc(e.club)} · ${fmtF(e.fecha)}</span></div>
      <div class="rx-cifras rx-cifras-sh">
        ${cifra("Entraron", fmtBs(entraron(e)), `${e.ingresaron}/${e.anotados} de lista · ${e.entradas_usadas} QR`)}
        ${cifra("Entradas", fmtBs(n(e.entradas_vendidas)), `${e.entradas_usadas} usadas`)}
        ${cifra("Mesas", fmtBs(n(e.mesas_confirmadas)), n(e.mesas_reservadas) ? `${e.mesas_reservadas} reservadas` : "confirmadas")}
        ${cifra("Ventas", bs(n(e.bruto_entradas) + n(e.bruto_mesas)), "para el boliche")}
      </div>
      <div class="rx-tit"><h2>Tu comisión</h2>${estadoPill(e.estado_comision)}</div>
      <div class="rx-desglose">${filas.map(([k, v]) => `<div><span>${k}</span><b>${v}</b></div>`).join("") || `<div><span>Sin comisión en este evento</span><b>—</b></div>`}
        <div class="tot"><span>Total</span><b>${bs(e.comision_total)}</b></div></div>
      <p class="hint">${e.estado_comision === "pagada" ? `Marcada como pagada${e.pagado_at ? ` el ${new Date(e.pagado_at).toLocaleDateString("es-BO")}` : ""}.`
        : e.estado_comision === "confirmada" ? "El evento cerró: es lo que te corresponde. Figura como pagada cuando el boliche o tu jefe lo marquen."
        : "El evento sigue abierto: el número puede cambiar hasta el cierre."}</p>`);
  }

  /* ================================================================
     ESTADÍSTICAS
     ================================================================ */
  const SERIES = [
    ["comision", "Comisión", e => n(e.comision_total), v => bs(v)],
    ["entradas", "Entradas", e => n(e.entradas_vendidas)],
    ["manillas", "Manillas", e => n(e.entradas_usadas)],
    ["mesas", "Mesas", e => n(e.mesas_confirmadas)],
    ["asistentes", "Asistentes", entraron]
  ];
  async function pStats() {
    const d = await datos();
    const l = delPeriodo(d.eventos), t = totales(l), todo = totales(d.eventos);
    const s = SERIES.find(x => x[0] === serie);
    const recs = records(d.eventos);
    // comparación entre boliches (del período)
    const porClub = {};
    l.forEach(e => { const o = porClub[e.club_id] = porClub[e.club_id] || { nombre: e.club, com: 0, ev: 0, entr: 0 };
      o.com += n(e.comision_total); o.ev++; o.entr += entraron(e); });
    const clubs = Object.values(porClub).sort((a, b) => b.com - a.com), maxC = Math.max(1, ...clubs.map(c => c.com));
    const mejores = [...l].sort((a, b) => n(b.comision_total) - n(a.comision_total)).slice(0, 5);
    const primero = d.eventos[d.eventos.length - 1];
    $("#main").innerHTML = `
      <div class="rx">
        <h1 class="rx-h1">Estadísticas</h1>
        <div class="rx-filtros">${pills()}${selClub(d.boliches)}</div>
        <div class="rx-cifras">
          ${cifra("Asistencia", `${pct(t.ing, t.an)}%`, `${fmtBs(t.ing)} de ${fmtBs(t.an)} anotados entraron`)}
          ${cifra("Comisión promedio", bs(t.eventos ? t.com / t.eventos : 0), "por evento")}
          ${cifra("Ventas generadas", bs(t.bruto), "para los boliches")}
          ${cifra("Eventos", fmtBs(t.eventos), "trabajados")}
        </div>
        <div class="rx-tit"><h2>Evolución mensual</h2></div>
        <div class="rx-pills rx-pills-chico">${SERIES.map(([k, lbl]) => `<button data-serie="${k}" class="${serie === k ? "on" : ""}">${lbl}</button>`).join("")}</div>
        <div class="rx-panel">${barras(porMes(l, s[2]), s[3])}</div>
        ${clubs.length > 1 ? `<div class="rx-tit"><h2>Por boliche</h2></div>
        <div class="rx-panel">${clubs.map(c => `<div class="rx-comp"><div><b>${esc(c.nombre)}</b><small>${c.ev} eventos · ${fmtBs(c.entr)} entraron</small></div>
          <div class="rx-comp-bar"><span style="width:${Math.round(c.com / maxC * 100)}%"></span></div><b>${bs(c.com)}</b></div>`).join("")}</div>` : ""}
        <div class="rx-tit"><h2>Mejores eventos</h2></div>
        ${mejores.length ? `<div class="rx-lista">${mejores.map(e => `<button class="rx-fila" data-pas="${e.evento_id}">${diaBloque(e.fecha)}
          <span class="rx-fila-tx"><b>${esc(e.evento)}</b><small>${esc(e.club)} · ${fmtBs(entraron(e))} entraron</small></span>
          <span class="rx-fila-num">${bs(e.comision_total)}</span></button>`).join("")}</div>` : vacio("Sin eventos en este período")}
        <div class="rx-tit"><h2>Mis récords</h2></div>
        ${recs.length ? `<div class="rx-records">${recs.map(r => `<div class="rx-rec"><span class="rx-k">${r.et}</span><b>${fmtRecord(r)}</b>
          <small>${r.e ? `${esc(r.e.evento)} · ${esc(r.e.club)} · ${fechaCorta(r.e.fecha)}` : r.mes ? nombreMes(r.mes) : primero ? `desde ${fechaCorta(primero.fecha)}` : ""}</small></div>`).join("")}</div>`
          : vacio("Tus récords aparecen con tu primer evento")}
        <div class="rx-tit"><h2>Trayectoria</h2><span class="rx-priv">Privada</span></div>
        <div class="rx-panel rx-tray">
          <div><span>Eventos trabajados</span><b>${fmtBs(todo.eventos)}</b></div>
          <div><span>Boliches</span><b>${new Set(d.eventos.map(e => e.club_id)).size}</b></div>
          <div><span>Personas que entraron por vos</span><b>${fmtBs(todo.entr)}</b></div>
          <div><span>Entradas vendidas</span><b>${fmtBs(todo.ent)}</b></div>
          <div><span>Mesas confirmadas</span><b>${fmtBs(todo.mes)}</b></div>
          <div><span>Ventas generadas</span><b>${bs(todo.bruto)}</b></div>
          <div><span>Ganancias totales</span><b>${bs(todo.com)}</b></div>
          ${primero ? `<div><span>En VENUE desde</span><b>${fmtF(primero.fecha)}</b></div>` : ""}
        </div>
        <div class="rx-tit"><h2>Clientes que vuelven</h2></div><div id="rxRec">${skeletonChico()}</div>
        <div class="rx-tit"><h2>Tu enlace de venta</h2></div><div id="rxLinks">${skeletonChico()}</div>
      </div>`;
    qsa("#main [data-serie]").forEach(b => b.onclick = () => { serie = b.dataset.serie; pStats(); });
    conectarFiltros(pStats);
    conectarComunes(d);
    // secundarios: no frenan la pantalla
    sb.rpc("rrpp_recurrentes", { p_club: fClub || null }).then(({ data }) => {
      const el = $("#rxRec"); if (!el) return;
      el.innerHTML = (data || []).length ? `<div class="rx-panel rx-tray">${data.slice(0, 10).map(r =>
        `<div><span>${esc(r.nombre)}</span><b>${r.eventos} eventos</b></div>`).join("")}</div>`
        : vacio("Todavía no hay invitados que repitan", "Cuando alguien vuelva a entrar por tu lista en otro evento, lo vas a ver acá.");
    });
    sb.rpc("rrpp_links", { p_desde: desdeDe(per) }).then(({ data }) => {
      const el = $("#rxLinks"); if (!el) return;
      const l2 = data || [];
      if (!l2.length) { el.innerHTML = vacio("Sin visitas por tu enlace todavía", "Compartí tu enlace desde un evento próximo: acá vas a ver cuánta gente entra y cuántos compran."); return; }
      const v = l2.reduce((a, x) => a + n(x.visitas), 0), c = l2.reduce((a, x) => a + n(x.compras), 0);
      el.innerHTML = `<div class="rx-cifras">${cifra("Visitas", fmtBs(v))}${cifra("Compras", fmtBs(c), `${pct(c, l2.reduce((a, x) => a + n(x.clientes), 0))}% de quienes iniciaron sesión`)}</div>`;
    });
  }
  const skeletonChico = () => `<div class="sk" style="height:64px;border-radius:14px"></div>`;

  /* ================================================================
     GANANCIAS
     ================================================================ */
  async function pGanancias() {
    const d = await datos();
    const l = delPeriodo(d.eventos), t = totales(l);
    $("#main").innerHTML = `
      <div class="rx">
        <h1 class="rx-h1">Ganancias</h1>
        <div class="rx-filtros">${pills()}${selClub(d.boliches)}</div>
        <section class="rx-hero">
          <span class="rx-k">Tu comisión en ${NOMBRE_PER[per]}</span>
          <div class="rx-grande">${bs(t.com)}</div>
          <small>Lo que vendiste para los boliches: ${bs(t.bruto)}. Eso no es tu ganancia: tu ganancia es la comisión.</small>
        </section>
        <div class="rx-panel rx-desglose">
          <div><span>Estimadas <small>eventos todavía abiertos</small></span><b>${bs(t.est)}</b></div>
          <div><span>Confirmadas <small>evento cerrado, falta pagar</small></span><b>${bs(t.conf)}</b></div>
          <div><span>Pagadas <small>marcadas por el boliche o tu jefe</small></span><b>${bs(t.pag)}</b></div>
          <div class="tot"><span>Total</span><b>${bs(t.com)}</b></div>
        </div>
        <div class="rx-tit"><h2>Por evento</h2></div>
        ${l.length ? `<div class="rx-lista">${l.map(e => `<button class="rx-fila" data-pas="${e.evento_id}">
            ${diaBloque(e.fecha)}
            <span class="rx-fila-tx"><b>${esc(e.evento)}</b><small>${esc(e.club)} · ${[
              n(e.comision_entradas) ? `entradas ${bs(e.comision_entradas)}` : "",
              n(e.comision_mesas) ? `mesas ${bs(e.comision_mesas)}` : "",
              n(e.comision_jefe) ? `jefe ${bs(e.comision_jefe)}` : "",
              n(e.bono) ? `bono ${bs(e.bono)}` : ""].filter(Boolean).join(" · ") || "sin comisión"}</small></span>
            <span class="rx-fila-num">${bs(e.comision_total)}${estadoPill(e.estado_comision)}</span>
          </button>`).join("")}</div>` : vacio("Sin comisiones en este período")}
        <p class="hint" style="margin-top:14px">Cada boliche paga distinto: el monto por manilla y por combo sale de la configuración de ese boliche y de tu team. Una comisión figura como pagada solo cuando el boliche o tu jefe la marca.</p>
      </div>`;
    conectarFiltros(pGanancias);
    conectarComunes(d);
  }

  /* ================================================================
     PERFIL: cuenta, boliches, solicitudes y herramientas
     ================================================================ */
  async function pPerfil() {
    const d = await datos(true);
    const { data: { user } } = await sb.auth.getUser();
    const correo = user?.email && !user.email.endsWith("@plataforma.local") ? user.email : "";
    const provs = (user?.identities || []).map(i => i.provider);
    const pend = d.solicitudes.filter(s => s.estado === "pendiente");
    const resueltas = d.solicitudes.filter(s => s.estado !== "pendiente");
    const herr = [
      ...tabsFor().filter(([t]) => !TABS_REL.includes(t)),
    ];
    const extras = accionesMas();
    $("#main").innerHTML = `
      <div class="rx">
        <div class="rx-cuenta">${inicial(me.nombre)}<div><b>${esc(me.nombre)}</b><small>${correo ? esc(correo) : `@${esc(me.usuario)}`}</small></div></div>
        <div class="rx-tit"><h2>Mis establecimientos</h2><button data-act="explorar">Explorar</button></div>
        ${d.boliches.length ? `<div class="rx-lista">${d.boliches.map(b => `<button class="rx-fila" data-bol="${esc(b.id)}">
            <span class="rx-logo">${b.logo_url ? `<img src="${esc(b.logo_url)}" alt="">` : esc((b.nombre || "?")[0])}</span>
            <span class="rx-fila-tx"><b>${esc(b.nombre)}</b><small>${b.activo ? `${b.rol === "jefe" ? "Jefe" : "Relacionador"}${b.team ? ` · ${esc(b.team)}` : ""}` : "Sin acceso · conservás tu historial"}</small></span>
            ${b.activo && b.id === club ? `<span class="rx-est ok">Activo</span>` : ""}
          </button>`).join("")}</div>`
          : vacio("Todavía no trabajás con ningún boliche", "", `<div class="rx-btns"><button class="btn primary" data-act="explorar">Explorar boliches</button><button class="btn ghost2" data-act="codigo">Tengo un enlace</button></div>`)}
        ${pend.length || resueltas.length ? `<div class="rx-tit"><h2>Solicitudes</h2></div>
        <div class="rx-lista">${[...pend, ...resueltas].map(s => `<div class="rx-fila">
            <span class="rx-logo">${s.logo_url ? `<img src="${esc(s.logo_url)}" alt="">` : esc((s.club || "?")[0])}</span>
            <span class="rx-fila-tx"><b>${esc(s.club)}</b><small>${s.team ? `${esc(s.team)} · ` : ""}${fechaCorta(s.created_at.slice(0, 10))}</small></span>
            ${s.estado === "pendiente" ? `<button class="rx-mini" data-cancel="${s.id}">Cancelar</button>`
              : `<span class="rx-est ${s.estado === "aprobada" ? "ok" : s.estado === "rechazada" ? "bad" : ""}">${{ aprobada: "Aprobada", rechazada: "Rechazada", cancelada: "Cancelada" }[s.estado]}</span>`}
          </div>`).join("")}</div>` : ""}
        <div class="rx-btns" style="margin-top:12px"><button class="btn ghost2" data-act="codigo">Tengo un enlace de invitación</button></div>
        ${club && (herr.length || extras.length) ? `<div class="rx-tit"><h2>Herramientas · ${esc(clubNombre(club))}</h2></div>
        <div class="mas-lista">
          ${herr.map(([t, lbl]) => `<button class="mas-op" data-herr="${t}"><svg viewBox="0 0 24 24" class="ic">${TAB_ICONS[t] || ""}</svg><span>${esc(lbl)}</span>${FLECHA}</button>`).join("")}
          ${extras.map(([k, lbl]) => `<button class="mas-op" data-ext="${k}"><svg viewBox="0 0 24 24" class="ic">${EXTRA_ICONS[k] || ""}</svg><span>${esc(lbl)}</span>${FLECHA}</button>`).join("")}
        </div>` : ""}
        <div class="rx-tit"><h2>Cuenta</h2></div>
        <div class="mas-lista">
          <button class="mas-op" data-cta="perfil">${ico("usuario")}<span>Mis datos y contraseña</span>${FLECHA}</button>
          ${!correo ? `<button class="mas-op" data-cta="correo">${ico("archivo")}<span>Agregar mi correo</span>${FLECHA}</button>` : ""}
          ${!provs.includes("google") ? `<button class="mas-op" data-vinc="google">${LOGO_GOOGLE}<span>Vincular Google</span>${FLECHA}</button>` : ""}
          ${!provs.includes("apple") ? `<button class="mas-op" data-vinc="apple">${LOGO_APPLE}<span>Vincular Apple</span>${FLECHA}</button>` : ""}
          <button class="mas-op" data-cta="salir">${ico("salida")}<span>Cerrar sesión</span></button>
        </div>
      </div>`;
    conectarComunes(d);
    qsa("#main [data-bol]").forEach(b => b.onclick = () => sheetBoliche(d, b.dataset.bol));
    qsa("#main [data-cancel]").forEach(b => b.onclick = async () => {
      const { error } = await sb.rpc("cancelar_solicitud", { p_id: b.dataset.cancel });
      if (error) return fail(error);
      toast("Solicitud cancelada"); invalidar(); pPerfil();
    });
    qsa("#main [data-herr]").forEach(b => b.onclick = () => irATab(b.dataset.herr));
    qsa("#main [data-ext]").forEach(b => b.onclick = () => extras.find(([k]) => k === b.dataset.ext)?.[2]());
    qsa("#main [data-vinc]").forEach(b => b.onclick = async () => {
      try { sessionStorage.setItem(MODO_ACCESO, "rel"); } catch { /* sin storage */ }
      const { error } = await sb.auth.linkIdentity({ provider: b.dataset.vinc, options: { redirectTo: volverA() } });
      if (error) toast(mensajeAuth(error), "warn");
    });
    $("#main [data-cta='perfil']").onclick = () => abrirPanelPerfil();
    $("#main [data-cta='salir']").onclick = () => logout();
    $("#main [data-cta='correo']") && ($("#main [data-cta='correo']").onclick = sheetCorreo);
  }

  function sheetCorreo() {
    sheet(`<div class="sh-h">Agregar mi correo</div>
      <p class="hint">Con tu correo podés entrar sin el usuario y recuperar la contraseña si te la olvidás. Te mandamos un enlace para confirmarlo.</p>
      <div class="field"><label>Correo</label><input id="ceMail" type="email" autocomplete="email" autocapitalize="none"></div>
      <button class="btn primary" id="ceGo">Mandar confirmación</button>`);
    $("#ceGo").onclick = async () => {
      const mail = $("#ceMail").value.trim().toLowerCase();
      if (!/^\S+@\S+\.\S+$/.test(mail)) return toast("Ese correo no parece válido", "warn");
      const { error } = await sb.auth.updateUser({ email: mail }, { emailRedirectTo: volverA() });
      if (error) return toast(mensajeAuth(error), "warn");
      closeSheet(); toast("Te mandamos un enlace para confirmarlo");
    };
  }

  /* detalle de un boliche: lo suyo en ese boliche */
  function sheetBoliche(d, id) {
    const b = d.boliches.find(x => x.id === id); if (!b) return;
    const l = d.eventos.filter(e => e.club_id === id), t = totales(l);
    const prox = d.proximos.filter(e => e.club_id === id);
    sheet(`<div class="sh-h">${esc(b.nombre)}<span class="r-sub">${b.activo ? `${b.rol === "jefe" ? "Jefe" : "Relacionador"}${b.team ? ` · ${esc(b.team)}` : ""}` : "Sin acceso"}</span></div>
      <div class="rx-cifras rx-cifras-sh">
        ${cifra("Eventos", fmtBs(t.eventos), "trabajados")}
        ${cifra("Entraron", fmtBs(t.entr), `${fmtBs(t.man)} manillas`)}
        ${cifra("Comisiones", bs(t.com), `${bs(t.pend)} por cobrar`, "ok")}
        ${cifra("Ventas", bs(t.bruto), `${fmtBs(t.mes)} mesas`)}
      </div>
      <div class="rx-panel">${barras(porMes(l, e => n(e.comision_total)), v => bs(v))}</div>
      ${prox.length ? `<div class="rx-tit"><h2>Próximos</h2></div><div class="rx-lista">${prox.map(filaProximo).join("")}</div>` : ""}
      ${l.length ? `<div class="rx-tit"><h2>Historial</h2></div><div class="rx-lista">${l.slice(0, 12).map(e => `<button class="rx-fila" data-pas="${e.evento_id}">${diaBloque(e.fecha)}
        <span class="rx-fila-tx"><b>${esc(e.evento)}</b><small>${fmtBs(entraron(e))} entraron</small></span>
        <span class="rx-fila-num">${bs(e.comision_total)}${estadoPill(e.estado_comision)}</span></button>`).join("")}</div>` : ""}
      ${b.activo && b.id !== club ? `<button class="btn primary" id="sbUsar" style="margin-top:14px">Trabajar en ${esc(b.nombre)}</button>` : ""}`);
    qsa("#sheetBody [data-prox]").forEach(x => x.onclick = () => sheetProximo(d.proximos.find(e => e.evento_id === x.dataset.prox)));
    qsa("#sheetBody [data-pas]").forEach(x => x.onclick = () => sheetPasado(d.eventos.find(e => e.evento_id === x.dataset.pas)));
    $("#sbUsar") && ($("#sbUsar").onclick = async () => {
      closeSheet();
      club = id; renderClubMenu(myClubs());
      await applyClubRole(); await loadEventos(); buildTabbar(); header();
      toast(`Ahora trabajás en ${b.nombre}`); renderTab();
    });
  }

  /* ── sumarse a un boliche ── */
  function sheetExplorar() {
    sheet(`<div class="sh-h">Explorar boliches</div>
      <div class="field"><input id="exQ" placeholder="Buscar por nombre o ciudad" autocomplete="off"></div>
      <div id="exRes">${skeletonChico()}</div>`);
    let tmr = null;
    const buscar = async () => {
      const { data, error } = await sb.rpc("explorar_boliches", { p_q: $("#exQ")?.value.trim() || null });
      const el = $("#exRes"); if (!el) return;
      if (error) { el.innerHTML = vacio("No pudimos buscar", esc(error.message)); return; }
      el.innerHTML = (data || []).length ? `<div class="rx-lista">${data.map(c => `<div class="rx-fila">
          <span class="rx-logo">${c.logo_url ? `<img src="${esc(c.logo_url)}" alt="">` : esc((c.nombre || "?")[0])}</span>
          <span class="rx-fila-tx"><b>${esc(c.nombre)}</b><small>${esc([c.zona, c.ciudad].filter(Boolean).join(", ") || c.subtitulo || "")}</small></span>
          ${c.ya_miembro ? `<span class="rx-est ok">Ya trabajás acá</span>` : c.pendiente ? `<span class="rx-est warn">Pendiente</span>`
            : `<button class="rx-mini on" data-pedir="${esc(c.id)}">Solicitar</button>`}
        </div>`).join("")}</div>`
        : vacio("No encontramos boliches", "Solo aparecen los que reciben solicitudes. Si te pasaron un enlace, usá “Tengo un enlace”.");
      qsa("#exRes [data-pedir]").forEach(b => b.onclick = async () => {
        b.disabled = true;
        const { error: e2 } = await sb.rpc("solicitar_union", { p_club: b.dataset.pedir, p_code: null });
        if (e2) { b.disabled = false; return toast(e2.message, "warn"); }
        toast("Solicitud enviada"); invalidar(); buscar();
      });
    };
    $("#exQ").oninput = () => { clearTimeout(tmr); tmr = setTimeout(buscar, 250); };
    buscar();
  }

  function sheetCodigo() {
    sheet(`<div class="sh-h">Tengo un enlace</div>
      <p class="hint">Pegá el enlace o el código que te pasó el boliche o tu jefe de team.</p>
      <div class="field"><input id="cdIn" autocapitalize="none" autocomplete="off" placeholder="https://… o código"></div>
      <button class="btn primary" id="cdGo">Continuar</button>`);
    $("#cdGo").onclick = () => {
      const v = $("#cdIn").value.trim();
      const m = v.match(/[?&](?:unirse|invite)=([A-Za-z0-9]+)/);
      const code = m ? m[1] : v.replace(/[^A-Za-z0-9]/g, "");
      if (code.length < 8) return toast("Ese código no parece completo", "warn");
      abrirUnirse(code);
    };
  }

  async function abrirUnirse(code) {
    const limpiar = () => { try { sessionStorage.removeItem("venue.unirse"); } catch { /* sin storage */ } };
    const { data: inv, error } = await sb.rpc("ver_invitacion", { p_code: code });
    if (error || !inv) {
      limpiar();
      return sheet(`<div class="sh-h">Enlace no válido</div><p class="hint">El enlace venció o fue desactivado. Pedile uno nuevo a quien te lo pasó.</p>`);
    }
    const clubs = inv.clubs || [];
    let elegido = clubs.length === 1 ? clubs[0].id : null;
    const pintar = () => sheet(`<div class="sh-h">Sumarte${inv.team ? ` al team ${esc(inv.team.nombre)}` : ""}</div>
      ${clubs.length > 1 ? `<p class="hint">Este team trabaja en varios boliches. Elegí en cuál.</p>` : ""}
      <div class="rx-lista">${clubs.map(c => `<button class="rx-fila${elegido === c.id ? " on" : ""}" data-elegir="${esc(c.id)}">
        <span class="rx-logo">${c.logo_url ? `<img src="${esc(c.logo_url)}" alt="">` : esc((c.nombre || "?")[0])}</span>
        <span class="rx-fila-tx"><b>${esc(c.nombre)}</b><small>${esc(c.ciudad || "")}</small></span>
        ${elegido === c.id ? `<span class="rx-est ok">Elegido</span>` : ""}</button>`).join("")}</div>
      <p class="hint">Tu solicitud queda pendiente hasta que ${inv.team ? "tu jefe de team o " : ""}el boliche la apruebe. Recién ahí ves sus eventos.</p>
      <button class="btn primary" id="unGo" ${elegido ? "" : "disabled"}>Solicitar unirme</button>
      <button class="btn ghost2" id="unNo" style="margin-top:8px">Ahora no</button>`);
    const conectar = () => {
      qsa("#sheetBody [data-elegir]").forEach(b => b.onclick = () => { elegido = b.dataset.elegir; pintar(); conectar(); });
      $("#unNo").onclick = () => { limpiar(); closeSheet(); };
      $("#unGo").onclick = async () => {
        $("#unGo").disabled = true;
        const { error: e2 } = await sb.rpc("solicitar_union", { p_club: elegido, p_code: code });
        limpiar();
        if (e2) { closeSheet(); return toast(e2.message, "warn"); }
        sheet(`<div class="sh-h">Solicitud enviada</div><p class="hint">Te avisamos acá apenas te aprueben. Mientras tanto la ves en Perfil.</p>
          <button class="btn primary" id="unOk">Listo</button>`);
        $("#unOk").onclick = () => { closeSheet(); invalidar(); renderTab(); };
      };
    };
    pintar(); conectar();
  }

  /* ================================================================
     GESTIÓN (admin del boliche y jefes de team)
     ================================================================ */
  const ORIGEN = { enlace_club: "Por el enlace del boliche", enlace_team: "Por el enlace de un team", directa: "Solicitud directa" };
  async function abrirGestion() {
    const esAdmin = me.rol === "admin";
    const [{ data: sol, error }, cfg] = await Promise.all([
      sb.rpc("solicitudes_club", { p_club: club }),
      esAdmin ? sb.rpc("invitacion_club", { p_club: club }) : Promise.resolve({ data: null })
    ]);
    if (error) return fail(error);
    if (esAdmin || me.rol === "jefe") await loadTeams();
    const teams = esAdmin ? teamsDelClub() : [];
    const inv = cfg?.data;
    const link = inv ? `${volverA()}?unirse=${inv.code}` : "";
    sheet(`<div class="sh-h">${esAdmin ? "Relacionadores" : "Quieren unirse a tu team"}<span class="r-sub">${esc(clubNombre(club))}</span></div>
      <div class="rx-tit"><h2>Solicitudes${(sol || []).length ? ` · ${sol.length}` : ""}</h2></div>
      ${(sol || []).length ? `<div class="rx-lista">${sol.map(s => `<div class="rx-sol" data-sol="${s.id}">
          <div class="rx-sol-h">${inicial(s.nombre)}<div><b>${esc(s.nombre)}</b>
            <small>${esc(s.email || "@" + s.usuario)} · ${ORIGEN[s.origen] || ""}${s.team ? ` (${esc(s.team)})` : ""}</small>
            <small>${n(s.eventos_trabajados) ? `${s.eventos_trabajados} eventos trabajados en VENUE` : "Sin eventos en VENUE todavía"}</small></div></div>
          ${esAdmin && teams.length ? `<select class="rx-sel" data-team-sol="${s.id}"><option value="">Sin team</option>
            ${teams.map(t => `<option value="${t.id}"${t.id === s.team_id ? " selected" : ""}>${esc(t.nombre)}</option>`).join("")}</select>` : ""}
          <div class="rx-btns"><button class="btn primary" data-ok="${s.id}">Aprobar</button><button class="btn ghost2" data-no="${s.id}">Rechazar</button></div>
        </div>`).join("")}</div>` : vacio("No hay solicitudes pendientes")}
      ${esAdmin && inv ? `<div class="rx-tit"><h2>Invitar relacionadores</h2></div>
      <div class="rx-panel">
        <p class="hint" style="margin-top:0">Quien abra este enlace entra por Relacionadores y te manda una solicitud. Nadie entra sin que la apruebes.</p>
        <div class="rx-link${inv.activo ? "" : " off"}">${esc(link)}</div>
        <div class="rx-btns">
          <button class="btn primary" id="gsWa" ${inv.activo ? "" : "disabled"}>Compartir por WhatsApp</button>
          <button class="btn ghost2" id="gsCp" ${inv.activo ? "" : "disabled"}>Copiar</button>
        </div>
        <div class="rx-btns">
          <button class="btn ghost2" id="gsAct">${inv.activo ? "Desactivar enlace" : "Activar enlace"}</button>
          <button class="btn ghost2" id="gsNuevo">Generar uno nuevo</button>
        </div>
      </div>
      <div class="rx-tit"><h2>Solicitudes públicas</h2></div>
      <label class="rx-switch"><input type="checkbox" id="gsPub" ${inv.publicas ? "checked" : ""}>
        <span><b>Aparecer en “Explorar boliches”</b><small>Cualquier relacionador puede encontrar ${esc(clubNombre(club))} y pedir sumarse.</small></span></label>` : ""}`);
    qsa("#sheetBody [data-ok], #sheetBody [data-no]").forEach(b => b.onclick = async () => {
      const id = b.dataset.ok || b.dataset.no, ok = !!b.dataset.ok;
      const sel = $(`#sheetBody [data-team-sol="${id}"]`);
      b.disabled = true;
      const { error: e2 } = await sb.rpc("resolver_solicitud", { p_id: id, p_aprobar: ok, p_team: sel?.value || null });
      if (e2) { b.disabled = false; return toast(e2.message, "warn"); }
      toast(ok ? "Aprobado: ya puede trabajar en el boliche" : "Solicitud rechazada");
      invalidarEfectivos();
      abrirGestion();
    });
    if (!inv) return;
    $("#gsCp").onclick = async () => { await copyText(link); toast("Enlace copiado"); };
    $("#gsWa").onclick = () => window.open(`https://wa.me/?text=${encodeURIComponent(`Sumate como relacionador de ${clubNombre(club)} en VENUE: ${link}`)}`, "_blank", "noopener");
    $("#gsAct").onclick = async () => {
      const { error: e2 } = await sb.rpc("config_solicitudes_club", { p_club: club, p_invite_activo: !inv.activo, p_publicas: null });
      if (e2) return fail(e2);
      abrirGestion();
    };
    $("#gsNuevo").onclick = async () => {
      const ok = await confirmar({ titulo: "¿Generar un enlace nuevo?", detalle: ["El enlace actual deja de funcionar."], accion: "Generar" });
      if (!ok) return;
      const { error: e2 } = await sb.rpc("regenerar_invitacion_club", { p_club: club });
      if (e2) return fail(e2);
      toast("Enlace nuevo listo"); abrirGestion();
    };
    $("#gsPub").onchange = async e => {
      const { error: e2 } = await sb.rpc("config_solicitudes_club", { p_club: club, p_invite_activo: null, p_publicas: e.target.checked });
      if (e2) { e.target.checked = !e.target.checked; return fail(e2); }
      toast(e.target.checked ? "Ya aparecés en Explorar" : "Ya no aparecés en Explorar");
    };
  }
  const invalidarEfectivos = () => { try { efectivosClub = null; } catch { /* no aplica */ } };

  /* ficha de una persona (admin): permisos y quitar acceso en ESTE boliche */
  const PERMISOS = [["listas", "Anotar en listas"], ["entradas", "Vender entradas QR"], ["mesas", "Vender mesas"]];
  function conectarFicha(g) {
    const bp = $("#fuPermisos"), bq = $("#fuQuitar");
    bp && (bp.onclick = async () => {
      const { data, error } = await sb.rpc("permisos_de", { p_user: g.id, p_club: club });
      if (error) return fail(error);
      const p = data || {};
      sheet(`<div class="sh-h">Permisos de ${esc(g.nombre)}<span class="r-sub">${esc(clubNombre(club))}</span></div>
        <p class="hint">Valen solo en este boliche. En los demás sigue con lo que tenga allá.</p>
        ${PERMISOS.map(([k, l]) => `<label class="rx-switch"><input type="checkbox" data-perm="${k}" ${p[k] === false ? "" : "checked"}><span><b>${l}</b></span></label>`).join("")}
        <button class="btn primary" id="pmGo" style="margin-top:14px">Guardar</button>`);
      $("#pmGo").onclick = async () => {
        const nuevo = {};
        qsa("#sheetBody [data-perm]").forEach(c => { if (!c.checked) nuevo[c.dataset.perm] = false; });
        const { error: e2 } = await sb.rpc("set_permisos", { p_user: g.id, p_club: club, p_permisos: nuevo });
        if (e2) return fail(e2);
        closeSheet(); toast("Permisos guardados");
      };
    });
    bq && (bq.onclick = async () => {
      const ok = await confirmar({
        titulo: `¿Quitar a ${g.nombre} de ${clubNombre(club)}?`,
        detalle: ["Deja de ver los eventos y herramientas de este boliche.", "Sus números quedan en el historial.", "Sus otros boliches no cambian."],
        accion: "Quitar acceso"
      });
      if (!ok) return;
      const { error } = await sb.rpc("revocar_acceso", { p_user: g.id, p_club: club });
      if (error) return fail(error);
      closeSheet(); toast("Acceso quitado"); invalidarEfectivos(); renderTab();
    });
  }

  window.Rel = {
    pintarAcceso, completarCuenta, errorAcceso, abrirGestion, conectarFicha, abrirUnirse,
    pantallas: { rinicio: pInicio, reventos: pEventos, rstats: pStats, rganancias: pGanancias, rperfil: pPerfil }
  };
})();
