/* Cobro con QR bancario · Banco Económico (API Market v1.0.0)
 *
 * Todo lo que toca al banco pasa por acá, del lado del servidor. Las
 * credenciales viven en los secretos de la función y nunca se loguean.
 *
 * Acciones (POST JSON):
 *   { accion: "qr", orden }      cliente con sesión: genera (o devuelve) el QR
 *   { accion: "estado", orden }  cliente con sesión: le pregunta AL BANCO si se pagó
 *   { accion: "barrido" }        tarea programada (header x-cron): revisa los QR
 *                                activos, concilia con paidQR y anula los vencidos
 *   { Payment: {...} }           aviso del banco (URL de notificación, opcional):
 *                                no se confía en el contenido; se re-consulta statusQR
 *
 * Lo que el manual no dice y se descubrió:
 *   - el cifrado es AES-256-CBC con un IV aleatorio de 16 bytes ADELANTE del
 *     texto cifrado, relleno PKCS7 y salida base64 (se verificó descifrando
 *     el ejemplo del manual). La llave son los 32 caracteres en ASCII.
 *   - statusQR y paidQR son GET "con cuerpo" en el manual; un GET no lleva
 *     cuerpo, así que van como parámetros de la URL.
 *   - el estado viene como statusQRCode (tabla) o statusQrCode (ejemplo) y
 *     payment como objeto (tabla) o lista (ejemplo): se aceptan las dos formas.
 */
import { createClient } from "jsr:@supabase/supabase-js@2";

const CORS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, apikey, content-type, x-cron",
};
const env = (k: string) => {
  const v = Deno.env.get(k);
  if (!v) throw new Error(`Falta configurar ${k}`);
  return v;
};
const admin = createClient(env("SUPABASE_URL"), env("SUPABASE_SERVICE_ROLE_KEY"), {
  auth: { persistSession: false },
});
const BASE = () => env("BANECO_BASE_URL").replace(/\/+$/, "");
const AMBIENTE = () => (BASE().includes("apimktdesa") ? "certificacion" : "produccion");

// ── cifrado AES-256-CBC (IV adelante) ──────────────────────────────────
async function cifrar(texto: string): Promise<string> {
  const llave = await crypto.subtle.importKey("raw", new TextEncoder().encode(env("BANECO_AES_KEY")),
    { name: "AES-CBC" }, false, ["encrypt"]);
  const iv = crypto.getRandomValues(new Uint8Array(16));
  const c = new Uint8Array(await crypto.subtle.encrypt({ name: "AES-CBC", iv }, llave, new TextEncoder().encode(texto)));
  const todo = new Uint8Array(iv.length + c.length);
  todo.set(iv); todo.set(c, iv.length);
  return btoa(String.fromCharCode(...todo));
}

// ── llamadas al banco ──────────────────────────────────────────────────
type Resp = Record<string, unknown> & { responseCode?: number; message?: string };
class ErrorBanco extends Error {
  constructor(public paso: string, public codigo: unknown, mensaje: string) { super(mensaje); }
}

async function banco(metodo: string, ruta: string, opts: { cuerpo?: unknown; query?: Record<string, string>; token?: string } = {}): Promise<Resp> {
  const url = new URL(BASE() + ruta);
  for (const [k, v] of Object.entries(opts.query ?? {})) url.searchParams.set(k, v);
  const r = await fetch(url, {
    method: metodo,
    headers: {
      "Content-Type": "application/json", Accept: "application/json",
      ...(opts.token ? { Authorization: `Bearer ${opts.token}` } : {}),
    },
    body: opts.cuerpo === undefined ? undefined : JSON.stringify(opts.cuerpo),
    signal: AbortSignal.timeout(25000),
  });
  const texto = await r.text();
  let datos: Resp;
  try { datos = JSON.parse(texto); } catch { throw new ErrorBanco(ruta, r.status, `Respuesta no JSON (HTTP ${r.status})`); }
  if (!r.ok) throw new ErrorBanco(ruta, r.status, String(datos.message ?? `HTTP ${r.status}`));
  return datos;
}

let token: { valor: string; vence: number } | null = null;
async function autenticar(): Promise<string> {
  if (token && Date.now() < token.vence) return token.valor;
  const r = await banco("POST", "/api/authentication/authenticate", {
    cuerpo: { userName: env("BANECO_USER"), password: await cifrar(env("BANECO_PASSWORD")) },
  });
  if (r.responseCode !== 0 || !r.token) throw new ErrorBanco("autenticacion", r.responseCode, String(r.message || "Sin token"));
  let vence = Date.now() + 25 * 60_000;
  try {
    const p = JSON.parse(atob(String(r.token).split(".")[1].replace(/-/g, "+").replace(/_/g, "/")));
    if (p.exp) vence = p.exp * 1000 - 60_000;   // un minuto antes de que venza
  } catch { /* token opaco: 25 minutos */ }
  token = { valor: String(r.token), vence };
  return token.valor;
}

