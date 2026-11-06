import type { SupabaseClient } from "@supabase/supabase-js";
import { Banco, type Datos, type Entorno, ErrorBanco } from "./bank.ts";

/* CORS: era `*`, o sea que cualquier página podía llamar a la función del cobro
   con la sesión de quien la estuviera mirando. Ahora sólo los dominios propios.
   El webhook del banco y la app nativa no mandan Origin: ahí no hay nada que
   autorizar en el navegador, y el permiso real lo da el token de la petición. */
const PROPIOS = [
  "https://www.aftrvenue.com", "https://aftrvenue.com",
  "https://aftr-web.vercel.app", "https://venue-web-amber.vercel.app",
  "http://localhost:5173", "http://localhost:8000", "http://127.0.0.1:5173",
];
const BASE_CORS = {
  "Access-Control-Allow-Methods": "POST, OPTIONS",
  "Access-Control-Allow-Headers": "authorization, apikey, content-type, x-cron, x-baneco-token",
};
function cors(req: Request, extra?: string) {
  const permitidos = [...PROPIOS, ...(extra ?? "").split(",").map((o) => o.trim()).filter(Boolean)];
  const origen = req.headers.get("origin");
  return origen && permitidos.includes(origen)
    ? { ...BASE_CORS, "Access-Control-Allow-Origin": origen, Vary: "Origin" }
    : BASE_CORS;
}
const publico = (q: Datos | null, imagen = true) => q && ({
  estado: q.estado, qrId: q.qr_id, ...(imagen ? { imagen: q.qr_imagen } : {}), monto: q.monto, moneda: q.moneda, vence: q.vence,
  // limite es cuando deja de cobrarse (diez minutos); nota, por qué quedó en
  // revisión. Sin esto la app no puede decirle a la persona qué le pasó.
  limite: q.limite_at, nota: q.nota,
});
// El cobro vive diez minutos: una orden puede tener varios QR, y sólo uno
// vivo. Los anulados quedan de histórico y no deben contestar por el actual.
const VIVOS = ["generando", "activo", "pagado", "revisar"];
const vivo = (q: Datos | null | undefined) => !!q && VIVOS.includes(String(q.estado));
const ultimoQr = (c: SupabaseClient, columna: string, id: string) =>
  c.from("pago_qr").select("*").eq(columna, id)
    .order("created_at", { ascending: false }).limit(1).maybeSingle();
const fallar = (error: unknown) => { if (error) throw new Error("No se pudo registrar el cobro."); };
const destinos = {
  orden: { tabla: "aftr_ordenes", columna: "orden_id" },
  recarga: { tabla: "pulse_recargas", columna: "recarga_id" },
  pedido: { tabla: "aftr_bar_pedidos", columna: "pedido_id" },
} as const;
type Tipo = keyof typeof destinos;
function tipoDe(valor: unknown): Tipo {
  if (valor === undefined) return "orden";
  if (typeof valor !== "string" || !Object.hasOwn(destinos, valor)) rechazar("Destino inválido.", 400);
  return valor as Tipo;
}
const rechazar = (mensaje: string, status: number): never => { throw new Response(JSON.stringify({ error: mensaje }), { status }); };
async function secretoIgual(a: string | null, b: string | undefined) {
  if (!a || !b || b.length < 32) return false;
  const hash = async (s: string) => new Uint8Array(await crypto.subtle.digest("SHA-256", new TextEncoder().encode(s)));
  const [x, y] = await Promise.all([hash(a), hash(b)]);
  let diferencia = 0;
  for (let i = 0; i < x.length; i++) diferencia |= x[i] ^ y[i];
  return diferencia === 0;
}

