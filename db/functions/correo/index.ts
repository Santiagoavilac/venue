/* El cartero de AFTR.
 *
 * Toma lo que haya en la cola `correos` y lo manda por Resend. Lo llama el
 * cron cada minuto con su token; no se expone a nadie más.
 *
 * La entrada va con su QR adentro, como imagen adjunta. No es un enlace a
 * propósito: quien compra sin cuenta tiene su sesión en ese navegador y nada
 * más, así que un enlace a Accesos no le sirve desde otro teléfono. Con el QR
 * en el correo, la entrada funciona en cualquier lado, que es justamente para
 * lo que está el correo.
 */
import { createClient } from "@supabase/supabase-js";
import { qrPng, base64 } from "./qr.ts";
import { entradasPdf } from "./pdf.ts";

const env = (n: string) => Deno.env.get(n);
const admin = createClient(env("SUPABASE_URL")!, env("SUPABASE_SERVICE_ROLE_KEY")!, {
  auth: { persistSession: false },
});

const DE = env("CORREO_REMITENTE") || "AFTR <entradas@aftrvenue.com>";
const RESPONDER_A = env("CORREO_RESPUESTA") || undefined;

async function secretoIgual(a: string | null, b: string | undefined) {
  if (!a || !b || b.length < 32) return false;
  const hash = async (s: string) =>
    new Uint8Array(await crypto.subtle.digest("SHA-256", new TextEncoder().encode(s)));
  const [x, y] = await Promise.all([hash(a), hash(b)]);
  let d = 0;
  for (let i = 0; i < x.length; i++) d |= x[i] ^ y[i];
  return d === 0;
}

/* El arte del evento, para el fondo del PDF.
 *
 * Sólo del almacenamiento del propio proyecto: la URL sale de la base, y
 * bajar cualquier dirección que venga de ahí sería dejar que una fila elija a
 * qué servidor llama esta función. Si no se puede bajar, la entrada sale con
 * fondo negro: nunca se deja de mandar la entrada por el fondo.
 */
async function bajarArte(url: unknown): Promise<Uint8Array | null> {
  if (typeof url !== "string" || !url) return null;
  try {
    const u = new URL(url);
    const propio = new URL(env("SUPABASE_URL")!);
    if (u.protocol !== "https:" || u.hostname !== propio.hostname) return null;
    if (!u.pathname.startsWith("/storage/v1/object/public/")) return null;
    const r = await fetch(u, { signal: AbortSignal.timeout(10000), redirect: "error" });
    if (!r.ok) return null;
    const tipo = r.headers.get("content-type") ?? "";
    // el PDF mete el JPEG tal cual; otro formato habría que decodificarlo
    if (!tipo.startsWith("image/jpeg")) return null;
    const b = new Uint8Array(await r.arrayBuffer());
    return b.length && b.length <= 6_000_000 ? b : null;
  } catch {
    return null;
  }
}

/* El QR, servido desde una URL firmada.
 *
 * Qué se rompía: iba incrustado como adjunto en línea (`cid:`). En el teléfono
 * se ve, pero Gmail en la web no lo dibuja -sale el cuadrito roto-, y ahí es
 * donde más gente abre el correo. Una URL firmada sí la muestra.
 *
 * El bucket es privado y el nombre es un uuid al azar: sin la firma no se
 * llega al archivo y no se pueden ir probando nombres. Si subir o firmar
 * falla, el correo sale igual sin la imagen: la entrada de verdad es el PDF
 * adjunto, que no depende de esto.
 */
const DIAS_FIRMA = 60;
async function qrFirmado(codigo: string): Promise<string | null> {
  try {
    const png = await qrPng(codigo);
    const ruta = `${crypto.randomUUID()}.png`;
    const subida = await admin.storage.from("aftr-qr")
      .upload(ruta, png, { contentType: "image/png", upsert: false });
    if (subida.error) return null;
    const firma = await admin.storage.from("aftr-qr")
      .createSignedUrl(ruta, DIAS_FIRMA * 24 * 3600);
    return firma.data?.signedUrl ?? null;
  } catch {
    return null;
  }
}