async function conToken<T>(f: (t: string) => Promise<T>): Promise<T> {
  try { return await f(await autenticar()); }
  catch (e) {
    // token rechazado: se pide uno nuevo una vez
    if (e instanceof ErrorBanco && (e.codigo === 401 || e.codigo === 403)) { token = null; return await f(await autenticar()); }
    throw e;
  }
}

const estadoDe = (r: Resp) => Number(r.statusQRCode ?? r.statusQrCode ?? r.statusQRcode ?? NaN);
const pagoDe = (r: Resp) => (Array.isArray(r.payment) ? r.payment[0] : r.payment) as Record<string, unknown> | undefined;

async function consultarEstado(qrId: string) {
  return await conToken(async (t) => {
    const r = await banco("GET", "/api/qrsimple/statusQR", { query: { qrId }, token: t });
    if (r.responseCode !== 0) throw new ErrorBanco("statusQR", r.responseCode, String(r.message));
    return { estado: estadoDe(r), pago: pagoDe(r) };
  });
}

// ── reglas ─────────────────────────────────────────────────────────────
const hoyBolivia = () => new Date(Date.now() - 4 * 3600_000).toISOString().slice(0, 10);

async function confirmarSiPagado(fila: { id: string; qr_id: string }) {
  const { estado, pago } = await consultarEstado(fila.qr_id);
  await admin.from("pago_qr").update({ ultimo_chequeo: new Date().toISOString() }).eq("id", fila.id);
  if (estado === 1 && pago) {
    const { data, error } = await admin.rpc("aftr_pago_confirmado", { p_qr: fila.qr_id, p_pago: pago });
    if (error) throw error;
    return (data as { estado: string }).estado;
  }
  if (estado === 9) {
    await admin.from("pago_qr").update({ estado: "anulado" }).eq("id", fila.id).eq("estado", "activo");
    return "anulado";
  }
  return "activo";
}

async function usuarioDe(req: Request) {
  const jwt = req.headers.get("authorization")?.replace(/^Bearer\s+/i, "");
  if (!jwt) return null;
  const { data } = await admin.auth.getUser(jwt);
  return data.user;
}

async function ordenDe(req: Request, ordenId: unknown) {
  const u = await usuarioDe(req);
  if (!u) throw new Response(JSON.stringify({ error: "Iniciá sesión." }), { status: 401 });
  const { data: o } = await admin.from("aftr_ordenes").select("*").eq("id", String(ordenId)).maybeSingle();
  if (!o || o.cliente_id !== u.id) throw new Response(JSON.stringify({ error: "Pedido no encontrado." }), { status: 404 });
  return o;
}

const publico = (q: Record<string, unknown> | null) => q && ({
  estado: q.estado, qrId: q.qr_id, imagen: q.qr_imagen, monto: q.monto, moneda: q.moneda, vence: q.vence,
});

async function accionQr(req: Request, ordenId: unknown) {
  const o = await ordenDe(req, ordenId);
  const { data: previo } = await admin.from("pago_qr").select("*").eq("orden_id", o.id).maybeSingle();
  if (previo && previo.qr_id && previo.estado !== "vencido" && previo.estado !== "anulado") return { pago: publico(previo) };
  if (o.estado !== "pendiente") throw new Response(JSON.stringify({ error: `Este pedido está ${o.estado}.` }), { status: 409 });
  if (!(o.total > 0)) throw new Response(JSON.stringify({ error: "Este pedido no tiene importe." }), { status: 409 });

  const transactionId = String(o.id).replaceAll("-", "");
  const vence = o.vence_at ? new Date(new Date(o.vence_at).getTime() - 4 * 3600_000).toISOString().slice(0, 10) : hoyBolivia();
  const r = await conToken(async (t) => banco("POST", "/api/qrsimple/generateQR", {
    token: t,
    cuerpo: {
      transactionId,
      accountCredit: await cifrar(env("BANECO_ACCOUNT")),
      currency: "BOB",
      amount: Number(o.total),
      description: "Entrada AFTR",
      dueDate: vence,
      singleUse: true,
      modifyAmount: false,
    },
  }));
  if (r.responseCode !== 0 || !r.qrId) throw new ErrorBanco("generateQR", r.responseCode, String(r.message || "Sin QR"));
  const fila = {
    orden_id: o.id, ambiente: AMBIENTE(), transaction_id: transactionId, qr_id: String(r.qrId),
    qr_imagen: String(r.qrImage ?? ""), monto: Number(o.total), moneda: "BOB", vence, estado: "activo",
  };
  const { data, error } = await admin.from("pago_qr")
    .upsert(fila, { onConflict: "orden_id" }).select().single();
  if (error) throw error;
  return { pago: publico(data) };
}