export function crearHandler(admin: SupabaseClient, banco: Banco | ((pasarela: string) => Banco),
  env: Entorno, ahora = Date.now,
  registrar: (datos: Datos) => void = (d) => console.error(JSON.stringify(d))) {
  // Cada boliche puede cobrar a su propia cuenta (migración 20261106280000).
  // La pasarela es un nombre corto que elige las credenciales; la vacía es la
  // de la plataforma, que es como funcionaba todo hasta ahora.
  const bancoDe = typeof banco === "function" ? banco : () => banco;
  const plataforma = bancoDe("");
  const log = (evento: string, error: unknown) => registrar({ evento,
    ...(error instanceof ErrorBanco ? { paso: error.paso, codigo: error.codigo } : { codigo: "ERROR_INTERNO" }) });
  async function rpc(nombre: string, params: Datos) {
    const { data, error } = await admin.rpc(nombre, params);
    fallar(error); return data;
  }
  async function ordenDe(req: Request, id: unknown, tipo: Tipo) {
    const jwt = req.headers.get("authorization")?.replace(/^Bearer\s+/i, "");
    if (!jwt) rechazar("Iniciá sesión.", 401);
    const { data: { user }, error } = await admin.auth.getUser(jwt!);
    if (error || !user) rechazar("Iniciá sesión.", 401);
    if (typeof id !== "string" || !/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(id)) rechazar("Pedido no encontrado.", 404);
    const r = await admin.from(destinos[tipo].tabla).select("*").eq("id", id).maybeSingle();
    fallar(r.error);
    if (!r.data || r.data.cliente_id !== user!.id) rechazar("Pedido no encontrado.", 404);
    return r.data as Datos;
  }
  async function confirmar(fila: Datos) {
    // La del QR y no la del boliche: el boliche pudo cambiar de cuenta
    // después de generarlo, y este cobro sigue siendo de la cuenta vieja.
    const banco = bancoDe(String(fila.pasarela ?? ""));
    const r = await banco.estado(String(fila.qr_id));
    const chequeo = await admin.from("pago_qr").update({ ultimo_chequeo: new Date(ahora()).toISOString() }).eq("id", fila.id);
    fallar(chequeo.error);
    if (r.estado === 1) return (await rpc("aftr_pago_confirmado", { p_qr: fila.qr_id, p_pago: r.pago })).estado as string;
    if (r.estado === 9) {
      await rpc("baneco_qr_anulado", { p_qr: fila.qr_id });
      return "anulado";
    }
    return String(fila.estado);
  }
  async function pedirQr(req: Request, id: unknown, tipo: Tipo) {
    const o = await ordenDe(req, id, tipo);
    // A qué cuenta cobra esto: la del evento, la del boliche o la de la
    // plataforma. Lo decide la base, que es la que sabe los enlaces.
    const banco = bancoDe(String(await rpc("baneco_pasarela_de", { p_tipo: tipo, p_id: o.id }) ?? ""));
    const anterior = await ultimoQr(admin, destinos[tipo].columna, String(o.id));
    fallar(anterior.error);
    // Un QR muerto de otro ambiente es histórico y no estorba; uno vivo sí.
    if (vivo(anterior.data) && anterior.data!.ambiente !== banco.config.ambiente) rechazar("Este pedido corresponde a otro ambiente de cobro.", 409);
    if (anterior.data?.qr_id && vivo(anterior.data)) {
      if (anterior.data.estado === "activo" && (o.estado !== "pendiente" || Date.parse(String(o.vence_at)) <= ahora())) {
        rechazar("Este pedido ya no está disponible para pagar.", 409);
      }
      return { pago: publico(anterior.data) };
    }
    if (o.estado !== "pendiente" || (o.vence_at && Date.parse(String(o.vence_at)) <= ahora())) rechazar("Este pedido venció o ya fue resuelto.", 409);
    // Fallar antes de reservar si faltan credenciales o la habilitación.
    const ambiente = banco.config.ambiente;
    const cuenta = await banco.prepararCuenta();
    await banco.autenticar();
    const reserva = tipo === "orden"
      ? await rpc("baneco_reservar_qr", { p_orden: o.id, p_cliente: o.cliente_id, p_ambiente: ambiente })
      : await rpc("baneco_reservar_destino", { p_tipo: tipo, p_id: o.id, p_cliente: o.cliente_id, p_ambiente: ambiente });
    const q = reserva.pago as Datos;
    if (!reserva.reservado) {
      if (q.qr_id) return { pago: publico(q) };
      rechazar(q.estado === "generando" ? "El QR se está preparando. Volvé a intentar en unos segundos." : "El cobro necesita revisión. No vuelvas a pagar.", 409);
    }
    let generado: Awaited<ReturnType<Banco["generar"]>>;
    try { generado = await banco.generar(q, cuenta); }
    catch (e) {
      // Un timeout no demuestra que el banco no haya creado el QR. No se reintenta.
      const incierto = !(e instanceof ErrorBanco) || e.incierto;
      const update = await admin.from("pago_qr").update({ estado: incierto ? "revisar" : "fallido",
        nota: incierto ? "GENERACION_INCIERTA" : "GENERACION_RECHAZADA" })
        .eq("id", q.id).eq("estado", "generando").eq("generacion_id", q.generacion_id);
      fallar(update.error); throw e;
    }
    // Guardar el identificador incluso si el pedido se canceló durante la llamada.
    const guardado = await admin.from("pago_qr").update({ estado: "activo", qr_id: generado.qrId,
      qr_imagen: generado.imagen, nota: null }).eq("id", q.id).eq("estado", "generando")
      .eq("generacion_id", q.generacion_id).select().single();
    fallar(guardado.error);
    if (!guardado.data) throw new Error("No se pudo registrar el QR.");
    return { pago: publico(guardado.data) };
  }
  async function estado(req: Request, id: unknown, tipo: Tipo) {
    const o = await ordenDe(req, id, tipo);
    const r = await ultimoQr(admin, destinos[tipo].columna, String(o.id));
    fallar(r.error);
    if (!r.data) return { pago: null, orden: o.estado };
    const q = r.data;
    if (vivo(q) && q.ambiente !== plataforma.config.ambiente) rechazar("Este pedido corresponde a otro ambiente de cobro.", 409);
    if (q.estado === "activo" && q.qr_id && (!q.ultimo_chequeo || ahora() - Date.parse(q.ultimo_chequeo) >= 4000)) await confirmar(q);
    const [pago, orden] = await Promise.all([
      admin.from("pago_qr").select("*").eq("id", q.id).single(),
      admin.from(destinos[tipo].tabla).select("estado").eq("id", o.id).single(),
    ]);
    fallar(pago.error); fallar(orden.error);
    return { pago: publico(pago.data, false), orden: orden.data?.estado };
  }
  async function barrido() {
    // Cada cuenta tiene su propia lista de pagados en el banco, así que el
    // barrido se hace una vez por pasarela y no una sola vez para todas.
    const lista = await rpc("baneco_pasarelas", {});
    // Si la base no contesta una lista, cobra la plataforma: el barrido tiene
    // que correr igual, no quedarse sin hacer nada.
    const pasarelas = Array.isArray(lista) && lista.length ? lista as string[] : [""];
    const todo = { revisados: 0, confirmados: 0, anulados: 0, errores: 0, conciliados: 0, ocupado: 0 };
    for (const pasarela of pasarelas) {
      const r = await barridoDe(pasarela);
      if ((r as { ocupado?: boolean }).ocupado) { todo.ocupado++; continue; }
      for (const k of ["revisados", "confirmados", "anulados", "errores", "conciliados"] as const) {
        todo[k] += (r as Record<string, number>)[k] ?? 0;
      }
    }
    return todo;
  }
  async function barridoDe(pasarela: string) {
    const banco = bancoDe(pasarela);
    const ambiente = banco.config.ambiente;
    const trabajo = await rpc("baneco_tomar_barrido", { p_ambiente: ambiente, p_pasarela: pasarela });
    if (!trabajo) return { ocupado: true };
    const inicio = ahora();
    const res = { revisados: 0, confirmados: 0, anulados: 0, errores: 0, conciliados: 0 };
    let diaOk: string | null = null;
    try {
      await rpc("baneco_liberar_sin_qr", {});
      const activos = await admin.from("pago_qr").select("id, qr_id, orden_id, recarga_id, pedido_id, limite_at, estado, intentos, pasarela, aftr_ordenes(estado, vence_at)")
        .eq("ambiente", ambiente).eq("pasarela", pasarela).eq("estado", "activo").not("qr_id", "is", null)
        .order("ultimo_chequeo", { ascending: true, nullsFirst: true }).limit(100);
      fallar(activos.error);
      for (const q of activos.data ?? []) {
        // Reservar tiempo para paidQR y liberar el lease antes del timeout de pg_net.
        if (ahora() - inicio > 24000) break;
        res.revisados++;
        try {
          const e = await confirmar(q);
          if (e === "pagado") res.confirmados++;
          const o = q.aftr_ordenes as unknown as { estado: string; vence_at: string } | null;
          const vencido = q.limite_at ? Date.parse(String(q.limite_at)) <= ahora()
            : q.orden_id && (o?.estado !== "pendiente" || (o?.vence_at && Date.parse(o.vence_at) <= ahora()));
          if (e === "activo" && vencido) {
            await banco.anular(q.qr_id);
            // Resolver la carrera pagar/cancelar consultando de nuevo al banco.
            const despues = await confirmar(q);
            if (despues === "anulado") res.anulados++;
            if (despues === "pagado") res.confirmados++;
          }
        } catch (e) {
          res.errores++; log("barrido_qr", e);
          const update = await admin.from("pago_qr").update({ intentos: q.intentos + 1, ultimo_chequeo: new Date(ahora()).toISOString() }).eq("id", q.id);
          fallar(update.error);
        }
      }
      // Cursor persistente: no saltear días si el servicio estuvo caído.
      const pagos = await banco.pagados(trabajo.dia);
      let diaCompleto = true;
      for (const p of pagos) {
        if (ahora() - inicio > 42000) { res.errores++; diaCompleto = false; break; }
        if (!p.qrId || !p.transactionId) { res.errores++; diaCompleto = false; continue; }
        const r = await admin.from("pago_qr").select("id, estado, pasarela").eq("ambiente", ambiente).eq("pasarela", pasarela).eq("qr_id", String(p.qrId)).maybeSingle();
        fallar(r.error);
        if (r.data && r.data.estado !== "pagado") {
          const resultado = await rpc("aftr_pago_confirmado", { p_qr: String(p.qrId), p_pago: p });
          if (resultado.nuevo) res.confirmados++;
          res.conciliados++;
        }
      }
      if (diaCompleto) diaOk = trabajo.dia;
    } catch (e) { res.errores++; log("conciliacion", e); }
    finally {
      await rpc("baneco_finalizar_barrido", { p_ambiente: ambiente, p_token: trabajo.token, p_dia_ok: diaOk, p_errores: res.errores, p_pasarela: pasarela });
    }
    return res;
  }
  async function aviso(req: Request, cuerpo: Datos) {
    if (!env("BANECO_WEBHOOK_TOKEN")) rechazar("Notificaciones no habilitadas.", 404);
    if (!await secretoIgual(req.headers.get("x-baneco-token"), env("BANECO_WEBHOOK_TOKEN"))) rechazar("No autorizado.", 401);
    const p = cuerpo.Payment ?? cuerpo.payment;
    if (!p || typeof p !== "object" || Array.isArray(p) || !(p as Datos).qrId) rechazar("Notificación inválida.", 400);
    const r = await admin.from("pago_qr").select("id, qr_id, estado, pasarela").eq("ambiente", plataforma.config.ambiente)
      .eq("qr_id", String((p as Datos).qrId)).maybeSingle();
    fallar(r.error);
    // El cuerpo recibido nunca se pasa a la función que emite entradas.
    if (r.data && r.data.estado !== "pagado") await confirmar(r.data);
    return { responseCode: 0, message: "" };
  }
  return async (req: Request): Promise<Response> => {
    const CORS = cors(req, env("ORIGENES_PERMITIDOS"));
    const json = (d: unknown, status = 200) => new Response(JSON.stringify(d), { status, headers: { ...CORS, "Content-Type": "application/json" } });
    if (req.method === "OPTIONS") return new Response("ok", { headers: CORS });
    if (req.method !== "POST") return json({ error: "Método no permitido." }, 405);
    try {
      const texto = await req.text();
      if (texto.length > 16384) return json({ error: "Solicitud demasiado grande." }, 413);
      let cuerpo: Datos;
      try { cuerpo = JSON.parse(texto); } catch { return json({ error: "JSON inválido." }, 400); }
      if (!cuerpo || typeof cuerpo !== "object" || Array.isArray(cuerpo)) return json({ error: "Solicitud inválida." }, 400);
      switch (cuerpo.accion) {
        case "qr": return json(await pedirQr(req, cuerpo.orden, tipoDe(cuerpo.tipo)));
        case "estado": return json(await estado(req, cuerpo.orden, tipoDe(cuerpo.tipo)));
        case "barrido":
          if (!await secretoIgual(req.headers.get("x-cron"), env("BANECO_CRON_TOKEN"))) return json({ error: "No autorizado." }, 401);
          return json(await barrido());
        default:
          if (cuerpo.accion !== undefined) return json({ error: "Acción desconocida." }, 400);
          return json(await aviso(req, cuerpo));
      }
    } catch (e) {
      if (e instanceof Response) return new Response(e.body, { status: e.status, headers: { ...CORS, "Content-Type": "application/json" } });
      log("solicitud", e);
      return json({ error: e instanceof ErrorBanco ? "No pudimos verificar el cobro con el banco. Volvé a intentar." : "El cobro no está disponible. Tu pedido quedó guardado." }, e instanceof ErrorBanco ? 502 : 503);
    }
  };
}
