/* ============================================================
   VENUE · listas, entradas QR y puerta (boliches dinámicos)
   Front vanilla + Supabase
   ============================================================ */
/* Dentro de Accesos, las pantallas de Invitados y Entradas escriben en
   #main y se repintan solas desde sus propios handlers (filtros, orden,
   marcar un ingreso). Eso borraba el shell de la sección y dejaba al
   usuario adentro sin navegación.
   Redirigiendo el selector a #accBody, esos repintados caen dentro del
   cuerpo y la navegación de arriba sobrevive, sin tocar el código de las
   pantallas ni la lógica de negocio. */
let accRedir = false;
const $ = s => {
  if (accRedir && s === "#main") {
    const b = document.getElementById("accBody");
    if (b) return b;
  }
  return document.querySelector(s);
};

/* Igual que document.querySelectorAll, pero "#main" también alcanza al
   cuerpo de Accesos. Sin esto, los botones de fila se pintaban dentro de
   #accBody y sus handlers —que buscan "#main [data-x]"— no los
   encontraban: se veían pero no respondían. */
function qsa(sel) {
  if (accRedir) {
    const b = document.getElementById("accBody");
    if (b) {
      // Cada parte se reescribe por separado: un selector compuesto como
      // "#main [x], #accBody [x]" no se puede recortar de una sola vez.
      const dentro = sel.split(",").map(s => s.trim())
        .map(s => s.startsWith("#main ") ? s.slice(6)
                : s.startsWith("#accBody ") ? s.slice(9) : s)
        .join(", ");
      const r = b.querySelectorAll(dentro);
      if (r.length) return r;
    }
  }
  return document.querySelectorAll(sel);
}

const CFG = window.CONFIG || {};
/* Las RPC de solo-lectura (PostgREST manda TODAS las RPC por POST, así que
   el método no alcanza para distinguirlas). Cualquier RPC fuera de esta
   lista se trata como escritura e invalida el caché de pantallas. */
const RPC_LECTURA = new Set([
  "resumen_evento", "liquidacion_evento", "historico_eventos", "ranking_rrpp",
  "reporte_fases", "reporte_filtro", "fases_evento", "fase_vigente",
  "cupos_fase", "ventana_venta", "excepciones_venta", "mis_cupos",
  "mis_permisos_mesa", "mi_telefono", "roster_relacionadores", "roster_cupos",
  "roster_mi_team", "usuarios_sin_tope", "telefonos_equipo", "teams_efectivos",
  "vendedores_posibles", "buscar_registros", "avisos_admin",
  "avisos_pendientes", "aviso_lectores", "bar_disponibilidad",
  "bar_cortesias_evento", "bar_proyeccion_compra", "bar_conteo_pendiente",
]);
let sb = null;
if (CFG.SUPABASE_URL && CFG.SUPABASE_ANON_KEY) {
  sb = window.supabase.createClient(CFG.SUPABASE_URL, CFG.SUPABASE_ANON_KEY, {
    global: {
      /* Toda escritura que el servidor confirme limpia el caché de datos de
         pantalla (ver conDatos): después de anular/generar/tickear, la
         próxima pintada pide fresco. Las lecturas no tocan nada. */
      fetch: (url, opts = {}) => {
        const p = fetch(url, opts);
        const u = String(url);
        if (u.includes("/rest/v1/")) {
          const metodo = (opts.method || "GET").toUpperCase();
          const rpc = u.includes("/rest/v1/rpc/") ? u.split("/rest/v1/rpc/")[1].split("?")[0] : null;
          const esLectura = metodo === "GET" || (rpc && RPC_LECTURA.has(rpc));
          if (!esLectura) p.then(r => { if (r.ok) dataCache.clear(); }).catch(() => {});
        }
        return p;
      },
    },
  });
} else {
  $("#loginCard").innerHTML = `<div class="setupbox"><b>Falta configurar Supabase.</b><br>
  Copiá <code>config.example.js</code> como <code>config.js</code> y completalo
  con la URL y la anon key del proyecto (Dashboard → Settings → API) y recargá.</div>`;
}

/* ---------- traer listados completos ----------
   PostgREST corta toda respuesta en 1000 filas (db_max_rows del proyecto) y no
   avisa: devuelve las primeras 1000 como si fueran todas. Con eso, cualquier
   contador que salga de contar el array miente en cuanto una noche pasa las
   1000 filas — y encima subir el .limit() no arregla nada, porque el tope es
   del servidor. Se pide de a páginas hasta traer todo.

   Pasar SIEMPRE un .order() estable en la query, o las páginas se pisan.
   `truncado` avisa si se llegó al techo duro (algo raro está pasando). */
/* Cuánto dura una reserva de mesa sin pagar. Es solo el texto que se le
   muestra a la gente: el vencimiento real lo fija la base al reservar y
   viaja en la mesa (reserva_vence_at), así que cambiar este número no le
   corre el plazo a ninguna reserva que ya esté hecha. */
const HORAS_RESERVA = 3;   // respaldo, por si el evento no lo trae
const horasReserva = () => (ev && ev.horas_reserva) || HORAS_RESERVA;

const PAGINA = 1000, TECHO = 20000;
async function traerTodo(hacerQuery) {
  const filas = [];
  for (let desde = 0; desde < TECHO; desde += PAGINA) {
    const { data, error } = await hacerQuery().range(desde, desde + PAGINA - 1);
    if (error) return { data: null, error, truncado: false };
    filas.push(...(data || []));
    if (!data || data.length < PAGINA) return { data: filas, error: null, truncado: false };
  }
  return { data: filas, error: null, truncado: true };
}

/* ---------- caché de datos de pantalla ----------
   El costo real de cambiar de tab es la RED: en la conexión del boliche
   cada viaje a Supabase tarda ~0,5-1 s, y cada pantalla volvía a pedir
   TODO en cada visita. Las lecturas quedan en memoria unos segundos,
   claveadas por boliche+evento (cambiar de local o de evento nunca mezcla
   datos porque cambia la clave), y CUALQUIER escritura confirmada limpia
   el caché entero (fetch interceptado arriba). El TTL corto acota lo que
   puede verse viejo por cambios hechos desde OTRO dispositivo. */
const dataCache = new Map();
const DATA_TTL = 45000;
const cacheKey = n => `${club}|${ev?.id || ""}|${n}`;
async function conDatos(nombre, fn, ttl = DATA_TTL) {
  const k = cacheKey(nombre);
  const hit = dataCache.get(k);
  if (hit && Date.now() - hit.at < ttl) return hit.v;
  const v = await fn();
  dataCache.set(k, { v, at: Date.now() });
  return v;
}

/* ---------- estado ---------- */
let me = null;            // profile
let myTeamClubs = null;   // boliches donde existe el team de la persona
let club = null;
let clubsDisponibles = []; // filas de `clubs`, cargadas una vez en boot()
const clubData = id => clubsDisponibles.find(c => c.id === id) || null;
const clubNombre = id => clubData(id)?.nombre || id;
// boliches donde el usuario puede operar (admin: todos los que existan) — usa la identidad base
/* `clubs` ya llega recortado por el servidor (RLS) a los locales donde la
   persona tiene algún rol: no hay regla que recalcular acá. Antes "sin
   boliches" valía "todos", y un admin veía todos los locales de la base. */
const myClubs = () => clubsDisponibles.map(c => c.id);
let eventos = [];         // eventos del club
let ev = null;            // evento seleccionado
let tab = "";
let listaTipos = [];

function hexToRgba(hex, alpha) {
  const h = (hex || "").replace('#', '');
  const r = parseInt(h.slice(0, 2), 16) || 0, g = parseInt(h.slice(2, 4), 16) || 0, b = parseInt(h.slice(4, 6), 16) || 0;
  return `rgba(${r},${g},${b},${alpha})`;
}
/* Inyecta los tokens de marca del boliche activo directo sobre #app:
   reemplaza lo que antes eran bloques CSS fijos por data-club. */
function aplicarTemaClub(c) {
  const el = document.getElementById("app");
  if (!el || !c) return;
  el.style.setProperty("--brand-primary", c.color_primario);
  el.style.setProperty("--brand-secondary", c.color_secundario);
  el.style.setProperty("--brand-accent", c.color_accent);
  el.style.setProperty("--brand-soft", hexToRgba(c.color_primario, .14));
  el.style.setProperty("--brand-glow", hexToRgba(c.color_primario, .32));
  el.style.setProperty("--brand-tint", hexToRgba(c.color_primario, .05));
  el.style.setProperty("--lounge", c.color_secundario);
  el.style.setProperty("--lounge-bd", hexToRgba(c.color_primario, .4));
}
/* Marca de texto genérica para cualquier boliche (reemplaza los SVG a
   medida de MARK_SVG, que solo cubrían 2 locales fijos). */
function clubMarkHTML(id) {
  const c = clubData(id);
  const letra = esc((c?.inicial || c?.nombre || "?").slice(0, 1).toUpperCase());
  return `<span class="club-mark-txt">${letra}</span>`;
}
// íconos de línea (heredan color con currentColor)
const IC = {
  people: '<svg viewBox="0 0 24 24" class="ic"><circle cx="9" cy="8" r="3.2"/><path d="M3.5 19c0-3 2.5-5 5.5-5s5.5 2 5.5 5"/><path d="M16 6.2a3 3 0 0 1 0 5.6M17.5 14c2.4.3 4 2.2 4 5"/></svg>',
  qr: '<svg viewBox="0 0 24 24" class="ic"><rect x="3" y="3" width="7" height="7" rx="1.3"/><rect x="14" y="3" width="7" height="7" rx="1.3"/><rect x="3" y="14" width="7" height="7" rx="1.3"/><path d="M14 14h3v3M20 14v.01M20 20v.01M17 20v.01M20 17h.01"/></svg>',
  mesa: '<svg viewBox="0 0 24 24" class="ic"><path d="M4 9h16M6 9l1.5 5M18 9l-1.5 5M5 6.5C5 5 8 4 12 4s7 1 7 2.5S16 9 12 9 5 8 5 6.5Z"/><path d="M8 14l-1 6M16 14l1 6"/></svg>',
  pincheck: '<svg viewBox="0 0 24 24" class="ic"><circle cx="10" cy="8" r="3.2"/><path d="M4 19c0-3.2 2.7-5 6-5"/><path d="M14.5 18.5l1.8 1.8L21 15.5"/></svg>',
  door: '<svg viewBox="0 0 24 24" class="ic"><path d="M6 21V4a1 1 0 0 1 1-1h8a1 1 0 0 1 1 1v17M6 21h12M6 21H4M18 21h2M13 12v1.5"/></svg>',
  star: '<svg viewBox="0 0 24 24" class="ic"><path d="M12 3.5l2.6 5.3 5.9.8-4.3 4.1 1 5.8-5.2-2.7-5.2 2.7 1-5.8L3.5 9.6l5.9-.8L12 3.5Z"/></svg>',
  list: '<svg viewBox="0 0 24 24" class="ic"><path d="M8 6h12M8 12h12M8 18h12M4 6h.01M4 12h.01M4 18h.01"/></svg>',
  shield: '<svg viewBox="0 0 24 24" class="ic"><path d="M12 3l7 3v5c0 4.5-3 7.6-7 9-4-1.4-7-4.5-7-9V6l7-3Z"/><path d="M9 12l2 2 4-4"/></svg>',
  clock: '<svg viewBox="0 0 24 24" class="ic"><circle cx="12" cy="12" r="8.5"/><path d="M12 7.5V12l3 2"/></svg>',
  up: '<svg viewBox="0 0 24 24" class="ic"><path d="M12 19V6M6 11l6-6 6 6"/></svg>',
  person: '<svg viewBox="0 0 24 24" class="ic"><circle cx="12" cy="8" r="3.4"/><path d="M5.5 20c0-3.4 2.9-5.6 6.5-5.6s6.5 2.2 6.5 5.6"/></svg>',
  tag: '<svg viewBox="0 0 24 24" class="ic"><circle cx="9" cy="8" r="3"/><path d="M3.5 19c0-2.9 2.4-4.8 5.5-4.8s5.5 1.9 5.5 4.8"/><path d="M16 6a3 3 0 0 1 0 5.5M17.5 14c2.2.3 3.8 2 3.8 4.6"/></svg>',
  clock2: '<svg viewBox="0 0 24 24" class="ic"><circle cx="12" cy="12" r="8.5"/><path d="M12 7.5V12l3 2"/></svg>'
};
const icoLista = n => { const s = (n || "").toLowerCase();
  return /puerta/.test(s) ? IC.door : /free|girl|cover|vip/.test(s) ? IC.star : /invit/.test(s) ? IC.people : IC.list; };
const accLabel = on => on ? "Orden normal" : `<span class="acc-ic">${IC.up}</span>Accedieron`;
async function copyText(txt) {
  try { await navigator.clipboard.writeText(txt); }
  catch (e) { const ta = document.createElement("textarea"); ta.value = txt; document.body.appendChild(ta); ta.select(); try { document.execCommand("copy"); } catch (e2) { } ta.remove(); }
}
// registro de mesas/combos en texto (formato planimetría), copiado al portapapeles
async function copyRegistroMesas() {
  const { data: ms } = await sb.from("mesas")
    .select("cliente, combo_qty, precio, etiqueta, c:combos(nombre,precio,comision_rrpp,comision_jefe)")
    .eq("evento_id", ev.id).neq("estado", "disponible").order("etiqueta");
  const arr = ms || [];
  if (!arr.length) return toast("No hay mesas vendidas todavía", "warn");
  // el registro va con el precio NETO: lo que queda al boliche después de comisiones
  const comDe = m => (+m.c?.comision_rrpp || 0) + (+m.c?.comision_jefe || 0);
  const netoDe = m => Math.max((+m.precio || 0) - comDe(m) * (m.combo_qty || 1), 0);
  let total = 0;
  const lineas = arr.map((m, i) => {
    const q = m.combo_qty || 1, nom = m.c?.nombre || "Combo", p = netoDe(m);
    total += p;
    return `${String(i + 1).padStart(2, " ")}. ${m.cliente || m.etiqueta || "—"} - ${q} ${nom} — ${fmtBs(p)} Bs`;
  });
  const g = {};
  arr.forEach(m => {
    const nom = m.c?.nombre || "Combo", q = m.combo_qty || 1;
    const o = g[nom] = g[nom] || { n: 0, sub: 0 };
    o.n += q; o.sub += netoDe(m);
  });
  const desglose = Object.entries(g).sort((a, b) => b[1].sub - a[1].sub)
    .map(([nom, o]) => `•  ${o.n} ${nom} × ${fmtBs(o.n ? o.sub / o.n : 0)} Bs = ${fmtBs(o.sub)} Bs`);
  const txt = `Combos ${ev.nombre} · ${fmtF(ev.fecha)}\n(precios ya con la comisión descontada)\n\n${lineas.join("\n")}\n\nTotal: ${fmtBs(total)} Bs\n\nDesglose:\n${desglose.join("\n")}`;
  await copyText(txt);
  toast("Registro copiado — precios ya sin comisión");
}
// desglose por rrpp de un team: manillas prepagadas o compras en puerta
async function copyDesgloseTeam(teamId, teamNombre, tipo) {
  const { data: stats } = await sb.from("v_stats_rrpp")
    .select("rrpp_id,rrpp,team_id,entradas_usadas").eq("evento_id", ev.id);   // solo tickeados (ingresaron)
  const members = (stats || []).filter(r => r.team_id === teamId);
  const tn = /^team/i.test(teamNombre.trim()) ? teamNombre.trim() : "Team " + teamNombre.trim();
  let lineas = [], total = 0, titulo;
  if (tipo === "manillas") {
    titulo = `${tn} — Manillas prepagadas · ${ev.nombre}`;
    members.filter(m => +m.entradas_usadas > 0)
      .sort((a, b) => b.entradas_usadas - a.entradas_usadas)
      .forEach(m => { lineas.push(`${m.rrpp} - ${m.entradas_usadas}`); total += +m.entradas_usadas; });
  } else {
    const lp = listaTipos.find(l => /puerta/i.test(l.nombre));
    if (!lp) return toast("No hay lista de 'Compra en puerta'", "warn");
    titulo = `${tn} — Compras en puerta · ${ev.nombre}`;
    const { data: regs } = await traerTodo(() => sb.from("registros")
      .select("rrpp_id, ingreso_at, p:profiles!registros_rrpp_id_fkey(nombre)")
      .eq("evento_id", ev.id).eq("lista_tipo_id", lp.id).not("ingreso_at", "is", null)
      .order("id"));   // solo tickeados
    const memberIds = new Set(members.map(m => m.rrpp_id));
    const cnt = {};
    (regs || []).forEach(r => { const o = cnt[r.rrpp_id] = cnt[r.rrpp_id] || { n: 0, nombre: r.p?.nombre || "?" }; o.n++; });
    Object.entries(cnt).filter(([id]) => memberIds.has(id)).map(([, v]) => v)
      .sort((a, b) => b.n - a.n)
      .forEach(v => { lineas.push(`${v.nombre} - ${v.n}`); total += v.n; });
  }
  const txt = `${titulo}:\n${lineas.join("\n") || "(sin registros)"}\nTotal: ${total}`;
  await copyText(txt);
  toast("Desglose copiado — pegalo en WhatsApp");
}
function sheetDesgloseTeam(teamId, teamNombre) {
  sheet(`
    <div class="sh-h">Desglose · ${esc(teamNombre)}<span class="r-sub">${esc(ev.nombre)}</span></div>
    <p class="hint" style="margin:0 0 14px">Copia el registro en texto para mandarlo por WhatsApp.</p>
    <button class="btn primary" id="dgMan">Manillas prepagadas</button>
    <div style="height:10px"></div>
    <button class="btn ghost2" id="dgPue">Compras en puerta</button>`);
  $("#dgMan").onclick = () => copyDesgloseTeam(teamId, teamNombre, "manillas");
  $("#dgPue").onclick = () => copyDesgloseTeam(teamId, teamNombre, "puerta");
}
/* "Compra en puerta" se viene reconociendo por el nombre de la lista desde
   siempre (ver copyDesgloseTeam); se centraliza acá para que el cierre y el
   editor usen exactamente el mismo criterio. Sigue siendo una lista común:
   el precio es sólo un dato para calcular, no habilita cobros ni entradas. */
const esListaPuerta = l => !!l && /puerta/i.test(l.nombre || "");
const listaPuertaDe = (tipos) => (tipos || []).find(esListaPuerta) || null;
/* La columna `precio` de lista_tipos es opcional: mientras no exista, la app
   funciona igual que antes y el cierre no descuenta nada por puerta. */
let PRECIO_PUERTA_OK = true;
const sinColumnaPrecio = e =>
  !!e && (e.code === "42703" || /column .*precio.* does not exist/i.test(e.message || ""));

const ROL_LABEL = { admin: "Administrador", jefe: "Jefe de team", rrpp: "Relacionador", portero: "Seguridad", caja: "Caja",
  propietario: "Propietario", barra: "Barra", deposito: "Recepción" };
/* módulo barra (v5): roles nuevos. Mientras nadie los tenga, no cambia nada de la app. */
const ROLES_BARRA = ["propietario", "barra", "deposito"];
const esRolBarra = r => ROLES_BARRA.includes(r);
const fmtBs = n => (+n || 0).toLocaleString("es-BO");
const fmtF = d => new Date(d + "T12:00").toLocaleDateString("es-BO", { weekday: "short", day: "numeric", month: "short" });
const hora = ts => ts ? new Date(ts).toLocaleTimeString("es-BO", { hour: "2-digit", minute: "2-digit", hour12: false }) : "";
/* Fecha corta desde un timestamp. Existe para que no convivan formatos
   distintos según la pantalla: toda fecha de la app sale de fmtF o fmtD. */
const fmtD = ts => ts ? new Date(ts).toLocaleDateString("es-BO", { day: "numeric", month: "short" }) : "";
/* escape de contenido de usuario antes de meterlo en innerHTML (nombres, motivos, etc.) */
const esc = s => String(s ?? "").replace(/[&<>"']/g, c => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[c]));
/* evento en curso según su horario (hoy, entre hora_inicio y hora_fin; contempla cruce de medianoche) */
function enCurso(e) {
  if (!e || e.estado === "cerrado") return false;
  const hi = (e.hora_inicio || "21:00").slice(0, 5), hf = (e.hora_fin || "06:00").slice(0, 5);
  const start = new Date(`${e.fecha}T${hi}:00`);
  const end = new Date(`${e.fecha}T${hf}:00`);
  if (hf <= hi) end.setDate(end.getDate() + 1);
  const now = new Date();
  return now >= start && now <= end;
}
/* un nombre por línea — sin "+N": cada persona va con su nombre completo.
   Si alguien escribe "Luis +2" se limpia el sufijo y queda solo "Luis". */
function expandNombres(raw) {
  return raw.split(/[\n,]/)
    .map(s => s.trim().replace(/\s*\+\s*\d+$/, "").trim())
    .filter(Boolean);
}

/* ---------- comprobantes privados ----------
   El bucket `comprobantes` dejó de ser público (db/23-comprobantes-privados.sql):
   la URL guardada ya no abre sola. Cada <img>/<a> que apunte a un
   comprobante se cambia por una URL firmada de corta duración, que el
   servidor solo entrega a quien puede ver ese archivo.
   Se hace observando el DOM para no tocar cada pantalla que los muestra. */
const RX_COMP = /\/storage\/v1\/object\/(?:public|sign)\/comprobantes\/([^?"']+)/;
const compFirmadas = new Map();
async function urlComprobante(url) {
  const m = RX_COMP.exec(url || "");
  if (!m || !sb) return url;
  const ruta = decodeURIComponent(m[1]);
  const hit = compFirmadas.get(ruta);
  if (hit && Date.now() - hit.at < 240000) return hit.url;
  const { data, error } = await sb.storage.from("comprobantes").createSignedUrl(ruta, 300);
  if (error || !data?.signedUrl) return "";
  compFirmadas.set(ruta, { url: data.signedUrl, at: Date.now() });
  return data.signedUrl;
}
function firmarComprobantes(raiz) {
  if (!raiz.querySelectorAll) return;
  raiz.querySelectorAll('img[src*="/public/comprobantes/"], a[href*="/public/comprobantes/"]').forEach(async el => {
    const attr = el.tagName === "A" ? "href" : "src";
    const original = el.getAttribute(attr);
    el.removeAttribute(attr);                       // no pedir la URL pública, que ya no existe
    const firmada = await urlComprobante(original);
    if (firmada) el.setAttribute(attr, firmada);
  });
}
new MutationObserver(ms => ms.forEach(m => m.addedNodes.forEach(n => firmarComprobantes(n))))
  .observe(document.documentElement, { childList: true, subtree: true });

/* ---------- toasts ---------- */
function toast(msg, type = "ok") {
  let w = document.getElementById("toastWrap");
  if (!w) { w = document.createElement("div"); w.id = "toastWrap"; w.className = "toast-wrap"; document.body.appendChild(w); }
  const el = document.createElement("div");
  el.className = "toast " + type;
  const span = document.createElement("span");
  span.textContent = msg;
  el.appendChild(span);
  w.appendChild(el);
  if (window.Motion) return Motion.toast(el);
  requestAnimationFrame(() => el.classList.add("show"));
  setTimeout(() => { el.classList.remove("show"); setTimeout(() => el.remove(), 260); }, 2600);
}
/* El servidor ahora rechaza por permisos, cupos y horarios. Se traduce lo
   que venía en crudo de Postgres; los mensajes de negocio (cupo agotado,
   venta cerrada, mesa ya vendida…) ya llegan escritos para la persona. */
function mensajeDeError(e) {
  const m = e?.message || String(e);
  if (e?.code === "42501" || /permission denied|row-level security|No autorizado/i.test(m))
    return "No tenés permiso para hacer esto en este boliche.";
  if (e?.code === "28000" || /No autenticado|JWT expired/i.test(m))
    return "Tu sesión venció. Volvé a ingresar.";
  if (esFallaDeRed(e)) return "Sin conexión. Revisá la señal y probá de nuevo.";
  if (e?.code === "23505") return "Ya existe uno igual.";
  return m;
}
const fail = e => { console.error(e); toast(mensajeDeError(e), "warn"); };

/* ---------- login ---------- */
$("#btnLogin") && ($("#btnLogin").onclick = login);
$("#lgEye") && ($("#lgEye").onclick = () => {
  const p = $("#lgPass"); const show = p.type === "password";
  p.type = show ? "text" : "password"; $("#lgEye").classList.toggle("on", show);
});
$("#lgPass") && $("#lgPass").addEventListener("keydown", e => { if (e.key === "Enter") login(); });

/* ---------- registro de RRPP por link de invitación (?invite=CODE) ---------- */
const INVITE = new URLSearchParams(location.search).get("invite");
if (INVITE && sb) {
  document.querySelector(".login-brand p").textContent = "Registro de relacionador";
  $("#loginCard").innerHTML = `
    <div id="regErr"></div>
    <div class="field"><label>Tu nombre y apellido</label><input id="rgNombre" autocomplete="name"></div>
    <div class="field"><label>Usuario (corto, sin espacios)</label><input id="rgUser" autocapitalize="none" autocomplete="off"></div>
    <div class="field"><label>Contraseña (mín. 6)</label><input id="rgPass" type="password" autocomplete="new-password"></div>
    <button class="btn primary" id="btnReg2">Registrarme</button>
    <p style="font-size:12px;color:var(--text-3);margin-top:12px;text-align:center">Al registrarte quedás en el team de quien te pasó este link.</p>`;
  $("#btnReg2").onclick = async () => {
    const nombre = $("#rgNombre").value.trim(), usuario = $("#rgUser").value.trim().toLowerCase().replace(/\s/g, ""), clave = $("#rgPass").value;
    $("#regErr").innerHTML = "";
    if (!nombre || !usuario || clave.length < 6) { $("#regErr").innerHTML = `<div class="err">Completá todo (clave 6+).</div>`; return; }
    const b = $("#btnReg2"); b.disabled = true; b.textContent = "Registrando…";
    const res = await fetch(`${CFG.SUPABASE_URL}/functions/v1/crear-usuario`, {
      method: "POST", headers: { "Content-Type": "application/json", apikey: CFG.SUPABASE_ANON_KEY, Authorization: `Bearer ${CFG.SUPABASE_ANON_KEY}` },
      body: JSON.stringify({ action: "registro", invite: INVITE, nombre, usuario, clave })
    });
    const out = await res.json();
    if (!res.ok) { b.disabled = false; b.textContent = "Registrarme"; $("#regErr").innerHTML = `<div class="err">${out.error || "Error"}</div>`; return; }
    toast(`Bienvenido al ${out.team}`);
    history.replaceState(null, "", location.pathname);
    const { error } = await sb.auth.signInWithPassword({ email: `${usuario}@plataforma.local`, password: clave });
    if (!error) boot(); else location.reload();
  };
}

async function login() {
  const u = $("#lgUser").value.trim().toLowerCase(), p = $("#lgPass").value;
  if (!u || !p) return;
  $("#loginErr").innerHTML = "";
  const { error } = await sb.auth.signInWithPassword({ email: `${u}@plataforma.local`, password: p });
  if (error) { $("#loginErr").innerHTML = `<div class="err">Usuario o contraseña incorrectos.</div>`; return; }
  boot();
}

async function boot() {
  const { data: { user } } = await sb.auth.getUser();
  if (!user) return;
  // perfil y catálogo de boliches en paralelo. El rol por boliche ya no se
  // calcula acá con las membresías: lo resuelve el servidor (rol_en_club).
  const [{ data: prof, error }, { data: cls_ }] = await Promise.all([
    sb.from("profiles").select("*").eq("id", user.id).single(),
    sb.from("clubs").select("*").eq("activo", true).order("nombre")
  ]);
  if (error || !prof) { fail(error || new Error("Perfil no encontrado")); return; }
  if (!prof.activo) { $("#loginErr").innerHTML = `<div class="err">Usuario desactivado.</div>`; await sb.auth.signOut(); return; }
  me = prof;
  clubsDisponibles = cls_ || [];
  // administración de la plataforma: crear boliches y nombrar administradores
  me.plataforma = (await sb.rpc("es_platform_admin")).data === true;
  // identidad base (el rol efectivo por boliche lo pone applyClubRole)
  me._rol = prof.rol; me._team = prof.team_id;
  // boliches permitidos: forzar club válido
  const cls = myClubs();
  if (!cls.includes(club)) club = cls[0] || null;
  renderClubMenu(cls);
  $("#login").classList.add("hidden");
  // sin ningún boliche todavía (arranque de cero): entra directo con el
  // rol base, la pantalla de Eventos del admin explica cómo crear el primero
  if (!club) { me.rol = me._rol; me.team_id = me._team; await enterApp(); return; }
  // los que manejan más de un boliche eligen primero en un menú
  if (cls.length > 1) { showClubPicker(cls); return; }
  await applyClubRole();
  enterApp();
}
// aplica el rol/team del boliche actual. Regla:
//  - membership de ese boliche manda (rol + team explícitos).
//  - si no hay membership: rol base, PERO si es jefe y su team no opera en este
//    boliche, queda como relacionador (y sin team acá).
async function applyClubRole() {
  // al cambiar de boliche, los estados de vista del club anterior no aplican
  // (un team que no opera en el nuevo club como filtro dejaba Invitados "vacío")
  listaSelId = null; lsFTeam = ""; lsFSeller = ""; lsRegs = null; lsEvId = null;
  tkQ = ""; tkFTeam = ""; tkFSeller = ""; accHistCat = ""; gnNav = null; gnScroll = {};
  /* El rol efectivo y el team en este boliche los resuelve el servidor
     (rol_en_club / mi_team_en_club), con la misma regla que usan las
     guardas de las RPC y la app móvil. Calcularlo acá con otra regla hacía
     que la pantalla ofreciera cosas que la base después rechazaba. */
  const [{ data: rolAca, error: eRol }, { data: teamAca }] = await Promise.all([
    sb.rpc("rol_en_club", { p_club: club }),
    sb.rpc("mi_team_en_club", { p_club: club })
  ]);
  if (eRol) console.error(eRol);
  me.rol = rolAca || me._rol;
  me.team_id = teamAca ?? null;
  myTeamClubs = null;
  if (me.team_id) {
    const { data: t } = await sb.from("teams").select("clubs").eq("id", me.team_id).single();
    myTeamClubs = t?.clubs || clubsDisponibles.map(c => c.id);
  }
}
function enterApp() {
  $("#clubPick")?.classList.add("hidden");
  $("#app").classList.remove("hidden");
  buildTabbar();
  window.Motion?.entrarApp();
  loadEventos().then(() => { header(); tab = homeTab(); setTab(); renderTab(); mostrarAvisos(); });
}

/* avisos del admin: aparecen una vez al entrar y se marcan como leídos */
async function mostrarAvisos() {
  if (!club || esRolBarra(me.rol)) return;
  const { data } = await sb.rpc("avisos_pendientes", { p_club: club });
  const pend = data || [];
  if (!pend.length) { setTimeout(pedirTelefono, 900); return; }
  let i = 0;
  const pintar = () => {
    const a = pend[i];
    if (!a) { closeSheet(); setTimeout(pedirTelefono, 400); return; }
    sheet(`
      <div class="sh-ico">${ico("megafono")}</div>
      <div class="sh-h" style="justify-content:center;text-align:center">${esc(a.titulo)}</div>
      <p style="white-space:pre-wrap;font-size:15px;line-height:1.5;color:var(--text-2);margin:6px 0 18px;text-align:center">${esc(a.mensaje)}</p>
      <button class="btn primary" id="avOk">Entendido${pend.length > 1 ? ` (${i + 1}/${pend.length})` : ""}</button>`);
    $("#avOk").onclick = async () => {
      await sb.rpc("marcar_aviso_visto", { p_aviso: a.id });
      i++; pintar();
    };
  };
  setTimeout(pintar, 900);   // deja que cargue la pantalla primero
}

/* WhatsApp del equipo.
   Las cuentas se crearon sin pedir teléfono, así que hoy no hay forma de
   escribirle a nadie desde el sistema. Se pide al entrar, una sola vez.

   Para relacionadores y jefes BLOQUEA: sin número no se puede seguir. Es la
   única forma de que la lista de teléfonos se complete — mientras se pudo
   postergar, la mitad no lo cargó nunca.
   Para seguridad y caja NO bloquea: un portero a las 2 de la mañana no puede
   quedar trabado por esto. Lo deja para después y le vuelve a aparecer la
   próxima vez. Y el admin siempre puede cargarlo por él desde Equipo. */
let telPedido = false;
/* mientras esté en true, la hoja del teléfono no se puede cerrar tocando
   el fondo: si se pudiera, el bloqueo no bloquearía nada. */
let telObliga = false;
async function pedirTelefono() {
  if (telPedido || !club || esRolBarra(me.rol)) return;
  telPedido = true;
  const { data: yaTiene } = await sb.rpc("mi_telefono");
  if (yaTiene) return;
  // el que vende es el que tiene que dar el número; el de puerta no se traba
  const obliga = ["rrpp", "jefe"].includes(me.rol);
  sheet(`
    <div class="sh-ico">${ico("telefono")}</div>
    <div class="sh-h" style="justify-content:center;text-align:center">Registrá tu WhatsApp</div>
    <p style="font-size:14px;line-height:1.5;color:var(--text-2);margin:6px 0 16px;text-align:center">
      Es para poder avisarte los cambios de horario, el cierre de venta y lo de tu rendición
      sin depender de que estés en el grupo. Se carga una sola vez.</p>
    <div class="field"><label>Tu celular</label>
      <div style="display:flex;gap:8px;align-items:center">
        <span style="flex-shrink:0;padding:13px 12px;border:1px solid var(--line-2);border-radius:12px;background:var(--surface-2);color:var(--text-2);font-weight:700">+591</span>
        <input id="telN" type="tel" inputmode="numeric" autocomplete="tel" placeholder="71234567" maxlength="20" style="flex:1">
      </div>
      <div class="hint" style="margin:6px 0 0">Los 8 dígitos. Si tu número es de otro país, escribilo completo con el código.</div>
    </div>
    <button class="btn primary" id="telGo">Guardar</button>
    ${obliga ? `<p class="hint" style="margin:10px 0 0;text-align:center;color:var(--warn)">
      Sin tu número no vas a poder seguir usando la app.</p>`
             : `<button class="btn ghost2" id="telLuego" style="margin-top:9px">Ahora no</button>`}`);
  const inp = $("#telN");
  setTimeout(() => inp.focus(), 250);
  const guardar = async () => {
    const v = inp.value.trim();
    if (!v) return toast("Escribí tu número", "warn");
    $("#telGo").disabled = true;
    const { error } = await sb.rpc("guardar_telefono", { p_tel: v });
    $("#telGo").disabled = false;
    if (error) return toast(error.message, "warn");
    telObliga = false;
    closeSheet();
    toast("Listo, quedó guardado");
  };
  $("#telGo").onclick = guardar;
  inp.onkeydown = e => { if (e.key === "Enter") guardar(); };
  const luego = $("#telLuego");
  if (luego) luego.onclick = closeSheet;
  // sin botón de salida no alcanza: el fondo también cierra la hoja
  telObliga = obliga;
}
function showClubPicker(cls) {
  let ov = $("#clubPick");
  if (!ov) { ov = document.createElement("div"); ov.id = "clubPick"; document.body.appendChild(ov); }
  ov.className = "clubpick";
  ov.innerHTML = `
    <div class="cp-inner">
      <div class="cp-brand">
        <span class="cp-logo">VENUE</span>
        <span class="cp-tag">Event Management Platform</span>
      </div>
      <div class="cp-h">Hola, ${esc((me.nombre || "").split(" ")[0])}</div>
      <div class="cp-sub">Elegí el boliche en el que vas a trabajar</div>
      <div class="cp-cards">
        ${cls.map(id => { const c = clubData(id); return `<button class="cp-card" data-cp="${id}" style="--mk-p:${esc(c?.color_primario || "")};--mk-s:${esc(c?.color_secundario || "")}">
          <span class="cp-mark">${clubMarkHTML(id)}</span>
          <span class="cp-txt">
            <span class="cp-name wm-club">${esc(c?.nombre || id)}</span>
            <span class="cp-cs">${esc(c?.subtitulo || "")}</span>
          </span>
          <svg class="cp-arrow" viewBox="0 0 24 24"><path d="M9 6l6 6-6 6"/></svg>
        </button>`; }).join("")}
      </div>
      ${me.plataforma ? `<button class="cp-nuevo" id="cpNuevo">${ico("mas")}Nuevo boliche</button>
      <div class="cp-form hidden" id="cpForm"></div>` : ""}
      <button class="cp-out" onclick="logout()">Cerrar sesión</button>
    </div>`;
  ov.classList.remove("hidden");
  // el superadmin puede dar de alta un boliche sin entrar a otro: el
  // formulario se abre acá mismo (la hoja vive dentro de #app, oculto)
  $("#cpNuevo") && ($("#cpNuevo").onclick = () => {
    const f = $("#cpForm");
    if (!f.classList.toggle("hidden")) {
      f.innerHTML = formClubHTML();
      bindFormClub((id, nombre) => { toast(`${nombre} creado`); showClubPicker(myClubs()); });
      $("#clN").focus();
    }
  });
  window.Motion?.selector(ov);
  ov.querySelectorAll("[data-cp]").forEach(b => b.onclick = async () => {
    club = b.dataset.cp;
    renderClubMenu(cls);
    await applyClubRole();
    enterApp();
  });
}

window.logout = async () => { stopCam(); await sb.auth.signOut(); location.reload(); };

/* ---------- header / club / eventos ---------- */
function header() {
  const c = clubData(club);
  aplicarTemaClub(c);
  const marca = `<span class="wm-club">${esc(clubNombre(club))}</span>`;
  const ini = (me.nombre || "?").slice(0, 1).toUpperCase();

  $("#clubName").innerHTML = marca;
  $("#clubMark").innerHTML = clubMarkHTML(club);
  $("#clubSub").textContent = ROL_LABEL[me.rol] || me.rol;
  $("#userNm") && ($("#userNm").textContent = me.nombre);
  $("#avatarIni") && ($("#avatarIni").textContent = ini);

  // La topbar repite local y cuenta porque en el celular la barra lateral
  // está oculta y esos dos datos tienen que estar siempre a la vista.
  $("#tbClubName") && ($("#tbClubName").innerHTML = marca);
  $("#tbClubMark") && ($("#tbClubMark").innerHTML = clubMarkHTML(club));
  $("#avatarM") && ($("#avatarM").textContent = ini);
  pintarEvTopbar();
}

/* Puebla el menú de cambio de boliche (#clubMenu) desde clubsDisponibles,
   reemplazando el markup estático que antes vivía en index.html. El click
   se maneja por delegación en el listener de #clubMenu (ver más abajo),
   así que acá solo hace falta generar los botones. */
function renderClubMenu(clsPermitidos) {
  const cont = $("#cmCardBody");
  if (!cont) return;
  cont.innerHTML = (clsPermitidos || []).map(id => {
    const c = clubData(id);
    return `<button data-loc="${id}"><span class="mk" style="--mk-p:${esc(c?.color_primario || "")};--mk-s:${esc(c?.color_secundario || "")}">${clubMarkHTML(id)}</span><span class="wm-club">${esc(c?.nombre || id)}</span><small>Eventos y planimetría</small></button>`;
  }).join("");
}

/* Evento activo en la topbar: es el contexto de todo lo que se ve
   debajo, así que deja de repetirse dentro de cada pantalla. */
function pintarEvTopbar() {
  const nm = $("#tbEvNm"), meta = $("#tbEvMeta");
  if (!nm) return;
  if (!ev) { nm.textContent = "Sin evento"; if (meta) meta.textContent = ""; return; }
  nm.textContent = ev.nombre;
  if (meta) meta.textContent = fmtF(ev.fecha);
  $("#tbEv")?.classList.toggle("vivo", enCurso(ev));
}

async function loadEventos() {
  if (!club) { eventos = []; ev = null; renderEvsel(); return; }
  const { data, error } = await sb.from("eventos").select("*")
    .eq("club_id", club).neq("estado", "cerrado")
    .order("fecha", { ascending: true });
  if (error) return fail(error);
  eventos = data || [];
  ev = eventos.find(e => e.id === (ev && ev.id)) || eventos[0] || null;
  renderEvsel();
  // Si las listas no cargan, el resto de la app tiene que seguir andando:
  // la pantalla de Listas mostrará su propio error con Reintentar.
  if (ev) { try { await loadListaTipos(); } catch (e) { console.error(e); listaTipos = []; } }
  subRealtime();
}

async function loadListaTipos() {
  const { data, error } = await sb.from("lista_tipos").select("*").eq("evento_id", ev.id).order("orden");
  // Sin esto, un fallo de red dejaba listaTipos vacío y la pantalla decía
  // "el evento no tiene listas configuradas" aunque sí las tuviera.
  if (error) throw error;
  listaTipos = data || [];
}

function renderEvsel() {
  const hoyISO = new Date().toLocaleDateString("sv-SE"); // yyyy-mm-dd local
  $("#evsel").innerHTML = eventos.length
    ? eventos.map(e => `<button data-ev="${e.id}" class="${ev && ev.id === e.id ? "on" : ""}"><span class="evs-n">${esc(e.nombre)}</span><span class="evs-d">${fmtF(e.fecha)}</span>${enCurso(e) ? '<span class="estado-vivo">En vivo</span>' : e.fecha === hoyISO ? '<span class="estado-hoy">Hoy</span>' : ""}</button>`).join("")
    : `<button class="on" disabled>Sin eventos próximos</button>`;
  // Con un solo evento la fila repite lo que ya dice la barra de arriba.
  $("#evsel").classList.toggle("solo", eventos.length <= 1);
}
$("#evsel").onclick = async e => {
  const b = e.target.closest("button[data-ev]"); if (!b) return;
  ev = eventos.find(x => x.id === b.dataset.ev);
  lsMarcados.clear();
  posReset();
  // Cambiar de evento debe invalidar lo cacheado: si no, Listas seguiría
  // mostrando los invitados del evento anterior.
  lsRegs = null; lsEvId = null;
  try { await loadListaTipos(); } catch (err) { console.error(err); listaTipos = []; }
  subRealtime();
  pintarEvTopbar();
  renderEvsel(); renderTab();
};

const abrirClubs = () => { if (myClubs().length > 1) $("#clubMenu").classList.add("show"); };
$("#clubBtn").onclick = abrirClubs;
$("#tbClub") && ($("#tbClub").onclick = abrirClubs);
// El selector de evento de la topbar lleva a Eventos, donde se cambia.
$("#tbEv") && ($("#tbEv").onclick = () => {
  // con varios eventos, la barra de arriba es el selector
  if (eventos.length > 1) {
    sheet(`<div class="sh-h">Evento</div>
    <div class="mas-lista">${eventos.map(e => `<button class="mas-op${ev && ev.id === e.id ? " on" : ""}" data-sev="${e.id}">
      <span style="flex:1;text-align:left">${esc(e.nombre)}<span class="evs-d" style="display:block">${fmtF(e.fecha)}</span></span>
      ${enCurso(e) ? '<span class="estado-vivo">En vivo</span>' : ""}</button>`).join("")}</div>`);
    document.querySelectorAll("#sheetBody [data-sev]").forEach(b => b.onclick = () => {
      closeSheet(); document.querySelector(`#evsel button[data-ev="${b.dataset.sev}"]`)?.click();
    });
    return;
  }
  if (tabsFor().some(([t]) => t === "eventos")) irATab("eventos");
  else toast(ev ? `${ev.nombre} · ${fmtF(ev.fecha)}` : "Sin evento activo");
});
$("#clubMenu").onclick = async e => {
  const b = e.target.closest("button[data-loc]");
  $("#clubMenu").classList.remove("show");
  if (b && b.dataset.loc !== club) {
    club = b.dataset.loc; ev = null; lsMarcados.clear();
    // El otro boliche tiene sus propios eventos: lo cacheado ya no sirve.
    lsRegs = null; lsEvId = null; listaTipos = [];
    posReset();
    await applyClubRole();               // rol/team del nuevo boliche
    buildTabbar();
    if (!tabsFor().some(([t]) => t === tab)) tab = homeTab();
    setTab(); header(); await loadEventos(); renderTab();
  }
};

/* ---------- tabs por rol ---------- */
/* Íconos de línea para acciones (mismo trazo que la navegación). Reemplazan
   a los emojis: cada sistema dibuja los emojis a su manera y le quitaban
   coherencia y seriedad a la interfaz. */
const ICO_PATHS = {
  sonido: '<path d="M4 9h4l5-4v14l-5-4H4z"/><path d="M16.5 8.5a5 5 0 0 1 0 7M19 6a8.5 8.5 0 0 1 0 12"/>',
  mudo: '<path d="M4 9h4l5-4v14l-5-4H4z"/><path d="M17 9l5 6M22 9l-5 6"/>',
  filtro: '<path d="M4 5h16l-6 7.5V19l-4 1.5v-8z"/>',
  bandera: '<path d="M5 21V4M5 4h11l-2 4 2 4H5"/>',
  recargar: '<path d="M20 11a8 8 0 1 0-2.3 5.7"/><path d="M20 4v7h-7"/>',
  megafono: '<path d="M4 10v4h3l8 5V5L7 10z"/><path d="M18.5 9a4 4 0 0 1 0 6"/>',
  telefono: '<rect x="7" y="3" width="10" height="18" rx="2"/><path d="M11 17.5h2"/>',
  imagen: '<rect x="3.5" y="4.5" width="17" height="15" rx="2"/><circle cx="9" cy="10" r="1.6"/><path d="M20.5 16l-5-5-8 8.5"/>',
  recibir: '<path d="M12 3v11M8 10l4 4 4-4"/><path d="M4 17v3h16v-3"/>',
  salida: '<path d="M6 4h12l-5 7v7h3M9 18h3"/><path d="M6 4l6 7"/>',
  ajuste: '<path d="M12 4v16M5 8h14M5 8l-2.5 6h5zM19 8l-2.5 6h5z"/>',
  baja: '<path d="M4 7h16M9 7V4h6v3M6.5 7l1 13h9l1-13"/>',
  deshacer: '<path d="M9 14L4 9l5-5"/><path d="M4 9h10a6 6 0 0 1 0 12h-3"/>',
  atras: '<path d="M15 6l-6 6 6 6"/>',
  mas: '<path d="M12 5v14M5 12h14"/>',
  menos: '<path d="M5 12h14"/>',
  ojo: '<path d="M2.5 12S6 5.5 12 5.5 21.5 12 21.5 12 18 18.5 12 18.5 2.5 12 2.5 12z"/><circle cx="12" cy="12" r="3"/>',
  base: '<ellipse cx="12" cy="6" rx="7" ry="2.8"/><path d="M5 6v12c0 1.5 3.1 2.8 7 2.8s7-1.3 7-2.8V6"/><path d="M5 12c0 1.5 3.1 2.8 7 2.8s7-1.3 7-2.8"/>',
  ticket: '<path d="M3 9V6.5A1.5 1.5 0 0 1 4.5 5h15A1.5 1.5 0 0 1 21 6.5V9a3 3 0 0 0 0 6v2.5a1.5 1.5 0 0 1-1.5 1.5h-15A1.5 1.5 0 0 1 3 17.5V15a3 3 0 0 0 0-6z"/><path d="M14.5 7v1.5M14.5 11.25v1.5M14.5 15.5V17"/>',
  sofa: '<path d="M5 11V8a2 2 0 0 1 2-2h10a2 2 0 0 1 2 2v3"/><path d="M3 13a2 2 0 0 1 4 0v1h10v-1a2 2 0 0 1 4 0v4a1 1 0 0 1-1 1H4a1 1 0 0 1-1-1z"/><path d="M6 18v2M18 18v2"/>',
  manilla: '<rect x="3" y="8" width="18" height="8" rx="4"/><path d="M8.5 8v8M15.5 8v8"/>',
  ajustes: '<circle cx="12" cy="12" r="3"/><path d="M19.4 15a1.6 1.6 0 0 0 .3 1.8l.1.1a2 2 0 1 1-2.8 2.8l-.1-.1a1.6 1.6 0 0 0-2.7 1.1V21a2 2 0 1 1-4 0v-.1a1.6 1.6 0 0 0-2.7-1.1l-.1.1a2 2 0 1 1-2.8-2.8l.1-.1A1.6 1.6 0 0 0 3.6 15H3a2 2 0 1 1 0-4h.1a1.6 1.6 0 0 0 1.1-2.7l-.1-.1a2 2 0 1 1 2.8-2.8l.1.1A1.6 1.6 0 0 0 9.7 4.4V3a2 2 0 1 1 4 0v.1a1.6 1.6 0 0 0 2.7 1.1l.1-.1a2 2 0 1 1 2.8 2.8l-.1.1a1.6 1.6 0 0 0 1.1 2.7H21a2 2 0 1 1 0 4h-.1a1.6 1.6 0 0 0-1.5 1.3z"/>',
  copiar: '<rect x="8.5" y="8.5" width="12" height="12" rx="2"/><path d="M15.5 8.5V5.5a2 2 0 0 0-2-2h-8a2 2 0 0 0-2 2v8a2 2 0 0 0 2 2h3"/>',
  archivo: '<path d="M14 3H7a2 2 0 0 0-2 2v14a2 2 0 0 0 2 2h10a2 2 0 0 0 2-2V8z"/><path d="M14 3v5h5"/>',
  calendario: '<rect x="3.5" y="5" width="17" height="15.5" rx="2"/><path d="M3.5 10h17M8 3v4M16 3v4"/>',
  escudo: '<path d="M12 3l7 3v5c0 4.5-3 7.6-7 9-4-1.4-7-4.5-7-9V6z"/>',
  usuario: '<circle cx="12" cy="8" r="3.6"/><path d="M5 20.5c.6-3.7 3.3-5.8 7-5.8s6.4 2.1 7 5.8"/>',
  grupo: '<circle cx="9" cy="8" r="3"/><path d="M3 20c.8-3.5 3-5 6-5s5.2 1.5 6 5"/><circle cx="17" cy="9" r="2.4"/><path d="M15.5 15.2c2.6.3 4.6 1.7 5.3 4.8"/>',
  barras: '<path d="M6 20v-5M12 20V9M18 20V4"/>',
  buscar: '<circle cx="11" cy="11" r="7"/><path d="M20 20l-3.5-3.5"/>',
  chevron: '<path d="M6 9l6 6 6-6"/>',
  puntos: '<circle cx="5.5" cy="12" r="1.3"/><circle cx="12" cy="12" r="1.3"/><circle cx="18.5" cy="12" r="1.3"/>',
  check: '<circle cx="12" cy="12" r="8.5"/><path d="M8.5 12.2l2.3 2.3 4.7-4.8"/>',
  reloj: '<circle cx="12" cy="12" r="8.5"/><path d="M12 7.5V12l3 2"/>',
  qr: '<rect x="4" y="4" width="6" height="6" rx="1"/><rect x="14" y="4" width="6" height="6" rx="1"/><rect x="4" y="14" width="6" height="6" rx="1"/><path d="M14 14h2v2M20 14v6h-6"/>',
  bolsa: '<path d="M5 8h14l-1 12H6z"/><path d="M9 8V6a3 3 0 0 1 6 0v2"/>',
  copa: '<path d="M7 3h10l-1 8a4 4 0 0 1-8 0L7 3z"/><path d="M12 15v5M8 21h8"/>',
  caja: '<path d="M4 8h16v12H4zM4 8l1.5-4h13L20 8"/><path d="M10 12h4"/>',
  mapa: '<path d="M9 4L3 6v14l6-2 6 2 6-2V4l-6 2-6-2z"/><path d="M9 4v14M15 6v14"/>',
  lista_: '<path d="M8 6h12M8 12h12M8 18h12M4 6h.01M4 12h.01M4 18h.01"/>',
};
const ico = (k, cls = "") => `<svg viewBox="0 0 24 24" class="ic ${cls}" aria-hidden="true">${ICO_PATHS[k]}</svg>`;

/* ---------- piezas del patrón de pantalla ----------
   Todas las secciones se arman con las mismas tres piezas, en web de
   escritorio, web de celular y la app:
     · pgHead: etiqueta de sección en mayúsculas, título y una línea de
       contexto; las acciones a la derecha (abajo en el celular).
     · kpi: el dato con su ícono en un recuadro a la izquierda.
     · pillEst: estado con punto de color (Activo, Pendiente…). */
function pgHead({ ey = "", t, s = "", acc = "" }) {
  return `
  <header class="pg-h">
    <div class="pg-h-tx">
      ${ey ? `<span class="pg-ey">${ey}</span>` : ""}
      <h1 class="pg-t">${t}</h1>
      ${s ? `<p class="pg-s">${s}</p>` : ""}
    </div>
    ${acc ? `<div class="pg-acc">${acc}</div>` : ""}
  </header>`;
}
/* tono: "" neutro · "marca" · "ok" · "warn" · "bad" */
function kpi({ ic, k, v, de, s = "", tono = "", cola = "", attrs = "", tag = "div" }) {
  return `
  <${tag} class="kp${tono ? " kp-" + tono : ""}" ${attrs}>
    ${ic ? `<span class="kp-ic">${ico(ic)}</span>` : ""}
    <div class="kp-tx">
      <span class="kp-k">${k}</span>
      <span class="kp-v">${v}${de != null ? `<small> / ${de}</small>` : ""}</span>
      ${s ? `<span class="kp-s">${s}</span>` : ""}
    </div>
    ${cola ? `<span class="kp-cola">${ico(cola)}</span>` : ""}
  </${tag}>`;
}
const pillEst = (txt, tono = "ok") => `<span class="pill-est ${tono}">${txt}</span>`;
const ROL_ICO = { admin: "escudo", jefe: "grupo", rrpp: "usuario", portero: "escudo", caja: "base",
  propietario: "copa", barra: "copa", deposito: "caja" };
const rolBadge = r => `<span class="us-rol" data-r="${r}">${ico(ROL_ICO[r] || "usuario")}${ROL_LABEL[r] || r}</span>`;
/* Tono estable por persona para la inicial: el mismo nombre siempre cae en
   el mismo color, y ninguno compite con el de la marca. */
const TINTES = ["#7A3B2E", "#2F3F6B", "#4B2F6B", "#2E5A4B", "#6B5A2F", "#5A2F4B", "#2F5A6B"];
const tinte = nm => { let h = 0; for (const c of String(nm || "")) h = (h * 31 + c.charCodeAt(0)) >>> 0; return TINTES[h % TINTES.length]; };
const inicial = nm => `<span class="ini" style="--ini:${tinte(nm)}">${esc((String(nm || "·").trim()[0] || "·").toUpperCase())}</span>`;

const TAB_ICONS = {
  accesos: '<path d="M13 3H6a1 1 0 0 0-1 1v16a1 1 0 0 0 1 1h7"/><path d="M10 12h11M17.5 8.5L21 12l-3.5 3.5"/>',
  home: '<path d="M3 10.5L12 3l9 7.5"/><path d="M5.5 9.5V20h13V9.5"/><path d="M9.5 20v-5.5h5V20"/>',
  mesas: '<path d="M9 4L3 6v14l6-2 6 2 6-2V4l-6 2-6-2z"/><path d="M9 4v14M15 6v14"/>',
  entradas: '<rect x="4" y="4" width="6" height="6" rx="1"/><rect x="14" y="4" width="6" height="6" rx="1"/><rect x="4" y="14" width="6" height="6" rx="1"/><path d="M14 14h3v3h-3zM20 14v.01M14 20h.01M17 20h.01M20 17v.01M20 20v.01"/>',
  listas: '<path d="M8 6h12M8 12h12M8 18h12M4 6h.01M4 12h.01M4 18h.01"/>',
  stats: '<path d="M4 20V10M10 20V4M16 20v-8M20 20H4"/>',
  team: '<circle cx="9" cy="8" r="3"/><path d="M3 20c.8-3.5 3-5 6-5s5.2 1.5 6 5"/><circle cx="17" cy="9" r="2.4"/><path d="M15.5 15.2c2.6.3 4.6 1.7 5.3 4.8"/>',
  eventos: '<path d="M3 10.5L12 3l9 7.5"/><path d="M5.5 9.5V20h13V9.5"/><path d="M9.5 20v-5.5h5V20"/>',
  escaner: '<path d="M4 8V6a2 2 0 012-2h2M4 16v2a2 2 0 002 2h2M16 4h2a2 2 0 012 2v2M16 20h2a2 2 0 002-2v-2M7 12h10"/>',
  lista: '<path d="M8 6h12M8 12h12M8 18h12M4 6h.01M4 12h.01M4 18h.01"/>',
  caja: '<circle cx="9" cy="8" r="3"/><path d="M3 20c.8-3.5 3-5 6-5s5.2 1.5 6 5"/><path d="M16 8h5M16 12h5M16 16h3"/>',
  /* consulta de relacionadores en puerta: grupo de gente, distinto del de
     caja (que lleva las rayas de la lista) para no confundirlos */
  rrpps: '<circle cx="9" cy="8" r="3.2"/><path d="M2.5 20c.8-3.6 3.2-5.2 6.5-5.2s5.7 1.6 6.5 5.2"/><circle cx="17.5" cy="9.5" r="2.3"/><path d="M17 14.2c2.4.2 4 1.7 4.5 4"/>',
  inventario: '<path d="M5 8h14v12H5zM5 8l1.5-4h11L19 8"/><path d="M10 12h4"/>',
  barmov: '<path d="M4 18V9M10 18V5M16 18v-6M20 21H4"/>',
  recepcion: '<path d="M12 3v11M8 10l4 4 4-4"/><path d="M4 17v3h16v-3"/>',
  recepmias: '<circle cx="12" cy="12" r="8.5"/><path d="M12 7.5V12l3 2"/>',
  barpos: '<path d="M6 4h12l-5 7v7h3M9 18h3"/><path d="M6 4l6 7"/>',
  barcierre: '<path d="M4 5h16v14H4z"/><path d="M4 10h16M9 14h6"/>',
  baranalitica: '<path d="M4 20V9M10 20V4M16 20v-7M22 20H2"/>'
};
/* Accesos secundarios o administrativos. No son secciones de todos los
   días: viven en "Más" (celular) y al pie de la barra lateral
   (escritorio), no en el perfil, que queda solo para la cuenta. */
const EXTRA_ICONS = {
  usuarios: '<circle cx="9" cy="8" r="3"/><path d="M3 20c.8-3.5 3-5 6-5s5.2 1.5 6 5"/><path d="M17 7v6M14 10h6"/>',
  filtro: '<path d="M5 21V4M5 4h11l-2 4 2 4H5"/>',
  cajalista: '<circle cx="9" cy="8" r="3"/><path d="M3 20c.8-3.5 3-5 6-5s5.2 1.5 6 5"/><path d="M16 8h5M16 12h5M16 16h3"/>',
  qrs: '<rect x="4" y="4" width="6" height="6" rx="1"/><rect x="14" y="4" width="6" height="6" rx="1"/><rect x="4" y="14" width="6" height="6" rx="1"/><path d="M14 14h2v2M20 14v6h-6"/>',
  combos: '<path d="M7 3h10l-1 8a4 4 0 0 1-8 0L7 3z"/><path d="M12 15v5M8 21h8"/>',
};
function accionesMas() {
  const a = [];
  if (me.rol === "admin") a.push(["usuarios", "Usuarios y equipos", abrirUsuarios]);
  if (["admin", "jefe"].includes(me.rol)) a.push(["filtro", "Rechazados en puerta", sheetFiltro]);
  if (me.admin_principal) a.push(["cajalista", "Lista de la caja", sheetCajaFiltro]);
  if (me.rol === "admin") a.push(["combos", "Combos", sheetCombos]);
  if (me.rol === "admin") a.push(["qrs", "QRs de cobro", sheetQrsCobro]);
  return a;
}
// entrar a usuarios siempre aterriza en la raíz (los filtros y el historial
// interno de niveles siguen vivos para navegar de nuevo)
function abrirUsuarios() {
  gnNav = null;
  try { history.pushState({ tab: "gente", nav: null }, "", "#gente/usuarios"); } catch { /* file:// */ }
  sheetUsuarios();
}
const MAS_TABS = 4;   // secciones que entran en la barra inferior del celular

// ¿la persona lidera su team en el boliche actual? (jefe solo donde vive su team)
const lideraAca = () => !!me.team_id && (!myTeamClubs || myTeamClubs.includes(club));
function tabsFor() {
  // módulo barra: pestañas propias, no ven nada de puerta
  if (me.rol === "propietario") return [["inventario", "Inventario"], ["barpos", "Vender"], ["barcierre", "Cierre"], ["baranalitica", "Analítica"], ["barmov", "Movimientos"]];
  if (me.rol === "deposito") return [["recepcion", "Registrar"], ["recepmias", "Lo mío"]];
  if (me.rol === "barra") return [["barpos", "Vender"]];
  if (me.rol === "caja") return [["caja", "Relacionadores"]];
  // El portero abre en el escáner: es lo que hace toda la noche.
  // El portero entra por Accesos, que para él es escáner + búsqueda.
  /* "rrpps" es SOLO CONSULTA: el guardia busca al relacionador que llega y
     ve a qué team pertenece. No marca nada — marcar es de la caja. */
  if (me.rol === "portero") return [["accesos", "Accesos"], ["lista", "Lista"], ["rrpps", "RRPPs"], ["mesas", "Mesas"]];
  if (me.rol === "admin") {
    // "eventos" es el Inicio: la gestión del evento es la puerta de entrada.
    // "accesos" agrupa listas, entradas, scanner e historial: es la misma
    // pregunta operativa vista de distintas formas.
    const t = [["eventos", "Inicio"], ["accesos", "Accesos"], ["mesas", "Mesas"], ["stats", "Reporte"]];
    if (lideraAca()) t.splice(3, 0, ["team", "Team"]);  // admin que además lidera un team acá
    return t;
  }
  if (me.rol === "jefe") {
    const t = [["accesos", "Accesos"], ["mesas", "Mesas"]];
    if (lideraAca()) t.push(["team", "Mi team"]);       // jefe solo en el boliche de su team
    t.push(["stats", me.rol === "jefe" && lideraAca() ? "Stats" : "Mis stats"]);
    return t;
  }
  return [["accesos", "Accesos"], ["mesas", "Mesas"], ["stats", "Mis stats"]];
}
const homeTab = () => tabsFor()[0][0];
/* La navegación sale de una sola fuente (tabsFor) y se pinta en dos
   lugares: la barra lateral en escritorio y la inferior en móvil. Cada
   una es la forma natural de su dispositivo, no la misma comprimida. */
function buildTabbar() {
  const items = tabsFor();
  const extras = accionesMas();
  $("#tabbar").innerHTML = items.map(([t, l]) =>
    `<button data-t="${t}" title="${esc(l)}"><svg viewBox="0 0 24 24" class="ic">${TAB_ICONS[t]}</svg><span>${esc(l)}</span></button>`).join("")
    + (extras.length ? `<div class="nav-sep" role="presentation"><span>Más</span></div>` + extras.map(([k, l]) =>
      `<button data-x="${k}" title="${esc(l)}"><svg viewBox="0 0 24 24" class="ic">${EXTRA_ICONS[k]}</svg><span>${esc(l)}</span></button>`).join("") : "");

  // En el celular entran cuatro; el resto va detrás de "Más".
  const bn = $("#botnav");
  if (bn) {
    const mas = items.length > MAS_TABS || extras.length;
    const vis = items.slice(0, mas ? MAS_TABS : items.length), resto = items.slice(vis.length);
    bn.innerHTML = vis.map(([t, l]) =>
      `<button data-t="${t}"><svg viewBox="0 0 24 24" class="ic">${TAB_ICONS[t]}</svg><span>${esc(l)}</span></button>`).join("")
      + ((resto.length || extras.length) ? `<button data-mas="1"><svg viewBox="0 0 24 24" class="ic"><circle cx="5" cy="12" r="1.6"/><circle cx="12" cy="12" r="1.6"/><circle cx="19" cy="12" r="1.6"/></svg><span>Más</span></button>` : "");
  }
  setTab();
}

const irATab = t => { tab = t; setTab(); renderTab(); cerrarNav(); };
$("#tabbar").onclick = e => {
  const b = e.target.closest("button"); if (!b) return;
  if (b.dataset.x) return accionesMas().find(([k]) => k === b.dataset.x)?.[2]();
  irATab(b.dataset.t);
};
$("#botnav") && ($("#botnav").onclick = e => {
  const b = e.target.closest("button"); if (!b) return;
  if (b.dataset.mas) return sheetMasTabs();
  irATab(b.dataset.t);
});

/* "Más" del celular: las secciones que no entran en la barra inferior y
   los accesos secundarios (usuarios, rechazados, lista de la caja, QRs). */
function sheetMasTabs() {
  const resto = tabsFor().slice(MAS_TABS), extras = accionesMas();
  sheet(`<div class="sh-h">Más</div>
    ${resto.length ? `<div class="mas-grid">${resto.map(([t, l]) =>
      `<button class="mas-item" data-mt="${t}"><svg viewBox="0 0 24 24" class="ic">${TAB_ICONS[t]}</svg><span>${esc(l)}</span></button>`).join("")}</div>` : ""}
    ${extras.length ? `<div class="mas-lista"${resto.length ? ' style="margin-top:14px"' : ""}>${extras.map(([k, l]) =>
      `<button class="mas-op" data-mx="${k}"><svg viewBox="0 0 24 24" class="ic">${EXTRA_ICONS[k]}</svg><span>${esc(l)}</span>
        <svg viewBox="0 0 24 24" class="ic mas-chev"><path d="M9 6l6 6-6 6"/></svg></button>`).join("")}</div>` : ""}`);
  document.querySelectorAll("#sheetBody [data-mt]").forEach(b => b.onclick = () => { closeSheet(); irATab(b.dataset.mt); });
  document.querySelectorAll("#sheetBody [data-mx]").forEach(b => b.onclick = () =>
    extras.find(([k]) => k === b.dataset.mx)?.[2]());
}

function setTab() {
  document.querySelectorAll("#tabbar button, #botnav button").forEach(b =>
    b.classList.toggle("on", b.dataset.t === tab || (b.dataset.x === "usuarios" && tab === "gente")));
  // "Más" queda marcado cuando la sección activa vive dentro de él.
  const mas = document.querySelector("#botnav [data-mas]");
  if (mas) mas.classList.toggle("on", !tabsFor().slice(0, MAS_TABS).some(([t]) => t === tab));
}

/* Menú lateral: fijo en escritorio, deslizable en celular. */
const cerrarNav = () => {
  $("#app").classList.remove("nav-open");
  $("#navScrim") && $("#navScrim").classList.remove("show");
};
$("#navScrim") && ($("#navScrim").onclick = cerrarNav);

/* Contraer la barra lateral: en jornadas largas se gana ancho para las
   tablas. La preferencia queda guardada. */
if (localStorage.getItem("nav-mini") === "1") document.documentElement.classList.add("nav-mini");
$("#navToggle") && ($("#navToggle").onclick = () => {
  const mini = document.documentElement.classList.toggle("nav-mini");
  localStorage.setItem("nav-mini", mini ? "1" : "0");
  $("#navToggle").title = mini ? "Expandir el menú" : "Contraer el menú";
});

/* Esqueleto de carga: la pantalla toma la forma de lo que va a aparecer
   en vez de quedar en blanco. Con conexión lenta durante un evento, el
   blanco se lee como "se colgó" y el operador vuelve a tocar. */
function skeleton(filas = 5) {
  return `<div class="sk-wrap" aria-hidden="true">
    <div class="sk-stats">${'<div class="sk sk-stat"></div>'.repeat(4)}</div>
    ${'<div class="sk-row"><div class="sk sk-av"></div><div class="sk-lines"><div class="sk sk-l1"></div><div class="sk sk-l2"></div></div><div class="sk sk-tag"></div></div>'.repeat(filas)}
  </div>`;
}

function renderTab() {
  // Fuera de Accesos, #main vuelve a ser #main.
  if (tab !== "accesos") accRedir = false;
  const scan = tab === "escaner";
  // Accesos maneja la visibilidad del escáner por su cuenta: dentro de esa
  // sección la cámara convive con la navegación de subtabs.
  if (tab !== "accesos") {
    $("#scanwrap").classList.toggle("hidden", !scan);
    $("#main").classList.toggle("hidden", scan);
    if (!scan) stopCam();
  }
  if (scan) return renderScan();
  // Se pinta el esqueleto y la pantalla que sigue lo reemplaza al resolver.
  $("#main").innerHTML = skeleton();
  // módulo barra: el stock es del boliche, no del evento
  if (tab === "inventario") return screenInventario();
  if (tab === "barconteo") return screenBarConteo();
  if (tab === "barmov") return screenBarMovimientos();
  if (tab === "barcierre") return screenBarCierre();
  if (tab === "baranalitica") return screenBarAnalitica();
  if (tab === "recepcion") return screenRecepcion();
  if (tab === "recepmias") return screenRecepcionMias();
  if (tab === "barpos") return screenBarPOS();
  if (tab === "caja") return screenCaja();   // no depende de evento
  /* con conPantalla: si la RPC falla, muestra "Reintentar" en vez de una
     pantalla en blanco (la función tira throw, como screenCaja). */
  if (tab === "rrpps") return conPantalla(screenRrppsPuerta);   // consulta del portero
  if (!ev && tab !== "eventos") {
    const verHist = ["rrpp", "jefe"].includes(me.rol);
    $("#main").innerHTML = `<div class="empty">No hay eventos próximos en este boliche.${me.rol === "admin" ? " Creá uno en Eventos." : ""}</div>${verHist ? `<div style="text-align:center;margin-top:8px"><button class="btn ghost2" style="width:auto;padding:10px 18px" id="btnHistVacio">Ver eventos pasados</button></div>` : ""}`;
    const bh = $("#btnHistVacio"); if (bh) bh.onclick = sheetHistorialRrpp;
    return;
  }
  if (tab === "accesos") return conPantalla(screenAccesos);
  if (tab === "mesas") return conPantalla(screenMesas);
  if (tab === "entradas") return conPantalla(screenEntradas);
  if (tab === "listas") return conPantalla(screenListas);
  if (tab === "stats") return conPantalla(screenStats);
  if (tab === "team") return conPantalla(screenTeam);
  if (tab === "eventos") return conPantalla(screenEventos);
  if (tab === "lista") return conPantalla(screenListaPuerta);
  if (tab === "gente") return conPantalla(screenGente);   // desde el perfil (admin)
}

/* Red de seguridad del esqueleto de carga.
 *
 * renderTab pinta el skeleton y espera que la pantalla lo reemplace. Si
 * la pantalla lanza una excepción a mitad de camino —una consulta que
 * falla, un dato que no llegó— nadie lo reemplaza y queda cargando para
 * siempre. Esto convierte ese silencio en un error visible con
 * Reintentar, que es lo que el operador necesita a las dos de la mañana.
 */
/* Corta la espera si una consulta queda colgada. No reemplaza al manejo
   de errores —la causa real se arregla arriba— pero evita que una
   conexión que ni responde ni falla deje la pantalla en el limbo. */
const conTiempo = (promesa, ms = 20000) => Promise.race([
  promesa,
  new Promise((_, rechazar) => setTimeout(() => rechazar(new Error("La consulta tardó demasiado")), ms))
]);

async function conPantalla(fn) {
  const cual = tab;
  try {
    await conTiempo(Promise.resolve(fn()));
  } catch (e) {
    console.error("Fallo al pintar", cual, e);
    if (tab !== cual) return;              // ya cambió de sección: no pisar
    $("#main").innerHTML = `<div class="empty">
      No pudimos cargar esta sección.<br>
      <span style="color:var(--text-muted);font-size:12.5px">${esc(e?.message || "Error inesperado")}</span><br>
      <button class="btn ghost2" style="width:auto;margin-top:12px;padding:10px 18px" id="scrRetry">Reintentar</button>
    </div>`;
    const r = $("#scrRetry"); if (r) r.onclick = () => renderTab();
  }
}

/* ============================================================
   ENTRADAS QR (rrpp / jefe / admin)
   ============================================================ */
let lastTk = null;
let tkQ = "", tkFTeam = "", tkFSeller = "";   // filtros de Entradas (persisten entre repintadas)
let recienCreadas = [];   // códigos de la última tanda generada, para marcarlos solos
/* invitados de lista marcados para mandar en tanda. Vive acá y no en el DOM
   porque el acordeón solo dibuja las filas de la lista abierta: si la
   selección saliera de los checkboxes, cambiar de lista la perdería y no se
   podrían mandar juntos invitados de dos listas distintas. */
let lsMarcados = new Set();
/* nombre de la fase de cada entrada. La entrada guarda fase_id; el nombre vive
   en la fase, así que se arma el mapa una vez por pantalla. */
let fasesMap = {}, fasesArte = {};
/* Sobre qué imagen se arma la entrada. Cada fase puede tener su propio arte:
   una Hot Ticket puede salir con un diseño distinto al de la Fase 1. Si la
   fase no tiene arte propio, se usa el del evento, como fue siempre.
   Se resuelve por `fase_id`, que queda guardado en la entrada, así que una
   entrada vieja se sigue dibujando con el arte de SU fase. */
const arteDeFase = t => (t && t.fase_id && fasesArte[t.fase_id]) || null;
const arteTicket = t => arteDeFase(t) || (ev && ev.ticket_url) || null;
const nombreFase = t => (t && t.fase_id && fasesMap[t.fase_id]) || (t && t.fase) || null;
async function screenEntradas() {
  const [datosEn] = await Promise.all([
    conDatos("entradas", () => Promise.all([
      // De acá salen TODOS los contadores de esta pantalla: emitidas, accedieron,
      // por team y por relacionador. Si la lista viene cortada, todos esos números
      // mienten y no cuadran con el Reporte — por eso va paginado.
      traerTodo(() => {
        let q = sb.from("entradas").select("*")
          .eq("evento_id", ev.id).is("mesa_id", null);
        // el relacionador solo ve lo suyo: se recorta EN LA CONSULTA (nada
        // ajeno viaja al navegador), además del filtro local de siempre
        if (me.rol === "rrpp") q = q.eq("rrpp_id", me.id);
        return q.order("created_at", { ascending: false }).order("id");
      }),
      // hasta cuándo puede vender ESTA persona (puede tener excepción propia o de su team)
      sb.rpc("ventana_venta", { p_evento: ev.id, p_user: me.id }),
      sb.rpc("fase_vigente", { p_evento: ev.id }),   // null si el evento no vende por fases
      sb.rpc("fases_evento", { p_evento: ev.id })
    ])),
    loadSinTope(),   // para marcar en dorado las innegables (cachea por club aparte)
  ]);
  let [{ data: tks, error, truncado }, { data: miVentana }, { data: fase }, { data: todasFases }] = datosEn;
  if (error) throw error;   // lo muestra conPantalla con Reintentar
  fasesMap = {}; fasesArte = {};
  (todasFases || []).forEach(f => { fasesMap[f.id] = f.nombre; if (f.ticket_url) fasesArte[f.id] = f.ticket_url; });
  /* Alcance por rol: el relacionador ve sólo lo suyo.
     Se recorta acá, en el origen, para que la lista, el buscador, los
     contadores y el preview del QR queden todos dentro del mismo alcance
     y no haya forma de abrir una entrada ajena. */
  if (me.rol === "rrpp") tks = tks.filter(t => t.rrpp_id === me.id);
  const mine = tks.filter(t => t.rrpp_id === me.id);
  const canSell = ["rrpp", "jefe", "admin"].includes(me.rol);   // jefe vende lo suyo; no toca lo ajeno
  // vendedores + su team (admin/jefe filtran por team y/o por relacionador)
  const verVendedor = me.rol === "admin" || me.rol === "jefe";
  let vendedores = {};            // id -> {nombre, teamId, teamNombre}
  if (verVendedor) {
    const ids = [...new Set(tks.map(t => t.rrpp_id))];
    if (ids.length) {
      // team EFECTIVO en este boliche (no el team base del perfil)
      await loadEfectivos();
      ids.forEach(id => {
        const e = efectivosCache[id];
        if (e) vendedores[id] = { nombre: e.nombre, teamId: e.team_id || "", teamNombre: e.team || "Sin team" };
      });
    }
  }
  const vendedoresList = Object.entries(vendedores).sort((a, b) => a[1].nombre.localeCompare(b[1].nombre));
  const nombreVend = id => vendedores[id]?.nombre || "";
  const teamDeVend = id => vendedores[id]?.teamId || "";
  // teams presentes entre los vendedores, con conteo de entradas
  const teamsMap = {};
  vendedoresList.forEach(([id, v]) => { (teamsMap[v.teamId] = teamsMap[v.teamId] || { nombre: v.teamNombre, ids: [] }).ids.push(id); });
  const teamsList = Object.entries(teamsMap).sort((a, b) => a[1].nombre.localeCompare(b[1].nombre));
  $("#main").innerHTML = `
    <div class="en-h">
      <div class="en-h-tx">
        <h2 class="en-t">Entradas</h2>
        <p class="en-s"><b>${tks.length}</b> emitidas · <b>${tks.filter(t => t.estado === "usada").length}</b> utilizadas</p>
      </div>
      <div class="en-h-acc">
        ${canSell ? `<button class="ghost en-cfg" id="btnCfg" title="Configuración">Configuración ⋯</button>` : ""}
      </div>
    </div>
    ${truncado ? `<div class="hint" style="color:var(--danger);margin:0 0 10px">Hay más de ${tks.length} entradas y no entraron todas — los conteos de esta pantalla están incompletos. Mirá el Reporte.</div>` : ""}
    ${canSell && ev.venta_por_fases ? (fase
      ? `<div class="en-fase ok">Fase abierta: <b>${esc(fase.nombre)}</b> · ${fmtBs(fase.precio)} Bs${fase.quedan_team != null ? ` · te quedan ${fase.quedan_team} de tu team` : fase.quedan != null ? ` · quedan ${fase.quedan}` : ""}</div>`
      : `<div class="en-fase bad">No hay ninguna fase de venta abierta ahora mismo</div>`) : ""}
    ${canSell && miVentana?.hasta ? `<div class="en-fase ${new Date(miVentana.hasta) < new Date() ? "bad" : ""}">${new Date(miVentana.hasta) < new Date() ? "Ya cerró tu venta de prepagadas" : "Podés vender prepagadas hasta las " + hora(miVentana.hasta)}${miVentana.origen === "team" ? " (horario de tu team)" : miVentana.origen === "persona" ? " (horario tuyo)" : ""}</div>` : ""}
    <div id="tkView"></div>
    ${canSell ? `<div class="cta-zona" id="genZona">
      <button class="btn primary cta-abrir" id="btnGenOpen"${ev.venta_por_fases && !fase ? " disabled" : ""}>Generar entrada</button>
    </div>` : ""}
    <div class="en-tools">
      ${tks.length > 8 ? `<div class="en-buscar"><input id="tkFilter" placeholder="Buscar por nombre o código…" autocomplete="off"></div>` : ""}
      ${verVendedor && vendedoresList.length ? `<div class="en-filtros">
        ${teamsList.length ? `<select id="tkTeam" title="Filtrar por team">
          <option value="">Todos los teams (${tks.length})</option>
          ${teamsList.map(([tid, tm]) => `<option value="${tid}">${esc(tm.nombre)} (${tks.filter(t => teamDeVend(t.rrpp_id) === tid).length})</option>`).join("")}
        </select>` : ""}
        <select id="tkSeller" title="Filtrar por relacionador">
          <option value="">Todos los relacionadores</option>
          <option value="__mias__">Solo las mías (${mine.length})</option>
          ${vendedoresList.map(([id, v]) => `<option value="${id}" data-team="${v.teamId}">${esc(v.nombre)} (${tks.filter(t => t.rrpp_id === id).length})</option>`).join("")}
        </select>
      </div>` : ""}
      ${tks.length > 1 ? `<button class="ghost en-orden" id="tkSort">${accLabel(false)}</button>` : ""}
      <span class="en-count" id="tkCount"></span>
    </div>
    <div id="tkTanda" class="tk-tanda hidden">
      <span id="tkTandaN">0 marcadas</span>
      <div class="tk-tanda-acc">
        <button class="btn ghost2" id="tkTandaExp">Exportar</button>
        <button class="btn ghost2" id="tkTandaOff">Limpiar</button>
        <button class="btn primary" id="tkTandaGo">Enviar</button>
      </div>
    </div>
    <div id="tkList">${tks.map(t => {
      const puedeAnular = t.estado === "valida" && (me.rol === "admin" || t.rrpp_id === me.id);   // jefe no anula
      const st = t.estado === "usada" ? `<span class="ce-time">ingresó ${hora(t.used_at)}</span><span class="cebox on">✓</span>`
        : t.estado === "anulada" ? `<span class="tkst" style="background:var(--danger-bg);color:var(--danger)">anulada</span>`
        : `<span class="tkst ok">válida</span>`;
      const rrppNom = nombreVend(t.rrpp_id), teamNom = vendedores[t.rrpp_id]?.teamNombre;
      const subs = verVendedor && vendedores[t.rrpp_id]
        ? `<span class="rc-sub">${IC.person}<span>${esc(rrppNom)}</span></span>${teamNom ? `<span class="rc-sub">${IC.tag}<span>${esc(teamNom)}</span></span>` : ""}`
        : "";
      return `
      <div class="list-row rc" data-row="${esc((t.cliente + " #" + t.code + " " + nombreVend(t.rrpp_id) + " " + (vendedores[t.rrpp_id]?.teamNombre || "")).toLowerCase())}" data-seller="${t.rrpp_id}" data-team="${teamDeVend(t.rrpp_id)}" data-used="${t.estado === "usada" ? 1 : 0}" data-rrppnom="${esc((nombreVend(t.rrpp_id) || "").toLowerCase())}">
        <label class="tk-pick" onclick="event.stopPropagation()"><input type="checkbox" data-pick="${t.code}"></label>
        <div class="r-l" data-code="${t.code}" style="cursor:pointer;flex:1;min-width:0;gap:11px;align-items:flex-start"><span class="code-chip${esInnegable(t) ? " oro" : ""}">#${t.code}</span><span class="rc-body"><span class="rc-nm">${esc(t.cliente)}${esInnegable(t) ? ` <span class="oro-chip">libre</span>` : ""}${nombreFase(t) ? ` <span class="fase-chip">${esc(nombreFase(t))}</span>` : ""}</span>${subs}</span></div>
        <div style="display:flex;gap:7px;align-items:center;flex-shrink:0">${st}
        ${puedeAnular ? `<button class="checkin" data-anular="${t.id}" data-cod="${t.code}" data-cli="${esc(t.cliente)}" data-fase="${esc(nombreFase(t) || "")}" data-est="${t.estado}" style="background:var(--danger-bg);color:var(--danger);border-color:rgba(251,113,133,.35)">Anular</button>` : ""}
        ${me.rol === "admin" ? `<button class="checkin" data-del-tk="${t.id}" data-cod="${t.code}" data-cli="${esc(t.cliente)}" data-est="${t.estado}" title="Eliminar entrada" style="background:var(--surface-3);color:var(--text-3);border-color:var(--line-2);padding:8px 11px">✕</button>` : ""}
        <button class="tk-mas" data-mas-tk="${t.code}" title="Ver ficha" aria-label="Ver ficha de ${esc(t.cliente)}">⋯</button></div>
      </div>`;
    }).join("") || `<div class="empty">Aún no hay entradas.</div>`}
    </div>`;
  // El preview muestra la entrada seleccionada, o dice que no hay ninguna:
  // dejar el QR anterior visible haría creer que es el de la fila que se
  // está mirando.
  if (lastTk && tks.some(x => x.code === lastTk.code)) {
    seleccionarEntrada(tks.find(x => x.code === lastTk.code));
  } else {
    lastTk = null;
    const v = $("#tkView");
    if (v) v.innerHTML = `<div class="tk-vacio">Tocá el nombre de una entrada para ver su QR.</div>`;
  }
  qsa("#main [data-anular], #accBody [data-anular]").forEach(b => b.onclick = async () => {
    // Anular pasa seguido y se puede volver a emitir: segundo toque alcanza.
    if (!dobleToque(b, "¿Anular?")) return;
    const { data, error: e2 } = await sb.rpc("anular_entrada", { p_entrada: b.dataset.anular });
    if (e2) return fail(e2);
    toast(`Entrada #${data.code} anulada`, "warn");
    if (lastTk && lastTk.id === b.dataset.anular) lastTk = null;
    screenEntradas();
  });
  qsa("#main [data-del-tk], #accBody [data-del-tk]").forEach(b => b.onclick = async () => {
    const d = b.dataset;
    // Una entrada ya usada guarda un ingreso real: ahí sí conviene explicar
    // qué se pierde. Las que no se usaron se borran con el segundo toque.
    if (d.est === "usada") {
      if (!await confirmar({
        titulo: `Eliminar entrada #${d.cod}`,
        detalle: [d.cli, `Estado: ${d.est}`],
        aviso: "Esta entrada ya fue usada para ingresar. Al borrarla se pierde ese registro de ingreso.",
        accion: "Eliminar entrada"
      })) return;
    } else if (!dobleToque(b)) return;
    const { data, error: e2 } = await sb.rpc("eliminar_entrada", { p_entrada: b.dataset.delTk });
    if (e2) return fail(e2);
    toast(`Entrada #${data.code} eliminada`, "warn");
    if (lastTk && lastTk.id === b.dataset.delTk) lastTk = null;
    screenEntradas();
  });
  /* Generar entradas en un panel, no como formulario siempre abierto.
     Mismo textarea (#tn) y mismo botón (#btnGen): el handler de abajo lo
     encuentra igual y la RPC no cambia. */
  /* El formulario se despliega donde está el botón, no en un panel: se
     ve en qué evento y con qué precio se está generando, sin tapar la
     pantalla. Cerrarlo devuelve el botón y no toca el QR ni los filtros. */
  const zona = $("#genZona");
  const btnAbrir = () => {
    if (!zona) return;
    zona.innerHTML = `<button class="btn primary cta-abrir" id="btnGenOpen"${ev.venta_por_fases && !fase ? " disabled" : ""}>Generar entrada</button>`;
    conectarAbrirGen();
  };
  function conectarAbrirGen() {
    const b = $("#btnGenOpen");
    if (!b) return;
    b.onclick = () => {
      const precio = fmtBs(fase ? fase.precio : ev.precio_manilla);
      zona.innerHTML = `
        <div class="cta-form">
          <div class="cta-form-h">
            <span class="cta-form-t">Generar entradas</span>
            <button class="cta-form-x" id="genCerrar" aria-label="Cerrar">
              <svg viewBox="0 0 24 24" class="ic"><path d="M6 6l12 12M18 6L6 18"/></svg>
            </button>
          </div>
          <p class="cta-form-s">${fase ? `Fase <b>${esc(fase.nombre)}</b> · ${precio} Bs cada una.` : `${precio} Bs cada una.`}</p>
          <div class="field">
            <label for="tn">Clientes</label>
            <textarea id="tn" rows="4" placeholder="Un nombre completo por línea:&#10;Andre Queirolo&#10;Jose Menacho&#10;Horacio Sandoval"></textarea>
            <small style="color:var(--text-muted)">Uno por línea. Máximo 40 por tanda.</small>
          </div>
          <div id="enResumen" class="iv-resumen">Escribí al menos un nombre.</div>
          <button class="btn primary" id="btnGen">Generar entradas</button>
        </div>`;

      const ta = zona.querySelector("#tn"), res = zona.querySelector("#enResumen");
      const contar = () => {
        const n = expandNombres(ta.value).length;
        res.textContent = n
          ? `Se generarán ${n} entrada${n === 1 ? "" : "s"} · ${fmtBs((fase ? fase.precio : ev.precio_manilla) * n)} Bs`
          : "Escribí al menos un nombre.";
        res.classList.toggle("listo", n > 0);
      };
      ta.addEventListener("input", contar);
      // El cierre se conecta antes que nada: no debe depender de que el
      // foco o el guardado se enganchen bien. Se busca dentro de la zona
      // porque $() redirige a #accBody y puede no alcanzar este nodo.
      zona.querySelector("#genCerrar").onclick = btnAbrir;
      conectarGenerar();
      try { if (!window.matchMedia("(hover: none)").matches) ta.focus(); } catch { /* sin foco */ }
    };
  }
  conectarAbrirGen();

  /* Configuración de preventa: eran tres botones grandes apilados que
     empujaban la lista hacia abajo. Ahora viven detrás de un menú. */
  const bcfg = $("#btnCfg");
  if (bcfg) bcfg.onclick = () => {
    sheet(`<div class="sh-h">Configuración</div>
      <div class="mas-lista">
        ${me.rol === "admin" ? `<button class="mas-op" data-cfg="horario">${IC.clock}<span>Horario de venta de prepagadas${ev.manilla_hasta_ts || ev.manilla_desde ? " ✓" : ""}</span></button>` : ""}
        ${me.rol === "admin" && ev.venta_por_fases ? `<button class="mas-op" data-cfg="fases">${IC.tag}<span>Fases de preventa${fase ? ` · ${esc(fase.nombre)}` : " · ninguna abierta"}</span></button>` : ""}
      </div>`);
    document.querySelectorAll("#sheetBody [data-cfg]").forEach(b => b.onclick = () => {
      const op = b.dataset.cfg;
      if (op === "horario") return sheetVentanaPrepagadas();
      if (op === "fases") return sheetFases(ev.id, ev.nombre, "entradas");
    });
  };

  conectarGenerar();
  function conectarGenerar() {
  const btn = $("#btnGen");
  if (btn) btn.onclick = async () => {
    const nombres = expandNombres($("#tn").value);
    if (!nombres.length) return toast("Pegá al menos un nombre", "warn");
    if (nombres.length > 40) return toast("Máximo 40 por tanda", "warn");
    btn.disabled = true;
    let ok = 0, ultima = null, corte = null; const creados = [];
    for (const nm of nombres) {
      btn.textContent = `Generando ${ok + 1}/${nombres.length}…`;
      const { data, error: e2 } = await sb.rpc("generar_entrada", { p_evento: ev.id, p_cliente: nm });
      if (e2) { corte = e2.message; break; }
      ok++; ultima = data; creados.push(data.code);
    }
    btn.disabled = false;
    if (ultima) lastTk = { ...ultima, estado: "valida" };
    recienCreadas = creados;
    // si se cortó a mitad hay que decir CUÁNTAS quedaron sin generar: si no, el
    // rrpp cree que salieron las 10 y le faltan 7 clientes por avisar
    if (corte) {
      toast(ok
        ? `${corte} · se generaron ${ok} de ${nombres.length}, faltaron ${nombres.length - ok}`
        : corte, "warn");
    } else {
      toast(ok === 1 ? `Entrada #${ultima.code} generada`
                     : `${ok} entradas generadas — ya están marcadas, tocá Enviar`);
    }
    // Repintar devuelve el botón a su lugar: no hay panel que cerrar.
    screenEntradas();
  };
  }
  /* Tocar el nombre selecciona esa entrada y pinta su QR arriba, en el
     momento. Antes sólo cambiaba lastTk y el preview se pintaba durante
     el render de la pantalla, así que había que salir y volver para verlo. */
  qsa("#main [data-code], #accBody [data-code]").forEach(r => r.onclick = () => {
    const t = tks.find(x => x.code === r.dataset.code);
    if (t) seleccionarEntrada(t);
  });

  /* La ficha completa vive detrás del ⋯: el nombre queda para el QR, que
     es lo que más se hace en esta pantalla. */
  qsa("#main [data-mas-tk], #accBody [data-mas-tk]").forEach(b => b.onclick = e => {
    e.stopPropagation();
    const t = tks.find(x => x.code === b.dataset.masTk);
    if (t) sheetDetalleEntrada(t, nombreVend, vendedores);
  });
  /* selección múltiple: marcar varias y mandarlas en una sola tanda */
  const barra = $("#tkTanda"), cuenta = $("#tkTandaN");
  const marcados = () => [...document.querySelectorAll("#tkList [data-pick]:checked")]
    .map(c => tks.find(t => t.code === c.dataset.pick)).filter(Boolean);
  const refrescarBarra = () => {
    const n = marcados().length;
    barra.classList.toggle("hidden", n === 0);
    cuenta.textContent = `${n} marcada${n === 1 ? "" : "s"}`;
    $("#tkTandaGo").textContent = `Enviar (${n})`;
  };
  document.querySelectorAll("#tkList [data-pick]").forEach(c => c.onchange = refrescarBarra);
  /* Exportar lo seleccionado: se copia al portapapeles en columnas, listo
     para pegar en una planilla. Sale de lo que ya está en memoria. */
  $("#tkTandaExp") && ($("#tkTandaExp").onclick = () => {
    const sel = marcados();
    if (!sel.length) return;
    const filas = sel.map(t => [
      t.code, t.cliente, nombreFase(t) || "General",
      t.precio || "", t.estado,
      t.used_at ? hora(t.used_at) : "",
      nombreVend(t.rrpp_id) || "",
    ].join("\t"));
    copyText(["Código\tCliente\tEntrada\tPrecio\tEstado\tIngreso\tVendió", ...filas].join("\n"));
    toast(`${sel.length} entrada${sel.length === 1 ? "" : "s"} copiada${sel.length === 1 ? "" : "s"}`);
  });
  $("#tkTandaOff").onclick = () => {
    document.querySelectorAll("#tkList [data-pick]:checked").forEach(c => c.checked = false);
    refrescarBarra();
  };
  $("#tkTandaGo").onclick = () => enviarTanda(marcados());
  // las recién generadas vienen marcadas solas: es el caso de "creé 5, las mando"
  if (recienCreadas.length) {
    document.querySelectorAll("#tkList [data-pick]").forEach(c => {
      if (recienCreadas.includes(c.dataset.pick)) c.checked = true; });
    recienCreadas = [];
    refrescarBarra();
    barra.scrollIntoView({ block: "nearest", behavior: "smooth" });
  }

  const flt = $("#tkFilter"), sel = $("#tkSeller"), selT = $("#tkTeam");
  const listEl = $("#tkList"), countEl = $("#tkCount"), sortBtn = $("#tkSort");
  const ordenOriginal = listEl ? [...listEl.querySelectorAll("[data-row]")] : [];
  let sortAcc = false;
  const refreshCount = () => {
    if (!countEl) return;
    const vis = [...document.querySelectorAll("#tkList [data-row]")].filter(r => r.style.display !== "none");
    countEl.textContent = `${vis.filter(r => r.dataset.used === "1").length}/${vis.length} accedieron`;
  };
  const aplicarOrden = () => {
    if (!listEl) return;
    if (sortAcc) {
      [...listEl.querySelectorAll("[data-row]")].sort((a, b) => {
        const ua = a.dataset.used === "1", ub = b.dataset.used === "1";
        if (ua !== ub) return ua ? -1 : 1;                               // accedieron arriba
        return a.dataset.rrppnom.localeCompare(b.dataset.rrppnom)        // por rrpp (iniciales)
          || a.dataset.row.localeCompare(b.dataset.row);
      }).forEach(r => listEl.appendChild(r));
    } else {
      ordenOriginal.forEach(r => listEl.appendChild(r));
    }
  };
  const aplicarFiltro = () => {
    const q = (flt?.value || "").trim().toLowerCase();
    const s = sel?.value || "", tm = selT?.value || "";
    tkQ = q; tkFTeam = tm; tkFSeller = s;   // sobreviven al repintado (anular/generar)
    document.querySelectorAll("#tkList [data-row]").forEach(row => {
      const okText = row.dataset.row.includes(q);
      const okTeam = !tm || row.dataset.team === tm;
      const okSeller = !s || (s === "__mias__" ? row.dataset.seller === me.id : row.dataset.seller === s);
      row.style.display = okText && okTeam && okSeller ? "" : "none";
    });
    refreshCount();
  };
  if (sortBtn) sortBtn.onclick = () => {
    sortAcc = !sortAcc;
    sortBtn.innerHTML = accLabel(sortAcc);
    sortBtn.classList.toggle("primary", sortAcc);
    aplicarOrden();
  };
  refreshCount();
  if (flt) flt.oninput = aplicarFiltro;
  if (sel) sel.onchange = aplicarFiltro;
  // al elegir team, RECONSTRUIR el selector de relacionador (iOS ignora option[hidden])
  const sellerOptsHTML = tm => `<option value="">Todos los relacionadores</option>
    <option value="__mias__">Solo las mías (${mine.length})</option>
    ${vendedoresList.filter(([id, v]) => !tm || v.teamId === tm)
      .map(([id, v]) => `<option value="${id}">${esc(v.nombre)} (${tks.filter(t => t.rrpp_id === id).length})</option>`).join("")}`;
  if (selT) selT.onchange = () => {
    if (sel) { sel.innerHTML = sellerOptsHTML(selT.value); sel.value = ""; }
    aplicarFiltro();
  };
  // restaurar los filtros que había antes del repintado (anular una entrada
  // repinta la pantalla entera: sin esto se perdían búsqueda y selects)
  if (tkQ || tkFTeam || tkFSeller) {
    if (flt) flt.value = tkQ;
    if (selT && tkFTeam) { selT.value = tkFTeam; if (sel) sel.innerHTML = sellerOptsHTML(tkFTeam); }
    if (sel && tkFSeller) sel.value = tkFSeller;
    aplicarFiltro();
  }
}

function qrSvg(text, cell) {
  const q = qrcode(0, "M"); q.addData(text); q.make();
  return q.createSvgTag({ cellSize: cell || 5, margin: 0 });
}

/* ---------- ticket con diseño del evento (canvas composite) ----------
   Spec para diseñadores: imagen 1080×1620 px (2:3). El sistema superpone:
   caja QR blanca centrada (52% del ancho) desde el 29% de la altura,
   código al 70.5% y nombre del cliente al 75.5%. Dejar esa franja limpia. */
/* Memoizada: el arte del ticket (200-600 KB) se volvía a bajar/decodificar
   con CADA selección de entrada. La misma URL = la misma imagen. */
const imgCache = new Map();
const loadImg = src => {
  if (imgCache.has(src)) return imgCache.get(src);
  const p = new Promise((res, rej) => {
    const i = new Image(); i.crossOrigin = "anonymous";
    i.onload = () => res(i); i.onerror = rej; i.src = src;
  });
  p.catch(() => imgCache.delete(src));   // no dejar cacheado un fallo
  imgCache.set(src, p);
  return p;
};
// achica una imagen (foto/captura de QR) a max px de lado y la devuelve como data-URI JPEG
/* data:image/...;base64,XXX  ->  Blob binario real (para subir a Storage) */
async function dataUrlToBlob(dataUrl) {
  const r = await fetch(dataUrl);
  return await r.blob();
}
/* guardar una imagen: en celu abre la hoja de compartir ("Guardar imagen" -> Fotos);
   en compu descarga el archivo normal */
async function guardarImagen(dataUrl, nombre) {
  try {
    const file = new File([await dataUrlToBlob(dataUrl)], nombre, { type: "image/png" });
    if (navigator.canShare && navigator.canShare({ files: [file] })) {
      await navigator.share({ files: [file], title: nombre });
      toast("Elegí “Guardar imagen” para mandarla a tus Fotos");
      return;
    }
  } catch (e) {
    if (e && e.name === "AbortError") return;   // el usuario cerró la hoja de compartir
  }
  const a = document.createElement("a");
  a.download = nombre; a.href = dataUrl; a.click();
  toast("Imagen descargada");
}
function comprimirImg(file, maxPx = 900, quality = 0.82) {
  return new Promise((res, rej) => {
    const fr = new FileReader();
    fr.onload = () => {
      const img = new Image();
      img.onload = () => {
        const scale = Math.min(1, maxPx / Math.max(img.width, img.height));
        const w = Math.round(img.width * scale), h = Math.round(img.height * scale);
        const cv = document.createElement("canvas"); cv.width = w; cv.height = h;
        cv.getContext("2d").drawImage(img, 0, 0, w, h);
        res(cv.toDataURL("image/jpeg", quality));
      };
      img.onerror = rej; img.src = fr.result;
    };
    fr.onerror = rej; fr.readAsDataURL(file);
  });
}
let lastTkPng = null;
/* Entradas innegables: las que generan Queirolo y jmenacho no tienen hora
   tope en puerta. Se marcan en dorado para que el portero las reconozca de
   una y no se ponga a discutir. Quién las tiene lo dice la base
   (ingreso_sin_tope), no una lista escrita acá. */
let sinTopeIds = new Set();
async function loadSinTope(forzar) {
  if (!forzar && cacheClub.sinTope === club) return;
  const { data } = await sb.rpc("usuarios_sin_tope", { p_club: club });
  sinTopeIds = new Set(data || []);
  cacheClub.sinTope = club;
}
const esInnegable = t => !!t && sinTopeIds.has(t.rrpp_id || me.id);

async function ticketImage(t, oro, fase) {
  const propio = arteDeFase(t);
  const img = await loadImg(propio || ev.ticket_url);
  const W = img.naturalWidth, H = img.naturalHeight;
  const cnv = document.createElement("canvas"); cnv.width = W; cnv.height = H;
  const ctx = cnv.getContext("2d");
  ctx.drawImage(img, 0, 0);
  const box = W * 0.52, bx = (W - box) / 2, by = H * 0.29, rad = box * 0.07;
  ctx.fillStyle = "#fff";
  ctx.beginPath(); ctx.roundRect(bx, by, box, box, rad); ctx.fill();
  const q = qrcode(0, "M"); q.addData(t.payload || `EVT:${ev.id}:${t.code}`); q.make();
  const n = q.getModuleCount(), pad = box * 0.06, cell = (box - 2 * pad) / n;
  ctx.fillStyle = "#000";
  for (let r = 0; r < n; r++) for (let c = 0; c < n; c++)
    if (q.isDark(r, c)) ctx.fillRect(bx + pad + c * cell, by + pad + r * cell, cell + 0.5, cell + 0.5);
  ctx.textAlign = "center";
  // código y nombre pegados justo debajo del QR (no al pie del arte)
  const codeY = by + box + H * 0.055, nameY = codeY + W * 0.075;
  ctx.shadowColor = "rgba(0,0,0,.9)"; ctx.shadowBlur = W * 0.02;
  ctx.fillStyle = "#fff";
  ctx.font = `700 ${Math.round(W * 0.078)}px "Space Grotesk", sans-serif`;
  ctx.fillText("#" + t.code, W / 2, codeY);
  ctx.font = `500 ${Math.round(W * 0.042)}px Inter, sans-serif`;
  ctx.fillText(t.cliente, W / 2, nameY);
  // si la fase trae su propio arte, el sello sobra: la imagen ya la distingue
  if (fase && !propio) marcaFase(ctx, W, H, fase);
  if (oro) marcaOro(ctx, W, H);
  return cnv.toDataURL("image/png");
}

/* La tanda impresa en la entrada. El cliente compró un "Hot Ticket" y eso es
   parte de lo que compró: sirve para él y para el que revisa en la puerta. */
function marcaFase(ctx, W, H, txt) {
  ctx.shadowColor = "transparent"; ctx.shadowBlur = 0;
  const t = String(txt).toUpperCase();
  ctx.font = `800 ${Math.round(W * 0.032)}px "Space Grotesk", sans-serif`;
  ctx.textAlign = "center"; ctx.textBaseline = "middle";
  const pw = ctx.measureText(t).width + W * 0.07, ph = W * 0.068;
  const px = (W - pw) / 2, py = H * 0.925 - ph / 2;
  ctx.fillStyle = "rgba(0,0,0,.55)";
  ctx.beginPath(); ctx.roundRect(px, py, pw, ph, ph / 2); ctx.fill();
  ctx.strokeStyle = "rgba(255,255,255,.5)"; ctx.lineWidth = Math.max(1, W * 0.0025);
  ctx.beginPath(); ctx.roundRect(px, py, pw, ph, ph / 2); ctx.stroke();
  ctx.fillStyle = "#fff";
  ctx.fillText(t, W / 2, py + ph / 2 + W * 0.002);
  ctx.textBaseline = "alphabetic";
}

/* marco dorado + sello, encima del arte del evento */
function marcaOro(ctx, W, H) {
  ctx.shadowColor = "transparent"; ctx.shadowBlur = 0;
  const m = W * 0.022, r = W * 0.035;
  const oro = ctx.createLinearGradient(0, 0, W, H);
  oro.addColorStop(0, "#ffe9a3"); oro.addColorStop(.5, "#e8b530"); oro.addColorStop(1, "#ffdf7a");
  ctx.strokeStyle = oro; ctx.lineWidth = W * 0.016;
  ctx.beginPath(); ctx.roundRect(m, m, W - 2 * m, H - 2 * m, r); ctx.stroke();
  // sello arriba, sobre el marco
  const txt = "ACCESO LIBRE";
  ctx.font = `800 ${Math.round(W * 0.037)}px "Space Grotesk", sans-serif`;
  const pw = ctx.measureText(txt).width + W * 0.075, ph = W * 0.078;
  const px = (W - pw) / 2, py = m - ph / 2;
  ctx.fillStyle = oro;
  ctx.beginPath(); ctx.roundRect(px, py, pw, ph, ph / 2); ctx.fill();
  ctx.fillStyle = "#2a1c00"; ctx.textAlign = "center"; ctx.textBaseline = "middle";
  ctx.fillText(txt, W / 2, py + ph / 2 + W * 0.002);
  ctx.textBaseline = "alphabetic";
}
/* Mandar varias entradas de una.
   El flujo era: generás 5 y las mandás una por una, entrando y saliendo de
   cada ticket. Ahora se marcan varias y salen todas juntas en la hoja de
   compartir del celular — se elige WhatsApp una sola vez y van las 5.
   En compu, donde no hay hoja de compartir, se descargan de a una. */
async function enviarTanda(tks) {
  if (!tks.length) return;
  const btn = $("#tkTandaGo");
  const paso = (i) => { if (btn) btn.textContent = `Armando ${i}/${tks.length}…`; };
  if (btn) btn.disabled = true;
  try {
    await loadSinTope();
    const files = [];
    for (let i = 0; i < tks.length; i++) {
      paso(i + 1);
      const oro = esInnegable(tks[i]);
      const png = arteTicket(tks[i]) ? await ticketImage(tks[i], oro, nombreFase(tks[i])) : null;
      if (!png) break;                       // sin arte del evento no hay imagen que mandar
      files.push(new File([await dataUrlToBlob(png)], `entrada-${tks[i].code}.png`, { type: "image/png" }));
    }
    if (!files.length) { toast("Este evento no tiene diseño de entrada cargado", "warn"); return; }

    const msg = `🎟️ ${files.length} entrada${files.length === 1 ? "" : "s"} · ${clubNombre(club)} — ${ev.nombre} · ${fmtF(ev.fecha)}\n${tks.map(t => t.cliente).join("\n")}\nCada QR vale para 1 solo ingreso.`;
    if (navigator.canShare && navigator.canShare({ files })) {
      try {
        await navigator.share({ files, text: msg });
        toast(`${files.length} entradas listas para mandar`);
        return;
      } catch (e) { if (e && e.name === "AbortError") return; }
    }
    // compu o navegador sin compartir: se bajan una por una
    for (const f of files) {
      const a = document.createElement("a");
      a.href = URL.createObjectURL(f); a.download = f.name;
      document.body.appendChild(a); a.click(); a.remove();
      setTimeout(() => URL.revokeObjectURL(a.href), 4000);
      await new Promise(r => setTimeout(r, 250));   // Chrome bloquea la ráfaga
    }
    toast(`${files.length} entradas descargadas`);
  } finally {
    if (btn) { btn.disabled = false; btn.textContent = `Enviar (${tks.length})`; }
  }
}

/* Conecta el × del preview. Cerrarlo no borra nada más: la lista, los
   filtros y el scroll quedan igual, y tocando otro nombre reaparece. */
function cerrarPreview(view) {
  const bx = $("#tkMiniX");
  if (!bx) return;
  bx.onclick = () => {
    lastTk = null;
    view.innerHTML = `<div class="tk-vacio">Tocá el nombre de una entrada para ver su QR.</div>`;
    qsa("#main .list-row.sel, #accBody .list-row.sel").forEach(r => r.classList.remove("sel"));
  };
}

/* Selecciona una entrada y pinta su QR arriba, al instante.
 *
 * Única vía de selección: la usan el nombre de la fila y el botón "Ver
 * QR" de la ficha. Antes cada uno hacía lo suyo y el preview sólo se
 * dibujaba al re-renderizar la pantalla entera.
 *
 * No re-renderiza nada más: la lista, los filtros y el scroll quedan
 * como estaban.
 */
function seleccionarEntrada(t) {
  lastTk = t;
  // Marca cuál está seleccionada, sin repintar la lista. Sirve para las
  // dos pantallas: en Entradas la fila trae data-code, en Listas data-verqr.
  qsa("#main .list-row.sel, #accBody .list-row.sel").forEach(r => r.classList.remove("sel"));
  qsa("#main [data-code], #accBody [data-code]").forEach(r => {
    if (r.dataset.code === t.code) r.closest(".list-row")?.classList.add("sel");
  });
  qsa("#main [data-verqr], #accBody [data-verqr]").forEach(r => {
    if (r.dataset.verqr === t.id) r.closest(".list-row")?.classList.add("sel");
  });
  renderTicket(t);
  // En el celular el preview está arriba y la lista puede ser larga.
  // Envuelto: un fallo al desplazar no debe impedir ver el QR.
  const v = $("#tkView");
  try { v?.scrollIntoView({ behavior: "smooth", block: "nearest" }); } catch { /* sin scroll */ }
}

/* Ficha de una entrada.
 *
 * Todo lo que hace falta saber sin salir del listado: quién es, qué
 * compró, si ya entró y a qué hora. El QR se abre desde acá y al
 * cerrarlo se vuelve exactamente a donde estabas.
 *
 * Sólo lee lo que ya tiene la entrada: no consulta nada nuevo.
 */
function sheetDetalleEntrada(t, nombreVend, vendedores) {
  const EST = {
    valida: ["ok", "Válida"],
    usada: ["ok", "Utilizada"],
    anulada: ["bad", "Anulada"],
  };
  const [cls, txt] = EST[t.estado] || ["", t.estado];
  const rrpp = nombreVend ? nombreVend(t.rrpp_id) : "";
  const team = vendedores?.[t.rrpp_id]?.teamNombre || "";
  const fase = nombreFase(t);

  const fila = (k, v, extra) => v
    ? `<div class="dt-f${extra ? " " + extra : ""}"><span class="dt-k">${k}</span><span class="dt-v">${v}</span></div>` : "";

  sheet(`
    <div class="dt-top">
      <span class="code-chip${esInnegable(t) ? " oro" : ""}">#${esc(t.code)}</span>
      <span class="tkst ${cls}">${txt}</span>
      ${esInnegable(t) ? `<span class="oro-chip">Innegable</span>` : ""}
    </div>
    <h2 class="dt-nm">${esc(t.cliente)}</h2>

    <div class="dt-datos">
      ${fila("Entrada", fase ? esc(fase) : "General")}
      ${fila("Precio", t.precio ? `${fmtBs(t.precio)} Bs` : "—")}
      ${fila("Vendió", rrpp ? esc(rrpp) : "—")}
      ${fila("Team", team ? esc(team) : "")}
      ${t.estado === "usada"
        ? fila("Ingreso", `Ingresó a las ${hora(t.used_at)}`, "ok")
        : fila("Ingreso", t.estado === "anulada" ? "No puede ingresar" : "Todavía no ingresó")}
    </div>

    <div class="dt-acc">
      <button class="btn primary" id="dtQr">Ver QR</button>
      ${t.estado === "valida" && (me.rol === "admin" || t.rrpp_id === me.id)
        ? `<button class="btn ghost2" id="dtAnular">Anular entrada</button>` : ""}
      ${me.rol === "admin"
        ? `<button class="btn ghost2" id="dtDel" style="color:var(--danger)">Eliminar</button>` : ""}
    </div>`);

  // Misma vía de selección que el nombre: un solo sistema de preview.
  $("#dtQr").onclick = () => { closeSheet(); seleccionarEntrada(t); };

  // En el celular los botones de la fila no se muestran: la ficha es el
  // único camino, así que acá tiene que estar TODO lo que la fila ofrecía.
  const bd = $("#dtDel");
  if (bd) bd.onclick = async () => {
    if (!await confirmar({
      titulo: `Eliminar entrada #${t.code}`,
      detalle: [t.cliente, `Estado: ${t.estado}`],
      aviso: t.estado === "usada"
        ? "Esta entrada ya fue usada para ingresar. Al borrarla se pierde ese registro de ingreso."
        : "La entrada se borra del evento.",
      accion: "Eliminar entrada"
    })) return;
    const { data, error } = await sb.rpc("eliminar_entrada", { p_entrada: t.id });
    if (error) return fail(error);
    toast(`Entrada #${data.code} eliminada`, "warn");
    if (lastTk && lastTk.id === t.id) lastTk = null;
    closeSheet();
    screenEntradas();
  };

  const ba = $("#dtAnular");
  if (ba) ba.onclick = async () => {
    // Desde la ficha sí se explica: acá no hay fila que dé contexto.
    if (!await confirmar({
      titulo: `Anular entrada #${t.code}`,
      detalle: [t.cliente, fase || null, `Estado: ${t.estado}`].filter(Boolean),
      aviso: "La entrada dejará de ser válida para el ingreso.",
      accion: "Anular entrada"
    })) return;
    const { data, error } = await sb.rpc("anular_entrada", { p_entrada: t.id });
    if (error) return fail(error);
    toast(`Entrada #${data.code} anulada`, "warn");
    closeSheet();
    screenEntradas();
  };
}

async function renderTicket(t) {
  const view = $("#tkView"); if (!view) return;
  await loadSinTope();
  const oro = esInnegable(t);
  if (arteTicket(t)) {
    try {
      lastTkPng = await ticketImage(t, oro, nombreFase(t));
      // Compacta: el arte ocupaba toda la pantalla y empujaba la lista
      // hacia abajo. Se ve en chico y se abre en grande si hace falta.
      view.innerHTML = `
        <div class="tk-mini">
          <img src="${lastTkPng}" alt="Entrada de ${esc(t.cliente)}" class="tk-mini-img" id="tkMiniImg">
          <div class="tk-mini-tx">
            <div class="tk-mini-nm">${esc(t.cliente)}</div>
            <div class="tk-mini-cd">#${esc(t.code)}</div>
            <div class="tk-actions">
              <button class="btn wa" onclick="waTk()">WhatsApp</button>
              <button class="btn ghost2" onclick="dlTk()">Descargar</button>
            </div>
          </div>
          <button class="tk-mini-x" id="tkMiniX" aria-label="Cerrar" title="Cerrar">
            <svg viewBox="0 0 24 24" class="ic"><path d="M6 6l12 12M18 6L6 18"/></svg>
          </button>
        </div>`;
      // Ver el arte en grande, en un panel que se cierra como cualquier otro.
      const im = $("#tkMiniImg");
      if (im) im.onclick = () => sheet(`<div class="sh-h">${esc(t.cliente)}<span class="r-sub">#${esc(t.code)}</span></div>
        <img src="${lastTkPng}" alt="Entrada de ${esc(t.cliente)}" style="width:100%;border-radius:16px;border:1px solid var(--border-strong)">
        <div class="tk-actions" style="margin-top:12px">
          <button class="btn wa" onclick="waTk()">WhatsApp</button>
          <button class="btn ghost2" onclick="dlTk()">Descargar</button>
        </div>`);
      cerrarPreview(view);
      return;
    } catch (e) { console.warn("diseño falló, uso genérico", e); }
  }
  lastTkPng = null;
  // El evento no tiene arte cargado: se muestra el ticket genérico, con el
  // mismo × que la versión con imagen.
  view.innerHTML = `<div class="tk-gen">
    ${ticketCard(t, oro)}
    <button class="tk-mini-x" id="tkMiniX" aria-label="Cerrar" title="Cerrar">
      <svg viewBox="0 0 24 24" class="ic"><path d="M6 6l12 12M18 6L6 18"/></svg>
    </button>
  </div>`;
  cerrarPreview(view);
}
window.dlTk = () => {
  if (!lastTkPng || !lastTk) return;
  guardarImagen(lastTkPng, `entrada-${lastTk.code}.png`);
};
/* muestra un ticket (venta o lista gratis) en una hoja, con WhatsApp/Descargar */
async function sheetTicket(t) {
  lastTk = t;
  sheet(`<div class="sh-h">Entrada${t.gratis ? " gratis" : ""} · ${esc(t.cliente)}</div><div id="stkView"><div class="empty">Generando…</div></div>`);
  const view = $("#stkView");
  await loadSinTope();
  const oro = esInnegable(t);
  if (arteTicket(t)) {
    try {
      lastTkPng = await ticketImage(t, oro, nombreFase(t));
      view.innerHTML = `<img src="${lastTkPng}" style="width:100%;border-radius:18px;border:1px solid var(--line-2);margin-bottom:10px">
        <div class="tk-actions"><button class="btn wa" onclick="waTk()">WhatsApp</button><button class="btn ghost2" onclick="dlTk()">Descargar</button></div>`;
      return;
    } catch (e) { console.warn("diseño falló, uso genérico", e); }
  }
  lastTkPng = null;
  view.innerHTML = ticketCard(t, oro);
}
function ticketCard(t, oro) {
  const payload = t.payload || `EVT:${ev.id}:${t.code}`;
  return `<div class="ticket t-club${oro ? " t-oro" : ""}" id="tkCard">
      ${oro ? `<span class="oro-sello">ACCESO LIBRE</span>` : ""}
      ${nombreFase(t) ? `<span class="fase-sello">${esc(nombreFase(t))}</span>` : ""}
      <div class="tk-head">
        <span class="tk-brand">${clubMarkHTML(club)}<span class="wm-club">${esc(clubNombre(club))}</span></span>
        <span class="tk-when">${fmtF(ev.fecha)}</span>
      </div>
      <div class="tk-strip"><span>Entrada</span></div>
      <div class="tk-body">
        <span class="tk-wm">${clubMarkHTML(club)}</span>
        <span class="tk-serial">${esc(ev.nombre.toUpperCase().slice(0, 14))} · #${t.code}</span>
        <div class="qrbox">${qrSvg(payload)}</div>
        <div class="tk-code">#${t.code}</div>
        <div class="tk-nm">${esc(t.cliente)}</div>
      </div>
      <div class="tk-perf"></div>
      <div class="tk-stub">
        <span class="tk-seal"><svg viewBox="0 0 24 24" class="ic"><path d="M12 3l7 3v5c0 4.5-3 8-7 10-4-2-7-5.5-7-10V6z"/><path d="M9 12l2 2 4-4"/></svg>1 solo ingreso</span>
        <span class="tk-by">Vendida por ${esc(me.nombre.split(" ")[0])}</span>
      </div>
    </div>
    <div class="tk-actions">
      <button class="btn wa" onclick="waTk()">WhatsApp</button>
      <button class="btn ghost2" onclick="imgTk()">Descargar</button>
    </div>`;
}
/* Compartir la IMAGEN de la entrada (Web Share nativo → WhatsApp).
   Sin código en el texto: el QR es la entrada. Fallback (PC): descarga + wa.me. */
window.waTk = async () => {
  const t = lastTk; if (!t) return;
  const code = t.code, cliente = t.cliente;
  const msg = `🎟️ Entrada ${clubNombre(club)} — ${ev.nombre} · ${fmtF(ev.fecha)}\n${cliente}\nVálida para 1 solo ingreso. Presentá este QR en puerta.`;
  try {
    let png = lastTkPng;
    if (!png) {
      const card = $("#tkCard");
      if (card) png = await htmlToImage.toPng(card, { pixelRatio: 3, backgroundColor: "#1a1a26" });
    }
    if (png && navigator.canShare) {
      const blob = await (await fetch(png)).blob();
      const file = new File([blob], `entrada-${code}.png`, { type: "image/png" });
      if (navigator.canShare({ files: [file] })) {
        try { await navigator.share({ files: [file], text: msg }); return; }
        catch (e) { if (e.name === "AbortError") return; }
      }
    }
    if (png) { const a = document.createElement("a"); a.download = `entrada-${code}.png`; a.href = png; a.click(); toast("Imagen descargada — adjuntala en WhatsApp"); }
  } catch (e) { console.warn(e); }
  window.open("https://wa.me/?text=" + encodeURIComponent(msg), "_blank");
};
window.imgTk = async () => {
  if (!lastTk) return;
  try {
    const url = await htmlToImage.toPng($("#tkCard"), { pixelRatio: 3, backgroundColor: "#1a1a26" });
    await guardarImagen(url, `entrada-${lastTk.code}.png`);
  } catch (e) { fail(e); }
};


/* Quién ve el botón de exportar contabilidad. Vive acá y no en
   contabilidad.js porque ese módulo se carga BAJO DEMANDA (al tocar el
   botón), así que la pantalla tiene que poder decidir sin él.
     · contabilidad_total (marca de la base: hoy @aqueirolo e
       @IpadQueirolo) -> libro general, todos los teams.
     · rol jefe -> libro de SU team; la RPC no le da nada más.
   Un admin sin la marca no lo ve. El filtro real está en el servidor
   (db/14-contabilidad-acceso.sql): esto sólo evita mostrar un botón que
   fallaría. */
const puedeVerExcelContable = () =>
  !!(me && (me.contabilidad_total === true || me.rol === "jefe"));

/* Carga contabilidad.js si el index no lo trajo (ver el onclick de
   #btnExcel). La URL se deriva del <script> de este mismo app.js, así
   sirve igual servido desde el bucket que abierto en local. */
let _contaPromise = null;
function cargarContabilidad() {
  if (typeof window.exportarContabilidadExcel === "function") return Promise.resolve();
  if (_contaPromise) return _contaPromise;
  _contaPromise = new Promise((ok, err) => {
    const mio = document.querySelector('script[src*="app.js"]');
    const src = (mio?.src || "app.js").replace(/app\.js(\?.*)?$/, "contabilidad.js");
    const s = document.createElement("script");
    s.src = src;
    s.onload = () => typeof window.exportarContabilidadExcel === "function"
      ? ok() : err(new Error("El módulo contable cargó incompleto"));
    s.onerror = () => { _contaPromise = null; err(new Error("No se pudo cargar el módulo contable")); };
    document.head.appendChild(s);
  });
  return _contaPromise;
}

/* Helpers financieros compartidos. */
const veDinero = () => ["admin", "jefe"].includes(me.rol);

/* Participación del boliche sobre las manillas prepagadas. Vive acá y no
   suelto en la fórmula para que cambiarlo sea tocar un solo número. */
const PCT_BOLICHE_MANILLAS = 0.5;

/* Resultado para el boliche.
 *
 *   50% de las manillas prepagadas que ingresaron
 *   + mesas brutas − comisión del combo
 *
 * Manillas prepagadas = entradas con mesa_id nulo (las de combo ya están
 * contadas dentro del precio de la mesa) y estado "usada", que es como la
 * base marca las que efectivamente ingresaron. Las vendidas sin usar no
 * entran: esto mide lo consumido en la puerta, no lo cobrado en preventa.
 *
 * La comisión de mesas es la fija del combo por cantidad, el mismo
 * criterio que ya usa Reporte (venda quien venda).
 *
 * Compra en puerta se resta: esa plata la cobró el boliche en la puerta,
 * así que la mitad que nos corresponde se descuenta de lo que le pagamos.
 * Sólo cuentan los que ingresaron —anotados que no aparecieron no mueven
 * nada— y sólo si esa lista tiene precio cargado.
 */
function resultadoBoliche(entradas, mesas, puerta) {
  const manillas = (entradas || []).filter(e => e.estado === "usada");
  const manBruto = manillas.reduce((a, e) => a + (+e.precio || 0), 0);
  const manBoliche = manBruto * PCT_BOLICHE_MANILLAS;

  const vendidas = (mesas || []).filter(m => m.estado && m.estado !== "disponible");
  const mesaBruto = vendidas.reduce((a, m) => a + (+m.precio || 0), 0);
  const mesaComision = vendidas.reduce((a, m) => {
    const q = m.combo_qty || 1;
    return a + ((+m.c?.comision_rrpp || 0) + (+m.c?.comision_jefe || 0)) * q;
  }, 0);
  const mesaNeto = Math.max(mesaBruto - mesaComision, 0);

  // Sin precio cargado no se descuenta nada: el cierre queda como antes.
  const pueCant = +(puerta?.ingresaron) || 0;
  const puePrecio = +(puerta?.precio) || 0;
  const pueBruto = pueCant * puePrecio;
  const pueDesc = pueBruto * PCT_BOLICHE_MANILLAS;

  return {
    manCant: manillas.length, manBruto, manBoliche,
    mesaCant: vendidas.length, mesaBruto, mesaComision, mesaNeto,
    pueCant, puePrecio, pueBruto, pueDesc,
    total: manBoliche + mesaNeto - pueDesc,
  };
}



/* ============================================================
   ACCESOS · quién entra al evento
   ============================================================
   Listas, Entradas, Scanner e Historial eran cuatro pantallas sueltas.
   Acá son una sola sección con subtabs: es la misma pregunta operativa
   —quién puede pasar y quién ya pasó— vista de distintas formas.

   No reemplaza la lógica existente: Invitados y Entradas siguen llamando
   a screenListas() y screenEntradas(), que ya funcionan y están
   probadas. Lo que agrega es la capa de navegación, el resumen y las
   vistas de tabla para escritorio.
   ============================================================ */

let accSub = "resumen";          // subtab activa
let accSel = new Set();          // selección para acciones masivas
let accFiltro = { q: "", lista: "", rrpp: "", estado: "" };

/* Qué ve cada rol.
 *
 * El portero trabaja en la puerta: escanea y busca. Los totales del
 * evento no le sirven para decidir si alguien pasa, y le compiten con lo
 * único que necesita mirar.
 *
 * El escáner queda fuera de la navegación de quien no atiende la puerta;
 * el admin lo conserva para supervisar.
 */
/* El Historial es de una sola cuenta, no de un rol: otro admin tampoco lo
   ve. La identidad estable es admin_principal (la cuenta protegida): no
   depende del nombre visible ni del usuario, que podrían cambiar. */
const esDuenioHistorial = () => me?.admin_principal === true;
/* La cuenta con admin_principal es máxima autoridad: nadie más la puede
   modificar (el server lo rechaza igual; acá no se ofrecen acciones que
   jamás van a poder ejecutarse). */
const cuentaProtegida = g => !!g?.admin_principal && g.id !== me.id;

function accSubs() {
  if (me.rol === "portero") return [["scanner", "Scanner"], ["buscar", "Buscar persona"]];
  const t = [["resumen", "Resumen"], ["invitados", "Listas"], ["entradas", "Entradas"]];
  if (esDuenioHistorial()) t.push(["historial", "Historial"]);
  if (me.rol === "admin") t.push(["scanner", "Scanner"]);
  return t;
}

function accHeader() {
  return `
  ${pgHead({ ey: "Puerta", t: "Accesos", s: ev ? `${esc(ev.nombre)} · ${fmtF(ev.fecha)}` : "Quién puede entrar y quién ya entró." })}
  <nav class="ac-subs" role="tablist">
    ${accSubs().map(([k, l]) =>
      `<button role="tab" aria-selected="${accSub === k}" class="ac-sub${accSub === k ? " on" : ""}" data-sub="${k}">${l}</button>`).join("")}
  </nav>`;
}

async function screenAccesos() {
  // El shell se pinta siempre en #main, nunca dentro del cuerpo.
  accRedir = false;

  // Si la subtab activa no corresponde al rol, se cae a la primera suya.
  // El portero aterriza en el escáner: no gestiona, opera.
  const permitidas = accSubs().map(([k]) => k);
  if (!permitidas.includes(accSub)) accSub = permitidas[0];

  if (accSub === "buscar") { abrirBuscar(); accSub = "scanner"; return screenAccesos(); }

  /* Invitados y Entradas reutilizan las pantallas que ya funcionan.
   *
   * El problema: esas pantallas se repintan solas (pintarListas, filtros,
   * marcar un ingreso) haciendo $("#main").innerHTML = …, lo que borraba
   * el shell de Accesos y dejaba al usuario adentro sin navegación.
   *
   * La solución es separar los dos contenedores: el shell se pinta una
   * vez en #main y la pantalla escribe dentro de #accBody. Como
   * screenListas() y screenEntradas() apuntan a #main, se redirige ese
   * selector sólo mientras corren, sin tocar una línea de su código. */
  if (accSub === "invitados" || accSub === "entradas") {
    $("#main").innerHTML = accHeader() + `<div id="accBody">${skeleton(4)}</div>`;
    conectarSubs();
    await conBody(accSub === "invitados" ? screenListas : screenEntradas);
    return;
  }
  // El escáner vive dentro de Accesos: se muestra su panel y se le
  // antepone la navegación, para que el portero no quede sin salida.
  if (accSub === "scanner") {
    $("#main").innerHTML = accHeader();
    $("#main").classList.remove("hidden");
    $("#scanwrap").classList.remove("hidden");
    conectarSubs();
    return renderScan();
  }
  // Volver a cualquier otra subtab esconde la cámara.
  $("#scanwrap").classList.add("hidden");
  stopCam();

  $("#main").innerHTML = accHeader() + `<div id="acCuerpo">${skeleton(4)}</div>`;
  conectarSubs();

  // Segunda barrera: aunque se fuerce accSub por fuera de la navegación,
  // el historial sólo corre para su dueño.
  if (accSub === "historial") {
    if (!esDuenioHistorial()) { accSub = accSubs()[0][0]; return screenAccesos(); }
    return accHistorial();
  }
  return accResumen();
}



async function conBody(fn) {
  accRedir = true;
  try {
    await fn();
  } finally {
    // Se mantiene activa: los handlers de la pantalla se disparan después.
    accRedir = (tab === "accesos" && ["invitados", "entradas"].includes(accSub));
  }
}

function conectarSubs() {
  qsa("#main [data-sub], #accBody [data-sub]").forEach(b => b.onclick = () => {
    irASub(b.dataset.sub);
  });
}

/* Cambiar de subtab deja huella en el historial: el botón Atrás del
   navegador vuelve a la anterior en vez de salir de la app. */
function irASub(sub, sinHistorial) {
  accSub = sub;
  accSel.clear();
  if (!sinHistorial) {
    try { history.pushState({ tab: "accesos", sub }, "", `#accesos/${sub}`); } catch { /* file:// */ }
  }
  conPantalla(screenAccesos);
}

/* Atrás del navegador. Actúa sobre las dos secciones con jerarquía
   interna (Accesos y la administración de gente): el resto de la app no
   usa historial y no debe verse afectado. */
window.addEventListener("popstate", e => {
  const s = e.state;
  if (!s) return;
  if (s.tab === "accesos") {
    if (tab !== "accesos") { tab = "accesos"; setTab(); }
    irASub(s.sub, true);
    return;
  }
  if (s.tab === "gente") {
    if (tab !== "gente") { tab = "gente"; setTab(); }
    gnIr(s.nav || null, true);   // sin volver a empujar historial
  }
});

/* ---------- RESUMEN ----------------------------------------------- */
/* La lectura de un vistazo: cuánta gente puede entrar, cuánta entró y
   por qué vía. Es lo que se mira antes de abrir puertas. */
async function accResumen() {
  const [{ data: rs, error }, { data: porLista }] = await conDatos("resumen", () => Promise.all([
    sb.rpc("resumen_evento", { p_evento: ev.id }),
    sb.from("registros").select("lista_tipo_id, ingreso_at").eq("evento_id", ev.id),
  ]));
  if (error) throw error;

  const anot = +rs?.anotados || 0, ing = +rs?.ingresaron || 0;
  const qrTot = +rs?.qr_total || 0, qrUso = +rs?.qr_usados || 0;
  const totalPuede = anot + qrTot, totalEntro = ing + qrUso;
  const pct = totalPuede ? Math.round(totalEntro / totalPuede * 100) : 0;

  // Desglose por lista: dónde está la gente y cuánta ya pasó.
  const porL = {};
  (porLista || []).forEach(r => {
    const k = r.lista_tipo_id || "—";
    porL[k] = porL[k] || { an: 0, in: 0 };
    porL[k].an++; if (r.ingreso_at) porL[k].in++;
  });
  const listas = listaTipos.map(l => ({ nombre: l.nombre, ...(porL[l.id] || { an: 0, in: 0 }) }))
    .filter(l => l.an > 0);

  const cont = $("#acCuerpo");
  if (!cont) return;
  cont.innerHTML = `
    <section class="ac-tot">
      <span class="ac-tot-ic">${ico("check")}</span>
      <div class="ac-tot-l">
        <div class="ac-tot-k">Ingresaron</div>
        <div class="ac-tot-v">${totalEntro}<span> / ${totalPuede}</span></div>
      </div>
      <div class="ac-tot-bar"><i style="width:${pct}%"></i></div>
      <div class="ac-tot-pct">${pct}%</div>
    </section>

    <div class="kps">
      ${kpi({ tag: "button", attrs: 'data-sub="invitados"', ic: "grupo", k: "Listas", v: ing, de: anot,
        s: `${Math.max(anot - ing, 0)} sin llegar`, cola: "chevron" })}
      ${kpi({ tag: "button", attrs: 'data-sub="entradas"', ic: "ticket", k: "Entradas", v: qrUso, de: qrTot,
        s: `${Math.max(qrTot - qrUso, 0)} sin usar`, cola: "chevron" })}
    </div>

    ${listas.length ? `
    <section class="ac-sec">
      <h2 class="ac-h2">Por lista</h2>
      <div class="ac-listas">
        ${listas.map(l => {
          const p = l.an ? Math.round(l.in / l.an * 100) : 0;
          return `<div class="ac-lista">
            <div class="ac-lista-nm">${esc(l.nombre)}</div>
            <div class="ac-lista-bar"><i style="width:${p}%"></i></div>
            <div class="ac-lista-n"><b>${l.in}</b>/${l.an}</div>
          </div>`;
        }).join("")}
      </div>
    </section>` : `<div class="empty">Todavía no hay nadie anotado en este evento.</div>`}`;

  conectarSubs();
}

/* ---------- HISTORIAL --------------------------------------------- */
/* Quién entró y cuándo, en orden. Sirve para reconstruir la noche
   cuando algo no cuadra. */
let accHistCat = "";   // filtro del historial (persiste entre repintadas)
async function accHistorial() {
  // TODOS los ingresos del evento (paginado real, no un tope arbitrario)
  const [regs, tks, gente] = await conDatos("historial", () => Promise.all([
    // ingreso_por / portero_id: quién tickeó o escaneó cada ingreso
    traerTodo(() => sb.from("registros").select("nombre, ingreso_at, lista_tipo_id, ingreso_por")
      .eq("evento_id", ev.id).not("ingreso_at", "is", null)
      .order("ingreso_at", { ascending: false }).order("id")),
    traerTodo(() => sb.from("entradas").select("cliente, used_at, code, portero_id")
      .eq("evento_id", ev.id).eq("estado", "usada")
      .order("used_at", { ascending: false }).order("id")),
    // nombres de quienes validan (porteros incluidos: efectivosCache no los
    // trae). Cambia poquísimo: TTL largo y compartido entre visitas.
    conDatos("nombresGente", () => sb.from("profiles").select("id, nombre"), 300000),
  ]));
  if (regs.error) throw regs.error;
  if (tks.error) throw tks.error;

  const nomL = id => (listaTipos.find(l => l.id === id) || {}).nombre || "Lista";
  const nomPersona = {};
  (gente.data || []).forEach(p => { nomPersona[p.id] = p.nombre; });
  // Las dos vías se mezclan en una sola línea de tiempo: en la puerta lo
  // que importa es el orden real, no de qué tabla vino cada uno.
  const filas = [
    ...(regs.data || []).map(r => ({ t: r.ingreso_at, nm: r.nombre, via: nomL(r.lista_tipo_id), tipo: "lista", cat: r.lista_tipo_id || "", por: nomPersona[r.ingreso_por] || "" })),
    ...(tks.data || []).map(t => ({ t: t.used_at, nm: t.cliente, via: `#${t.code}`, tipo: "qr", cat: "__qr__", por: nomPersona[t.portero_id] || "" })),
  ].filter(f => f.t).sort((a, b) => (a.t < b.t ? 1 : -1));

  // filtros por vía: Todos · Entradas (QR) · una por cada lista con ingresos
  // (Invitados, Compra en Puerta, Free cover… según el evento)
  const porCat = {};
  filas.forEach(f => { porCat[f.cat] = (porCat[f.cat] || 0) + 1; });
  if (!filas.some(f => f.cat === accHistCat)) accHistCat = "";
  const chips = [
    ["", `Todos (${filas.length})`],
    ...(porCat.__qr__ ? [["__qr__", `Entradas (${porCat.__qr__})`]] : []),
    ...listaTipos.filter(l => porCat[l.id]).map(l => [l.id, `${l.nombre} (${porCat[l.id]})`]),
  ];

  const cont = $("#acCuerpo");
  if (!cont) return;
  cont.innerHTML = filas.length ? `
    <div class="hf-filtros">
      ${chips.map(([v, l]) => `<button class="hf-chip${accHistCat === v ? " on" : ""}" data-hf="${v}">${esc(l)}</button>`).join("")}
    </div>
    <div class="ac-hist">
      ${filas.map(f => `
        <div class="ac-hf" data-cat="${esc(f.cat)}">
          <span class="ac-hf-h">${hora(f.t)}</span>
          <span class="ac-hf-ic ${f.tipo}">${f.tipo === "qr" ? IC.qr : IC.people}</span>
          <span class="ac-hf-nm">${esc(f.nm)}</span>
          <span class="ac-hf-via">${esc(f.via)}</span>
          ${f.por ? `<span class="ac-hf-por" title="Quién validó este ingreso">✓ ${esc(f.por)}</span>` : ""}
          <span class="ac-hf-ok">Ingresó</span>
        </div>`).join("")}
    </div>`
    : `<div class="empty">Todavía no ingresó nadie a este evento.</div>`;

  // filtrar es solo mostrar/ocultar filas ya pintadas: cero red
  const aplicarHf = () => {
    qsa("#acCuerpo .ac-hf").forEach(r => { r.style.display = !accHistCat || r.dataset.cat === accHistCat ? "" : "none"; });
    qsa("#acCuerpo .hf-chip").forEach(c => c.classList.toggle("on", c.dataset.hf === accHistCat));
  };
  qsa("#acCuerpo .hf-chip").forEach(c => c.onclick = () => { accHistCat = c.dataset.hf; aplicarHf(); });
  aplicarHf();

  conectarSubs();
}

/* ============================================================
   LISTAS (registro de nombres)
   ============================================================ */
let listaSelId; // lista abierta (accordion); null = todas cerradas
let lsFTeam = "", lsFSeller = ""; // filtros de admin en Listas (persisten entre re-renders)
let lsSortAcc = false; // orden: los que ingresaron arriba (por relacionador)
/* Los registros de la lista se bajan UNA vez por evento y se guardan acá.
   Antes cada toque (abrir un acordeón, filtrar, ordenar, marcar un ingreso)
   volvía a descargarlos: en la puerta, con 300 check-ins, eran 300 descargas
   de ~190 KB cada una. Ahora solo se vuelve a pedir cuando hace falta. */
let lsRegs = null, lsCupos = null, lsEvId = null;
async function cargarRegistrosLista(forzar) {
  if (!forzar && lsEvId === ev.id && lsRegs) return;
  // "forzar" saltea el atajo local; la frescura real la gobierna el caché
  // de datos: cualquier escritura lo limpia y ahí sí se vuelve a la red.
  const [{ data: todosRegs, error }, { data: misCupos }] = await conDatos("registrosLista", () => Promise.all([
    traerTodo(() => sb.from("registros").select("*, rrpp:profiles!registros_rrpp_id_fkey(nombre,team_id)")
      .eq("evento_id", ev.id).order("created_at", { ascending: false }).order("id")),
    sb.rpc("mis_cupos", { p_evento: ev.id })
  ]));
  // El error se propaga en vez de tragarse: antes se avisaba por toast y se
  // seguía igual, dejando lsRegs en null y la pantalla a medio pintar.
  if (error) throw error;
  lsRegs = todosRegs || []; lsCupos = misCupos || []; lsEvId = ev.id;
}
/* repinta con lo que ya está en memoria (no toca la red) */
const pintarListas = () => screenListas(true);

async function screenListas(soloPintar) {
  if (!listaTipos.length) {
    // Puede ser que el evento no tenga listas, o que la carga haya fallado.
    // Se ofrece reintentar en los dos casos: distinguirlos acá obligaría a
    // arrastrar el error, y el botón no molesta cuando de verdad no hay.
    $("#main").innerHTML = `
      ${pgHead({ ey: "Puerta", t: "Listas", s: esc(ev.nombre) })}
      <div class="empty">Todavía no hay listas para este evento.<br>
        <span style="color:var(--text-muted);font-size:12.5px">${me.rol === "admin" ? "Creálas en Eventos → botón Listas." : "Pedile al admin que las cree."}</span><br>
        <button class="btn ghost2" style="width:auto;margin-top:12px;padding:10px 18px" id="lsRetry">Reintentar</button>
      </div>`;
    const r = $("#lsRetry");
    if (r) r.onclick = async () => {
      $("#main").innerHTML = skeleton(3);
      try { await loadListaTipos(); } catch (e) { console.error(e); }
      renderTab();
    };
    return;
  }
  // Las listas arrancan cerradas: se ve el resumen de cada una y se abre
  // la que interesa. Antes se desplegaba la primera y la pantalla era un
  // scroll largo de anotados apenas entrabas.
  if (listaSelId === undefined) listaSelId = null;
  if (listaSelId && !listaTipos.find(l => l.id === listaSelId)) listaSelId = null;
  // entrar a la pantalla valida el caché; los toques de vista solo repintan.
  // Registros y permisos viajan JUNTOS: eran dos tandas de red en serie.
  const [, [{ data: permLs }, { data: gentePosible }]] = await Promise.all([
    cargarRegistrosLista(!soloPintar),
    // lo mismo que ya rige para las mesas: Queirolo puede anotar y dejarlo a
    // nombre del relacionador que consiguió al invitado. Cambia poquísimo:
    // TTL largo.
    conDatos("permisosListas", () => Promise.all([
      sb.rpc("mis_permisos_mesa", { p_evento: ev.id }),
      sb.rpc("vendedores_posibles", { p_evento: ev.id })
    ]), 300000)
  ]);
  const puedeANombre = !!permLs?.a_nombre_de;
  const todosRegs = lsRegs, misCupos = lsCupos;
  const cupoEsp = {}; (misCupos || []).forEach(c => { if (c.especial) cupoEsp[c.lista_tipo_id] = c.cupo; });
  // filtros de admin: por team y/o relacionador (como en Entradas)
  const esAdminLs = me.rol === "admin";
  const puedeTk = me.puede_tickear !== false;   // cuentas con puede_tickear=false: solo borran, no tickean
  if (esAdminLs) await Promise.all([loadTeams(), loadEfectivos()]);
  const tSel = lsFTeam === "__none__" ? "" : lsFTeam;
  // el team que vale es el del boliche que se está mirando
  const okTeamLs = r => !lsFTeam || teamDe(r.rrpp_id) === tSel;
  if (lsFTeam && lsFSeller) { // coherencia: si el seller no es del team elegido, soltarlo
    const s = (todosRegs || []).find(r => r.rrpp_id === lsFSeller);
    if (s && !okTeamLs(s)) lsFSeller = "";
  }
  const allRegs = (todosRegs || []).filter(r => okTeamLs(r) && (!lsFSeller || r.rrpp_id === lsFSeller));
  const vendLs = {};
  (todosRegs || []).forEach(r => { if (okTeamLs(r)) vendLs[r.rrpp_id] = r.rrpp?.nombre || "?"; });
  const teamsLs = {};
  (todosRegs || []).forEach(r => { const tid = teamDe(r.rrpp_id); teamsLs[tid] = (teamsLs[tid] || 0) + 1; });
  const byLista = {};
  (allRegs || []).forEach(r => (byLista[r.lista_tipo_id] = byLista[r.lista_tipo_id] || []).push(r));
  const ca = (allRegs || []).length, ce = (allRegs || []).filter(r => r.ingreso_at).length;
  const canAdd = ["rrpp", "jefe", "admin"].includes(me.rol);   // jefe anota lo suyo; no tickea ni borra ajenos
  const nrm = s => (s || "").toLowerCase().normalize("NFD").replace(/[̀-ͯ]/g, "");
  // Se declara antes de pintar porque el HTML de cada fila la usa. Estando
  // más abajo caía en zona muerta temporal y rompía el render completo.
  const nombreLista = id => listaTipos.find(l => l.id === id)?.nombre || "?";
  // misma regla que el botón QR de cada fila: los tuyos, los de tu team si
  // sos jefe, todos si sos admin. La base la vuelve a aplicar igual.
  const puedeMandar = r => canAdd && (me.rol === "admin" || r.rrpp_id === me.id
    || (me.rol === "jefe" && teamDe(r.rrpp_id) === me.team_id));
  $("#main").innerHTML = `
    <div class="iv-h">
      <div class="iv-h-tx">
        <h2 class="iv-t">Listas</h2>
        <p class="iv-s"><b>${ca}</b> anotados · <b>${ce}</b> ingresaron</p>
      </div>
      ${/* Con una lista abierta el botón vive en su cabecera, junto a los
            datos de esa lista. Acá sólo aparece cuando no hay ninguna
            abierta, para que agregar no quede sin acceso. */
        canAdd && listaTipos.length && !listaSelId
          ? `<button class="btn primary iv-add" data-addlt="${listaTipos[0].id}">Agregar invitados</button>` : ""}
    </div>
    <div class="iv-tools">
      <div class="iv-buscar"><input id="lsBuscar" placeholder="Buscar por nombre en todas las listas…" autocomplete="off"></div>
      ${esAdminLs ? `<div class="iv-filtros">
        <select id="lsTeamF" title="Filtrar por team">
          <option value="">Todos los teams (${(todosRegs || []).length})</option>
          ${teamsCache.filter(t => teamsLs[t.id]).map(t => `<option value="${t.id}"${lsFTeam === t.id ? " selected" : ""}>${esc(t.nombre)} (${teamsLs[t.id]})</option>`).join("")}
          ${teamsLs[""] ? `<option value="__none__"${lsFTeam === "__none__" ? " selected" : ""}>Sin team (${teamsLs[""]})</option>` : ""}
        </select>
        <select id="lsSellerF" title="Filtrar por relacionador">
          <option value="">Todos los relacionadores</option>
          ${Object.entries(vendLs).sort((a, b) => a[1].localeCompare(b[1])).map(([id, nm]) => `<option value="${id}"${lsFSeller === id ? " selected" : ""}>${esc(nm)}</option>`).join("")}
        </select>
      </div>` : ""}
    </div>
    <div id="tkView"></div>
    <div id="lsResultados" class="hidden"></div>
    <div id="lsTanda" class="tk-tanda hidden">
      <span id="lsTandaN">0 marcados</span>
      <div style="display:flex;gap:7px">
        <button class="btn ghost2" id="lsTandaOff" style="padding:9px 13px">Limpiar</button>
        <button class="btn primary" id="lsTandaGo" style="padding:9px 15px">Enviar</button>
      </div>
    </div>
    <div id="lsAcordeon">${listaTipos.map(l => {
      const rs = byLista[l.id] || [];
      const lce = rs.filter(r => r.ingreso_at).length;
      const on = l.id === listaSelId;
      const propios = rs.filter(r => r.rrpp_id === me.id).length;
      const cupoBase = me.rol === "jefe" ? (l.cupo_jefe ?? l.cupo_por_rrpp) : me.rol === "admin" ? l.cupo_admin : l.cupo_por_rrpp;
      const esEspecial = cupoEsp[l.id] != null;
      const miCupo = esEspecial ? cupoEsp[l.id] : cupoBase;
      const cupoTxt = miCupo ? `${propios}/${miCupo} tuyos${esEspecial ? " ★" : ""}` : `${propios} tuyos${me.rol === "admin" ? " · sin límite" : ""}`;
      const rsView = lsSortAcc
        ? [...rs].sort((a, b) => {
            const ia = !!a.ingreso_at, ib = !!b.ingreso_at;
            if (ia !== ib) return ia ? -1 : 1;                                  // ingresaron arriba
            return (a.rrpp?.nombre || "").toLowerCase().localeCompare((b.rrpp?.nombre || "").toLowerCase())  // por relacionador
              || (a.nombre || "").localeCompare(b.nombre || "");
          })
        : rs;
      return `<div class="lst-card ${on ? "open" : ""}" data-lt="${l.id}">
        <div class="lst-head">
          <span class="lst-ic">${icoLista(l.nombre)}</span>
          <span class="lst-nm">${esc(l.nombre)}</span>
          <span class="lst-cnt" title="Anotados"><b>${rs.length}</b> anotados</span>
          <span class="lst-cnt ok" title="Ingresaron"><b>${lce}</b> ingresaron</span>
          ${l.ingreso_hasta ? `<span class="lst-cnt" style="color:var(--warn)" title="Hora límite de ingreso">hasta ${l.ingreso_hasta.slice(0, 5)}</span>` : ""}
          <span class="lst-tar">Free</span>
          ${me.rol === "admin" ? `<button class="lst-menu" data-editlt="${l.id}" title="Editar lista">⋮</button>` : ""}
        </div>
        ${on ? `<div class="lst-body">
          ${canAdd ? `
          <div class="cta-zona" data-zona="${l.id}">
            <button class="btn primary cta-abrir" data-addlt="${l.id}" data-dentro="1">Agregar invitados</button>
            <span class="iv-cupo">${cupoTxt}</span>
          </div>` : ""}
          ${rs.length > 1 ? `<button class="btn ghost2 accbtn ${lsSortAcc ? "primary" : ""}" id="lstSort" style="margin-bottom:12px">${accLabel(lsSortAcc)}</button>` : ""}
          ${rsView.map(r => `
          <div class="list-row rc">
            ${puedeMandar(r) ? `<label class="tk-pick" onclick="event.stopPropagation()"><input type="checkbox" data-lpick="${r.id}"${lsMarcados.has(r.id) ? " checked" : ""}></label>` : ""}
            <div class="r-l" data-verqr="${r.id}" style="cursor:pointer;flex:1;min-width:0">
              <span class="relmark" title="${esc(r.rrpp?.nombre || "")}">${esc((r.rrpp?.nombre || "?")[0])}</span>
              <span class="rc-body">
                <span class="rc-nm">${esc(r.nombre)}</span>
                <span class="iv-est">
                  ${r.ingreso_at
                    ? `<span class="iv-ok">Ingresó ${hora(r.ingreso_at)}</span>`
                    : `<span class="iv-no">No ingresó</span>`}
                  ${r.code ? `<span class="iv-qr">QR</span>` : ""}
                </span>
              </span>
            </div>
            <div style="display:flex;gap:6px;align-items:center">
            ${canAdd && !r.ingreso_at && (me.rol === "admin" || r.rrpp_id === me.id) ? `<button class="checkin" data-qrl="${r.id}" title="Generar/enviar QR gratis" style="background:var(--surface-3);color:var(--text-2);border-color:var(--line-2)">QR</button>` : ""}
            ${me.rol === "admin" && puedeTk
              ? (r.ingreso_at
                ? `<span class="ce-time">${hora(r.ingreso_at)}</span><button class="cebox on" data-unce="${r.id}" title="Tocá para desmarcar">✓</button>`
                : `<button class="cebox" data-ce="${r.id}" aria-label="Marcar ingreso"></button>`)
              : (r.ingreso_at ? `<span class="ce-time">${hora(r.ingreso_at)}</span><span class="cebox on">✓</span>` : `<span class="cebox" style="opacity:.5"></span>`)}
            ${canAdd && (me.rol === "admin" || r.rrpp_id === me.id) ? `<button class="checkin" data-delr="${r.id}" data-nom="${esc(r.nombre)}" data-lst="${esc(nombreLista(r.lista_tipo_id) || "")}" data-rrpp="${esc(r.rrpp?.nombre || "")}" data-ing="${r.ingreso_at ? 1 : 0}" title="Eliminar de la lista" style="background:var(--surface-3);color:var(--text-3);border-color:var(--line-2);padding:8px 10px">✕</button>` : ""}
            </div>
          </div>`).join("") || `<div class="empty">Nadie anotado todavía.</div>`}
        </div>` : ""}
      </div>`;
    }).join("")}</div>`;
  const ltf = $("#lsTeamF"), lsf = $("#lsSellerF");
  if (ltf) ltf.onchange = () => { lsFTeam = ltf.value; pintarListas(); };
  if (lsf) lsf.onchange = () => { lsFSeller = lsf.value; pintarListas(); };
  // buscador global: encuentra al anotado en cualquier lista del evento
  const lb = $("#lsBuscar"), lres = $("#lsResultados"), lac = $("#lsAcordeon");
  lb.oninput = () => {
    const q = nrm(lb.value.trim());
    if (q.length < 2) { lres.classList.add("hidden"); lac.classList.remove("hidden"); return; }
    const hits = (allRegs || []).filter(r => nrm(r.nombre).includes(q)).slice(0, 30);
    lac.classList.add("hidden"); lres.classList.remove("hidden");
    lres.innerHTML = hits.map(r => `
      <div class="list-row">
        <div class="r-l"><span class="relmark">${esc((r.rrpp?.nombre || "?")[0])}</span>
          <span>${esc(r.nombre)}<br><small style="color:var(--text-3)">${esc(nombreLista(r.lista_tipo_id))} · lo anotó ${esc(r.rrpp?.nombre || "?")}</small></span></div>
        ${r.ingreso_at ? `<span class="ce-time">${hora(r.ingreso_at)}</span><span class="cebox on">✓</span>` : `<span class="cebox" style="opacity:.5"></span>`}
      </div>`).join("") || `<div class="empty">Nadie anotado con “${esc(lb.value.trim())}”.</div>`;
  };
  qsa("#main .lst-head").forEach(h => h.onclick = () => {
    const id = h.parentElement.dataset.lt;
    listaSelId = listaSelId === id ? null : id;
    pintarListas();
  });
  qsa("#main [data-editlt]").forEach(b => b.onclick = e => {
    e.stopPropagation();   // no togglear el acordeón
    const l = listaTipos.find(x => x.id === b.dataset.editlt);
    if (l) sheetEditarLista(l, ev.id, async () => { closeSheet(); await cargarRegistrosLista(true); pintarListas(); }, () => { closeSheet(); pintarListas(); });
  });
  const bSort = $("#lstSort");
  if (bSort) bSort.onclick = () => { lsSortAcc = !lsSortAcc; pintarListas(); };
  qsa("#main [data-ce]").forEach(b => b.onclick = async () => {
    if (b.disabled) return;          // el doble toque generaba dos intentos
    b.disabled = true;
    const reg = (lsRegs || []).find(r => r.id === b.dataset.ce);
    const nom = reg?.nombre || "Invitado";

    // Si no hay señal el ingreso se guarda y se envía después: en la puerta
    // la persona ya está entrando, no puede quedar trabada por el wifi.
    const r = await ingresoResiliente("checkin_registro", { p_registro: b.dataset.ce }, `Ingreso de ${nom}`);
    b.disabled = false;

    if (!r.ok) return fail(r.error);
    if (r.encolado) {
      toast(`Ingreso guardado sin señal · ${nom}`, "warn");
      if (reg) reg.ingreso_at = new Date().toISOString();
    } else {
      toast(r.data.resultado === "ok" ? `Ingreso: ${r.data.nombre}` : "Ya había ingresado");
      if (reg) reg.ingreso_at = r.data.hora || new Date().toISOString();
    }
    pintarListas();
  });
  /* Tocar el nombre muestra el QR arriba, igual que en Entradas: misma
     vía de selección y mismo preview, no un segundo sistema.
     El QR de lista se genera al pedirlo (RPC de siempre); si ya existe,
     la base devuelve el mismo código. */
  const verQrLista = async (id, boton) => {
    const reg = (lsRegs || []).find(r => r.id === id);
    if (!reg) return;
    if (boton) boton.disabled = true;
    const { data, error: e2 } = await sb.rpc("generar_qr_lista", { p_registro: id });
    if (boton) boton.disabled = false;
    if (e2) return fail(e2);
    seleccionarEntrada({
      id, code: data.code, cliente: data.nombre,
      payload: `LST:${ev.id}:${data.code}`, gratis: true,
      lista: nombreLista(reg.lista_tipo_id),
    });
  };

  qsa("#main [data-qrl], #accBody [data-qrl]").forEach(b => b.onclick = e => {
    e.stopPropagation();
    verQrLista(b.dataset.qrl, b);
  });
  qsa("#main [data-verqr], #accBody [data-verqr]").forEach(b => b.onclick = () => {
    // Sólo tiene sentido para quien puede generar el QR de esa persona.
    const reg = (lsRegs || []).find(r => r.id === b.dataset.verqr);
    if (!reg) return;
    if (!(canAdd && (me.rol === "admin" || reg.rrpp_id === me.id))) return;
    verQrLista(b.dataset.verqr);
  });

  /* ---- mandar los QR de varios invitados juntos ----
     Mismo flujo que en Entradas: se marcan, sale una sola hoja de compartir y
     se elige WhatsApp una vez. La marca cruza las listas: se pueden mandar
     juntos invitados de dos listas distintas. */
  const lsBarra = $("#lsTanda"), lsCuenta = $("#lsTandaN");
  const refrescarLs = () => {
    const n = lsMarcados.size;
    if (lsBarra) lsBarra.classList.toggle("hidden", n === 0);
    if (lsCuenta) lsCuenta.textContent = `${n} marcado${n === 1 ? "" : "s"}`;
    const g = $("#lsTandaGo"); if (g) g.textContent = `Enviar (${n})`;
  };
  qsa("#main [data-lpick]").forEach(c => c.onchange = () => {
    if (c.checked) lsMarcados.add(c.dataset.lpick); else lsMarcados.delete(c.dataset.lpick);
    refrescarLs();
  });
  const lsOff = $("#lsTandaOff");
  if (lsOff) lsOff.onclick = () => {
    lsMarcados.clear();
    qsa("#main [data-lpick]").forEach(c => c.checked = false);
    refrescarLs();
  };
  const lsGo = $("#lsTandaGo");
  if (lsGo) lsGo.onclick = async () => {
    const ids = [...lsMarcados];
    if (!ids.length) return;
    lsGo.disabled = true; lsGo.textContent = "Generando QR…";
    // una sola llamada para todos: la base devuelve el code de cada uno y le
    // crea el que le falte, sin tocar el de los que ya lo tenían
    const { data, error: eq } = await sb.rpc("generar_qr_lista_masivo", { p_registros: ids });
    lsGo.disabled = false; refrescarLs();
    if (eq) return fail(eq);
    const filas = data || [];
    if (!filas.length) return toast("Ninguno de los marcados es tuyo para mandar", "warn");
    if (filas.length < ids.length) {
      toast(`${ids.length - filas.length} no son tuyos y quedaron afuera`, "warn");
    }
    // el ticket de lista usa el payload LST:, igual que el que se abre al anotar
    await enviarTanda(filas.map(f => ({
      code: f.code, cliente: f.nombre, rrpp_id: f.rrpp_id,
      payload: `LST:${ev.id}:${f.code}`
    })));
    lsMarcados.clear();
    await cargarRegistrosLista(true); pintarListas();
  };
  refrescarLs();
  qsa("#main [data-delr], #accBody [data-delr]").forEach(b => b.onclick = async () => {
    // Quitar a alguien de una lista es frecuente y reversible (se vuelve a
    // anotar). Un diálogo por cada uno frena el trabajo: alcanza con pedir
    // el segundo toque.
    if (!dobleToque(b)) return;
    const { error: e2 } = await sb.rpc("eliminar_registro", { p_registro: b.dataset.delr });
    if (e2) return fail(e2);
    toast(`${b.dataset.nom} eliminado de la lista`, "warn");
    if (lsRegs) lsRegs = lsRegs.filter(r => r.id !== b.dataset.delr);
    pintarListas();
  });
  qsa("#main [data-unce]").forEach(b => b.onclick = async () => {
    if (b.dataset.arm !== "1") { b.dataset.arm = "1"; b.style.borderColor = "var(--danger)"; b.style.color = "var(--danger)"; toast("Tocá de nuevo para desmarcar el ingreso", "warn"); setTimeout(() => { b.dataset.arm = "0"; b.style.borderColor = ""; b.style.color = ""; }, 2500); return; }
    const { error: e2 } = await sb.rpc("descheckin_registro", { p_registro: b.dataset.unce });
    if (e2) return fail(e2);
    toast("Ingreso desmarcado", "warn");
    const reg = (lsRegs || []).find(r => r.id === b.dataset.unce);
    if (reg) reg.ingreso_at = null;
    pintarListas();
  });
  /* Agregar invitados en un panel, no como formulario siempre abierto.
     El contenido y los ids son los mismos de antes, así que el guardado
     de más abajo funciona igual: sólo cambió dónde se muestra. */
  conectarAgregarLista();
  function conectarAgregarLista() {
  document.querySelectorAll("#accBody [data-addlt], #main [data-addlt]").forEach(b => b.onclick = () => {
    const lt = listaTipos.find(x => x.id === b.dataset.addlt);
    if (!lt) return;
    // Si el botón salió de una lista abierta, la decisión ya está tomada.
    const desdeLista = b.dataset.dentro === "1";
    // Al guardar, la lista donde se anotó queda abierta para ver el resultado.
    listaSelId = lt.id;
    /* Dentro de una lista el formulario se despliega ahí mismo, donde
       está el botón. Desde la vista general no hay dónde: va en panel. */
    const zonaL = document.querySelector(`[data-zona="${lt.id}"]`);
    const inline = desdeLista && !!zonaL;
    const pintar = html => {
      if (inline) { zonaL.innerHTML = `<div class="cta-form">${html}</div>`; }
      else sheet(html);
    };

    pintar(`
      ${inline ? `<div class="cta-form-h">
          <span class="cta-form-t">Agregar invitados</span>
          <button class="cta-form-x" id="addCerrar" aria-label="Cerrar">
            <svg viewBox="0 0 24 24" class="ic"><path d="M6 6l12 12M18 6L6 18"/></svg>
          </button>
        </div>` : `<div class="sh-h">Agregar invitados</div>`}
      ${desdeLista
        // Ya se eligió la lista al abrirla: no se vuelve a preguntar.
        ? `<p class="hint" style="margin:-2px 0 12px">Se anotan en <b>${esc(lt.nombre)}</b>.</p>`
        // Desde la vista general no hay lista activa: ahí sí hace falta.
        : listaTipos.length > 1 ? `<div class="field">
            <label for="ivLista">Lista</label>
            <select id="ivLista">${listaTipos.map(x =>
              `<option value="${x.id}"${x.id === lt.id ? " selected" : ""}>${esc(x.nombre)}</option>`).join("")}</select>
          </div>`
        : `<p class="hint" style="margin:-2px 0 12px">Se anotan en <b>${esc(lt.nombre)}</b>.</p>`}
      <div class="field">
        <label for="gnames">Nombres</label>
        <textarea id="gnames" rows="6" placeholder="Un nombre completo por línea:&#10;Andre Queirolo&#10;Jose Menacho&#10;Horacio Sandoval"></textarea>
        <small style="color:var(--text-muted)">Uno por línea. Se anotan todos juntos.</small>
      </div>
      ${puedeANombre ? `<div class="field">
        <label for="lsDuenio">Anotar a nombre de</label>
        <select id="lsDuenio">
          <option value="">${esc(me.nombre)} (vos)</option>
          ${(gentePosible || []).filter(v => v.id !== me.id).map(v =>
            `<option value="${v.id}">${esc(v.nombre)}${v.team ? " · " + esc(v.team) : ""}</option>`).join("")}
        </select>
        <small style="color:var(--text-muted)">Quedan de quien elijas y salen de su cupo. Se guarda que los anotaste vos.</small>
      </div>` : ""}
      <div id="ivResumen" class="iv-resumen">Escribí al menos un nombre.</div>
      <button class="btn primary" id="btnReg">Agregar invitados</button>`);

    // Cerrar devuelve el botón sin tocar el QR, los filtros ni el scroll.
    const bc = $("#addCerrar");
    if (bc) bc.onclick = () => {
      zonaL.innerHTML = `<button class="btn primary cta-abrir" data-addlt="${lt.id}" data-dentro="1">Agregar invitados</button>`;
      conectarAgregarLista();
    };

    // Cuántos se van a agregar, contados con la misma función que guarda.
    const ta = $("#gnames"), res = $("#ivResumen");
    const contar = () => {
      const n = expandNombres(ta.value).length;
      res.textContent = n ? `Se agregarán ${n} invitado${n === 1 ? "" : "s"}.` : "Escribí al menos un nombre.";
      res.classList.toggle("listo", n > 0);
    };
    ta.addEventListener("input", contar);
    // El guardado usa listaSelId: elegir otra lista acá lo actualiza.
    const selL = $("#ivLista");
    if (selL) selL.onchange = () => { listaSelId = selL.value; };
    if (!window.matchMedia("(hover: none)").matches) ta.focus();
    conectarAgregar();
  });
  }

  conectarAgregar();
  function conectarAgregar() {
  const btn = $("#btnReg");
  if (btn) btn.onclick = async () => {
    const names = expandNombres($("#gnames").value);
    if (!names.length) return;
    btn.disabled = true;
    const { data, error: e2 } = await sb.rpc("registrar_lista", {
      p_lista: listaSelId, p_nombres: names, p_a_nombre_de: $("#lsDuenio")?.value || null });
    btn.disabled = false;
    if (e2) return fail(e2);
    toast(data.a_nombre_de
      ? `${data.insertados} anotado(s) a nombre de ${data.a_nombre_de}`
      : `${data.insertados} anotado(s)`);
    if (data.duplicados && data.duplicados.length)
      toast(`Ojo: ya estaba(n) anotado(s) en el evento: ${data.duplicados.join(", ")}`, "warn");
    closeSheet();
    // La lista donde se anotó queda abierta para ver el resultado.
    await cargarRegistrosLista(true);
    pintarListas();
  };
  }
}

/* ============================================================
   LISTA EN PUERTA (portero: buscar + check-in)
   ============================================================ */
async function screenListaPuerta() {
  $("#main").innerHTML = `
    ${pgHead({ ey: "Puerta", t: "Lista en puerta", s: esc(ev.nombre) })}
    <div style="display:flex;gap:8px;align-items:flex-start">
      <div class="field" style="flex:1"><input id="pq" placeholder="Buscar nombre…" autocomplete="off"></div>
      <button class="ghost" id="pqRefresh" title="Traer lo último" style="padding:13px 15px;flex-shrink:0" aria-label="Traer lo último">${ico("recargar")}</button>
    </div>
    <div class="hint" style="margin:-4px 0 10px">Buscá por nombre y marcá el ingreso. Sirve para los de lista y también para los que compraron manilla pero no tienen el QR a mano.</div>
    <div id="prows"><div class="empty">Escribí al menos 2 letras.</div></div>`;
  const input = $("#pq");
  let t0 = null;
  input.oninput = () => { clearTimeout(t0); t0 = setTimeout(buscar, 250); };
  $("#pqRefresh").onclick = async () => {
    const b = $("#pqRefresh"); b.disabled = true; b.style.opacity = ".5";
    await buscar();
    b.disabled = false; b.style.opacity = "";
    toast("Lista actualizada");
  };
  async function buscar() {
    const raw = input.value;
    // filtro discreto de puerta: escribir un espacio adelante "esconde" la lista
    const discreto = raw.length && raw[0] === " ";
    const q = raw.trim();
    if (q.length < 2) { $("#prows").innerHTML = `<div class="empty">${discreto ? "Sin resultados." : "Escribí al menos 2 letras."}</div>`; return; }
    const { data: regsRaw, error } = await sb.rpc("buscar_registros", { p_evento: ev.id, p_q: q });
    if (error) throw error;   // lo muestra conPantalla con Reintentar
    // el filtro discreto tapa a todos MENOS a los de la casa: esos tienen que
    // aparecer siempre, si no el guardia los da por inexistentes
    if (discreto && !(regsRaw || []).some(r => r.sin_tope)) {
      $("#prows").innerHTML = `<div class="empty">Sin resultados.</div>`; return; }
    // orden: los marcados (no pasó filtro) al fondo; arriba los que ingresaron (más reciente primero); pendientes al medio
    const regs = (regsRaw || []).filter(r => !discreto || r.sin_tope).slice().sort((a, b) => {
      if (!!a.filtro_at !== !!b.filtro_at) return a.filtro_at ? 1 : -1;
      if (!!a.ingreso_at !== !!b.ingreso_at) return a.ingreso_at ? -1 : 1;
      if (a.ingreso_at && b.ingreso_at) return b.ingreso_at.localeCompare(a.ingreso_at);
      return (a.nombre || "").localeCompare(b.nombre || "");
    });
    $("#prows").innerHTML = regs.map(r => r.tipo === "entrada" ? `
      <div class="list-row${r.filtro_at ? " row-filtro" : ""}${r.sin_tope ? " row-oro" : ""}">
        <div class="r-l"><span class="relmark" style="${r.sin_tope ? "background:rgba(232,181,48,.16);color:#e8b530" : "background:var(--mesa-bg);color:var(--mesa)"}">Q</span>
          <span>${esc(r.nombre)}${r.sin_tope ? ` <span class="oro-chip">de la casa</span>` : ""}${r.filtro_at ? ` <span class="flag-badge">no pasó filtro</span>` : ""}<br><small style="color:var(--text-3)">${esc(r.lista)} · #${esc(r.code)} · ${r.sin_tope ? "invitación de" : "vendió"} ${esc(r.rrpp)}</small></span></div>
        <div style="display:flex;gap:6px;align-items:center">
          ${r.sin_tope ? "" : `<button class="flagbtn${r.filtro_at ? " on" : ""}" data-flag-e="${esc(r.code)}" title="Marcar: no pasó el control del boliche" aria-label="Marcar: no pasó el control del boliche">${ico("bandera")}</button>`}
          ${r.estado === "anulada"
            ? `<span class="tkst" style="background:var(--danger-bg);color:var(--danger);font-size:11px">anulada</span>`
            : r.ingreso_at
            // se puede desmarcar por si se tickeó a la persona equivocada — salvo las de la casa
            ? `<span class="ce-time">${hora(r.ingreso_at)}</span>${r.sin_tope && me.rol !== "admin" ? `<span class="cebox on" style="cursor:default">✓</span>` : `<button class="cebox on" data-untk-e="${esc(r.code)}" title="Tocá para desmarcar">✓</button>`}`
            // sin QR a mano: se marca el ingreso desde acá
            : `<button class="cebox" data-tk-e="${esc(r.code)}" aria-label="Marcar ingreso"></button>`}
        </div>
      </div>` : `
      <div class="list-row${r.filtro_at ? " row-filtro" : ""}">
        <div class="r-l"><span class="relmark">${esc((r.rrpp || "?")[0])}</span>
          <span>${esc(r.nombre)}${r.filtro_at ? ` <span class="flag-badge">no pasó filtro</span>` : ""}<br><small style="color:var(--text-3)">${esc(r.lista || "")} · lo anotó ${esc(r.rrpp || "?")}</small></span></div>
        <div style="display:flex;gap:6px;align-items:center">
          ${r.sin_tope ? "" : `<button class="flagbtn${r.filtro_at ? " on" : ""}" data-flag="${r.id}" data-nom="${esc(r.nombre)}" title="Marcar: no pasó el control del boliche" aria-label="Marcar: no pasó el control del boliche">${ico("bandera")}</button>`}
          ${r.ingreso_at
            ? `<span class="ce-time">${hora(r.ingreso_at)}</span><button class="cebox on" data-unreg="${r.id}" title="Tocá para desmarcar">✓</button>`
            : `<button class="cebox" data-reg="${r.id}" aria-label="Marcar ingreso"></button>`}
        </div>
      </div>`).join("") || `<div class="empty">Sin resultados para “${esc(q)}”.</div>`;
    document.querySelectorAll("#prows [data-flag-e]").forEach(b => b.onclick = async () => {
      const { data, error: e2 } = await sb.rpc("marcar_filtro_entrada", { p_evento: ev.id, p_code: b.dataset.flagE });
      if (e2) return fail(e2);
      toast(data.marcado ? `${data.nombre} marcado — vendió ${data.rrpp}` : `Marca quitada a ${data.nombre}`, data.marcado ? "warn" : "ok");
      buscar();
    });
    document.querySelectorAll("#prows [data-flag]").forEach(b => b.onclick = async () => {
      const { data, error: e2 } = await sb.rpc("marcar_filtro_registro", { p_registro: b.dataset.flag });
      if (e2) return fail(e2);
      toast(data.marcado ? `${data.nombre} marcado — lo trajo ${data.rrpp}` : `Marca quitada a ${data.nombre}`, data.marcado ? "warn" : "ok");
      buscar();
    });
    // manilla prepagada sin QR a mano: pasa por el MISMO camino que el escáner,
    // así aplica los mismos controles (anulada, ya usada, fuera de hora)
    document.querySelectorAll("#prows [data-tk-e]").forEach(b => b.onclick = async () => {
      b.disabled = true;
      const { data, error: e2 } = await sb.rpc("validar_entrada", { p_evento: ev.id, p_code: b.dataset.tkE });
      if (e2) { b.disabled = false; return fail(e2); }
      const R = data?.resultado;
      if (R === "valida") toast(`Ingreso: ${data.cliente}`);
      else if (R === "usada") toast(`${data.cliente} ya había ingresado ${hora(data.used_at)}`, "warn");
      else if (R === "anulada") toast(`${data.cliente}: entrada anulada. No entra.`, "warn");
      else if (R === "fuera_hora") toast(`${data.cliente}: fuera del horario de ingreso`, "warn");
      else toast("No se encontró esa entrada", "warn");
      buscar();
    });
    let armUnE = null;
    document.querySelectorAll("#prows [data-untk-e]").forEach(b => b.onclick = async () => {
      if (armUnE !== b.dataset.untkE) {
        armUnE = b.dataset.untkE;
        b.style.borderColor = "var(--danger)"; b.style.color = "var(--danger)";
        toast("Tocá de nuevo para desmarcar el ingreso", "warn");
        setTimeout(() => { b.style.borderColor = ""; b.style.color = ""; if (armUnE === b.dataset.untkE) armUnE = null; }, 2500);
        return;
      }
      const { data, error: e2 } = await sb.rpc("descheckin_entrada", { p_evento: ev.id, p_code: b.dataset.untkE });
      if (e2) return fail(e2);
      toast(`Ingreso desmarcado a ${data?.cliente || ""}`, "warn");
      buscar();
    });
    document.querySelectorAll("#prows [data-reg]").forEach(b => b.onclick = async () => {
      b.disabled = true;
      const { data, error: e2 } = await sb.rpc("checkin_registro", { p_registro: b.dataset.reg });
      if (e2) return fail(e2);
      toast(data.resultado === "ok" ? `Ingreso: ${data.nombre}` : "Ya había ingresado", data.resultado === "ok" ? "ok" : "warn");
      buscar();
    });
    let armUn = null;
    document.querySelectorAll("#prows [data-unreg]").forEach(b => b.onclick = async () => {
      if (armUn !== b.dataset.unreg) { armUn = b.dataset.unreg; b.style.borderColor = "var(--danger)"; b.style.color = "var(--danger)"; toast("Tocá de nuevo para desmarcar el ingreso", "warn"); setTimeout(() => { b.style.borderColor = ""; b.style.color = ""; if (armUn === b.dataset.unreg) armUn = null; }, 2500); return; }
      const { error: e2 } = await sb.rpc("descheckin_registro", { p_registro: b.dataset.unreg });
      if (e2) return fail(e2);
      toast("Ingreso desmarcado", "warn");
      buscar();
    });
  }
}

/* ventana de venta de manillas prepagadas (admin): desde/hasta día + hora */
function sheetVentanaPrepagadas() {
  const toLocal = ts => ts ? new Date(new Date(ts).getTime() - new Date().getTimezoneOffset() * 60000).toISOString().slice(0, 16) : "";
  sheet(`
    <div class="sh-h">Horario de venta de prepagadas<span class="r-sub">${esc(ev.nombre)}</span></div>
    <div class="hint" style="margin:0 0 12px">Definí desde y hasta cuándo los relacionadores pueden vender manillas prepagadas. Vacío = sin límite.</div>
    <div class="field"><label>Desde (día y hora)</label><input id="vpD" type="datetime-local" value="${toLocal(ev.manilla_desde)}"></div>
    <div class="field"><label>Hasta (día y hora)</label><input id="vpH" type="datetime-local" value="${toLocal(ev.manilla_hasta_ts)}"></div>
    <button class="btn primary" id="vpGo">Guardar horario</button>
    <div style="height:9px"></div>
    <button class="btn ghost2" id="vpClear">Quitar límites</button>
    ${me.admin_principal ? `
    <div class="sh-h" style="margin-top:20px">Excepciones<span class="r-sub">quién puede vender más tarde</span></div>
    <p class="hint" style="margin:-4px 0 10px">Ejemplo: todos hasta las 22:00, pero el Team AQ hasta las 23:00. La excepción de una persona manda sobre la de su team.</p>
    <div id="vpExc"><div class="empty">Cargando…</div></div>` : ""}`);
  if (me.admin_principal) renderExcepciones();
  $("#vpGo").onclick = async () => {
    const d = $("#vpD").value, h = $("#vpH").value;
    const { error } = await sb.from("eventos").update({
      manilla_desde: d ? new Date(d).toISOString() : null,
      manilla_hasta_ts: h ? new Date(h).toISOString() : null
    }).eq("id", ev.id);
    if (error) return fail(error);
    ev.manilla_desde = d ? new Date(d).toISOString() : null;
    ev.manilla_hasta_ts = h ? new Date(h).toISOString() : null;
    toast("Horario guardado"); closeSheet(); renderTab();
  };
  $("#vpClear").onclick = async () => {
    await sb.from("eventos").update({ manilla_desde: null, manilla_hasta_ts: null }).eq("id", ev.id);
    ev.manilla_desde = null; ev.manilla_hasta_ts = null;
    toast("Sin límites de horario"); closeSheet(); renderTab();
  };
}

/* excepciones de horario: un team (o una persona) que vende más tarde que el resto */
async function renderExcepciones() {
  const cont = $("#vpExc"); if (!cont) return;
  const hhmm = ts => ts ? new Date(ts).toLocaleString("es-BO", { day: "2-digit", month: "2-digit", hour: "2-digit", minute: "2-digit", hour12: false }) : "sin límite";
  const [{ data: exc }] = await Promise.all([sb.rpc("excepciones_venta", { p_evento: ev.id }), loadTeams()]);
  const lista = exc || [];
  cont.innerHTML = `
    ${lista.map(x => `
      <div class="list-row rc">
        <div class="r-l" style="flex:1;min-width:0">
          <span class="relmark" style="${x.tipo === "team" ? "" : "background:var(--surface-3);color:var(--text-2)"}">${x.tipo === "team" ? "T" : esc((x.nombre || "?")[0])}</span>
          <span class="rc-body"><span class="rc-nm">${esc(x.nombre || "—")}</span>
            <span class="rc-sub"><span>${x.tipo === "team" ? "todo el team" : "solo esta persona"} · vende hasta ${hhmm(x.hasta_ts)}</span></span></span></div>
        <button class="checkin" data-delx="${x.id}" title="Quitar excepción" style="background:var(--surface-3);color:var(--text-3);border-color:var(--line-2);padding:8px 11px">✕</button>
      </div>`).join("") || `<div class="empty">Sin excepciones: todos siguen el horario general.</div>`}
    <button class="btn ghost2" id="vpAddExc" style="margin-top:8px">+ Dar más tiempo a un team o persona</button>
    <div id="vpExcForm"></div>`;
  document.querySelectorAll("#vpExc [data-delx]").forEach(b => b.onclick = async () => {
    const { error } = await sb.from("venta_excepcion").delete().eq("id", b.dataset.delx);
    if (error) return fail(error);
    toast("Excepción quitada", "warn"); renderExcepciones();
  });
  $("#vpAddExc").onclick = async () => {
    $("#vpAddExc").style.display = "none";
    await loadEfectivos();
    const gente = Object.values(efectivosCache)
      .filter(g => ["rrpp", "jefe"].includes(g.rol))
      .sort((a, b) => (a.nombre || "").localeCompare(b.nombre || ""));
    const teams = teamsDelClub();
    // por defecto, una hora más que el corte general
    const base = ev.manilla_hasta_ts ? new Date(new Date(ev.manilla_hasta_ts).getTime() + 36e5) : new Date(Date.now() + 36e5);
    const local = new Date(base.getTime() - base.getTimezoneOffset() * 60000).toISOString().slice(0, 16);
    $("#vpExcForm").innerHTML = `
      <div class="seg" style="margin-top:10px"><button type="button" class="segbtn on" data-xt="team">Un team</button><button type="button" class="segbtn" data-xt="persona">Una persona</button></div>
      <div class="field" id="xcTeamBox"><label>Team</label><select id="xcTeam">${teams.map(t => `<option value="${t.id}">${esc(t.nombre)}</option>`).join("")}</select></div>
      <div class="field hidden" id="xcUserBox"><label>Persona</label><select id="xcUser">${gente.map(g => `<option value="${g.user_id}">${esc(g.nombre)} · ${esc(g.team)}</option>`).join("")}</select></div>
      <div class="field"><label>Puede vender hasta</label><input id="xcHasta" type="datetime-local" value="${local}"></div>
      <button class="btn primary" id="xcGo">Guardar excepción</button>`;
    let tipo = "team";
    document.querySelectorAll("#vpExcForm [data-xt]").forEach(b => b.onclick = () => {
      tipo = b.dataset.xt;
      document.querySelectorAll("#vpExcForm [data-xt]").forEach(x => x.classList.toggle("on", x.dataset.xt === tipo));
      $("#xcTeamBox").classList.toggle("hidden", tipo !== "team");
      $("#xcUserBox").classList.toggle("hidden", tipo !== "persona");
    });
    $("#xcGo").onclick = async () => {
      const h = $("#xcHasta").value;
      if (!h) return toast("Poné hasta qué hora", "warn");
      const fila = { evento_id: ev.id, hasta_ts: new Date(h).toISOString(), team_id: null, user_id: null };
      if (tipo === "team") fila.team_id = $("#xcTeam").value; else fila.user_id = $("#xcUser").value;
      // si ya tenía una excepción para este evento, se reemplaza
      const previa = sb.from("venta_excepcion").delete().eq("evento_id", ev.id);
      await (tipo === "team" ? previa.eq("team_id", fila.team_id) : previa.eq("user_id", fila.user_id));
      const { error } = await sb.from("venta_excepcion").insert(fila);
      if (error) return fail(error);
      toast("Excepción guardada");
      renderExcepciones();
    };
  };
}

/* ============================================================
   CAJA: relacionadores por team (para entregar manillas de rrpp)
   ============================================================ */
let cajaSel = null;
let cajaChecks = new Set();
async function screenCaja() {
  // evento del boliche para marcar: primero uno abierto; si no hay (pasó la noche
  // y ya lo cerraron), el último cerrado — la caja tiene que poder marcar igual
  let { data: evActivo } = await sb.from("eventos").select("id,nombre,estado,fecha")
    .eq("club_id", club).neq("estado", "cerrado").order("fecha").limit(1).maybeSingle();
  if (!evActivo) {
    const { data: ult } = await sb.from("eventos").select("id,nombre,estado,fecha")
      .eq("club_id", club).order("fecha", { ascending: false }).limit(1).maybeSingle();
    evActivo = ult || null;
  }
  /* roster_caja = roster_relacionadores + el filtro del evento (sólo los
     que vendieron prepagadas, más las excepciones). Con el filtro apagado
     devuelve exactamente lo mismo que antes. El filtro se aplica en la RPC,
     no acá: esconderlos en el cliente dejaría la lista entera viajando. */
  const [{ data, error }, { data: checks }, { data: filtro }] = await Promise.all([
    sb.rpc("roster_caja", { p_club: club, p_evento: evActivo?.id || null }),
    evActivo ? sb.from("caja_check").select("user_id").eq("evento_id", evActivo.id) : Promise.resolve({ data: [] }),
    evActivo ? sb.from("caja_filtro").select("activo").eq("evento_id", evActivo.id).maybeSingle() : Promise.resolve({ data: null })
  ]);
  if (error) throw error;   // lo muestra conPantalla con Reintentar
  cajaChecks = new Set((checks || []).map(c => c.user_id));
  const filtroOn = !!filtro?.activo;
  const nrm = s => (s || "").toLowerCase().normalize("NFD").replace(/[̀-ͯ]/g, "");
  // solo los del boliche actual
  const gente = (data || []).filter(g => !g.clubs?.length || g.clubs.includes(club));
  const byTeam = {};
  gente.forEach(g => (byTeam[g.team] = byTeam[g.team] || []).push(g));
  const teams = Object.keys(byTeam).sort((a, b) => a === "Sin team" ? 1 : b === "Sin team" ? -1 : a.localeCompare(b));
  const fila = g => `
    <div class="list-row${cajaChecks.has(g.id) ? " row-checked" : ""}" data-cj="${esc(nrm(g.nombre + " " + g.usuario))}">
      <div class="r-l"><span class="relmark">${esc(g.nombre[0])}</span>
        <span>${esc(g.nombre)}${g.rol === "jefe" ? ` <span class="pill" style="background:var(--accent-soft);color:var(--accent-2);font-size:10px;padding:2px 8px">JEFE</span>` : ""}<br>
        <small style="color:var(--text-3)">@${esc(g.usuario)} · ${esc(g.team)}</small></span></div>
      ${evActivo ? `<button class="cebox ${cajaChecks.has(g.id) ? "on" : ""}" data-cchk="${g.id}" data-nom="${esc(g.nombre)}" title="Marcar que entró / recibió su manilla"></button>` : ""}
    </div>`;
  $("#main").innerHTML = `
    ${pgHead({ ey: "Caja", t: "Relacionadores", s: `${esc(clubNombre(club))} · <span id="cjCount">${cajaChecks.size}/${gente.length} atendidos</span>` })}
    <div class="hint" style="margin:0 0 12px">Buscá al relacionador, entregale su manilla y tocá el ✓ para marcar que ya pasó.${evActivo
      ? ` Evento: <b style="color:var(--text-2)">${esc(evActivo.nombre)}</b>${evActivo.estado === "cerrado" ? " (ya cerrado — se sigue pudiendo marcar)" : ""}.`
      : ` <span style="color:var(--warn)">Este boliche todavía no tiene ningún evento creado — pedile al admin que lo cree para poder marcar.</span>`}</div>
    ${filtroOn ? `<div class="hint" style="margin:-6px 0 12px;color:var(--accent-2)">
      Lista filtrada: sólo los que cargaron prepagadas en este evento${gente.length ? ` (${gente.length})` : ""}. Si falta alguien, se agrega desde “Lista de la caja” en el perfil.</div>` : ""}
    <div class="field"><input id="cjBuscar" placeholder="Buscar relacionador…" autocomplete="off"></div>
    <div id="cjResultados" class="hidden"></div>
    <div id="cjTeams">${teams.map(t => `
      <div class="lst-card ${cajaSel === t ? "open" : ""}" data-cjt="${esc(t)}">
        <div class="lst-head">
          <span class="lst-nm">${esc(t)}</span>
          <span class="lst-cnt"><b>${byTeam[t].length}</b></span>
        </div>
        ${cajaSel === t ? `<div class="lst-body">${byTeam[t].map(fila).join("")}</div>` : ""}
      </div>`).join("")}</div>`;
  document.querySelectorAll("#cjTeams .lst-head").forEach(h => h.onclick = () => {
    const t = h.parentElement.dataset.cjt;
    cajaSel = cajaSel === t ? null : t;
    screenCaja();
  });
  const cb = $("#cjBuscar"), cres = $("#cjResultados"), ctm = $("#cjTeams");
  const bindChecks = () => qsa("#main [data-cchk]").forEach(b => b.onclick = async () => {
    const uid = b.dataset.cchk, nom = b.dataset.nom || "", marcado = cajaChecks.has(uid);
    b.disabled = true;
    if (marcado) {
      const { error: e1 } = await sb.from("caja_check").delete().eq("evento_id", evActivo.id).eq("user_id", uid);
      b.disabled = false;
      if (e1) return toast(e1.message, "warn");
      cajaChecks.delete(uid); toast(`${nom} desmarcado`, "warn");
    } else {
      const { error: e2 } = await sb.from("caja_check").upsert({ evento_id: evActivo.id, user_id: uid });
      b.disabled = false;
      if (e2) return toast(e2.message, "warn");
      cajaChecks.add(uid); toast(`✓ ${nom} atendido`);
    }
    b.classList.toggle("on", cajaChecks.has(uid));
    b.closest(".list-row")?.classList.toggle("row-checked", cajaChecks.has(uid));
    const c = $("#cjCount"); if (c) c.textContent = `${cajaChecks.size}/${gente.length} atendidos`;
  });
  bindChecks();
  cb.oninput = () => {
    const q = nrm(cb.value.trim());
    if (q.length < 2) { cres.classList.add("hidden"); ctm.classList.remove("hidden"); return; }
    const hits = gente.filter(g => nrm(g.nombre + " " + g.usuario).includes(q)).slice(0, 30);
    ctm.classList.add("hidden"); cres.classList.remove("hidden");
    cres.innerHTML = hits.map(fila).join("") || `<div class="empty">Sin resultados para “${esc(cb.value.trim())}”.</div>`;
    bindChecks();
  };
}

/* ============================================================
   RRPPs · consulta para la puerta (rol portero)
   ============================================================
   El guardia busca al relacionador que llega y ve a qué team pertenece.
   Es SOLO LECTURA: marcar quién pasó es de la caja, y si los dos marcaran
   se pisarían entre sí.

   Usa la MISMA lista que la caja (roster_caja), así que respeta el
   interruptor de "Lista de la caja": con el filtro puesto, el guardia ve a
   los que cargaron prepagadas más los agregados a mano. Una sola lista
   para la puerta, no dos que se contradigan.

   Seguridad: roster_caja no devuelve ninguna cifra de dinero — nombre,
   usuario, rol y team. El portero sigue sin ver plata, como el resto de
   sus pantallas. */
let rpSel = null;
async function screenRrppsPuerta() {
  let { data: evA } = await sb.from("eventos").select("id,nombre,estado,fecha")
    .eq("club_id", club).neq("estado", "cerrado").order("fecha").limit(1).maybeSingle();
  if (!evA) {
    const { data: ult } = await sb.from("eventos").select("id,nombre,estado,fecha")
      .eq("club_id", club).order("fecha", { ascending: false }).limit(1).maybeSingle();
    evA = ult || null;
  }
  const [{ data, error }, { data: filtro }] = await Promise.all([
    sb.rpc("roster_caja", { p_club: club, p_evento: evA?.id || null }),
    evA ? sb.from("caja_filtro").select("activo").eq("evento_id", evA.id).maybeSingle()
        : Promise.resolve({ data: null })
  ]);
  if (error) throw error;
  const filtroOn = !!filtro?.activo;

  const nrm = s => (s || "").toLowerCase().normalize("NFD").replace(/[̀-ͯ]/g, "");
  const gente = (data || []).filter(g => !g.clubs?.length || g.clubs.includes(club));
  const byTeam = {};
  gente.forEach(g => (byTeam[g.team] = byTeam[g.team] || []).push(g));
  for (const t in byTeam) byTeam[t].sort((a, b) => (a.nombre || "").localeCompare(b.nombre || ""));
  const teams = Object.keys(byTeam).sort((a, b) =>
    a === "Sin team" ? 1 : b === "Sin team" ? -1 : a.localeCompare(b));

  const fila = g => `
    <div class="list-row">
      <div class="r-l"><span class="relmark">${esc((g.nombre || "?")[0])}</span>
        <span>${esc(g.nombre)}${g.rol === "jefe" ? ` <span class="pill" style="background:var(--accent-soft);color:var(--accent-2);font-size:10px;padding:2px 8px">JEFE</span>` : ""}<br>
        <small style="color:var(--text-3)">@${esc(g.usuario || "")} · ${esc(g.team)}</small></span></div>
    </div>`;

  $("#main").innerHTML = `
    ${pgHead({ ey: "Puerta", t: "Relacionadores", s: `${esc(clubNombre(club))} · ${gente.length} en la lista` })}
    <div class="hint" style="margin:0 0 12px">Buscá al relacionador para ver a qué team pertenece.${
      evA ? ` Evento: <b style="color:var(--text-2)">${esc(evA.nombre)}</b>.` : ""}</div>
    ${filtroOn ? `<div class="hint" style="margin:-6px 0 12px;color:var(--accent-2)">
      Lista filtrada: sólo los que cargaron prepagadas en este evento.</div>` : ""}
    <div class="field"><input id="rpBuscar" placeholder="Buscar relacionador…" autocomplete="off"></div>
    <div id="rpResultados" class="hidden"></div>
    <div id="rpTeams">${teams.map(t => `
      <div class="lst-card ${rpSel === t ? "open" : ""}" data-rpt="${esc(t)}">
        <div class="lst-head">
          <span class="lst-nm">${esc(t)}</span>
          <span class="lst-cnt"><b>${byTeam[t].length}</b></span>
        </div>
        ${rpSel === t ? `<div class="lst-body">${byTeam[t].map(fila).join("")}</div>` : ""}
      </div>`).join("") || `<div class="empty">No hay relacionadores en la lista.</div>`}</div>`;

  document.querySelectorAll("#rpTeams .lst-head").forEach(h => h.onclick = () => {
    const t = h.parentElement.dataset.rpt;
    rpSel = rpSel === t ? null : t;
    screenRrppsPuerta();
  });
  const rb = $("#rpBuscar"), rres = $("#rpResultados"), rtm = $("#rpTeams");
  rb.oninput = () => {
    const q = nrm(rb.value.trim());
    if (q.length < 2) { rres.classList.add("hidden"); rtm.classList.remove("hidden"); return; }
    const hits = gente.filter(g => nrm(g.nombre + " " + g.usuario).includes(q)).slice(0, 30);
    rtm.classList.add("hidden"); rres.classList.remove("hidden");
    rres.innerHTML = hits.map(fila).join("")
      || `<div class="empty">Sin resultados para “${esc(rb.value.trim())}”.</div>`;
  };
}

/* ============================================================
   ESCÁNER QR (portero)
   ============================================================ */
let stream = null, scanTimer = null, torchOn = false, actx = null, scans = [], rechazoMode = false;
function beep(freq) {
  try {
    actx = actx || new (window.AudioContext || window.webkitAudioContext)();
    const o = actx.createOscillator(), g = actx.createGain();
    o.frequency.value = freq; o.connect(g); g.connect(actx.destination);
    g.gain.setValueAtTime(.15, actx.currentTime);
    g.gain.exponentialRampToValueAtTime(.001, actx.currentTime + .15);
    o.start(); o.stop(actx.currentTime + .16);
  } catch (e) { }
}
/* El pitido se puede apagar: adentro la música lo tapa y en la puerta a
   veces molesta. La vibración queda siempre, que es la señal que el
   portero sí percibe con el celular en la mano. */
let scanMudo = localStorage.getItem("scan-mudo") === "1";
function feedback(cls) {
  try { navigator.vibrate && navigator.vibrate(cls === "ok" ? 80 : [60, 60, 60]); } catch (e) { }
  if (!scanMudo) beep(cls === "ok" ? 880 : cls === "warn" ? 440 : 220);
  const f = $("#vfFlash");
  f.className = "vf-flash " + cls;
  setTimeout(() => { f.className = "vf-flash"; }, 550);
}
const RES_ICONS = {
  ok: '<path d="M5 12l5 5L20 7"/>',
  warn: '<path d="M12 9v4M12 17h.01M10.3 4.6L2.8 18a2 2 0 001.7 3h15a2 2 0 001.7-3L13.7 4.6a2 2 0 00-3.4 0z"/>',
  bad: '<path d="M6 6l12 12M18 6L6 18"/>'
};
async function validar(raw) {
  if (!ev) return toast("Elegí un evento", "warn");
  let code = (raw || "").trim();
  let esLista = false;
  const ml = code.match(/LST[:|]([\w-]+)[:|](\w+)/i);
  const m = code.match(/EVT[:|]([\w-]+)[:|](\w+)/i);
  if (ml) {
    if (ml[1] !== ev.id) { pintarRes("bad", { titulo: "Otro evento", nota: "Este QR es de otro evento o de otro boliche." }); feedback("bad"); return; }
    code = ml[2]; esLista = true;
  } else if (m) {
    if (m[1] !== ev.id) { pintarRes("bad", { titulo: "Otro evento", nota: "Este QR es de otro evento o de otro boliche." }); feedback("bad"); return; }
    code = m[2];
  }
  code = code.replace(/^#/, "").toUpperCase();
  if (!code) return;
  // modo filtro: rechaza sin consumir la entrada (se ve igual que una no válida).
  // Además registra en silencio la marca de filtro (queda el rrpp que la vendió).
  // Las entradas de la casa no se pueden filtrar: la base las devuelve como
  // "protegida" y en vez de rebotarlas seguimos derecho a validarlas.
  if (rechazoMode) {
    // se pregunta por los dos caminos: manilla QR y gente de lista. Antes solo
    // se miraba la manilla, y por eso los invitados de la casa rebotaban acá
    // sin llegar siquiera a validarse.
    const { data: mf } = await sb.rpc(esLista ? "marcar_filtro_lista" : "marcar_filtro_entrada",
      { p_evento: ev.id, p_code: code });
    let protegida = mf?.resultado === "protegida";
    if (!protegida) {
      pintarRes("bad", { titulo: "Código no válido", nota: `#${esc(code)} no existe para este evento.` });
      feedback("bad"); scans.unshift({ cls: "bad", code, nm: "—", t: hora(new Date().toISOString()) });
      $("#scanCode").value = ""; renderScanHist(); return;
    }
  }
  const { data: r, error } = await sb.rpc(esLista ? "validar_qr_lista" : "validar_entrada", { p_evento: ev.id, p_code: code });
  if (error) {
    // Validar exige consultar: sin señal no se puede saber si el QR es
    // legítimo, y dejar pasar a ciegas sería peor que esperar. Al menos
    // el portero entiende qué pasa en vez de ver un error técnico.
    if (esFallaDeRed(error)) {
      pintarRes("warn", {
        titulo: "Sin señal",
        nota: "No se puede verificar el QR ahora. Buscá a la persona por nombre en Lista, o probá de nuevo en unos segundos."
      });
      feedback("warn");
      $("#scanCode").value = "";
      return;
    }
    return fail(error);
  }
  if (r.resultado === "valida") {
    pintarRes("ok", {
      nombre: esc(r.cliente),
      titulo: r.lista ? esc(r.lista_nombre || "Lista")
        : r.mesa ? "Manilla de combo"
        : r.sin_tope ? "Entrada de la casa" : "Entrada prepagada",
      // Quién lo consiguió: información de apoyo, después del cliente.
      quien: [r.rrpp ? esc(r.rrpp) : null, r.team ? `Team ${esc(r.team)}` : null].filter(Boolean).join(" · "),
      // La hora queda a la vista: es lo que se consulta si vuelve a pasar.
      hora: `Ingresó a las ${hora(new Date().toISOString())}`,
      datos: [
        r.mesa ? `Mesa ${esc(r.mesa)}` : null,
        r.sin_tope ? "Sin tope de horario" : null
      ]
    }, esLista ? null : code);
    feedback("ok"); scans.unshift({ cls: "ok", code: r.code, nm: r.cliente, t: hora(new Date().toISOString()) });
  } else if (r.resultado === "usada") {
    pintarRes("warn", {
      nombre: esc(r.cliente),
      titulo: r.lista_nombre ? esc(r.lista_nombre) : r.mesa ? `Mesa ${esc(r.mesa)}` : "Entrada prepagada",
      quien: [r.rrpp ? esc(r.rrpp) : null, r.team ? `Team ${esc(r.team)}` : null].filter(Boolean).join(" · "),
      // La hora del ingreso anterior es el dato que resuelve la discusión.
      hora: `Ingresó a las ${hora(r.used_at)}`,
      nota: "Esta entrada ya fue usada. No vuelve a entrar."
    }, esLista ? null : code);
    feedback("warn"); scans.unshift({ cls: "warn", code: r.code, nm: r.cliente, t: hora(new Date().toISOString()) });
  } else if (r.resultado === "anulada") {
    pintarRes("bad", { nombre: esc(r.cliente), titulo: "Entrada anulada",
      nota: "El vendedor anuló esta entrada." });
    feedback("bad"); scans.unshift({ cls: "bad", code: r.code, nm: r.cliente, t: hora(new Date().toISOString()) });
  } else if (r.resultado === "fuera_hora") {
    pintarRes("bad", { nombre: esc(r.cliente), titulo: "Fuera de hora",
      nota: "El ingreso con QR ya cerró para este evento." });
    feedback("bad"); scans.unshift({ cls: "bad", code: r.code, nm: r.cliente, t: hora(new Date().toISOString()) });
  } else if (r.resultado === "fuera_horario") {
    pintarRes("bad", {
      nombre: esc(r.cliente),
      titulo: `${esc(r.lista_nombre || "Lista")} cerrada`,
      datos: [r.limite ? `Entraba hasta ${esc(r.limite)}` : null]
    });
    feedback("bad"); scans.unshift({ cls: "bad", code: r.code, nm: r.cliente, t: hora(new Date().toISOString()) });
  } else {
    pintarRes("bad", { titulo: "Código no válido", nota: `#${esc(code)} no existe para este evento.` });
    feedback("bad"); scans.unshift({ cls: "bad", code, nm: "—", t: hora(new Date().toISOString()) });
  }
  $("#scanCode").value = "";
  reenfocarCodigo();
  renderScanHist();
}
/* Resultado del escaneo.
 *
 * En la puerta no se lee: se mira. Por eso el veredicto (PASA / YA INGRESÓ /
 * NO PASA) va primero y grande, después el nombre, y recién al final los
 * datos sueltos como etiquetas. Antes todo venía en una frase corrida que
 * obligaba al portero a interpretar mientras la fila esperaba.
 *
 *   pintarRes(cls, big, sub, flagCode)          ← forma antigua, sigue andando
 *   pintarRes(cls, { titulo, nombre, datos[], nota }, flagCode)
 */
function pintarRes(cls, big, sub, flagCode) {
  // Compatibilidad: si llega el objeto nuevo, el 3er argumento es flagCode.
  const o = (big && typeof big === "object") ? big : { titulo: big, nota: sub };
  if (big && typeof big === "object") flagCode = sub;

  const VEREDICTO = { ok: "PASA", warn: "YA INGRESÓ", bad: "NO PASA" };
  const datos = (o.datos || []).filter(Boolean);

  $("#scanResult").innerHTML = `<div class="res ${cls} res-v2">
    <div class="res-top">
      <svg viewBox="0 0 24 24" class="ic res-ic">${RES_ICONS[cls]}</svg>
      <span class="res-vd">${VEREDICTO[cls] || ""}</span>
      ${flagCode ? `<button class="flagbtn" id="scanFlag" data-code="${esc(flagCode)}" title="Marcar: no pasó el control del boliche" aria-label="Marcar: no pasó el control del boliche">${ico("bandera")}</button>` : ""}
    </div>
    ${o.nombre ? `<div class="res-nm">${o.nombre}</div>` : ""}
    <div class="res-tp">${o.titulo || ""}</div>
    ${o.quien ? `<div class="res-quien">${o.quien}</div>` : ""}
    ${o.hora ? `<div class="res-hora">${o.hora}</div>` : ""}
    ${datos.length ? `<div class="res-datos">${datos.map(d => `<span class="res-dato">${d}</span>`).join("")}</div>` : ""}
    ${o.nota ? `<div class="res-nota">${o.nota}</div>` : ""}
  </div>`;
  window.Motion?.veredicto($("#scanResult").firstElementChild, cls);
  const fb = $("#scanFlag");
  if (fb) fb.onclick = async () => {
    const { data, error } = await sb.rpc("marcar_filtro_entrada", { p_evento: ev.id, p_code: fb.dataset.code });
    if (error) return fail(error);
    if (data.resultado !== "ok") return toast("No se encontró la entrada", "warn");
    fb.classList.toggle("on", data.marcado);
    toast(data.marcado ? `${data.nombre} marcado — lo vendió ${data.rrpp}` : `Marca quitada a ${data.nombre}`, data.marcado ? "warn" : "ok");
  };
}
async function renderScan() {
  if (!ev) { $("#vfHint").textContent = "No hay evento activo."; return; }
  renderScanHist();
}
let scanHistT = null;
function refrescarContadorScan() {
  clearTimeout(scanHistT);
  scanHistT = setTimeout(() => { if (tab === "escaner") renderScanHist(); }, 1200);
}
async function renderScanHist() {
  // una sola consulta: esto corre en cada escaneo de la puerta
  const { data: r } = await sb.rpc("resumen_evento", { p_evento: ev.id });
  const usadas = +r?.qr_usados || 0, total = +r?.qr_total || 0;
  $("#scanCount").textContent = `${usadas} ingresaron · ${Math.max(total - usadas, 0)} pendientes`;
  $("#scanHist").innerHTML = scans.slice(0, 30).map(s =>
    `<div class="list-row"><div class="r-l"><span class="st ${s.cls}"></span><span class="r-id">#${esc(s.code)}</span><span>${esc(s.nm)}</span></div>
     <span class="r-sub">${s.t}</span></div>`).join("") || `<div class="empty">Todavía no escaneaste entradas.</div>`;
}
async function startCam() {
  try {
    stream = await navigator.mediaDevices.getUserMedia({ video: { facingMode: "environment" } });
    const v = $("#cam"); v.srcObject = stream; v.classList.remove("hidden"); await v.play();
    $("#vfHint").textContent = "Buscando QR…"; $("#btnCam").textContent = "Detener cámara";
    const track = stream.getVideoTracks()[0];
    const caps = track.getCapabilities ? track.getCapabilities() : {};
    $("#btnTorch").classList.toggle("hidden", !caps.torch);
    let last = 0;
    const hit = raw => { if (Date.now() - last > 1800) { last = Date.now(); validar(raw); } };
    if ("BarcodeDetector" in window) {
      const det = new BarcodeDetector({ formats: ["qr_code"] });
      scanTimer = setInterval(async () => {
        try { const codes = await det.detect(v); if (codes.length) hit(codes[0].rawValue); } catch (e) { }
      }, 350);
    } else if (window.jsQR) {
      const cnv = document.createElement("canvas"), ctx = cnv.getContext("2d", { willReadFrequently: true });
      scanTimer = setInterval(() => {
        if (!v.videoWidth) return;
        const w = 320, h = Math.round(v.videoHeight * (320 / v.videoWidth));
        cnv.width = w; cnv.height = h;
        ctx.drawImage(v, 0, 0, w, h);
        const code = jsQR(ctx.getImageData(0, 0, w, h).data, w, h);
        if (code && code.data) hit(code.data);
      }, 350);
    }
  } catch (e) {
    $("#vfHint").textContent = "Cámara no disponible (requiere HTTPS y permiso) — usá el código manual.";
  }
}
function stopCam() {
  if (scanTimer) { clearInterval(scanTimer); scanTimer = null; }
  if (stream) { stream.getTracks().forEach(t => t.stop()); stream = null; }
  torchOn = false;
  const c = $("#cam"); if (c) c.classList.add("hidden");
  $("#btnTorch") && $("#btnTorch").classList.add("hidden");
  $("#btnCam") && ($("#btnCam").textContent = "Iniciar cámara");
}
$("#btnCam").onclick = () => stream ? stopCam() : startCam();
$("#btnTorch").onclick = async () => {
  if (!stream) return;
  try {
    torchOn = !torchOn;
    await stream.getVideoTracks()[0].applyConstraints({ advanced: [{ torch: torchOn }] });
  } catch (e) { }
};
$("#btnVal").onclick = () => validar($("#scanCode").value);
$("#scanCode").addEventListener("keydown", e => { if (e.key === "Enter") validar(e.target.value); });

/* Silenciar el pitido. La preferencia queda guardada: el portero lo
   configura una vez al empezar la noche, no en cada escaneo. */
$("#btnSonido") && (function () {
  const b = $("#btnSonido");
  const pintar = () => {
    b.innerHTML = ico(scanMudo ? "mudo" : "sonido");
    b.setAttribute("aria-pressed", String(scanMudo));
    b.title = scanMudo ? "Activar el pitido del escáner" : "Silenciar el pitido del escáner";
    b.classList.toggle("on", scanMudo);
  };
  pintar();
  b.onclick = () => {
    scanMudo = !scanMudo;
    localStorage.setItem("scan-mudo", scanMudo ? "1" : "0");
    pintar();
    toast(scanMudo ? "Pitido silenciado — la vibración sigue" : "Pitido activado");
  };
})();

/* Con lector físico o tecleando, el campo queda listo para el siguiente
   sin tener que volver a tocarlo. En móvil no: abriría el teclado encima
   de la cámara. */
function reenfocarCodigo() {
  if (window.matchMedia("(hover: none)").matches) return;
  const i = $("#scanCode");
  if (i && tab === "escaner") { i.value = ""; i.focus(); }
}
/* filtro de puerta: modo discreto de rechazo (el QR se ve como "no válida" sin consumir la entrada).
   Indicador mínimo: un puntito casi imperceptible; el botón queda igual que siempre. */
$("#btnFiltro") && ($("#btnFiltro").onclick = () => {
  rechazoMode = !rechazoMode;
  $("#btnFiltro").classList.toggle("filtro-on", rechazoMode);
});

/* Cómo se movió cada fase de preventa. Solo aparece si el evento vendió
   por fases — en un evento normal no tiene nada que mostrar.
   Se ve vendido e INGRESADO por separado a propósito: una tanda puede
   vender mucho y presentarse poco, y eso decide si el esquema se repite. */
async function pintarFases() {
  const box = $("#fasesBox"); if (!box) return;
  const { data: R, error } = await sb.rpc("reporte_fases", { p_evento: ev.id });
  if (error || !R || (!R.usa_fases && !(R.fases || []).length)) { box.innerHTML = ""; return; }
  const fs = R.fases || [];
  if (!fs.length) { box.innerHTML = ""; return; }
  const fila = (nom, f, extra) => `
    <div class="list-row rc" style="align-items:flex-start${f.agotada ? ";border-color:rgba(232,181,48,.35)" : ""}">
      <div class="r-l" style="flex:1;min-width:0"><span class="rc-body" style="width:100%">
        <span class="rc-nm">${esc(nom)}${extra || ""}</span>
        <span class="rc-sub"><span>${f.vendidas} vendidas · <b style="color:var(--ok)">${f.ingresaron} entraron</b>${f.conversion != null ? ` · ${f.conversion}% se presentó` : ""}</span></span>
        ${f.pct_bruto != null ? `<span style="display:block;height:5px;border-radius:99px;background:var(--surface-3);margin-top:7px;overflow:hidden">
          <span style="display:block;height:100%;width:${Math.max(2, Math.min(100, f.pct_bruto))}%;background:linear-gradient(90deg,var(--accent-2),var(--accent))"></span></span>` : ""}
      </span></div>
      <div style="text-align:right;flex-shrink:0;padding-left:10px">
        <span style="font-family:var(--display);font-size:15px">${fmtBs(f.bruto)}</span>
        <span style="display:block;font-size:10px;color:var(--text-3);font-weight:600">${f.pct_bruto != null ? f.pct_bruto + "% del bruto" : "Bs"}</span></div>
    </div>`;
  box.innerHTML = `
    <div class="sh-h" style="margin-top:18px;font-size:14px">Preventa por fases<span class="r-sub">${fmtBs(R.bruto_total)} Bs en total</span></div>
    ${fs.map(f => fila(f.nombre, f,
      ` <small style="color:var(--text-3);font-weight:600">${fmtBs(f.precio)} Bs</small>` +
      (f.agotada ? ` <span class="tkst" style="background:rgba(232,181,48,.16);color:#e8b530;font-size:10px">AGOTADA</span>` : "") +
      (f.cupo ? ` <small style="color:var(--text-3)">${f.vendidas}/${f.cupo}</small>` : ""))).join("")}
    ${R.sin_fase ? fila("Sin fase", R.sin_fase, ` <small style="color:var(--text-3)">antes de activar las fases</small>`) : ""}`;
}

/* Lo que el boliche debería cobrar esa noche: el 50 % de cada manilla que
   ingresó, más las mesas ya descontadas las comisiones de cada combo.
   Algunas manillas son de externos (prensa, invitados de afuera) y no entran
   en ese reparto — ese número se guarda en el evento, no se pierde al
   recargar ni hay que acordárselo cada vez. */
/* Lo que se le debe pagar al boliche:
 *
 *   prepagadas ingresadas × precio × 50%
 * + mesas brutas − comisiones
 * − ingresados de Compra en puerta × precio × 50%
 *
 * Los tres términos se calculan y se muestran acá, cada uno con la cuenta
 * de la que sale, para que el total se pueda verificar a ojo.
 *
 * Prepagadas ingresadas son las entradas en estado "usada": las vendidas
 * que no se presentaron no entran. Las mesas conservan su comisión actual
 * de la RPC. Compra en puerta se resta porque esa plata la cobró el
 * boliche en la puerta; sólo cuenta a quienes efectivamente ingresaron.
 *
 * "Manillas de externos" es otra cosa y sigue donde estaba: descuenta
 * manillas del reparto, no tiene nada que ver con Compra en puerta.
 */
async function pintarLiquidacion(prepagadas) {
  const box = $("#liqBox"); if (!box) return;
  const lp = listaPuertaDe(listaTipos);
  const [{ data: L, error }, pue] = await Promise.all([
    sb.rpc("liquidacion_evento", { p_evento: ev.id }),
    contarPuertaIngresada(lp)
  ]);
  if (error || !L) return;
  const pct = Math.round(PCT_BOLICHE_MANILLAS * 100);

  // Prepagadas: de lo que ya trae la pantalla, para que la cuenta mostrada
  // sea exactamente la que da el total.
  const preCant = +(prepagadas?.cant) || 0;
  const preBruto = +(prepagadas?.bruto) || 0;
  const preBoliche = preBruto * PCT_BOLICHE_MANILLAS;
  const preUnit = preCant > 0 ? Math.round(preBruto / preCant) : 0;

  // Mesas netas: bruto menos las comisiones que ya calcula la RPC.
  const mesaNeto = +L.total_mesas || 0;

  // Compra en puerta: sólo ingresados, sólo con precio cargado.
  const pueCant = +(pue.ingresaron) || 0, puePrecio = +(pue.precio) || 0;
  const pueDesc = pueCant * puePrecio * PCT_BOLICHE_MANILLAS;

  const total = preBoliche + mesaNeto - pueDesc;

  const cerrado = ev.estado === "cerrado";
  const sub = (ic, k, v, d, neg) => `
        <div class="rp-sub${neg ? " neg" : ""}">
          <span class="rp-sub-ic">${ico(ic)}</span>
          <div class="rp-sub-tx"><span class="rp-sub-k">${k}</span><span class="rp-sub-v">${v}</span><span class="rp-sub-s">${d}</span></div>
        </div>`;
  box.innerHTML = `
      <div class="rp-hero-h">
        <span class="rp-hero-ic">${ico("base")}</span>
        <div class="rp-hero-tx">
          <span class="rp-hero-k">Total a pagar al boliche</span>
          <span class="rp-hero-v">Bs ${fmtBs(total)}</span>
        </div>
        ${pillEst(cerrado ? "Cerrado" : "Pendiente de cierre", cerrado ? "ok" : "warn")}
      </div>
      <div class="rp-hero-grid">
        ${sub("ticket", `Prepagadas — ${pct}%`, `Bs ${fmtBs(preBoliche)}`,
          `${preCant} ingresaron${preUnit ? ` × ${fmtBs(preUnit)} Bs` : ""} × ${pct}%`)}
        ${sub("sofa", "Mesas netas", `Bs ${fmtBs(mesaNeto)}`,
          `${fmtBs(L.bruto_mesas)} − ${fmtBs(L.comision_mesas)} comisiones`)}
        ${pueDesc > 0 ? sub("bolsa", `Menos Compra en Puerta — ${pct}%`, `−Bs ${fmtBs(pueDesc)}`,
          `${pueCant} ingresaron × ${fmtBs(puePrecio)} Bs × ${pct}%`, true) : ""}
        ${sub("manilla", "Manillas externas", `${+L.manillas_externas || 0}`, "No se reparten")}
      </div>
      ${lp && pueCant > 0 && !pue.hayPrecio ? `<p class="rp-cierre-av">${pueCant} persona${pueCant === 1 ? "" : "s"} de
        <b>${esc(lp.nombre)}</b> ingres${pueCant === 1 ? "ó" : "aron"}, pero esa lista todavía no tiene precio
        cargado, así que no se descuenta nada. Se pone al editar la lista.</p>` : ""}`;
  const aj = $("#liqAj");
  if (aj) {
    aj.innerHTML = `
      <div class="rp-aj-h"><span class="rp-aj-ic">${ico("ajustes")}</span><h2 class="rp-aj-t">Ajustes del cierre</h2></div>
      <div class="field"><label for="liqExt">Manillas de externos (no se reparten)</label>
        <div class="num-step">
          <input id="liqExt" type="number" min="0" inputmode="numeric" value="${L.manillas_externas}">
          <span class="num-step-b">
            <button type="button" data-paso="1" aria-label="Sumar una">${ico("chevron", "rot180")}</button>
            <button type="button" data-paso="-1" aria-label="Restar una">${ico("chevron")}</button>
          </span>
        </div>
      </div>
      <p class="rp-aj-n">De las ${L.manillas_usadas} que ingresaron se descuentan ${L.manillas_externas}. Es otra cosa que Compra en Puerta: acá se sacan manillas del reparto. Queda guardado en el evento.</p>
      <div class="rp-aj-acc"><button class="btn ghost2" id="liqGo">Aplicar</button></div>`;
    qsa("#liqAj [data-paso]").forEach(b => b.onclick = () => {
      const i = $("#liqExt"); i.value = Math.max(0, (+i.value || 0) + +b.dataset.paso);
    });
  }
  $("#liqGo").onclick = async () => {
    const b = $("#liqGo"); b.disabled = true;
    const { error: e2 } = await sb.rpc("set_manillas_externas", {
      p_evento: ev.id, p_cant: +$("#liqExt").value || 0 });
    b.disabled = false;
    if (e2) return fail(e2);
    pintarLiquidacion(prepagadas);
  };
}

/* Cuántos de Compra en puerta ingresaron y a qué precio. Sólo lee: no crea
   pagos ni entradas. Si la columna de precio todavía no existe en la base,
   devuelve el conteo sin precio y el cierre no descuenta nada. */
async function contarPuertaIngresada(lp) {
  const vacio = { ingresaron: 0, precio: 0, hayPrecio: false };
  if (!lp) return vacio;
  let precio = 0, hayPrecio = false;
  if (PRECIO_PUERTA_OK) {
    const { data, error } = await sb.from("lista_tipos").select("precio").eq("id", lp.id).single();
    if (error) { if (sinColumnaPrecio(error)) PRECIO_PUERTA_OK = false; }
    else if (data && data.precio != null) { precio = +data.precio || 0; hayPrecio = precio > 0; }
  }
  const { count, error: e2 } = await sb.from("registros")
    .select("id", { count: "exact", head: true })
    .eq("evento_id", ev.id).eq("lista_tipo_id", lp.id)
    .not("ingreso_at", "is", null);          // sólo los que efectivamente entraron
  if (e2) return vacio;
  return { ingresaron: +count || 0, precio, hayPrecio };
}

/* ============================================================
   STATS (rrpp propias · jefe team · admin global)
   ============================================================ */
async function screenStats() {
  const [{ data: rows, error }, { data: mrows }, { data: bonos }, { data: mesasAll }, { data: entRows }, { data: regsAll }] = await conDatos("reporte", () => Promise.all([
    sb.from("v_stats_rrpp").select("*").eq("evento_id", ev.id),
    sb.from("v_stats_mesas").select("*").eq("evento_id", ev.id),
    sb.from("bonos").select("*, p:profiles!bonos_user_id_fkey(nombre)").eq("evento_id", ev.id),
    sb.from("mesas").select("precio, combo_qty, c:combos(comision_rrpp,comision_jefe)").eq("evento_id", ev.id).neq("estado", "disponible"),
    // total real de entradas prepagadas (incluye las vendidas por admins, que v_stats_rrpp no cuenta)
    traerTodo(() => sb.from("entradas").select("precio, estado").eq("evento_id", ev.id).is("mesa_id", null).order("id")),
    // total real de anotados en listas (incluye lo que meten jefes y admins).
    // Trae también la lista para el desglose de abajo: antes se pedía dos veces.
    traerTodo(() => sb.from("registros").select("ingreso_at, lista_tipo_id").eq("evento_id", ev.id).order("id"))
  ]));
  if (error) throw error;   // lo muestra conPantalla con Reintentar
  const regTot = (regsAll || []).reduce((a, r) => ({ an: a.an + 1, in: a.in + (r.ingreso_at ? 1 : 0) }), { an: 0, in: 0 });
  const entTot = (entRows || []).reduce((a, e) => ({
    vend: a.vend + (e.estado !== "anulada" ? 1 : 0),
    usad: a.usad + (e.estado === "usada" ? 1 : 0),
    bruto: a.bruto + (e.estado === "usada" ? (+e.precio || 0) : 0)
  }), { vend: 0, usad: 0, bruto: 0 });
  // comisión de mesas real = fija del combo × cantidad (indep. de quién la vendió)
  const mesasTot = (mesasAll || []).reduce((a, m) => {
    const q = m.combo_qty || 1;
    return { n: a.n + 1, bs: a.bs + (+m.precio || 0),
      comR: a.comR + (+m.c?.comision_rrpp || 0) * q, comJ: a.comJ + (+m.c?.comision_jefe || 0) * q };
  }, { n: 0, bs: 0, comR: 0, comJ: 0 });
  const mesasBy = {}; (mrows || []).forEach(m => mesasBy[m.rrpp_id] = m);
  const bonosBy = {}; (bonos || []).forEach(b => bonosBy[b.user_id] = (bonosBy[b.user_id] || 0) + +b.monto);
  // desglose CA/CE por lista (admin)
  let porLista = [];
  if (me.rol === "admin") {
    const g = {};   // se arma con los registros que ya vinieron arriba
    (regsAll || []).forEach(r => { const o = g[r.lista_tipo_id] = g[r.lista_tipo_id] || { ca: 0, ce: 0 }; o.ca++; if (r.ingreso_at) o.ce++; });
    porLista = listaTipos.map(l => ({ nombre: l.nombre, ...(g[l.id] || { ca: 0, ce: 0 }) })).filter(l => l.ca);
  }
  const all = rows.map(r => {
    const m = mesasBy[r.rrpp_id] || {};
    return {
      ...r, mv: +(m.mesas_vendidas || 0), bm: +(m.bruto_mesas || 0),
      cm_r: +(m.comision_rrpp_mesas || 0), cm_j: +(m.comision_jefe_mesas || 0),
      bono: bonosBy[r.rrpp_id] || 0
    };
  });
  const visibles = all.filter(r => r.anotados > 0 || r.entradas_vendidas > 0 || r.mv > 0 || r.bono > 0);
  /* loadTeams sigue: llena teamsCache, que usan otras pantallas y el ⋯.
     La lista de teams presentes se fue con el filtro de "Por relacionador". */
  if (me.rol === "admin") await loadTeams();
  const tot = visibles.reduce((a, r) => ({
    an: a.an + +r.anotados, in: a.in + +r.ingresaron,
    ev_: a.ev_ + +r.entradas_vendidas, eu: a.eu + +r.entradas_usadas,
    br: a.br + +r.bruto_entradas, cr: a.cr + +r.comision_rrpp, cj: a.cj + +r.comision_jefe,
    mv: a.mv + r.mv, bm: a.bm + r.bm, cmr: a.cmr + r.cm_r, cmj: a.cmj + r.cm_j, bono: a.bono + r.bono
  }), { an: 0, in: 0, ev_: 0, eu: 0, br: 0, cr: 0, cj: 0, mv: 0, bm: 0, cmr: 0, cmj: 0, bono: 0 });
  /* boliche = residuo: bruto − comisiones reales (cut_rel editable por persona)
     Bruto usa el total REAL de entradas (incluye las vendidas por admins, sin comisión).
     Mesas: se resta la comisión fija del combo (venda quien venda), no la del vendedor.

     PENDIENTE · dos criterios conviven para el mismo concepto:
       - acá: bruto de entradas − comisiones reales de cada RRPP − bonos
       - Inicio (resultadoBoliche): 50% de las manillas ingresadas + mesas netas
     Los números pueden no coincidir. Queda por decidir cuál rige y unificar
     los dos lugares en una sola función. */
  const bolicheEnt = entTot.bruto - tot.cr - tot.cj;
  const comTotal = tot.cr + tot.cj + mesasTot.comR + mesasTot.comJ + tot.bono;
  const neto = bolicheEnt + mesasTot.bs - mesasTot.comR - mesasTot.comJ - tot.bono;
  const title = me.rol === "admin" ? "Cierre del evento" : me.rol === "jefe" ? "Stats de mi team" : "Mis stats";
  const esAdm = me.rol === "admin";
  const excel = puedeVerExcelContable() ? `<button class="btn ghost2" id="btnExcel">${ico("archivo")}${me.rol === "jefe" && me.contabilidad_total !== true
        ? "Exportar contabilidad de mi team" : "Exportar contabilidad Excel"}</button>` : "";
  $("#main").innerHTML = `
    ${pgHead({ ey: esAdm ? "Reporte" : "Stats", t: title, s: `${esc(ev.nombre)} · ${fmtF(ev.fecha)}` })}
    ${esAdm ? `<div class="rp-top">
      <section class="rp-hero" id="liqBox"><div class="sk sk-l1"></div></section>
      <aside class="rp-aj" id="liqAj"></aside>
    </div>` : ""}
    <div class="kps">
      ${kpi({ ic: "grupo", k: "Ingresaron de lista", v: regTot.in, de: regTot.an })}
      ${kpi({ ic: "ticket", k: "Entradas ingresadas", v: entTot.usad, de: entTot.vend })}
      ${esAdm ? kpi({ ic: "sofa", k: "Mesas vendidas", v: mesasTot.n }) : ""}
      ${me.rol === "rrpp" ? kpi({ ic: "sofa", k: "Mis mesas", v: tot.mv, s: `Bs ${fmtBs(tot.bm)}` })
        + kpi({ ic: "base", k: "Mi comisión total", v: `Bs ${fmtBs(tot.cr + tot.cmr + tot.bono)}`, s: "Entradas + mesas + bonos", tono: "ok" }) : ""}
      ${me.rol === "jefe" ? kpi({ ic: "grupo", k: "Comisión RRPPs", v: `Bs ${fmtBs(tot.cr + tot.cmr)}` })
        + kpi({ ic: "base", k: "Mi comisión (jefe)", v: `Bs ${fmtBs(tot.cj + tot.cmj)}`, tono: "ok" }) : ""}
    </div>
    ${esAdm && porLista.length ? `<div class="rp-bloque">
      <div class="rp-bloque-h"><span class="rp-bloque-t">Por lista</span>
        <span class="rp-bloque-s">entraron / anotados</span></div>
      <div class="rp-listas">${porLista.map(l => `
        <span class="rp-lp"><span class="rp-lp-n">${esc(l.nombre)}</span>
          <span class="rp-lp-v"><b>${l.ce}</b>/${l.ca}</span></span>`).join("")}</div>
    </div>` : ""}
    ${esAdm ? `<div id="fasesBox"></div>` : ""}
    ${["rrpp", "jefe"].includes(me.rol) ? `<div class="pg-fila-acc">
      ${me.rol === "rrpp" ? `<button class="btn ghost2" id="btnMisNombres">${ico("usuario")}Ver mis nombres</button>` : ""}
      <button class="btn ghost2" id="btnHistStats">${ico("reloj")}Eventos pasados</button>
    </div>` : ""}
    ${esAdm ? `
    <details class="rp-det">
      <summary class="rp-det-s">${ico("chevron", "rp-det-ch")}<span>Ver desglose por comisiones</span>${ico("chevron", "rp-det-ch2")}</summary>
      <div class="rp-det-b">
        <p class="rp-det-n">Otra forma de leer la misma noche: el bruto menos lo que se lleva
          cada relacionador. Es un control interno — la cifra que se paga es la de arriba.</p>
        <div class="rp-dl">
          <div class="rp-d"><span class="rp-d-k">Bruto entradas</span><span class="rp-d-v">${fmtBs(entTot.bruto)} Bs</span></div>
          <div class="rp-d"><span class="rp-d-k">Bruto mesas</span><span class="rp-d-v">${fmtBs(mesasTot.bs)} Bs</span></div>
          <div class="rp-d"><span class="rp-d-k">Comisiones + bonos</span><span class="rp-d-v rp-d-neg">− ${fmtBs(comTotal)} Bs</span></div>
          <div class="rp-d rp-d-tot"><span class="rp-d-k">Neto por comisiones</span><span class="rp-d-v">${fmtBs(neto)} Bs</span></div>
        </div>
      </div>
    </details>
    <div class="rp-acc">
      <button class="btn primary" id="btnCopiar">${ico("copiar")}Copiar cierre</button>
      ${excel}
      <button class="ghost rp-mas" id="rpMas" aria-label="Más acciones">${ico("puntos")}</button>
    </div>` : excel ? `<div class="rp-acc">${excel}</div>` : ""}`;
  /* La lista "Por relacionador" salió de esta pantalla (pedido del dueño):
     con ella se fueron su filtro por team, su buscador y el click que abría
     el detalle. El desglose nombre por nombre sigue disponible desde
     "Mi team" (sheetHistTeam) y desde el Excel contable. */
  const bmn = $("#btnMisNombres"); if (bmn) bmn.onclick = () => sheetRrppDetalle(me.id, me.nombre);
  const bhs = $("#btnHistStats"); if (bhs) bhs.onclick = sheetHistorialRrpp;
  if (me.rol === "admin") { pintarLiquidacion({ cant: entTot.usad, bruto: entTot.bruto }); pintarFases(); }
  /* Las secundarias van detrás del ⋯: se usan una vez, no en la mesa de
     cierre. Ninguna desaparece, sólo dejan de competir con Copiar cierre. */
  const bmas = $("#rpMas");
  if (bmas) bmas.onclick = () => {
    const op = [
      ["comis", "Comisiones", IC.tag],
      ["bonos", "Bonos", IC.star],
      ["hist", "Histórico", IC.clock],
      ["usuarios", "Usuarios y teams", IC.people],
      ["audit", "Auditoría", IC.shield],
    ];
    sheet(`<div class="sh-h">Reporte<span class="r-sub">${esc(ev.nombre)}</span></div>
      <div class="mas-lista">${op.map(([k, l, ico]) =>
        `<button class="mas-op" data-rpop="${k}">${ico}<span>${esc(l)}</span></button>`).join("")}</div>`);
    document.querySelectorAll("#sheetBody [data-rpop]").forEach(b => b.onclick = () => {
      const k = b.dataset.rpop;
      if (k === "comis") return sheetComisiones();
      if (k === "bonos") return sheetBonos();
      if (k === "hist") return sheetHistorico("mes");
      if (k === "usuarios") return sheetUsuarios();
      if (k === "audit") return sheetAuditoria();
    });
  };
  /* Exportación contable a Excel · SOLO la cuenta protegida
     (admin_principal). El botón ni se pinta para los demás, y
     exportarContabilidadExcel() vuelve a chequear por si la llaman suelta.

     El módulo puede no estar cargado: el index del hosting es un archivo
     aparte que solo cambia con un redeploy de Vercel, mientras que app.js
     se actualiza re-corriendo deployar-prueba.mjs. Para que actualizar la
     app siga siendo UN solo paso, si falta se carga acá desde el mismo
     bucket que sirve este app.js. */
  const bx = $("#btnExcel");
  if (bx) bx.onclick = () => cargarContabilidad()
    .then(() => window.exportarContabilidadExcel())
    .catch(e => { console.error(e); toast(e.message || "No se pudo cargar el módulo contable", "warn"); });

  const bc = $("#btnCopiar");
  if (bc) bc.onclick = async () => {
    const porRel = visibles.sort((a, b) => (b.entradas_usadas + b.mv) - (a.entradas_usadas + a.mv))
      .map(r => `• ${r.rrpp}: ${r.ingresaron}/${r.anotados} lista · ${r.entradas_usadas} QR · ${r.mv} mesas · a pagar ${fmtBs(+r.comision_rrpp + +r.comision_jefe + r.cm_r + r.cm_j + r.bono)} Bs`).join("\n");
    const txt = `🍾 CIERRE ${ev.nombre.toUpperCase()} — ${clubNombre(club)} · ${fmtF(ev.fecha)}\n\n` +
      `💰 Para el boliche: ${fmtBs(neto)} Bs\n` +
      `Bruto entradas: ${fmtBs(entTot.bruto)} Bs (${entTot.usad} ingresaron de ${entTot.vend} vendidas)\n` +
      `Bruto mesas: ${fmtBs(mesasTot.bs)} Bs (${mesasTot.n} mesas)\n` +
      `Comisiones + bonos: ${fmtBs(comTotal)} Bs\n` +
      `Listas: ${regTot.in}/${regTot.an} ingresaron\n\nPor relacionador:\n${porRel}`;
    try { await navigator.clipboard.writeText(txt); }
    catch (e) {
      const ta = document.createElement("textarea"); ta.value = txt;
      document.body.appendChild(ta); ta.select();
      try { document.execCommand("copy"); } catch (e2) { } ta.remove();
    }
    toast("Cierre copiado — pegalo en WhatsApp");
  };
}

/* detalle de un relacionador en un evento: nombre por nombre (listas + entradas).
   evObj opcional para históricos (eventos pasados); por defecto el evento actual. */
async function sheetRrppDetalle(rrppId, nombre, evObj, onBack) {
  const e0 = evObj || ev;
  const [{ data: regs }, { data: ents }] = await Promise.all([
    sb.from("registros").select("nombre, ingreso_at, lt:lista_tipos(nombre)").eq("evento_id", e0.id).eq("rrpp_id", rrppId).order("ingreso_at", { ascending: false, nullsFirst: false }).limit(1000),
    sb.from("entradas").select("cliente, code, estado, mesa_id, used_at").eq("evento_id", e0.id).eq("rrpp_id", rrppId).neq("estado", "anulada").order("used_at", { ascending: false, nullsFirst: false }).limit(1000)
  ]);
  const nombreLista = r => r.lt?.nombre || "Lista";
  const rL = regs || [], eSueltas = (ents || []).filter(e => !e.mesa_id), eMesa = (ents || []).filter(e => e.mesa_id);
  const caL = rL.length, ceL = rL.filter(r => r.ingreso_at).length;
  const caE = eSueltas.length, ceE = eSueltas.filter(e => e.estado === "usada").length;
  const fila = (nm, sub, ingreso) => `
    <div class="list-row">
      <div class="r-l" style="min-width:0"><span>${esc(nm)}<br><small style="color:var(--text-3)">${esc(sub)}</small></span></div>
      ${ingreso ? `<span class="ce-time">${hora(ingreso)}</span><span class="cebox on">✓</span>` : `<span class="tkst" style="background:var(--surface-3);color:var(--text-3);font-size:11px">sin ingresar</span>`}
    </div>`;
  sheet(`
    <button class="btn ghost2" style="width:auto;padding:8px 14px;margin-bottom:12px" id="rdBack">${ico("atras")}Volver</button>
    <div class="sh-h">${esc(nombre)}<span class="r-sub">${esc(e0.nombre)}${e0.fecha ? " · " + fmtF(e0.fecha) : ""}</span></div>
    <div class="stats" style="grid-template-columns:1fr 1fr;padding:0 0 14px">
      <div class="stat"><span class="k">Lista (entraron / anotó)</span><span class="v"><span class="ok">${ceL}</span>/${caL}</span></div>
      <div class="stat"><span class="k">Entradas QR (entraron / vendió)</span><span class="v"><span class="ok">${ceE}</span>/${caE}</span></div>
    </div>
    ${caE ? `<div class="sh-h" style="margin-top:6px">Entradas prepagadas (${caE})</div>
      <div>${eSueltas.map(e => fila(e.cliente, "#" + e.code, e.estado === "usada" ? e.used_at : null)).join("")}</div>` : ""}
    ${eMesa.length ? `<div class="sh-h" style="margin-top:12px">Manillas de mesa (${eMesa.length})</div>
      <div>${eMesa.map(e => fila(e.cliente, "#" + e.code, e.estado === "usada" ? e.used_at : null)).join("")}</div>` : ""}
    ${caL ? `<div class="sh-h" style="margin-top:12px">En listas (${caL})</div>
      <div>${rL.map(r => fila(r.nombre, nombreLista(r), r.ingreso_at)).join("")}</div>` : ""}
    ${!caE && !caL && !eMesa.length ? `<div class="empty">Sin actividad de ${esc(nombre)} en este evento.</div>` : ""}`);
  const rb = $("#rdBack"); if (rb) rb.onclick = onBack || closeSheet;
}

/* historial de eventos pasados para rrpp/jefe: entrar y ver su data por evento */
async function sheetHistorialRrpp() {
  const { data: evs } = await sb.from("eventos").select("id,nombre,fecha,estado")
    .eq("club_id", club).order("fecha", { ascending: false }).limit(60);
  const pasados = (evs || []).filter(e => e.estado === "cerrado" || e.fecha < new Date().toLocaleDateString("sv-SE"));
  sheet(`
    <div class="sh-h">Historial · ${clubNombre(club)}</div>
    <div class="hint" style="margin:0 0 12px">Tocá un evento pasado para ver tu data (listas y entradas) de esa noche.</div>
    <div>${pasados.map(e => `
      <div class="list-row" data-hev="${e.id}" data-hnom="${esc(e.nombre)}" data-hfecha="${e.fecha || ""}" style="cursor:pointer">
        <div class="r-l"><span class="r-id">${fmtF(e.fecha)}</span><span>${esc(e.nombre)}</span></div>
        <span class="r-sub">${e.estado === "cerrado" ? "cerrado" : "pasado"} ›</span>
      </div>`).join("") || `<div class="empty">Todavía no hay eventos pasados.</div>`}</div>`);
  document.querySelectorAll("#sheetBody [data-hev]").forEach(row => row.onclick = () => {
    const evObj = { id: row.dataset.hev, nombre: row.dataset.hnom, fecha: row.dataset.hfecha };
    if (me.rol === "jefe") sheetHistTeam(evObj);          // jefe: desglose de su team
    else sheetRrppDetalle(me.id, me.nombre, evObj);       // rrpp: su detalle nombre por nombre
  });
}

/* historial de un jefe: stats de su team en un evento pasado, con drilldown por rrpp */
async function sheetHistTeam(evObj) {
  const [{ data: rows }, { data: mrows }] = await Promise.all([
    sb.from("v_stats_rrpp").select("*").eq("evento_id", evObj.id),
    sb.from("v_stats_mesas").select("*").eq("evento_id", evObj.id)
  ]);
  const mesasBy = {}; (mrows || []).forEach(m => mesasBy[m.rrpp_id] = m);
  const all = (rows || []).map(r => {
    const m = mesasBy[r.rrpp_id] || {};
    return { ...r, mv: +(m.mesas_vendidas || 0), cm_r: +(m.comision_rrpp_mesas || 0), cm_j: +(m.comision_jefe_mesas || 0) };
  });
  const visibles = all.filter(r => +r.anotados > 0 || +r.entradas_vendidas > 0 || r.mv > 0)
    .sort((a, b) => (+b.entradas_usadas + b.mv) - (+a.entradas_usadas + a.mv));
  const tot = visibles.reduce((a, r) => ({
    an: a.an + +r.anotados, in: a.in + +r.ingresaron, ev_: a.ev_ + +r.entradas_vendidas, eu: a.eu + +r.entradas_usadas,
    cr: a.cr + +r.comision_rrpp + r.cm_r, cj: a.cj + +r.comision_jefe + r.cm_j, mv: a.mv + r.mv
  }), { an: 0, in: 0, ev_: 0, eu: 0, cr: 0, cj: 0, mv: 0 });
  sheet(`
    <button class="btn ghost2" style="width:auto;padding:8px 14px;margin-bottom:12px" id="htBack">${ico("atras")}Volver</button>
    <div class="sh-h">Mi team<span class="r-sub">${esc(evObj.nombre)}${evObj.fecha ? " · " + fmtF(evObj.fecha) : ""}</span></div>
    <div class="stats" style="grid-template-columns:1fr 1fr;padding:0 0 14px">
      <div class="stat"><span class="k">Anotados en listas</span><span class="v">${tot.an}</span></div>
      <div class="stat"><span class="k">Ingresaron de lista</span><span class="v ok">${tot.in}</span></div>
      <div class="stat"><span class="k">Entradas vendidas</span><span class="v">${tot.ev_}</span></div>
      <div class="stat"><span class="k">Entradas ingresadas</span><span class="v ok">${tot.eu}</span></div>
      <div class="stat"><span class="k">Mesas vendidas</span><span class="v">${tot.mv}</span></div>
      <div class="stat"><span class="k">Comisión RRPPs</span><span class="v">${fmtBs(tot.cr)} Bs</span></div>
      <div class="stat" style="grid-column:1/-1"><span class="k">Mi comisión (jefe)</span><span class="v ok">${fmtBs(tot.cj)} Bs</span></div>
    </div>
    <div class="sh-h">Por relacionador <span class="r-sub">tocá para ver nombre por nombre</span></div>
    <div>${visibles.map(r => `
      <div class="list-row" data-rrpp="${r.rrpp_id}" data-nom="${esc(r.rrpp)}" style="cursor:pointer">
        <div class="r-l"><span class="relmark">${esc(r.rrpp[0])}</span><span>${esc(r.rrpp)}</span></div>
        <span class="r-sub">${r.ingresaron}/${r.anotados} lista · ${r.entradas_usadas} QR · ${r.mv} mesas</span>
      </div>`).join("") || `<div class="empty">Tu team no tuvo actividad en este evento.</div>`}</div>`);
  $("#htBack").onclick = sheetHistorialRrpp;
  document.querySelectorAll("#sheetBody [data-rrpp]").forEach(row => row.onclick = () =>
    sheetRrppDetalle(row.dataset.rrpp, row.dataset.nom, evObj, () => sheetHistTeam(evObj)));
}

/* histórico + ranking (admin) */
async function sheetHistorico(rango) {
  const desde = rango === "mes"
    ? new Date(new Date().getFullYear(), new Date().getMonth(), 1).toISOString().slice(0, 10)
    : "2000-01-01";
  const [{ data: hist, error }, { data: rank }] = await Promise.all([
    sb.rpc("historico_eventos", { p_club: club }),
    sb.rpc("ranking_rrpp", { p_club: club, p_desde: desde })
  ]);
  if (error) return fail(error);
  const medal = i => `${i + 1}.`;
  sheet(`
    <div class="sh-h">Histórico · ${clubNombre(club)}</div>
    <div>${(hist || []).map(h => `
      <div class="list-row">
        <div class="r-l"><span class="r-id">${fmtF(h.fecha)}</span>
          <span>${esc(h.nombre)}<br><small style="color:var(--text-3)">${h.entradas_usadas}/${h.entradas_vendidas} QR · ${h.lista_in}/${h.lista_total} lista · ${h.mesas} mesas</small></span></div>
        <span class="r-sub" style="color:var(--ok);font-weight:600">${fmtBs(h.utilidad)} Bs</span>
      </div>`).join("") || `<div class="empty">Sin eventos.</div>`}
    </div>
    <div class="sh-h" style="margin-top:18px">Ranking RRPPs
      <span style="display:flex;gap:6px">
        <button class="checkin${rango === "mes" ? "" : ""}" id="rkMes" style="${rango === "mes" ? "" : "background:var(--surface-3);color:var(--text-2);border-color:var(--line-2)"}">Este mes</button>
        <button class="checkin" id="rkTodo" style="${rango === "todo" ? "" : "background:var(--surface-3);color:var(--text-2);border-color:var(--line-2)"}">Todo</button>
      </span>
    </div>
    <div>${(rank || []).map((r, i) => `
      <div class="list-row">
        <div class="r-l"><span style="width:26px;text-align:center;flex-shrink:0">${medal(i)}</span>
          <span>${esc(r.nombre)}<br><small style="color:var(--text-3)">${r.ingresados}/${r.anotados} lista · ${r.entradas} QR · ${r.mesas} mesas</small></span></div>
        <span class="r-sub" style="font-weight:600">${fmtBs(r.comision)} Bs</span>
      </div>`).join("") || `<div class="empty">Sin actividad en el período.</div>`}
    </div>`);
  $("#rkMes").onclick = () => sheetHistorico("mes");
  $("#rkTodo").onclick = () => sheetHistorico("todo");
}

/* comisiones por team con cut editable por relacionador (admin)
   boliche = precio − cutJefe − cutRel: si sube el cut de un rel, baja lo del boliche */
let comisTeamOpen = null;
async function sheetComisiones() {
  const [{ data: rows, error }, { data: gente }] = await Promise.all([
    sb.from("v_stats_rrpp").select("*").eq("evento_id", ev.id),
    sb.from("profiles").select("id,nombre,rol,team_id,cut_rel").in("rol", ["rrpp", "jefe", "admin"]).eq("activo", true)
  ]);
  if (error) return fail(error);
  await loadTeams();
  const cutDef = ev.cut_rrpp != null ? +ev.cut_rrpp
    : ev.precio_manilla * (1 - ev.pct_boliche / 100) * (ev.pct_rrpp / 100);
  const cutJefe = ev.precio_manilla * (1 - ev.pct_boliche / 100) * (1 - ev.pct_rrpp / 100);
  const byId = {}; (gente || []).forEach(g => byId[g.id] = g);
  let totGeneral = 0;
  const cards = teamsCache.map(t => {
    const tRows = rows.filter(r => r.team_id === t.id);
    if (!tRows.length) return "";
    const man = tRows.reduce((a, r) => a + +r.entradas_usadas, 0);
    const comRel = tRows.reduce((a, r) => a + +r.comision_rrpp, 0);
    const comJefe = tRows.reduce((a, r) => a + +r.comision_jefe, 0);
    const jefeRow = tRows.find(r => byId[r.rrpp_id]?.rol === "jefe");
    const jefeNombre = byId[t.jefe_id]?.nombre || (jefeRow ? byId[jefeRow.rrpp_id].nombre : "—");
    totGeneral += comRel + comJefe;
    const open = comisTeamOpen === t.id;
    return `<div class="lst-card ${open ? "open" : ""}" data-tm="${t.id}">
      <div class="lst-head">
        <span class="lst-nm">${esc(t.nombre)}</span>
        <span class="lst-cnt"><b>${man}</b> manillas</span>
        <span class="lst-cnt ok"><b>${fmtBs(comRel + comJefe)}</b> Bs a pagar</span>
      </div>
      ${open ? `<div class="lst-body">
        <div class="list-row" style="background:var(--surface-3);border-radius:10px;padding:9px 12px;margin-bottom:6px">
          <div class="r-l"><span class="relmark" style="background:var(--warn)">${esc(jefeNombre[0])}</span>
            <span>Jefe: ${esc(jefeNombre)}<br><small style="color:var(--text-3)">${fmtBs(cutJefe)} Bs × manilla del team</small></span></div>
          <span class="r-sub" style="font-weight:600;color:var(--ok)">${fmtBs(comJefe)} Bs</span>
        </div>
        ${tRows.filter(r => byId[r.rrpp_id]?.rol === "rrpp").sort((a, b) => b.entradas_usadas - a.entradas_usadas).map(r => {
          const g = byId[r.rrpp_id];
          return `<div class="list-row com-row">
            <div class="r-l"><span class="relmark">${esc(r.rrpp[0])}</span>
              <span>${esc(r.rrpp)}<br><small style="color:var(--text-3)">${r.entradas_usadas} manillas · ${fmtBs(r.comision_rrpp)} Bs</small></span></div>
            <input type="number" data-cut="${r.rrpp_id}" value="${g?.cut_rel ?? ""}" placeholder="${cutDef}" title="Bs por manilla — vacío = ${cutDef}">
          </div>`;
        }).join("")}
      </div>` : ""}
    </div>`;
  }).join("");
  sheet(`
    <div class="sh-h">Comisiones · ${esc(ev.nombre)}</div>
    <div class="hint" style="margin:0 0 12px">Tocá un team para editar los Bs por manilla de cada relacionador (vacío = ${fmtBs(cutDef)} Bs). Lo del boliche se ajusta solo: precio − jefe − relacionador. Se paga solo sobre ingresados (CE).</div>
    ${cards || `<div class="empty">Sin actividad por teams todavía.</div>`}
    <div class="com-total">Total comisiones a pagar: ${fmtBs(totGeneral)} Bs</div>`);
  document.querySelectorAll("#sheetBody .lst-head").forEach(h => h.onclick = () => {
    const id = h.parentElement.dataset.tm;
    comisTeamOpen = comisTeamOpen === id ? null : id;
    sheetComisiones();
  });
  document.querySelectorAll("#sheetBody [data-cut]").forEach(inp => inp.onchange = async () => {
    const v = inp.value.trim();
    const cut = v === "" ? null : +v;
    if (cut !== null && (isNaN(cut) || cut < 0 || cut > ev.precio_manilla)) return toast(`Entre 0 y ${ev.precio_manilla}`, "warn");
    const { error: e2 } = await sb.from("profiles").update({ cut_rel: cut }).eq("id", inp.dataset.cut);
    if (e2) return fail(e2);
    toast("Comisión actualizada");
    sheetComisiones();
  });
}

/* bonos (admin) */
async function sheetBonos() {
  const [{ data: gente }, { data: bonos }] = await Promise.all([
    sb.from("profiles").select("id,nombre,rol").in("rol", ["rrpp", "jefe"]).eq("activo", true).order("nombre"),
    sb.from("bonos").select("*, p:profiles!bonos_user_id_fkey(nombre)").eq("evento_id", ev.id).order("created_at", { ascending: false })
  ]);
  sheet(`
    <div class="sh-h">Bonos · ${esc(ev.nombre)}</div>
    <div class="field"><label>Persona</label><select id="boU">${(gente || []).map(g =>
      `<option value="${g.id}">${esc(g.nombre)} (${g.rol})</option>`).join("")}</select></div>
    <div class="row2">
      <div class="field"><label>Monto Bs</label><input id="boM" type="number"></div>
      <div class="field"><label>Motivo</label><input id="boMot" placeholder="Meta de ventas"></div>
    </div>
    <button class="btn primary" id="boGo">Dar bono</button>
    <div class="sh-h" style="margin-top:16px">Del evento</div>
    <div>${(bonos || []).map(b => `
      <div class="list-row"><div class="r-l"><span>${esc(b.p?.nombre)}</span></div>
      <span class="r-sub">${fmtBs(b.monto)} Bs${b.motivo ? " · " + esc(b.motivo) : ""}</span></div>`).join("") || `<div class="empty">Sin bonos.</div>`}
    </div>`);
  $("#boGo").onclick = async () => {
    const monto = +$("#boM").value;
    if (!monto) return toast("Monto", "warn");
    const { error } = await sb.from("bonos").insert({ evento_id: ev.id, user_id: $("#boU").value, monto, motivo: $("#boMot").value.trim() || null });
    if (error) return fail(error);
    toast("Bono registrado"); sheetBonos();
  };
}

/* WhatsApp del equipo (admin): quién cargó su número y quién no.
   El admin puede cargarlo por alguien que no lo hizo, y copiar la lista
   entera para pegarla donde la necesite. */
const telLindo = t => !t ? "" : t.startsWith("591") && t.length === 11
  ? "+591 " + t.slice(3, 4) + " " + t.slice(4, 7) + " " + t.slice(7)
  : "+" + t;
async function sheetTelefonos() {
  const { data, error } = await sb.rpc("telefonos_equipo", { p_club: club });
  if (error) return fail(error);
  const gente = (data || []).filter(g => g.activo !== false);
  const con = gente.filter(g => g.telefono), sin = gente.filter(g => !g.telefono);
  const fila = g => `
    <div class="list-row rc">
      <div class="r-l" style="min-width:0"><span class="relmark">${esc((g.nombre || "?")[0])}</span>
        <span class="rc-body"><span class="rc-nm">${esc(g.nombre)}</span>
        <span class="rc-sub"><span>${ROL_LABEL[g.rol] || g.rol}${g.team ? " · " + esc(g.team) : ""}</span></span></span></div>
      ${g.telefono
        ? `<div style="display:flex;gap:5px;flex-shrink:0;align-items:center">
             <a class="checkin" style="text-decoration:none" href="https://wa.me/${g.telefono}" target="_blank" rel="noopener">${esc(telLindo(g.telefono))}</a>
             <button class="checkin" style="background:var(--surface-3);color:var(--text-2);border-color:var(--line-2)" data-tel-ed="${g.user_id}" data-tel-nom="${esc(g.nombre)}" data-tel-val="${g.telefono}">Editar</button>
           </div>`
        : `<button class="checkin" style="background:var(--warn-bg,var(--surface-3));color:var(--warn)" data-tel-ed="${g.user_id}" data-tel-nom="${esc(g.nombre)}" data-tel-val="">Cargar</button>`}
    </div>`;
  sheet(`
    <button class="btn ghost2" style="width:auto;padding:8px 14px;margin-bottom:12px" id="telBack">${ico("atras")}Volver</button>
    <div class="sh-h">WhatsApp del equipo<span class="r-sub">${con.length} de ${gente.length} cargados</span></div>
    <div class="stats" style="grid-template-columns:1fr 1fr;padding:0 0 12px">
      <div class="stat st-ok"><span class="k">Ya lo cargaron</span><span class="v ok">${con.length}</span></div>
      <div class="stat"><span class="k">Faltan</span><span class="v" style="color:var(--warn)">${sin.length}</span></div>
    </div>
    <div class="hint" style="margin:0 0 12px">A cada uno le aparece el pedido cuando entra a la app. Si alguno no lo carga, pedíselo y anotalo vos acá.</div>
    <div class="row2">
      <div class="field" style="display:flex"><button class="btn ghost2" id="telCopy" style="padding:12px">Copiar los ${con.length} números</button></div>
      <div class="field" style="display:flex"><button class="btn ghost2" id="telCopyFalta" style="padding:12px">Copiar quiénes faltan</button></div>
    </div>
    ${sin.length ? `<div class="sh-h" style="margin-top:8px">Faltan (${sin.length})</div><div>${sin.map(fila).join("")}</div>` : ""}
    ${con.length ? `<div class="sh-h" style="margin-top:14px">Cargados (${con.length})</div><div>${con.map(fila).join("")}</div>` : ""}
    ${!gente.length ? `<div class="empty">No hay gente en este boliche.</div>` : ""}`);
  $("#telBack").onclick = () => sheetUsuarios();
  $("#telCopy").onclick = () => {
    if (!con.length) return toast("Todavía no cargó nadie", "warn");
    copyText(con.map(g => `${g.nombre} - ${telLindo(g.telefono)}`).join("\n"));
    toast(`${con.length} números copiados`);
  };
  $("#telCopyFalta").onclick = () => {
    if (!sin.length) return toast("Ya cargaron todos");
    copyText(`Faltan pasar su WhatsApp:\n${sin.map(g => `• ${g.nombre}${g.team ? " (" + g.team + ")" : ""}`).join("\n")}`);
    toast(`${sin.length} nombres copiados`);
  };
  conectarEditarTel(sheetTelefonos);
}

/* Editor de celular. Vive aparte porque lo usan dos pantallas: la de
   WhatsApp del equipo y la lista de usuarios. `volver` decide a cuál se
   regresa después de guardar. */
function conectarEditarTel(volver) {
  document.querySelectorAll("#sheetBody [data-tel-ed]").forEach(b => b.onclick = () =>
    editarTelDe(b.dataset.telEd, b.dataset.telNom, b.dataset.telVal, volver));
}

/* El editor propiamente dicho, separado para que lo pueda abrir cualquier
   pantalla —no sólo una fila dentro de un panel ya abierto. */
function editarTelDe(id, nom, actual, volver) {
  sheet(`
    <button class="btn ghost2" style="width:auto;padding:8px 14px;margin-bottom:12px" id="teBack">${ico("atras")}Volver</button>
    <div class="sh-h">${esc(nom)}<span class="r-sub">WhatsApp</span></div>
    <div class="field"><label>Celular</label>
      <input id="teN" type="tel" inputmode="numeric" placeholder="71234567" value="${actual ? esc(actual.startsWith("591") ? actual.slice(3) : actual) : ""}"></div>
    <div class="hint" style="margin:-4px 0 14px">Los 8 dígitos si es de Bolivia. Dejalo vacío para borrarlo.</div>
    <button class="btn primary" id="teGo">Guardar</button>`);
  $("#teBack").onclick = volver;
  $("#teGo").onclick = async () => {
    $("#teGo").disabled = true;
    const { error: e2 } = await sb.rpc("guardar_telefono_de", { p_user: id, p_tel: $("#teN").value.trim() });
    $("#teGo").disabled = false;
    if (e2) return toast(e2.message, "warn");
    toast("Guardado"); volver();
  };
}

/* usuarios y teams (admin) — Administración de usuarios y equipos.
 *
 * Pantalla con NIVELES:
 *   Usuarios | Teams  →  Team AQ  →  Sofía (detalle con contexto)
 * Cada nivel interno lleva su "← Volver" contextual y el botón Atrás del
 * navegador respeta la misma jerarquía (pushState/popstate, como Accesos).
 * Al volver se restaura el scroll, y los filtros/búsqueda persisten.
 *
 * Las ACCIONES rápidas siguen en drawers (editar, clave, teléfono, QR,
 * desglose); las vistas con contenido (team, persona con contexto) son
 * internas. Toda la lógica es la preexistente: mismas consultas, mismo
 * rol/team efectivo, mismas sheets (sheetEditarUsuario, sheetEditarTeam,
 * resetClave, editarTelDe, sheetTelefonos) y el DESGLOSE de siempre
 * (sheetDesgloseTeam → copyDesgloseTeam: manillas prepagadas o compras
 * en puerta del evento activo, en texto listo para WhatsApp). */
const clubTag = cl => !cl || !cl.length ? "Todos"
  : cl.length === 1 ? (clubNombre(cl[0]).slice(0, 7))
  : `${cl.length} boliches`;
const teamsDelClub = () => teamsCache.filter(t => !t.clubs || t.clubs.includes(club));

let genteTab = "usuarios";                       // Usuarios | Teams
let gnNav = null;                                // null | {tipo:"team",id} | {tipo:"user",id,teamId}
let gnQ = "", gnFRol = "", gnFTeam = "", gnFEstado = "";   // filtros (persisten)
let gnGente = [], gnTels = {};                   // datos de la última carga
let gnScroll = {};                               // scroll por nivel, para restaurar al volver

/* Compatibilidad: todo lo que "volvía" a la sheet vieja (editar usuario,
   editar team, teléfonos, el menú del perfil) cae acá y aterriza en la
   pantalla nueva, EN el nivel donde estaba. */
function sheetUsuarios() {
  closeSheet();
  if (tab !== "gente") { tab = "gente"; setTab(); }
  renderTab();
}

const gnNivelKey = () => !gnNav ? `raiz-${genteTab}` : `${gnNav.tipo}-${gnNav.id}`;
/* navegar guardando historial + scroll del nivel que se deja */
function gnIr(nav, sinHistorial) {
  gnScroll[gnNivelKey()] = window.scrollY;
  gnNav = nav;
  if (!sinHistorial) {
    const ruta = !nav ? genteTab : nav.tipo === "team" ? `team/${nav.id}` : `u/${nav.id}`;
    try { history.pushState({ tab: "gente", nav }, "", `#gente/${ruta}`); } catch { /* file:// */ }
  }
  conPantalla(screenGente);
}

async function screenGente() {
  if (me.rol !== "admin") { $("#main").innerHTML = `<div class="empty">Solo para administradores.</div>`; return; }
  await loadTeams();
  const [{ data: todos }, { data: allMems }, { data: tels }] = await conDatos("gente", () => Promise.all([
    // los eliminados quedan solo como etiqueta de su historial: no se listan
    sb.from("profiles").select("*, t:teams!profiles_team_id_fkey(nombre)").is("eliminado_at", null).order("rol").order("nombre"),
    sb.from("club_membership").select("user_id, club_id, rol, team_id"),
    // El teléfono no vive en profiles: lo resuelve esta RPC, la misma que usa
    // la pantalla de WhatsApp.
    sb.rpc("telefonos_equipo", { p_club: club })
  ]));
  const telPorId = {};
  (tels || []).forEach(t => { if (t.telefono) telPorId[t.user_id] = t.telefono; });
  // rol/team EFECTIVO en el boliche actual (membership manda; si no, la base)
  const memBy = {}; (allMems || []).forEach(m => (memBy[m.user_id] = memBy[m.user_id] || {})[m.club_id] = m);
  const teamById = id => teamsCache.find(t => t.id === id);
  const nombreTeam = id => teamById(id)?.nombre || "";
  (todos || []).forEach(g => {
    const mm = g.rol === "admin" ? null : memBy[g.id]?.[club];
    if (mm) { g._effRol = mm.rol; g._effTeam = mm.team_id ?? null; }
    else if (g.rol === "admin") { g._effRol = "admin"; g._effTeam = g.team_id ?? null; }
    else {
      // team base solo si opera en este boliche; si no, jefe→relacionador, sin team
      const bt = g.team_id ? teamById(g.team_id) : null;
      const baseAca = bt && (!bt.clubs || bt.clubs.includes(club));
      g._effRol = (g.rol === "jefe" && !baseAca) ? "rrpp" : g.rol;
      g._effTeam = baseAca ? g.team_id : null;
    }
    g._effTeamNom = g._effTeam ? nombreTeam(g._effTeam) : "";
  });
  // solo la gente del boliche activo (los de "Ambos" y admins salen en los dos)
  const gente = (todos || []).filter(g => g.rol === "admin" || !g.clubs?.length || g.clubs.includes(club));
  gnGente = gente; gnTels = telPorId;
  if (gnFTeam && gnFTeam !== "__none__" && !teamsDelClub().some(t => t.id === gnFTeam)) gnFTeam = "";

  // niveles internos: si el destino ya no existe (team borrado, usuario
  // eliminado), se cae al nivel de arriba en vez de morir
  if (gnNav?.tipo === "team" && !teamsDelClub().some(t => t.id === gnNav.id)) gnNav = null;
  if (gnNav?.tipo === "user" && !gente.some(g => g.id === gnNav.id)) gnNav = gnNav.teamId ? { tipo: "team", id: gnNav.teamId } : null;

  if (gnNav?.tipo === "team") { gnVistaTeam(teamById(gnNav.id)); return; }
  if (gnNav?.tipo === "user") { gnVistaUsuario(gente.find(g => g.id === gnNav.id)); return; }

  const clubNom = clubNombre(club);
  const nAdm = gente.filter(g => g._effRol === "admin").length;
  const nAct = gente.filter(g => g.activo).length;
  $("#main").innerHTML = `
    ${pgHead({
      ey: "Gestión", t: "Administración de usuarios y equipos",
      s: `${esc(clubNom)} · ${gente.length} usuario${gente.length === 1 ? "" : "s"} · ${teamsDelClub().length} team${teamsDelClub().length === 1 ? "" : "s"}`,
      acc: `${genteTab === "usuarios" ? `<button class="btn ghost2" id="gnTels">${ico("telefono")}WhatsApp</button>` : ""}
        <button class="btn primary" id="gnNuevo">${ico("mas")}${genteTab === "usuarios" ? "Nuevo usuario" : "Nuevo team"}</button>` })}
    <div class="kps kps-4">
      ${kpi({ ic: "usuario", k: "Usuarios totales", v: gente.length, cola: "grupo" })}
      ${kpi({ ic: "grupo", k: "Teams", v: teamsDelClub().length, cola: "grupo" })}
      ${kpi({ ic: "escudo", k: "Administradores", v: nAdm, tono: "marca" })}
      ${kpi({ ic: "check", k: "Activos", v: nAct, tono: "ok", cola: "barras" })}
    </div>
    <nav class="ac-subs gn-tabs" role="tablist">
      <button role="tab" class="ac-sub${genteTab === "usuarios" ? " on" : ""}" data-gt="usuarios">Usuarios</button>
      <button role="tab" class="ac-sub${genteTab === "teams" ? " on" : ""}" data-gt="teams">Teams</button>
    </nav>
    <div id="gnCuerpo">${genteTab === "usuarios" ? gnListaUsuarios(gente, telPorId) : gnListaTeams(gente)}</div>`;

  qsa("#main [data-gt]").forEach(b => b.onclick = () => { genteTab = b.dataset.gt; screenGente(); });
  $("#gnNuevo").onclick = () => genteTab === "usuarios" ? sheetNuevoUsuario() : sheetNuevoTeam();
  if (genteTab === "usuarios") gnConectarUsuarios(gente);
  else gnConectarTeams();
  const sy = gnScroll[gnNivelKey()];
  if (sy) requestAnimationFrame(() => window.scrollTo(0, sy));
}

/* ---------- nivel raíz · USUARIOS ---------- */
function gnListaUsuarios(gente, telPorId) {
  const filaDe = g => {
    const busca = `${g.nombre} @${g.usuario} ${ROL_LABEL[g._effRol]} ${g._effTeamNom} ${telPorId[g.id] || ""}`.toLowerCase();
    return `
    <div class="gn-fila" data-gu="${g.id}" data-row="${esc(busca)}" data-team="${g._effTeam || ""}" data-rol="${g._effRol}" data-act="${g.activo ? 1 : 0}" role="button" tabindex="0">
      ${inicial(g.nombre)}
      <span class="gn-nm">${esc(g.nombre)}${g.id === me.id ? ` <span class="us-yo">Vos</span>` : ""}</span>
      <span class="gn-user">@${esc(g.usuario)}</span>
      <span class="gn-rol">${rolBadge(g._effRol)}</span>
      <span class="gn-team">${ico("grupo")}${g._effTeamNom ? esc(g._effTeamNom) : `<span class="vacio">Sin team</span>`}</span>
      <span class="gn-est">${g.activo ? pillEst("Activo") : pillEst("Pausado", "off")}</span>
      <button class="tk-mas" data-mas-gu="${g.id}" title="Ficha" aria-label="Ficha de ${esc(g.nombre)}">${ico("puntos")}</button>
    </div>`;
  };
  return `
    <div class="iv-tools">
      <label class="campo-ic iv-buscar">${ico("buscar")}<input id="gnBuscar" placeholder="Buscar por nombre, usuario, team o número…" autocomplete="off" value="${esc(gnQ)}"></label>
      <div class="iv-filtros gn-filtros">
        <label class="sel-ic">${ico("usuario")}<select id="gnRolF" title="Filtrar por rol">
          <option value="">Todos los roles</option>
          ${["admin", "jefe", "rrpp", "portero", "caja"].map(r => `<option value="${r}"${gnFRol === r ? " selected" : ""}>${ROL_LABEL[r]}</option>`).join("")}
        </select></label>
        <label class="sel-ic">${ico("grupo")}<select id="gnTeamF" title="Filtrar por team">
          <option value="">Todos los teams</option>
          ${teamsDelClub().map(t => `<option value="${t.id}"${gnFTeam === t.id ? " selected" : ""}>${esc(t.nombre)}</option>`).join("")}
          <option value="__none__"${gnFTeam === "__none__" ? " selected" : ""}>Sin team</option>
        </select></label>
        <label class="sel-ic sel-dot"><span class="dot"></span><select id="gnEstF" title="Filtrar por estado">
          <option value="">Estado: Todos</option>
          <option value="1"${gnFEstado === "1" ? " selected" : ""}>Activos</option>
          <option value="0"${gnFEstado === "0" ? " selected" : ""}>Pausados</option>
        </select></label>
      </div>
    </div>
    <div class="gn-tabla">
      <div class="gn-cab" aria-hidden="true">
        <span></span><span>Nombre</span><span>Usuario</span><span>Rol</span><span>Team</span><span>Estado</span><span>Acciones</span>
      </div>
      ${gente.map(filaDe).join("") || `<div class="empty">No hay usuarios.</div>`}
    </div>
    <div class="gn-vacio empty hidden" id="gnSinResultados">Nadie coincide con esos filtros.</div>`;
}

function gnConectarUsuarios(gente) {
  // desde la lista, la ficha es un drawer: acciones rápidas sin perder
  // filtros ni scroll (el detalle CON contexto vive dentro de cada team)
  const abrirFicha = id => { const g = gente.find(x => x.id === id); if (g) sheetFichaUsuario(g); };
  qsa("#main .gn-fila[data-gu]").forEach(f => {
    f.onclick = () => abrirFicha(f.dataset.gu);
    f.onkeydown = e => { if (e.key === "Enter") abrirFicha(f.dataset.gu); };
  });
  $("#gnTels") && ($("#gnTels").onclick = e => { e.stopPropagation(); sheetTelefonos(); });
  const bq = $("#gnBuscar"), fr = $("#gnRolF"), ft = $("#gnTeamF"), fe = $("#gnEstF");
  const aplicar = () => {
    gnQ = (bq?.value || "").trim().toLowerCase();
    gnFRol = fr?.value || ""; gnFTeam = ft?.value || ""; gnFEstado = fe?.value ?? "";
    let visibles = 0;
    qsa("#main .gn-fila[data-gu]").forEach(row => {
      const ok = row.dataset.row.includes(gnQ)
        && (!gnFRol || row.dataset.rol === gnFRol)
        && (!gnFTeam || (gnFTeam === "__none__" ? !row.dataset.team : row.dataset.team === gnFTeam))
        && (gnFEstado === "" || row.dataset.act === gnFEstado);
      row.style.display = ok ? "" : "none";
      if (ok) visibles++;
    });
    $("#gnSinResultados")?.classList.toggle("hidden", visibles > 0);
    $("#main .gn-cab") && ($("#main .gn-cab").style.display = visibles ? "" : "none");
  };
  if (bq) bq.oninput = aplicar;
  [fr, ft, fe].forEach(s => { if (s) s.onchange = aplicar; });
  aplicar();   // los filtros persisten entre visitas
}

/* ---------- nivel raíz · TEAMS ---------- */
function gnListaTeams(gente) {
  const filas = teamsDelClub().map(t => {
    const miembros = gente.filter(g => g._effTeam === t.id);
    const jefes = miembros.filter(g => g._effRol === "jefe");
    const rrpps = miembros.filter(g => g._effRol === "rrpp");
    return `
    <div class="gn-fila gn-fila-tm" data-tm="${t.id}" role="button" tabindex="0">
      ${inicial(t.nombre.replace(/^team /i, "") || "T")}
      <span class="gn-nm">${esc(t.nombre)}</span>
      <span class="gn-user">${jefes.length ? `Jefe: ${esc(jefes.map(j => j.nombre.split(" ")[0]).join(", "))}` : `<span class="vacio">Sin jefe</span>`}</span>
      <span class="gn-rol">${rrpps.length} RRPP</span>
      <span class="gn-team">${ico("grupo")}${miembros.length} miembro${miembros.length === 1 ? "" : "s"}</span>
      <span class="gn-est"><span class="pill-club">${clubTag(t.clubs)}</span></span>
      <button class="tk-mas" data-mas-tm="${t.id}" title="Abrir" aria-label="Abrir ${esc(t.nombre)}">${ico("puntos")}</button>
    </div>`;
  }).join("");
  return `
    <div class="gn-tabla">
      <div class="gn-cab" aria-hidden="true">
        <span></span><span>Team</span><span>Jefe</span><span>RRPP</span><span>Miembros</span><span>Boliche</span><span>Acciones</span>
      </div>
      ${filas || `<div class="empty">Todavía no hay teams en este boliche.</div>`}
    </div>`;
}

function gnConectarTeams() {
  qsa("#main .gn-fila[data-tm]").forEach(f => {
    f.onclick = () => gnIr({ tipo: "team", id: f.dataset.tm });
    f.onkeydown = e => { if (e.key === "Enter") gnIr({ tipo: "team", id: f.dataset.tm }); };
  });
}

/* ---------- vista interna · UN TEAM ---------- */
function gnVistaTeam(t) {
  if (!t) { gnNav = null; return screenGente(); }
  const miembros = gnGente.filter(g => g._effTeam === t.id)
    .sort((a, b) => (a._effRol === "jefe" ? 0 : 1) - (b._effRol === "jefe" ? 0 : 1) || a.nombre.localeCompare(b.nombre));
  const jefes = miembros.filter(g => g._effRol === "jefe");
  const rrpps = miembros.filter(g => g._effRol === "rrpp");
  const invite = `${location.origin}${location.pathname}?invite=${t.invite_code}`;
  $("#main").innerHTML = `
    <button class="btn ghost2 gn-volver" id="gnBack">${ico("atras")}Todos los teams</button>
    ${pgHead({ ey: "Team", t: esc(t.nombre),
      s: `${jefes.length ? `Jefe: <b>${esc(jefes.map(j => j.nombre).join(", "))}</b> · ` : ""}<b>${rrpps.length}</b> RRPP · <b>${miembros.length}</b> miembro${miembros.length === 1 ? "" : "s"} · ${clubTag(t.clubs)}`,
      acc: ev ? `<button class="btn primary" id="gnResumen">${ico("copiar")}Copiar resumen</button>` : "" })}
    <div class="dt-acc" style="flex-wrap:wrap;margin-bottom:16px">
      <button class="btn ghost2" id="ftInv">${ico("copiar")}Copiar link de registro</button>
      <button class="btn ghost2" id="ftQr">${ico("qr")}QR de cobro</button>
      <button class="btn ghost2" id="ftEdit">${ico("ajustes")}Editar team</button>
    </div>
    <div class="gn-tabla">
      <div class="gn-cab" aria-hidden="true">
        <span></span><span>Nombre</span><span>Usuario</span><span>Rol</span><span></span><span>Estado</span><span></span>
      </div>
      ${miembros.map(g => `
      <div class="gn-fila" data-gu="${g.id}" role="button" tabindex="0">
        ${inicial(g.nombre)}
        <span class="gn-nm">${esc(g.nombre)}</span>
        <span class="gn-user">@${esc(g.usuario)}</span>
        <span class="gn-rol">${rolBadge(g._effRol)}</span>
        <span class="gn-team"></span>
        <span class="gn-est">${g.activo ? pillEst("Activo") : pillEst("Pausado", "off")}</span>
        <button class="tk-mas" title="Abrir" aria-label="Abrir ${esc(g.nombre)}">${ico("puntos")}</button>
      </div>`).join("") || `<div class="empty">Nadie asignado a este team acá.</div>`}
    </div>
    <p class="hint" style="margin-top:10px">Tocá a alguien para ver su detalle, moverlo de team o cambiarle el rol.</p>`;
  $("#gnBack").onclick = () => gnIr(null);
  // el desglose de SIEMPRE (manillas prepagadas / compras en puerta del
  // evento activo, texto listo para WhatsApp) — misma lógica, nuevo lugar
  const br = $("#gnResumen");
  if (br) br.onclick = () => sheetDesgloseTeam(t.id, t.nombre);
  $("#ftInv").onclick = async () => { await copyText(invite); toast("Link copiado — mandalo a ese team"); };
  $("#ftQr").onclick = () => sheetQrTeamAdmin(t);
  $("#ftEdit").onclick = () => sheetEditarTeam(t);
  qsa("#main .gn-fila[data-gu]").forEach(f => {
    f.onclick = () => gnIr({ tipo: "user", id: f.dataset.gu, teamId: t.id });
    f.onkeydown = e => { if (e.key === "Enter") gnIr({ tipo: "user", id: f.dataset.gu, teamId: t.id }); };
  });
  const sy = gnScroll[gnNivelKey()];
  if (sy) requestAnimationFrame(() => window.scrollTo(0, sy));
}

/* ---------- vista interna · UNA PERSONA (con contexto) ---------- */
async function gnVistaUsuario(g) {
  if (!g) { gnNav = null; return screenGente(); }
  const desdeTeam = gnNav?.teamId ? teamsCache.find(t => t.id === gnNav.teamId) : null;
  const tel = gnTels[g.id] || "";
  const esRel = ["rrpp", "jefe"].includes(g._effRol);
  $("#main").innerHTML = `
    <button class="btn ghost2 gn-volver" id="gnBack">${ico("atras")}${desdeTeam ? `Volver a ${esc(desdeTeam.nombre)}` : "Volver"}</button>
    ${desdeTeam ? `<p class="gn-miga">Teams / ${esc(desdeTeam.nombre)} / <b>${esc(g.nombre)}</b></p>` : ""}
    <div class="pg-persona">
      ${inicial(g.nombre).replace('class="ini"', 'class="ini ini-lg"')}
      ${pgHead({ ey: "Usuario", t: `${esc(g.nombre)}${g.id === me.id ? ` <span class="us-yo">Vos</span>` : ""}`,
        s: `@${esc(g.usuario)} · ${ROL_LABEL[g._effRol]}${g._effTeamNom ? ` · ${esc(g._effTeamNom)}` : ""}` })}
    </div>
    <div class="dt-datos" style="max-width:560px">
      <div class="dt-f"><span class="dt-k">Estado</span><span class="dt-v">${g.activo ? pillEst("Activo") : pillEst("Pausado", "off")}</span></div>
      ${g.rol === "admin" ? "" : `<div class="dt-f"><span class="dt-k">Opera en</span><span class="dt-v">${clubTag(g.clubs)}</span></div>`}
      ${g._effRol !== g.rol || (g._effTeam ?? null) !== (g.team_id ?? null)
        ? `<div class="dt-f"><span class="dt-k">Base</span><span class="dt-v">${ROL_LABEL[g.rol]}${g.t?.nombre ? ` · ${esc(g.t.nombre)}` : ""}</span></div>` : ""}
      <div class="dt-f"><span class="dt-k">WhatsApp</span><span class="dt-v">${tel
        ? `<a class="us-tel" href="https://wa.me/${esc(tel)}" target="_blank" rel="noopener">${esc(telLindo(tel))}</a>`
        : "—"}</span></div>
      <div id="gnStats"></div>
    </div>
    ${cuentaProtegida(g)
      ? `<p class="hint gn-protegida" style="margin-top:14px">Cuenta protegida — solo su dueño puede modificarla.</p>`
      : `<div class="dt-acc" style="flex-wrap:wrap;margin-top:14px">
      <button class="btn primary" id="fuEdit">Editar</button>
      <button class="btn ghost2" id="fuPausa">${g.activo ? "Pausar" : "Activar"}</button>
      <button class="btn ghost2" id="fuTel">${tel ? "Cambiar número" : "Cargar número"}</button>
      <button class="btn ghost2" id="fuClave">Resetear clave</button>
    </div>`}`;
  $("#gnBack").onclick = () => gnIr(desdeTeam ? { tipo: "team", id: desdeTeam.id } : null);
  gnConectarAccionesUsuario(g, tel);
  gnPintarStats(g, esRel, "#gnStats");
}

/* acciones de la ficha/vista (ausentes cuando la cuenta está protegida) */
function gnConectarAccionesUsuario(g, tel) {
  const be = $("#fuEdit"); if (!be) return;   // cuenta protegida: sin acciones
  be.onclick = () => sheetEditarUsuario(g);
  $("#fuPausa").onclick = async () => {
    const { error } = await sb.from("profiles").update({ activo: !g.activo }).eq("id", g.id);
    if (error) return fail(error);
    toast(g.activo ? `${g.nombre} pausado` : `${g.nombre} activado`, g.activo ? "warn" : "ok");
    sheetUsuarios();
  };
  $("#fuTel").onclick = () => editarTelDe(g.id, g.nombre, tel, sheetUsuarios);
  $("#fuClave").onclick = () => resetClave(g.id, g.nombre);
}

/* números del evento activo, solo para quien vende (porteros/caja sin
   métricas). Sale de la vista que ya usa el Reporte. */
async function gnPintarStats(g, esRel, sel) {
  if (!esRel || !ev) return;
  const { data: st } = await sb.from("v_stats_rrpp").select("anotados,ingresaron,entradas_vendidas,entradas_usadas")
    .eq("evento_id", ev.id).eq("rrpp_id", g.id).maybeSingle();
  const el = $(sel);
  if (el && st) el.innerHTML = `
    <div class="dt-f"><span class="dt-k">${esc(ev.nombre)}</span><span class="dt-v">${st.entradas_vendidas} vendidas · ${st.anotados} anotados · ${(+st.ingresaron) + (+st.entradas_usadas)} ingresaron</span></div>`;
}

/* Ficha rápida (drawer) desde la lista de Usuarios: mismas acciones, sin
   perder filtros ni scroll de la lista. */
async function sheetFichaUsuario(g) {
  const tel = gnTels[g.id] || "";
  const esRel = ["rrpp", "jefe"].includes(g._effRol);
  sheet(`
    <div class="acct" style="margin-bottom:6px"><div class="avatar">${esc(g.nombre[0])}</div>
      <div class="an">${esc(g.nombre)}</div>
      <div class="as">@${esc(g.usuario)} · ${ROL_LABEL[g._effRol]}${g._effTeamNom ? ` · ${esc(g._effTeamNom)}` : ""}</div></div>
    <div class="dt-datos">
      <div class="dt-f"><span class="dt-k">Estado</span><span class="dt-v">${g.activo ? "Activo" : "Pausado"}</span></div>
      ${g.rol === "admin" ? "" : `<div class="dt-f"><span class="dt-k">Opera en</span><span class="dt-v">${clubTag(g.clubs)}</span></div>`}
      ${g._effRol !== g.rol || (g._effTeam ?? null) !== (g.team_id ?? null)
        ? `<div class="dt-f"><span class="dt-k">Base</span><span class="dt-v">${ROL_LABEL[g.rol]}${g.t?.nombre ? ` · ${esc(g.t.nombre)}` : ""}</span></div>` : ""}
      <div class="dt-f"><span class="dt-k">WhatsApp</span><span class="dt-v">${tel
        ? `<a class="us-tel" href="https://wa.me/${esc(tel)}" target="_blank" rel="noopener">${esc(telLindo(tel))}</a>`
        : "—"}</span></div>
      <div id="gnStatsSheet"></div>
    </div>
    ${cuentaProtegida(g)
      ? `<p class="hint gn-protegida">Cuenta protegida — solo su dueño puede modificarla.</p>`
      : `<div class="dt-acc" style="flex-wrap:wrap">
      <button class="btn primary" id="fuEdit">Editar</button>
      <button class="btn ghost2" id="fuPausa">${g.activo ? "Pausar" : "Activar"}</button>
      <button class="btn ghost2" id="fuTel">${tel ? "Cambiar número" : "Cargar número"}</button>
      <button class="btn ghost2" id="fuClave">Resetear clave</button>
    </div>`}`);
  gnConectarAccionesUsuario(g, tel);
  gnPintarStats(g, esRel, "#gnStatsSheet");
}

/* alta de usuario: el formulario de siempre, en su propia sheet */
function sheetNuevoUsuario() {
  sheet(`
    <div class="sh-h">Nuevo usuario · ${clubNombre(club)}</div>
    <div class="row2">
      <div class="field"><label>Nombre</label><input id="usN"></div>
      <div class="field"><label>Usuario</label><input id="usU" autocapitalize="none"></div>
    </div>
    <div class="row2">
      <div class="field"><label>Rol</label><select id="usR"><option value="rrpp">Relacionador</option><option value="jefe">Jefe de team</option><option value="portero">Seguridad</option><option value="caja">Caja</option>${me.plataforma ? `<option value="admin">Admin</option>` : ""}${me.admin_principal ? `<optgroup label="Barra (fase 2 — todavía no anunciada)"><option value="propietario">Propietario de barra</option><option value="barra">Bartender</option><option value="deposito">Recepción de mercadería</option></optgroup>` : ""}</select></div>
      <div class="field"><label>Team</label><select id="usT"><option value="">—</option>${teamsDelClub().map(t => `<option value="${t.id}">${esc(t.nombre)}</option>`).join("")}</select></div>
    </div>
    <div class="row2">
      <div class="field"><label>Boliches donde opera</label>
        <div class="chk-group" id="usClubs">${clubsDisponibles.map(c =>
          `<label class="chk"><input type="checkbox" value="${c.id}"${c.id === club ? " checked" : ""}> ${esc(c.nombre)}</label>`
        ).join("") || `<small style="color:var(--text-3)">Todavía no hay ningún boliche creado.</small>`}</div></div>
      <div class="field"><label>Contraseña (mín. 6)</label><input id="usP"></div>
    </div>
    <button class="btn primary" id="usGo">Crear usuario</button>`);
  $("#usGo").onclick = async () => {
    const nombre = $("#usN").value.trim(), usuario = $("#usU").value.trim(), clave = $("#usP").value;
    if (!nombre || !usuario || clave.length < 6) return toast("Completá nombre, usuario y clave (6+)", "warn");
    $("#usGo").disabled = true;
    const { data: { session } } = await sb.auth.getSession();
    const res = await fetch(`${CFG.SUPABASE_URL}/functions/v1/crear-usuario`, {
      method: "POST",
      headers: { "Content-Type": "application/json", Authorization: `Bearer ${session.access_token}` },
      body: JSON.stringify({ usuario, nombre, clave, rol: $("#usR").value, team_id: $("#usT").value || null })
    });
    $("#usGo").disabled = false;
    const out = await res.json();
    if (!res.ok) return toast(out.error || "Error", "warn");
    // boliches elegidos: sobrescriben lo que se haya heredado del team
    const seleccionados = [...document.querySelectorAll("#usClubs input:checked")].map(i => i.value);
    await sb.from("profiles").update({ clubs: seleccionados.length ? seleccionados : [club] }).eq("usuario", usuario.toLowerCase());
    toast(`@${usuario} creado`);
    sheetUsuarios();
  };
}

/* alta de team, en su propia sheet */
function sheetNuevoTeam() {
  sheet(`
    <div class="sh-h">Nuevo team · ${clubNombre(club)}</div>
    <div class="field"><label>Nombre</label><input id="tmN" placeholder="Team A.Q"></div>
    <button class="btn primary" id="tmGo">Crear team</button>`);
  $("#tmGo").onclick = async () => {
    const nombre = $("#tmN").value.trim(); if (!nombre) return;
    $("#tmGo").disabled = true;
    const { error } = await sb.from("teams").insert({ nombre, clubs: [club] });
    $("#tmGo").disabled = false;
    if (error) return toast(error.message.includes("duplicate") || error.code === "23505" ? `Ya existe un team llamado "${nombre}"` : error.message, "warn");
    invalidarCache("teams");
    toast("Team creado"); sheetUsuarios();
  };
}

/* editar un usuario: nombre, rol, team, boliches + clave y eliminar */
async function sheetEditarUsuario(g) {
  if (!g) return;
  // el server lo rechaza igual (trigger); acá ni se abre el editor
  if (cuentaProtegida(g)) return toast("Esta cuenta administrativa está protegida.", "warn");
  const misClubs = g.clubs && g.clubs.length ? g.clubs : [];
  const roles = { rrpp: "Relacionador", jefe: "Jefe de team", portero: "Seguridad", caja: "Caja", admin: "Admin" };
  const teamOpts = (selId) => `<option value="">— sin team —</option>${teamsCache.map(t => `<option value="${t.id}"${selId === t.id ? " selected" : ""}>${esc(t.nombre)}</option>`).join("")}`;
  const rolOpts = (selR) => Object.entries({ rrpp: "Relacionador", jefe: "Jefe de team" }).map(([v, l]) => `<option value="${v}"${selR === v ? " selected" : ""}>${l}</option>`).join("");
  // membresías actuales de este usuario (rol/team por boliche)
  const { data: mems } = await sb.from("club_membership").select("club_id, rol, team_id").eq("user_id", g.id);
  const memBy = {}; (mems || []).forEach(m => memBy[m.club_id] = m);
  const dobleBoliche = g.rol !== "admin" && misClubs.length >= 2;
  const bloqueBoliche = c => {
    const nm = clubNombre(c);
    const m = memBy[c] || { rol: g.rol === "admin" ? "rrpp" : g.rol, team_id: g.team_id };
    return `<div class="lst-card open" style="margin-bottom:10px" data-bloque="${c}"><div class="lst-body" style="padding:12px">
      <div class="lst-nm" style="margin-bottom:8px">${esc(nm)}</div>
      <div class="row2">
        <div class="field"><label>Rol acá</label><select data-brol="${c}">${rolOpts(m.rol)}</select></div>
        <div class="field"><label>Team acá</label><select data-bteam="${c}">${teamOpts(m.team_id)}</select></div>
      </div></div></div>`;
  };
  sheet(`
    <div class="sh-h">Editar usuario</div>
    <div class="acct" style="margin-bottom:8px"><div class="avatar">${esc(g.nombre[0])}</div>
      <div class="an">${esc(g.nombre)}</div><div class="as">@${esc(g.usuario)}</div></div>
    <div class="field"><label>Nombre</label><input id="euN" value="${esc(g.nombre)}"></div>
    <div class="row2">
      <div class="field"><label>Rol${dobleBoliche ? " base" : ""}</label><select id="euR">${Object.entries(roles).filter(([v]) => v !== "admin" || me.plataforma || g.rol === "admin").map(([v, l]) => `<option value="${v}"${g.rol === v ? " selected" : ""}>${l}</option>`).join("")}</select></div>
      <div class="field"><label>Team${dobleBoliche ? " base" : ""}</label><select id="euT">${teamOpts(g.team_id)}</select></div>
    </div>
    <div class="field"><label>Boliches donde opera</label>
      <div class="chk-group" id="euClubs">${clubsDisponibles.map(c =>
        `<label class="chk"><input type="checkbox" value="${c.id}"${misClubs.includes(c.id) ? " checked" : ""}> ${esc(c.nombre)}</label>`
      ).join("")}</div>
      <small style="color:var(--text-3)">Los admin ven todos igual.</small></div>
    <div id="euBloques">${dobleBoliche ? `<div class="sh-h" style="margin-top:14px">Rol y team por boliche</div>
      <div class="hint" style="margin:0 0 10px">Puede ser jefe en un boliche y relacionador en otro (con su team en cada uno). Vacío = usa el rol/team base.</div>
      ${misClubs.map(bloqueBoliche).join("")}` : ""}</div>
    <button class="btn primary" id="euGo">Guardar</button>
    <div style="height:12px"></div>
    <button class="btn ghost2" id="euClave">Cambiar contraseña</button>
    <div style="height:10px"></div>
    <button class="btn danger" id="euDel">Eliminar usuario</button>
    <p class="hint" style="margin-top:8px">Si ya cargó manillas o listas, la cuenta se bloquea y deja de aparecer, pero lo que vendió sigue figurando con su nombre en los desgloses.</p>`);
  const refrescarBloques = () => {
    const sel = [...document.querySelectorAll("#euClubs input:checked")].map(i => i.value);
    const dobleAhora = $("#euR").value !== "admin" && sel.length >= 2;
    $("#euBloques").innerHTML = dobleAhora ? `<div class="sh-h" style="margin-top:14px">Rol y team por boliche</div>
      <div class="hint" style="margin:0 0 10px">Puede ser jefe en un boliche y relacionador en otro (con su team en cada uno). Vacío = usa el rol/team base.</div>
      ${sel.map(bloqueBoliche).join("")}` : "";
  };
  document.querySelectorAll("#euClubs input").forEach(i => i.onchange = refrescarBloques);
  $("#euR").onchange = refrescarBloques;
  $("#euGo").onclick = async () => {
    const nombre = $("#euN").value.trim();
    if (!nombre) return toast("Poné el nombre", "warn");
    const seleccionados = [...document.querySelectorAll("#euClubs input:checked")].map(i => i.value);
    const clubs = seleccionados.length ? seleccionados : [club];
    const { error } = await sb.from("profiles").update({
      nombre, rol: $("#euR").value, team_id: $("#euT").value || null, clubs
    }).eq("id", g.id);
    if (error) return toast(error.message, "warn");
    // membresías por boliche (solo si opera en 2+): guardamos SIEMPRE el rol/team de cada uno
    if (clubs.length >= 2 && $("#euR").value !== "admin") {
      const rows = clubs.map(c => ({
        user_id: g.id, club_id: c,
        rol: document.querySelector(`[data-brol="${c}"]`)?.value || $("#euR").value,
        team_id: document.querySelector(`[data-bteam="${c}"]`)?.value || null
      }));
      const { error: em } = await sb.from("club_membership").upsert(rows);
      if (em) return toast("No se guardó la config por boliche: " + em.message, "warn");
    } else {
      await sb.from("club_membership").delete().eq("user_id", g.id);  // un solo boliche: sin overrides
    }
    efectivosClub = null;   // cambió un team: recalcular en la próxima pantalla
    toast("Usuario actualizado"); sheetUsuarios();
  };
  $("#euClave").onclick = () => resetClave(g.id, g.nombre);
  $("#euDel").onclick = async () => {
    if (!await confirmar({
      titulo: `Eliminar usuario ${g.nombre}`,
      detalle: [`@${g.usuario}`, ROL_LABEL[g.rol] || g.rol].filter(Boolean),
      aviso: "Pierde el acceso a la plataforma. Sus manillas y listas quedan registradas con su nombre.",
      accion: "Eliminar usuario"
    })) return;
    const { data: res, error } = await sb.rpc("eliminar_usuario", { p_user: g.id });
    if (error) return toast(error.message, "warn");
    toast(res?.modo === "archivado"
      ? `${g.nombre} eliminado — sus manillas y listas quedan con su nombre`
      : `${g.nombre} eliminado`, "warn");
    efectivosClub = null;
    sheetUsuarios();
  };
}

/* editar un team: nombre, boliches, eliminar */
function sheetEditarTeam(t, onDone) {
  if (!t) return;
  const listo = onDone || sheetUsuarios;
  const misClubs = t.clubs && t.clubs.length ? t.clubs : [];
  sheet(`
    <div class="sh-h">Editar team</div>
    <div class="field"><label>Nombre</label><input id="etNombre" value="${esc(t.nombre)}"></div>
    <div class="field"><label>Boliches donde opera</label>
      <div class="chk-group" id="etClubs">${clubsDisponibles.map(c =>
        `<label class="chk"><input type="checkbox" value="${c.id}"${misClubs.includes(c.id) ? " checked" : ""}> ${esc(c.nombre)}</label>`
      ).join("")}</div></div>
    <button class="btn primary" id="etGo">Guardar</button>
    <div class="hint" style="margin:10px 0 4px">Los usuarios nuevos que se registren por el link de este team heredan estos boliches.</div>
    <div class="sh-h" style="margin-top:16px">Eliminar team</div>
    <div class="field"><label>Al eliminar, mover sus usuarios a</label>
      <select id="etDest"><option value="">— dejar sin team —</option>${teamsCache.filter(x => x.id !== t.id).map(x => `<option value="${x.id}"${x.id === me.team_id ? " selected" : ""}>${esc(x.nombre)}</option>`).join("")}</select></div>
    <button class="btn danger" id="etDel">Eliminar team</button>`);
  $("#etGo").onclick = async () => {
    const nombre = $("#etNombre").value.trim();
    if (!nombre) return toast("Poné el nombre", "warn");
    const seleccionados = [...document.querySelectorAll("#etClubs input:checked")].map(i => i.value);
    const clubs = seleccionados.length ? seleccionados : clubsDisponibles.map(c => c.id);
    const { error } = await sb.from("teams").update({ nombre, clubs }).eq("id", t.id);
    if (error) return toast(error.message, "warn");
    toast("Team actualizado"); invalidarCache("teams"); efectivosClub = null; await loadTeams(true); listo();
  };
  $("#etDel").onclick = async () => {
    const dest = $("#etDest").value || null;
    const destNom = dest ? ($("#etDest").selectedOptions[0]?.textContent || "").trim() : "";
    if (!await confirmar({
      titulo: `Eliminar team ${t.nombre}`,
      detalle: [destNom ? `Sus integrantes pasan a ${destNom}` : "Sus integrantes quedan sin team"],
      aviso: destNom ? "" : "Los usuarios de este team quedarán sin asignar.",
      accion: "Eliminar team"
    })) return;
    const { data, error } = await sb.rpc("eliminar_team", { p_team: t.id, p_destino: dest });
    if (error) return toast(error.message, "warn");
    toast(`Team ${t.nombre} eliminado${data?.movidos ? ` — ${data.movidos} usuario(s) movido(s)` : ""}`, "warn");
    invalidarCache("teams"); efectivosClub = null; await loadTeams(true); listo();
  };
}

/* ---------- administración de boliches (admin) ---------- */
function sheetBoliches() {
  sheet(`
    <div class="sh-h">Boliches<span class="r-sub">${clubsDisponibles.length}</span></div>
    <button class="btn primary" id="clNuevo">Nuevo boliche</button>
    <div style="margin-top:14px">${clubsDisponibles.map(c => `
      <div class="list-row rc">
        <div class="r-l" style="flex:1">
          <span class="club-mark" style="--accent:${esc(c.color_primario)};--accent-2:${esc(c.color_secundario)};--glow:${hexToRgba(c.color_primario, .55)}">${clubMarkHTML(c.id)}</span>
          <span class="rc-body"><span class="rc-nm">${esc(c.nombre)}</span><span class="rc-sub">${esc(c.subtitulo || c.id)}</span></span>
        </div>
        <button class="checkin" data-cled="${c.id}">Editar</button>
      </div>`).join("") || `<div class="empty" style="margin-top:10px">Todavía no creaste ningún boliche.</div>`}</div>`);
  $("#clNuevo").onclick = sheetNuevoClub;
  document.querySelectorAll("[data-cled]").forEach(b => b.onclick = () =>
    sheetEditarClub(clubsDisponibles.find(c => c.id === b.dataset.cled)));
}

async function recargarClubs() {
  const { data } = await sb.from("clubs").select("*").eq("activo", true).order("nombre");
  clubsDisponibles = data || [];
}

/* Formulario de alta de boliche: lo usan la hoja "Boliches" y el selector
   de boliche del inicio (que está fuera de #app, donde vive la hoja). */
function formClubHTML() {
  return `
    <div class="field"><label>Nombre</label><input id="clN" placeholder="Mi Boliche" autocomplete="off"></div>
    <div class="field"><label>Slug (identificador único, sin espacios)</label><input id="clId" placeholder="se autogenera" autocomplete="off"></div>
    <div class="field"><label>Subtítulo (opcional)</label><input id="clSub" placeholder="Ej: Rojo · pista principal" autocomplete="off"></div>
    <div class="row2">
      <div class="field"><label>Color primario</label><input type="color" id="clP" value="#7C3AED"></div>
      <div class="field"><label>Color secundario</label><input type="color" id="clS" value="#A855F7"></div>
    </div>
    <div class="field"><label>Color de acento</label><input type="color" id="clA" value="#22D3EE"></div>
    <button class="btn primary" id="clGo">Crear boliche</button>`;
}
function bindFormClub(alCrear) {
  $("#clN").addEventListener("input", () => {
    if (!$("#clId").dataset.tocado) {
      $("#clId").value = $("#clN").value.trim().toLowerCase()
        .normalize("NFD").replace(/[\u0300-\u036f]/g, "")
        .replace(/[^a-z0-9]+/g, "-").replace(/^-+|-+$/g, "").slice(0, 30);
    }
  });
  $("#clId").addEventListener("input", () => $("#clId").dataset.tocado = "1");
  $("#clGo").onclick = async () => {
    const nombre = $("#clN").value.trim(), id = $("#clId").value.trim();
    if (!nombre || !id) return toast("Completá nombre y slug", "warn");
    if (!/^[a-z0-9][a-z0-9-]{1,29}$/.test(id)) return toast("Slug inválido: minúsculas, números y guiones", "warn");
    $("#clGo").disabled = true;
    const { error } = await sb.from("clubs").insert({
      id, nombre, subtitulo: $("#clSub").value.trim() || null,
      color_primario: $("#clP").value, color_secundario: $("#clS").value, color_accent: $("#clA").value,
      inicial: nombre.slice(0, 1).toUpperCase()
    });
    $("#clGo").disabled = false;
    if (error) return toast(error.code === "23505" ? `Ya existe un boliche con el slug "${id}"` : error.message, "warn");
    await recargarClubs();
    alCrear(id, nombre);
  };
}

function sheetNuevoClub() {
  sheet(`<div class="sh-h">Nuevo boliche</div>${formClubHTML()}`);
  bindFormClub(async (id, nombre) => {
    // primer boliche creado: ahora hay que elegirlo para poder operar
    if (!club) { club = id; renderClubMenu(myClubs()); await applyClubRole(); return enterApp(); }
    toast(`${nombre} creado`);
    sheetBoliches();
  });
}

function sheetEditarClub(c) {
  if (!c) return;
  sheet(`
    <div class="sh-h">Editar boliche</div>
    <div class="field"><label>Nombre</label><input id="ceN" value="${esc(c.nombre)}"></div>
    <div class="field"><label>Subtítulo</label><input id="ceSub" value="${esc(c.subtitulo || "")}"></div>
    <div class="row2">
      <div class="field"><label>Color primario</label><input type="color" id="ceP" value="${esc(c.color_primario)}"></div>
      <div class="field"><label>Color secundario</label><input type="color" id="ceS" value="${esc(c.color_secundario)}"></div>
    </div>
    <div class="field"><label>Color de acento</label><input type="color" id="ceA" value="${esc(c.color_accent)}"></div>
    <button class="btn primary" id="ceGo">Guardar</button>
    <div style="height:12px"></div>
    <button class="btn danger" id="ceDel">Desactivar boliche</button>
    <p class="hint" style="margin-top:8px">No se elimina (los eventos históricos quedan intactos); deja de aparecer para crear eventos nuevos.</p>`);
  $("#ceGo").onclick = async () => {
    const nombre = $("#ceN").value.trim();
    if (!nombre) return toast("Poné el nombre", "warn");
    const { error } = await sb.from("clubs").update({
      nombre, subtitulo: $("#ceSub").value.trim() || null,
      color_primario: $("#ceP").value, color_secundario: $("#ceS").value, color_accent: $("#ceA").value
    }).eq("id", c.id);
    if (error) return toast(error.message, "warn");
    await recargarClubs();
    if (club === c.id) aplicarTemaClub(clubData(club));
    toast("Boliche actualizado");
    sheetBoliches();
  };
  $("#ceDel").onclick = async () => {
    if (!await confirmar({
      titulo: `Desactivar ${c.nombre}`,
      aviso: "No podrás crear eventos nuevos acá, pero el historial se conserva.",
      accion: "Desactivar"
    })) return;
    const { error } = await sb.from("clubs").update({ activo: false }).eq("id", c.id);
    if (error) return toast(error.message, "warn");
    await recargarClubs();
    toast("Boliche desactivado", "warn");
    sheetBoliches();
  };
}

/* admin: ver/subir/cambiar el QR de cobro de cualquier team
   (a este QR pagan las manillas del team y le rinden sus rrpps) */
async function sheetQrTeamAdmin(t) {
  if (!t) return;
  // la imagen se pide solo para ESTE team (no viaja en la lista general)
  const { data: row } = await sb.from("teams").select("qr_cobro_url").eq("id", t.id).maybeSingle();
  const qr = row?.qr_cobro_url || null;
  sheet(`
    <div class="sh-h">QR de cobro · ${esc(t.nombre)}</div>
    ${qr
      ? `<img src="${esc(qr)}" alt="QR ${esc(t.nombre)}" style="width:100%;max-width:300px;display:block;margin:0 auto 10px;border-radius:14px;background:#fff;padding:10px">`
      : `<div class="empty" style="margin-bottom:10px">Este team todavía no tiene QR.</div>`}
    <div class="hint" style="margin:0 0 12px">A este QR pagan los clientes las manillas de ${esc(t.nombre)} y le rinden sus relacionadores. El jefe también puede subirlo desde Pagos.</div>
    <button class="btn primary" id="qtSubir">${qr ? "Cambiar QR" : "Subir QR"}</button>
    ${qr ? `<div style="height:9px"></div><button class="btn danger" id="qtQuitar">Quitar QR</button>` : ""}
    <input type="file" id="qtFile" accept="image/*" class="hidden">`);
  $("#qtSubir").onclick = () => {
    const inp = $("#qtFile");
    inp.onchange = async () => {
      const f = inp.files[0]; if (!f) return;
      toast("Guardando QR…");
      try {
        const dataUrl = await comprimirImg(f, 900, 0.82);
        const { error } = await sb.rpc("set_team_qr", { p_url: dataUrl, p_team: t.id });
        if (error) return fail(error);
        toast(`QR de ${t.nombre} guardado`);
        invalidarCache("teams"); teamsConQr = null; await loadTeams(true);
        sheetQrTeamAdmin(teamsCache.find(x => x.id === t.id));
      } catch (e) { fail(e); }
    };
    inp.click();
  };
  const bq = $("#qtQuitar");
  if (bq) bq.onclick = async () => {
    const { error } = await sb.rpc("set_team_qr", { p_url: null, p_team: t.id });
    if (error) return fail(error);
    toast(`QR de ${t.nombre} quitado`, "warn");
    invalidarCache("teams"); teamsConQr = null; await loadTeams(true);
    sheetQrTeamAdmin(teamsCache.find(x => x.id === t.id));
  };
}

/* ============================================================
   MI TEAM (jefe crea/gestiona RRPPs)
   ============================================================ */
async function screenTeam() {
  if (me.rol === "admin") return screenTeamAdmin();
  const [{ data: rosterRaw, error }, { data: myTeam }] = await Promise.all([
    sb.rpc("roster_mi_team", { p_club: club }),   // rrpps por team EFECTIVO en este boliche
    sb.from("teams").select("invite_code, nombre").eq("id", me.team_id).single()
  ]);
  if (error) throw error;   // lo muestra conPantalla con Reintentar
  const gente = rosterRaw || [];
  const inviteUrl = myTeam?.invite_code ? `${location.origin}${location.pathname}?invite=${myTeam.invite_code}` : null;
  $("#main").innerHTML = `
    ${pgHead({ ey: "Team", t: "Mi team", s: `${gente.length} relacionadores` })}
    ${inviteUrl ? `<div class="assigned" style="display:flex;justify-content:space-between;align-items:center;gap:10px;margin-bottom:14px">
      <span style="min-width:0;overflow:hidden;text-overflow:ellipsis;white-space:nowrap">Link de registro: ${inviteUrl}</span>
      <button class="checkin" id="btnInv" style="flex-shrink:0">Copiar</button></div>` : ""}
    ${me.team_id && ev ? `<div class="ph-actions" style="margin-bottom:14px;justify-content:flex-start">
      <button class="ghost" id="dgMan">Manillas prepagadas</button>
      <button class="ghost" id="dgPue">Compras en puerta</button></div>` : ""}
    <div class="row2">
      <div class="field"><label>Nombre</label><input id="nuNombre"></div>
      <div class="field"><label>Usuario</label><input id="nuUser" autocapitalize="none"></div>
    </div>
    <div class="field"><label>Contraseña (mín. 6)</label><input id="nuPass"></div>
    <button class="btn primary" id="btnNU">Crear relacionador</button>
    <div class="sh-h" style="margin-top:20px">Relacionadores</div>
    <div>${gente.map(g => `
      <div class="list-row">
        <div class="r-l"><span class="relmark">${esc(g.nombre[0])}</span><span>${esc(g.nombre)}<br><small style="color:var(--text-3)">@${esc(g.usuario)}</small></span></div>
        <div style="display:flex;gap:6px">
          <button class="checkin" style="background:var(--surface-3);color:var(--text-2);border-color:var(--line-2)" data-reset="${g.id}" data-nom="${esc(g.nombre)}">Clave</button>
          <button class="checkin" style="${g.activo ? "background:var(--danger-bg);color:var(--danger);border-color:rgba(251,113,133,.35)" : ""}"
            data-tg="${g.id}" data-act="${g.activo}">${g.activo ? "Desactivar" : "Activar"}</button>
        </div>
      </div>`).join("") || `<div class="empty">Todavía no creaste relacionadores.</div>`}
    </div>`;
  const bi = $("#btnInv");
  if (bi) bi.onclick = async () => {
    try { await navigator.clipboard.writeText(inviteUrl); } catch (e) {
      const ta = document.createElement("textarea"); ta.value = inviteUrl;
      document.body.appendChild(ta); ta.select();
      try { document.execCommand("copy"); } catch (e2) { } ta.remove();
    }
    toast("Link copiado — mandalo a tus RRPPs");
  };
  const dm = $("#dgMan"); if (dm) dm.onclick = () => copyDesgloseTeam(me.team_id, myTeam?.nombre || "mi team", "manillas");
  const dp = $("#dgPue"); if (dp) dp.onclick = () => copyDesgloseTeam(me.team_id, myTeam?.nombre || "mi team", "puerta");
  $("#btnNU").onclick = async () => {
    const nombre = $("#nuNombre").value.trim(), usuario = $("#nuUser").value.trim(), clave = $("#nuPass").value;
    if (!nombre || !usuario || clave.length < 6) return toast("Completá nombre, usuario y clave (6+)", "warn");
    $("#btnNU").disabled = true;
    const { data: { session } } = await sb.auth.getSession();
    const res = await fetch(`${CFG.SUPABASE_URL}/functions/v1/crear-usuario`, {
      method: "POST",
      headers: { "Content-Type": "application/json", Authorization: `Bearer ${session.access_token}` },
      body: JSON.stringify({ usuario, nombre, clave, rol: "rrpp", team_id: me.team_id })
    });
    $("#btnNU").disabled = false;
    const out = await res.json();
    if (!res.ok) return toast(out.error || "Error", "warn");
    toast(`Usuario @${usuario} creado`);
    screenTeam();
  };
  qsa("#main [data-tg]").forEach(b => b.onclick = async () => {
    const { error: e2 } = await sb.from("profiles").update({ activo: b.dataset.act !== "true" }).eq("id", b.dataset.tg);
    if (e2) return fail(e2);
    screenTeam();
  });
  qsa("#main [data-reset]").forEach(b => b.onclick = () => resetClave(b.dataset.reset, b.dataset.nom));
}

/* pestaña Team para ADMIN: todos los teams del boliche + crear/editar */
/* Team abierto en el acordeón; null = todos cerrados. */
let tmAbierto = null;
/* Y dentro del team abierto, qué persona tiene la ficha desplegada. */
let tmPersona = null;

async function screenTeamAdmin() {
  const [, , , tq] = await Promise.all([
    loadTeams(), loadEfectivos(true), loadTeamsConQr(true),
    // El teléfono no viene en teams_efectivos: lo resuelve la misma RPC que
    // usa la pantalla de WhatsApp del equipo. No hace falta backend nuevo.
    sb.rpc("telefonos_equipo", { p_club: club })
  ]);
  const telDe = {};
  ((tq && tq.data) || []).forEach(x => { if (x.telefono) telDe[x.user_id] = x.telefono; });
  const teams = teamsDelClub();
  // cuenta por el team EFECTIVO del boliche: alguien puede estar en un team
  // acá y en otro en el otro boliche
  const cnt = {};
  Object.values(efectivosCache).forEach(e => {
    if (e.team_id && ["rrpp", "jefe"].includes(e.rol)) cnt[e.team_id] = (cnt[e.team_id] || 0) + 1;
  });
  const inv = t => `${location.origin}${location.pathname}?invite=${t.invite_code}`;
  $("#main").innerHTML = `
    ${pgHead({ ey: "Gestión", t: "Teams", s: `<b>${teams.length}</b> ${teams.length === 1 ? "team" : "teams"} en ${esc(clubNombre(club))}` })}
    <div class="cta-zona" id="tmZona">
      <button class="btn primary cta-abrir" id="btnNTOpen">Crear team</button>
    </div>
    <div class="tm-lista">${teams.map(t => {
      // Miembros de este team, con el jefe primero: es a quien se busca.
      const gente = Object.values(efectivosCache)
        .filter(g => g.team_id === t.id && ["rrpp", "jefe"].includes(g.rol))
        .sort((a, b) => (a.rol === "jefe" ? -1 : b.rol === "jefe" ? 1 : 0)
          || (a.nombre || "").localeCompare(b.nombre || ""));
      const abierto = tmAbierto === t.id;
      return `
      <div class="tm-card${abierto ? " abierto" : ""}">
        <button class="tm-head" data-tm="${t.id}" aria-expanded="${abierto}">
          <span class="relmark">${esc((t.nombre.replace(/^team /i, "")[0] || "T").toUpperCase())}</span>
          <span class="tm-nm">${esc(t.nombre)}</span>
          <span class="tm-cnt">${cnt[t.id] || 0}</span>
          <svg viewBox="0 0 24 24" class="ic tm-ch${abierto ? " abierto" : ""}"><path d="M6 9l6 6 6-6"/></svg>
        </button>
        ${abierto ? `<div class="tm-body">
          ${gente.length ? `<div class="tm-gente">${gente.map(g => {
            const ab = tmPersona === g.user_id;
            const tel = telDe[g.user_id] || "";
            return `
            <div class="tm-p-w${ab ? " abierto" : ""}">
              <button class="tm-p" data-per="${g.user_id}" aria-expanded="${ab}">
                <span class="tm-p-ini">${esc((g.nombre || "?")[0].toUpperCase())}</span>
                <span class="tm-p-nm">${esc(g.nombre)}</span>
                ${g.rol === "jefe" ? `<span class="tm-p-jefe">Jefe</span>` : ""}
                <svg viewBox="0 0 24 24" class="ic tm-p-ch${ab ? " abierto" : ""}"><path d="M6 9l6 6 6-6"/></svg>
              </button>
              ${ab ? `<div class="tm-ficha">
                <div class="tm-d">
                  <span class="tm-d-k">Nombre</span>
                  <span class="tm-d-v">${esc(g.nombre)}</span>
                </div>
                <div class="tm-d">
                  <span class="tm-d-k">Celular</span>
                  ${tel
                    ? `<a class="tm-d-tel" href="https://wa.me/${esc(tel)}" target="_blank" rel="noopener">${esc(telLindo(tel))}</a>`
                    : `<span class="tm-d-v tm-d-falta">Sin cargar</span>`}
                </div>
                <div class="tm-d-acc">
                  ${tel ? `<button class="ghost" data-per-cp="${esc(tel)}">Copiar número</button>` : ""}
                  <button class="ghost" data-tel-ed="${g.user_id}" data-tel-nom="${esc(g.nombre)}" data-tel-val="${esc(tel)}">${tel ? "Editar celular" : "Cargar celular"}</button>
                </div>
              </div>` : ""}
            </div>`;
          }).join("")}</div>`
            : `<div class="empty">Todavía no hay nadie en este team.</div>`}
          <div class="tm-acc">
            <button class="ghost" data-desg="${t.id}" data-nom="${esc(t.nombre)}">Ver desglose</button>
            <button class="ghost" data-inv="${inv(t)}">Copiar link</button>
            <button class="ghost" data-qr-tm="${t.id}">QR${teamsConQr?.has(t.id) ? " ✓" : ""}</button>
            <button class="ghost" data-edit-tm="${t.id}">Editar</button>
          </div>
        </div>` : ""}
      </div>`;
    }).join("") || `<div class="empty">Sin teams en este boliche. Creá el primero con el botón de arriba.</div>`}
    </div>`;
  // Tocar el team despliega su gente. Uno abierto a la vez: la lista se
  // recorre buscando a alguien, no comparando varios a la vez.
  qsa("#main [data-tm]").forEach(b => b.onclick = () => {
    tmAbierto = tmAbierto === b.dataset.tm ? null : b.dataset.tm;
    tmPersona = null;             // cerrar el team cierra la ficha de adentro
    screenTeam();
  });

  /* Segundo nivel: tocar a alguien despliega su ficha. Uno a la vez, igual
     que los teams, para que la lista no se estire de golpe. */
  qsa("#main [data-per]").forEach(b => b.onclick = () => {
    tmPersona = tmPersona === b.dataset.per ? null : b.dataset.per;
    screenTeam();
  });
  qsa("#main [data-per-cp]").forEach(b => b.onclick = () => {
    copyText(telLindo(b.dataset.perCp));
    toast("Número copiado");
  });
  /* Editar el celular abre el mismo editor que la pantalla de WhatsApp del
     equipo; al guardar vuelve acá con la ficha todavía abierta. */
  qsa("#main [data-tel-ed]").forEach(b => b.onclick = () =>
    editarTelDe(b.dataset.telEd, b.dataset.telNom, b.dataset.telVal,
      () => { closeSheet(); screenTeam(); }));

  /* Crear team con el mismo patrón que el resto: botón que despliega el
     formulario donde está, no un bloque siempre abierto. */
  const zonaT = $("#tmZona");
  const botonNT = () => {
    zonaT.innerHTML = `<button class="btn primary cta-abrir" id="btnNTOpen">Crear team</button>`;
    conectarNT();
  };
  function conectarNT() {
    const b = zonaT.querySelector("#btnNTOpen");
    if (!b) return;
    b.onclick = () => {
      zonaT.innerHTML = `
        <div class="cta-form">
          <div class="cta-form-h">
            <span class="cta-form-t">Crear team</span>
            <button class="cta-form-x" id="ntCerrar" aria-label="Cerrar">
              <svg viewBox="0 0 24 24" class="ic"><path d="M6 6l12 12M18 6L6 18"/></svg>
            </button>
          </div>
          <div class="field">
            <label for="ntNombre">Nombre</label>
            <input id="ntNombre" placeholder="Team A.Q" autocomplete="off">
          </div>
          <button class="btn primary" id="btnNT">Crear team</button>
        </div>`;
      zonaT.querySelector("#ntCerrar").onclick = botonNT;
      const inp = zonaT.querySelector("#ntNombre");
      zonaT.querySelector("#btnNT").onclick = async () => {
        const nombre = inp.value.trim();
        if (!nombre) return toast("Poné el nombre del team", "warn");
        const { error } = await sb.from("teams").insert({ nombre, clubs: [club] });
        if (error) return toast(error.message.includes("duplicate") || error.code === "23505"
          ? `Ya existe un team llamado "${nombre}"` : error.message, "warn");
        invalidarCache("teams");
        toast("Team creado"); screenTeam();
      };
      try { if (!window.matchMedia("(hover: none)").matches) inp.focus(); } catch { /* sin foco */ }
    };
  }
  conectarNT();
  qsa("#main [data-inv]").forEach(b => b.onclick = async () => {
    try { await navigator.clipboard.writeText(b.dataset.inv); }
    catch (e) { const ta = document.createElement("textarea"); ta.value = b.dataset.inv; document.body.appendChild(ta); ta.select(); try { document.execCommand("copy"); } catch (e2) { } ta.remove(); }
    toast("Link del team copiado");
  });
  qsa("#main [data-edit-tm]").forEach(b => b.onclick = () =>
    sheetEditarTeam(teamsCache.find(t => t.id === b.dataset.editTm), () => { closeSheet(); screenTeam(); }));
  qsa("#main [data-qr-tm]").forEach(b => b.onclick = () =>
    sheetQrTeamAdmin(teamsCache.find(t => t.id === b.dataset.qrTm)));
  qsa("#main [data-desg]").forEach(b => b.onclick = () =>
    sheetDesgloseTeam(b.dataset.desg, b.dataset.nom));
}

/* ============================================================
   EVENTOS (admin: crear + listas del evento)
   ============================================================ */
let evPanelOpen = false;
/* Los pasados arrancan cerrados: el Inicio tiene que abrir limpio, con
   el evento activo como único protagonista. */
let evPasOpen = false;

/* Fila de evento en las listas de Inicio. Compacta a propósito: la
   tarjeta grande está reservada al evento activo. */
function filaEvento(e) {
  const [dia, resto] = fmtF(e.fecha).split(",");
  return `
  <div class="ev-fila">
    <button class="ev-fecha" data-sel="${e.id}">
      <span class="ev-dia">${esc((dia || "").trim())}</span>
      <span class="ev-num">${esc((resto || "").trim())}</span>
    </button>
    <button class="ev-fila-nm" data-sel="${e.id}">
      <span class="ev-fila-t">${esc(e.nombre)}</span>
      <span class="ev-fila-e">
        ${enCurso(e) ? '<span class="estado-vivo">En vivo</span>' : `<span class="tag-estado ${esc(e.estado)}">${esc(ESTADO_EV[e.estado] || e.estado)}</span>`}
        ${e.publicado === false ? '<span class="ev-borr sm">Borrador</span>' : ""}
      </span>
    </button>
    <div class="ev-fila-acc">
      <button class="ghost" data-edit="${e.id}">Editar</button>
      ${e.publicado === false ? `<button class="ghost pub" data-pub="${e.id}" data-nom="${esc(e.nombre)}">Publicar</button>` : ""}
      <button class="ghost ev-mas" data-mas-ev="${e.id}" data-nom="${esc(e.nombre)}" data-cerrado="${e.estado === "cerrado" ? 1 : 0}" title="Más acciones" aria-label="Más acciones">⋯</button>
    </div>
  </div>`;
}
async function screenEventos() {
  // arranque de cero: sin ningún boliche creado todavía, no hay nada que
  // listar — el admin crea el primero desde acá mismo
  if (!club) {
    $("#main").innerHTML = `
      ${pgHead({ ey: "Inicio", t: "Bienvenido", s: "Todavía no hay ningún boliche creado.",
        acc: me.rol === "admin" ? `<button class="btn primary" id="irBoliches">${ico("mas")}Crear boliche</button>` : "" })}
      <div class="empty">${me.rol === "admin"
        ? "Creá el primer boliche para empezar a cargar eventos."
        : "Pedile a un administrador que cree el primer boliche."}</div>`;
    $("#irBoliches") && ($("#irBoliches").onclick = sheetBoliches);
    return;
  }
  // el listado y los contadores del héroe viajan JUNTOS (eran dos tandas)
  const [{ data: evs, error }, rsHero] = await conDatos("inicio", () => Promise.all([
    sb.from("eventos").select("*")
      .eq("club_id", club).order("fecha", { ascending: false }).limit(30),
    ev ? sb.rpc("resumen_evento", { p_evento: ev.id }) : Promise.resolve({ data: null })
  ]));
  if (error) throw error;   // lo muestra conPantalla con Reintentar
  /* Tarjeta protagonista del evento activo: el estado de la noche y las
     acciones para gestionarla. Sin datos de plata — eso vive en Pagos y
     Reporte; acá manda la operación. */
  let hero = "";
  if (ev) {
    // los cuatro contadores vienen juntos (antes eran 4 consultas)
    const rs = rsHero?.data;
    const ca = +rs?.anotados || 0, ce = +rs?.ingresaron || 0,
          qr = +rs?.entradas || 0, mv = +rs?.mesas || 0;
    const hoyISO = new Date().toLocaleDateString("sv-SE");
    hero = `
    <section class="ev-card">
      <div class="ev-card-h">
        <span class="ev-mk">${clubMarkHTML(club)}</span>
        ${enCurso(ev) ? '<span class="estado-vivo">En vivo</span>'
          : ev.fecha === hoyISO ? '<span class="estado-hoy">Hoy</span>'
          : `<span class="tag-estado ${esc(ev.estado)}">${esc(ESTADO_EV[ev.estado] || ev.estado)}</span>`}
        ${ev.publicado === false ? '<span class="ev-borr">Borrador · sólo lo ves vos</span>' : ""}
      </div>

      <h2 class="ev-nm">${esc(ev.nombre)}</h2>
      <p class="ev-meta">
        <span>${fmtF(ev.fecha)}</span><span class="ev-pt"></span>
        <span>${(ev.hora_inicio || "21:00").slice(0, 5)}–${(ev.hora_fin || "06:00").slice(0, 5)}</span>
        ${ev.precio_manilla ? `<span class="ev-pt"></span><span>Manilla ${fmtBs(ev.precio_manilla)} Bs</span>` : ""}
      </p>

      <div class="kps kps-4 ev-kps">
        ${kpi({ tag: "button", attrs: 'data-go="listas"', ic: "grupo", k: "Anotados en listas", v: ca })}
        ${kpi({ tag: "button", attrs: 'data-go="entradas"', ic: "ticket", k: "Entradas", v: qr })}
        ${kpi({ tag: "button", attrs: 'data-go="mesas"', ic: "sofa", k: "Mesas", v: mv })}
        ${kpi({ tag: "button", attrs: 'data-go="listas"', ic: "check", k: "Ingresaron", v: ce, tono: "ok" })}
      </div>

      <div class="ev-acc">
        <button class="ghost" data-listas="${ev.id}">${ico("lista_")}Listas</button>
        <button class="ghost" data-edit="${ev.id}">${ico("ajustes")}Editar</button>
        <button class="ghost" data-dis="${ev.id}">${ico("imagen")}Diseño${ev.ticket_url ? " ✓" : ""}</button>
        <button class="ghost ev-mas" id="evMas" title="Más acciones" aria-label="Más acciones">${ico("puntos")}</button>
      </div>
    </section>`;
  }

  // Pasados: cerrados o con fecha anterior a hoy. El evento activo no se
  // repite abajo, que es lo que ensuciaba la lista.
  const hoyStr = new Date().toLocaleDateString("sv-SE");
  const pasados = (evs || []).filter(e =>
    e.id !== (ev && ev.id) && (e.estado === "cerrado" || e.fecha < hoyStr));
  const otros = (evs || []).filter(e =>
    e.id !== (ev && ev.id) && !(e.estado === "cerrado" || e.fecha < hoyStr));

  $("#main").innerHTML = `
    ${pgHead({ ey: esc(clubNombre(club)), t: "Inicio", s: "Tu próximo evento y los anteriores.",
      acc: `${me.plataforma ? `<button class="btn ghost2" id="irBoliches" title="Administrar boliches">${ico("mapa")}Boliches</button>` : ""}
        <button class="btn primary" id="evNuevoBtn">${ico("mas")}Crear nuevo evento</button>` })}

    ${hero || `<div class="empty">Todavía no hay ningún evento en este boliche.<br>
      <span style="color:var(--text-muted);font-size:12.5px">Creá el primero con el botón de arriba.</span></div>`}

    ${otros.length ? `
    <section class="in-sec">
      <h2 class="in-h2">Próximos</h2>
      <div class="ev-lista">${otros.map(filaEvento).join("")}</div>
    </section>` : ""}

    <section class="in-sec">
      <button class="ev-acc-h" id="evPasH" aria-expanded="${evPasOpen}" aria-controls="evPasBody">
        <span class="ev-acc-t">Eventos pasados</span>
        <span class="ev-acc-n">${pasados.length}</span>
        <svg viewBox="0 0 24 24" class="ic ev-acc-ch ${evPasOpen ? "abierto" : ""}"><path d="M6 9l6 6 6-6"/></svg>
      </button>
      <div class="ev-acc-b ${evPasOpen ? "abierto" : ""}" id="evPasBody">
        ${pasados.length ? `<div class="ev-lista">${pasados.map(filaEvento).join("")}</div>`
          : `<div class="empty">Todavía no hay eventos cerrados.</div>`}
      </div>
    </section>

    <div class="lst-card ${evPanelOpen ? "open" : ""}" id="evNewCard" ${evPanelOpen ? "" : "hidden"}>
      <div class="lst-head"><span class="lst-nm">Crear evento</span><span class="lst-cnt">${evPanelOpen ? "cerrar" : "abrir"}</span></div>
      ${evPanelOpen ? `<div class="lst-body">
        <div class="row2">
          <div class="field"><label>Nombre</label><input id="evNombre" placeholder="PECULIAR"></div>
          <div class="field"><label>Fecha</label><input id="evFecha" type="date"></div>
        </div>
        <div class="row2">
          <div class="field"><label>Precio manilla (Bs)</label><input id="evPrecio" type="number" value="60"></div>
          <div class="field"><label>Comisión rrpp (Bs)</label><input id="evCut" type="number" value="15" title="Bs fijos por manilla ingresada — no depende del precio de la manilla"></div>
          <div class="field"><label>% boliche</label><input id="evPct" type="number" value="50"></div>
        </div>
        <div class="field"><label>¿Cómo se venden las prepagadas?</label>
          <div class="seg"><button type="button" class="segbtn on" data-evmodo="unico">Precio único</button><button type="button" class="segbtn" data-evmodo="fases">Por fases</button></div>
          <small style="color:var(--text-3)" id="evModoHint">Todas al mismo precio, como siempre.</small></div>
        <button class="btn primary" id="btnEv">Crear evento</button>
      </div>` : ""}
    </div>
    <input type="file" id="disFile" accept="image/png,image/jpeg,image/webp" class="hidden">`;
  $("#irBoliches") && ($("#irBoliches").onclick = sheetBoliches);
  // El CTA de la cabecera abre el mismo formulario de siempre.
  $("#evNuevoBtn").onclick = () => {
    evPanelOpen = !evPanelOpen;
    screenEventos().then(() => {
      const c = $("#evNewCard");
      if (evPanelOpen && c) c.scrollIntoView({ behavior: "smooth", block: "center" });
    });
  };
  $("#evNewCard").querySelector(".lst-head").onclick = () => { evPanelOpen = !evPanelOpen; screenEventos(); };

  // Acordeón de pasados. Se repinta en vez de animar altura: la lista es
  // corta y así el estado vive en un solo lugar.
  $("#evPasH").onclick = () => { evPasOpen = !evPasOpen; screenEventos(); };

  /* Acciones secundarias del evento activo: las que no deben competir con
     Listas, Editar y Diseño. Cerrar va acá por ser la destructiva. */
  const bm = $("#evMas");
  if (bm && ev) bm.onclick = () => {
    sheet(`<div class="sh-h">${esc(ev.nombre)}</div>
      <div class="mas-lista">
        <button class="mas-op" data-op="avisos">${IC.tag}<span>Avisos del equipo</span></button>
        ${ev.estado !== "cerrado" ? `<button class="mas-op peligro" data-op="cerrar">${IC.shield}<span>Cerrar evento</span></button>` : ""}
      </div>`);
    document.querySelectorAll("#sheetBody [data-op]").forEach(b => b.onclick = async () => {
      const op = b.dataset.op;
      closeSheet();
      // "Anotar cliente en lista" se quitó de acá: anotar gente vive en
      // Accesos → Invitados (sheetNuevoCliente sigue existiendo para
      // quien lo use desde allá).
      if (op === "avisos") return sheetAvisos();
      if (op === "cerrar") {
        if (!await confirmar({
          titulo: `Cerrar ${ev.nombre}`,
          detalle: [fmtF(ev.fecha)],
          aviso: "El evento deja de estar activo: no se podrán anotar invitados ni vender más. Los datos quedan guardados.",
          accion: "Cerrar evento"
        })) return;
        const { error: ec } = await sb.from("eventos").update({ estado: "cerrado" }).eq("id", ev.id);
        if (ec) return fail(ec);
        toast(`${ev.nombre} cerrado`, "warn");
        await loadEventos(); screenEventos();
      }
    });
  };

  /* Mismo menú para las filas de la lista. */
  qsa("#main [data-mas-ev]").forEach(b => b.onclick = () => {
    const id = b.dataset.masEv, nom = b.dataset.nom, cerrado = b.dataset.cerrado === "1";
    sheet(`<div class="sh-h">${esc(nom)}</div>
      <div class="mas-lista">
        ${cerrado ? "" : `<button class="mas-op" data-fop="cerrar">${IC.shield}<span>Cerrar evento</span></button>`}
        <button class="mas-op peligro" data-fop="borrar">${IC.clock}<span>Eliminar evento</span></button>
      </div>`);
    document.querySelectorAll("#sheetBody [data-fop]").forEach(x => x.onclick = async () => {
      const op = x.dataset.fop;
      closeSheet();
      if (op === "cerrar") {
        if (!await confirmar({ titulo: `Cerrar ${nom}`, aviso: "El evento deja de estar activo. Los datos quedan guardados.", accion: "Cerrar evento" })) return;
        const { error: ec } = await sb.from("eventos").update({ estado: "cerrado" }).eq("id", id);
        if (ec) return fail(ec);
        toast(`${nom} cerrado`, "warn");
        await loadEventos(); screenEventos();
      }
      if (op === "borrar") {
        // Reutiliza el mismo camino que el botón de borrar de siempre.
        const f = document.querySelector(`#main [data-del-ev="${id}"]`);
        if (f) f.click();
        else toast("Abrí el evento para eliminarlo", "warn");
      }
    });
  });
  qsa("#main [data-sel]").forEach(b => b.onclick = async () => {
    ev = evs.find(e => e.id === b.dataset.sel) || ev;
    await loadListaTipos(); subRealtime();
    screenEventos();
  });
  /* Publicar un borrador. Doble toque a propósito: es la acción que lo hace
     visible para los 229 relacionadores y no se deshace. */
  let armPub = null;
  qsa("#main [data-pub]").forEach(b => b.onclick = async () => {
    if (armPub !== b.dataset.pub) {
      armPub = b.dataset.pub;
      b.textContent = "¿Publicar? Tocá de nuevo";
      setTimeout(() => { if (armPub === b.dataset.pub) { armPub = null; b.textContent = "Publicar"; } }, 4000);
      return;
    }
    armPub = null; b.disabled = true;
    const { data, error: ep } = await sb.rpc("publicar_evento", { p_evento: b.dataset.pub });
    b.disabled = false;
    if (ep) return fail(ep);
    toast(`${data.nombre} publicado · ${data.listas} lista(s) y ${data.mesas} mesa(s) ya visibles`);
    await loadEventos(); screenEventos();
  });
  qsa("#main [data-del-ev]").forEach(b => b.onclick = async () => {
    // Borrar un evento arrastra sus listas, entradas y mesas. Se cuenta
    // qué hay dentro para que la magnitud quede a la vista antes de decidir.
    const id = b.dataset.delEv;
    const cnt = async (tabla) => (await sb.from(tabla)
      .select("id", { count: "exact", head: true }).eq("evento_id", id)).count || 0;
    const [regs, tks, mesas] = await Promise.all([cnt("registros"), cnt("entradas"), cnt("mesas")]);
    const vendidas = mesas ? (await sb.from("mesas").select("id", { count: "exact", head: true })
      .eq("evento_id", id).neq("estado", "disponible")).count || 0 : 0;

    const detalle = [];
    if (regs) detalle.push(`${regs} anotado${regs === 1 ? "" : "s"} en listas`);
    if (tks) detalle.push(`${tks} entrada${tks === 1 ? "" : "s"} emitida${tks === 1 ? "" : "s"}`);
    if (mesas) detalle.push(`${mesas} mesa${mesas === 1 ? "" : "s"}${vendidas ? ` · ${vendidas} con venta` : ""}`);
    if (!detalle.length) detalle.push("Sin listas, entradas ni mesas cargadas");

    if (!await confirmar({
      titulo: `Eliminar evento ${b.dataset.nom}`,
      detalle,
      aviso: (regs || tks || vendidas)
        ? "Se borra todo el contenido del evento, incluidas las ventas registradas. No se puede deshacer."
        : "El evento se elimina por completo. No se puede deshacer.",
      accion: "Eliminar evento"
    })) return;

    const { data, error: e2 } = await sb.rpc("eliminar_evento", { p_evento: b.dataset.delEv });
    if (e2) return fail(e2);
    toast(`Evento "${data.nombre}" eliminado`, "warn");
    if (ev && ev.id === b.dataset.delEv) ev = null;
    await loadEventos(); screenEventos();
  });
  let evModo = "unico";
  qsa("#main [data-evmodo]").forEach(b => b.onclick = () => {
    evModo = b.dataset.evmodo;
    qsa("#main [data-evmodo]").forEach(o => o.classList.toggle("on", o === b));
    $("#evModoHint").textContent = evModo === "fases"
      ? "Al crearlo se abren las fases para que cargues cada tanda con su precio y stock."
      : "Todas al mismo precio, como siempre.";
  });
  const bev = $("#btnEv");
  if (bev) bev.onclick = async () => {
    const nombre = $("#evNombre").value.trim(), fecha = $("#evFecha").value;
    if (!nombre || !fecha) return toast("Nombre y fecha", "warn");
    const { data: nuevo, error: e2 } = await sb.from("eventos").insert({
      club_id: club, nombre, fecha,
      precio_manilla: +$("#evPrecio").value || 60, pct_boliche: +$("#evPct").value || 50,
      cut_rrpp: +$("#evCut").value || 15
    }).select().single();
    if (e2) return fail(e2);
    // listas por defecto para que el evento nazca usable (editables en "Listas")
    const { data: lsNuevas } = await sb.from("lista_tipos").insert([
      { evento_id: nuevo.id, nombre: "Invitados", orden: 0 },
      { evento_id: nuevo.id, nombre: "Free Cover Girls", orden: 1 }
    ]).select();
    // los cupos especiales de cada lista se arrastran del evento anterior
    for (const l of (lsNuevas || [])) await sb.rpc("heredar_cupos_lista", { p_lista: l.id });
    // hereda el plano de mesas del último evento del boliche (para que no haya que rehacerlo)
    const { data: nMesas } = await sb.rpc("heredar_mesas", { p_hacia: nuevo.id });
    toast(nMesas
      ? `Borrador creado · ${nMesas} mesas heredadas. Solo lo ves vos hasta que lo publiques`
      : "Borrador creado con listas Invitados y Free Cover Girls. Solo lo ves vos hasta que lo publiques");
    await loadEventos(); screenEventos();
    // si eligió venta por fases, se abre directo el armado de tandas: crear el
    // evento y después ir a buscar dónde configurarlas era el paso que se perdía
    if (evModo === "fases") sheetFases(nuevo.id, nombre, "crear");
  };
  // "Nuevo cliente" y "Avisos" pasaron al menú ⋯ del evento; los botones
  // sueltos ya no existen, pero el flujo se conserva intacto.
  qsa("#main [data-go]").forEach(b => b.onclick = () => { tab = b.dataset.go; setTab(); renderTab(); });
  qsa("#main [data-cerrar]").forEach(b => b.onclick = async () => {
    const { error: e2 } = await sb.from("eventos").update({ estado: "cerrado" }).eq("id", b.dataset.cerrar);
    if (e2) return fail(e2);
    await loadEventos(); screenEventos();
  });
  qsa("#main [data-listas]").forEach(b => b.onclick = () => sheetListas(b.dataset.listas));
  qsa("#main [data-edit]").forEach(b => b.onclick = () => sheetEditarEvento(b.dataset.edit));
  qsa("#main [data-dis]").forEach(b => b.onclick = () => {
    const inp = $("#disFile");
    inp.onchange = async () => {
      const file = inp.files[0]; if (!file) return;
      toast("Subiendo diseño…");
      // el ticket se arma sobre 1080 px de ancho: subir más grande no mejora
      // nada y lo descarga cada persona que genera una entrada
      const blob = await dataUrlToBlob(await comprimirImg(file, 1080, 0.88));
      const path = `${b.dataset.dis}.jpg`;
      const { error: e1 } = await sb.storage.from("disenos").upload(path, blob, { upsert: true, contentType: "image/jpeg" });
      if (e1) return fail(e1);
      const { data: { publicUrl } } = sb.storage.from("disenos").getPublicUrl(path);
      const { error: e2 } = await sb.from("eventos").update({ ticket_url: publicUrl + "?v=" + Date.now() }).eq("id", b.dataset.dis);
      if (e2) return fail(e2);
      toast("Diseño de entrada actualizado");
      await loadEventos(); screenEventos();
    };
    inp.click();
  });
}

/* Nuevo cliente en 2 pasos (flujo Fourvenius): 1 elegir lista · 2 nombre + acompañantes */
async function sheetNuevoCliente() {
  if (!ev) return;
  if (!listaTipos.length) return toast("El evento no tiene listas — crealas con el botón Listas", "warn");
  const { data: regs } = await traerTodo(() => sb.from("registros").select("id, lista_tipo_id").eq("evento_id", ev.id).order("id"));
  const cnt = {}; (regs || []).forEach(r => cnt[r.lista_tipo_id] = (cnt[r.lista_tipo_id] || 0) + 1);
  sheet(`
    <div class="sh-h">Nuevo cliente<span class="r-sub">paso 1 · elegí la lista</span></div>
    <div>${listaTipos.map(l => `
      <button class="nc-lista" data-nc="${l.id}">
        <span>${esc(l.nombre)}</span>
        <span class="nc-cnt">${cnt[l.id] || 0}</span>
      </button>`).join("")}</div>`);
  document.querySelectorAll("#sheetBody [data-nc]").forEach(b => b.onclick = () => paso2(b.dataset.nc));
  function paso2(ltId) {
    const lt = listaTipos.find(l => l.id === ltId);
    $("#sheetBody").innerHTML = `
      <div class="sh-h"><button class="nc-back" id="ncBack" aria-label="Volver">${ico("atras")}</button>${esc(lt.nombre)}<span class="r-sub">paso 2 · nombres</span></div>
      <div class="field"><label>Nombres — un nombre completo por línea</label>
        <textarea id="ncNom" rows="4" autocomplete="off" placeholder="Andre Queirolo&#10;Jose Menacho&#10;Horacio Sandoval"></textarea></div>
      <button class="btn primary" id="ncGo">Anotar en ${esc(lt.nombre)}</button>
      <p class="hint" style="margin-top:8px">Cada persona va con su nombre completo — nada de "+1".</p>`;
    $("#ncBack").onclick = sheetNuevoCliente;
    $("#ncNom").focus();
    $("#ncGo").onclick = async () => {
      const nombres = expandNombres($("#ncNom").value);
      if (!nombres.length) return toast("Poné al menos un nombre", "warn");
      $("#ncGo").disabled = true;
      const { data, error } = await sb.rpc("registrar_lista", { p_lista: ltId, p_nombres: nombres });
      $("#ncGo").disabled = false;
      if (error) return fail(error);
      toast(`${data.insertados} anotado(s) en ${lt.nombre}`);
      if (data.duplicados && data.duplicados.length)
        toast(`Ojo: ya estaba(n) anotado(s): ${data.duplicados.join(", ")}`, "warn");
      closeSheet();
      if (tab === "eventos") screenEventos(); else renderTab();
    };
  }
}

async function sheetEditarEvento(evId) {
  const e = (await sb.from("eventos").select("*").eq("id", evId).single()).data;
  if (!e) return;
  sheet(`
    <div class="sh-h">Editar evento</div>
    <div class="row2">
      <div class="field"><label>Nombre</label><input id="eeN" value="${esc(e.nombre)}"></div>
      <div class="field"><label>Fecha</label><input id="eeF" type="date" value="${e.fecha}"></div>
    </div>
    <div class="row2">
      <div class="field"><label>Precio manilla (Bs)</label><input id="eeP" type="number" value="${e.precio_manilla}"></div>
      <div class="field"><label>% boliche</label><input id="eePct" type="number" value="${e.pct_boliche}"></div>
    </div>
    <div class="field"><label>Comisión del relacionador (Bs por manilla)</label>
      <input id="eeCut" type="number" value="${e.cut_rrpp ?? 15}">
      <small style="color:var(--text-3)">Monto fijo. No se mueve aunque cambies el precio de la manilla.</small></div>
    <div class="row2">
      <div class="field"><label>Empieza</label><input id="eeHi" type="time" value="${(e.hora_inicio || "21:00").slice(0, 5)}"></div>
      <div class="field"><label>Termina</label><input id="eeHf" type="time" value="${(e.hora_fin || "06:00").slice(0, 5)}"></div>
    </div>
    <div class="field"><label>QR válido hasta · opcional (después de esa hora el QR no ingresa)</label>
      <input id="eeQr" type="datetime-local" value="${e.entrada_hasta ? new Date(new Date(e.entrada_hasta).getTime() - new Date().getTimezoneOffset() * 60000).toISOString().slice(0, 16) : ""}"></div>
    <p class="hint" style="margin:-4px 0 14px">La hora tope para anotar en cada lista se edita desde <b>Listas</b> (o el ⋮ de cada lista) → "Anotar hasta".</p>
    <button class="btn ghost2" id="eeFases" style="margin-bottom:14px">Fases de preventa${e.venta_por_fases ? " · ACTIVADAS" : ""}</button>
    <div class="sh-h" style="font-size:14px;margin-top:6px">Cómo se venden las mesas</div>
    <div class="field"><label>Reservas</label>
      <div class="seg"><button type="button" class="segbtn ${e.permite_reserva !== false ? "on" : ""}" data-sw="res" data-v="1">Se puede reservar</button><button type="button" class="segbtn ${e.permite_reserva === false ? "on" : ""}" data-sw="res" data-v="0">Solo pagada</button></div></div>
    <div class="field"><label>Horas para pagar una reserva</label>
      <input id="eeHr" type="number" min="1" max="24" value="${e.horas_reserva ?? 3}">
      <small style="color:var(--text-3)">Cambiarlo no le corre el reloj a las reservas ya hechas.</small></div>
    <div class="field"><label>Sumar más mesas al mismo combo</label>
      <div class="seg"><button type="button" class="segbtn ${e.permite_agrupar !== false ? "on" : ""}" data-sw="agr" data-v="1">Permitido</button><button type="button" class="segbtn ${e.permite_agrupar === false ? "on" : ""}" data-sw="agr" data-v="0">Cada mesa sola</button></div></div>
    <div class="field"><label>Cuando se venden varias juntas, el combo</label>
      <div class="seg"><button type="button" class="segbtn ${e.combo_por_mesa ? "" : "on"}" data-sw="cxm" data-v="0">Se cobra una vez</button><button type="button" class="segbtn ${e.combo_por_mesa ? "on" : ""}" data-sw="cxm" data-v="1">Se cobra por mesa</button></div></div>
    <div class="field"><label>Combo</label>
      <div class="seg"><button type="button" class="segbtn ${e.combo_obligatorio !== false ? "on" : ""}" data-sw="cob" data-v="1">Obligatorio</button><button type="button" class="segbtn ${e.combo_obligatorio === false ? "on" : ""}" data-sw="cob" data-v="0">Opcional</button></div>
      <small style="color:var(--text-3)">En opcional se puede tomar una mesa sin combo: queda en 0 Bs.</small></div>
    <div class="field"><label>Estado</label><select id="eeE">
      <option value="proximo"${e.estado === "proximo" ? " selected" : ""}>Próximo</option>
      <option value="activo"${e.estado === "activo" ? " selected" : ""}>Activo (noche en curso)</option>
      <option value="cerrado"${e.estado === "cerrado" ? " selected" : ""}>Cerrado</option>
    </select></div>
    <p class="hint" style="margin:-4px 0 14px"><b>Próximo</b>: visible, se anota y se vende. <b>Activo</b>: igual, solo marca que la noche está en curso. <b>Cerrado</b>: desaparece del selector y queda en el Histórico. El día del evento aparece la etiqueta HOY sola.</p>
    <button class="btn primary" id="eeGo">Guardar cambios</button>`);
  $("#eeFases").onclick = () => sheetFases(evId, e.nombre);
  const sw = { res: e.permite_reserva !== false, agr: e.permite_agrupar !== false,
               cxm: !!e.combo_por_mesa, cob: e.combo_obligatorio !== false };
  document.querySelectorAll("#sheetBody [data-sw]").forEach(b => b.onclick = () => {
    sw[b.dataset.sw] = b.dataset.v === "1";
    document.querySelectorAll(`#sheetBody [data-sw="${b.dataset.sw}"]`)
      .forEach(x => x.classList.toggle("on", x === b));
  });
  $("#eeGo").onclick = async () => {
    const { error } = await sb.from("eventos").update({
      nombre: $("#eeN").value.trim() || e.nombre,
      fecha: $("#eeF").value || e.fecha,
      precio_manilla: +$("#eeP").value || e.precio_manilla,
      pct_boliche: +$("#eePct").value || e.pct_boliche,
      cut_rrpp: +$("#eeCut").value || 15,
      hora_inicio: $("#eeHi").value || e.hora_inicio,
      hora_fin: $("#eeHf").value || e.hora_fin,
      entrada_hasta: $("#eeQr").value ? new Date($("#eeQr").value).toISOString() : null,
      permite_reserva: sw.res,
      horas_reserva: Math.min(24, Math.max(1, +$("#eeHr").value || 1)),
      permite_agrupar: sw.agr,
      combo_por_mesa: sw.cxm,
      combo_obligatorio: sw.cob,
      estado: $("#eeE").value
    }).eq("id", evId);
    if (error) return fail(error);
    toast("Evento actualizado"); closeSheet();
    await loadEventos(); screenEventos();
  };
}

async function sheetListas(evId) {
  const e = (await sb.from("eventos").select("*").eq("id", evId).single()).data;
  const { data: lts } = await sb.from("lista_tipos").select("*").eq("evento_id", evId).order("orden");
  const cupoTxt = l => {
    const p = []; if (l.cupo_por_rrpp) p.push(l.cupo_por_rrpp + "/RRPP"); if (l.cupo_jefe) p.push(l.cupo_jefe + "/jefe"); if (l.cupo_admin) p.push(l.cupo_admin + "/admin"); if (l.cupo_total) p.push("máx " + l.cupo_total);
    return p.length ? p.join(" · ") : "sin límite";
  };
  $("#sheetBody").innerHTML = `
    <button class="btn ghost2" style="width:auto;padding:8px 14px;margin-bottom:12px" id="slBack">${ico("atras")}Volver</button>
    <div class="sh-h">Listas de ${esc(e.nombre)}</div>
    <div>${(lts || []).map((l, i) => {
      const vent = l.registro_desde || l.registro_hasta
        ? `${l.registro_desde ? "desde " + hora(l.registro_desde) + " " + fmtF(l.registro_desde.slice(0, 10)) : ""}${l.registro_hasta ? " hasta " + hora(l.registro_hasta) + " " + fmtF(l.registro_hasta.slice(0, 10)) : ""}`
        : "sin ventana";
      return `
      <div class="list-row">
        <div style="display:flex;flex-direction:column;gap:2px;margin-right:6px">
          <button class="ordbtn" data-up="${l.id}" ${i === 0 ? "disabled" : ""} title="Subir">▲</button>
          <button class="ordbtn" data-down="${l.id}" ${i === (lts.length - 1) ? "disabled" : ""} title="Bajar">▼</button>
        </div>
        <div class="r-l" style="flex:1"><span>${esc(l.nombre)}<br><small style="color:var(--text-3)">${cupoTxt(l)} · ${vent}${l.ingreso_hasta ? ` · entra hasta ${l.ingreso_hasta.slice(0, 5)}` : ""}</small></span></div>
        <div style="display:flex;gap:6px">
          <button class="checkin" data-edl="${l.id}" style="background:var(--surface-3);color:var(--text-2);border-color:var(--line-2)">Editar</button>
          <button class="checkin" data-dell="${l.id}" data-nom="${esc(l.nombre)}" style="background:var(--danger-bg);color:var(--danger);border-color:rgba(251,113,133,.35)">Borrar</button>
        </div>
      </div>`;
    }).join("") || `<div class="empty">Sin listas aún.</div>`}
    </div>
    <div class="sh-h" style="margin-top:16px">Nueva lista</div>
    <div class="row2">
      <div class="field"><label>Nombre lista</label><input id="ltNombre" placeholder="Invitados"></div>
      <div class="field"><label>Cupo por RRPP</label><input id="ltCupo" type="number" placeholder="sin límite"></div>
    </div>
    <div class="row2">
      <div class="field"><label>Cupo por jefe</label><input id="ltCupoJ" type="number" placeholder="= al de RRPP"></div>
      <div class="field"><label>Cupo por admin</label><input id="ltCupoA" type="number" placeholder="sin límite"></div>
    </div>
    <div class="row2">
      <div class="field"><label>Cupo total de la lista</label><input id="ltTot" type="number" placeholder="sin límite"></div>
      <div class="field"><label>Anotar desde · opcional</label><input id="ltDesde" type="datetime-local"></div>
    </div>
    <div class="row2">
      <div class="field"><label>Anotar hasta · opcional</label><input id="ltHasta" type="datetime-local"></div>
      <div class="field"></div>
    </div>
    <button class="btn primary" id="btnLT">Agregar lista</button>`;
  $("#sheet").classList.add("open"); $("#scrim").classList.add("show");
  $("#slBack").onclick = closeSheet;
  $("#btnLT").onclick = async () => {
    const nombre = $("#ltNombre").value.trim();
    if (!nombre) return toast("Poné el nombre de la lista", "warn");
    const d = $("#ltDesde").value, h = $("#ltHasta").value;
    const { data: nl, error: e2 } = await sb.from("lista_tipos").insert({
      evento_id: evId, nombre, cupo_por_rrpp: +$("#ltCupo").value || null, cupo_jefe: +$("#ltCupoJ").value || null, cupo_admin: +$("#ltCupoA").value || null, cupo_total: +$("#ltTot").value || null,
      registro_desde: d ? new Date(d).toISOString() : null,
      registro_hasta: h ? new Date(h).toISOString() : null,
      orden: (lts || []).length
    }).select().single();
    if (e2) return fail(e2);
    // si ya hubo una lista con este nombre en el boliche, se traen sus cupos especiales
    const { data: nHer } = await sb.rpc("heredar_cupos_lista", { p_lista: nl.id });
    toast(nHer ? `Lista agregada · ${nHer} cupo(s) especial(es) heredados` : "Lista agregada");
    await loadListaTipos();
    sheetListas(evId);
  };
  document.querySelectorAll("#sheetBody [data-edl]").forEach(b => b.onclick = () =>
    sheetEditarLista((lts || []).find(l => l.id === b.dataset.edl), evId));
  const mover = async (id, dir) => {
    const i = lts.findIndex(l => l.id === id), j = i + dir;
    if (j < 0 || j >= lts.length) return;
    const a = lts[i], b = lts[j];
    await Promise.all([
      sb.from("lista_tipos").update({ orden: b.orden }).eq("id", a.id),
      sb.from("lista_tipos").update({ orden: a.orden }).eq("id", b.id)
    ]);
    await loadListaTipos();
    sheetListas(evId);
  };
  document.querySelectorAll("#sheetBody [data-up]").forEach(b => b.onclick = () => mover(b.dataset.up, -1));
  document.querySelectorAll("#sheetBody [data-down]").forEach(b => b.onclick = () => mover(b.dataset.down, 1));
  document.querySelectorAll("#sheetBody [data-dell]").forEach(b => b.onclick = async () => {
    // Los anotados se cuentan al momento de borrar: es la consecuencia que
    // el usuario necesita ver antes de decidir.
    const { count } = await sb.from("registros")
      .select("id", { count: "exact", head: true })
      .eq("lista_tipo_id", b.dataset.dell);
    const n = count || 0;
    const { count: ing } = n ? await sb.from("registros")
      .select("id", { count: "exact", head: true })
      .eq("lista_tipo_id", b.dataset.dell).not("ingreso_at", "is", null) : { count: 0 };

    const detalle = n
      ? [`${n} anotado${n === 1 ? "" : "s"}`].concat(ing ? [`${ing} ya ingresó al evento`] : [])
      : ["Sin anotados"];

    if (!await confirmar({
      titulo: `Eliminar lista ${b.dataset.nom}`,
      detalle,
      aviso: n ? `Se borrarán también sus ${n} anotado${n === 1 ? "" : "s"}. No se puede deshacer.` : "",
      accion: "Eliminar lista"
    })) return;

    const { error: e2 } = await sb.from("lista_tipos").delete().eq("id", b.dataset.dell);
    if (e2) return fail(e2);
    toast(`Lista "${b.dataset.nom}" borrada`, "warn");
    await loadListaTipos();
    sheetListas(evId);
  });
}

function sheetEditarLista(l, evId, onDone, onBack) {
  const volver = onBack || (() => sheetListas(evId));
  const listo = onDone || (() => sheetListas(evId));
  const toLocal = ts => ts ? new Date(new Date(ts).getTime() - new Date().getTimezoneOffset() * 60000).toISOString().slice(0, 16) : "";
  sheet(`
    <button class="btn ghost2" style="width:auto;padding:8px 14px;margin-bottom:12px" id="elBack">${ico("atras")}Volver</button>
    <div class="sh-h">Editar lista</div>
    <div class="row2">
      <div class="field"><label>Nombre</label><input id="elN" value="${esc(l.nombre)}"></div>
      <div class="field"><label>Cupo por RRPP</label><input id="elC" type="number" value="${l.cupo_por_rrpp ?? ""}" placeholder="sin límite"></div>
    </div>
    <div class="row2">
      <div class="field"><label>Cupo por jefe</label><input id="elCJ" type="number" value="${l.cupo_jefe ?? ""}" placeholder="= al de RRPP"></div>
      <div class="field"><label>Cupo por admin</label><input id="elCA" type="number" value="${l.cupo_admin ?? ""}" placeholder="sin límite"></div>
    </div>
    <div class="row2">
      <div class="field"><label>Cupo total de la lista</label><input id="elT" type="number" value="${l.cupo_total ?? ""}" placeholder="sin límite"></div>
      <div class="field"></div>
    </div>
    <div class="row2">
      <div class="field"><label>Anotar desde · opcional</label><input id="elD" type="datetime-local" value="${toLocal(l.registro_desde)}"></div>
      <div class="field"><label>Anotar hasta · opcional</label><input id="elH" type="datetime-local" value="${toLocal(l.registro_hasta)}"></div>
    </div>
    <div class="field"><label>Ingreso permitido hasta · hora tope para entrar con esta lista</label>
      <input id="elIng" type="time" value="${l.ingreso_hasta ? l.ingreso_hasta.slice(0, 5) : ""}"></div>
    ${esListaPuerta(l) ? `
    <div class="field"><label for="elPrecio">Precio por persona · Bs</label>
      <input id="elPrecio" type="number" min="0" step="1" value="${l.precio ?? ""}" placeholder="ej. 100"></div>
    <p class="hint" style="margin:-4px 0 14px">Sólo se usa para calcular el cierre del evento: de cada persona
      de esta lista que ingresa, la mitad se descuenta de lo que se le paga al boliche. No cobra nada acá
      ni genera entradas — la plata se sigue recibiendo en la puerta como siempre.</p>` : ""}
    <p class="hint" style="margin:-4px 0 14px">Después de esa hora el QR y el check-in de esta lista se rechazan en puerta. Dejalo vacío para que entren toda la noche. Si ponés una hora anterior al inicio del evento (ej. 02:00), se toma como la madrugada siguiente.</p>
    <button class="btn primary" id="elGo">Guardar</button>
    <div class="sh-h" style="margin-top:20px">Cupos especiales<span class="r-sub">personas con más lugares</span></div>
    <p class="hint" style="margin:-4px 0 10px">El cupo de acá manda sobre el general. Ejemplo: la lista da 1 invitado a cada relacionador, pero a una persona puntual le das 3.</p>
    <div id="elCupos"><div class="empty">Cargando…</div></div>`);
  $("#elBack").onclick = volver;
  renderCuposLista(l);
  $("#elGo").onclick = async () => {
    const nombre = $("#elN").value.trim();
    if (!nombre) return toast("Poné el nombre", "warn");
    const d = $("#elD").value, h = $("#elH").value;
    const campos = {
      nombre, cupo_por_rrpp: +$("#elC").value || null, cupo_jefe: +$("#elCJ").value || null, cupo_admin: +$("#elCA").value || null, cupo_total: +$("#elT").value || null,
      registro_desde: d ? new Date(d).toISOString() : null,
      registro_hasta: h ? new Date(h).toISOString() : null,
      ingreso_hasta: $("#elIng").value || null
    };
    const inpP = $("#elPrecio");
    if (inpP) {
      const v = inpP.value.trim();
      if (v !== "" && +v < 0) return toast("El precio no puede ser negativo", "warn");
      campos.precio = v === "" ? null : +v;
    }
    let { error } = await sb.from("lista_tipos").update(campos).eq("id", l.id);
    // La columna de precio es opcional en la base: si todavía no se creó, se
    // guarda todo lo demás y se avisa, en vez de perder la edición entera.
    if (error && sinColumnaPrecio(error)) {
      PRECIO_PUERTA_OK = false;
      delete campos.precio;
      ({ error } = await sb.from("lista_tipos").update(campos).eq("id", l.id));
      if (!error) {
        toast("Lista actualizada · el precio no se guardó: falta la columna en la base", "warn");
        await loadListaTipos();
        return listo();
      }
    }
    if (error) return fail(error);
    toast("Lista actualizada");
    await loadListaTipos();
    listo();
  };
}

/* cupos especiales de una lista: quién tiene más lugares que el resto */
async function renderCuposLista(l) {
  const cont = $("#elCupos"); if (!cont) return;
  const [{ data: cupos }, { data: gente }, { data: fijos }] = await Promise.all([
    sb.from("cupo_rrpp").select("user_id, cupo, p:profiles!cupo_rrpp_user_id_fkey(nombre, usuario)").eq("lista_tipo_id", l.id),
    sb.rpc("roster_cupos", { p_club: club }),
    // cupos fijos del boliche para listas con este nombre (no dependen del evento)
    sb.from("cupo_permanente").select("user_id, cupo, p:profiles!cupo_permanente_user_id_fkey(nombre, usuario)")
      .eq("club_id", club).ilike("lista_nombre", (l.nombre || "").trim())
  ]);
  const lista = cupos || [], roster = gente || [], permanentes = fijos || [];
  const gral = l.cupo_por_rrpp ?? "sin límite";
  const yaTienen = new Set((lista || []).map(c => c.user_id));
  const libres = roster.filter(g => !yaTienen.has(g.id));
  // los fijos se muestran arriba y no se tocan desde acá: valen en todos los eventos
  const htmlFijos = permanentes.map(c => `
    <div class="list-row rc" style="border-color:rgba(139,92,246,.35)!important">
      <div class="r-l" style="flex:1;min-width:0"><span class="relmark">${esc((c.p?.nombre || "?")[0])}</span>
        <span class="rc-body"><span class="rc-nm">${esc(c.p?.nombre || "—")} <span class="pill" style="background:var(--accent-soft);color:var(--accent-2);font-size:10px;padding:2px 8px">FIJO</span></span>
          <span class="rc-sub"><span>@${esc(c.p?.usuario || "")} · <b style="color:var(--accent-2)">${c.cupo}</b> siempre, en todos los eventos</span></span></span></div>
    </div>`).join("");
  cont.innerHTML = htmlFijos + (lista.length ? lista.map(c => `
    <div class="list-row rc">
      <div class="r-l" style="flex:1;min-width:0"><span class="relmark">${esc((c.p?.nombre || "?")[0])}</span>
        <span class="rc-body"><span class="rc-nm">${esc(c.p?.nombre || "—")}</span>
          <span class="rc-sub"><span>@${esc(c.p?.usuario || "")} · <b style="color:var(--accent-2)">${c.cupo}</b> en vez de ${gral}</span></span></span></div>
      <button class="checkin" data-delcupo="${c.user_id}" title="Quitar cupo especial" style="background:var(--surface-3);color:var(--text-3);border-color:var(--line-2);padding:8px 11px">✕</button>
    </div>`).join("")
    : (htmlFijos ? "" : `<div class="empty">Todos con el cupo general (${gral}).</div>`))
    + (libres.length ? `<button class="btn ghost2" id="elAddCupo" style="margin-top:8px">+ Dar cupo especial a alguien</button>
      <div id="elCupoForm"></div>` : "");

  document.querySelectorAll("#elCupos [data-delcupo]").forEach(b => b.onclick = async () => {
    const { error } = await sb.from("cupo_rrpp").delete().eq("lista_tipo_id", l.id).eq("user_id", b.dataset.delcupo);
    if (error) return fail(error);
    toast("Cupo especial quitado", "warn");
    renderCuposLista(l);
  });

  const add = $("#elAddCupo");
  if (add) add.onclick = () => {
    add.style.display = "none";
    $("#elCupoForm").innerHTML = `
      <div class="row2" style="margin-top:8px">
        <div class="field"><label>Persona</label><select id="elCupoWho">${libres.map(g =>
          `<option value="${g.id}">${esc(g.nombre)} · ${esc(g.team)}</option>`).join("")}</select></div>
        <div class="field"><label>Cuántos puede anotar</label><input id="elCupoN" type="number" min="0" value="${(l.cupo_por_rrpp || 1) + 2}"></div>
      </div>
      <button class="btn primary" id="elCupoGo">Guardar cupo especial</button>`;
    $("#elCupoGo").onclick = async () => {
      const uid = $("#elCupoWho").value, n = +$("#elCupoN").value;
      if (!uid || isNaN(n) || n < 0) return toast("Elegí persona y cantidad", "warn");
      const { error } = await sb.from("cupo_rrpp").upsert({ lista_tipo_id: l.id, user_id: uid, cupo: n });
      if (error) return fail(error);
      toast(`Cupo especial guardado · ${n} lugares`);
      renderCuposLista(l);
    };
  };
}
/* Cerrar el panel: tocando fuera, con la × o con Escape. Antes sólo se
   cerraba tocando fuera y un QR abierto se sentía atrapado. Lo de abajo
   no se toca: al cerrar queda igual, con su búsqueda, filtros y scroll. */
/* Confirmación de un toque para acciones de fila.
 *
 * Quitar un invitado o anular una entrada pasa muchas veces por noche y
 * se rehace fácil. Un diálogo por cada uno frena el trabajo; alcanza con
 * que el botón pida el segundo toque.
 *
 * Sólo puede haber una acción armada a la vez: tocar otra fila desarma la
 * anterior, y a los 4 segundos vuelve sola a su estado normal.
 *
 * Para lo irreversible —cerrar un evento, borrar con cascada— se sigue
 * usando confirmar(), que explica las consecuencias.
 */
let _armado = null, _armadoT = null;
function desarmar() {
  if (!_armado) return;
  _armado.el.textContent = _armado.txt;
  _armado.el.classList.remove("armado");
  clearTimeout(_armadoT);
  _armado = null;
}
function dobleToque(el, textoArmado = "¿?") {
  if (_armado && _armado.el === el) { desarmar(); return true; }  // segundo toque
  desarmar();                                                     // otra fila: se desarma
  _armado = { el, txt: el.textContent };
  el.textContent = textoArmado;
  el.classList.add("armado");
  _armadoT = setTimeout(desarmar, 4000);
  return false;
}
// Cambiar de sección o abrir un panel cancela lo que estuviera armado.
document.addEventListener("click", e => {
  // Se ignora el clic que acaba de armar: llega acá en la misma pasada y
  // lo desarmaría antes de que el usuario pueda dar el segundo toque.
  if (!_armado || e.target.closest("[data-delr],[data-del-tk],[data-anular]")) return;
  desarmar();
});

function cerrarPanel() {
  if (telObliga) return toast("Cargá tu número de WhatsApp para seguir", "warn");
  $("#sheet").classList.remove("open");
  $("#scrim").classList.remove("show");
}
$("#scrim").onclick = cerrarPanel;
$("#sheetX") && ($("#sheetX").onclick = cerrarPanel);
document.addEventListener("keydown", e => {
  if (e.key === "Escape" && $("#sheet").classList.contains("open")) cerrarPanel();
});

/* ============================================================
   MESAS · planimetría por evento (venta + editor admin)
   ============================================================ */
let mesas = [], planta = "alta", editMode = false, moverMesas = false, combosCache = [], teamsCache = [], rtChan = null;

function subRealtime() {
  if (rtChan) { sb.removeChannel(rtChan); rtChan = null; }
  if (!ev) return;
  rtChan = sb.channel("rt-" + ev.id)
    // varias ventas seguidas llegan como varios eventos: se agrupan en un solo
    // re-dibujo para no disparar una tanda de queries por cada uno
    .on("postgres_changes", { event: "*", schema: "public", table: "mesas", filter: "evento_id=eq." + ev.id },
      () => { if (tab === "mesas" && !editMode) redibujarMesas(); })
    .on("postgres_changes", { event: "*", schema: "public", table: "entradas", filter: "evento_id=eq." + ev.id },
      // en la puerta hay varios porteros escaneando: cada validación ajena
      // llegaba como un evento y disparaba una consulta. Se agrupan.
      () => { if (me.rol === "portero" && tab === "escaner") refrescarContadorScan(); })
    .subscribe();
}

let rtMesasT = null, pausaPlano = false;
function redibujarMesas() {
  // mientras se confirman pagos en tanda, no tiene sentido redibujar el plano
  // después de cada uno: se hace una sola vez al cerrar
  if (pausaPlano) return;
  clearTimeout(rtMesasT);
  rtMesasT = setTimeout(() => { if (tab === "mesas" && !editMode) screenMesas(); }, 700);
}

/* El barrido de reservas vencidas no hace falta en cada render: alcanza con
   correrlo cada tantos minutos. En noche de evento hay mucha gente mirando el
   plano a la vez y esto era un request extra por cada re-dibujo. */
let ultimoBarrido = 0;
const BARRIDO_MS = 3 * 60 * 1000;
async function barrerReservasVencidas() {
  if (Date.now() - ultimoBarrido < BARRIDO_MS) return;
  ultimoBarrido = Date.now();
  try {
    const { data: lib } = await sb.rpc("liberar_reservas_vencidas", { p_evento: ev.id });
    const mias = (lib?.liberadas || []).filter(x => x.vendido_por === me.id);
    if (mias.length) toast(`Se liberó ${mias.map(x => x.etiqueta).join(", ")} — la reserva venció sin pago`, "warn");
  } catch (e) { /* si falla, el plano carga igual */ }
}
async function loadMesas() {
  await barrerReservasVencidas();
  const { data } = await sb.from("mesas").select("*").eq("evento_id", ev.id).order("etiqueta");
  mesas = data || [];
}
/* combos, teams y fondos casi no cambian durante la noche: se guardan por
   boliche y se vuelven a pedir solo cuando el admin los edita (invalidarCache). */
let fondosCache = {};
let cacheClub = { combos: null, teams: null, fondos: null, sinTope: null };
function invalidarCache(que) {
  if (que) cacheClub[que] = null;
  else cacheClub = { combos: null, teams: null, fondos: null, sinTope: null };
}
async function loadFondos(forzar) {
  if (!forzar && cacheClub.fondos === club) return;
  const { data } = await sb.from("plano_fondos").select("planta,url").eq("club_id", club);
  fondosCache = {};
  (data || []).forEach(f => fondosCache[f.planta] = f.url);
  cacheClub.fondos = club;
  // se mide cada fondo de antemano: al cambiar de piso el plano ya nace con
  // la proporción del dibujo y no salta cuando termina de cargar la imagen
  await Promise.all(Object.values(fondosCache).filter(u => u && !propFondo[u]).map(u => new Promise(ok => {
    const i = new Image(); i.crossOrigin = "anonymous";
    i.onload = () => { propFondo[u] = (i.naturalWidth / i.naturalHeight).toFixed(4); ok(); };
    i.onerror = ok; i.src = u;
    setTimeout(ok, 2500);   // sin señal no se traba la pantalla: se ajusta al cargar
  })));
}
async function loadCombos(forzar) {
  if (!forzar && cacheClub.combos === club && combosCache.length) return;
  const { data } = await sb.from("combos").select("*").eq("club_id", club).order("precio");
  combosCache = data || [];
  cacheClub.combos = club;
}
async function loadTeams(forzar) {
  if (!forzar && cacheClub.teams === club && teamsCache.length) return;
  // NUNCA traer qr_cobro_url acá: son imágenes guardadas como texto y suman
  // ~800 KB. Esto se pide al entrar a Mesas, a Listas y al cambiar de boliche;
  // en la red del boliche eran varios segundos de pantalla congelada.
  // Quien necesita el QR lo pide para ese team puntual (sheetQrTeamAdmin).
  const { data } = await sb.from("teams")
    .select("id,nombre,activo,jefe_id,clubs,invite_code")
    .eq("activo", true).order("nombre");
  teamsCache = data || [];
  cacheClub.teams = club;
}
/* qué teams tienen QR cargado, sin bajar las imágenes (solo para el ✓ de la lista) */
let teamsConQr = null;
async function loadTeamsConQr(forzar) {
  if (!forzar && teamsConQr) return teamsConQr;
  const { data } = await sb.from("teams").select("id").not("qr_cobro_url", "is", null);
  teamsConQr = new Set((data || []).map(t => t.id));
  return teamsConQr;
}
/* team y rol EFECTIVOS de cada persona en ESTE boliche.
   Alguien puede estar en un team distinto en cada boliche donde opera:
   siempre manda el del boliche que se está mirando, nunca el team base
   del perfil. */
let efectivosCache = {}, efectivosClub = null;
async function loadEfectivos(forzar) {
  if (!forzar && efectivosClub === club) return;
  const { data } = await sb.rpc("teams_efectivos", { p_club: club });
  efectivosCache = {};
  (data || []).forEach(r => efectivosCache[r.user_id] = r);
  efectivosClub = club;
}
const teamDe = uid => efectivosCache[uid]?.team_id || "";
const teamNomDe = uid => efectivosCache[uid]?.team || "Sin team";

const EST_LABEL = { disponible: "Libre", reservada: "Reservada", pagada: "Pagada", ocupada: "Ocupada" };
/* pisos por club: los que tengan mesas; si no hay, defaults del boliche */
const FLOOR_LABEL = { piso1: "Piso 1", piso2: "Piso 2", piso3: "Piso 3", alta: "Planta alta", baja: "Planta baja" };
const FLOOR_ORDER = ["piso1", "piso2", "piso3", "alta", "baja"];
const pisosDe = () => {
  const presentes = [...new Set(mesas.map(m => m.planta))];
  const p = FLOOR_ORDER.filter(f => presentes.includes(f));
  return p.length ? p : ["alta", "baja"];
};
/* zoom del plano: null = automático (en el celular arranca acercado para
   que las mesas se lean; en escritorio, ajustado al ancho) */
const ESTADO_EV = { proximo: "Próximo", activo: "Activo", cerrado: "Cerrado", borrador: "Borrador" };
const ZOOMS = [1, 1.25, 1.5, 1.75, 2, 2.5, 3];
let planoZoom = null, planoX = null;   // planoX: centro visible, 0–1
const propFondo = {};                  // url del fondo → ancho/alto de la imagen
const zoomPlano = () => planoZoom ?? (innerWidth < 700 ? 1.75 : 1);
async function screenMesas() {
  await Promise.all([loadMesas(), loadCombos(), loadTeams(), loadFondos()]);
  const pisos = pisosDe();
  if (!pisos.includes(planta)) planta = pisos[0];
  const enPlanta = mesas.filter(m => m.planta === planta);
  const oc = mesas.filter(m => m.estado !== "disponible");
  const esPortero = me.rol === "portero";   // seguridad: solo ve nombre y combo, sin plata
  // mis reservas pendientes de pago (cada una se vence en su propia hora)
  const misRes = mesas.filter(x => x.estado === "reservada" && x.vendido_por === me.id && x.reservada_at);
  // mesas cobradas que esperan el visto bueno del admin (la contabilidad del día después)
  const porVerif = mesas.filter(x => x.estado === "pagada" && !x.pago_verificado && +x.precio > 0);
  // El vencimiento viaja en la mesa (reserva_vence_at). No se recalcula acá:
  // las reservas hechas cuando la ventana era de 6 h conservan sus 6 h, y
  // cambiar la ventana no le mueve el plazo a nadie que ya reservó.
  const vence = m => hora(new Date(m.reserva_vence_at || new Date(m.reservada_at).getTime() + horasReserva() * 36e5));
  $("#main").innerHTML = `
    ${pgHead({ ey: "Salón", t: "Mesas",
      s: `<b>${oc.length}</b> de <b>${mesas.length}</b> ${esPortero ? "ocupadas" : "vendidas"}${
          !esPortero && oc.length ? ` · <b>Bs ${fmtBs(oc.reduce((a, m) => a + (+m.precio || 0), 0))}</b>` : ""}${pisos.length < 2 ? ` · ${esc(FLOOR_LABEL[planta] || planta)}` : ""}`,
      acc: `<div class="ms-h-acc" id="msAcc"></div>` })}
    ${misRes.length ? `<div class="hint" style="color:var(--warn);margin:0 0 10px">Reservas sin pago: ${misRes.map(x => `${esc(x.etiqueta)} vence ${vence(x)}`).join(" · ")} — confirmá el pago o se liberan solas.</div>` : ""}
    <div class="floors${pisos.length < 2 ? " solo" : ""}" style="margin:0 0 12px"><span class="ind" style="width:calc(${(100 / pisos.length).toFixed(2)}% - 5px);transform:translateX(${pisos.indexOf(planta) * 100}%)"></span>
      ${pisos.map(f => `<button data-f="${f}" class="${planta === f ? "on" : ""}">${FLOOR_LABEL[f] || f}</button>`).join("")}</div>
    <div class="ms-acc">
      ${/* Afuera lo que se usa durante el evento: confirmar pagos, el
            registro de combos y guardar el plano. Adentro del ⋯ queda la
            configuración previa —editar el plano y los combos—, que se
            toca una vez y no en el medio de la noche. */""}
      ${!editMode && me.rol === "admin" && porVerif.length
        ? `<button class="ghost ms-urgente" id="btnConta">Confirmar pagos (${porVerif.length})</button>` : ""}
      ${!editMode && oc.length && !esPortero ? `<button class="ghost" id="btnRegM">Registro de combos</button>` : ""}
      ${!editMode ? `<button class="ghost" id="btnPlano">Guardar imagen</button>` : ""}
      ${me.rol === "admin" && editMode ? `
        <button class="ghost editing-on" id="btnEd">Listo</button>
        <button class="ghost${moverMesas ? " ms-mover" : ""}" id="btnLock">${moverMesas ? "Mover: activado" : "Posiciones bloqueadas"}</button>
        <button class="ghost" id="btnAddM">Agregar mesa</button>
        <button class="ghost" id="btnAddL">Agregar lounge</button>
        <button class="ghost" id="btnFondo">Fondo del ${FLOOR_LABEL[planta] || planta}${fondosCache[planta] ? " ✓" : ""}</button>
        ${!mesas.length ? `<button class="ghost" id="btnCopy">Copiar de otro evento</button>` : ""}
      ` : ""}
      ${/* Sólo el admin configura el plano: para el resto quedaría vacío. */""}
      ${!editMode && me.rol === "admin" ? `<button class="ghost ev-mas" id="msMas" title="Configuración del plano" aria-label="Configuración del plano">⋯</button>` : ""}
    </div>
    <div class="plano">
    <div class="canvas-wrap" id="cvWrap">
      <div class="canvas ${editMode ? "editmode" : ""}" id="cv2" style="--z:${zoomPlano()}${propFondo[fondosCache[planta]] ? `;aspect-ratio:${propFondo[fondosCache[planta]]}` : ""}">
        ${fondosCache[planta] ? `<img class="cv-fondo" src="${esc(fondosCache[planta])}" alt="" crossorigin="anonymous">` : `<div class="watermark">${FLOOR_LABEL[planta] || planta}</div>`}
      </div>
    </div>
    <div class="zoom" role="group" aria-label="Zoom del plano">
      <button data-zoom="-1" aria-label="Alejar" title="Alejar">${ico("menos")}</button>
      <button data-zoom="0" class="zoom-v" aria-label="Ajustar al ancho" title="Ajustar al ancho">${Math.round(zoomPlano() * 100)}%</button>
      <button data-zoom="1" aria-label="Acercar" title="Acercar">${ico("mas")}</button>
    </div>
    </div>
    <input type="file" id="fondoFile" accept="image/*" class="hidden">
    <div class="legend">
      <span><i class="sw libre"></i>Libre</span>
      <span><i class="sw reservada"></i>Reservada</span>
      <span><i class="sw pagada"></i>Pagada</span>
      <span><i class="sw ocupada"></i>Ocupada</span>
      <span class="hint">${editMode ? (moverMesas ? "Arrastrá para acomodar · tocá para editar" : "Posiciones bloqueadas — activá Mover para arrastrar · tocá para editar") : esPortero ? "Tocá una mesa para ver el nombre y su combo" : "Tocá una mesa para vender o gestionar"}</span>
    </div>`;
  const cv2 = $("#cv2");
  /* Con fondo, el plano toma la proporción de la imagen: así el dibujo no
     se estira y las mesas (en % del plano) caen sobre su lugar. */
  const imgF = cv2.querySelector(".cv-fondo");
  if (imgF) {
    const ajustar = () => {
      if (!imgF.naturalWidth) return;
      propFondo[imgF.getAttribute("src")] = (imgF.naturalWidth / imgF.naturalHeight).toFixed(4);
      cv2.style.aspectRatio = propFondo[imgF.getAttribute("src")];
      window.ScrollTrigger?.refresh();
    };
    if (imgF.complete) ajustar(); else imgF.addEventListener("load", ajustar, { once: true });
  }
  enPlanta.forEach(m => {
    const d = document.createElement("div");
    const libre = m.estado === "disponible", narrow = m.w < 14;
    const sinVerif = m.estado === "pagada" && !m.pago_verificado;
    d.className = "chip " + (libre ? "free " + (m.categoria === "lounge" ? "l" : "m") : m.categoria) + (narrow ? " narrow" : "") + " e-" + m.estado + (sinVerif ? " no-verif" : "");
    d.style.cssText = `left:${m.x}%;top:${m.y}%;width:${m.w}%` + (m.h ? `;height:${m.h}%` : "");
    // nombre completo en el chip: la foto del plano se manda a planimetría
    const nm = libre ? "Libre" : (m.cliente || "").trim();
    const team = m.team_id ? teamsCache.find(t => t.id === m.team_id) : null;
    d.innerHTML = `<span class="id">${esc(m.etiqueta)}</span><span class="nm">${esc(nm)}</span>` +
      (libre ? "" : `<span class="st-dot ${m.estado}${sinVerif ? " no-verif" : ""}" title="${sinVerif ? "pagada · por verificar" : EST_LABEL[m.estado]}"></span>`) +
      (team ? `<span class="relmark" style="position:absolute;top:-9px;left:-7px;width:19px;height:19px;font-size:9.5px;background:var(--warn)" title="${esc(team.nombre)}">${esc(team.nombre.replace("Team ", "")[0])}</span>` : "");
    if (editMode && me.rol === "admin") {
      if (moverMesas) dragMesa(d, m, cv2);
      else d.onclick = () => sheetMesaEdit(m);
    } else d.onclick = () => sheetMesa(m);
    cv2.appendChild(d);
  });
  /* Zoom: el plano escala entero (mesas en % del plano) y se recorre
     deslizando. Al cambiar el zoom se conserva el punto que se miraba. */
  const wrap = $("#cvWrap");
  qsa("#main [data-zoom]").forEach(b => b.onclick = () => {
    const d = +b.dataset.zoom, z0 = zoomPlano();
    const i = ZOOMS.indexOf(z0);
    const z = d === 0 ? 1 : ZOOMS[Math.max(0, Math.min(ZOOMS.length - 1, (i < 0 ? ZOOMS.findIndex(x => x >= z0) : i) + d))];
    const cx = (wrap.scrollLeft + wrap.clientWidth / 2) / wrap.scrollWidth;
    planoZoom = z;
    $("#cv2").style.setProperty("--z", z);
    qsa("#main .zoom-v").forEach(v => v.textContent = Math.round(z * 100) + "%");
    wrap.scrollLeft = cx * wrap.scrollWidth - wrap.clientWidth / 2;
  });
  // El plano se repinta solo (tiempo real): se vuelve al mismo lugar que
  // se estaba mirando. La primera vez arranca centrado.
  if (wrap) {
    wrap.scrollLeft = planoX == null
      ? (wrap.scrollWidth - wrap.clientWidth) / 2
      : planoX * wrap.scrollWidth - wrap.clientWidth / 2;
    wrap.addEventListener("scroll", () => {
      planoX = (wrap.scrollLeft + wrap.clientWidth / 2) / wrap.scrollWidth;
    }, { passive: true });
  }
  qsa("#main .floors button").forEach(b => b.onclick = () => { planta = b.dataset.f; screenMesas(); });
  /* Acciones secundarias del plano. Eran hasta ocho botones al mismo
     nivel; ahora sólo queda visible lo que pide acción y el resto vive
     acá. Cada opción llama exactamente a lo mismo que antes. */
  const bmas = $("#msMas");
  if (bmas) bmas.onclick = () => {
    // Configuración del evento: se arma una vez, antes de la noche.
    const op = [];
    if (me.rol === "admin") op.push(["editar", "Editar plano", IC.mesa]);
    if (me.rol === "admin") op.push(["combos", "Combos", IC.tag]);

    sheet(`<div class="sh-h">Mesas<span class="r-sub">${FLOOR_LABEL[planta] || planta}</span></div>
      <div class="mas-lista">${op.map(([k, l, ico]) =>
        `<button class="mas-op" data-msop="${k}">${ico}<span>${esc(l)}</span></button>`).join("")}</div>`);

    document.querySelectorAll("#sheetBody [data-msop]").forEach(b => b.onclick = () => {
      const k = b.dataset.msop;
      closeSheet();
      if (k === "editar") { editMode = true; moverMesas = false; return screenMesas(); }
      if (k === "combos") return sheetCombos();
    });
  };

  const be = $("#btnEd"); if (be) be.onclick = () => { editMode = !editMode; moverMesas = false; screenMesas(); };
  const blk = $("#btnLock"); if (blk) blk.onclick = () => { moverMesas = !moverMesas; screenMesas(); };
  const bm = $("#btnAddM"); if (bm) bm.onclick = () => nuevaMesa("mesa");
  const bl = $("#btnAddL"); if (bl) bl.onclick = () => nuevaMesa("lounge");
  const bc = $("#btnCombos"); if (bc) bc.onclick = sheetCombos;
  const brm = $("#btnRegM"); if (brm) brm.onclick = copyRegistroMesas;
  const bct = $("#btnConta"); if (bct) bct.onclick = () => sheetContabilidad(porVerif);
  const bcp = $("#btnCopy"); if (bcp) bcp.onclick = sheetCopiar;
  const bf = $("#btnFondo");
  if (bf) bf.onclick = () => {
    const inp = $("#fondoFile");
    inp.onchange = async () => {
      const f = inp.files[0]; if (!f) return;
      bf.disabled = true; bf.textContent = "Subiendo…";
      // el fondo del plano lo baja cada persona que abre Mesas: va comprimido
      const blob = await dataUrlToBlob(await comprimirImg(f, 1400, 0.82));
      const path = `fondo-${club}-${planta}.jpg`;
      const { error: e1 } = await sb.storage.from("disenos").upload(path, blob, { upsert: true, contentType: "image/jpeg" });
      if (e1) { bf.disabled = false; return fail(e1); }
      const { data: { publicUrl } } = sb.storage.from("disenos").getPublicUrl(path);
      const { error: e2 } = await sb.from("plano_fondos").upsert({ club_id: club, planta, url: publicUrl + "?v=" + Date.now() });
      if (e2) { bf.disabled = false; return fail(e2); }
      toast(`Fondo del ${FLOOR_LABEL[planta] || planta} actualizado`);
      invalidarCache("fondos");
      screenMesas();
    };
    inp.click();
  };
  const bpl = $("#btnPlano");
  if (bpl) bpl.onclick = async () => {
    bpl.disabled = true; bpl.textContent = "Generando…";
    await guardarPlano();
    bpl.disabled = false; bpl.textContent = "Guardar imagen";
  };
}

/* Exporta el plano como imagen. Se extrajo del botón para que también lo
   use el menú de acciones: misma captura, mismo nombre de archivo. */
async function guardarPlano() {
  try {
    const url = await htmlToImage.toPng($("#cv2"), { pixelRatio: 2, backgroundColor: "#14141e", skipFonts: true, cacheBust: true });
    await guardarImagen(url, `plano-${(ev.nombre || "evento").replace(/\s+/g, "-")}-planta-${planta}.png`);
  } catch (e) { fail(e); }
}

function dragMesa(el, m, cv2) {
  el.onpointerdown = e => {
    e.preventDefault();
    try { el.setPointerCapture(e.pointerId); } catch (err) { }
    const rect = cv2.getBoundingClientRect();
    const sx = e.clientX, sy = e.clientY, ox = +m.x, oy = +m.y;
    let moved = false;
    const mv = evp => {
      const dx = (evp.clientX - sx) / rect.width * 100, dy = (evp.clientY - sy) / rect.height * 100;
      if (Math.abs(dx) + Math.abs(dy) > 0.6) moved = true;
      m.x = Math.round(Math.min(Math.max(ox + dx, 0.5), 99 - m.w) * 2) / 2;
      m.y = Math.round(Math.min(Math.max(oy + dy, 0.5), 86) * 2) / 2;
      el.style.left = m.x + "%"; el.style.top = m.y + "%";
    };
    const up = async () => {
      window.removeEventListener("pointermove", mv);
      window.removeEventListener("pointerup", up);
      if (moved) await sb.from("mesas").update({ x: m.x, y: m.y }).eq("id", m.id);
      else sheetMesaEdit(m);
    };
    window.addEventListener("pointermove", mv);
    window.addEventListener("pointerup", up);
  };
}

async function nuevaMesa(cat) {
  const n = mesas.length + 1;
  const { error } = await sb.from("mesas").insert({
    evento_id: ev.id, planta, etiqueta: "M" + n, categoria: cat,
    x: 42, y: 45, w: cat === "lounge" ? 18 : 14
  });
  if (error) return fail(error);
  toast((cat === "lounge" ? "Lounge" : "Mesa") + " agregada");
  screenMesas();
}

/* Auditoría: quién cambió qué y cuándo en este boliche. Lee audit_log,
   que llenan los triggers del servidor (db/25); la política de lectura
   deja verla solo a la plataforma y al admin del boliche. Solo lectura. */
const AUD_TIPOS = [
  ["", "Todo"], ["pagos", "Pagos"], ["entradas", "Entradas"], ["registros", "Invitados"],
  ["mesas", "Mesas"], ["profiles,club_membership", "Personas"], ["eventos", "Eventos"],
  ["teams", "Teams"], ["bar_ventas", "Barra"], ["clubs", "Boliche"],
];
const AUD_TABLA = { pagos: "Pago", entradas: "Entrada", registros: "Invitado", mesas: "Mesa", profiles: "Persona",
  club_membership: "Membresía", eventos: "Evento", teams: "Team", bar_ventas: "Venta de barra", clubs: "Boliche" };
const AUD_OP = { INSERT: ["alta", "ok"], UPDATE: ["cambio", "warn"], DELETE: ["baja", "bad"] };
const AUD_IGNORAR = new Set(["id", "updated_at", "created_at", "evento_id", "club_id"]);
const AUD_ISO = /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}/;
function audValor(v) {
  if (v === null || v === undefined || v === "") return "—";
  if (typeof v === "string" && AUD_ISO.test(v))
    return new Date(v).toLocaleString("es-BO", { day: "numeric", month: "short", hour: "2-digit", minute: "2-digit" });
  const t = typeof v === "object" ? JSON.stringify(v) : String(v);
  return t.length > 38 ? t.slice(0, 37) + "…" : t;
}
function audResumen(r) {
  const a = r.antes || {}, d = r.despues || {};
  const fila = r.op === "DELETE" ? a : d;
  const nombre = fila.nombre || fila.cliente || fila.etiqueta || fila.usuario || fila.code || fila.concepto || "";
  if (r.op !== "UPDATE") return { nombre, cambios: [] };
  const cambios = Object.keys(d)
    .filter(k => !AUD_IGNORAR.has(k) && JSON.stringify(a[k]) !== JSON.stringify(d[k]))
    .slice(0, 4).map(k => {
      // un id suelto no le dice nada a nadie: se dice qué pasó con él
      if (/_id$|_por$/.test(k)) return [k.replace(/_id$|_por$/, "").replace(/_/g, " "),
        a[k] ? "asignado" : "—", d[k] ? (a[k] ? "otro" : "asignado") : "quitado"];
      return [k.replace(/_/g, " "), audValor(a[k]), audValor(d[k])];
    });
  return { nombre, cambios };
}
async function sheetAuditoria(filtro = "") {
  sheet(`<div class="sh-h">Auditoría<span class="r-sub">${esc(clubData(club)?.nombre || club)}</span></div>
    <div class="hf-chips" style="display:flex;gap:6px;flex-wrap:wrap;margin-bottom:12px">${AUD_TIPOS.map(([k, l]) =>
      `<button class="hf-chip${k === filtro ? " on" : ""}" data-aud="${k}">${esc(l)}</button>`).join("")}</div>
    <div id="audLista">${skeleton(4)}</div>`);
  document.querySelectorAll("#sheetBody [data-aud]").forEach(b => b.onclick = () => sheetAuditoria(b.dataset.aud));
  try {
    let q = sb.from("audit_log").select("id,at,actor,tabla,op,antes,despues").eq("club_id", club)
      .order("at", { ascending: false }).limit(120);
    if (filtro) q = q.in("tabla", filtro.split(","));
    const { data, error } = await q;
    if (error) throw error;
    const ids = [...new Set((data || []).map(r => r.actor).filter(Boolean))];
    const nombres = {};
    if (ids.length) {
      const { data: ps } = await sb.from("profiles").select("id,nombre,usuario").in("id", ids);
      (ps || []).forEach(p => nombres[p.id] = p.nombre || "@" + p.usuario);
    }
    const lista = $("#audLista");
    if (!lista) return;   // la hoja se cerró o cambió mientras cargaba
    if (!data?.length) { lista.innerHTML = `<div class="empty">Sin movimientos registrados${filtro ? " de este tipo" : ""}.</div>`; return; }
    lista.innerHTML = data.map(r => {
      const { nombre, cambios } = audResumen(r);
      const [opTxt, opCls] = AUD_OP[r.op] || [r.op, ""];
      const quien = r.actor ? (nombres[r.actor] || "Alguien del equipo") : "Sistema";
      const cuando = new Date(r.at).toLocaleString("es-BO", { day: "numeric", month: "short", hour: "2-digit", minute: "2-digit" });
      return `<div class="list-row aud-row">
        <div style="min-width:0;flex:1">
          <div style="font-weight:600">${esc(AUD_TABLA[r.tabla] || r.tabla)}${nombre ? ` · ${esc(audValor(nombre))}` : ""}
            <span class="pill ${opCls}" style="margin-left:6px;font-size:10.5px">${esc(opTxt)}</span></div>
          ${cambios.map(([k, x, y]) => `<div class="aud-cambio"><span>${esc(k)}</span> ${esc(x)} → <b>${esc(y)}</b></div>`).join("")}
          <div style="font-size:12px;color:var(--text-3);margin-top:3px">${esc(quien)} · ${esc(cuando)}</div>
        </div>
      </div>`;
    }).join("") + (data.length === 120 ? `<div class="hint" style="text-align:center;margin-top:10px">Se muestran los últimos 120.</div>` : "");
  } catch (e) {
    const lista = $("#audLista");
    if (lista) lista.innerHTML = `<div class="empty">${esc(mensajeDeError(e))}</div>`;
  }
}
function sheet(html) { $("#sheetBody").innerHTML = html; $("#sheet").classList.add("open"); $("#scrim").classList.add("show"); }
function closeSheet() { $("#sheet").classList.remove("open"); $("#scrim").classList.remove("show"); }

/* ============================================================
   BUSCAR PERSONA · una consulta para toda la noche
   ============================================================
   En la puerta el problema real es "esta persona dice que está en
   lista": hay que revisar listas, entradas y mesas por separado para
   saber si es cierto. Esto las cruza en una sola búsqueda.

   No guarda nada nuevo: lee las mismas tablas que ya usan las demás
   pantallas (registros, entradas, mesas) y arma la respuesta en el
   cliente. Sin tablas paralelas ni datos duplicados.
   ============================================================ */

let buscarT = null;          // debounce
let buscarSeq = 0;           // descarta respuestas que llegan tarde
/* Nombres de quienes venden, cacheados por sesión: los resultados los
   necesitan para decir quién anotó a cada persona, y no vale pedir el
   perfil una vez por fila. */
let vendCache = {};
let vendCacheOk = false;

async function cargarVendedores() {
  if (vendCacheOk) return;
  const { data } = await sb.from("profiles").select("id, nombre");
  (data || []).forEach(p => { vendCache[p.id] = p.nombre; });
  vendCacheOk = true;
}

function abrirBuscar(inicial = "") {
  sheet(`
    <div class="sh-h">Buscar persona</div>
    <div class="bsc-campo">
      <label for="bscQ" class="sr-only">Nombre, código de entrada o mesa</label>
      <input id="bscQ" placeholder="Nombre, código de entrada o mesa…"
             autocomplete="off" autocapitalize="words" enterkeyhint="search">
    </div>
    <div id="bscRes" class="bsc-res"></div>`);

  const inp = $("#bscQ");
  inp.value = inicial;

  // En móvil el teclado tapa la hoja; conviene que el operador decida
  // cuándo abrirlo. En escritorio el foco ahorra un clic.
  if (!window.matchMedia("(hover: none)").matches) inp.focus();

  const lanzar = () => {
    clearTimeout(buscarT);
    const q = inp.value.trim();
    if (q.length < 2) {
      $("#bscRes").innerHTML = q
        ? `<div class="empty">Escribí al menos 2 letras.</div>`
        : `<div class="empty">Buscá por nombre, código de entrada (#A2F9B1) o mesa (A4).</div>`;
      return;
    }
    // Un pedido por pausa de tecleo, no por tecla.
    buscarT = setTimeout(() => correrBusqueda(q), 260);
  };

  inp.addEventListener("input", lanzar);
  inp.addEventListener("keydown", e => { if (e.key === "Enter") { clearTimeout(buscarT); correrBusqueda(inp.value.trim()); } });
  lanzar();
}

async function correrBusqueda(q) {
  if (!ev) { $("#bscRes").innerHTML = `<div class="empty">Elegí un evento para buscar.</div>`; return; }
  const seq = ++buscarSeq;
  $("#bscRes").innerHTML = skeleton(3);

  const like = `%${q.replace(/[%_]/g, "")}%`;
  const code = q.replace(/^#/, "").toUpperCase();

  try {
    // Las consultas van juntas: la puerta no puede esperar viajes en fila.
    const [, regs, tks, mesas] = await Promise.all([
      cargarVendedores(),
      sb.from("registros")
        .select("id, nombre, ingreso_at, lista_tipo_id, rrpp_id, filtro_at")
        .eq("evento_id", ev.id).ilike("nombre", like).limit(12),
      sb.from("entradas")
        .select("id, code, cliente, estado, used_at, rrpp_id, precio, fase_id")
        .eq("evento_id", ev.id).or(`cliente.ilike.${like},code.eq.${code}`).limit(12),
      sb.from("mesas")
        .select("id, etiqueta, cliente, estado, categoria, planta, precio, pago_verificado, combo_qty")
        .eq("evento_id", ev.id).or(`cliente.ilike.${like},etiqueta.ilike.${like}`).limit(12),
    ]);

    if (seq !== buscarSeq) return;   // llegó tarde: ya hay una búsqueda nueva
    pintarBusqueda(q, regs.data || [], tks.data || [], mesas.data || []);
  } catch (e) {
    if (seq !== buscarSeq) return;
    console.error(e);
    $("#bscRes").innerHTML = `<div class="empty">No se pudo buscar. Revisá la conexión.<br>
      <button class="btn ghost2" style="width:auto;margin-top:10px;padding:9px 16px" id="bscRetry">Reintentar</button></div>`;
    const r = $("#bscRetry"); if (r) r.onclick = () => correrBusqueda(q);
  }
}

function pintarBusqueda(q, regs, tks, mesas) {
  const total = regs.length + tks.length + mesas.length;
  if (!total) {
    $("#bscRes").innerHTML = `<div class="empty">Nadie con «${esc(q)}» en este evento.<br>
      <span style="color:var(--text-muted)">Probá con parte del nombre o el código de la entrada.</span></div>`;
    return;
  }

  const nomLista = id => (listaTipos.find(l => l.id === id) || {}).nombre || "Lista";
  const nomVend = id => vendCache[id] || "";

  const bloque = (titulo, filas) => filas.length
    ? `<div class="bsc-grupo"><div class="bsc-tit">${titulo} · ${filas.length}</div>${filas.join("")}</div>` : "";

  // --- invitados de lista ---
  const fRegs = regs.map(r => {
    const dentro = !!r.ingreso_at;
    return `<button class="bsc-item" data-ir-lista="${r.id}">
      <span class="bsc-ic ${dentro ? "ok" : ""}">${dentro ? "✓" : "○"}</span>
      <span class="bsc-body">
        <span class="bsc-nm">${esc(r.nombre)}${r.filtro_at ? ` <span class="flag-badge">Marcado</span>` : ""}</span>
        <span class="bsc-sub">${esc(nomLista(r.lista_tipo_id))}${nomVend(r.rrpp_id) ? ` · ${esc(nomVend(r.rrpp_id))}` : ""}</span>
      </span>
      <span class="bsc-est ${dentro ? "ok" : "pend"}">${dentro ? "Ingresó " + hora(r.ingreso_at) : "Sin ingresar"}</span>
    </button>`;
  });

  // --- entradas ---
  const EST = { valida: ["pend", "Válida"], usada: ["ok", "Usada"], anulada: ["bad", "Anulada"] };
  const fTks = tks.map(t => {
    const [cls, txt] = EST[t.estado] || ["pend", t.estado];
    return `<button class="bsc-item" data-ir-tk="${esc(t.code)}">
      <span class="code-chip">#${esc(t.code)}</span>
      <span class="bsc-body">
        <span class="bsc-nm">${esc(t.cliente)}</span>
        <span class="bsc-sub">${nomVend(t.rrpp_id) ? esc(nomVend(t.rrpp_id)) : "Entrada"}${t.precio ? ` · ${fmtBs(t.precio)} Bs` : ""}</span>
      </span>
      <span class="bsc-est ${cls}">${txt}${t.used_at ? " " + hora(t.used_at) : ""}</span>
    </button>`;
  });

  // --- mesas ---
  const fMesas = mesas.map(m => {
    const libre = !m.estado || m.estado === "disponible";
    const cls = libre ? "" : m.estado === "pagada" ? "ok" : "pend";
    return `<button class="bsc-item" data-ir-mesa="${m.id}">
      <span class="code-chip">${esc(m.etiqueta)}</span>
      <span class="bsc-body">
        <span class="bsc-nm">${esc(m.cliente || (m.categoria === "lounge" ? "Lounge libre" : "Mesa libre"))}</span>
        <span class="bsc-sub">${esc(FLOOR_LABEL[m.planta] || m.planta || "")}${m.combo_qty ? ` · ${m.combo_qty} combo${m.combo_qty === 1 ? "" : "s"}` : ""}${m.precio ? ` · ${fmtBs(m.precio)} Bs` : ""}</span>
      </span>
      <span class="bsc-est ${cls}">${libre ? "Libre" : esc(m.estado)}${!libre && m.pago_verificado === false ? " ·  sin verificar" : ""}</span>
    </button>`;
  });

  $("#bscRes").innerHTML = bloque("En listas", fRegs) + bloque("Entradas", fTks) + bloque("Mesas", fMesas);

  // Abrir el resultado lleva a la pantalla donde se resuelve, ya filtrada:
  // encontrar a la persona y actuar no deberían ser dos búsquedas.
  document.querySelectorAll("#bscRes [data-ir-lista]").forEach(b => b.onclick = () => {
    closeSheet(); tab = "listas"; setTab(); renderTab();
  });
  document.querySelectorAll("#bscRes [data-ir-tk]").forEach(b => b.onclick = () => {
    closeSheet(); tab = "entradas"; setTab(); renderTab();
    // El buscador de la pantalla de entradas queda con el código puesto.
  });
  document.querySelectorAll("#bscRes [data-ir-mesa]").forEach(b => b.onclick = () => {
    closeSheet(); tab = "mesas"; setTab(); renderTab();
  });
}

/* ---------- confirmación de acciones destructivas ----------
   Un solo patrón para toda la app. Reemplaza el "tocá otra vez", que no
   decía qué se estaba por borrar ni sus consecuencias.

   confirmar({
     titulo:  "Eliminar mesa A4",          // nombra el elemento concreto
     detalle: ["400 Bs cobrados", ...],    // por qué importa
     aviso:   "…",                         // sólo si hay plata o cascada
     accion:  "Eliminar mesa"              // el botón dice lo que hace
   }) -> Promise<boolean>

   Se resuelve en false al cancelar, tocar fuera o presionar Escape: el
   camino de salida siempre es el seguro. */
function confirmar({ titulo, detalle = [], aviso = "", accion = "Eliminar", cancelar = "Cancelar" }) {
  return new Promise(resolve => {
    const prev = document.activeElement;
    const wrap = document.createElement("div");
    wrap.className = "cfm-scrim";
    wrap.innerHTML = `
      <div class="cfm" role="alertdialog" aria-modal="true" aria-labelledby="cfmT">
        <h2 class="cfm-t" id="cfmT">${esc(titulo)}</h2>
        ${detalle.length ? `<ul class="cfm-d">${detalle.map(d => `<li>${esc(d)}</li>`).join("")}</ul>` : ""}
        ${aviso ? `<p class="cfm-w">${esc(aviso)}</p>` : ""}
        <div class="cfm-btns">
          <button class="cfm-no" type="button">${esc(cancelar)}</button>
          <button class="cfm-si" type="button">${esc(accion)}</button>
        </div>
      </div>`;
    document.body.appendChild(wrap);

    const cerrar = ok => {
      document.removeEventListener("keydown", onKey);
      wrap.classList.remove("show");
      setTimeout(() => wrap.remove(), 180);
      if (prev && prev.focus) prev.focus();
      resolve(ok);
    };
    const onKey = e => {
      if (e.key === "Escape") { e.preventDefault(); cerrar(false); }
      // El foco queda encerrado en el diálogo mientras está abierto.
      if (e.key === "Tab") {
        const f = wrap.querySelectorAll("button");
        const [a, z] = [f[0], f[f.length - 1]];
        if (e.shiftKey && document.activeElement === a) { e.preventDefault(); z.focus(); }
        else if (!e.shiftKey && document.activeElement === z) { e.preventDefault(); a.focus(); }
      }
    };

    wrap.querySelector(".cfm-no").onclick = () => cerrar(false);
    wrap.querySelector(".cfm-si").onclick = () => cerrar(true);
    wrap.onclick = e => { if (e.target === wrap) cerrar(false); };
    document.addEventListener("keydown", onKey);

    requestAnimationFrame(() => {
      wrap.classList.add("show");
      // El foco arranca en Cancelar: un Enter reflejo no borra nada.
      wrap.querySelector(".cfm-no").focus();
    });
  });
}


/* seguridad (portero): solo nombre del cliente y su combo — nada de plata */
async function sheetMesaSeguridad(m) {
  const tag = m.categoria === "lounge" ? "Lounge" : "Mesa";
  if (m.estado === "disponible") return sheet(`<div class="sh-h">${esc(m.etiqueta)} · ${tag}</div><div class="empty">Libre</div>`);
  let prim = m;
  if (m.grupo_id) {
    const { data: gm } = await sb.from("mesas").select("etiqueta,cliente,combo_id,precio").eq("grupo_id", m.grupo_id);
    const p2 = (gm || []).find(x => +x.precio > 0); if (p2) prim = p2;
  }
  const combo = combosCache.find(c => c.id === prim.combo_id);
  sheet(`
    <div class="sh-h">${esc(m.etiqueta)} · ${tag}</div>
    <div class="sh-name" style="font-family:'Space Grotesk';font-size:21px;font-weight:600;margin-bottom:4px">${esc(m.cliente || "—")}</div>
    <div class="r-sub" style="font-size:13px;color:var(--text-2)">${combo ? esc(combo.nombre) : "Sin combo"}</div>`);
}

/* venta / info de mesa */
async function sheetMesa(m) {
  if (me.rol === "portero") return sheetMesaSeguridad(m);
  const tag = m.categoria === "lounge" ? "Lounge" : "Mesa";
  if (m.estado === "disponible") {
    if (!["rrpp", "jefe", "admin"].includes(me.rol)) return;   // jefe también vende
    if (!combosCache.filter(c => c.activo).length) return toast("El admin debe crear combos primero", "warn");
    // qué puede hacer esta cuenta acá: regalar la mesa y/o cargarla a nombre de
    // otro. La base lo vuelve a validar igual; esto solo decide qué se dibuja.
    const [{ data: permMesa }, { data: posibles }] = await Promise.all([
      sb.rpc("mis_permisos_mesa", { p_evento: ev.id }),
      sb.rpc("vendedores_posibles", { p_evento: ev.id })
    ]);
    const puedeCort = !!permMesa?.cortesia, puedeANombre = !!permMesa?.a_nombre_de;
    const activos = combosCache.filter(c => c.activo);
    // Cada combo dice en qué tipos de mesa se puede vender (lo configura el admin
    // en Combos). Sin tipos marcados sirve para todas. Si se venden varias mesas
    // juntas, el combo tiene que estar habilitado para TODOS los tipos del grupo.
    const comboVale = (c, cats) => !c.categorias || !c.categorias.length || cats.every(k => c.categorias.includes(k));
    const combosPara = cats => activos.filter(c => comboVale(c, cats));
    const comboOptsHTML = cats => {
      const ok = combosPara(cats);
      if (!ok.length) return `<option value="">Ningún combo habilitado para este tipo de mesa</option>`;
      return ok.map(c =>
        `<option value="${c.id}" data-man="${c.incluye_manillas || 0}" data-precio="${c.precio}">${esc(c.nombre)} · ${fmtBs(c.precio)} Bs${c.incluye_manillas ? " · " + c.incluye_manillas + " manillas" : ""}</option>`).join("");
    };
    // otras mesas libres del mismo piso, para vender en grupo con un mismo combo
    const libresPiso = mesas.filter(x => x.planta === m.planta && x.estado === "disponible" && x.id !== m.id)
      .sort((a, b) => a.etiqueta.localeCompare(b.etiqueta, undefined, { numeric: true }));
    sheet(`
      <div class="sh-h">Vender ${esc(m.etiqueta)} · ${tag}</div>
      <div class="field"><label>Cliente</label><input id="vmCli" autocomplete="off"></div>
      <div class="field"><label>Combo${ev.combo_obligatorio === false ? " (opcional)" : ""}</label><select id="vmCombo">${
        ev.combo_obligatorio === false ? `<option value="" data-precio="0" data-man="0">Sin combo — 0 Bs</option>` : ""
      }${comboOptsHTML([m.categoria || "mesa"])}</select></div>
      <div class="field"><label>Cantidad de combos</label>
        <div class="qty"><button type="button" class="qbtn" id="vmQMinus">−</button><span class="qval" id="vmQty">1</span><button type="button" class="qbtn" id="vmQPlus">+</button>
          <span class="qtot" id="vmTotal"></span></div></div>
      ${libresPiso.length && ev.permite_agrupar !== false ? `<div class="field"><label>Sumar más mesas al mismo combo (opcional)</label>
        <div class="chip-pick">${libresPiso.map(x => `<button type="button" class="mchip" data-mplus="${x.id}">${esc(x.etiqueta)}</button>`).join("")}</div>
        <small style="color:var(--text-3)">${ev.combo_por_mesa
          ? "Cada mesa paga su propio combo."
          : "El combo se cobra una sola vez para todas las mesas seleccionadas."}</small></div>` : ""}
      ${me.rol === "rrpp" ? `
      <div class="field"><label>Botellas (opcional)</label><input id="vmBot" placeholder="Vodka, Fernet"></div>` : `
      <div class="row2">
        <div class="field"><label>Botellas (opcional)</label><input id="vmBot" placeholder="Vodka, Fernet"></div>
        <div class="field"><label>Manillas extra</label><input id="vmMan" type="number" value="0"></div>
      </div>`}
      <div class="field"><label>Nombres de las manillas <span id="vmManCount" style="color:var(--text-3)"></span></label>
        <textarea id="vmManNames" rows="2" placeholder="Uno por línea. Podés dejarlo vacío y cargarlos después."></textarea>
        <small style="color:var(--text-3)">Cada nombre genera su entrada con QR (incluida en el combo, no cobra aparte).</small></div>
      ${puedeANombre ? `<div class="field"><label>A nombre de</label>
        <select id="vmDuenio">
          <option value="">${esc(me.nombre)} (vos)</option>
          ${(posibles || []).filter(v => v.id !== me.id).map(v =>
            `<option value="${v.id}">${esc(v.nombre)}${v.team ? " · " + esc(v.team) : ""}</option>`).join("")}
        </select>
        <small style="color:var(--text-3)">La mesa y su comisión quedan de quien elijas. Se guarda que la cargaste vos.</small></div>` : ""}
      ${puedeCort ? `<div class="field"><label>Cortesía</label>
        <div class="seg"><button type="button" class="segbtn on" data-cort="0">Se cobra</button><button type="button" class="segbtn" data-cort="1">Cortesía</button></div>
        <small style="color:var(--text-3)" id="vmCortHint">Una cortesía mantiene el combo pero queda en 0 Bs y no paga comisión.</small></div>` : ""}
      <div class="field"><label>Estado</label><select id="vmEst">
        ${ev.permite_reserva === false ? "" : `<option value="reservada">Reservada — ${horasReserva()} h para pagar</option>`}
        <option value="pagada">Ya pagó</option></select>
        <small style="color:var(--text-3)" id="vmEstHint">${ev.permite_reserva === false
          ? "En este evento las mesas se venden solo pagadas."
          : `Si en ${horasReserva()} horas no se confirma el pago, la reserva se libera sola.`}</small></div>
      <div id="vmPagoBox" class="hidden">
        <div class="field"><label>¿Cómo pagó?</label>
          <div class="seg"><button type="button" class="segbtn on" data-mp="transferencia">Transferencia</button><button type="button" class="segbtn" data-mp="efectivo">Efectivo</button></div></div>
        <div id="vmCompBox">
          <button type="button" class="btn ghost2" id="vmVerQr">Ver QR para que pague</button>
          <div id="vmQrBox"></div>
          <div style="height:9px"></div>
        </div>
        <div id="vmCompPrev"></div>
        <div id="vmFotoBox">
          <button type="button" class="btn ghost2" id="vmFoto">Subir foto del comprobante</button>
          <div style="height:9px"></div>
        </div>
        <input type="file" id="vmFile" accept="image/*" class="hidden">
      </div>
      <button class="btn primary" id="vmGo">Confirmar venta</button>`);
    let qty = 1;
    // se declara acá y no junto a su botón: updCount() corre durante el armado
    // de la hoja y si la leyera antes de existir, tiraría por zona muerta.
    let esCortesia = false;
    const updCount = () => {
      const opt = $("#vmCombo").selectedOptions[0];
      const inc = +opt.dataset.man || 0, ext = +($("#vmMan")?.value || 0), precio = +opt.dataset.precio || 0;
      $("#vmManCount").textContent = `(incluye ${inc * qty + ext})`;
      $("#vmQty").textContent = qty;
      $("#vmTotal").textContent = esCortesia ? "= 0 Bs (cortesía)"
        : qty > 1 ? `= ${fmtBs(precio * qty)} Bs` : "";
    };
    $("#vmCombo").onchange = updCount; const vmMan = $("#vmMan"); if (vmMan) vmMan.oninput = updCount;
    // si la venta nace pagada: cómo pagó y, si fue transferencia, la foto
    let metodoPago = "transferencia", urlCompVenta = null;
    const esAdminV = me.rol === "admin";
    const sincPago = () => {
      const pagada = $("#vmEst").value === "pagada";
      $("#vmPagoBox").classList.toggle("hidden", !pagada);
      $("#vmEstHint").textContent = !pagada
        ? `Si en ${HORAS_RESERVA} horas no se confirma el pago, la reserva se libera sola.`
        : esAdminV ? "Queda pagada y verificada."
        : "Queda como pagada · por verificar, hasta que el admin confirme.";
      const pideFoto = pagada && metodoPago === "transferencia" && !esAdminV;
      const esTransf = pagada && metodoPago === "transferencia";
      $("#vmCompBox").classList.toggle("hidden", !esTransf);   // QR: solo si paga por transferencia
      $("#vmFotoBox").classList.toggle("hidden", !esTransf);
      $("#vmGo").textContent = pideFoto && !urlCompVenta ? "Subí el comprobante para confirmar" : "Confirmar venta";
      $("#vmGo").disabled = pideFoto && !urlCompVenta;
    };
    // el QR se muestra acá mismo para no perder lo que ya cargó en el formulario
    let qrAbierto = false;
    $("#vmVerQr").onclick = async () => {
      const box = $("#vmQrBox");
      if (qrAbierto) { box.innerHTML = ""; qrAbierto = false; $("#vmVerQr").textContent = "Ver QR para que pague"; return; }
      const { data: qrs } = await sb.from("qr_cobro").select("*").eq("club_id", club).eq("activo", true).order("orden");
      const q = (qrs || [])[0];
      if (!q) return toast("El admin todavía no cargó ningún QR de cobro", "warn");
      box.innerHTML = `
        <img src="${esc(q.url)}" alt="QR de cobro" style="width:100%;max-width:250px;display:block;margin:8px auto 6px;border-radius:12px;background:#fff;padding:9px">
        <div class="hint" style="text-align:center;margin-bottom:8px">La plata de las mesas entra siempre a <b>${esc(q.nombre)}</b>.</div>`;
      qrAbierto = true; $("#vmVerQr").textContent = "Ocultar QR";
    };
    $("#vmEst").onchange = sincPago;
    document.querySelectorAll("#vmPagoBox [data-mp]").forEach(b => b.onclick = () => {
      metodoPago = b.dataset.mp;
      document.querySelectorAll("#vmPagoBox [data-mp]").forEach(x => x.classList.toggle("on", x.dataset.mp === metodoPago));
      sincPago();
    });
    const vmFile = $("#vmFile");
    vmFile.onchange = async () => {
      const f = vmFile.files[0]; if (!f) return;
      const bf = $("#vmFoto"); bf.disabled = true; bf.textContent = "Subiendo…";
      try {
        urlCompVenta = await subirComprobanteMesa(f, m.id);
        $("#vmCompPrev").innerHTML = `<img src="${esc(urlCompVenta)}" alt="comprobante" style="width:100%;max-width:220px;display:block;margin:0 auto 10px;border-radius:12px;border:1px solid var(--line-2)">`;
        bf.textContent = "Cambiar foto";
        toast("Comprobante cargado");
      } catch (e) { fail(e); bf.textContent = "Reintentar"; }
      bf.disabled = false; sincPago();
    };
    $("#vmFoto").onclick = () => vmFile.click();
    $("#vmQMinus").onclick = () => { qty = Math.max(1, qty - 1); updCount(); };
    $("#vmQPlus").onclick = () => { qty = Math.min(20, qty + 1); updCount(); };
    updCount();
    const extraMesas = new Set();
    const catsDelGrupo = () => [...new Set([m.categoria || "mesa",
      ...[...extraMesas].map(id => mesas.find(x => x.id === id)?.categoria || "mesa")])];
    document.querySelectorAll("#sheetBody [data-mplus]").forEach(b => b.onclick = () => {
      const id = b.dataset.mplus;
      if (extraMesas.has(id)) { extraMesas.delete(id); b.classList.remove("on"); }
      else { extraMesas.add(id); b.classList.add("on"); }
      // al sumar una mesa de otro tipo, se recalculan los combos que sirven para el grupo
      const sel = $("#vmCombo"), antes = sel.value;
      sel.innerHTML = comboOptsHTML(catsDelGrupo());
      if ([...sel.options].some(o => o.value === antes)) sel.value = antes;
      updCount();
    });
    document.querySelectorAll("#sheetBody [data-cort]").forEach(b => b.onclick = () => {
      esCortesia = b.dataset.cort === "1";
      document.querySelectorAll("#sheetBody [data-cort]").forEach(x => x.classList.toggle("on", x === b));
      // una cortesía no se cobra: no hay comprobante ni método que pedir
      const pb = $("#vmPagoBox"); if (pb) pb.classList.toggle("hidden", esCortesia || $("#vmEst").value !== "pagada");
      const h = $("#vmCortHint");
      if (h) h.textContent = esCortesia
        ? "Queda en 0 Bs. No se pide comprobante ni genera comisión."
        : "Una cortesía mantiene el combo pero queda en 0 Bs y no paga comisión.";
      updCount();
    });
    $("#vmGo").onclick = async () => {
      const cli = $("#vmCli").value.trim();
      if (!cli) return toast("Nombre del cliente", "warn");
      if (!$("#vmCombo").value && ev.combo_obligatorio !== false) return toast("No hay ningún combo habilitado para este tipo de mesa. Pedile al admin que habilite uno.", "warn");
      $("#vmGo").disabled = true;
      const botellas = $("#vmBot").value.split(",").map(s => s.trim()).filter(Boolean);
      const manEx = +($("#vmMan")?.value || 0), estado = $("#vmEst").value, combo = $("#vmCombo").value || null;
      const efectivo = estado === "pagada" && metodoPago === "efectivo";
      const comp = estado === "pagada" && !esCortesia && metodoPago === "transferencia" ? urlCompVenta : null;
      let primaria, data;
      if (extraMesas.size) {
        const p = [m.id, ...extraMesas];
        const r = await sb.rpc("vender_mesa_grupo", { p_mesas: p, p_cliente: cli, p_combo: combo, p_botellas: botellas, p_manillas: manEx, p_estado: estado, p_cantidad: qty, p_comprobante: comp, p_efectivo: efectivo, p_a_nombre_de: $("#vmDuenio")?.value || null, p_cortesia: esCortesia });
        if (r.error) { $("#vmGo").disabled = false; return fail(r.error); }
        data = { etiqueta: r.data.mesas.join(" + "), precio: r.data.precio }; primaria = r.data.primaria;
      } else {
        const r = await sb.rpc("vender_mesa", { p_mesa: m.id, p_cliente: cli, p_combo: combo, p_botellas: botellas, p_manillas: manEx, p_estado: estado, p_cantidad: qty, p_comprobante: comp, p_efectivo: efectivo, p_a_nombre_de: $("#vmDuenio")?.value || null, p_cortesia: esCortesia });
        if (r.error) { $("#vmGo").disabled = false; return fail(r.error); }
        data = r.data; primaria = m.id;
      }
      const nombres = expandNombres($("#vmManNames").value);
      let ok = 0;
      for (const nm of nombres) {
        const { error: e2 } = await sb.rpc("generar_entrada", { p_evento: ev.id, p_cliente: nm, p_mesa: primaria });
        if (!e2) ok++;
      }
      $("#vmGo").disabled = false;
      if (estado === "reservada") toast(`${data.etiqueta} reservada${ok ? ` · ${ok} manilla(s) con QR` : ""} — tenés ${HORAS_RESERVA} h para confirmar el pago o se libera sola`, "warn");
      else if (!esAdminV) toast(`${data.etiqueta} pagada en ${metodoPago} · por verificar${ok ? ` · ${ok} manilla(s)` : ""}`, "warn");
      else toast(`${data.etiqueta} vendida · ${fmtBs(data.precio)} Bs${ok ? ` · ${ok} manilla(s) con QR` : ""}`);
      closeSheet(); screenMesas();
    };
  } else {
    // si es parte de un grupo, la mesa primaria (precio>0) tiene el combo y las manillas
    let grupoMesas = [m];
    if (m.grupo_id) {
      const { data: gm } = await sb.from("mesas").select("*").eq("grupo_id", m.grupo_id).order("etiqueta");
      if (gm?.length) grupoMesas = gm;
    }
    const prim = grupoMesas.find(x => +x.precio > 0) || grupoMesas[0];
    const combo = combosCache.find(c => c.id === prim.combo_id);
    const qtyC = prim.combo_qty || 1;
    const incluidas = (combo?.incluye_manillas || 0) * qtyC + (prim.manillas || 0);
    // quién vendió y su team salen del mapa de personas del boliche, que ya
    // está cargado: abrir una ficha pedía 4 consultas y ahora pide 1.
    // (importa cuando el admin repasa mesa por mesa haciendo la contabilidad)
    await loadEfectivos();
    const faltan = [prim.vendido_por, prim.pagada_por].filter(x => x && !efectivosCache[x]);
    const extra = {};
    if (faltan.length) {   // p. ej. alguien dado de baja: se busca solo en ese caso
      const { data: ps } = await sb.from("profiles").select("id,nombre").in("id", faltan);
      (ps || []).forEach(p => extra[p.id] = { nombre: p.nombre });
    }
    const quien = id => (id ? efectivosCache[id] || extra[id] || null : null);
    const { data: mans } = await sb.from("entradas").select("*").eq("mesa_id", prim.id).order("created_at");
    const vend = quien(prim.vendido_por);
    const pagBy = quien(prim.pagada_por);
    const teamVend = teamsCache.find(t => t.id === (vend?.team_id || null));
    const manList = mans || [];
    const esGrupo = grupoMesas.length > 1;
    const primForMan = prim;  // manillas se cargan/borran sobre la primaria
    const soloVer = me.rol === "jefe" && m.vendido_por !== me.id;   // jefe: solo lectura en mesas AJENAS; las suyas las gestiona
    // ver manillas: quien vendió, jefe (ver) o admin. Editar: admin o el vendedor (incluido jefe).
    const puedeMan = me.rol === "admin" || me.rol === "jefe" || m.vendido_por === me.id;
    const editMan = puedeMan && !soloVer;
    const restantes = incluidas ? Math.max(incluidas - manList.length, 0) : Infinity;
    sheet(`
      <div class="sh-h">${esGrupo ? esc(grupoMesas.map(x => x.etiqueta).join(" + ")) : esc(m.etiqueta) + " · " + tag}<span class="tag-estado ${m.estado === "pagada" ? "activo" : m.estado === "reservada" ? "proximo" : "cerrado"}">${EST_LABEL[m.estado]}</span></div>
      <div class="sh-name" style="font-family:'Space Grotesk';font-size:21px;font-weight:600;margin-bottom:4px">${esc(m.cliente || "—")}</div>
      <div class="r-sub" style="font-size:13px;color:var(--text-2)">${combo ? esc(combo.nombre) + (qtyC > 1 ? ` ×${qtyC}` : "") + " · " + fmtBs(prim.precio) + " Bs" : ""}${esGrupo ? ` · ${grupoMesas.length} mesas` : ""}${prim.manillas ? " · " + prim.manillas + " manillas extra" : ""}</div>
      ${esGrupo ? `<div class="r-sub" style="font-size:13px;color:var(--warn);margin-top:3px">Combo compartido en: ${esc(grupoMesas.map(x => x.etiqueta).join(", "))}</div>` : ""}
      ${vend?.nombre ? `<div class="r-sub" style="font-size:13px;color:var(--accent-2);margin-top:3px">Vendió: ${esc(vend.nombre)}</div>` : ""}
      ${teamVend ? `<div class="r-sub" style="font-size:13px;color:var(--accent-2);margin-top:2px">Team: ${esc(teamVend.nombre)}</div>` : ""}
      ${prim.pagada_at ? `<div class="r-sub" style="font-size:13px;color:var(--ok);margin-top:3px">Cobró: ${esc(pagBy?.nombre || "—")} · ${hora(prim.pagada_at)}</div>` : ""}
      ${m.estado === "pagada" && !prim.pago_verificado ? `<div class="r-sub" style="font-size:13px;color:var(--warn);margin-top:3px">Pago por verificar${prim.metodo_pago ? ` · cobrado en ${esc(prim.metodo_pago)}` : ""} — falta que el admin lo confirme</div>` : ""}
      ${m.estado === "pagada" && prim.pago_verificado && prim.verificado_at ? `<div class="r-sub" style="font-size:13px;color:var(--ok);margin-top:3px">✓ Pago verificado</div>` : ""}
      ${m.estado === "reservada" && (prim.reservada_at || m.reservada_at) ? `<div class="r-sub" style="font-size:13px;color:var(--warn);margin-top:3px">Vence ${hora(new Date((prim.reserva_vence_at || m.reserva_vence_at) || new Date(prim.reservada_at || m.reservada_at).getTime() + HORAS_RESERVA * 36e5))} — si no se paga, se libera sola</div>` : ""}
      ${prim.comprobante_url ? `<div style="margin-top:10px"><img src="${esc(prim.comprobante_url)}" alt="comprobante" style="width:100%;max-width:260px;border-radius:12px;border:1px solid var(--line-2);display:block"><div class="hint" style="margin-top:4px">Comprobante de pago</div></div>` : ""}
      ${prim.botellas?.length ? `<div class="r-sub" style="font-size:13px;color:var(--text-2);margin-top:2px">Botellas: ${esc(prim.botellas.join(", "))}</div>` : ""}
      ${puedeMan ? `
      <div class="sh-h" style="margin-top:16px">Manillas ${incluidas ? `<span class="r-sub">${manList.length}/${incluidas} con nombre</span>` : `<span class="r-sub">${manList.length}</span>`}</div>
      <div>${manList.map(t => `
        <div class="list-row">
          <div class="r-l" data-mtk="${t.code}" style="cursor:pointer;flex:1"><span class="r-id">#${t.code}</span><span>${esc(t.cliente)}</span></div>
          <div style="display:flex;gap:6px;align-items:center;flex-shrink:0">
            <span class="tkst ${t.estado === "usada" ? "used" : "ok"}">${t.estado === "usada" ? "ingresó" : "válida"}</span>
            ${editMan && t.estado === "valida" ? `<button class="checkin" data-del-man="${t.id}" data-nom="${esc(t.cliente)}" title="Eliminar manilla" style="background:var(--surface-3);color:var(--text-3);border-color:var(--line-2);padding:7px 10px">✕</button>` : ""}
          </div>
        </div>`).join("") || `<div class="empty">Sin manillas cargadas.</div>`}</div>
      ${editMan ? (restantes > 0 ? `
      <div class="field" style="margin-top:8px"><textarea id="mmNames" rows="2" placeholder="Agregar manillas (un nombre por línea)${incluidas ? ` — quedan ${restantes}` : ""}"></textarea></div>
      <button class="btn ghost2" id="mmAdd">Generar QR de esas manillas</button>`
      : `<div class="hint" style="margin:8px 0 4px">La mesa ya tiene sus ${incluidas} manillas con QR. Para más, editá las "manillas extra" de la mesa.</div>`) : ""}` : ""}
      <div style="height:14px"></div>
      ${soloVer ? `<div class="hint" style="text-align:center">Vista de jefe — solo lectura</div>` : `
      <button class="btn ghost2" id="mzEditar">Editar nombre y combo</button><div style="height:9px"></div>
      ${m.estado !== "pagada" ? `<button class="btn ghost2" id="mzCobrar">Mostrar QR de cobro</button><div style="height:9px"></div>` : ""}
      ${m.estado !== "pagada" ? `<button class="btn primary" id="mzPagar">Marcar pagada${esGrupo ? " (grupo)" : ""} — con comprobante</button><div style="height:9px"></div>` : ""}
      ${m.estado === "pagada" && !prim.pago_verificado && me.rol === "admin" ? `
        <button class="btn primary" id="mzVerif">✓ Confirmar que el pago entró</button><div style="height:9px"></div>
        <button class="btn danger" id="mzRech">✕ Rechazar — volver a reservada</button><div style="height:9px"></div>` : ""}
      ${m.estado !== "ocupada" ? `<button class="btn ghost2" onclick="estadoMesa('${m.id}','ocupada')">Marcar ocupada (llegaron)</button><div style="height:9px"></div>` : ""}
      <button class="btn danger" onclick="estadoMesa('${m.id}','disponible')">Liberar ${esGrupo ? "las " + grupoMesas.length + " mesas" : "mesa"}</button>`}`);
    const bEd = $("#mzEditar");
    if (bEd) bEd.onclick = () => sheetEditarMesa(m, prim, esGrupo ? grupoMesas.length : 1);
    const bCob = $("#mzCobrar");
    if (bCob) bCob.onclick = () => sheetQrMesa(m, prim, esGrupo ? grupoMesas.length : 1);
    const bPag = $("#mzPagar");
    if (bPag) bPag.onclick = () => sheetPagarMesa(m, prim, esGrupo ? grupoMesas.length : 1);
    const bVer = $("#mzVerif");
    if (bVer) bVer.onclick = async () => {
      bVer.disabled = true;
      const { error } = await sb.rpc("verificar_mesa", { p_mesa: m.id, p_ok: true });
      if (error) { bVer.disabled = false; return fail(error); }
      toast(`Pago de ${m.etiqueta} confirmado`);
      closeSheet(); screenMesas();
    };
    const bRech = $("#mzRech");
    if (bRech) bRech.onclick = async () => {
      if (!await confirmar({
        titulo: `Rechazar el pago de ${m.etiqueta}`,
        detalle: [m.cliente || "Sin cliente asignado"],
        aviso: "La mesa vuelve al estado reservada y queda pendiente de cobro.",
        accion: "Rechazar pago"
      })) return;
      const { error } = await sb.rpc("verificar_mesa", { p_mesa: m.id, p_ok: false });
      if (error) return fail(error);
      toast(`Pago rechazado — ${m.etiqueta} volvió a reservada`, "warn");
      closeSheet(); screenMesas();
    };
    document.querySelectorAll("#sheetBody [data-mtk]").forEach(r => r.onclick = () => {
      lastTk = manList.find(t => t.code === r.dataset.mtk);
      closeSheet(); tab = "entradas"; setTab(); renderTab();
      setTimeout(() => window.scrollTo({ top: 0, behavior: "smooth" }), 200);
    });
    const bAdd = $("#mmAdd");
    if (bAdd) bAdd.onclick = async () => {
      const nombres = expandNombres($("#mmNames").value);
      if (!nombres.length) return toast("Escribí al menos un nombre", "warn");
      if (nombres.length > restantes) return toast(`Solo quedan ${restantes} manilla(s) de este combo`, "warn");
      bAdd.disabled = true;
      let ok = 0;
      for (const nm of nombres) {
        const { error: e2 } = await sb.rpc("generar_entrada", { p_evento: ev.id, p_cliente: nm, p_mesa: primForMan.id });
        if (!e2) ok++;
      }
      bAdd.disabled = false;
      toast(`${ok} manilla(s) con QR agregada(s)`);
      sheetMesa(m);
    };
    document.querySelectorAll("#sheetBody [data-del-man]").forEach(b => b.onclick = async () => {
      if (!await confirmar({
        titulo: "Eliminar manilla",
        detalle: [b.dataset.nom, `Mesa ${m.etiqueta}`],
        aviso: "La manilla deja de ser válida para el ingreso.",
        accion: "Eliminar manilla"
      })) return;
      const { error: e2 } = await sb.rpc("eliminar_entrada", { p_entrada: b.dataset.delMan });
      if (e2) return toast(e2.message, "warn");
      toast(`Manilla de ${b.dataset.nom} eliminada`, "warn");
      sheetMesa(m);
    });
  }
}
window.estadoMesa = async (id, est) => {
  const { error } = await sb.rpc("estado_mesa", { p_mesa: id, p_estado: est });
  if (error) return fail(error);
  toast(est === "disponible" ? "Mesa liberada" : "Mesa " + EST_LABEL[est].toLowerCase());
  closeSheet(); screenMesas();
};

/* admin: gestionar los QR de cobro del boliche (uno por cada cuenta que cobra) */
async function sheetQrsCobro() {
  const { data: qrs } = await sb.from("qr_cobro").select("*").eq("club_id", club).order("orden");
  const lista = qrs || [];
  sheet(`
    <div class="sh-h">QRs de cobro · ${clubNombre(club)}</div>
    <div class="hint" style="margin:0 0 12px">Cargá un QR por cada cuenta que cobra. Al cobrar una mesa elegís cuál mostrar.</div>
    <div>${lista.map(q => `
      <div class="list-row">
        <div class="r-l"><img src="${esc(q.url)}" alt="" style="width:40px;height:40px;border-radius:8px;background:#fff;padding:2px;object-fit:cover"><span>${esc(q.nombre)}${q.activo ? "" : ` <small style="color:var(--danger)">(pausado)</small>`}</span></div>
        <div style="display:flex;gap:6px">
          <button class="checkin" data-qtg="${q.id}" data-act="${q.activo}" style="background:var(--surface-3);color:var(--text-2);border-color:var(--line-2)">${q.activo ? "Pausar" : "Activar"}</button>
          <button class="checkin" data-qdel="${q.id}" data-nom="${esc(q.nombre)}" style="background:var(--danger-bg);color:var(--danger);border-color:rgba(251,113,133,.35)">✕</button>
        </div>
      </div>`).join("") || `<div class="empty">Sin QRs cargados.</div>`}
    </div>
    <div class="sh-h" style="margin-top:16px">Nuevo QR</div>
    <div class="field"><label>Nombre (a quién se cobra)</label><input id="nqNom" placeholder="Caja principal"></div>
    <button class="btn primary" id="nqGo">Subir imagen del QR</button>
    <input type="file" id="nqFile" accept="image/*" class="hidden">`);
  $("#nqGo").onclick = () => {
    const nom = $("#nqNom").value.trim();
    if (!nom) return toast("Poné el nombre", "warn");
    const inp = $("#nqFile");
    inp.onchange = async () => {
      const f = inp.files[0]; if (!f) return;
      toast("Subiendo QR…");
      const comp = await dataUrlToBlob(await comprimirImg(f, 900, 0.85));   // Blob, NO el data URL
      const path = `qr-cobro-${club}-${nom.toLowerCase().replace(/[^a-z0-9]/g, "")}-${Date.now()}.jpg`;
      const { error: e1 } = await sb.storage.from("disenos").upload(path, comp, { upsert: true, contentType: "image/jpeg" });
      if (e1) return fail(e1);
      const { data: { publicUrl } } = sb.storage.from("disenos").getPublicUrl(path);
      const { error: e2 } = await sb.from("qr_cobro").insert({ club_id: club, nombre: nom, url: publicUrl, orden: (qrs || []).length });
      if (e2) return fail(e2);
      toast(`QR de ${nom} cargado`);
      sheetQrsCobro();
    };
    inp.click();
  };
  document.querySelectorAll("#sheetBody [data-qtg]").forEach(b => b.onclick = async () => {
    const { error } = await sb.from("qr_cobro").update({ activo: b.dataset.act !== "true" }).eq("id", b.dataset.qtg);
    if (error) return fail(error);
    sheetQrsCobro();
  });
  document.querySelectorAll("#sheetBody [data-qdel]").forEach(b => b.onclick = async () => {
    if (!await confirmar({
      titulo: "Eliminar QR de cobro",
      detalle: [b.dataset.nom],
      aviso: "Deja de estar disponible para cobrar en este evento.",
      accion: "Eliminar QR"
    })) return;
    const { error } = await sb.from("qr_cobro").delete().eq("id", b.dataset.qdel);
    if (error) return fail(error);
    toast(`QR de ${b.dataset.nom} eliminado`, "warn");
    sheetQrsCobro();
  });
}

/* cobrar una mesa: muestra el QR de cobro del boliche (varios a elegir) */
let qrCobroSel = null;
async function sheetQrMesa(m, prim, nMesas) {
  const { data: qrs } = await sb.from("qr_cobro").select("*").eq("club_id", club).eq("activo", true).order("orden");
  const lista = qrs || [];
  if (!lista.length) return toast("El admin todavía no cargó ningún QR de cobro (Más → QRs de cobro)", "warn");
  // LAS MESAS SE PAGAN SIEMPRE AL QR DEL BOLICHE (el del admin), nunca al del team.
  // Solo el admin puede elegir entre sus QRs; el resto ve el principal, sin opción.
  const puedeElegir = me.rol === "admin" && lista.length > 1;
  if (!puedeElegir || !qrCobroSel || !lista.find(q => q.id === qrCobroSel)) qrCobroSel = lista[0].id;
  const sel = lista.find(q => q.id === qrCobroSel);
  sheet(`
    <button class="btn ghost2" style="width:auto;padding:8px 14px;margin-bottom:12px" id="qmBack">${ico("atras")}Volver</button>
    <div class="sh-h">Cobrar ${esc(m.etiqueta)}${nMesas > 1 ? ` +${nMesas - 1}` : ""}<span class="r-sub">${fmtBs(prim.precio)} Bs</span></div>
    ${puedeElegir ? `<div class="seg" style="margin-bottom:12px">${lista.map(q =>
      `<button class="segbtn ${q.id === qrCobroSel ? "on" : ""}" data-qsel="${q.id}">${esc(q.nombre)}</button>`).join("")}</div>` : ""}
    <div class="hint" style="text-align:center;margin:0 0 10px;font-size:14px;color:var(--text)">Pagar al siguiente QR para la mesa <b>${esc(m.etiqueta)}</b></div>
    <img src="${esc(sel.url)}" alt="QR de cobro ${esc(sel.nombre)}" style="width:100%;max-width:320px;display:block;margin:0 auto 10px;border-radius:14px;background:#fff;padding:10px">
    <div class="hint" style="text-align:center;margin-bottom:14px">La plata de las mesas entra siempre a <b>${esc(sel.nombre)}</b>${me.rol === "admin" ? "" : " — no al QR de tu team"}.</div>
    ${m.estado !== "pagada" ? `<button class="btn primary" id="qmPagada">Ya pagó — subir comprobante${nMesas > 1 ? " (grupo)" : ""}</button>` : ""}`);
  $("#qmBack").onclick = () => sheetMesa(m);
  document.querySelectorAll("#sheetBody [data-qsel]").forEach(b => b.onclick = () => {
    qrCobroSel = b.dataset.qsel; sheetQrMesa(m, prim, nMesas);
  });
  const bp = $("#qmPagada");
  if (bp) bp.onclick = () => sheetPagarMesa(m, prim, nMesas);
}

/* Contabilidad: confirmar de corrido todas las mesas cobradas.
   Antes había que abrir y cerrar mesa por mesa (4 consultas cada una);
   acá se ven todas juntas con su comprobante y se confirman de una. */
async function sheetContabilidad(pendientes) {
  await loadEfectivos();
  pausaPlano = true;   // se redibuja una sola vez, al terminar
  const total = pendientes.reduce((a, m) => a + (+m.precio || 0), 0);
  const fila = m => {
    const v = efectivosCache[m.vendido_por], c = efectivosCache[m.pagada_por];
    return `<div class="list-row rc" data-cf="${m.id}" style="align-items:flex-start">
      <div class="r-l" style="flex:1;min-width:0;align-items:flex-start">
        <span class="relmark">${esc(m.etiqueta[0])}</span>
        <span class="rc-body">
          <span class="rc-nm">${esc(m.etiqueta)} · ${esc(m.cliente || "—")}</span>
          <span class="rc-sub"><span>${fmtBs(m.precio)} Bs · ${m.metodo_pago === "efectivo" ? "efectivo" : "transferencia"}${v ? " · vendió " + esc(v.nombre) : ""}${c ? " · cobró " + esc(c.nombre) : ""}</span></span>
          ${m.comprobante_url
            ? `<a href="${esc(m.comprobante_url)}" target="_blank" rel="noopener"><img src="${esc(m.comprobante_url)}" alt="comprobante" style="width:104px;border-radius:9px;border:1px solid var(--line-2);margin-top:7px;display:block"></a>`
            : `<span class="rc-sub" style="color:var(--warn);margin-top:5px">Sin comprobante (efectivo)</span>`}
        </span>
      </div>
      <div style="display:flex;flex-direction:column;gap:6px;flex-shrink:0">
        <button class="checkin" data-ok="${m.id}" style="background:var(--ok-bg,rgba(61,220,151,.12));color:var(--ok);border-color:rgba(61,220,151,.35)">✓ Entró</button>
        <button class="checkin" data-no="${m.id}" style="background:var(--surface-3);color:var(--danger);border-color:var(--line-2)">✕</button>
      </div>
    </div>`;
  };
  sheet(`
    <div class="sh-h">Confirmar pagos<span class="r-sub">${pendientes.length} · ${fmtBs(total)} Bs</span></div>
    <div class="hint" style="margin:0 0 12px">Mirá el comprobante y confirmá si la plata entró. Rechazar devuelve la mesa a reservada.</div>
    <div id="ctaLista">${pendientes.map(fila).join("")}</div>`);
  const cerrar = () => { pausaPlano = false; scrimEl.removeEventListener("click", onScrim); closeSheet(); screenMesas(); };
  const quitar = id => {
    const row = document.querySelector(`#ctaLista [data-cf="${id}"]`);
    if (row) row.remove();
    if (!document.querySelectorAll("#ctaLista [data-cf]").length) cerrar();
  };
  // si cierra a mano (scrim o back), el plano se actualiza igual
  const scrimEl = $("#scrim");
  const onScrim = () => { scrimEl.removeEventListener("click", onScrim); cerrar(); };
  scrimEl.addEventListener("click", onScrim);
  const bind = () => {
    document.querySelectorAll("#ctaLista [data-ok]").forEach(b => b.onclick = async () => {
      b.disabled = true;
      const { error } = await sb.rpc("verificar_mesa", { p_mesa: b.dataset.ok, p_ok: true });
      if (error) { b.disabled = false; return fail(error); }
      const m = pendientes.find(x => x.id === b.dataset.ok);
      if (m) m.pago_verificado = true;                 // el plano se entera sin volver a pedir nada
      toast(`${m?.etiqueta || "Mesa"} confirmada`);
      quitar(b.dataset.ok);
    });
    document.querySelectorAll("#ctaLista [data-no]").forEach(b => {
      b.onclick = async () => {
        const mp = pendientes.find(x => x.id === b.dataset.no);
        if (!await confirmar({
          titulo: `Rechazar el pago de ${mp?.etiqueta || "la mesa"}`,
          detalle: [mp?.cliente || "Sin cliente asignado"],
          aviso: "La mesa vuelve al estado reservada y queda pendiente de cobro.",
          accion: "Rechazar pago"
        })) return;
        const { error } = await sb.rpc("verificar_mesa", { p_mesa: b.dataset.no, p_ok: false });
        if (error) return fail(error);
        const m = pendientes.find(x => x.id === b.dataset.no);
        if (m) { m.estado = "reservada"; m.pago_verificado = false; }
        toast(`${m?.etiqueta || "Mesa"} vuelve a reservada`, "warn");
        quitar(b.dataset.no);
      };
    });
  };
  bind();
}

/* sube la foto del comprobante a Storage y devuelve su URL pública */
async function subirComprobanteMesa(file, mesaId) {
  const dataUrl = await comprimirImg(file, 1100, 0.8);   // legible y liviano
  const blob = await dataUrlToBlob(dataUrl);
  // el bucket exige que el archivo cuelgue de la carpeta del propio usuario
  const path = `${me.id}/mesa-${mesaId}-${Date.now()}.jpg`;
  const { error } = await sb.storage.from("comprobantes").upload(path, blob, { upsert: true, contentType: "image/jpeg" });
  if (error) throw error;
  const { data: { publicUrl } } = sb.storage.from("comprobantes").getPublicUrl(path);
  return publicUrl;
}

/* marcar una mesa como pagada: el comprobante es obligatorio salvo para el admin */
/* Editar una mesa ya vendida sin tener que liberarla y volver a venderla.
   El permiso lo decide la base: quien la vendió, su jefe, o el admin. Acá
   solo se muestra el botón; si no le corresponde, el RPC lo rebota. */
function sheetEditarMesa(m, prim, nMesas) {
  const activos = combosCache.filter(c => c.activo);
  const cats = [m.categoria || "mesa"];
  const vale = c => !c.categorias || !c.categorias.length || cats.every(k => c.categorias.includes(k));
  const ok = activos.filter(c => vale(c) || c.id === prim.combo_id);
  sheet(`
    <button class="btn ghost2" style="width:auto;padding:8px 14px;margin-bottom:12px" id="emBack">${ico("atras")}Volver</button>
    <div class="sh-h">Editar ${esc(m.etiqueta)}${nMesas > 1 ? ` +${nMesas - 1}` : ""}<span class="r-sub">${fmtBs(prim.precio || 0)} Bs</span></div>
    <div class="field"><label>Cliente</label><input id="emCli" value="${esc(prim.cliente || "")}"></div>
    <div class="field"><label>Combo</label><select id="emCombo">
      ${ok.map(c => `<option value="${c.id}"${c.id === prim.combo_id ? " selected" : ""}>${esc(c.nombre)} · ${fmtBs(c.precio)} Bs${c.incluye_manillas ? " · " + c.incluye_manillas + " manillas" : ""}</option>`).join("")}
    </select></div>
    <div class="hint" style="margin:-4px 0 14px">Si cambiás el combo se recalcula el precio.${nMesas > 1 ? " El cambio aplica a las " + nMesas + " mesas del grupo." : ""}</div>
    <button class="btn primary" id="emGo">Guardar</button>`);
  $("#emBack").onclick = () => sheetMesa(m);
  $("#emGo").onclick = async () => {
    const b = $("#emGo"); b.disabled = true;
    const { data, error } = await sb.rpc("editar_mesa", {
      p_mesa: m.id, p_cliente: $("#emCli").value.trim(), p_combo: $("#emCombo").value || null });
    b.disabled = false;
    if (error) return fail(error);
    toast(`${data.etiqueta} actualizada · ${fmtBs(data.precio || 0)} Bs`);
    closeSheet(); await loadMesas(true); screenMesas();
  };
}

function sheetPagarMesa(m, prim, nMesas) {
  const esAdmin = me.rol === "admin";
  sheet(`
    <button class="btn ghost2" style="width:auto;padding:8px 14px;margin-bottom:12px" id="pmBack">${ico("atras")}Volver</button>
    <div class="sh-h">Marcar pagada · ${esc(m.etiqueta)}${nMesas > 1 ? ` +${nMesas - 1}` : ""}<span class="r-sub">${fmtBs(prim.precio)} Bs</span></div>
    <div class="field"><label>¿Cómo pagó?</label>
      <div class="seg"><button type="button" class="segbtn on" data-pmp="transferencia">Transferencia</button><button type="button" class="segbtn" data-pmp="efectivo">Efectivo</button></div></div>
    <div class="hint" style="margin:0 0 12px" id="pmHint">${esAdmin
      ? "Como admin podés confirmarla directo, o adjuntar el comprobante igual para dejar constancia."
      : "Subí la foto del comprobante. Sin foto la mesa no se puede marcar pagada."}</div>
    <div id="pmPrev"></div>
    <div id="pmCompBox">
      <button class="btn ghost2" id="pmFoto">${esAdmin ? "Adjuntar comprobante (opcional)" : "Subir foto del comprobante"}</button>
      <div style="height:9px"></div>
    </div>
    <button class="btn primary" id="pmGo"${esAdmin ? "" : " disabled"}>Confirmar pago</button>
    <input type="file" id="pmFile" accept="image/*" class="hidden">
    <p class="hint" style="margin-top:10px">${esAdmin
      ? "Queda registrado que vos confirmaste el pago y a qué hora."
      : "La mesa queda como <b>pagada · por verificar</b> hasta que el admin confirme que la plata entró."}</p>`);
  let urlComp = null, metodoPm = "transferencia";
  $("#pmBack").onclick = () => sheetMesa(m);
  const sincPm = () => {
    const transf = metodoPm === "transferencia";
    $("#pmCompBox").classList.toggle("hidden", !transf);
    $("#pmHint").textContent = esAdmin
      ? (transf ? "Como admin podés confirmarla directo, o adjuntar el comprobante para dejar constancia."
                : "Cobrado en efectivo. Queda pagada y verificada.")
      : (transf ? "Subí la foto del comprobante. Sin foto la mesa no se puede marcar pagada."
                : "Cobrado en efectivo: no hace falta foto, pero la mesa queda por verificar hasta que el admin la confirme.");
    $("#pmGo").disabled = !esAdmin && transf && !urlComp;
  };
  document.querySelectorAll("#sheetBody [data-pmp]").forEach(b => b.onclick = () => {
    metodoPm = b.dataset.pmp;
    document.querySelectorAll("#sheetBody [data-pmp]").forEach(x => x.classList.toggle("on", x.dataset.pmp === metodoPm));
    sincPm();
  });
  const inpComp = $("#pmFile");
  inpComp.onchange = async () => {
    const f = inpComp.files[0]; if (!f) return;
    const bf = $("#pmFoto"); bf.disabled = true; bf.textContent = "Subiendo…";
    try {
      urlComp = await subirComprobanteMesa(f, m.id);
      $("#pmPrev").innerHTML = `<img src="${esc(urlComp)}" alt="comprobante" style="width:100%;max-width:260px;display:block;margin:0 auto 10px;border-radius:12px;border:1px solid var(--line-2)">`;
      bf.textContent = "Cambiar foto";
      const go = $("#pmGo"); if (go) go.disabled = false;
      toast("Comprobante cargado");
    } catch (e) { fail(e); bf.textContent = "Reintentar"; }
    bf.disabled = false;
  };
  $("#pmFoto").onclick = () => inpComp.click();
  $("#pmGo").onclick = async () => {
    if (!esAdmin && metodoPm === "transferencia" && !urlComp) return toast("Subí la foto del comprobante o marcá efectivo", "warn");
    $("#pmGo").disabled = true;
    const { error } = await sb.rpc("pagar_mesa", { p_mesa: m.id, p_url: urlComp, p_efectivo: metodoPm === "efectivo" });
    if (error) { $("#pmGo").disabled = false; return fail(error); }
    toast(esAdmin ? `${m.etiqueta} pagada en ${metodoPm} · verificada` : `${m.etiqueta} pagada en ${metodoPm} — queda por verificar`, esAdmin ? "" : "warn");
    closeSheet(); screenMesas();
  };
}

/* editor admin: propiedades de la mesa */
function sheetMesaEdit(m) {
  sheet(`
    <div class="sh-h">Editar ${esc(m.etiqueta)}</div>
    <div class="row2">
      <div class="field"><label>Etiqueta</label><input id="emEt" value="${esc(m.etiqueta)}"></div>
      <div class="field"><label>Categoría</label><select id="emCat">
        <option value="mesa"${m.categoria === "mesa" ? " selected" : ""}>Mesa</option>
        <option value="lounge"${m.categoria === "lounge" ? " selected" : ""}>Lounge</option></select></div>
    </div>
    <div class="row2">
      <div class="field"><label>Ancho %</label><input id="emW" type="number" min="8" max="30" value="${m.w}"></div>
      <div class="field"><label>Alto %</label><input id="emH" type="number" min="8" max="45" value="${m.h ?? 21}"></div>
    </div>
    <div class="row2">
      <div class="field"><label>Team asignado</label><select id="emTeam"><option value="">— libre —</option>${teamsDelClub().map(t =>
        `<option value="${t.id}"${m.team_id === t.id ? " selected" : ""}>${esc(t.nombre)}</option>`).join("")}</select></div>
      <div class="field"><label>Piso</label><select id="emPl">${pisosDe().map(f =>
        `<option value="${f}"${m.planta === f ? " selected" : ""}>${FLOOR_LABEL[f] || f}</option>`).join("")}</select></div>
    </div>
    <button class="btn primary" id="emGo">Guardar</button>
    <div style="height:9px"></div>
    <button class="btn danger" id="emDel">Eliminar mesa</button>`);
  $("#emGo").onclick = async () => {
    const { error } = await sb.from("mesas").update({
      etiqueta: $("#emEt").value.trim() || m.etiqueta, categoria: $("#emCat").value,
      w: +$("#emW").value || m.w, h: +$("#emH").value || null,
      team_id: $("#emTeam").value || null, planta: $("#emPl").value
    }).eq("id", m.id);
    if (error) return fail(error);
    toast("Mesa actualizada"); closeSheet(); screenMesas();
  };
  $("#emDel").onclick = async () => {
    const vendida = m.estado && m.estado !== "disponible";
    const detalle = [m.categoria === "lounge" ? "Lounge" : "Mesa"];
    if (m.cliente) detalle.push(`Cliente: ${m.cliente}`);
    if (m.combo) detalle.push(`Combo: ${m.combo}`);
    if (vendida) detalle.push(`Estado: ${m.estado}`);
    if (!m.cliente && !vendida) detalle.push("Libre, sin venta asociada");

    if (!await confirmar({
      titulo: `Eliminar ${m.etiqueta}`,
      detalle,
      aviso: vendida
        ? "Esta mesa tiene una venta asociada. Al eliminarla se pierde su registro en el plano y en los reportes."
        : "",
      accion: "Eliminar mesa"
    })) return;
    const { error } = await sb.from("mesas").delete().eq("id", m.id);
    if (error) return fail(error);
    toast("Mesa eliminada"); closeSheet(); screenMesas();
  };
}

/* En qué tipos de mesa se puede vender cada combo.
   Sin ninguno marcado (o los dos) el combo sirve para todas. */
const CATS_MESA = [{ id: "lounge", nom: "Lounges" }, { id: "mesa", nom: "Mesas (redondas)" }];
const catsChips = (id, sel) => `
  <div class="chip-pick">${CATS_MESA.map(k =>
    `<button type="button" class="mchip${(sel || []).includes(k.id) ? " on" : ""}" data-${id}="${k.id}">${k.nom}</button>`).join("")}</div>`;
const catsLeer = attr => {
  const marcados = [...document.querySelectorAll(`#sheetBody [data-${attr}].on`)].map(b => b.dataset[attr]);
  // ninguno o los dos = sirve para todas: se guarda null y no se filtra nada
  return (!marcados.length || marcados.length === CATS_MESA.length) ? null : marcados;
};
const catsEnganchar = attr => document.querySelectorAll(`#sheetBody [data-${attr}]`)
  .forEach(b => b.onclick = () => b.classList.toggle("on"));
const catsTexto = c => !c.categorias || !c.categorias.length || c.categorias.length === CATS_MESA.length
  ? "todas las mesas"
  : "solo " + c.categorias.map(k => (CATS_MESA.find(x => x.id === k) || {}).nom || k).join(" y ").toLowerCase();

/* combos CRUD (admin) */
async function sheetCombos() {
  await loadCombos(true);   // pantalla de gestión: siempre datos frescos (y deja el caché al día)
  sheet(`
    <div class="sh-h">Combos · ${clubNombre(club)}</div>
    <div>${combosCache.map(c => `
      <div class="list-row" style="${c.activo ? "" : "opacity:.55"}">
        <div class="r-l"><span>${esc(c.nombre)}<br><small style="color:var(--text-3)">${fmtBs(c.precio)} Bs · com. ${fmtBs(c.comision_rrpp)}/${fmtBs(c.comision_jefe)}${c.incluye_manillas ? " · " + c.incluye_manillas + " man." : ""}<br>${esc(catsTexto(c))}</small></span></div>
        <div style="display:flex;gap:6px">
          <button class="checkin" data-edc="${c.id}" style="background:var(--surface-3);color:var(--text-2);border-color:var(--line-2)">Editar</button>
          <button class="checkin" data-tgc="${c.id}" data-act="${c.activo}">${c.activo ? "Pausar" : "Activar"}</button>
          <button class="checkin" data-delc="${c.id}" data-nom="${esc(c.nombre)}" style="background:var(--danger-bg);color:var(--danger);border-color:rgba(251,113,133,.35)">Borrar</button>
        </div>
      </div>`).join("") || `<div class="empty">Sin combos aún.</div>`}
    </div>
    <div class="sh-h" style="margin-top:16px">Nuevo combo</div>
    <div class="row2">
      <div class="field"><label>Nombre</label><input id="cbN" placeholder="Combo Lounge"></div>
      <div class="field"><label>Precio Bs</label><input id="cbP" type="number"></div>
    </div>
    <div class="field"><label>Productos (coma)</label><input id="cbProd" placeholder="1 botella, sodas, hielo"></div>
    <div class="row2">
      <div class="field"><label>Comisión RRPP Bs</label><input id="cbCR" type="number" value="0"></div>
      <div class="field"><label>Comisión Jefe Bs</label><input id="cbCJ" type="number" value="0"></div>
    </div>
    <div class="field"><label>Manillas incluidas</label><input id="cbM" type="number" value="0"></div>
    <div class="field"><label>¿Dónde se puede vender?</label>
      ${catsChips("cbcat", null)}
      <small style="color:var(--text-3)">Sin marcar nada sirve para todas. Marcá solo Lounges si es un combo especial.</small></div>
    <button class="btn primary" id="cbGo">Crear combo</button>`);
  catsEnganchar("cbcat");
  $("#cbGo").onclick = async () => {
    const nombre = $("#cbN").value.trim(), precio = +$("#cbP").value;
    if (!nombre || !precio) return toast("Nombre y precio", "warn");
    const { error } = await sb.from("combos").insert({
      club_id: club, nombre, precio,
      productos: $("#cbProd").value.split(",").map(s => s.trim()).filter(Boolean),
      comision_rrpp: +$("#cbCR").value || 0, comision_jefe: +$("#cbCJ").value || 0,
      incluye_manillas: +$("#cbM").value || 0,
      categorias: catsLeer("cbcat")
    });
    if (error) return fail(error);
    toast("Combo creado"); sheetCombos();
  };
  document.querySelectorAll("#sheetBody [data-tgc]").forEach(b => b.onclick = async () => {
    await sb.from("combos").update({ activo: b.dataset.act !== "true" }).eq("id", b.dataset.tgc);
    sheetCombos();
  });
  document.querySelectorAll("#sheetBody [data-edc]").forEach(b => b.onclick = () =>
    sheetEditarCombo(combosCache.find(c => c.id === b.dataset.edc)));
  document.querySelectorAll("#sheetBody [data-delc]").forEach(b => b.onclick = async () => {
    if (!await confirmar({
      titulo: `Eliminar combo ${b.dataset.nom}`,
      detalle: ["Deja de ofrecerse al vender mesas"],
      aviso: "Si ya hay mesas vendidas con este combo, no se podrá borrar: en ese caso conviene pausarlo.",
      accion: "Eliminar combo"
    })) return;
    const { error } = await sb.from("combos").delete().eq("id", b.dataset.delc);
    if (error) return toast("No se puede borrar: hay mesas vendidas con este combo. Usá Pausar.", "warn");
    toast(`Combo "${b.dataset.nom}" borrado`, "warn"); sheetCombos();
  });
}

function sheetEditarCombo(c) {
  sheet(`
    <div class="sh-h">Editar combo</div>
    <div class="row2">
      <div class="field"><label>Nombre</label><input id="ecN" value="${esc(c.nombre)}"></div>
      <div class="field"><label>Precio Bs</label><input id="ecP" type="number" value="${c.precio}"></div>
    </div>
    <div class="field"><label>Productos (coma)</label><input id="ecProd" value="${esc((c.productos || []).join(', '))}"></div>
    <div class="row2">
      <div class="field"><label>Comisión RRPP Bs</label><input id="ecCR" type="number" value="${c.comision_rrpp}"></div>
      <div class="field"><label>Comisión Jefe Bs</label><input id="ecCJ" type="number" value="${c.comision_jefe}"></div>
    </div>
    <div class="field"><label>Manillas incluidas</label><input id="ecM" type="number" value="${c.incluye_manillas}"></div>
    <div class="field"><label>¿Dónde se puede vender?</label>
      ${catsChips("eccat", c.categorias)}
      <small style="color:var(--text-3)">Sin marcar nada sirve para todas las mesas.</small></div>
    <button class="btn primary" id="ecGo">Guardar</button>`);
  catsEnganchar("eccat");
  $("#ecGo").onclick = async () => {
    const nombre = $("#ecN").value.trim(), precio = +$("#ecP").value;
    if (!nombre || !precio) return toast("Nombre y precio", "warn");
    const { error } = await sb.from("combos").update({
      nombre, precio,
      productos: $("#ecProd").value.split(",").map(s => s.trim()).filter(Boolean),
      comision_rrpp: +$("#ecCR").value || 0, comision_jefe: +$("#ecCJ").value || 0,
      incluye_manillas: +$("#ecM").value || 0,
      categorias: catsLeer("eccat")
    }).eq("id", c.id);
    if (error) return fail(error);
    toast("Combo actualizado"); sheetCombos();
  };
}

/* ============================================================
   FASES DE PREVENTA (admin)
   El evento vende con un solo precio salvo que acá se prendan las fases.
   Cada fase tiene su precio y su stock: cuando se agota una, la siguiente
   toma el lugar sola, sin que nadie tenga que tocar nada de madrugada.
   ============================================================ */
const dtLocal = ts => ts ? new Date(new Date(ts).getTime() - new Date().getTimezoneOffset() * 60000).toISOString().slice(0, 16) : "";
/* fmtF espera una fecha suelta ("2026-08-10"); las fases guardan timestamp
   completo, así que se formatea aparte con día, mes y hora */
const fmtTS = ts => ts ? new Date(ts).toLocaleString("es-BO",
  { day: "numeric", month: "short", hour: "2-digit", minute: "2-digit", hour12: false }) : "—";
async function sheetFases(evId, evNombre, volverA) {
  const [{ data: fases }, { data: evRow }] = await Promise.all([
    sb.rpc("fases_evento", { p_evento: evId }),
    sb.from("eventos").select("venta_por_fases, precio_manilla").eq("id", evId).single()
  ]);
  const fs = fases || [], on = !!evRow?.venta_por_fases;
  fs.forEach(f => { if (f.ticket_url) fasesArte[f.id] = f.ticket_url; else delete fasesArte[f.id]; });
  sheet(`
    <button class="btn ghost2" style="width:auto;padding:8px 14px;margin-bottom:12px" id="fsBack">${ico("atras")}Volver</button>
    <div class="sh-h">Fases de preventa<span class="r-sub">${esc(evNombre || "")}</span></div>
    ${volverA === "crear" ? `<div class="hint" style="margin:0 0 10px;color:var(--ok)">✓ Evento creado. Cargá las tandas acá abajo y después prendé la venta por fases.</div>` : ""}
    <div class="hint" style="margin:0 0 12px">Apagado, el evento vende todo a ${fmtBs(evRow?.precio_manilla || 0)} Bs como siempre. Prendido, el precio y el stock los pone la fase que esté abierta.</div>
    <button class="btn ${on ? "danger" : "primary"}" id="fsToggle">${on ? "Apagar — volver al precio único" : "Prender venta por fases"}</button>
    <div class="sh-h" style="margin-top:18px;font-size:14px">Fases (${fs.length})</div>
    <p class="hint" style="margin:0 0 8px">Con el botón de imagen le podés poner a cada fase su propio diseño de entrada. La que no tenga usa el diseño del evento, y le sale el sello con el nombre de la tanda.</p>
    <div>${fs.map(f => `
      <div class="list-row rc" style="${f.activo ? "" : "opacity:.5"}${f.vigente ? ";border-color:rgba(61,220,151,.45)" : ""}">
        <div class="r-l" style="flex:1;min-width:0"><span class="rc-body">
          <span class="rc-nm">${esc(f.nombre)} ${f.vigente ? `<span class="tkst ok" style="font-size:10px">ABIERTA</span>` : f.agotada ? `<span class="tkst" style="background:var(--danger-bg);color:var(--danger);font-size:10px">AGOTADA</span>` : ""}</span>
          <span class="rc-sub"><span>${fmtBs(f.precio)} Bs · ${f.vendidas}/${f.cupo ?? "sin tope"}${f.desde || f.hasta ? ` · ${fmtTS(f.desde)} a ${fmtTS(f.hasta)}` : ""}</span></span>
        </span></div>
        <div style="display:flex;gap:5px;flex-shrink:0">
          <button class="checkin" data-farte="${f.id}" data-fnom="${esc(f.nombre)}" title="Arte de la entrada de esta fase" style="background:var(--surface-3);color:${f.ticket_url ? "var(--ok)" : "var(--text-2)"};border-color:var(--line-2)" aria-label="Diseño de la entrada de esta fase">${ico("imagen")}${f.ticket_url ? " ✓" : ""}</button>
          <button class="checkin" data-fcup="${f.id}" data-fnom="${esc(f.nombre)}" style="background:var(--accent-soft);color:var(--accent-2);border-color:rgba(139,92,246,.4)">Cupos</button>
          <button class="checkin" data-fed="${f.id}" style="background:var(--surface-3);color:var(--text-2);border-color:var(--line-2)">Editar</button>
          ${f.vendidas ? "" : `<button class="checkin" data-fdel="${f.id}" style="background:var(--danger-bg);color:var(--danger);border-color:rgba(251,113,133,.35)">✕</button>`}
        </div>
      </div>`).join("") || `<div class="empty">Todavía no hay fases. Creá la primera abajo.</div>`}</div>
    <div class="sh-h" style="margin-top:16px;font-size:14px" id="fsFormTit">Nueva fase</div>
    <input type="hidden" id="fsId">
    <input type="file" id="fsArteFile" accept="image/png,image/jpeg,image/webp" class="hidden">
    <div class="row2">
      <div class="field"><label>Nombre</label><input id="fsN" placeholder="Hot Tickets"></div>
      <div class="field"><label>Precio Bs</label><input id="fsP" type="number"></div>
    </div>
    <div class="row2">
      <div class="field"><label>Stock (vacío = sin tope)</label><input id="fsC" type="number" placeholder="100"></div>
      <div class="field"><label>Orden</label><input id="fsO" type="number" value="${fs.length + 1}"></div>
    </div>
    <div class="row2">
      <div class="field"><label>Desde</label><input id="fsD" type="datetime-local"></div>
      <div class="field"><label>Hasta</label><input id="fsH" type="datetime-local"></div>
    </div>
    <div class="hint" style="margin:-4px 0 12px">La fase se cierra sola cuando llega la fecha o cuando se vende el último ticket, lo que pase primero.</div>
    <button class="btn primary" id="fsGo">Guardar fase</button>`);

  $("#fsBack").onclick = () => volverA === "entradas" || volverA === "crear" ? closeSheet() : sheetEditarEvento(evId);
  $("#fsToggle").onclick = async () => {
    const b = $("#fsToggle"); b.disabled = true;
    const { error } = await sb.rpc("set_venta_por_fases", { p_evento: evId, p_on: !on });
    b.disabled = false;
    if (error) return fail(error);
    toast(on ? "Volvió al precio único" : "Venta por fases activada");
    if (ev && ev.id === evId) ev.venta_por_fases = !on;   // el botón de Entradas refleja el cambio
    sheetFases(evId, evNombre, volverA);
  };
  document.querySelectorAll("#sheetBody [data-fed]").forEach(b => b.onclick = () => {
    const f = fs.find(x => x.id === b.dataset.fed); if (!f) return;
    $("#fsFormTit").textContent = "Editar “" + f.nombre + "”";
    $("#fsId").value = f.id; $("#fsN").value = f.nombre; $("#fsP").value = f.precio;
    $("#fsC").value = f.cupo ?? ""; $("#fsO").value = f.orden;
    $("#fsD").value = dtLocal(f.desde); $("#fsH").value = dtLocal(f.hasta);
    $("#fsN").scrollIntoView({ block: "center", behavior: "smooth" });
  });
  document.querySelectorAll("#sheetBody [data-fdel]").forEach(b => b.onclick = async () => {
    const { error } = await sb.rpc("borrar_fase", { p_fase: b.dataset.fdel });
    if (error) return fail(error);
    toast("Fase borrada", "warn"); sheetFases(evId, evNombre, volverA);
  });
  /* Arte propio de la fase: una Hot Ticket puede salir con otro diseño que la
     Fase 1. Se sube al mismo bucket que el arte del evento, con el id de la
     fase como nombre, así reemplazar es sobrescribir. */
  document.querySelectorAll("#sheetBody [data-farte]").forEach(b => b.onclick = () => {
    const inp = $("#fsArteFile");
    inp.value = "";
    inp.onchange = async () => {
      const file = inp.files[0]; if (!file) return;
      const antes = b.textContent; b.disabled = true; b.textContent = "…";
      try {
        // mismo tamaño que el arte del evento: la entrada se arma sobre 1080 px
        const blob = await dataUrlToBlob(await comprimirImg(file, 1080, 0.88));
        const path = `fase-${b.dataset.farte}.jpg`;
        const { error: e1 } = await sb.storage.from("disenos").upload(path, blob, { upsert: true, contentType: "image/jpeg" });
        if (e1) throw e1;
        const { data: { publicUrl } } = sb.storage.from("disenos").getPublicUrl(path);
        const url = publicUrl + "?v=" + Date.now();
        const { error: e2 } = await sb.rpc("fase_arte", { p_fase: b.dataset.farte, p_url: url });
        if (e2) throw e2;
        fasesArte[b.dataset.farte] = url;
        toast(`Diseño de "${b.dataset.fnom}" actualizado`);
        sheetFases(evId, evNombre, volverA);
      } catch (err) { b.disabled = false; b.textContent = antes; fail(err); }
    };
    inp.click();
  });
  document.querySelectorAll("#sheetBody [data-fcup]").forEach(b => b.onclick = () =>
    sheetCuposFase(b.dataset.fcup, b.dataset.fnom, evId, evNombre, volverA));
  $("#fsGo").onclick = async () => {
    const b = $("#fsGo"); b.disabled = true;
    const { error } = await sb.rpc("guardar_fase", {
      p_evento: evId, p_id: $("#fsId").value || null,
      p_nombre: $("#fsN").value.trim(), p_precio: +$("#fsP").value || 0,
      p_cupo: +$("#fsC").value || null,
      p_desde: $("#fsD").value ? new Date($("#fsD").value).toISOString() : null,
      p_hasta: $("#fsH").value ? new Date($("#fsH").value).toISOString() : null,
      p_orden: +$("#fsO").value || 0, p_activo: true });
    b.disabled = false;
    if (error) return fail(error);
    toast("Fase guardada"); sheetFases(evId, evNombre, volverA);
  };
}

/* Cupo de cada team dentro de una tanda.
   Sin esto, los 100 tickets de Hot Tickets se los lleva el que venda más
   rápido y pueden salir todos de un mismo team. Vacío = ese team vende sin
   límite propio, contra el stock general de la fase. */
async function sheetCuposFase(faseId, faseNom, evId, evNombre, volverA) {
  const { data: cupos, error } = await sb.rpc("cupos_fase", { p_fase: faseId });
  if (error) return fail(error);
  const cs = cupos || [];
  const conCupo = cs.filter(c => c.cupo != null);
  sheet(`
    <button class="btn ghost2" style="width:auto;padding:8px 14px;margin-bottom:12px" id="cpBack">${ico("atras")}Volver</button>
    <div class="sh-h">Cupos por team<span class="r-sub">${esc(faseNom)}</span></div>
    <div class="hint" style="margin:0 0 14px">Dejá el campo vacío para que ese team venda sin límite propio. ${conCupo.length ? `Hoy ${conCupo.length} team(s) tienen cupo asignado.` : "Hoy ninguno tiene cupo: se lo lleva el que venda más rápido."}</div>
    <div>${cs.map(c => `
      <div class="list-row rc">
        <div class="r-l" style="flex:1;min-width:0"><span class="relmark">${esc((c.team || "?")[0])}</span>
          <span class="rc-body"><span class="rc-nm">${esc(c.team)}</span>
          <span class="rc-sub"><span>vendió ${c.vendidas}${c.cupo != null ? ` de ${c.cupo} · quedan ${c.quedan}` : " · sin límite propio"}</span></span></span></div>
        <input type="number" min="0" data-cupo="${c.team_id}" value="${c.cupo ?? ""}" placeholder="—"
          style="width:78px;flex-shrink:0;text-align:center;background:var(--bg-2,var(--surface-2));border:1px solid var(--line-2);border-radius:10px;padding:10px;color:var(--text);font-weight:700">
      </div>`).join("") || `<div class="empty">No hay teams activos en este boliche.</div>`}</div>
    <button class="btn primary" id="cpGo" style="margin-top:14px">Guardar cupos</button>`);
  $("#cpBack").onclick = () => sheetFases(evId, evNombre, volverA);
  $("#cpGo").onclick = async () => {
    const b = $("#cpGo"); b.disabled = true;
    for (const inp of document.querySelectorAll("#sheetBody [data-cupo]")) {
      const prev = cs.find(c => c.team_id === inp.dataset.cupo)?.cupo ?? null;
      const nuevo = inp.value === "" ? null : +inp.value;
      if (prev === nuevo) continue;                 // solo se manda lo que cambió
      const { error: e2 } = await sb.rpc("guardar_cupo_team", {
        p_fase: faseId, p_team: inp.dataset.cupo, p_cupo: nuevo || 0 });
      if (e2) { b.disabled = false; return fail(e2); }
    }
    b.disabled = false;
    toast("Cupos guardados");
    sheetCuposFase(faseId, faseNom, evId, evNombre, volverA);
  };
}

/* copiar planimetría de otro evento */
async function sheetCopiar() {
  const { data: evs } = await sb.from("eventos").select("id,nombre,fecha").eq("club_id", club).neq("id", ev.id).order("fecha", { ascending: false }).limit(15);
  sheet(`
    <div class="sh-h">Copiar planimetría</div>
    <div class="field"><label>Desde el evento</label><select id="cpEv">${(evs || []).map(e =>
      `<option value="${e.id}">${esc(e.nombre)} · ${fmtF(e.fecha)}</option>`).join("")}</select></div>
    <button class="btn primary" id="cpGo">Copiar mesas</button>`);
  $("#cpGo").onclick = async () => {
    const { data, error } = await sb.rpc("copiar_mesas", { p_desde: $("#cpEv").value, p_hacia: ev.id });
    if (error) return fail(error);
    toast(data + " mesas copiadas"); closeSheet(); screenMesas();
  };
}

/* ---------- buscar ---------- */
$("#btnBuscar") && ($("#btnBuscar").onclick = () => abrirBuscar());
/* En escritorio ⌘K (Ctrl+K fuera de la Mac) abre la búsqueda desde
   cualquier lado; "/" también, salvo que el foco ya esté en un campo. */
const esMac = /Mac|iPhone|iPad/.test(navigator.platform || navigator.userAgent);
{ const k = $("#btnBuscar kbd"); if (k) k.textContent = esMac ? "⌘ K" : "Ctrl K"; }
document.addEventListener("keydown", e => {
  const atajoK = e.key.toLowerCase() === "k" && (esMac ? e.metaKey : e.ctrlKey) && !e.altKey;
  if (!atajoK && (e.key !== "/" || e.ctrlKey || e.metaKey || e.altKey)) return;
  const t = e.target;
  if (!atajoK && t && (t.tagName === "INPUT" || t.tagName === "TEXTAREA" || t.tagName === "SELECT")) return;
  if (!me || $("#app").classList.contains("hidden")) return;
  e.preventDefault();
  abrirBuscar();
});

/* ---------- cuenta ---------- */
function abrirCuenta() {
  $("#sheetBody").innerHTML = `
    <div class="acct"><div class="avatar">${esc(me.nombre[0])}</div>
    <div class="an">${esc(me.nombre)}</div>
    <div class="as">@${esc(me.usuario)} · ${ROL_LABEL[me.rol]}</div></div>
    <div class="sh-h" style="margin-top:16px">Cambiar mi contraseña</div>
    <div class="field"><input id="pwN" type="password" placeholder="Nueva contraseña (mín. 6)" autocomplete="new-password"></div>
    <button class="btn ghost2" id="pwGo">Cambiar contraseña</button>
    <div style="height:10px"></div>
    <button class="btn danger" onclick="logout()">Cerrar sesión</button>`;
  $("#sheet").classList.add("open"); $("#scrim").classList.add("show");
  $("#pwGo").onclick = async () => {
    const p = $("#pwN").value;
    if (p.length < 6) return toast("Mínimo 6 caracteres", "warn");
    const { error } = await sb.auth.updateUser({ password: p });
    if (error) return fail(error);
    toast("Contraseña actualizada"); closeSheet();
  };
}
// La cuenta se abre desde la barra lateral (escritorio) y desde la
// topbar (celular): son el mismo panel.
$("#avatar") && ($("#avatar").onclick = abrirCuenta);
$("#avatarM") && ($("#avatarM").onclick = abrirCuenta);

/* ============================================================
   CAJA · quiénes aparecen en la lista (sólo @aqueirolo)
   ============================================================
   Interruptor por EVENTO: con él puesto, la caja sólo ve a los
   relacionadores que cargaron prepagadas en ese evento. Cuenta tenerlas en
   el registro — NO importa si esa gente entró. Debajo, las excepciones:
   gente sin prepagadas que igual tiene que aparecer.

   La preferencia es por evento porque "quién vendió" cambia cada noche: un
   interruptor global mostraría a los vendedores de la noche anterior.
   El filtro real lo aplica roster_caja en el servidor
   (db/15-caja-filtro-prepagadas.sql); esta pantalla sólo lo maneja. */
async function sheetCajaFiltro() {
  if (!me.admin_principal) return toast("No autorizado", "warn");
  sheet(`<div class="sh-h">Lista de la caja</div><div class="hint">Cargando…</div>`);
  await renderCajaFiltro();
}
async function renderCajaFiltro() {
  /* el mismo evento que usa la caja: uno abierto; si no, el último cerrado */
  let { data: evA } = await sb.from("eventos").select("id,nombre,estado,fecha")
    .eq("club_id", club).neq("estado", "cerrado").order("fecha").limit(1).maybeSingle();
  if (!evA) {
    const { data: ult } = await sb.from("eventos").select("id,nombre,estado,fecha")
      .eq("club_id", club).order("fecha", { ascending: false }).limit(1).maybeSingle();
    evA = ult || null;
  }
  if (!evA) return sheet(`<div class="sh-h">Lista de la caja</div>
    <div class="empty">Este boliche todavía no tiene ningún evento.</div>`);

  const [{ data: f }, { data: exc }, { data: conPre }] = await Promise.all([
    sb.from("caja_filtro").select("activo").eq("evento_id", evA.id).maybeSingle(),
    sb.from("caja_filtro_excepcion").select("user_id, p:profiles!caja_filtro_exc_user_fkey(nombre,usuario)")
      .eq("evento_id", evA.id),
    sb.rpc("roster_caja", { p_club: club, p_evento: evA.id })
  ]);
  const on = !!f?.activo;
  const listos = (conPre || []);
  const excs = (exc || []);

  /* cuántos hay de cada lado, para que el número no sea una sorpresa al
     prender el interruptor */
  const conPrepagadas = listos.filter(g => g.motivo !== "excepcion").length;
  const totalSinFiltro = on ? null : listos.length;

  sheet(`
    <div class="sh-h">Lista de la caja<span class="r-sub">${esc(evA.nombre)}</span></div>
    <p class="hint" style="margin:0 0 15px">Elegí a quiénes ve la caja cuando entrega las manillas.</p>

    <div class="cf-card ${on ? "on" : ""}">
      <div class="cf-top">
        <div class="cf-tx">
          <span class="cf-t">Sólo los que pusieron prepagadas</span>
          <small class="cf-s">${on
            ? "Activado · la caja ve únicamente a quienes cargaron prepagadas en este evento."
            : "Desactivado · la caja ve a todos los relacionadores."}</small>
        </div>
        <button class="cf-sw ${on ? "on" : ""}" id="cfTog"
          role="switch" aria-checked="${on}" aria-label="Sólo los que pusieron prepagadas"></button>
      </div>
      ${on ? `<div class="cf-num">
        <div class="cf-n"><span class="cf-nv">${listos.length}</span><span class="cf-nk">ve la caja</span></div>
        <div class="cf-n"><span class="cf-nv">${conPrepagadas}</span><span class="cf-nk">con prepagadas</span></div>
        <div class="cf-n"><span class="cf-nv">${excs.length}</span><span class="cf-nk">agregados</span></div>
      </div>` : `<div class="cf-num">
        <div class="cf-n"><span class="cf-nv">${totalSinFiltro}</span><span class="cf-nk">ve la caja</span></div>
      </div>`}
    </div>

    <div class="cf-sec">
      <span class="cf-sec-t">Agregados a mano${excs.length ? `<span class="cf-chip">${excs.length}</span>` : ""}</span>
      <span class="cf-sec-s">aparecen sin prepagadas</span>
    </div>
    <div id="cfExc">${excs.map(x => `
      <div class="list-row rc">
        <div class="r-l" style="flex:1;min-width:0">
          <span class="relmark" style="background:var(--surface-3);color:var(--text-2)">${esc((x.p?.nombre || "?")[0])}</span>
          <span class="rc-body"><span class="rc-nm">${esc(x.p?.nombre || "—")}</span>
            <span class="rc-sub"><span>@${esc(x.p?.usuario || "")}</span></span></span></div>
        <button class="checkin" data-delcf="${x.user_id}" title="Quitar de la lista" style="background:var(--surface-3);color:var(--text-3);border-color:var(--line-2);padding:8px 11px">✕</button>
      </div>`).join("") || `<div class="empty">Nadie agregado a mano.</div>`}</div>
    <button class="btn ghost2" id="cfAdd" style="margin-top:10px">+ Agregar a alguien</button>
    <div id="cfForm"></div>
    ${!on ? `<p class="hint" style="margin-top:14px;font-size:12px">Con el filtro apagado la caja
      ve a todos, así que los agregados a mano no cambian nada — sirven al prenderlo.</p>` : ""}`);

  $("#cfTog").onclick = async () => {
    const { error } = await sb.from("caja_filtro")
      .upsert({ evento_id: evA.id, activo: !on, updated_at: new Date().toISOString() },
              { onConflict: "evento_id" });
    if (error) return fail(error);
    toast(!on ? "Filtro activado — la caja ve sólo a los que pusieron prepagadas"
              : "Filtro desactivado — la caja ve a todos", !on ? "ok" : "warn");
    renderCajaFiltro();
  };
  document.querySelectorAll("#cfExc [data-delcf]").forEach(b => b.onclick = async () => {
    const { error } = await sb.from("caja_filtro_excepcion").delete()
      .eq("evento_id", evA.id).eq("user_id", b.dataset.delcf);
    if (error) return fail(error);
    toast("Excepción quitada", "warn"); renderCajaFiltro();
  });
  $("#cfAdd").onclick = async () => {
    $("#cfAdd").style.display = "none";
    /* BUG DEL "uuid undefined" (2026-08-23): esto usaba `efectivosCache`
       (teams_efectivos) y leía `g.id`. Esa RPC devuelve
       **user_id, nombre, rol, team, team_id** — NO tiene `id` ni `usuario`.
       El <option> salía con value="undefined" y el insert mandaba el string
       "undefined" a una columna uuid:
         invalid input syntax for type uuid: "undefined"
       Se cambia a roster_relacionadores, que devuelve
       **id, nombre, usuario, rol, team, clubs**: trae el `usuario` que hace
       falta para buscar por username y ya viene acotada al club, así que
       los boliches no se mezclan. La clave acá es `id`, la misma que usa
       roster_caja — una sola forma para toda esta pantalla. */
    const { data: roster, error: eRos } = await sb.rpc("roster_relacionadores", { p_club: club });
    if (eRos) { $("#cfAdd").style.display = ""; return fail(eRos); }

    const yaExc = new Set(excs.map(x => x.user_id));
    const yaEnLista = new Set(listos.map(g => g.id));
    const gente = (roster || [])
      .filter(g => (!g.clubs?.length || g.clubs.includes(club))
                && ["rrpp", "jefe"].includes(g.rol)
                && g.id && !yaExc.has(g.id) && !yaEnLista.has(g.id))
      .sort((a, b) => (a.nombre || "").localeCompare(b.nombre || ""));

    /* teams presentes entre los candidatos: no tiene sentido ofrecer un
       team del que no queda nadie por agregar. roster_relacionadores da el
       NOMBRE del team ('Sin team' incluido), no el id. */
    const teamsCand = [...new Set(gente.map(g => g.team).filter(t => t && t !== "Sin team"))]
      .sort((a, b) => a.localeCompare(b));
    const haySinTeam = gente.some(g => !g.team || g.team === "Sin team");

    $("#cfForm").innerHTML = `
      <div class="field" style="margin-top:10px"><label>Team</label>
        <select id="cfTeam">
          <option value="">Todos los teams</option>
          ${teamsCand.map(nom => `<option value="${esc(nom)}">${esc(nom)}</option>`).join("")}
          ${haySinTeam ? `<option value="__sin__">Sin team</option>` : ""}
        </select></div>
      <div class="field"><label>Buscar</label>
        <input id="cfBuscar" placeholder="Buscar relacionador…" autocomplete="off"></div>
      <div class="field"><label>Relacionador</label><select id="cfWho"></select></div>
      <button class="btn primary" id="cfSave">Agregar a la lista de caja</button>`;

    const nrm = s => (s || "").toLowerCase().normalize("NFD").replace(/[̀-ͯ]/g, "");
    const selWho = $("#cfWho"), selTeam = $("#cfTeam"), inpQ = $("#cfBuscar");
    /* Team + búsqueda se combinan: el selector siempre muestra la
       intersección de los dos. */
    const pintar = () => {
      const t = selTeam.value, q = nrm(inpQ.value.trim());
      const sinTeam = g => !g.team || g.team === "Sin team";
      const hits = gente.filter(g =>
        (!t || (t === "__sin__" ? sinTeam(g) : g.team === t)) &&
        (!q || nrm(g.nombre + " " + (g.usuario || "")).includes(q)));
      /* value = el UUID real (roster_relacionadores.id), nunca el usuario */
      selWho.innerHTML = hits.map(g =>
        `<option value="${g.id}">${esc(g.nombre)}${g.usuario ? ` · @${esc(g.usuario)}` : ""}${g.team && g.team !== "Sin team" ? ` · ${esc(g.team)}` : ""}</option>`).join("")
        || `<option value="">— nadie coincide —</option>`;
      const n = hits.length;
      $("#cfSave").disabled = !n;
      $("#cfSave").textContent = n ? "Agregar a la lista de caja" : "No hay a quién agregar";
    };
    selTeam.onchange = pintar;
    inpQ.oninput = pintar;
    pintar();

    $("#cfSave").onclick = async () => {
      const uid = selWho.value;
      /* Protección: nunca mandar un uuid inválido a la base —ni
         "undefined", ni "null", ni un usuario en un campo uuid—. Es defensa
         extra (la causa real ya está arreglada arriba), pero si mañana
         cambia la forma de la RPC el error tiene que ser legible.
         Se valida TAMBIÉN el evento: es el otro uuid del payload. */
      const ES_UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
      if (!uid || !ES_UUID.test(uid))
        return toast("No se pudo identificar al relacionador seleccionado.", "warn");
      if (!evA?.id || !ES_UUID.test(evA.id))
        return toast("No se pudo identificar el evento.", "warn");
      if (yaExc.has(uid) || yaEnLista.has(uid))
        return toast("Este relacionador ya está en la lista de caja.", "warn");

      const { error } = await sb.from("caja_filtro_excepcion")
        .upsert({ evento_id: evA.id, user_id: uid }, { onConflict: "evento_id,user_id" });
      if (error) return fail(error);
      toast("Agregado a la lista de caja"); renderCajaFiltro();
    };
  };
}

/* reporte de rechazados por filtro de puerta, agrupado por rrpp */
async function sheetFiltro() {
  if (!ev) return toast("Elegí un evento", "warn");
  const { data, error } = await sb.rpc("reporte_filtro", { p_evento: ev.id });
  if (error) return fail(error);
  const rows = data || [];
  const total = rows.reduce((a, r) => a + +r.cantidad, 0);
  sheet(`
    <div class="sh-h">Rechazados en puerta · ${esc(ev.nombre)}<span class="r-sub">${total} en total</span></div>
    <div class="hint" style="margin:0 0 12px">Personas que Seguridad marcó como "no pasó el control", agrupadas por el relacionador que las trajo o les vendió.</div>
    ${rows.length ? rows.map(r => `
      <div class="lst-card open" style="margin-bottom:10px">
        <div class="lst-head">
          <span class="lst-nm">${esc(r.rrpp)}${r.team ? ` · ${esc(r.team)}` : ""}</span>
          <span class="lst-cnt"><b>${r.cantidad}</b></span>
        </div>
        <div class="lst-body"><div class="r-sub" style="padding:4px 2px">${(r.personas || []).map(esc).join(" · ")}</div></div>
      </div>`).join("") : `<div class="empty">Nadie fue marcado por filtro en este evento.</div>`}`);
}

/* reset de clave de terceros (admin cualquiera; jefe sus RRPP) */
window.resetClave = async (userId, nombre) => {
  const p = prompt(`Nueva contraseña para ${nombre} (mín. 6):`);
  if (p === null) return;
  if (p.length < 6) return toast("Mínimo 6 caracteres", "warn");
  const { data: { session } } = await sb.auth.getSession();
  const res = await fetch(`${CFG.SUPABASE_URL}/functions/v1/crear-usuario`, {
    method: "POST",
    headers: { "Content-Type": "application/json", Authorization: `Bearer ${session.access_token}` },
    body: JSON.stringify({ action: "reset", user_id: userId, clave: p })
  });
  const out = await res.json();
  if (!res.ok) return toast(out.error || "Error", "warn");
  toast(`Clave de ${nombre} actualizada`);
};

/* ---------- arranque: sesión persistida ---------- */
if (sb) sb.auth.getSession().then(({ data: { session } }) => { if (session) boot(); });

if ("serviceWorker" in navigator && location.protocol === "https:") {
  navigator.serviceWorker.register("sw.js").then(reg => {
    // buscar update al abrir y periódicamente (mantiene la app en la última versión)
    reg.update();
    setInterval(() => reg.update(), 60 * 60 * 1000);
  }).catch(() => { });
  // cuando un SW nuevo toma control, recargar una vez para tomar la versión nueva
  let refreshing = false;
  navigator.serviceWorker.addEventListener("controllerchange", () => {
    if (refreshing) return; refreshing = true; location.reload();
  });
}

/* ============================================================
   MÓDULO BARRA · Fase 1 — inventario
   Stock perpetuo por boliche, en ml. El costo solo lo ve el propietario.
   Estas pantallas solo existen para los roles propietario/barra/deposito:
   mientras nadie los tenga, la app funciona exactamente igual que antes.
   ============================================================ */
let bebidasCache = [], catBarCache = [], barrasCache = [];
const fmtMl = ml => {
  const n = +ml || 0;
  return n >= 1000 ? (n / 1000).toLocaleString("es-BO", { maximumFractionDigits: 1 }) + " L" : Math.round(n) + " ml";
};
const botTxt = (ml, vol) => {
  const b = (+ml || 0) / (+vol || 750);
  return b >= 10 ? Math.round(b) + " bot." : b.toFixed(1).replace(".0", "") + " bot.";
};
async function loadCatBar() {
  if (catBarCache.length) return;
  const { data } = await sb.from("bar_categorias").select("*").eq("activo", true).order("orden");
  catBarCache = data || [];
}
async function loadBebidas() {
  const { data } = await sb.from("bebidas").select("*, c:bar_categorias(nombre)")
    .eq("club_id", club).eq("activo", true).order("nombre");
  bebidasCache = data || [];
}
async function loadBarras() {
  const { data } = await sb.from("barras").select("*").eq("club_id", club).eq("activo", true).order("nombre");
  barrasCache = data || [];
}

/* ---------- PROPIETARIO · Inventario ---------- */
async function screenInventario() {
  await Promise.all([loadCatBar(), loadBebidas(), loadBarras()]);
  const { data: stock, error } = await sb.from("v_bar_stock").select("*").eq("club_id", club).order("nombre");
  if (error) throw error;   // lo muestra conPantalla con Reintentar
  const filas = stock || [];
  const valor = filas.reduce((a, s) => a + (+s.valor_bs || 0), 0);
  const bajos = filas.filter(s => s.bajo_stock);
  const porCat = {};
  filas.forEach(s => (porCat[s.categoria] = porCat[s.categoria] || []).push(s));
  $("#main").innerHTML = `
    ${pgHead({ ey: "Barra", t: "Inventario", s: `${esc(clubNombre(club))} · ${filas.length} bebidas` })}
    <div class="kps">
      ${kpi({ ic: "base", k: "Stock valorizado", v: `Bs ${fmtBs(Math.round(valor))}`, tono: "marca" })}
      ${kpi({ ic: "caja", k: "Por reponer", v: `${bajos.length}`, tono: bajos.length ? "warn" : "ok" })}
    </div>
    <div class="ph-actions" style="margin-bottom:12px">
      <button class="ghost" id="btnRecibir">Cargar compra</button>
      <button class="ghost" id="btnNuevaBebida">+ Bebida</button>
      <button class="ghost" id="btnTragos">Carta</button>
      <button class="ghost" id="btnBarras">Barras (${barrasCache.length})</button>
      <button class="ghost" id="btnTurno">Turno</button>
      <button class="ghost" id="btnConteo">Contar</button>
      <button class="ghost" id="btnCortCfg">Cortesías</button>
    </div>
    ${bajos.length ? `<div class="hint" style="color:var(--warn);margin:0 0 10px">Hay que reponer: ${bajos.map(b => esc(b.nombre)).join(" · ")}</div>` : ""}
    ${!filas.length ? `<div class="empty">Todavía no cargaste bebidas. Empezá con "+ Bebida" y después registrá la compra.</div>` : ""}
    ${Object.entries(porCat).map(([cat, items]) => `
      <div class="sh-h" style="margin-top:16px;font-size:14px">${esc(cat)}<span class="r-sub">${items.length}</span></div>
      ${items.map(s => {
        const pct = Math.min((+s.botellas_equiv || 0) / Math.max(+s.umbral * 2, 1) * 100, 100);
        return `<div class="list-row rc" data-beb="${s.bebida_id}" style="cursor:pointer">
          <div class="r-l" style="flex:1;min-width:0">
            <span class="relmark" style="${s.bajo_stock ? "background:var(--warn);color:#1a1a26" : ""}">${esc(s.nombre[0])}</span>
            <span class="rc-body">
              <span class="rc-nm">${esc(s.nombre)}</span>
              <span class="rc-sub"><span>${botTxt(s.ml_total, s.volumen_ml)} · ${fmtMl(s.ml_total)}${+s.lotes_abiertos ? ` · ${s.lotes_abiertos} lote(s)` : ""}</span></span>
              <span class="bar" style="height:6px;border-radius:99px;background:var(--surface-3);overflow:hidden;margin-top:5px;display:block">
                <i style="display:block;height:100%;width:${pct}%;border-radius:99px;background:${s.bajo_stock ? "var(--warn)" : "linear-gradient(90deg,var(--accent),var(--accent-2))"}"></i></span>
            </span>
          </div>
          <div style="text-align:right;flex-shrink:0">
            <span style="font-family:var(--display);font-size:14px">${fmtBs(Math.round(+s.valor_bs))}</span>
            <span style="display:block;font-size:10px;color:var(--text-3);font-weight:600">Bs</span>
          </div>
        </div>`;
      }).join("")}`).join("")}`;
  $("#btnRecibir").onclick = () => sheetRecibirLote();
  $("#btnNuevaBebida").onclick = () => sheetNuevaBebida();
  $("#btnBarras").onclick = () => sheetBarras();
  $("#btnTragos").onclick = () => sheetTragos();
  $("#btnTurno").onclick = () => sheetTurno();
  $("#btnConteo").onclick = () => { tab = "barconteo"; setTab(); renderTab(); };
  $("#btnCortCfg").onclick = () => sheetCortesiasConfig();
  qsa("#main [data-beb]").forEach(r => r.onclick = () => sheetBebida(r.dataset.beb));
}

/* alta de bebida (el SKU: nombre, categoría, tamaño) */
function sheetNuevaBebida() {
  sheet(`
    <div class="sh-h">Nueva bebida</div>
    <div class="field"><label>Nombre</label><input id="nbN" placeholder="Johnnie Walker Etiqueta Roja" autocomplete="off"></div>
    <div class="row2">
      <div class="field"><label>Categoría</label><select id="nbC">${catBarCache.map(c => `<option value="${c.id}">${esc(c.nombre)}</option>`).join("")}</select></div>
      <div class="field"><label>Presentación</label><select id="nbU">
        <option value="botella">Botella</option><option value="lata">Lata</option><option value="botellin">Botellín</option></select></div>
    </div>
    <div class="row2">
      <div class="field"><label>Contenido (ml)</label><input id="nbV" type="number" value="750"></div>
      <div class="field"><label>Avisar cuando queden</label><input id="nbT" type="number" placeholder="3" ></div>
    </div>
    <p class="hint" style="margin:-4px 0 12px">El contenido es lo que trae la botella llena. El aviso es para que el sistema te marque cuándo reponer.</p>
    <button class="btn primary" id="nbGo">Guardar bebida</button>`);
  $("#nbGo").onclick = async () => {
    const nombre = $("#nbN").value.trim(), vol = +$("#nbV").value;
    if (!nombre) return toast("Poné el nombre", "warn");
    if (!vol || vol <= 0) return toast("El contenido tiene que ser mayor a 0", "warn");
    $("#nbGo").disabled = true;
    const { error } = await sb.from("bebidas").insert({
      club_id: club, categoria_id: $("#nbC").value, nombre, volumen_ml: vol,
      unidad: $("#nbU").value, umbral_bajo: +$("#nbT").value || null
    });
    $("#nbGo").disabled = false;
    if (error) return toast(error.message.includes("duplicate") || error.code === "23505"
      ? `Ya tenés una bebida llamada "${nombre}"` : error.message, "warn");
    toast(`${nombre} agregada`);
    closeSheet(); screenInventario();
  };
}

/* registrar una compra: cantidad + costo por unidad (el costo lo congela el lote) */
function sheetRecibirLote(bebidaId) {
  if (!bebidasCache.length) return toast("Primero cargá al menos una bebida", "warn");
  const esProp = me.rol === "propietario";
  sheet(`
    <div class="sh-h">Cargar compra</div>
    <div class="field"><label>Bebida</label><select id="rlB">${bebidasCache.map(b =>
      `<option value="${b.id}"${b.id === bebidaId ? " selected" : ""}>${esc(b.nombre)} · ${b.volumen_ml} ml</option>`).join("")}</select></div>
    <div class="row2">
      <div class="field"><label>Cuántas ${esProp ? "unidades" : "botellas"}</label><input id="rlQ" type="number" inputmode="numeric" placeholder="12"></div>
      ${esProp ? `<div class="field"><label>Costo por unidad Bs</label><input id="rlC" type="number" inputmode="decimal" placeholder="165"></div>` : ""}
    </div>
    <div class="field"><label>Código del lote (opcional)</label><input id="rlCod" placeholder="se genera solo" autocomplete="off"></div>
    <div class="field"><label>Nota (opcional)</label><input id="rlN" placeholder="compra semanal" autocomplete="off"></div>
    <div id="rlPrev" class="hint" style="margin:-4px 0 12px"></div>
    <button class="btn primary" id="rlGo">Registrar ingreso</button>
    <p class="hint" style="margin-top:10px">${esProp
      ? "El costo queda congelado en este lote: si la próxima compra sale más cara, no cambia el valor de lo que ya tenías."
      : "El costo lo carga el propietario. Vos registrás solo lo que llegó."}</p>`);
  const prev = () => {
    const b = bebidasCache.find(x => x.id === $("#rlB").value);
    const q = +$("#rlQ").value || 0, c = +($("#rlC")?.value || 0);
    $("#rlPrev").innerHTML = q && b
      ? `Entran <b>${fmtMl(q * b.volumen_ml)}</b> de ${esc(b.nombre)}${c ? ` · total <b>${fmtBs(q * c)} Bs</b>` : ""}`
      : "";
  };
  $("#rlB").onchange = prev; $("#rlQ").oninput = prev;
  const rlC = $("#rlC"); if (rlC) rlC.oninput = prev;
  $("#rlGo").onclick = async () => {
    const q = +$("#rlQ").value;
    if (!q || q <= 0) return toast("Poné cuántas unidades llegaron", "warn");
    $("#rlGo").disabled = true;
    const { data, error } = await sb.rpc("bar_recibir_lote", {
      p_bebida: $("#rlB").value, p_cantidad: q,
      p_codigo: $("#rlCod").value || null,
      p_costo: +($("#rlC")?.value || 0) || null,
      p_notas: $("#rlN").value || null
    });
    $("#rlGo").disabled = false;
    if (error) return fail(error);
    toast(`Ingreso registrado · ${data.botellas} unidades (${fmtMl(data.ml)})`);
    closeSheet();
    if (me.rol === "deposito") screenRecepcionMias(); else screenInventario();
  };
}

/* ficha de una bebida: lotes, conteo y baja */
async function sheetBebida(id) {
  const b = bebidasCache.find(x => x.id === id); if (!b) return;
  const [{ data: lotes }, { data: st }] = await Promise.all([
    sb.from("lotes").select("*").eq("bebida_id", id).gt("ml_actual", 0).order("recibido_at"),
    sb.from("v_bar_stock").select("*").eq("bebida_id", id).maybeSingle()
  ]);
  const ls = lotes || [];
  sheet(`
    <div class="sh-h">${esc(b.nombre)}<span class="r-sub">${b.volumen_ml} ml · ${esc(b.c?.nombre || "")}</span></div>
    <div class="stats" style="margin-bottom:12px">
      <div class="stat"><span class="k">En stock</span><span class="v">${botTxt(st?.ml_total || 0, b.volumen_ml)}</span><small>${fmtMl(st?.ml_total || 0)}</small></div>
      <div class="stat"><span class="k">Valor</span><span class="v vio">${fmtBs(Math.round(+st?.valor_bs || 0))} Bs</span></div>
    </div>
    <div class="sh-h" style="margin-top:14px;font-size:14px">Lotes abiertos<span class="r-sub">se consume el más viejo primero</span></div>
    ${ls.map(l => `
      <div class="list-row rc">
        <div class="r-l" style="flex:1;min-width:0"><span class="rc-body">
          <span class="rc-nm">${esc(l.codigo)}</span>
          <span class="rc-sub"><span>${fmtMl(l.ml_actual)} de ${fmtMl(l.cant_inicial * l.volumen_ml)} · ${fmtBs(l.costo_unitario)} Bs c/u · ${fmtD(l.recibido_at)}</span></span>
        </span></div>
        <div style="display:flex;gap:6px;flex-shrink:0">
          <button class="checkin" data-conteo="${l.id}" style="background:var(--surface-3);color:var(--text-2);border-color:var(--line-2)">Contar</button>
          <button class="checkin" data-baja="${l.id}" style="background:var(--surface-3);color:var(--danger);border-color:var(--line-2)">Baja</button>
        </div>
      </div>`).join("") || `<div class="empty">Sin stock. Cargá una compra.</div>`}
    <div style="height:12px"></div>
    <button class="btn ghost2" id="fbRecibir">Cargar compra de ${esc(b.nombre)}</button>`);
  $("#fbRecibir").onclick = () => sheetRecibirLote(id);
  document.querySelectorAll("#sheetBody [data-conteo]").forEach(x => x.onclick = () =>
    sheetConteo(ls.find(l => l.id === x.dataset.conteo), b));
  document.querySelectorAll("#sheetBody [data-baja]").forEach(x => x.onclick = () =>
    sheetBaja(ls.find(l => l.id === x.dataset.baja), b));
}

/* conteo físico: se escribe lo que hay de verdad y el sistema explica la diferencia */
function sheetConteo(l, b) {
  if (!l) return;
  sheet(`
    <div class="sh-h">Contar ${esc(l.codigo)}<span class="r-sub">${esc(b.nombre)}</span></div>
    <div class="hint" style="margin:0 0 12px">El sistema dice que quedan <b>${fmtMl(l.ml_actual)}</b> (${botTxt(l.ml_actual, l.volumen_ml)}). Poné lo que contaste de verdad.</div>
    <div class="row2">
      <div class="field"><label>Botellas enteras</label><input id="ctB" type="number" inputmode="numeric" value="${Math.floor(l.ml_actual / l.volumen_ml)}"></div>
      <div class="field"><label>Y una abierta al… %</label><input id="ctP" type="number" inputmode="numeric" placeholder="50" value="${Math.round((l.ml_actual % l.volumen_ml) / l.volumen_ml * 100)}"></div>
    </div>
    <div id="ctPrev" class="hint" style="margin:-4px 0 12px"></div>
    <div class="field"><label>Motivo (opcional)</label><input id="ctM" placeholder="conteo de cierre" autocomplete="off"></div>
    <button class="btn primary" id="ctGo">Guardar conteo</button>`);
  const calc = () => (+$("#ctB").value || 0) * l.volumen_ml + (+$("#ctP").value || 0) / 100 * l.volumen_ml;
  const prev = () => {
    const ml = calc(), d = ml - l.ml_actual;
    $("#ctPrev").innerHTML = !d ? "Coincide con el sistema ✓"
      : `<span style="color:${d < 0 ? "var(--danger)" : "var(--warn)"}">${d < 0 ? "Faltan" : "Sobran"} <b>${fmtMl(Math.abs(d))}</b> (${fmtBs(Math.abs(Math.round(l.costo_unitario * d / l.volumen_ml)))} Bs)</span>`;
  };
  $("#ctB").oninput = prev; $("#ctP").oninput = prev; prev();
  $("#ctGo").onclick = async () => {
    $("#ctGo").disabled = true;
    const { data, error } = await sb.rpc("bar_ajuste_conteo", {
      p_lote: l.id, p_ml_fisico: calc(), p_evento: ev?.id || null, p_motivo: $("#ctM").value || null
    });
    $("#ctGo").disabled = false;
    if (error) return fail(error);
    toast(data?.sin_cambios ? "El conteo coincide" : `Conteo guardado · ${fmtMl(Math.abs(data.delta_ml))} de diferencia`, data?.sin_cambios ? "" : "warn");
    closeSheet(); screenInventario();
  };
}

/* baja: rotura, derrame, cortesía. Siempre con motivo. */
function sheetBaja(l, b) {
  if (!l) return;
  sheet(`
    <div class="sh-h">Dar de baja<span class="r-sub">${esc(b.nombre)} · ${esc(l.codigo)}</span></div>
    <div class="row2">
      <div class="field"><label>Botellas</label><input id="bjB" type="number" inputmode="numeric" value="0"></div>
      <div class="field"><label>ml sueltos</label><input id="bjM" type="number" inputmode="numeric" value="0"></div>
    </div>
    <div class="field"><label>Motivo</label><select id="bjMot">
      <option>Se rompió</option><option>Se derramó</option><option>Cortesía</option>
      <option>Vencida</option><option>Otro</option></select></div>
    <div id="bjPrev" class="hint" style="margin:-4px 0 12px"></div>
    <button class="btn danger" id="bjGo">Registrar baja</button>
    <p class="hint" style="margin-top:10px">Queda registrado quién la dio de baja y cuándo. Es merma explicada: sale del stock pero no se confunde con lo que falta sin razón.</p>`);
  const calc = () => (+$("#bjB").value || 0) * l.volumen_ml + (+$("#bjM").value || 0);
  const prev = () => {
    const ml = calc();
    $("#bjPrev").innerHTML = ml ? `Salen <b>${fmtMl(ml)}</b> · ${fmtBs(Math.round(l.costo_unitario * ml / l.volumen_ml))} Bs` : "";
  };
  $("#bjB").oninput = prev; $("#bjM").oninput = prev;
  $("#bjGo").onclick = async () => {
    const ml = calc();
    if (!ml) return toast("Poné cuánto se perdió", "warn");
    if (ml > l.ml_actual) return toast(`Ese lote solo tiene ${fmtMl(l.ml_actual)}`, "warn");
    $("#bjGo").disabled = true;
    const { error } = await sb.rpc("bar_baja", { p_lote: l.id, p_ml: ml, p_motivo: $("#bjMot").value, p_evento: ev?.id || null });
    $("#bjGo").disabled = false;
    if (error) return fail(error);
    toast(`Baja registrada · ${fmtMl(ml)}`, "warn");
    closeSheet(); screenInventario();
  };
}

/* barras físicas del boliche */
async function sheetBarras() {
  await loadBarras();
  sheet(`
    <div class="sh-h">Barras · ${clubNombre(club)}</div>
    <div>${barrasCache.map(b => `
      <div class="list-row rc"><div class="r-l" style="flex:1"><span class="rc-body">
        <span class="rc-nm">${esc(b.nombre)}</span><span class="rc-sub"><span>Planta ${b.planta}</span></span></span></div>
      </div>`).join("") || `<div class="empty">Sin barras cargadas.</div>`}</div>
    <div class="row2" style="margin-top:10px">
      <div class="field"><label>Nueva barra</label><input id="nbaN" placeholder="Barra planta alta"></div>
      <div class="field"><label>Planta</label><input id="nbaP" type="number" value="1"></div>
    </div>
    <button class="btn primary" id="nbaGo">Agregar barra</button>`);
  $("#nbaGo").onclick = async () => {
    const nombre = $("#nbaN").value.trim();
    if (!nombre) return toast("Poné el nombre", "warn");
    const { error } = await sb.from("barras").insert({ club_id: club, nombre, planta: +$("#nbaP").value || 1 });
    if (error) return toast(error.code === "23505" ? "Ya existe una barra con ese nombre" : error.message, "warn");
    toast("Barra agregada"); sheetBarras();
  };
}

/* ---------- PROPIETARIO · Movimientos ---------- */
async function screenBarMovimientos() {
  const { data, error } = await sb.from("v_bar_movimientos").select("*")
    .eq("club_id", club).order("created_at", { ascending: false }).limit(200);
  if (error) throw error;   // lo muestra conPantalla con Reintentar
  const movs = data || [];
  const ICO = { entrada: ico("recibir"), salida: ico("salida"), ajuste: ico("ajuste"), baja: ico("baja"), anulacion: ico("deshacer"), devolucion: ico("deshacer") };
  $("#main").innerHTML = `
    ${pgHead({ ey: "Barra", t: "Movimientos", s: `Últimos ${movs.length}` })}
    <div class="hint" style="margin:0 0 12px">Todo lo que entró y salió, con quién y cuándo. Nada se borra: una corrección queda como un movimiento más.</div>
    <div>${movs.map(m => `
      <div class="list-row rc">
        <div class="r-l" style="flex:1;min-width:0">
          <span class="relmark" style="background:var(--surface-3);font-size:15px">${ICO[m.tipo] || "•"}</span>
          <span class="rc-body">
            <span class="rc-nm">${esc(m.bebida)}</span>
            <span class="rc-sub"><span>${esc(m.motivo || m.tipo)} · ${esc(m.quien || "—")} · ${new Date(m.created_at).toLocaleString("es-BO", { day: "2-digit", month: "short", hour: "2-digit", minute: "2-digit", hour12: false })}</span></span>
          </span>
        </div>
        <div style="text-align:right;flex-shrink:0">
          <span style="font-family:var(--display);font-size:13.5px;color:${+m.ml_delta < 0 ? "var(--danger)" : "var(--ok)"}">${+m.ml_delta > 0 ? "+" : ""}${fmtMl(Math.abs(m.ml_delta))}</span>
          <span style="display:block;font-size:10px;color:var(--text-3);font-weight:600">${fmtBs(Math.abs(Math.round(+m.costo)))} Bs</span>
        </div>
      </div>`).join("") || `<div class="empty">Sin movimientos todavía.</div>`}</div>`;
}

/* ---------- PROPIETARIO · conteo de la noche ----------
   Todo lo que hay que contar en una lista. Los valores del sistema vienen
   precargados, así que contar es corregir lo que no coincide y no teclear
   cuarenta veces. Un solo Guardar manda todo junto.

   Sin esto la merma no se puede calcular: v_bar_merma necesita apertura y
   cierre, y por eso la analítica muestra "faltan conteos". */
let conteoMomento = "cierre", conteoLineas = {};

async function screenBarConteo() {
  if (!ev) { $("#main").innerHTML = `<div class="empty">No hay evento abierto.</div>`; return; }
  const { data, error } = await sb.rpc("bar_conteo_pendiente",
    { p_evento: ev.id, p_momento: conteoMomento });
  if (error) throw error;   // lo muestra conPantalla con Reintentar
  const filas = data || [];
  const yaCont = filas.filter(f => f.ml_contado != null).length;
  conteoLineas = {};
  filas.forEach(f => {
    const ml = f.ml_contado != null ? +f.ml_contado : +f.ml_sistema;
    conteoLineas[f.lote_id] = {
      bot: Math.floor(ml / f.volumen_ml),
      pct: Math.round((ml % f.volumen_ml) / f.volumen_ml * 100),
      vol: +f.volumen_ml, sistema: +f.ml_sistema,
      // El ml exacto con el que arrancó la fila, y si alguien la tocó.
      // El campo de porcentaje es entero: en una botella de 1500 ml, 1 % son
      // 15 ml, así que reconstruir "17 bot + 87 %" no devuelve el número
      // original. Si mandáramos eso para las filas que nadie tocó, el guardar
      // inventaría ajustes de unos pocos ml en todo el inventario — y esos
      // ajustes fantasma ensucian justo la merma que esta pantalla habilita.
      orig: ml, tocado: false
    };
  });

  const porCat = {};
  filas.forEach(f => (porCat[f.categoria || "Sin categoría"] ||= []).push(f));

  $("#main").innerHTML = `
    ${pgHead({ ey: "Barra", t: "Conteo", s: `${esc(ev.nombre)} · ${filas.length} lote(s)` })}
    <div class="seg" style="margin-bottom:10px">
      <button class="segbtn ${conteoMomento === "apertura" ? "on" : ""}" data-cm="apertura">Apertura</button>
      <button class="segbtn ${conteoMomento === "cierre" ? "on" : ""}" data-cm="cierre">Cierre</button>
    </div>
    <div class="hint" style="margin:0 0 12px">Vienen cargados los números del sistema. Cambiá solo lo que no coincida.
      ${yaCont ? `<b>${yaCont} ya contado(s).</b>` : ""}</div>
    ${!filas.length ? `<div class="empty">No hay nada con stock para contar.</div>` : ""}
    ${Object.entries(porCat).map(([cat, items]) => `
      <div class="sh-h" style="margin-top:14px;font-size:14px">${esc(cat)}<span class="r-sub">${items.length}</span></div>
      ${items.map(f => `
        <div class="list-row rc" data-cl="${f.lote_id}" style="align-items:center">
          <div class="r-l" style="flex:1;min-width:0"><span class="rc-body">
            <span class="rc-nm">${esc(f.bebida)}</span>
            <span class="rc-sub"><span>${esc(f.codigo)} · sistema ${botTxt(f.ml_sistema, f.volumen_ml)}</span></span>
            <span class="rc-sub cdif" style="margin-top:3px"></span>
          </span></div>
          <div style="display:flex;gap:6px;flex-shrink:0;align-items:center">
            <input class="cbot" type="number" inputmode="numeric" value="${conteoLineas[f.lote_id].bot}"
              style="width:56px;text-align:center;padding:8px 4px;border-radius:10px;
                     background:var(--surface-3);border:1px solid var(--line-2);color:var(--text)">
            <span style="font-size:11px;color:var(--text-3)">bot</span>
            <input class="cpct" type="number" inputmode="numeric" value="${conteoLineas[f.lote_id].pct}"
              style="width:52px;text-align:center;padding:8px 4px;border-radius:10px;
                     background:var(--surface-3);border:1px solid var(--line-2);color:var(--text)">
            <span style="font-size:11px;color:var(--text-3)">%</span>
          </div>
        </div>`).join("")}`).join("")}
    ${filas.length ? `<div style="position:sticky;bottom:calc(var(--nav-h) + 8px);margin-top:16px;
        background:var(--surface-2);border:1px solid var(--line-2);border-radius:16px;padding:12px 14px">
      <div id="ctResumen" class="hint" style="margin:0 0 9px"></div>
      <button class="btn primary" id="ctGuardar">Guardar conteo de ${conteoMomento}</button>
    </div>` : ""}`;

  qsa("#main [data-cm]").forEach(b => b.onclick = () => {
    conteoMomento = b.dataset.cm; screenBarConteo();
  });

  /* lo que se va a grabar de una fila: si nadie la tocó, el número exacto con
     el que vino; si la tocaron, lo que se tecleó */
  const mlDe = st => st.tocado ? st.bot * st.vol + st.pct / 100 * st.vol : st.orig;

  const recalc = () => {
    let dif = 0, tocados = 0;
    qsa("#main [data-cl]").forEach(row => {
      const id = row.dataset.cl, st = conteoLineas[id];
      st.bot = +row.querySelector(".cbot").value || 0;
      st.pct = Math.max(0, Math.min(+row.querySelector(".cpct").value || 0, 99));
      const ml = mlDe(st);
      const d = ml - st.sistema;
      const cel = row.querySelector(".cdif");
      cel.innerHTML = !d ? `<span style="color:var(--ok)">coincide ✓</span>`
        : `<span style="color:${d < 0 ? "var(--danger)" : "var(--warn)"}">${d < 0 ? "faltan" : "sobran"} ${fmtMl(Math.abs(d))}</span>`;
      if (d) { dif += Math.abs(d); tocados++; }
    });
    const r = $("#ctResumen");
    if (r) r.innerHTML = tocados
      ? `<span style="color:var(--warn)">${tocados} lote(s) con diferencia · ${fmtMl(dif)} en total</span>`
      : `Todo coincide con el sistema.`;
  };
  qsa("#main .cbot, #main .cpct").forEach(i => i.oninput = e => {
    const fila = e.target.closest("[data-cl]");
    if (fila && conteoLineas[fila.dataset.cl]) conteoLineas[fila.dataset.cl].tocado = true;
    recalc();
  });
  recalc();

  const g = $("#ctGuardar");
  if (g) g.onclick = async () => {
    g.disabled = true;
    /* Lo que se manda es un conteo físico ABSOLUTO: la base lo aplica contra el
       saldo de este momento. Si mandáramos la foto que se cargó al abrir la
       pantalla, todo lo que el bartender vendió mientras tanto se revertiría —
       y el ledger no lo delataría, porque `lotes` y `stock_mov` se mueven
       juntos. Por eso, justo antes de grabar, se vuelve a leer el saldo real y
       las filas que nadie tocó se mandan con ESE número, no con el viejo. Las
       tocadas van con lo que se tecleó, que es el punto de contar. */
    const { data: fresco, error: eF } = await sb.rpc("bar_conteo_pendiente",
      { p_evento: ev.id, p_momento: conteoMomento });
    if (eF) { g.disabled = false; return fail(eF); }
    const ahora = {};
    (fresco || []).forEach(f => (ahora[f.lote_id] = +f.ml_sistema));
    const lineas = Object.entries(conteoLineas).map(([lote_id, s]) =>
      ({ lote_id, ml_fisico: s.tocado ? mlDe(s) : (ahora[lote_id] ?? s.orig) }));
    const { data: res, error: err } = await sb.rpc("bar_conteo_masivo",
      { p_evento: ev.id, p_momento: conteoMomento, p_lineas: lineas });
    g.disabled = false;
    if (err) return fail(err);
    toast(res.ajustados
      ? `Conteo guardado · ${res.ajustados} lote(s) ajustado(s)`
      : `Conteo guardado · todo coincidía`, res.ajustados ? "warn" : "ok");
    screenBarConteo();
  };
}

/* ---------- RECEPCIÓN (depósito) ---------- */
async function screenRecepcion() {
  await loadBebidas();
  $("#main").innerHTML = `
    ${pgHead({ ey: "Depósito", t: "Registrar lo que llega" })}
    <div class="hint" style="margin:0 0 14px">Anotá lo que entra al depósito. No manejás costos ni ves el stock total — de eso se ocupa el propietario.</div>
    <button class="btn primary" id="rcGo">Registrar ingreso</button>`;
  $("#rcGo").onclick = () => sheetRecibirLote();
}
async function screenRecepcionMias() {
  const { data } = await sb.from("lotes").select("codigo, cant_inicial, recibido_at, b:bebidas(nombre, volumen_ml)")
    .eq("recibido_por", me.id).order("recibido_at", { ascending: false }).limit(80);
  const ls = data || [];
  $("#main").innerHTML = `
    ${pgHead({ ey: "Depósito", t: "Lo que registraste", s: `${ls.length} registro${ls.length === 1 ? "" : "s"}` })}
    <div>${ls.map(l => `
      <div class="list-row rc">
        <div class="r-l" style="flex:1;min-width:0"><span class="relmark" style="background:var(--surface-3)">${ico("recibir")}</span>
          <span class="rc-body"><span class="rc-nm">${esc(l.b?.nombre || "—")}</span>
            <span class="rc-sub"><span>${esc(l.codigo)} · ${new Date(l.recibido_at).toLocaleString("es-BO", { day: "2-digit", month: "short", hour: "2-digit", minute: "2-digit", hour12: false })}</span></span></span></div>
        <div style="text-align:right;flex-shrink:0">
          <span style="font-family:var(--display);font-size:15px">${l.cant_inicial}</span>
          <span style="display:block;font-size:10px;color:var(--text-3);font-weight:600">unid.</span></div>
      </div>`).join("") || `<div class="empty">Todavía no registraste ingresos.</div>`}</div>
    <div class="hint" style="margin-top:12px">Si te equivocaste en una cantidad, avisale al propietario: él lo corrige y queda registrado el ajuste.</div>`;
}


/* ============================================================
   MÓDULO BARRA · Fase 2 — punto de venta
   El bartender solo ve la carta con precio de venta. Cada trago que
   registra descuenta del stock real; si no alcanza, la venta no pasa.

   El catálogo se pide UNA vez al entrar y vive en memoria. Tocar un trago
   no vuelve a la red ni repinta la pantalla: parchea la tarjeta y el pie.
   Antes eran dos llamadas por toque, y armar una ronda de seis tragos
   eran doce viajes — medio segundo de lag por dedo en el wifi del boliche.
   ============================================================ */
let posBarra = null, posCarrito = {}, posDisp = [], posMias = [];
let posCortesias = [], posCortSel = null, posCat = "", posBusca = "";
let posUltima = null;   // {id, total, at} — para poder anular lo recién cobrado

/* El carrito es de una barra y una noche. Si se cambia de evento o de
   boliche hay que soltarlo: si no, quedan tragos de otro contexto que el
   catálogo nuevo no conoce, el pie los cuenta pero no los suma, y cobrar
   rebota contra el servidor sin que se entienda por qué. */
function posReset() {
  posBarra = null; posCarrito = {}; posDisp = []; posMias = [];
  posCortSel = null; posUltima = null; posAnulArm = null; posCat = ""; posBusca = "";
}

/* cuántos vasos quedan de un trago contando lo que ya está en el carrito */
const posQuedan = t => Math.max(0, (+t.alcanza_para || 0) - (posCarrito[t.id] || 0));

/* los tragos que pasan el filtro de categoría y búsqueda */
function posVisibles() {
  const q = posBusca.trim().toLowerCase();
  return posDisp.filter(t =>
    (!posCat || (t.categoria || "") === posCat) &&
    (q.length < 2 || (t.nombre || "").toLowerCase().includes(q)));
}

/* ---- red: solo acá ---- */
async function posCargar() {
  await loadBarras();
  posMias = barrasCache;
  if (me.rol === "barra") {
    const { data: st } = await sb.from("bar_staff").select("barra_id")
      .eq("evento_id", ev.id).eq("user_id", me.id);
    const ids = new Set((st || []).map(x => x.barra_id));
    posMias = barrasCache.filter(b => ids.has(b.id));
  }
  if (!posMias.length) { posDisp = []; return; }
  if (!posBarra || !posMias.find(b => b.id === posBarra)) posBarra = posMias[0].id;
  const { data } = await sb.rpc("bar_disponibilidad", { p_club: club, p_barra: posBarra });
  posDisp = data || [];
}

/* ---------- cola de ventas sin señal ----------
   El wifi de un boliche se cae. Si la venta se pierde con él, el bartender
   deja de cobrar y la noche se contabiliza a mano.

   Cada venta lleva una client_key generada ACÁ, antes de salir. Si el
   servidor ya la había recibido y lo que se perdió fue la respuesta, el
   reintento encuentra la venta hecha y devuelve la misma: no cobra dos
   veces. Esa es toda la razón de que la clave la genere el teléfono y no
   la base.

   Solo efectivo entra acá: una venta por QR sin señal no tiene sentido
   porque el cliente tampoco puede pagar. Eso se filtra en posCobrar,
   antes de encolar. */
const COLA_KEY = "barra.cola.v1";
const colaBarra = {
  leer() { try { return JSON.parse(localStorage.getItem(COLA_KEY) || "[]"); } catch { return []; } },
  guardar(a) { localStorage.setItem(COLA_KEY, JSON.stringify(a)); },
  pendientes() { return this.leer().length; },
  encolar(payload) {
    const a = this.leer();
    a.push({ ...payload, at: Date.now() });
    this.guardar(a);
    return payload.p_client_key;
  },
  async drenar() {
    const a = this.leer();
    if (!a.length) return { enviadas: 0, fallidas: 0 };
    const quedan = []; let enviadas = 0;
    for (const v of a) {
      const { at, ...args } = v;
      const { error } = await sb.rpc("bar_vender", args);
      // un error de negocio (sin stock, cupo agotado) no se reintenta para
      // siempre: se descarta y se avisa. Solo se guarda lo que falló por red.
      if (!error) enviadas++;
      else if (esFallaDeRed(error)) quedan.push(v);
      else { enviadas++; toast(`Una venta en cola no entró: ${error.message}`, "warn"); }
    }
    this.guardar(quedan);
    return { enviadas, fallidas: quedan.length };
  }
};
const esFallaDeRed = e =>
  window.__offline || !navigator.onLine ||
  /fetch|network|failed to fetch|timeout/i.test(e?.message || "");

/* ============================================================
   COLA DE PUERTA · el check-in no se pierde por falta de señal
   ============================================================
   La barra ya tenía cola propia (colaBarra) porque una venta no puede
   perderse. En la puerta pasa lo mismo y era lo que faltaba: si se corta
   el wifi con gente entrando, el portero se queda sin poder validar y la
   fila se para.

   Ahora el ingreso se guarda en el teléfono y se envía solo cuando
   vuelve la señal. El operador ve la persona como ingresada al instante
   y sigue trabajando.

   Sólo se encola lo que registra un ingreso. Las consultas no: si no hay
   señal para leer, no hay nada que guardar.
   ============================================================ */

const COLA_PUERTA_KEY = "cola-puerta-v1";

const colaPuerta = {
  leer() { try { return JSON.parse(localStorage.getItem(COLA_PUERTA_KEY) || "[]"); } catch { return []; } },
  guardar(a) { localStorage.setItem(COLA_PUERTA_KEY, JSON.stringify(a)); },
  pendientes() { return this.leer().length; },

  /* rpc: nombre de la función; args: sus parámetros; etiqueta: para el aviso. */
  encolar(rpc, args, etiqueta) {
    const a = this.leer();
    a.push({ rpc, args, etiqueta, at: Date.now() });
    this.guardar(a);
    this.pintarAviso();
  },

  async drenar() {
    const a = this.leer();
    if (!a.length) return { enviadas: 0, fallidas: 0 };
    const quedan = []; let enviadas = 0;
    for (const v of a) {
      const { error } = await sb.rpc(v.rpc, v.args);
      // Un error de negocio ("ya había ingresado") no se reintenta para
      // siempre: se descarta con aviso. Sólo se guarda lo que falló por red.
      if (!error) enviadas++;
      else if (esFallaDeRed(error)) quedan.push(v);
      else { enviadas++; toast(`${v.etiqueta || "Un ingreso"} no se pudo registrar: ${error.message}`, "warn"); }
    }
    this.guardar(quedan);
    this.pintarAviso();
    return { enviadas, fallidas: quedan.length };
  },

  /* Barra fija: el portero tiene que saber que está trabajando sin señal,
     sin que eso le corte el paso. */
  pintarAviso() {
    const n = this.pendientes();
    let el = document.getElementById("colaAviso");
    if (!n) { if (el) el.remove(); return; }
    if (!el) {
      el = document.createElement("div");
      el.id = "colaAviso";
      el.className = "cola-aviso";
      document.body.appendChild(el);
      el.onclick = async () => {
        if (!navigator.onLine) return toast("Todavía sin señal", "warn");
        const { enviadas } = await this.drenar();
        if (enviadas) toast(`${enviadas} ingreso(s) registrados`);
      };
    }
    el.innerHTML = `<span class="cola-pt"></span>
      <span>${n} ingreso${n === 1 ? "" : "s"} sin enviar</span>
      <span class="cola-cta">${navigator.onLine ? "Reintentar" : "Sin señal"}</span>`;
  }
};

/* Registra un ingreso tolerando cortes de señal.
   Devuelve { ok, encolado, data } para que quien llama decida qué mostrar. */
async function ingresoResiliente(rpc, args, etiqueta) {
  if (!navigator.onLine || window.__offline) {
    colaPuerta.encolar(rpc, args, etiqueta);
    return { ok: true, encolado: true };
  }
  const { data, error } = await sb.rpc(rpc, args);
  if (!error) return { ok: true, encolado: false, data };
  if (esFallaDeRed(error)) {
    colaPuerta.encolar(rpc, args, etiqueta);
    return { ok: true, encolado: true };
  }
  return { ok: false, error };
}

/* Al volver la señal la cola se vacía sola: el portero no tiene que
   acordarse de tocar nada. */
window.addEventListener("online", async () => {
  colaPuerta.pintarAviso();
  if (!colaPuerta.pendientes() || !sb) return;
  const { enviadas } = await colaPuerta.drenar();
  if (enviadas) {
    toast(`Volvió la señal · ${enviadas} ingreso(s) registrados`);
    if (tab === "listas") renderTab();
  }
});
window.addEventListener("offline", () => colaPuerta.pintarAviso());


/* que se drene sola cuando vuelve la conexión, sin esperar a que el
   bartender note la barra amarilla y toque Reintentar. */
window.addEventListener("online", async () => {
  if (!colaBarra.pendientes() || !sb) return;
  const { enviadas } = await colaBarra.drenar();
  if (enviadas) {
    toast(`Volvió la señal · ${enviadas} venta(s) enviadas`);
    if (tab === "barpos") { await posCargar(); posPintar(); }
  }
});

async function screenBarPOS() {
  if (!ev) { $("#main").innerHTML = `<div class="empty">No hay ningún evento abierto en este boliche.</div>`; return; }
  $("#main").innerHTML = `<div class="empty">Cargando la carta…</div>`;
  await posCargar();
  posPintar();
}

/* ---- pintar: sin red ---- */
function posPintar() {
  if (!posMias.length) {
    $("#main").innerHTML = `<div class="sh-h">Vender</div>
      <div class="empty">No estás asignado a ninguna barra en ${esc(ev.nombre)}. Pedile al propietario que te asigne.</div>`;
    return;
  }
  const cats = [...new Set(posDisp.map(t => t.categoria).filter(Boolean))];
  const vis = posVisibles();
  $("#main").innerHTML = `
    ${pgHead({ ey: "Barra", t: "Vender", s: `${esc(ev.nombre)} · ${posDisp.length} tragos` })}
    ${colaBarra.pendientes() ? `<div class="hint" style="background:rgba(246,180,74,.12);
      border:1px solid rgba(246,180,74,.35);border-radius:12px;padding:10px 13px;margin-bottom:10px;color:var(--warn)">
      ${colaBarra.pendientes()} venta(s) esperando señal
      <button class="checkin" id="posDrenar" style="float:right;background:var(--surface-3);
        color:var(--text-2);border-color:var(--line-2);padding:4px 9px">Reintentar</button></div>` : ""}
    ${posMias.length > 1 ? `<div class="seg" style="margin-bottom:10px">${posMias.map(b =>
      `<button class="segbtn ${b.id === posBarra ? "on" : ""}" data-pb="${b.id}">${esc(b.nombre)}</button>`).join("")}</div>` : ""}
    ${cats.length > 1 ? `<div class="seg" style="margin-bottom:10px">
      <button class="segbtn ${posCat ? "" : "on"}" data-pc="">Todo</button>
      ${cats.map(c => `<button class="segbtn ${posCat === c ? "on" : ""}" data-pc="${esc(c)}">${esc(c)}</button>`).join("")}</div>` : ""}
    ${posDisp.length > 8 ? `<div class="field" style="margin-bottom:10px">
      <input id="posQ" placeholder="Buscar trago…" autocomplete="off" value="${esc(posBusca)}"></div>` : ""}
    ${posCortSel ? `<div class="hint" id="posCortBox" style="background:rgba(246,180,74,.12);border:1px solid rgba(246,180,74,.35);border-radius:12px;padding:10px 13px;margin-bottom:10px;color:var(--warn)">
      Cortesía de <b>${esc(posCortSel.nombre)}</b> · le quedan ${posCortSel.cupo - posCortSel.usados} de ${posCortSel.cupo}
      <button class="checkin" id="posCortX" style="float:right;background:var(--surface-3);color:var(--text-3);border-color:var(--line-2);padding:4px 9px">✕</button></div>` : ""}
    ${!vis.length ? `<div class="empty">${posDisp.length ? "Ningún trago coincide." : "No hay tragos cargados para esta barra."}</div>` : ""}
    <div id="posGrid" style="display:grid;grid-template-columns:1fr 1fr;gap:9px">
      ${vis.map(posTarjeta).join("")}
    </div>
    <div id="posPie"></div>`;

  qsa("#main [data-pb]").forEach(b => b.onclick = async () => {
    posBarra = b.dataset.pb; posCarrito = {}; posCortSel = null;
    $("#main").innerHTML = `<div class="empty">Cargando la carta…</div>`;
    await posCargar(); posPintar();
  });
  qsa("#main [data-pc]").forEach(b => b.onclick = () => {
    posCat = b.dataset.pc; posPintar();
  });
  const q = $("#posQ");
  if (q) q.oninput = e => {
    posBusca = e.target.value;
    // solo se repinta la grilla: si repintáramos todo, el input pierde el foco
    $("#posGrid").innerHTML = posVisibles().map(posTarjeta).join("");
    posBind();
  };
  const cx = $("#posCortX"); if (cx) cx.onclick = () => { posCortSel = null; posPintar(); };
  const dr = $("#posDrenar");
  if (dr) dr.onclick = async () => {
    dr.disabled = true;
    const { enviadas, fallidas } = await colaBarra.drenar();
    toast(fallidas ? `${enviadas} enviadas · ${fallidas} siguen esperando`
                   : `${enviadas} venta(s) enviadas`, fallidas ? "warn" : "ok");
    await posCargar(); posPintar();
  };
  posBind();
  posPie();
}

/* una tarjeta. Es su propio nodo para poder reemplazarla sola. */
function posTarjeta(t) {
  const n = posCarrito[t.id] || 0, sin = posQuedan(t) <= 0 && !n;
  return `<div class="rc" data-pt="${t.id}" style="text-align:center;padding:11px 10px;position:relative;
      opacity:${sin ? ".45" : "1"};${n ? "border-color:var(--accent)!important;background:var(--accent-soft)" : ""}">
    <div style="font-weight:600;font-size:13.5px;line-height:1.2">${esc(t.nombre)}</div>
    <div style="font-family:var(--display);font-size:15px;color:var(--amber,#ffc53d);margin-top:3px">${fmtBs(t.precio)} Bs</div>
    <div style="font-size:10.5px;color:var(--text-3);margin-top:2px">${sin ? "sin stock" : `quedan ${posQuedan(t)}`}</div>
    <div style="display:flex;align-items:center;justify-content:center;gap:10px;margin-top:7px">
      <button class="checkin" data-menos="${t.id}" style="padding:5px 12px;font-size:16px;line-height:1;
        background:var(--surface-3);color:${n ? "var(--text-2)" : "var(--text-3)"};border-color:var(--line-2);
        visibility:${n ? "visible" : "hidden"}">−</button>
      <span style="font-family:var(--display);font-size:18px;min-width:22px;color:${n ? "var(--accent-2)" : "var(--text-3)"}">${n || "0"}</span>
      <button class="checkin" data-mas="${t.id}" style="padding:5px 12px;font-size:16px;line-height:1;
        background:var(--surface-3);color:var(--text-2);border-color:var(--line-2)">+</button>
    </div>
  </div>`;
}

/* ---- parche quirúrgico: una tarjeta y el pie, nada más ---- */
function posParche(id) {
  const t = posDisp.find(x => x.id === id); if (!t) return;
  const nodo = document.querySelector(`#posGrid [data-pt="${id}"]`);
  if (nodo) { nodo.outerHTML = posTarjeta(t); posBind(id); }
  posPie();
}

/* En una barra a oscuras el blanco tiene que ser grande: toda la tarjeta
   suma uno. El − y el + frenan la propagación para no sumar dos veces. */
function posSumar(id) {
  const t = posDisp.find(x => x.id === id); if (!t) return;
  if (posQuedan(t) <= 0) return toast(`Solo alcanza para ${t.alcanza_para}`, "warn");
  posCarrito[t.id] = (posCarrito[t.id] || 0) + 1;
  posParche(t.id);
}

function posBind(soloId) {
  const base = soloId ? `#posGrid [data-pt="${soloId}"]` : "#posGrid [data-pt]";
  /* La marca del long-press guarda CUÁNDO se abrió la hoja, no un sí/no. Con
     una bandera pegajosa quedaba puesta si la hoja se descartaba: al abrirse,
     el scrim tapa la tarjeta y se lleva el click que debía consumirla, así que
     el toque siguiente se perdía. Con la marca por tiempo se cura sola. */
  const recienAbierta = card => card && Date.now() - (+card.dataset.largo || 0) < 600;
  document.querySelectorAll(base).forEach(c => c.onclick = () => {
    if (recienAbierta(c)) { c.dataset.largo = ""; return; }
    posSumar(c.dataset.pt);
  });
  const sel = soloId ? `#posGrid [data-pt="${soloId}"] ` : "#posGrid ";
  document.querySelectorAll(sel + "[data-mas]").forEach(b => b.onclick = ev2 => {
    ev2.stopPropagation();
    const card = b.closest("[data-pt]");
    if (recienAbierta(card)) { card.dataset.largo = ""; return; }
    posSumar(b.dataset.mas);
  });
  document.querySelectorAll(sel + "[data-menos]").forEach(b => b.onclick = ev2 => {
    ev2.stopPropagation();
    const id = b.dataset.menos, n = (posCarrito[id] || 0) - 1;
    if (n > 0) posCarrito[id] = n; else delete posCarrito[id];
    posParche(id);
  });
  // El pointerdown/pointerup de + y − burbujean a la tarjeta si no se cortan acá:
  // mantener apretado el − terminaba abriendo igual la hoja de cantidad.
  document.querySelectorAll(sel + "[data-mas]").forEach(b => b.onpointerdown = ev2 => ev2.stopPropagation());
  document.querySelectorAll(sel + "[data-menos]").forEach(b => b.onpointerdown = ev2 => ev2.stopPropagation());

  // Mantener apretado abre el teclado para cargar una cantidad de golpe.
  // Se marca la tarjeta con data-largo para que el click que viene después
  // de soltar no sume uno encima de lo que se acaba de escribir.
  document.querySelectorAll(base).forEach(card => {
    let tmr = null;
    const arrancar = () => {
      clearTimeout(tmr);
      tmr = setTimeout(() => {
        tmr = null;
        card.dataset.largo = String(Date.now());
        sheetCantidad(card.dataset.pt);
      }, 550);
    };
    const soltar = () => { if (tmr) { clearTimeout(tmr); tmr = null; } };
    card.onpointerdown = arrancar;
    card.onpointerup = soltar;
    card.onpointercancel = soltar;
    card.onpointerleave = soltar;
  });
}

/* cargar de golpe: seis del mismo trago son seis toques, o uno largo */
function sheetCantidad(id) {
  const t = posDisp.find(x => x.id === id); if (!t) return;
  const tope = (+t.alcanza_para || 0);
  sheet(`
    <div class="sh-h">${esc(t.nombre)}<span class="r-sub">${fmtBs(t.precio)} Bs c/u</span></div>
    <div class="field"><label>Cuántos</label>
      <input id="qcN" type="number" inputmode="numeric" value="${posCarrito[id] || 1}" min="0" max="${tope}"></div>
    <p class="hint" style="margin:-4px 0 12px">Con el stock de ahora alcanza para ${tope}.</p>
    <button class="btn primary" id="qcGo">Poner en el carrito</button>`);
  $("#qcN").focus();
  $("#qcGo").onclick = () => {
    const n = Math.max(0, Math.min(+$("#qcN").value || 0, tope));
    if (n > 0) posCarrito[id] = n; else delete posCarrito[id];
    closeSheet(); posParche(id);
  };
}

/* ---- el pie: total, cobrar, anular ---- */
function posPie() {
  const nCar = Object.values(posCarrito).reduce((a, n) => a + n, 0);
  const total = posDisp.reduce((a, t) => a + (posCarrito[t.id] || 0) * +t.precio, 0);
  const pie = $("#posPie"); if (!pie) return;
  if (!nCar) {
    pie.innerHTML = `<div class="ph-actions" style="margin-top:14px">
      <button class="ghost" id="posCort">Cortesía de relacionador</button>
      ${posUltima && Date.now() - posUltima.at < POS_VENTANA_ANUL
        ? `<button class="ghost" id="posAnul" style="color:var(--danger)">Anular ${fmtBs(posUltima.total)} Bs</button>` : ""}
    </div>`;
  } else {
    pie.innerHTML = `<div style="position:sticky;bottom:calc(var(--nav-h) + 8px);margin-top:14px;
        background:var(--surface-2);border:1px solid var(--line-2);border-radius:16px;padding:12px 14px">
      <div style="display:flex;justify-content:space-between;align-items:center;margin-bottom:9px">
        <span style="font-size:13px;color:var(--text-2)">${nCar} trago${nCar === 1 ? "" : "s"}</span>
        <span style="font-family:var(--display);font-size:20px">${posCortSel ? "Cortesía" : fmtBs(total) + " Bs"}</span>
      </div>
      <button class="btn primary" id="posEf">${posCortSel ? "Registrar cortesía" : "Cobrar en efectivo"}</button>
      <div style="height:8px"></div>
      <div class="ph-actions" style="justify-content:space-between">
        <button class="ghost" id="posClear">Vaciar</button>
        ${!posCortSel ? `<button class="ghost" id="posCort">Es cortesía</button>` : ""}
      </div>
    </div>`;
  }
  const bc = $("#posClear"); if (bc) bc.onclick = () => { posCarrito = {}; posPintar(); };
  const bk = $("#posCort"); if (bk) bk.onclick = sheetCortesia;
  const be = $("#posEf"); if (be) be.onclick = () => posCobrar("efectivo");
  const ba = $("#posAnul"); if (ba) ba.onclick = posAnularUltima;
}

async function posCobrar(forma) {
  const items = Object.entries(posCarrito).filter(([, n]) => n > 0)
    .map(([trago_id, qty]) => ({ trago_id, qty }));
  if (!items.length) return;
  const args = {
    p_evento: ev.id, p_barra: posBarra, p_items: items,
    p_cortesia_de: posCortSel?.user_id || null,
    p_forma_pago: posCortSel ? "cortesia" : forma,
    p_client_key: crypto.randomUUID()
  };
  const b = $("#posEf"); if (b) b.disabled = true;

  // window.__offline simula el corte de wifi para poder probar la cola sin
  // desconectar el teléfono de verdad.
  const { data, error } = window.__offline
    ? { data: null, error: { message: "offline" } }
    : await sb.rpc("bar_vender", args);
  if (b) b.disabled = false;

  if (error) {
    if (!esFallaDeRed(error)) {
      const msg = error.message.replace(/^.*CUPO AGOTADO/, "CUPO AGOTADO");
      toast(msg, "warn");
      // Si rebotó por stock, lo que muestran las tarjetas ya no es cierto:
      // se vuelve a pedir el catálogo para que los números se corrijan solos.
      if (/no hay stock/i.test(error.message)) { await posCargar(); posPintar(); }
      return;
    }
    // Sin señal: solo el efectivo (y la cortesía, que tampoco cobra) tiene
    // sentido encolado. Una venta por QR sin red no sirve porque el cliente
    // tampoco puede pagar — mostrar el error y no encolar.
    if (args.p_forma_pago === "qr") {
      return toast("Sin señal: el cobro por QR necesita conexión", "warn");
    }
    colaBarra.encolar(args);
    toast(`Sin señal · guardada, sale sola cuando vuelva (${colaBarra.pendientes()} en cola)`, "warn");
    posCarrito = {}; posCortSel = null; posPintar();
    return;
  }

  toast(data.cortesia ? "Cortesía registrada" : `✓ Cobrado ${fmtBs(data.total)} Bs`);
  posUltima = { id: data.venta, total: data.total, at: Date.now() };
  posCarrito = {}; posCortSel = null;
  // el stock cambió de verdad: acá sí se vuelve a pedir el catálogo
  await posCargar(); posPintar();
}

/* Anular lo que se acaba de cobrar. El botón vive dos minutos: pasado ese
   rato ya no es "me equivoqué", es un ajuste, y eso lo hace el propietario
   desde Movimientos con motivo. */
const POS_VENTANA_ANUL = 2 * 60 * 1000;
/* Guarda el id de la venta para la que se armó la confirmación, no un simple
   sí/no. Con una bandera booleana, armar el botón y cobrar otra venta antes de
   que venza el plazo dejaba el arme puesto sobre la venta nueva: un solo toque
   la anulaba sin preguntar. Atado al id, el arme de una venta no sirve para
   otra, sin importar los tiempos. */
let posAnulArm = null;

async function posAnularUltima() {
  if (!posUltima) return;
  if (Date.now() - posUltima.at > POS_VENTANA_ANUL) {
    posUltima = null; posAnulArm = null; posPie();
    return toast("Pasaron más de 2 minutos: pedile el ajuste al propietario", "warn");
  }
  const b = $("#posAnul");
  if (posAnulArm !== posUltima.id) {
    const armada = posUltima.id;
    posAnulArm = armada;
    if (b) b.textContent = "¿Seguro? Tocá de nuevo";
    setTimeout(() => {
      if (posAnulArm !== armada) return;      // ya se usó, o se armó otra
      posAnulArm = null;
      if ($("#posAnul") && posUltima) $("#posAnul").textContent = `Anular ${fmtBs(posUltima.total)} Bs`;
    }, 4000);
    return;
  }
  posAnulArm = null;
  if (b) b.disabled = true;
  const { error } = await sb.rpc("bar_anular_venta", { p_venta: posUltima.id, p_motivo: "Anulada en barra" });
  if (error) { if (b) b.disabled = false; return fail(error); }
  toast("Venta anulada · el stock volvió", "warn");
  posUltima = null;
  await posCargar(); posPintar();
}

/* elegir a quién se le da la cortesía (muestra cuánto le queda) */
async function sheetCortesia() {
  const { data } = await sb.rpc("bar_cortesias_evento", { p_evento: ev.id });
  posCortesias = data || [];
  if (!posCortesias.length) return toast("No hay relacionadores con cortesías habilitadas", "warn");
  sheet(`
    <div class="sh-h">Cortesía de relacionador</div>
    <div class="hint" style="margin:0 0 12px">Mostrá la manilla, elegí el nombre y cargá el trago. Si ya usó su cupo, el sistema no te deja registrarlo.</div>
    <div class="field"><input id="coBuscar" placeholder="Buscar…" autocomplete="off"></div>
    <div id="coLista">${posCortesias.map(c => {
      const queda = c.cupo - c.usados, lleno = queda <= 0;
      return `<div class="list-row rc" data-co="${c.user_id}" data-q="${esc((c.nombre || "").toLowerCase())}" style="cursor:${lleno ? "not-allowed" : "pointer"};opacity:${lleno ? ".5" : "1"}">
        <div class="r-l" style="flex:1;min-width:0"><span class="relmark">${esc((c.nombre || "?")[0])}</span>
          <span class="rc-body"><span class="rc-nm">${esc(c.nombre)}</span>
            <span class="rc-sub"><span>${esc(c.team)}</span></span></span></div>
        <span class="tkst ${lleno ? "" : "ok"}" style="${lleno ? "background:var(--danger-bg);color:var(--danger)" : ""}">${lleno ? "CUPO AGOTADO" : `${c.usados}/${c.cupo}`}</span>
      </div>`;
    }).join("")}</div>`);
  const bind = () => document.querySelectorAll("#coLista [data-co]").forEach(r => r.onclick = () => {
    const c = posCortesias.find(x => x.user_id === r.dataset.co);
    if (!c || c.cupo - c.usados <= 0) return toast(`${c.nombre} ya usó sus ${c.cupo} vaso(s)`, "warn");
    posCortSel = c; closeSheet(); posPintar();
  });
  bind();
  $("#coBuscar").oninput = e => {
    const q = e.target.value.trim().toLowerCase();
    document.querySelectorAll("#coLista [data-co]").forEach(r =>
      r.classList.toggle("hidden", q.length > 1 && !r.dataset.q.includes(q)));
  };
}

/* ---------- PROPIETARIO · carta y recetas ---------- */
async function sheetTragos() {
  await Promise.all([loadBarras(), loadBebidas()]);
  const { data } = await sb.from("tragos").select("*, r:receta_items(ml, bebida_id)")
    .eq("club_id", club).order("orden").order("nombre");
  const ts = data || [];
  sheet(`
    <div class="sh-h">Carta de tragos<span class="r-sub">${ts.length}</span></div>
    <div class="hint" style="margin:0 0 12px">Un trago se activa recién cuando tiene receta: sin receta, venderlo no descontaría nada del stock.</div>
    <div>${ts.map(t => {
      const barra = barrasCache.find(b => b.id === t.barra_id);
      return `<div class="list-row rc">
        <div class="r-l" data-tr="${t.id}" style="cursor:pointer;flex:1;min-width:0">
          <span class="relmark" style="${t.activo ? "" : "background:var(--surface-3);color:var(--text-3)"}">${esc(t.nombre[0])}</span>
          <span class="rc-body"><span class="rc-nm">${esc(t.nombre)}${t.activo ? "" : ` <small style="color:var(--text-3)">(inactivo)</small>`}</span>
            <span class="rc-sub"><span>${fmtBs(t.precio_venta)} Bs · ${(t.r || []).length ? `${t.r.length} ingrediente(s)` : "sin receta"}${barra ? " · " + esc(barra.nombre) : " · todas las barras"}</span></span></span></div>
      </div>`;
    }).join("") || `<div class="empty">Sin tragos cargados.</div>`}</div>
    <div style="height:12px"></div>
    <button class="btn primary" id="ntGo2">+ Nuevo trago</button>`);
  $("#ntGo2").onclick = () => sheetNuevoTrago();
  document.querySelectorAll("#sheetBody [data-tr]").forEach(x => x.onclick = () =>
    sheetTrago(ts.find(t => t.id === x.dataset.tr)));
}

function sheetNuevoTrago() {
  sheet(`
    <div class="sh-h">Nuevo trago</div>
    <div class="field"><label>Nombre</label><input id="ntN" placeholder="Whisky-Cola" autocomplete="off"></div>
    <div class="row2">
      <div class="field"><label>Precio de venta Bs</label><input id="ntP" type="number" inputmode="decimal" placeholder="40"></div>
      <div class="field"><label>Barra</label><select id="ntB"><option value="">Todas</option>${barrasCache.map(b =>
        `<option value="${b.id}">${esc(b.nombre)}</option>`).join("")}</select></div>
    </div>
    <button class="btn primary" id="ntG">Crear trago</button>
    <p class="hint" style="margin-top:10px">Después le cargás la receta (qué bebida usa y cuántos ml) y ahí se activa.</p>`);
  $("#ntG").onclick = async () => {
    const nombre = $("#ntN").value.trim(), precio = +$("#ntP").value;
    if (!nombre) return toast("Poné el nombre", "warn");
    if (!precio && precio !== 0) return toast("Poné el precio", "warn");
    const { error } = await sb.from("tragos").insert({
      club_id: club, nombre, precio_venta: precio, barra_id: $("#ntB").value || null
    });
    if (error) return fail(error);
    toast(`${nombre} creado — cargale la receta`);
    sheetTragos();
  };
}

async function sheetTrago(t) {
  if (!t) return;
  const { data: rec } = await sb.from("receta_items").select("*, b:bebidas(nombre, volumen_ml)").eq("trago_id", t.id);
  const items = rec || [];
  sheet(`
    <div class="sh-h">${esc(t.nombre)}<span class="r-sub">${fmtBs(t.precio_venta)} Bs</span></div>
    <div class="sh-h" style="margin-top:12px;font-size:14px">Receta<span class="r-sub">por vaso</span></div>
    <div>${items.map(r => `
      <div class="list-row rc">
        <div class="r-l" style="flex:1"><span class="rc-body"><span class="rc-nm">${esc(r.b?.nombre || "—")}</span>
          <span class="rc-sub"><span>${r.ml} ml por vaso</span></span></span></div>
        <button class="checkin" data-delr="${r.id}" style="background:var(--surface-3);color:var(--text-3);border-color:var(--line-2)">✕</button>
      </div>`).join("") || `<div class="empty">Sin ingredientes todavía.</div>`}</div>
    <div class="row2" style="margin-top:10px">
      <div class="field"><label>Bebida</label><select id="riB">${bebidasCache.map(b =>
        `<option value="${b.id}">${esc(b.nombre)}</option>`).join("")}</select></div>
      <div class="field"><label>ml por vaso</label><input id="riM" type="number" inputmode="numeric" placeholder="45"></div>
    </div>
    <button class="btn ghost2" id="riGo">+ Agregar ingrediente</button>
    <div style="height:12px"></div>
    <button class="btn ${t.activo ? "danger" : "primary"}" id="trTg">${t.activo ? "Desactivar trago" : "Activar trago"}</button>`);
  $("#riGo").onclick = async () => {
    const ml = +$("#riM").value;
    if (!ml || ml <= 0) return toast("Poné cuántos ml lleva", "warn");
    const { error } = await sb.from("receta_items").insert({ trago_id: t.id, bebida_id: $("#riB").value, ml });
    if (error) return toast(error.code === "23505" ? "Esa bebida ya está en la receta" : error.message, "warn");
    toast("Ingrediente agregado"); sheetTrago(t);
  };
  document.querySelectorAll("#sheetBody [data-delr]").forEach(x => x.onclick = async () => {
    await sb.from("receta_items").delete().eq("id", x.dataset.delr);
    toast("Ingrediente quitado", "warn"); sheetTrago(t);
  });
  $("#trTg").onclick = async () => {
    const { error } = await sb.from("tragos").update({ activo: !t.activo }).eq("id", t.id);
    if (error) return toast(error.message, "warn");
    toast(t.activo ? "Trago desactivado" : "Trago activado");
    sheetTragos();
  };
}

/* ---------- PROPIETARIO · turno y cortesías ---------- */
async function sheetTurno() {
  if (!ev) return toast("No hay evento abierto", "warn");
  await loadBarras();
  const [{ data: staff }, { data: gente }] = await Promise.all([
    sb.from("bar_staff").select("barra_id, user_id").eq("evento_id", ev.id),
    sb.from("profiles").select("id, nombre, rol").in("rol", ["barra", "propietario"]).eq("activo", true).order("nombre")
  ]);
  const asign = staff || [], staffIds = new Set(asign.map(s => s.barra_id + "|" + s.user_id));
  sheet(`
    <div class="sh-h">Turno · ${esc(ev.nombre)}</div>
    <div class="hint" style="margin:0 0 12px">Quién atiende cada barra esta noche. Solo el asignado puede registrar ventas en esa barra.</div>
    ${barrasCache.map(b => `
      <div class="sh-h" style="margin-top:12px;font-size:14px">${esc(b.nombre)}</div>
      ${(gente || []).map(g => `
        <div class="list-row rc">
          <div class="r-l" style="flex:1"><span class="relmark">${esc(g.nombre[0])}</span>
            <span class="rc-body"><span class="rc-nm">${esc(g.nombre)}</span></span></div>
          <button class="cebox ${staffIds.has(b.id + "|" + g.id) ? "on" : ""}" data-st="${b.id}|${g.id}"></button>
        </div>`).join("")}`).join("") || `<div class="empty">Primero creá las barras.</div>`}`);
  document.querySelectorAll("#sheetBody [data-st]").forEach(x => x.onclick = async () => {
    const [barra_id, user_id] = x.dataset.st.split("|");
    const on = x.classList.contains("on");
    if (on) await sb.from("bar_staff").delete().eq("evento_id", ev.id).eq("barra_id", barra_id).eq("user_id", user_id);
    else { const { error } = await sb.from("bar_staff").insert({ evento_id: ev.id, barra_id, user_id }); if (error) return toast(error.message, "warn"); }
    x.classList.toggle("on");
  });
}

async function sheetCortesiasConfig() {
  const { data: cfg } = await sb.from("bar_cortesia_config").select("*").eq("club_id", club).maybeSingle();
  const cupo = cfg?.cupo_default ?? 0;
  sheet(`
    <div class="sh-h">Cortesías de relacionadores</div>
    <div class="hint" style="margin:0 0 12px">Cuántos vasos puede sacar cada relacionador por evento. Cuando llega al tope, al bartender le sale <b>CUPO AGOTADO</b> y no puede registrar más — no depende de que se acuerde.</div>
    <div class="field"><label>Vasos por relacionador · ${clubNombre(club)}</label>
      <input id="ccN" type="number" inputmode="numeric" value="${cupo}"></div>
    <p class="hint" style="margin:-4px 0 12px">En 0, las cortesías quedan deshabilitadas.</p>
    <button class="btn primary" id="ccGo">Guardar</button>`);
  $("#ccGo").onclick = async () => {
    const n = +$("#ccN").value;
    if (isNaN(n) || n < 0) return toast("Número inválido", "warn");
    const { error } = await sb.from("bar_cortesia_config").upsert({ club_id: club, cupo_default: n, updated_at: new Date().toISOString() });
    if (error) return fail(error);
    toast(n ? `Cupo: ${n} vaso(s) por relacionador` : "Cortesías deshabilitadas");
    closeSheet();
  };
}

/* ---------- PROPIETARIO · cierre de la noche ---------- */
/* ============================================================
   MÓDULO BARRA · Fase 3 — analítica
   El Cierre dice cuánto se vendió. Esto dice cuánto QUEDÓ, que no es lo
   mismo: descuenta el costo de lo servido, lo que se regaló y lo que
   falta sin explicación. Solo la ve el propietario — las vistas leen de
   `stock_mov`/`lotes`, que por RLS nadie más puede tocar.
   ============================================================ */
const pctBarra = p => Math.max(2, Math.min(100, +p || 0));
async function screenBarAnalitica() {
  if (!ev) { $("#main").innerHTML = `<div class="empty">No hay evento abierto.</div>`; return; }
  const [{ data: res }, { data: barras }, { data: margen }, { data: merma }, { data: top }] = await Promise.all([
    sb.from("v_bar_evento").select("*").eq("evento_id", ev.id).maybeSingle(),
    sb.from("v_bar_por_barra").select("*").eq("evento_id", ev.id).order("ingresos", { ascending: false }),
    sb.from("v_bar_margen").select("*").eq("evento_id", ev.id).maybeSingle(),
    sb.from("v_bar_merma").select("*").eq("evento_id", ev.id).not("merma_bs", "is", null).order("merma_bs", { ascending: false }).limit(8),
    sb.from("v_bar_top_trago").select("*").eq("evento_id", ev.id).lte("puesto_evento", 5).order("puesto_evento")
  ]);
  if (!res) {
    $("#main").innerHTML = `<div class="sh-h">Analítica · ${esc(ev.nombre)}</div>
      <div class="empty">Todavía no hay ventas de barra en esta noche.</div>`;
    return;
  }
  const m = margen || {};
  const bs = (barras || []), mm = (merma || []), tp = (top || []);
  const faltanConteos = mm.length === 0;
  const mermaTot = +(m.merma_bs || 0);
  $("#main").innerHTML = `
    ${pgHead({ ey: "Barra", t: "Analítica", s: `${esc(ev.nombre)} · ${res.vasos} vasos · ${res.pedidos} pedidos` })}

    <div class="stats" style="margin-bottom:12px">
      <div class="stat st-ok" style="grid-column:1/-1"><span class="k">Lo que quedó de verdad</span>
        <span class="v ok" style="font-size:28px">${fmtBs(m.margen_neto || 0)} Bs</span>
        <small>de ${fmtBs(res.ingresos)} Bs vendidos</small></div>
      <div class="stat"><span class="k">Costo de lo servido</span><span class="v">${fmtBs(m.costo_vendido || 0)} Bs</span></div>
      <div class="stat"><span class="k">Margen bruto</span><span class="v ok">${m.margen_pct ?? "—"}%</span></div>
      <div class="stat"><span class="k">Cortesías</span><span class="v" style="color:var(--warn)">${fmtBs(m.costo_cortesias || 0)} Bs</span><small>${res.vasos_cortesia} vasos regalados</small></div>
      <div class="stat"><span class="k">Falta sin explicar</span><span class="v" style="color:${mermaTot > 0 ? "var(--danger)" : "var(--text-2)"}">${faltanConteos ? "—" : fmtBs(mermaTot) + " Bs"}</span><small>${faltanConteos ? "faltan conteos" : "merma"}</small></div>
    </div>
    <div class="hint" style="margin:0 0 16px">Ticket promedio ${fmtBs(res.ticket_promedio || 0)} Bs · ${res.barras_activas} barra(s) con movimiento.</div>

    <div class="sh-h" style="font-size:14px">Cómo le fue a cada barra</div>
    ${bs.map(b => `
      <div class="list-row rc" style="align-items:flex-start">
        <div class="r-l" style="flex:1;min-width:0"><span class="rc-body" style="width:100%">
          <span class="rc-nm">${esc(b.barra)}</span>
          <span class="rc-sub"><span>${b.vasos} vasos · ${b.pedidos} pedidos · ticket ${fmtBs(b.ticket_promedio || 0)} Bs</span></span>
          <span style="display:block;height:6px;border-radius:99px;background:var(--surface-3);margin-top:7px;overflow:hidden">
            <span style="display:block;height:100%;width:${pctBarra(b.pct_del_evento)}%;background:linear-gradient(90deg,var(--accent-2),var(--accent))"></span></span>
        </span></div>
        <div style="text-align:right;flex-shrink:0;padding-left:10px">
          <span style="font-family:var(--display);font-size:15px">${fmtBs(b.ingresos)}</span>
          <span style="display:block;font-size:10px;color:var(--text-3);font-weight:600">${b.pct_del_evento ?? 0}% de la noche</span></div>
      </div>`).join("")}

    ${tp.length ? `<div class="sh-h" style="margin-top:16px;font-size:14px">Lo que más se vendió</div>
      ${tp.map(t => `<div class="list-row rc">
        <div class="r-l" style="flex:1"><span class="relmark">${t.puesto_evento}</span>
          <span class="rc-body"><span class="rc-nm">${esc(t.trago)}</span>
          <span class="rc-sub"><span>${t.vasos} vasos</span></span></span></div>
        <span style="font-family:var(--display);font-size:14px">${fmtBs(t.ingresos)} Bs</span>
      </div>`).join("")}` : ""}

    <div class="sh-h" style="margin-top:16px;font-size:14px">Qué falta que no explican las ventas</div>
    ${faltanConteos
      ? `<div class="empty">Sin conteo de apertura y cierre no se puede calcular. Cargalos desde Inventario para que esta noche cuadre.</div>`
      : mm.map(x => `<div class="list-row rc">
          <div class="r-l" style="flex:1"><span class="rc-body">
            <span class="rc-nm">${esc(x.bebida)}</span>
            <span class="rc-sub"><span>${x.merma_botellas} botella(s) · ${x.merma_pct}% de lo servido</span></span></span></div>
          <span class="tkst" style="background:var(--danger-bg);color:var(--danger)">${fmtBs(x.merma_bs)} Bs</span>
        </div>`).join("")}

    <div class="sh-h" style="margin-top:18px;font-size:14px">Qué comprar para la próxima</div>
    <div class="row2">
      <div class="field"><label>Gente esperada</label><input id="pjAsist" type="number" value="500"></div>
      <div class="field" style="display:flex;align-items:flex-end"><button class="btn ghost2" id="pjGo" style="padding:13px">Calcular</button></div>
    </div>
    <div id="pjOut"></div>`;

  $("#pjGo").onclick = async () => {
    const b = $("#pjGo"); b.disabled = true;
    const { data, error } = await sb.rpc("bar_proyeccion_compra", {
      p_club: club, p_asistentes: +$("#pjAsist").value || 500 });
    b.disabled = false;
    if (error) throw error;   // lo muestra conPantalla con Reintentar
    const filas = data || [];
    $("#pjOut").innerHTML = filas.length
      ? `<div class="hint" style="margin:0 0 8px">Sobre el consumo real de las últimas noches, con 15% de colchón.</div>` +
        filas.map(f => `<div class="list-row rc">
          <div class="r-l" style="flex:1"><span class="rc-body"><span class="rc-nm">${esc(f.bebida)}</span>
            <span class="rc-sub"><span>tenés ${f.stock_botellas} · vas a necesitar ${f.necesita_botellas}</span></span></span></div>
          <span class="tkst ${+f.comprar_botellas > 0 ? "" : "ok"}" style="${+f.comprar_botellas > 0 ? "background:var(--warn-bg,rgba(246,180,74,.12));color:var(--warn)" : ""}">${+f.comprar_botellas > 0 ? "comprar " + f.comprar_botellas : "alcanza"}</span>
        </div>`).join("")
      : `<div class="empty">Todavía no hay noches suficientes para proyectar.</div>`;
  };
}

async function screenBarCierre() {
  if (!ev) { $("#main").innerHTML = `<div class="empty">No hay evento abierto.</div>`; return; }
  const [{ data: cierre }, { data: cort }] = await Promise.all([
    sb.from("v_bar_cierre").select("*").eq("evento_id", ev.id),
    sb.rpc("bar_cortesias_evento", { p_evento: ev.id })
  ]);
  const cs = cierre || [];
  const tot = cs.reduce((a, c) => ({ bs: a.bs + +c.bs, tragos: a.tragos + +c.tragos, cort: a.cort + +c.cortesias }), { bs: 0, tragos: 0, cort: 0 });
  const usaron = (cort || []).filter(c => +c.usados > 0).sort((a, b) => b.usados - a.usados);
  $("#main").innerHTML = `
    ${pgHead({ ey: "Barra", t: "Cierre de barra", s: esc(ev.nombre) })}
    <div class="stats" style="margin-bottom:12px">
      <div class="stat st-ok"><span class="k">Vendido</span><span class="v ok">${fmtBs(tot.bs)} Bs</span><small>${tot.tragos} tragos</small></div>
      <div class="stat st-vio"><span class="k">Cortesías</span><span class="v vio">${tot.cort}</span><small>vasos</small></div>
    </div>
    <div class="sh-h" style="margin-top:14px;font-size:14px">Por barra</div>
    ${cs.map(c => `
      <div class="list-row rc"><div class="r-l" style="flex:1"><span class="rc-body">
        <span class="rc-nm">${esc(c.barra)}</span>
        <span class="rc-sub"><span>${c.tragos} tragos · ${c.ventas} ventas${+c.cortesias ? ` · ${c.cortesias} cortesías` : ""}</span></span></span></div>
        <div style="text-align:right"><span style="font-family:var(--display);font-size:15px">${fmtBs(c.bs)}</span>
          <span style="display:block;font-size:10px;color:var(--text-3);font-weight:600">Bs</span></div>
      </div>`).join("") || `<div class="empty">Todavía no se registraron ventas.</div>`}
    ${usaron.length ? `<div class="sh-h" style="margin-top:16px;font-size:14px">Cortesías por relacionador</div>
      ${usaron.map(c => `<div class="list-row rc"><div class="r-l" style="flex:1"><span class="relmark">${esc((c.nombre||"?")[0])}</span>
        <span class="rc-body"><span class="rc-nm">${esc(c.nombre)}</span><span class="rc-sub"><span>${esc(c.team)}</span></span></span></div>
        <span class="tkst ${c.usados >= c.cupo ? "" : "ok"}" style="${c.usados >= c.cupo ? "background:var(--warn-bg,rgba(246,180,74,.12));color:var(--warn)" : ""}">${c.usados}/${c.cupo}</span>
      </div>`).join("")}` : ""}`;
}

/* ============================================================
   AVISOS (admin -> equipo)
   Se escriben acá y le aparecen a cada uno al entrar a la app, una sola vez.
   Queda registrado quién lo leyó: la mitad del problema de avisar por
   WhatsApp es no saber si se enteraron.
   ============================================================ */
async function sheetAvisos() {
  const { data } = await sb.rpc("avisos_admin", { p_club: club });
  const avisos = data || [];
  const DEST = { todos: "Todo el equipo", rrpp: "Solo relacionadores", jefe: "Solo jefes", team: "Un team" };
  sheet(`
    <div class="sh-h">Avisos<span class="r-sub">${avisos.length}</span></div>
    <p class="hint" style="margin:0 0 12px">Le aparece a cada uno cuando entra a la app y lo tiene que cerrar para seguir. Se muestra una sola vez por persona.</p>
    <button class="btn primary" id="avNuevo">Nuevo aviso</button>
    <div id="avLista" style="margin-top:14px">${avisos.map(a => {
      const pct = +a.alcance ? Math.round(+a.leidos / +a.alcance * 100) : 0;
      const vencido = a.hasta_ts && new Date(a.hasta_ts) < new Date();
      return `<div class="list-row rc" style="align-items:flex-start;${a.activo && !vencido ? "" : "opacity:.55"}">
        <div class="r-l" style="flex:1;min-width:0;align-items:flex-start">
          <span class="rc-body">
            <span class="rc-nm">${esc(a.titulo)}${a.activo && !vencido ? "" : ` <small style="color:var(--text-3)">(${vencido ? "vencido" : "apagado"})</small>`}</span>
            <span class="rc-sub"><span>${esc(DEST[a.destino] || a.destino)}${a.team ? " · " + esc(a.team) : ""}${a.club_id ? " · " + esc(clubNombre(a.club_id)) : " · todos"}</span></span>
            <span class="rc-sub" style="margin-top:4px"><span>Leído por <b style="color:${pct >= 80 ? "var(--ok)" : pct >= 40 ? "var(--warn)" : "var(--text-2)"}">${a.leidos} de ${a.alcance}</b></span></span>
            <span class="bar" style="height:5px;border-radius:99px;background:var(--surface-3);overflow:hidden;margin-top:5px;display:block">
              <i style="display:block;height:100%;width:${pct}%;border-radius:99px;background:${pct >= 80 ? "var(--ok)" : "var(--accent)"}"></i></span>
          </span>
        </div>
        <div style="display:flex;flex-direction:column;gap:6px;flex-shrink:0">
          <button class="checkin" data-avq="${a.id}" style="background:var(--surface-3);color:var(--text-2);border-color:var(--line-2)">Quién</button>
          <button class="checkin" data-avtg="${a.id}" data-act="${a.activo}" style="background:var(--surface-3);color:var(--text-2);border-color:var(--line-2)">${a.activo ? "Apagar" : "Prender"}</button>
          <button class="checkin" data-avdel="${a.id}" data-txt="${esc(a.titulo || "")}" title="Eliminar aviso" style="background:var(--surface-3);color:var(--text-3);border-color:var(--line-2)">✕</button>
        </div>
      </div>`;
    }).join("") || `<div class="empty">Todavía no mandaste ningún aviso.</div>`}</div>`);
  $("#avNuevo").onclick = sheetNuevoAviso;
  document.querySelectorAll("#avLista [data-avtg]").forEach(b => b.onclick = async () => {
    const { error } = await sb.from("avisos").update({ activo: b.dataset.act !== "true" }).eq("id", b.dataset.avtg);
    if (error) return fail(error);
    toast(b.dataset.act === "true" ? "Aviso apagado" : "Aviso prendido"); sheetAvisos();
  });
  document.querySelectorAll("#avLista [data-avdel]").forEach(b => b.onclick = async () => {
    if (!await confirmar({
      titulo: "Eliminar aviso",
      detalle: [b.dataset.txt || "Aviso del equipo"],
      accion: "Eliminar aviso"
    })) return;
    const { error } = await sb.from("avisos").delete().eq("id", b.dataset.avdel);
    if (error) return fail(error);
    toast("Aviso borrado", "warn"); sheetAvisos();
  });
  document.querySelectorAll("#avLista [data-avq]").forEach(b => b.onclick = () => sheetQuienLeyo(b.dataset.avq));
}

function sheetNuevoAviso() {
  sheet(`
    <button class="btn ghost2" style="width:auto;padding:8px 14px;margin-bottom:12px" id="naBack">${ico("atras")}Volver</button>
    <div class="sh-h">Nuevo aviso</div>
    <div class="field"><label>Título</label><input id="naT" placeholder="Este sábado abrimos 22:00" autocomplete="off"></div>
    <div class="field"><label>Mensaje</label><textarea id="naM" rows="4" placeholder="Escribí acá lo que querés que lean."></textarea></div>
    <div class="row2">
      <div class="field"><label>¿A quién?</label><select id="naD">
        <option value="todos">Todo el equipo</option>
        <option value="rrpp">Solo relacionadores</option>
        <option value="jefe">Solo jefes</option>
        <option value="team">Un team</option></select></div>
      <div class="field"><label>Boliche</label><select id="naC">
        <option value="">Todos los boliches</option>
        ${clubsDisponibles.map(c => `<option value="${c.id}">${esc(c.nombre)}</option>`).join("")}</select></div>
    </div>
    <div class="field hidden" id="naTeamBox"><label>Team</label><select id="naTeam">${teamsCache.map(t => `<option value="${t.id}">${esc(t.nombre)}</option>`).join("")}</select></div>
    <div class="field"><label>Dejar de mostrarlo el (opcional)</label><input id="naH" type="datetime-local"></div>
    <button class="btn primary" id="naGo">Publicar aviso</button>
    <p class="hint" style="margin-top:10px">Les va a aparecer la próxima vez que entren a la app.</p>`);
  $("#naBack").onclick = sheetAvisos;
  $("#naD").onchange = () => $("#naTeamBox").classList.toggle("hidden", $("#naD").value !== "team");
  $("#naGo").onclick = async () => {
    const titulo = $("#naT").value.trim(), mensaje = $("#naM").value.trim();
    if (!titulo) return toast("Poné un título", "warn");
    if (!mensaje) return toast("Escribí el mensaje", "warn");
    const destino = $("#naD").value, h = $("#naH").value;
    const { error } = await sb.from("avisos").insert({
      titulo, mensaje, destino,
      club_id: $("#naC").value || null,
      team_id: destino === "team" ? $("#naTeam").value : null,
      hasta_ts: h ? new Date(h).toISOString() : null
    });
    if (error) return fail(error);
    toast("Aviso publicado — lo verán al entrar");
    sheetAvisos();
  };
}

async function sheetQuienLeyo(id) {
  const { data } = await sb.rpc("aviso_lectores", { p_aviso: id });
  const l = data || [];
  sheet(`
    <button class="btn ghost2" style="width:auto;padding:8px 14px;margin-bottom:12px" id="qlBack">${ico("atras")}Volver</button>
    <div class="sh-h">Quién lo leyó<span class="r-sub">${l.length}</span></div>
    <div>${l.map(x => `
      <div class="list-row rc">
        <div class="r-l" style="flex:1"><span class="relmark">${esc((x.nombre || "?")[0])}</span>
          <span class="rc-body"><span class="rc-nm">${esc(x.nombre)}</span></span></div>
        <span class="ce-time">${hora(x.visto_at)}</span>
      </div>`).join("") || `<div class="empty">Todavía no lo leyó nadie.</div>`}</div>`);
  $("#qlBack").onclick = sheetAvisos;
}