async function accionEstado(req: Request, ordenId: unknown) {
  const o = await ordenDe(req, ordenId);
  const { data: q } = await admin.from("pago_qr").select("*").eq("orden_id", o.id).maybeSingle();
  if (!q) return { pago: null, orden: o.estado };
  if (q.estado === "activo" && q.qr_id) {
    try { q.estado = await confirmarSiPagado(q); }
    catch (e) { console.error("estado:", e instanceof Error ? e.message : e); }
  }
  const { data: o2 } = await admin.from("aftr_ordenes").select("estado").eq("id", o.id).single();
  return { pago: { ...publico(q), imagen: undefined }, orden: o2?.estado };
}

async function accionBarrido() {
  const res = { revisados: 0, confirmados: 0, anulados: 0, errores: 0 };
  // 1) QR activos: estado uno por uno
  const { data: activos } = await admin.from("pago_qr")
    .select("id, qr_id, orden_id, aftr_ordenes(estado)").eq("estado", "activo").not("qr_id", "is", null).limit(100);
  for (const q of activos ?? []) {
    res.revisados++;
    try {
      const e = await confirmarSiPagado(q);
      if (e === "pagado") res.confirmados++;
      // pedido muerto y sin pagar: se anula en el banco para que no se pueda pagar
      const ord = (q as { aftr_ordenes?: { estado?: string } }).aftr_ordenes?.estado;
      if (e === "activo" && (ord === "vencida" || ord === "cancelada")) {
        const r = await conToken((t) => banco("DELETE", "/api/qrsimple/cancelQR", { token: t, cuerpo: { qrId: q.qr_id } }));
        if (r.responseCode === 0) {
          await admin.from("pago_qr").update({ estado: "anulado" }).eq("id", q.id);
          res.anulados++;
        }
      }
    } catch (e) {
      res.errores++;
      console.error("barrido:", e instanceof Error ? e.message : e);
      await admin.from("pago_qr").update({ intentos: ((q as { intentos?: number }).intentos ?? 0) + 1 }).eq("id", q.id);
    }
  }
  // 2) conciliación del día con paidQR (por si un estado se perdió)
  try {
    const r = await conToken((t) => banco("GET", "/api/qrsimple/paidQR", { token: t, query: { paymentDate: hoyBolivia() } }));
    for (const p of (r.paymentList as Record<string, unknown>[] | undefined) ?? []) {
      const { data: q } = await admin.from("pago_qr").select("id, estado").eq("qr_id", String(p.qrId)).maybeSingle();
      if (q && q.estado !== "pagado") {
        const { data } = await admin.rpc("aftr_pago_confirmado", { p_qr: String(p.qrId), p_pago: p });
        if ((data as { nuevo?: boolean })?.nuevo) res.confirmados++;
      }
    }
  } catch (e) {
    console.error("paidQR:", e instanceof Error ? e.message : e);
  }
  return res;
}

async function accionAviso(cuerpo: Record<string, unknown>) {
  const p = (cuerpo.Payment ?? cuerpo.payment) as Record<string, unknown> | undefined;
  const qrId = p?.qrId ? String(p.qrId) : null;
  if (qrId) {
    const { data: q } = await admin.from("pago_qr").select("id, qr_id, estado").eq("qr_id", qrId).maybeSingle();
    // no se confía en el aviso: se le vuelve a preguntar al banco
    if (q && q.estado === "activo") {
      try { await confirmarSiPagado(q); } catch (e) { console.error("aviso:", e instanceof Error ? e.message : e); }
    }
  }
  return { responseCode: 0, message: "" };
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: CORS });
  const json = (d: unknown, status = 200) =>
    new Response(JSON.stringify(d), { status, headers: { ...CORS, "Content-Type": "application/json" } });
  try {
    const cuerpo = await req.json().catch(() => ({})) as Record<string, unknown>;
    switch (cuerpo.accion) {
      case "qr": return json(await accionQr(req, cuerpo.orden));
      case "estado": return json(await accionEstado(req, cuerpo.orden));
      case "barrido":
        if (req.headers.get("x-cron") !== env("BANECO_CRON_TOKEN")) return json({ error: "No autorizado." }, 401);
        return json(await accionBarrido());
      default:
        return json(await accionAviso(cuerpo));
    }
  } catch (e) {
    if (e instanceof Response) return new Response(e.body, { status: e.status, headers: { ...CORS, "Content-Type": "application/json" } });
    if (e instanceof ErrorBanco) {
      console.error(`banco ${e.paso}: ${e.codigo} ${e.message}`);
      return json({ error: "El banco no respondió como esperábamos.", paso: e.paso, codigo: e.codigo, detalle: e.message }, 502);
    }
    console.error("baneco:", e instanceof Error ? e.message : e);
    return json({ error: e instanceof Error ? e.message : "Error inesperado" }, 500);
  }
});