const esc = (s: unknown) =>
  String(s ?? "").replace(/[&<>"']/g, (c) =>
    ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[c]!));

type Datos = Record<string, unknown>;

const nombreCompleto = (d: Datos) =>
  [d.nombre, d.apellido].map((x) => String(x ?? "").trim()).filter(Boolean).join(" ");

function cuerpoEntradas(d: Datos, codigos: string[], imagenes: (string | null)[]) {
  const nombre = String(d.nombre ?? "").split(" ")[0];
  const persona = nombreCompleto(d) || "Invitado";
  const esMesa = d.tipo === "mesa";
  const cuantas = codigos.length;
  return `<!doctype html><html lang="es"><body style="margin:0;background:#0b0b0d;font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Roboto,Helvetica,Arial,sans-serif;color:#f4f4f5">
  <div style="max-width:520px;margin:0 auto;padding:32px 22px">
    <p style="margin:0 0 28px;font-size:12px;letter-spacing:.18em;color:#a1a1aa">AFTR</p>
    <h1 style="margin:0 0 10px;font-size:28px;line-height:1.2;font-weight:700">
      ${nombre ? `${esc(nombre)}, tu${cuantas > 1 ? "s" : ""} entrada${cuantas > 1 ? "s" : ""} ${cuantas > 1 ? "están" : "está"} lista${cuantas > 1 ? "s" : ""}.` : `Tu${cuantas > 1 ? "s" : ""} entrada${cuantas > 1 ? "s" : ""} ${cuantas > 1 ? "están" : "está"} lista${cuantas > 1 ? "s" : ""}.`}
    </h1>
    <p style="margin:0 0 26px;font-size:15px;color:#a1a1aa">
      Mostrá ${cuantas > 1 ? "cada" : "este"} QR en la puerta. También ${cuantas > 1 ? "están" : "está"} en AFTR, en Accesos.
    </p>

    <div style="border:1px solid rgba(255,255,255,.12);border-radius:16px;padding:20px;margin-bottom:26px">
      <div style="font-size:19px;font-weight:700;margin-bottom:6px">${esc(d.evento)}</div>
      <div style="font-size:14px;color:#a1a1aa">${esc(d.club)}</div>
      <div style="font-size:14px;color:#a1a1aa;margin-top:8px">${esc(d.fecha)}${d.hora ? ` · ${esc(d.hora)}` : ""}</div>
      ${esMesa ? `<div style="font-size:14px;color:#e8c26a;margin-top:8px">Mesa · ${cuantas} manilla${cuantas > 1 ? "s" : ""}</div>` : ""}
    </div>

    ${codigos.map((_c, i) => `
      <div style="border:1px solid rgba(255,255,255,.12);border-radius:16px;padding:20px;margin-bottom:14px;text-align:center">
        ${cuantas > 1 ? `<div style="font-size:12px;letter-spacing:.14em;color:#a1a1aa;margin-bottom:12px">ENTRADA ${i + 1} DE ${cuantas}</div>` : ""}
        ${imagenes[i]
          ? `<img src="${esc(imagenes[i])}" alt="QR de la entrada" width="220" height="220"
                 style="display:block;margin:0 auto;background:#fff;border-radius:12px;padding:10px">`
          : `<div style="padding:26px 10px;font-size:14px;color:#a1a1aa">Tu QR está en el PDF adjunto.</div>`}
        <div style="margin-top:14px;font-size:12px;color:#a1a1aa">A nombre de</div>
        <div style="margin-top:2px;font-size:17px;font-weight:700">${esc(persona)}</div>
      </div>`).join("")}

    <p style="margin:26px 0 0;font-size:13px;color:#71717a">
      ${cuantas > 1 ? "Tus entradas están" : "Tu entrada está"} adjunta${cuantas > 1 ? "s" : ""}
      en PDF, para guardar o imprimir. Si acá no ves el QR, abrí el adjunto: ahí está siempre.
    </p>
    <p style="margin:14px 0 0;font-size:13px;color:#71717a">
      Cada QR entra una sola vez. Si lo compartís, entra quien lo muestre primero.
    </p>
    <p style="margin:18px 0 0;font-size:13px;color:#71717a">
      ¿Algo no cuadra? Respondé este correo y lo resolvemos.
    </p>
  </div></body></html>`;
}

