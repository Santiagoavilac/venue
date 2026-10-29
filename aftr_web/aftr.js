/* AFTR web. HTML + JS plano, sin build, como la web de Venue.
 *
 * Habla solo con las RPC aftr_* (db/35-aftr.sql): mirar no pide cuenta;
 * comprar, reservar, anotarse y la billetera sí. El mapa es MapLibre con el
 * estilo oscuro de CARTO (sin cuenta ni token), no el de Apple. */
"use strict";

// sesión propia: si AFTR y Venue comparten dominio, no se pisan las cuentas
const sb = supabase.createClient(CONFIG.SUPABASE_URL, CONFIG.SUPABASE_ANON_KEY, { auth: { storageKey: "aftr.sesion" } });
const $ = (s, r = document) => r.querySelector(s);
const $$ = (s, r = document) => [...r.querySelectorAll(s)];
const vista = $("#vista");

const E = { sesion: null, perfil: null, eventos: null, lugares: null, accesos: null, cuando: "todo" };

/* ── utilidades ─────────────────────────────────────────────────────── */
const esc = (s) => String(s ?? "").replace(/[&<>"']/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[c]));
const bs = (v) => (v == null ? "" : v === 0 ? "Gratis" : `Bs ${Math.round(v)}`);
const MESES = ["ene", "feb", "mar", "abr", "may", "jun", "jul", "ago", "sep", "oct", "nov", "dic"];
const DIAS = ["dom", "lun", "mar", "mié", "jue", "vie", "sáb"];
const dia = (s) => { const [y, m, d] = String(s).split("-").map(Number); return new Date(y, m - 1, d); };
const hoy0 = () => { const h = new Date(); return new Date(h.getFullYear(), h.getMonth(), h.getDate()); };
function fechaCorta(s) {
  const f = dia(s), d = Math.round((f - hoy0()) / 864e5);
  if (d === 0) return "Hoy";
  if (d === 1) return "Mañana";
  return `${DIAS[f.getDay()]} ${f.getDate()} ${MESES[f.getMonth()]}`;
}
const linea = (e) => [fechaCorta(e.fecha), e.hora_inicio, e.club?.zona].filter(Boolean).join(" · ");
const precioDesde = (e) => (e.desde_precio == null ? (e.tiene_lista ? "Lista free" : null) : e.desde_precio === 0 ? "Gratis" : `Desde ${bs(e.desde_precio)}`);
const esAhora = (e) => new Date(e.inicio) - Date.now() < 3 * 36e5;
const esHoy = (e) => fechaCorta(e.fecha) === "Hoy";
function mensaje(e) {
  if (e?.code === "PGRST202") return "AFTR todavía no está activado en la base.";
  if (e?.message?.includes("Failed to fetch")) return "Sin conexión. Revisá la señal y probá de nuevo.";
  return e?.message || "Ocurrió un error inesperado.";
}
async function rpc(fn, p = {}) {
  const { data, error } = await sb.rpc(fn, p);
  if (error) throw error;
  return data;
}

// imagen con fundido; sin imagen, degradé del color del boliche
function img(url, color, extra = "") {
  return `<div class="img ${extra}" style="--c:${esc(color || "#26262a")}">${url ? `<img src="${esc(url)}" alt="" loading="lazy" onload="this.classList.add('cargada')">` : ""}</div>`;
}
const ICO = {
  chev: `<svg class="chevron" viewBox="0 0 24 24"><path d="M9 6l6 6-6 6"/></svg>`,
  atras: `<svg viewBox="0 0 24 24"><path d="M15 5l-7 7 7 7"/></svg>`,
  comp: `<svg viewBox="0 0 24 24"><path d="M12 3v12M7 8l5-5 5 5M5 14v5a2 2 0 002 2h10a2 2 0 002-2v-5"/></svg>`,
  cor: `<svg viewBox="0 0 24 24"><path d="M12 20s-7-4.4-7-10a4 4 0 017-2.6A4 4 0 0119 10c0 5.6-7 10-7 10z"/></svg>`,
  cal: `<svg viewBox="0 0 24 24"><rect x="4" y="5" width="16" height="15" rx="2"/><path d="M4 10h16M9 3v4M15 3v4"/></svg>`,
  reloj: `<svg viewBox="0 0 24 24"><circle cx="12" cy="12" r="8"/><path d="M12 8v4l3 2"/></svg>`,
  lugar: `<svg viewBox="0 0 24 24"><path d="M12 21s-6-5.5-6-11a6 6 0 0112 0c0 5.5-6 11-6 11z"/><circle cx="12" cy="10" r="2"/></svg>`,
  id: `<svg viewBox="0 0 24 24"><rect x="3" y="6" width="18" height="12" rx="2"/><path d="M7 14h4M7 10h2"/></svg>`,
  ir: `<svg viewBox="0 0 24 24"><path d="M3 11l18-8-8 18-2-8z"/></svg>`,
  ok: `<svg viewBox="0 0 24 24"><path d="M12 3l7 3v6c0 4-3 7.5-7 9-4-1.5-7-5-7-9V6z"/><path d="M9 12l2 2 4-4"/></svg>`,
  persona: `<svg viewBox="0 0 24 24"><circle cx="12" cy="8" r="4"/><path d="M4 21c1.5-4 4.5-6 8-6s6.5 2 8 6"/></svg>`,
  salir: `<svg viewBox="0 0 24 24"><path d="M15 4h3a2 2 0 012 2v12a2 2 0 01-2 2h-3M10 17l-5-5 5-5M5 12h11"/></svg>`,
  borrar: `<svg viewBox="0 0 24 24"><path d="M4 7h16M10 11v6M14 11v6M6 7l1 13h10l1-13M9 7V4h6v3"/></svg>`,
  ticket: `<svg viewBox="0 0 24 24"><path d="M3 8a2 2 0 012-2h14a2 2 0 012 2v2a2 2 0 000 4v2a2 2 0 01-2 2H5a2 2 0 01-2-2v-2a2 2 0 000-4z"/></svg>`,
};
const check = `<svg class="check" viewBox="0 0 84 84" fill="none" stroke="#34d399" stroke-width="5" stroke-linecap="round" stroke-linejoin="round"><circle cx="42" cy="42" r="39" transform="rotate(-90 42 42)"/><path d="M24 44l13 12 24-25"/></svg>`;

let tAviso;
function avisar(t) {
  const a = $("#aviso");
  a.textContent = t;
  a.classList.add("si");
  clearTimeout(tAviso);
  tAviso = setTimeout(() => a.classList.remove("si"), 2800);
}

/* ── hoja de abajo ──────────────────────────────────────────────────── */
let alCerrarHoja = null;
function abrirHoja(html, alCerrar) {
  $("#hoja-cuerpo").innerHTML = html;
  alCerrarHoja = alCerrar || null;
  const h = $("#hoja"), f = $("#hoja-fondo");
  h.hidden = f.hidden = false;
  requestAnimationFrame(() => { h.classList.add("si"); f.classList.add("si"); });
  return $("#hoja-cuerpo");
}
function cerrarHoja() {
  const h = $("#hoja"), f = $("#hoja-fondo");
  h.classList.remove("si"); f.classList.remove("si");
  setTimeout(() => { h.hidden = f.hidden = true; $("#hoja-cuerpo").innerHTML = ""; }, 420);
  const cb = alCerrarHoja; alCerrarHoja = null; cb?.();
}
$("#hoja-fondo").addEventListener("click", cerrarHoja);
document.addEventListener("keydown", (e) => { if (e.key === "Escape" && !$("#hoja").hidden) cerrarHoja(); });
const listo = (titulo, texto, accion, fn) => `<div class="listo">${check}<h2 class="aparecer" style="--o:6">${esc(titulo)}</h2><p class="aparecer" style="--o:7">${esc(texto)}</p>
  <button class="boton" data-listo>${esc(accion)}</button><button class="enlace" data-cerrar>Listo</button></div>`;
function ligarListo(c, fn) {
  $("[data-listo]", c)?.addEventListener("click", () => { cerrarHoja(); fn?.(); });
  $("[data-cerrar]", c)?.addEventListener("click", cerrarHoja);
}

/* ── arranque (igual que la app: la A, destellos, AFTR letra por letra) ─ */
const FOTOS = ["img/noche1.jpg", "img/noche2.jpg", "img/noche3.jpg"];
const LETRAS = [[0, 158], [234, 112], [418, 137], [627, 142]]; // posición en el logotipo, sobre 769
function armarPalabra(cont) {
  cont.style.position = "relative";
  // con las letras en absoluto el ancho no sale solo: se calcula del alto
  cont.style.width = `${(cont.getBoundingClientRect().height * 769) / 151}px`;
  cont.style.gap = "0";
  $$("img", cont).forEach((im, i) => Object.assign(im.style, {
    position: "absolute", top: "0", height: "100%", width: `${(LETRAS[i][1] / 769) * 100}%`, left: `${(LETRAS[i][0] / 769) * 100}%`, margin: "0",
  }));
}
function arranque() {
  const s = $("#splash"), fotos = $(".sp-fotos", s), marca = $(".sp-marca", s), letras = $$(".sp-letras img", s), lema = $(".sp-lema", s), pal = $(".sp-letras", s);
  armarPalabra(pal);
  let extra = [];
  try { extra = JSON.parse(localStorage.getItem("aftr.splash.flyers") || "[]"); } catch {}
  const todas = [...FOTOS, ...extra.slice(0, 3)];
  todas.forEach((u) => { const i = new Image(); i.src = u; });
  const TOTAL = 2700, ease = (t) => 1 - Math.pow(1 - t, 3), easeIn = (t) => t * t * t;
  const tramo = (ms, a, b, f = ease) => f(Math.min(1, Math.max(0, (ms - a) / (b - a))));
  let t0 = null, fin = false;
  const terminar = () => { if (fin) return; fin = true; s.classList.add("fuera"); setTimeout(() => s.remove(), 420); };
  s.addEventListener("click", terminar);
  function cuadro(t) {
    if (fin) return;
    t0 ??= t;
    const ms = t - t0;
    const entra = tramo(ms, 0, 380), zoom = tramo(ms, 1060, 1500, easeIn), a = tramo(ms, 1250, 1650), lm = tramo(ms, 1900, 2350);
    if (ms > 380 && ms < 1060) {
      const n = Math.floor((ms - 380) / 115);
      fotos.style.opacity = 1;
      fotos.style.backgroundImage = `url("${todas[n % todas.length]}")`;
      fotos.style.backgroundPosition = ["center", "top", "bottom", "left"][n % 4];
      fotos.style.transform = `scale(${1.08 + 0.06 * (n % 3)})`;
      fotos.classList.toggle("bn", n % 2 === 1);
    } else fotos.style.opacity = 0;
    marca.style.opacity = entra * (1 - zoom);
    marca.style.transform = `scale(${(0.86 + 0.14 * entra) * (1 + 6 * zoom)})`;
    pal.style.transform = `scale(${1 + 0.6 * (1 - a)})`;
    letras[0].style.opacity = a;
    for (let i = 1; i < 4; i++) {
      const l = tramo(ms, 1420 + i * 110, 1780 + i * 110);
      letras[i].style.opacity = l;
      letras[i].style.transform = `translateX(${26 * (1 - l)}px)`;
    }
    lema.style.opacity = lm;
    lema.style.letterSpacing = `${3 + 3 * lm}px`;
    if (ms >= TOTAL - 250) return terminar();
    requestAnimationFrame(cuadro);
  }
  requestAnimationFrame(cuadro);
}

/* ── datos ──────────────────────────────────────────────────────────── */
async function cargarEventos(forzar) {
  if (E.eventos && !forzar) return E.eventos;
  E.eventos = (await rpc("aftr_eventos")) || [];
  try { localStorage.setItem("aftr.splash.flyers", JSON.stringify(E.eventos.map((e) => e.flyer).filter(Boolean).slice(0, 4))); } catch {}
  return E.eventos;
}
async function cargarLugares(forzar) {
  if (E.lugares && !forzar) return E.lugares;
  return (E.lugares = (await rpc("aftr_lugares")) || []);
}
async function cargarPerfil() {
  E.perfil = E.sesion ? await rpc("aftr_mi_perfil").catch(() => null) : null;
  pintarAvatar();
  return E.perfil;
}
function pintarAvatar() {
  const a = $("#avatar");
  a.innerHTML = E.perfil ? esc(E.perfil.nombre.slice(0, 1).toUpperCase()) : ICO.persona;
}

// billetera con realtime: Venue confirma o la puerta marca usado y se recarga sola
let canal = null, tRecarga;
async function cargarAccesos() {
  if (!E.sesion) return (E.accesos = null);
  E.accesos = await rpc("aftr_mis_accesos");
  const validos = proximos(E.accesos).filter((a) => a.qr && a.estado === "valida").length;
  const g = $("#globo"); g.hidden = !validos; g.textContent = validos;
  if (!canal) {
    const uid = E.sesion.user.id;
    canal = sb.channel(`aftr-accesos-${uid}`);
    for (const t of ["entradas", "registros", "mesas", "aftr_ordenes"]) {
      canal.on("postgres_changes", { event: "*", schema: "public", table: t, filter: `cliente_id=eq.${uid}` }, () => {
        clearTimeout(tRecarga);
        tRecarga = setTimeout(async () => { await cargarAccesos(); if (ruta().nombre === "accesos") pintar(); }, 600);
      });
    }
    canal.subscribe();
  }
  return E.accesos;
}

/* Las tarjetas de la billetera, como en la app. */
function aplanar(j) {
  if (!j) return [];
  const out = [];
  for (const x of j.ordenes || []) {
    const mesa = x.tipo === "mesa";
    out.push({ id: x.id, tipo: "pedido", estado: "pendiente", evento: x.evento, total: x.total,
      titulo: mesa ? `Mesa ${x.mesa || ""}`.trim() : x.cantidad === 1 ? "1 entrada" : `${x.cantidad} entradas`,
      detalle: mesa ? "Reserva esperando confirmación" : x.fase || "Esperando confirmación" });
  }
  for (const x of j.entradas || []) out.push({ id: x.id, tipo: "entrada", estado: x.estado, evento: x.evento, qr: x.qr, code: x.code,
    transferible: x.transferible, titulo: x.mesa ? `Manilla · Mesa ${x.mesa}` : "Entrada", detalle: x.fase });
  for (const x of j.listas || []) out.push({ id: x.id, tipo: "lista", estado: x.estado, evento: x.evento, qr: x.qr, code: x.code,
    titulo: x.lista || "Lista", detalle: x.hasta ? `Entrás hasta las ${x.hasta}` : null });
  return out;
}
function proximos(j) {
  const ayer = new Date(hoy0() - 864e5);
  return aplanar(j).filter((a) => (a.estado === "valida" || a.estado === "pendiente") && dia(a.evento.fecha) >= ayer)
    .sort((a, b) => new Date(a.evento.inicio) - new Date(b.evento.inicio));
}
function pasados(j) {
  const p = new Set(proximos(j).map((a) => a.id));
  return aplanar(j).filter((a) => !p.has(a.id)).sort((a, b) => new Date(b.evento.inicio) - new Date(a.evento.inicio));
}

/* ── cuenta: ingreso con Apple o Google, y la bienvenida ───────────── */
async function asegurarCuenta() {
  if (!E.sesion) { abrirIngreso(); return false; }
  if (!E.perfil) await cargarPerfil();
  if (!E.perfil) { abrirBienvenida(); return false; }
  return true;
}
function abrirIngreso() {
  const d = document.createElement("div");
  d.className = "ingreso";
  d.innerHTML = `<div class="fotos" style="background-image:url(${FOTOS[0]})"></div><div class="velo"></div>
    <div class="dentro">
      <div style="display:flex;align-items:center"><div class="palabra-barra" style="height:22px;margin:0">${["a", "f", "t", "r"].map((l) => `<img src="img/${l}.svg" alt="">`).join("")}</div>
        <button class="redondo" style="margin-left:auto" data-x aria-label="Cerrar"><svg viewBox="0 0 24 24"><path d="M6 6l12 12M18 6L6 18"/></svg></button></div>
      <h1 class="titular aparecer">Your night<br>starts here.</h1>
      <p class="suave aparecer" style="--o:2;margin:0 0 32px">Descubrí, reservá y entrá. Todo desde un solo lugar.</p>
      <button class="boton aparecer" style="--o:4" data-p="apple"><svg width="20" height="20" viewBox="0 0 24 24" fill="#000"><path d="M16.4 12.6c0-2.6 2.1-3.8 2.2-3.9-1.2-1.8-3.1-2-3.7-2-1.6-.2-3.1.9-3.9.9-.8 0-2-.9-3.4-.9-1.7 0-3.3 1-4.2 2.6-1.8 3.1-.5 7.7 1.3 10.2.9 1.2 1.9 2.6 3.2 2.6 1.3-.1 1.8-.8 3.3-.8 1.6 0 2 .8 3.4.8 1.4 0 2.3-1.3 3.1-2.5 1-1.4 1.4-2.8 1.4-2.9 0 0-2.7-1-2.7-4.1zM13.9 4.9c.7-.9 1.2-2 1.1-3.2-1 0-2.3.7-3 1.6-.7.8-1.2 2-1.1 3.1 1.2.1 2.3-.6 3-1.5z"/></svg>Continuar con Apple</button>
      <button class="boton sec aparecer" style="--o:5" data-p="google"><b style="font-size:18px">G</b>Continuar con Google</button>
      <p class="tenue" style="text-align:center;font-size:12px;margin:18px 0 0">Al continuar aceptás los términos y la política de privacidad de AFTR.</p>
    </div>`;
  document.body.append(d);
  let n = 0;
  const reloj = setInterval(() => { $(".fotos", d).style.backgroundImage = `url(${FOTOS[++n % FOTOS.length]})`; }, 2400);
  const cerrar = () => { clearInterval(reloj); d.remove(); };
  $("[data-x]", d).onclick = cerrar;
  $$("[data-p]", d).forEach((b) => (b.onclick = async () => {
    b.innerHTML = `<span class="giro"></span>`;
    const { error } = await sb.auth.signInWithOAuth({ provider: b.dataset.p, options: { redirectTo: location.href.split("#")[0] + location.hash } });
    if (error) { avisar(error.message.includes("not enabled") ? "Ese ingreso todavía no está activado." : mensaje(error)); cerrar(); }
  }));
}
function sugerirUsuario(n) {
  return n.toLowerCase().normalize("NFD").replace(/[̀-ͯ]/g, "").replace(/[^a-z0-9_.]/g, "").slice(0, 24);
}
function abrirBienvenida() {
  const meta = E.sesion?.user?.user_metadata || {};
  let nombre = (meta.full_name || meta.name || "").trim(), usuario = sugerirUsuario(nombre), paso = 0;
  const d = document.createElement("div");
  d.className = "ingreso";
  document.body.append(d);
  const pintarPaso = (error) => {
    const primero = nombre.split(" ")[0];
    d.innerHTML = `<div class="dentro">
      <div style="display:flex;align-items:center;gap:14px"><button class="redondo" data-atras style="background:var(--sup2)">${ICO.atras}</button>
        <div class="progreso"><i style="width:${(paso + 1) * 50}%"></i></div><span class="suave" style="font-size:13px">${paso + 1}/2</span></div>
      <div class="paso aparecer" style="margin-top:36px;flex:1">
        <h1 class="titular" style="font-size:34px;margin:0 0 40px">${paso === 0 ? "Tu noche empieza acá.<br>¿Cómo te llamamos?" : `Hola, ${esc(primero)}.<br>Elegí tu usuario.`}</h1>
        ${paso === 0 ? `<input id="campo" placeholder="Tu nombre" value="${esc(nombre)}" autocomplete="name">`
          : `<div style="display:flex;align-items:baseline"><span class="fuerte tenue" style="font-size:24px">@</span><input id="campo" placeholder="usuario" value="${esc(usuario)}" autocapitalize="off" autocorrect="off" spellcheck="false"></div>`}
        <p style="margin:14px 0 0;font-size:14px;color:${error ? "var(--alerta)" : "var(--texto3)"}">${esc(error || (paso === 1 ? "Con este nombre te encuentran tus amigos para mandarte entradas." : ""))}</p>
      </div>
      <button class="boton" data-sig>${paso === 0 ? "Siguiente" : "Empezar"}</button></div>`;
    const campo = $("#campo", d), sig = $("[data-sig]", d);
    const valido = () => (paso === 0 ? campo.value.trim().length > 0 : /^[a-z0-9_.]{3,24}$/.test(campo.value.trim().toLowerCase()));
    sig.disabled = !valido();
    campo.oninput = () => (sig.disabled = !valido());
    campo.onkeydown = (e) => e.key === "Enter" && valido() && sig.click();
    campo.focus();
    $("[data-atras]", d).onclick = async () => {
      if (paso === 1) { usuario = campo.value; paso = 0; return pintarPaso(); }
      await sb.auth.signOut(); d.remove();
    };
    sig.onclick = async () => {
      if (paso === 0) { nombre = campo.value.trim(); if (!usuario) usuario = sugerirUsuario(nombre); paso = 1; return pintarPaso(); }
      sig.innerHTML = `<span class="giro"></span>`;
      try {
        E.perfil = await rpc("aftr_crear_perfil", { p_usuario: campo.value.trim().toLowerCase(), p_nombre: nombre });
        pintarAvatar(); d.remove(); pintar();
      } catch (e) { usuario = campo.value; pintarPaso(mensaje(e)); }
    };
  };
  pintarPaso();
}

/* ── rutas ──────────────────────────────────────────────────────────── */
function ruta() {
  const p = location.hash.replace(/^#\/?/, "").split("/");
  if (p[0] === "evento") return { nombre: "evento", id: p[1] };
  if (p[0] === "lugar") return { nombre: "lugar", id: decodeURIComponent(p[1] || "") };
  if (["mapa", "accesos", "cuenta"].includes(p[0])) return { nombre: p[0] };
  return { nombre: "descubrir" };
}
let limpiar = null;
async function pintar() {
  limpiar?.(); limpiar = null;
  const r = ruta();
  document.body.classList.toggle("en-mapa", r.nombre === "mapa");
  document.body.classList.remove("con-compra");
  $$("[data-tab]").forEach((a) => a.classList.toggle("activa", a.dataset.tab === r.nombre));
  $("#barra").hidden = r.nombre === "evento" || r.nombre === "lugar";
  window.scrollTo(0, 0);
  try {
    if (r.nombre === "evento") return await pintarEvento(r.id);
    if (r.nombre === "lugar") return await pintarLugar(r.id);
    if (r.nombre === "mapa") return await pintarMapa();
    if (r.nombre === "accesos") return await pintarAccesos();
    if (r.nombre === "cuenta") return pintarCuenta();
    return await pintarDescubrir();
  } catch (e) {
    vista.innerHTML = `<div class="vacio"><img src="img/marca.svg" alt=""><p>${esc(mensaje(e))}</p><button class="pildora" onclick="location.reload()">Reintentar</button></div>`;
  }
}
window.addEventListener("hashchange", pintar);

/* ── descubrir ──────────────────────────────────────────────────────── */
function rango(c) {
  const h = hoy0(), mas = (n) => new Date(+h + n * 864e5);
  if (/^\d{4}-\d{2}-\d{2}$/.test(c)) return [dia(c), dia(c)];
  if (c === "hoy") return [h, h];
  if (c === "manana") return [mas(1), mas(1)];
  if (c === "finde") {
    const wd = h.getDay(); // 0 dom … 5 vie
    const desde = wd === 5 || wd === 6 || wd === 0 ? h : mas(5 - wd);
    return [desde, mas((7 - wd) % 7)];
  }
  return [h, mas(60)];
}
/* La tira de fechas (como Dice o RA): "Todo" y los próximos 21 días, con el
   nombre chico arriba, el número grande, un punto si hay algo esa noche y una
   línea que se desliza hasta el elegido. */
const iso = (d) => `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, "0")}-${String(d.getDate()).padStart(2, "0")}`;
let tiraScroll = 0, lineaAntes = null;
function tiraFechas(todos) {
  const con = new Set(todos.map((e) => e.fecha));
  const h = hoy0();
  const dias = Array.from({ length: 21 }, (_, i) => new Date(+h + i * 864e5));
  return `<div class="tira" id="tira"><button class="dia todo ${E.cuando === "todo" ? "si" : ""}" data-cuando="todo"><small>&nbsp;</small><b>Todo</b><i></i></button>
    ${dias.map((d, i) => { const k = iso(d); return `<button class="dia ${E.cuando === k ? "si" : ""} ${con.has(k) ? "hay" : ""}" data-cuando="${k}">
      <small>${i === 0 ? "Hoy" : i === 1 ? "Mañ" : DIAS[d.getDay()]}</small><b>${d.getDate()}</b><i></i></button>`; }).join("")}
    <span class="linea" id="linea"></span></div>`;
}
function moverLinea() {
  const t = $("#tira"), sel = $(".dia.si", t), l = $("#linea");
  if (!t || !sel) return;
  t.scrollLeft = tiraScroll;
  const destino = { x: sel.offsetLeft + sel.offsetWidth / 2 - 9, w: 18 };
  if (lineaAntes) { l.style.transition = "none"; l.style.transform = `translateX(${lineaAntes.x}px)`; l.offsetWidth; l.style.transition = ""; }
  l.style.transform = `translateX(${destino.x}px)`;
  lineaAntes = destino;
  t.onscroll = () => (tiraScroll = t.scrollLeft);
}
const enRango = (lista, c) => { const [a, b] = rango(c); return lista.filter((e) => dia(e.fecha) >= a && dia(e.fecha) <= b); };
const tarjeta = (e, i) => `<a class="tarjeta presionable aparecer" style="--o:${i}" href="#/evento/${e.id}">
  ${img(e.flyer, e.club?.color).replace("</div>", (precioDesde(e) ? `<span class="pildora densa">${esc(precioDesde(e))}</span>` : "") + "</div>")}
  <h4>${esc(e.nombre)}</h4><p>${esc(e.club?.nombre)}</p><p class="suave">${esc(linea(e))}</p></a>`;
const filaEvento = (e, i) => `<a class="fila presionable aparecer" style="--o:${i}" href="#/evento/${e.id}">${img(e.flyer, e.club?.color)}
  <div class="cuerpo"><b>${esc(e.nombre)}</b><span>${esc(e.club?.nombre)} · ${esc(fechaCorta(e.fecha))} ${esc(e.hora_inicio)}</span>
  ${precioDesde(e) ? `<span style="color:var(--acento);font-weight:600">${esc(precioDesde(e))}</span>` : ""}</div>${ICO.chev}</a>`;
const filaLugar = (l, i) => `<a class="fila presionable aparecer" style="--o:${i}" href="#/lugar/${encodeURIComponent(l.id)}">${img(l.logo || l.fotos?.[0] || l.proximo?.flyer, l.color)}
  <div class="cuerpo"><b>${esc(l.nombre)}</b><span class="suave">${esc([l.zona || l.ciudad, l.proximo?.nombre].filter(Boolean).join(" · "))}</span></div>${ICO.chev}</a>`;
const carrusel = (t, lista) => `<div class="titulo-sec"><h3>${esc(t)}</h3></div><div class="carrusel">${lista.map(tarjeta).join("")}</div>`;

async function pintarDescubrir() {
  const cuerpo = () => {
    const todos = E.eventos || [];
    const lista = enRango(todos, E.cuando);
    let html = `<div class="envoltura"><h1 class="titular saludo aparecer">Discover<br>the night.</h1>
      ${tiraFechas(todos)}`;
    if (!E.eventos) {
      html += `<div style="padding:12px 20px"><div class="esq" style="aspect-ratio:.82;border-radius:24px;max-height:74vh"></div></div>`;
    } else if (!lista.length) {
      html += `<div class="vacio"><img src="img/marca.svg" alt=""><p>${todos.length ? "Esa noche no hay nada publicado todavía. Probá otro día." : "Todavía no hay eventos publicados. Volvé más tarde."}</p></div>`;
    } else {
      const d = lista[0], ahora = esAhora(d);
      html += `<a class="destacado img presionable aparecer" style="--o:1;--c:${esc(d.club?.color || "#26262a")}" href="#/evento/${d.id}">
        ${d.flyer ? `<img src="${esc(d.flyer)}" alt="" onload="this.classList.add('cargada')">` : ""}<div class="degrade"></div>
        <div class="info"><div style="display:flex;align-items:center">${ahora ? `<span class="punto-vivo"></span><span class="etq vivo">Esta noche</span>` : `<span class="etq oro">${esc(d.club?.nombre)}</span>`}</div>
        <h2 class="titular">${esc(d.nombre)}</h2><div>${esc(linea(d))}</div>
        ${precioDesde(d) ? `<span class="pildora densa activa" style="margin-top:14px">${esc(precioDesde(d))}</span>` : ""}</div></a>`;
      const hoy = enRango(todos, "hoy"), finde = enRango(todos, "finde");
      const gratis = lista.filter((e) => e.desde_precio === 0 || e.tiene_lista), mesas = lista.filter((e) => e.mesas_libres > 0);
      if (E.cuando === "todo" && hoy.length) html += carrusel("Esta noche", hoy);
      if (E.cuando === "todo" && finde.length) html += carrusel("Este fin de semana", finde);
      if (E.cuando !== "todo" && lista.length > 1) html += carrusel("También", lista.slice(1));
      if (gratis.length) html += carrusel("Gratis con lista", gratis);
      if (mesas.length) html += carrusel("Con mesas disponibles", mesas);
      const gen = {};
      lista.forEach((e) => (e.generos || []).forEach((g) => (gen[g] ||= []).push(e)));
      Object.entries(gen).slice(0, 3).forEach(([g, l]) => (html += carrusel(g, l)));
      if (E.cuando === "todo" && lista.length > 1) html += `<div class="titulo-sec"><h3>Próximos</h3></div>${lista.map(filaEvento).join("")}`;
    }
    if (E.lugares?.length) html += `<div class="titulo-sec"><h3>Lugares</h3></div>${E.lugares.map(filaLugar).join("")}`;
    vista.innerHTML = html + "</div>";
    moverLinea();
    $$("[data-cuando]").forEach((b) => (b.onclick = () => { E.cuando = b.dataset.cuando; cuerpo(); }));
  };
  cuerpo();
  await Promise.all([cargarEventos(), cargarLugares().catch(() => [])]);
  if (ruta().nombre === "descubrir") cuerpo();
}

/* ── evento ─────────────────────────────────────────────────────────── */
/* Enlace personal de un relacionador (?r=código): se guarda para la sesión
   y cada evento que se abre con él suma una visita a su nombre. No cambia
   precios ni comisiones: solo mide cuánta gente llega por su enlace. */
const REF = (() => {
  try {
    const r = new URLSearchParams(location.search).get("r");
    if (r && /^[a-z0-9]{6,12}$/i.test(r)) sessionStorage.setItem("aftr.ref", r.toLowerCase());
    return sessionStorage.getItem("aftr.ref");
  } catch { return null; }
})();
async function pintarEvento(id) {
  if (REF) sb.rpc("aftr_visita_ref", { p_evento: id, p_ref: REF }).then(() => {}, () => {});
  const previo = (E.eventos || []).find((e) => e.id === id);
  if (previo) vista.innerHTML = cabeceraEvento(previo) + `<div class="det"><div class="esq" style="height:120px;border-radius:18px;margin-top:20px"></div></div>`;
  const d = await rpc("aftr_evento", { p_id: id });
  if (!d) { vista.innerHTML = `<div class="vacio"><p>Este evento ya no está disponible.</p><a class="pildora" href="#/">Volver</a></div>`; return; }
  let fase = (d.fases || []).find((f) => f.estado === "abierta")?.id || null, guardado = d.guardado;
  const seVende = () => (d.venta_por_fases ? !!fase : d.venta_abierta);
  const faseSel = () => (d.fases || []).find((f) => f.id === fase);
  const precio = () => (d.venta_por_fases ? faseSel()?.precio : d.precio);
  const render = () => {
    const sub = (f) => ({ agotada: "Agotada", proxima: "Pronto", cerrada: "Cerrada" }[f.estado] || (f.quedan != null ? `${bs(f.precio)} · quedan ${f.quedan}` : bs(f.precio)));
    const horarios = d.venta_por_fases
      ? (d.fases || []).map((f) => `<button class="horario ${f.estado !== "abierta" ? "off" : ""} ${f.id === fase ? "si" : ""}" data-fase="${f.id}" ${f.estado !== "abierta" ? "disabled" : ""}><b>${esc(f.nombre)}</b><small>${esc(sub(f).toUpperCase())}</small></button>`).join("")
      : `<button class="horario ${d.venta_abierta ? "si" : "off"}"><b>General</b><small>${esc((d.venta_abierta ? bs(d.precio) : "Venta cerrada").toUpperCase())}</small></button>`;
    const minCombo = (d.combos || []).length ? Math.min(...d.combos.map((c) => c.precio || 0)) : null;
    vista.innerHTML = cabeceraEvento(d, guardado) + `<div class="det">
      <a class="etq oro aparecer" href="#/lugar/${encodeURIComponent(d.club.id)}">${esc(d.club.nombre)} ›</a>
      <h1 class="titular aparecer" style="--o:1">${esc(d.nombre)}</h1>
      <div class="datos aparecer" style="--o:2"><span>${ICO.cal}${esc(fechaCorta(d.fecha))}</span><span>${ICO.reloj}${esc(d.hora_inicio)} a ${esc(d.hora_fin)}</span>
        <span>${ICO.id}+${esc(d.edad_min)}</span>${d.club.zona ? `<span>${ICO.lugar}${esc(d.club.zona)}</span>` : ""}</div>
      ${(d.generos || []).length ? `<div style="display:flex;gap:6px;flex-wrap:wrap;margin-top:14px">${d.generos.map((g) => `<span class="pildora densa">${esc(g)}</span>`).join("")}</div>` : ""}
      ${(d.fases || []).length || !d.venta_por_fases ? `<h3 class="sec-tit">Entradas</h3><div class="horarios">${horarios}</div>` : ""}
      ${(d.listas || []).length ? `<h3 class="sec-tit">Listas</h3>${d.listas.map((l) => `<div class="caja"><div class="cuerpo"><b>${esc(l.nombre)}</b>
        <small>${[(l.precio || 0) > 0 ? `${bs(l.precio)} en puerta` : "Free", l.hasta ? `hasta ${l.hasta}` : ""].filter(Boolean).join(" · ")}</small></div>
        ${l.abierta ? `<button class="mini-boton" data-lista="${l.id}">Anotarme</button>` : `<span class="tenue">Cerrada</span>`}</div>`).join("")}` : ""}
      ${(d.mesas || []).length ? `<h3 class="sec-tit">Mesas</h3><button class="caja oro presionable" data-mesa style="width:100%;text-align:left">
        <div class="cuerpo"><b>Reservá una mesa</b><small>${d.mesas.length} disponibles${minCombo != null ? ` · desde ${bs(minCombo)}` : ""}</small></div>${ICO.chev}</button>` : ""}
      ${d.descripcion ? `<h3 class="sec-tit">Sobre el evento</h3><div class="texto-largo" data-largo>${esc(d.descripcion)}</div>` : ""}
      <h3 class="sec-tit">Dónde</h3><a class="caja presionable" href="#/lugar/${encodeURIComponent(d.club.id)}">${img(d.club.logo, d.club.color).replace('class="img ', 'style="width:52px;height:52px;border-radius:12px;flex:none" class="img ')}
        <div class="cuerpo"><b>${esc(d.club.nombre)}</b><small>${esc([d.club.zona, d.club.ciudad].filter(Boolean).join(", "))}</small></div>${ICO.chev}</a>
      </div><div class="barra-compra"><div class="cuerpo"><div class="suave" style="font-size:13px">${esc(seVende() ? (d.venta_por_fases ? faseSel()?.nombre || "" : "Entrada") : "Entradas")}</div>
        <div class="fuerte" style="font-size:20px">${esc(seVende() ? bs(precio()) : "No disponibles")}</div></div>
        <button class="boton" data-comprar ${seVende() ? "" : "disabled"}>Comprar</button></div>`;
    document.body.classList.add("con-compra");
    $$("[data-fase]").forEach((b) => (b.onclick = () => { fase = b.dataset.fase; render(); }));
    $("[data-comprar]").onclick = async () => { if (await asegurarCuenta()) hojaCompra(d, d.venta_por_fases ? faseSel() : null); };
    $("[data-mesa]") && ($("[data-mesa]").onclick = async () => { if (await asegurarCuenta()) hojaMesa(d); });
    $$("[data-lista]").forEach((b) => (b.onclick = async () => {
      if (!(await asegurarCuenta())) return;
      b.textContent = "...";
      try {
        await rpc("aftr_anotarme_lista", { p_evento: d.id, p_lista: b.dataset.lista });
        const l = d.listas.find((x) => x.id === b.dataset.lista);
        const c = abrirHoja(listo("Estás en la lista", `${l.nombre}${l.hasta ? ` · entrás hasta las ${l.hasta}` : ""}. Tu QR ya está en Accesos.`, "Ver mi QR"));
        ligarListo(c, () => (location.hash = "#/accesos"));
      } catch (e) { avisar(mensaje(e)); }
      b.textContent = "Anotarme";
    }));
    $("[data-largo]")?.addEventListener("click", (e) => e.currentTarget.classList.toggle("abierto"));
    ligarCabecera(d, () => guardado, async () => {
      if (!(await asegurarCuenta())) return;
      guardado = !guardado; render();
      try { guardado = await rpc("aftr_guardar", { p_evento: d.id }); } catch (e) { guardado = !guardado; avisar(mensaje(e)); }
      render();
    });
  };
  render();
}
function cabeceraEvento(e, guardado) {
  return `<div class="redondos" id="redondos"><button class="redondo" data-atras aria-label="Atrás">${ICO.atras}</button>
    <div class="titulo-mini">${esc(e.nombre)}</div><button class="redondo" data-comp aria-label="Compartir">${ICO.comp}</button>
    ${guardado == null ? "" : `<button class="redondo ${guardado ? "lleno" : ""}" data-guardar aria-label="Guardar">${ICO.cor}</button>`}</div>
    <div class="portada">${img(e.flyer, e.club?.color)}</div>`;
}
function ligarCabecera(e, _g, guardar) {
  $("[data-atras]").onclick = () => (history.length > 1 ? history.back() : (location.hash = "#/"));
  $("[data-comp]").onclick = () => {
    const texto = `${e.nombre} · ${e.club?.nombre} · ${fechaCorta(e.fecha)} ${e.hora_inicio}. Lo vi en AFTR.`;
    if (navigator.share) navigator.share({ text: texto, url: location.href }).catch(() => {});
    else navigator.clipboard?.writeText(`${texto} ${location.href}`).then(() => avisar("Link copiado"));
  };
  if (guardar) $("[data-guardar]").onclick = guardar;
  const foto = $(".portada .img"), barra = $("#redondos");
  const alto = $(".portada").offsetHeight;
  const onScroll = () => {
    const y = scrollY;
    foto.style.transform = y < 0 ? `scale(${1 - y / 400})` : `translateY(${y * 0.5}px)`;
    barra.classList.toggle("solida", y > alto - 140);
  };
  addEventListener("scroll", onScroll, { passive: true });
  limpiar = () => removeEventListener("scroll", onScroll);
}

function hojaCompra(d, fase) {
  let n = 1;
  const precio = fase ? fase.precio : d.precio, max = Math.max(1, Math.min(10, fase?.quedan ?? 10));
  const c = abrirHoja("");
  const render = () => {
    c.innerHTML = `<h2 class="fuerte" style="font-size:22px;margin:10px 0 4px">${esc(d.nombre)}</h2>
      <div class="suave">${esc(d.club.nombre)} · ${esc(fechaCorta(d.fecha))} · ${esc(d.hora_inicio)}</div>
      <div class="caja" style="margin-top:22px;background:none;border:1px solid var(--borde)"><div class="cuerpo"><b>${esc(fase?.nombre || "Entrada general")}</b><small>${bs(precio)} c/u</small></div>
        <div class="contador"><button data-menos ${n <= 1 ? "disabled" : ""}>−</button><output>${n}</output><button data-mas ${n >= max ? "disabled" : ""}>+</button></div></div>
      ${pasoPago}<div class="total"><span>Total</span><b>${bs(precio * n)}</b></div><button class="boton" data-ok>Confirmar pedido</button>`;
    $("[data-menos]", c).onclick = () => { n--; render(); };
    $("[data-mas]", c).onclick = () => { n++; render(); };
    $("[data-ok]", c).onclick = async (ev) => {
      ev.currentTarget.innerHTML = `<span class="giro"></span>`;
      try {
        await rpc("aftr_comprar", { p_evento: d.id, p_fase: fase?.id || null, p_cantidad: n });
        c.innerHTML = listo("Pedido enviado", `${d.club.nombre} lo confirma y tus ${n === 1 ? "entrada aparece" : `${n} entradas aparecen`} en Accesos.`, "Ver en Accesos");
        ligarListo(c, () => (location.hash = "#/accesos"));
        cargarAccesos().catch(() => {});
      } catch (e) { avisar(mensaje(e)); render(); }
    };
  };
  render();
}
// el paso de pago: hoy el boliche confirma desde Venue; la pasarela va acá
const pasoPago = `<div class="paso-pago">${ICO.ok}<span>El boliche confirma tu pedido y tus QR aparecen en Accesos. Te avisamos ahí mismo.</span></div>`;

function hojaMesa(d) {
  let mesa = null, combo = null;
  const c = abrirHoja("");
  const combos = () => (mesa ? (d.combos || []).filter((k) => !(k.categorias || []).length || k.categorias.includes(mesa.categoria)) : []);
  const puede = () => mesa && (combo || (!d.combo_obligatorio && !combos().length));
  const render = () => {
    const cats = {};
    (d.mesas || []).forEach((m) => (cats[m.categoria || "Mesas"] ||= []).push(m));
    c.innerHTML = `<h2 class="fuerte" style="font-size:22px;margin:10px 0 4px">Reservá una mesa</h2><div class="suave">${d.mesas.length} disponibles · ${esc(d.club.nombre)}</div>
      ${Object.entries(cats).map(([k, ms]) => `<div class="etq" style="margin:22px 0 10px">${esc(k)}</div><div class="opciones-mesa">${ms.map((m) => `<button class="pildora ${mesa?.id === m.id ? "activa" : ""}" data-m="${m.id}">${esc(m.etiqueta)}</button>`).join("")}</div>`).join("")}
      ${combos().length ? `<div class="etq" style="margin:26px 0 10px">Elegí tu combo</div>${combos().map((k) => `<button class="combo ${combo?.id === k.id ? "si" : ""}" data-k="${k.id}"><div class="cuerpo"><b class="fuerte">${esc(k.nombre)}</b>
        ${(k.productos || []).length || k.descripcion ? `<div class="suave" style="font-size:13px;margin-top:4px">${esc((k.productos || []).length ? k.productos.join(" · ") : k.descripcion)}</div>` : ""}
        ${k.manillas ? `<div style="font-size:13px;color:var(--acento);margin-top:4px">Incluye ${k.manillas} manillas</div>` : ""}</div><b class="fuerte">${bs(k.precio)}</b></button>`).join("")}` : ""}
      ${pasoPago}<div class="total"><span>${mesa ? `Mesa ${esc(mesa.etiqueta)}` : "Elegí una mesa"}</span><b>${combo ? bs(combo.precio) : ""}</b></div>
      <button class="boton" data-ok ${puede() ? "" : "disabled"}>Reservar</button>`;
    $$("[data-m]", c).forEach((b) => (b.onclick = () => { mesa = d.mesas.find((m) => m.id === b.dataset.m); if (combo && !combos().includes(combo)) combo = null; render(); }));
    $$("[data-k]", c).forEach((b) => (b.onclick = () => { combo = d.combos.find((k) => k.id === b.dataset.k); render(); }));
    $("[data-ok]", c).onclick = async (ev) => {
      ev.currentTarget.innerHTML = `<span class="giro"></span>`;
      try {
        await rpc("aftr_reservar_mesa", { p_evento: d.id, p_mesa: mesa.id, p_combo: combo?.id || null });
        c.innerHTML = listo(`Mesa ${mesa.etiqueta} reservada`, `La guardamos para vos mientras ${d.club.nombre} confirma. Las manillas llegan a Accesos.`, "Ver en Accesos");
        ligarListo(c, () => (location.hash = "#/accesos"));
      } catch (e) { avisar(mensaje(e)); render(); }
    };
  };
  render();
}

/* ── lugar ──────────────────────────────────────────────────────────── */
const comoLlegar = (l) => `https://www.google.com/maps/dir/?api=1&destination=${l.lat},${l.lng}`;
async function pintarLugar(id) {
  const l = await rpc("aftr_lugar", { p_id: id });
  if (!l) { vista.innerHTML = `<div class="vacio"><p>Este lugar no está disponible.</p><a class="pildora" href="#/">Volver</a></div>`; return; }
  let sigo = l.siguiendo;
  const fotos = (l.fotos || []).length ? l.fotos : [l.eventos?.[0]?.flyer || l.logo];
  const render = () => {
    vista.innerHTML = `<div class="redondos" id="redondos"><button class="redondo" data-atras>${ICO.atras}</button><div class="titulo-mini">${esc(l.nombre)}</div><button class="redondo" data-comp>${ICO.comp}</button></div>
      <div class="portada"><div class="fotos-lugar" id="fotos">${fotos.map((f) => img(f, l.color)).join("")}</div>
      ${fotos.length > 1 ? `<div class="puntos">${fotos.map((_, i) => `<i class="${i ? "" : "si"}"></i>`).join("")}</div>` : ""}</div>
      <div class="det" style="margin-top:0;padding-top:20px"><div style="display:flex;gap:12px;align-items:flex-start">
        <div style="flex:1"><h1 class="titular aparecer" style="margin:0">${esc(l.nombre)}</h1>${l.subtitulo ? `<p style="margin:6px 0 0">${esc(l.subtitulo)}</p>` : ""}</div>
        <button class="seguir ${sigo ? "si" : ""}" data-seguir>${sigo ? "Siguiendo" : "Seguir"}</button></div>
        <div class="datos" style="margin-top:14px"><span>${ICO.lugar}${esc([l.direccion, l.zona, l.ciudad].filter(Boolean).join(", ") || "Sin dirección cargada")}</span></div>
        ${l.lat != null ? `<a class="pildora" style="margin-top:14px" target="_blank" rel="noopener" href="${comoLlegar(l)}">Cómo llegar</a>` : ""}
        ${l.descripcion ? `<p style="margin-top:22px">${esc(l.descripcion)}</p>` : ""}
        <h3 class="sec-tit" style="margin-top:30px">Próximos eventos</h3></div>
      ${(l.eventos || []).length ? l.eventos.map(filaEvento).join("") : `<p class="suave" style="padding:0 20px">No hay eventos publicados por ahora. Seguilo para enterarte.</p>`}`;
    ligarCabecera({ ...l, club: l }, null, null);
    $("[data-comp]").onclick = () => navigator.share ? navigator.share({ text: `${l.nombre} en AFTR`, url: location.href }).catch(() => {}) : navigator.clipboard?.writeText(location.href).then(() => avisar("Link copiado"));
    const tira = $("#fotos");
    tira?.addEventListener("scroll", () => {
      const i = Math.round(tira.scrollLeft / tira.clientWidth);
      $$(".puntos i").forEach((p, j) => p.classList.toggle("si", i === j));
    }, { passive: true });
    $("[data-seguir]").onclick = async () => {
      if (!(await asegurarCuenta())) return;
      sigo = !sigo; render();
      try { sigo = await rpc("aftr_seguir", { p_club: l.id }); } catch (e) { sigo = !sigo; avisar(mensaje(e)); }
      render();
    };
  };
  render();
}

/* ── mapa (MapLibre + CARTO oscuro) ─────────────────────────────────── */
const ESTILO = "https://basemaps.cartocdn.com/gl/dark-matter-gl-style/style.json";
async function pintarMapa() {
  vista.innerHTML = `<div class="mapa-pag"><div id="mapa"></div><div class="mapa-sombra" id="sombra"></div>
    <div class="mapa-arriba"><div class="buscador vidrio"><svg viewBox="0 0 24 24"><circle cx="11" cy="11" r="7"/><path d="M20 20l-4-4"/></svg>
      <input id="q" placeholder="Buscar fiestas, lugares, géneros" enterkeyhint="search"></div>
      <div class="filtros">${[["hoy", "Hoy"], ["mesas", "Con mesas"], ["listas", "Listas"], ["gratis", "Gratis"]].map(([f, t]) => `<button class="pildora densa" data-f="${f}">${t}</button>`).join("")}</div></div>
    <button class="centrar vidrio" id="centrar" aria-label="Centrar"><svg viewBox="0 0 24 24"><path d="M3 11l18-8-8 18-2-8z"/></svg></button>
    <section class="hoja-mapa" id="hmapa"><div class="manija"></div><div class="cabeza"><span id="vivo"></span><b id="cuenta"></b><span class="tenue solo-celu" style="font-size:12px">Deslizá para ver todos</span></div>
      <div class="tarjetas-pin" id="tpins"></div><div class="lista" id="lmapa"></div></section></div>`;
  const [eventos, lugares] = await Promise.all([cargarEventos(), cargarLugares()]);
  if (ruta().nombre !== "mapa") return;
  const filtros = new Set();
  let elegido = 0, pines = [], marcadores = [];
  const mapa = new maplibregl.Map({ container: "mapa", style: ESTILO, center: [-63.1821, -17.7833], zoom: 12.5, attributionControl: { compact: true } });
  mapa.addControl(new maplibregl.GeolocateControl({ positionOptions: { enableHighAccuracy: true }, showUserLocation: true }), "bottom-right");
  limpiar = () => mapa.remove();

  const filtrar = () => {
    const q = $("#q").value.trim().toLowerCase();
    return eventos.filter((e) => {
      if (filtros.has("hoy") && !esHoy(e)) return false;
      if (filtros.has("mesas") && !e.mesas_libres) return false;
      if (filtros.has("listas") && !e.tiene_lista) return false;
      if (filtros.has("gratis") && !(e.desde_precio === 0 || e.tiene_lista)) return false;
      if (q && ![e.nombre, e.club?.nombre, e.club?.zona, ...(e.generos || [])].some((s) => (s || "").toLowerCase().includes(q))) return false;
      return true;
    }).sort((a, b) => new Date(a.inicio) - new Date(b.inicio));
  };
  const encuadrar = (animar = true) => {
    if (!pines.length) return;
    const b = new maplibregl.LngLatBounds();
    pines.forEach((p) => b.extend([p.l.lng, p.l.lat]));
    const ancho = innerWidth >= 900;
    mapa.fitBounds(b, { padding: { top: 140, bottom: ancho ? 60 : innerHeight * 0.36, left: ancho ? 480 : 60, right: 60 }, maxZoom: 15, duration: animar ? 900 : 0 });
  };
  const elegir = (i, desdePin) => {
    elegido = i;
    marcadores.forEach((m, j) => m.getElement().classList.toggle("si", j === i));
    $$(".tpin").forEach((t, j) => t.classList.toggle("si", j === i));
    const p = pines[i];
    if (!p) return;
    mapa.easeTo({ center: [p.l.lng, p.l.lat], offset: [innerWidth >= 900 ? 210 : 0, innerWidth >= 900 ? 0 : -innerHeight * 0.12], duration: 600 });
    if (desdePin) {
      const t = $$(".tpin")[i];
      t?.scrollIntoView({ behavior: "smooth", inline: "center", block: "nearest" });
      if (alto > PEEK + 0.02) fijarAlto(PEEK);
    }
  };
  const render = () => {
    const filt = filtrar(), todos = !filtros.size && !$("#q").value.trim();
    const primero = {};
    filt.forEach((e) => (primero[e.club.id] ||= e));
    pines = lugares.filter((l) => l.lat != null && l.lng != null && (primero[l.id] || todos)).map((l) => ({ l, e: primero[l.id] || null }))
      .sort((a, b) => (a.e && b.e ? new Date(a.e.inicio) - new Date(b.e.inicio) : a.e ? -1 : b.e ? 1 : a.l.nombre.localeCompare(b.l.nombre)));
    marcadores.forEach((m) => m.remove());
    marcadores = pines.map((p, i) => {
      const el = document.createElement("button");
      el.className = `pin cae ${p.e && esHoy(p.e) ? "hoy" : ""} ${p.e ? "" : "apagado"} ${i === elegido ? "si" : ""}`;
      el.style.animationDelay = `${i * 40}ms`;
      el.textContent = (p.l.nombre || "A").slice(0, 1).toUpperCase();
      el.onclick = (ev) => { ev.stopPropagation(); elegir(i, true); };
      return new maplibregl.Marker({ element: el }).setLngLat([p.l.lng, p.l.lat]).addTo(mapa);
    });
    const hoy = filt.filter(esHoy).length;
    $("#vivo").innerHTML = hoy ? `<span class="punto-vivo"></span>` : "";
    $("#cuenta").textContent = !filt.length ? "Sin eventos con estos filtros" : hoy ? `${hoy} esta noche · ${filt.length} en total` : `${filt.length} ${filt.length === 1 ? "evento" : "eventos"}`;
    $("#tpins").innerHTML = pines.map((p, i) => `<a class="tpin ${i === elegido ? "si" : ""}" href="${p.e ? `#/evento/${p.e.id}` : `#/lugar/${encodeURIComponent(p.l.id)}`}">
      ${img(p.e?.flyer || p.l.fotos?.[0] || p.l.logo, p.l.color)}<div class="cuerpo"><span class="etq oro">${esc(p.l.nombre)}</span>
      <b>${esc(p.e?.nombre || "Sin eventos próximos")}</b>${p.e ? `<small>${esc(linea(p.e))}</small>` : ""}${p.e && precioDesde(p.e) ? `<small style="color:#fff;font-weight:700;margin-top:6px">${esc(precioDesde(p.e))}</small>` : ""}</div></a>`).join("");
    $("#lmapa").innerHTML = filt.length ? `<h3 class="fuerte" style="font-size:20px;margin:22px 20px 8px">Todos los eventos</h3>${filt.map(filaEvento).join("")}`
      : lugares.some((l) => l.lat != null) ? "" : `<p class="suave" style="padding:12px 20px">Los boliches todavía no cargaron su ubicación en Venue.</p>`;
  };
  // tarjeta centrada en el carrusel = pin elegido
  let tScroll;
  $("#tpins").addEventListener("scroll", () => {
    clearTimeout(tScroll);
    tScroll = setTimeout(() => {
      const t = $("#tpins"), centro = t.scrollLeft + t.clientWidth / 2;
      let mejor = 0, dist = 1e9;
      $$(".tpin", t).forEach((x, i) => { const d = Math.abs(x.offsetLeft + x.offsetWidth / 2 - centro); if (d < dist) { dist = d; mejor = i; } });
      if (mejor !== elegido) elegir(mejor, false);
    }, 120);
  }, { passive: true });
  $("#q").oninput = () => { elegido = 0; render(); };
  $$("[data-f]").forEach((b) => (b.onclick = () => { filtros.has(b.dataset.f) ? filtros.delete(b.dataset.f) : filtros.add(b.dataset.f); b.classList.toggle("activa"); elegido = 0; render(); encuadrar(); }));
  $("#centrar").onclick = () => encuadrar();

  // la hoja que se jala: tres alturas con imán (peek, medio, lleno)
  const PEEK = 0.34, MEDIO = 0.6, LLENO = 0.93, hoja = $("#hmapa"), lista = $("#lmapa");
  let alto = PEEK;
  const fijarAlto = (a, sinAnim) => {
    alto = a;
    hoja.classList.toggle("arrastrando", !!sinAnim);
    hoja.style.height = `${a * 100}vh`;
    const o = Math.min(1, Math.max(0, (a - MEDIO) / (LLENO - MEDIO)));
    $("#sombra").style.opacity = 0.7 * o;
    $("#centrar").style.bottom = `calc(${Math.min(Math.max(a, PEEK), MEDIO) * 100}vh + 12px)`;
    $("#centrar").style.opacity = 1 - o;
  };
  fijarAlto(PEEK);
  let y0 = null, a0 = 0, t0 = 0;
  hoja.addEventListener("pointerdown", (e) => {
    if (innerWidth >= 900 || (e.target.closest("#lmapa") && lista.scrollTop > 0) || e.target.closest("#tpins")) return;
    y0 = e.clientY; a0 = alto; t0 = performance.now();
  });
  addEventListener("pointermove", (e) => {
    if (y0 == null) return;
    const a = Math.min(LLENO, Math.max(PEEK - 0.04, a0 + (y0 - e.clientY) / innerHeight));
    if (Math.abs(a - a0) > 0.01) fijarAlto(a, true);
  });
  addEventListener("pointerup", (e) => {
    if (y0 == null) return;
    const v = (y0 - e.clientY) / (performance.now() - t0); // px/ms, positivo = sube
    y0 = null;
    const opciones = [PEEK, MEDIO, LLENO];
    let destino = opciones.reduce((m, o) => (Math.abs(o - alto) < Math.abs(m - alto) ? o : m));
    if (Math.abs(v) > 0.5) destino = opciones[Math.min(2, Math.max(0, opciones.indexOf(destino) + (v > 0 ? 1 : -1)))] ?? destino;
    fijarAlto(destino);
  });
  render();
  mapa.on("load", () => encuadrar(false));
}

/* ── accesos (billetera apilada) ────────────────────────────────────── */
let abierta = null;
async function pintarAccesos() {
  if (!E.sesion) {
    vista.innerHTML = `<div class="pagina"><h1 class="titular">Accesos</h1><div style="padding:40px 4px"><img src="img/marca.svg" style="height:56px;margin-bottom:24px" alt="">
      <h2 class="titular" style="font-size:30px;margin:0 0 10px">Tus entradas, en un solo lugar.</h2>
      <p class="suave">Entrá para comprar, anotarte en listas, reservar mesas y recibir entradas de tus amigos.</p><button class="boton" data-entrar style="margin-top:24px">Entrar</button></div></div>`;
    $("[data-entrar]").onclick = asegurarCuenta;
    return;
  }
  if (!E.accesos) vista.innerHTML = `<div class="pagina"><h1 class="titular">Accesos</h1><div class="esq" style="height:200px;border-radius:24px"></div></div>`;
  await cargarPerfil();
  if (!E.perfil) { vista.innerHTML = `<div class="pagina"><h1 class="titular">Accesos</h1><button class="boton" onclick="abrirBienvenida()">Completar perfil</button></div>`; return; }
  await cargarAccesos();
  if (ruta().nombre !== "accesos") return;
  const prox = proximos(E.accesos), pas = pasados(E.accesos);
  if (!prox.find((a) => a.id === abierta)) abierta = null;
  vista.innerHTML = `<div class="pagina"><h1 class="titular">Accesos ${abierta ? `<button class="pildora densa" data-cerrar-t>Cerrar</button>` : ""}</h1>
    ${prox.length ? `<div class="pila" id="pila">${prox.map((a, i) => tarjetaWallet(a, i)).join("")}</div>`
      : `<div class="vacio-caja"><img src="img/marca.svg" alt=""><h3 class="fuerte" style="font-size:20px;margin:0 0 6px">Tu próxima noche va acá</h3>
        <p class="suave" style="margin:0 0 20px">Las entradas, listas y mesas que consigas aparecen con su QR.</p><a class="boton" href="#/">Explorar eventos</a></div>`}
    ${pas.length && !abierta ? `<h3 class="fuerte" style="font-size:20px;margin:34px 4px 8px">Historial</h3>${pas.slice(0, 30).map((a) => `<div class="fila" style="padding:8px 4px">${img(a.evento.flyer, a.evento.club?.color).replace('class="img ', 'style="width:48px;height:48px;border-radius:12px;flex:none" class="img ')}
      <div class="cuerpo"><b style="font-size:15px">${esc(a.evento.nombre)}</b><span class="suave">${esc(a.titulo)} · ${esc(fechaCorta(a.evento.fecha))}</span></div>
      <span class="tenue" style="font-size:13px">${{ usada: "Usada", anulada: "Anulada", valida: "Sin usar", pendiente: "Pendiente" }[a.estado]}</span></div>`).join("")}` : ""}</div>`;
  apilar(prox);
  $("[data-cerrar-t]")?.addEventListener("click", () => { abierta = null; pintarAccesos(); });
}
function tarjetaWallet(a, i) {
  const pend = a.estado === "pendiente";
  return `<div class="tarjeta-wallet aparecer" style="--o:${i}" data-id="${a.id}">${img(a.evento.flyer, a.evento.club?.color)}<div class="degrade"></div>
    <div class="tw-cuerpo"><div style="display:flex;align-items:center"><span class="etq" style="color:#fff">${{ entrada: "Entrada", lista: "Lista", pedido: "Pedido" }[a.tipo]}</span>
      <span style="margin-left:auto;display:flex;align-items:center">${pend ? `<span class="punto-vivo" style="--pc:var(--acento)"></span><span class="etq oro">Esperando al boliche</span>` : `<img src="img/marca.svg" style="height:16px" alt="">`}</span></div>
      <h3>${esc(a.evento.nombre)}</h3><div style="font-size:13px">${esc(a.evento.club?.nombre)} · ${esc(fechaCorta(a.evento.fecha))} · ${esc(a.evento.hora_inicio)}</div>
      ${a.id === abierta ? abiertaHtml(a) : `<div class="tw-pie"><div class="cuerpo"><b>${esc(a.titulo)}</b>${a.detalle ? `<div style="font-size:13px">${esc(a.detalle)}</div>` : ""}</div>
        ${pend && a.total != null ? `<b class="fuerte" style="font-size:18px">${bs(a.total)}</b>` : ""}${a.qr && a.estado === "valida" ? `<svg width="30" height="30" viewBox="0 0 24 24" fill="none" stroke="#fff" stroke-width="1.6"><rect x="3" y="3" width="7" height="7"/><rect x="14" y="3" width="7" height="7"/><rect x="3" y="14" width="7" height="7"/><path d="M14 14h3v3h-3zM18 18h3v3h-3z"/></svg>` : ""}</div>`}
    </div></div>`;
}
function abiertaHtml(a) {
  const club = a.evento.club || {};
  if (a.qr && a.estado === "valida") {
    const q = qrcode(0, "M"); q.addData(a.qr); q.make();
    return `<div class="tw-abierta"><div class="qr">${q.createSvgTag({ cellSize: 6, margin: 0, scalable: true })}</div><div class="codigo">${esc(a.code)}</div>
      <div class="suave" style="font-size:13px">${esc([a.titulo, a.detalle].filter(Boolean).join(" · "))}</div>
      <div class="acciones">${a.transferible ? `<button class="boton" data-enviar>Enviar a un amigo</button>` : ""}
      ${club.lat != null ? `<a class="circ" target="_blank" rel="noopener" href="${comoLlegar(club)}">${ICO.ir}</a>` : ""}</div></div>`;
  }
  return `<div class="tw-abierta"><b class="fuerte" style="font-size:20px">${esc(a.titulo)}</b>
    <p style="margin:6px 0 10px">${esc(club.nombre)} tiene que confirmar tu pedido. Cuando lo haga, tus QR aparecen acá solos.</p>
    ${a.total != null ? `<b class="fuerte" style="font-size:24px">${bs(a.total)}</b>` : ""}
    <div class="acciones">${a.tipo === "pedido" ? `<button class="boton sec" data-cancelar>Cancelar pedido</button>` : ""}</div></div>`;
}
function apilar(prox) {
  const pila = $("#pila");
  if (!pila) return;
  const ancho = pila.clientWidth, altoA = Math.min(ancho * 1.32, innerHeight * 0.78), altoC = 210, CAB = 86, APR = 14;
  const iA = prox.findIndex((a) => a.id === abierta);
  pila.style.height = `${iA < 0 ? CAB * (prox.length - 1) + altoC : altoA + 18 + APR * (prox.length - 1) + CAB * 0.6}px`;
  $$(".tarjeta-wallet", pila).forEach((t, i) => {
    const top = iA < 0 ? CAB * i : i === iA ? 0 : altoA + 18 + APR * (i < iA ? i : i - 1);
    Object.assign(t.style, { top: `${top}px`, height: `${i === iA ? altoA : altoC}px`, left: iA >= 0 && i !== iA ? "8px" : "0", right: iA >= 0 && i !== iA ? "8px" : "0", zIndex: i === iA ? 50 : i });
    t.classList.toggle("abierta", i === iA);
    t.onclick = (e) => {
      if (e.target.closest("button, a")) return;
      abierta = abierta === prox[i].id ? null : prox[i].id;
      pintarAccesos();
    };
    $("[data-enviar]", t)?.addEventListener("click", () => hojaEnviar(prox[i]));
    $("[data-cancelar]", t)?.addEventListener("click", async (e) => {
      e.currentTarget.innerHTML = `<span class="giro"></span>`;
      try { await rpc("aftr_cancelar_mi_orden", { p_orden: prox[i].id }); abierta = null; await cargarAccesos(); pintarAccesos(); } catch (er) { avisar(mensaje(er)); pintarAccesos(); }
    });
  });
}

function hojaEnviar(a) {
  let para = null, res = [], t;
  const c = abrirHoja("");
  const render = (q = "") => {
    c.innerHTML = `<h2 class="fuerte" style="font-size:22px;margin:10px 0 4px">Enviar a un amigo</h2><div class="suave">${esc(a.titulo)} · ${esc(a.evento.nombre)}</div>
      <div class="caja" id="volador" style="margin-top:18px;background:linear-gradient(90deg,${esc(a.evento.club?.color || "#26262a")}80,var(--sup2))">${ICO.ticket.replace("<svg", '<svg width="22" height="22" fill="none" stroke="#fff" stroke-width="1.8"')}
        <div class="cuerpo"><b>${esc(a.evento.nombre)} · ${esc(fechaCorta(a.evento.fecha))}</b></div>${para ? `<span style="color:var(--acento);font-weight:600">@${esc(para.usuario)}</span>` : ""}</div>
      <input class="buscar-amigo" id="amigo" placeholder="@usuario o nombre" value="${esc(q)}" autocapitalize="off" autocorrect="off" spellcheck="false">
      <div>${res.map((p, i) => `<button class="persona aparecer" style="--o:${i}" data-u="${esc(p.usuario)}"><span class="avatar">${esc((p.nombre || "?").slice(0, 1).toUpperCase())}</span>
        <span class="cuerpo"><b class="fuerte">${esc(p.nombre)}</b><br><span class="suave" style="font-size:13px">@${esc(p.usuario)}</span></span><span class="marca" style="${para?.usuario === p.usuario ? "border-color:var(--acento);background:var(--acento)" : ""}"></span></button>`).join("")}
      ${q.replace("@", "").length >= 2 && !res.length ? `<p class="suave">No encontramos a nadie con ese nombre.</p><button class="pildora" data-invitar>Invitalo a AFTR</button>` : ""}</div>
      ${para ? `<p class="tenue" style="text-align:center;font-size:13px;margin:16px 0 10px">Tu QR deja de servir y ${esc(para.nombre)} recibe uno nuevo.</p>` : ""}
      <button class="boton" data-enviar style="margin-top:12px" ${para ? "" : "disabled"}>${para ? `Enviar a @${esc(para.usuario)}` : "Elegí a quién"}</button>`;
    const inp = $("#amigo", c);
    inp.focus(); inp.setSelectionRange(q.length, q.length);
    inp.oninput = () => {
      clearTimeout(t); para = null;
      const v = inp.value;
      if (v.replace("@", "").trim().length < 2) { res = []; return render(v); }
      t = setTimeout(async () => { try { res = (await rpc("aftr_buscar_usuario", { p_q: v })) || []; } catch { res = []; } render(v); }, 280);
    };
    $$("[data-u]", c).forEach((b) => (b.onclick = () => { para = res.find((p) => p.usuario === b.dataset.u); render(inp.value); }));
    $("[data-invitar]", c)?.addEventListener("click", () => {
      const texto = `Entrá a AFTR para que te pase la entrada de ${a.evento.nombre}: ahí vas a tener tu QR. ${location.origin}${location.pathname}`;
      navigator.share ? navigator.share({ text: texto }).catch(() => {}) : navigator.clipboard?.writeText(texto).then(() => avisar("Invitación copiada"));
    });
    $("[data-enviar]", c).onclick = async (ev) => {
      ev.currentTarget.innerHTML = `<span class="giro"></span>`;
      try {
        await rpc("aftr_transferir", { p_entrada: a.id, p_usuario: para.usuario });
        $("#volador", c).classList.add("vuela");
        await new Promise((r) => setTimeout(r, 650));
        c.innerHTML = listo("Entrada enviada", `Ya la tiene ${para.nombre} en su AFTR. Tu QR quedó sin efecto.`, "Listo");
        ligarListo(c);
        abierta = null; await cargarAccesos(); if (ruta().nombre === "accesos") pintarAccesos();
      } catch (e) { avisar(mensaje(e)); render(inp.value); }
    };
  };
  render();
}

/* ── cuenta ─────────────────────────────────────────────────────────── */
async function pintarCuenta() {
  if (!E.sesion) {
    vista.innerHTML = `<div class="pagina"><h1 class="titular">Cuenta</h1><div style="padding:60px 4px"><div class="palabra-barra" style="height:30px;margin:0 0 18px">${["a", "f", "t", "r"].map((l) => `<img src="img/${l}.svg" alt="">`).join("")}</div>
      <p style="font-size:16px">Guardá eventos, seguí lugares y tené tus QR siempre a mano.</p><button class="boton" data-entrar style="margin-top:22px">Entrar</button></div></div>`;
    $("[data-entrar]").onclick = asegurarCuenta;
    return;
  }
  await cargarPerfil();
  const g = await rpc("aftr_mis_guardados").catch(() => ({ eventos: [], lugares: [] }));
  if (ruta().nombre !== "cuenta") return;
  const p = E.perfil;
  vista.innerHTML = `<div class="pagina"><h1 class="titular">Cuenta</h1>
    <div class="perfil aparecer"><span class="avatar">${esc((p?.nombre || "?").slice(0, 1).toUpperCase())}</span><div><b class="fuerte" style="font-size:24px">${esc(p?.nombre || "")}</b>
      ${p ? `<div class="suave">@${esc(p.usuario)}</div>` : ""}</div></div>
    ${!p ? `<button class="boton" style="margin-top:20px" onclick="abrirBienvenida()">Completar perfil</button>` : ""}
    ${g.eventos?.length ? `<h3 class="fuerte" style="font-size:22px;margin:30px 4px 14px">Guardados</h3><div class="carrusel" style="padding:0 4px">${g.eventos.map(tarjeta).join("")}</div>` : ""}
    ${g.lugares?.length ? `<h3 class="fuerte" style="font-size:22px;margin:30px 4px 6px">Siguiendo</h3>${g.lugares.map((l, i) => filaLugar(l, i).replace('class="fila ', 'style="padding:8px 4px" class="fila ')).join("")}` : ""}
    <h3 class="fuerte" style="font-size:22px;margin:30px 4px 6px">Ajustes</h3>
    <a class="opcion" href="#/accesos">${ICO.ticket}Mis accesos</a>
    <button class="opcion" data-salir>${ICO.salir}Cerrar sesión</button>
    <button class="opcion mal" data-borrar>${ICO.borrar}Eliminar cuenta</button>
    <img src="img/marca.svg" style="height:26px;margin:30px auto 8px;opacity:.35" alt=""><p class="tenue" style="text-align:center;font-size:12px;margin:0">AFTR · Nightlife &amp; Events</p></div>`;
  $("[data-salir]").onclick = async () => { await sb.auth.signOut(); };
  $("[data-borrar]").onclick = () => {
    const c = abrirHoja(`<h2 class="fuerte" style="font-size:22px;margin:14px 0 8px">¿Eliminar tu cuenta?</h2>
      <p class="suave">Se borran tu perfil, tus guardados y los lugares que seguís. Las entradas que tengas dejan de estar a tu nombre en AFTR. No se puede deshacer.</p>
      <button class="boton" data-si style="margin-top:22px">Eliminar cuenta</button><button class="boton sec" data-no style="margin-top:10px">Cancelar</button>`);
    $("[data-no]", c).onclick = cerrarHoja;
    $("[data-si]", c).onclick = async () => {
      try { await rpc("aftr_eliminar_cuenta"); cerrarHoja(); await sb.auth.signOut(); avisar("Tu cuenta se eliminó."); } catch (e) { avisar(mensaje(e)); }
    };
  };
}

/* ── inicio ─────────────────────────────────────────────────────────── */
armarPalabra($(".palabra-barra"));
arranque();
pintarAvatar();
// supabase-js se traba si se espera otra llamada dentro de este aviso: se
// difiere al siguiente turno
sb.auth.onAuthStateChange((_ev, sesion) => setTimeout(() => alCambiarSesion(sesion), 0));
async function alCambiarSesion(sesion) {
  const antes = E.sesion?.user?.id;
  E.sesion = sesion;
  if (antes === sesion?.user?.id && antes !== undefined) return;
  if (canal) { sb.removeChannel(canal); canal = null; }
  E.accesos = null;
  await cargarPerfil();
  if (sesion && !E.perfil) abrirBienvenida();
  if (sesion) cargarAccesos().catch(() => {});
  else $("#globo").hidden = true;
  pintar();
}
pintar();