async function mandar(fila: Datos) {
  const clave = env("RESEND_API_KEY");
  if (!clave) throw new Error("Falta configurar RESEND_API_KEY.");
  const d = (fila.datos ?? {}) as Datos;
  const codigos = (Array.isArray(d.codigos) ? d.codigos : []).map(String).filter(Boolean);
  if (!codigos.length) throw new Error("El correo no tiene ninguna entrada que mandar.");

  // los QR del cuerpo, firmados: Gmail en la web no dibuja los `cid:`
  const imagenes = await Promise.all(codigos.map((c) => qrFirmado(c)));

  // y la entrada para descargar: una página por entrada, con el arte de fondo
  const arte = await bajarArte(d.arte);
  const pdf = await entradasPdf(codigos.map((c) => ({
    evento: String(d.evento ?? "AFTR"),
    club: String(d.club ?? ""),
    fecha: String(d.fecha ?? ""),
    hora: String(d.hora ?? ""),
    persona: nombreCompleto(d),
    codigo: c,
  })), arte);
  const todos = [{
    filename: `entrada${codigos.length > 1 ? "s" : ""}-aftr.pdf`,
    content: base64(pdf),
  }];

  const asunto = `Tu${codigos.length > 1 ? "s" : ""} entrada${codigos.length > 1 ? "s" : ""} · ${String(d.evento ?? "AFTR")}`;
  const r = await fetch("https://api.resend.com/emails", {
    method: "POST",
    headers: { Authorization: `Bearer ${clave}`, "Content-Type": "application/json" },
    body: JSON.stringify({
      from: DE,
      to: [String(fila.destino)],
      ...(RESPONDER_A ? { reply_to: RESPONDER_A } : {}),
      subject: asunto,
      html: cuerpoEntradas(d, codigos, imagenes),
      attachments: todos,
    }),
    signal: AbortSignal.timeout(15000),
  });
  const cuerpo = await r.text();
  if (!r.ok) throw new Error(`Resend ${r.status}: ${cuerpo.slice(0, 200)}`);
  return cuerpo;
}

Deno.serve(async (req: Request) => {
  const json = (d: unknown, status = 200) =>
    new Response(JSON.stringify(d), { status, headers: { "Content-Type": "application/json" } });
  // Sin CORS a propósito: esto no lo llama ningún navegador, sólo el cron.
  if (req.method !== "POST") return json({ error: "Método no permitido." }, 405);
  if (!await secretoIgual(req.headers.get("x-cron"), env("CORREO_CRON_TOKEN"))) {
    return json({ error: "No autorizado." }, 401);
  }

  const { data, error } = await admin.rpc("correos_tomar", { p_cuantos: 20 });
  if (error) return json({ error: "No se pudo leer la cola." }, 500);

  const res = { mandados: 0, fallidos: 0 };
  for (const fila of data ?? []) {
    try {
      await mandar(fila);
      await admin.rpc("correos_resultado", { p_id: fila.id, p_ok: true });
      res.mandados++;
    } catch (e) {
      const motivo = e instanceof Error ? e.message : "error desconocido";
      // el motivo se guarda para poder arreglarlo; no se registra el destino
      console.error(JSON.stringify({ evento: "correo", id: fila.id, motivo }));
      await admin.rpc("correos_resultado", { p_id: fila.id, p_ok: false, p_error: motivo });
      res.fallidos++;
    }
  }
  return json(res);
});
