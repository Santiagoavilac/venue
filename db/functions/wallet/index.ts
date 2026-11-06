/* La entrada, a la billetera del teléfono.
 *
 * Se abre desde el correo, que se lee fuera de la app y sin sesión. Por eso el
 * enlace lleva el código de la entrada y una firma corta; sin la firma no se
 * mira nada. El código solo no alcanza: quien tenga el correo tiene la
 * entrada, que es como ya funciona el QR, pero nadie puede ir probando códigos
 * contra esta función.
 *
 * Apple devuelve un archivo firmado (.pkpass). Google, un enlace a su propio
 * sitio con un JWT firmado adentro. Las dos llevan la hora del evento y la
 * ubicación del boliche: eso es lo que hace que el pase aparezca solo en la
 * pantalla bloqueada cuando se acerca la fecha o cuando la persona llega.
 */
import { createClient } from "@supabase/supabase-js";
import { armarPase } from "./pkpass.ts";
import { dePem, llaveDePem } from "./cms.ts";
import { enlaceGoogle } from "./google.ts";

const env = (n: string) => Deno.env.get(n);
const admin = createClient(env("SUPABASE_URL")!, env("SUPABASE_SERVICE_ROLE_KEY")!, {
  auth: { persistSession: false },
});

const PROPIOS = [
  "https://www.aftrvenue.com", "https://aftrvenue.com",
  "https://aftr-web.vercel.app", "http://localhost:8000",
];

function cors(req: Request) {
  const base: Record<string, string> = { "Access-Control-Allow-Methods": "GET, POST, OPTIONS" };
  const origen = req.headers.get("origin");
  if (!origen || !PROPIOS.includes(origen)) return base;
  const pedidos = req.headers.get("access-control-request-headers");
  return {
    ...base,
    ...(pedidos ? { "Access-Control-Allow-Headers": pedidos } : {}),
    "Access-Control-Allow-Origin": origen,
    Vary: "Origin, Access-Control-Request-Headers",
  };
}

/* La firma del enlace. Corta a propósito: no protege un secreto, sólo impide
   que alguien vaya probando códigos contra esta función. */
export async function firmaDe(codigo: string, secreto: string) {
  const llave = await crypto.subtle.importKey(
    "raw", new TextEncoder().encode(secreto).buffer,
    { name: "HMAC", hash: "SHA-256" }, false, ["sign"]);
  const f = new Uint8Array(await crypto.subtle.sign(
    "HMAC", llave, new TextEncoder().encode(codigo).buffer));
  return [...f].map((b) => b.toString(16).padStart(2, "0")).join("").slice(0, 24);
}

async function iguales(a: string, b: string) {
  if (a.length !== b.length) return false;
  let d = 0;
  for (let i = 0; i < a.length; i++) d |= a.charCodeAt(i) ^ b.charCodeAt(i);
  return d === 0;
}

async function paseApple(d: Record<string, unknown>) {
  const certs = [
    dePem(env("WALLET_CERT")!, "CERTIFICATE")[0],
    dePem(env("WALLET_WWDR")!, "CERTIFICATE")[0],
  ];
  const llave = await llaveDePem(env("WALLET_KEY")!);
  // el ícono del pase: el mismo de la app
  const icono = await (await fetch(
    `${env("SUPABASE_URL")}/storage/v1/object/public/disenos/wallet-icono.png`,
  )).arrayBuffer().catch(() => null);
  const imagenes: Record<string, Uint8Array> = {};
  if (icono) {
    const b = new Uint8Array(icono);
    imagenes["icon.png"] = b;
    imagenes["icon@2x.png"] = b;
    imagenes["logo.png"] = b;
  }
  if (!imagenes["icon.png"]) throw new Error("Falta el ícono del pase.");
  return await armarPase({
    codigo: String(d.codigo), serie: String(d.serie),
    evento: String(d.evento ?? "AFTR"), club: String(d.club ?? ""),
    persona: String(d.persona ?? "Invitado"), inicio: String(d.inicio),
    lugar: d.lat != null && d.lng != null ? { lat: Number(d.lat), lng: Number(d.lng) } : null,
  }, {
    passTypeIdentifier: env("WALLET_PASS_TYPE")!,
    teamIdentifier: env("WALLET_TEAM")!,
    certs, llave, imagenes,
  });
}

Deno.serve(async (req: Request) => {
  const CORS = cors(req);
  const json = (d: unknown, status = 200) =>
    new Response(JSON.stringify(d), { status, headers: { ...CORS, "Content-Type": "application/json" } });
  if (req.method === "OPTIONS") return new Response("ok", { headers: CORS });

  try {
    const u = new URL(req.url);
    const codigo = (u.searchParams.get("c") ?? "").trim();
    const firma = (u.searchParams.get("f") ?? "").trim();
    const tipo = (u.searchParams.get("t") ?? "apple").trim();
    const secreto = env("WALLET_LINK_SECRET");
    if (!secreto) return json({ error: "La billetera no está configurada." }, 503);
    if (!codigo || !firma) return json({ error: "Enlace incompleto." }, 400);
    if (!await iguales(firma, await firmaDe(codigo, secreto))) {
      return json({ error: "Este enlace no es válido." }, 403);
    }

    const { data, error } = await admin.rpc("wallet_entrada", { p_code: codigo });
    if (error) return json({ error: "No pudimos leer la entrada." }, 500);
    if (!data) return json({ error: "Esta entrada ya no está disponible." }, 404);

    if (tipo === "google") {
      const cuenta = JSON.parse(env("FCM_AFTR")!);
      const enlace = await enlaceGoogle({
        codigo: String(data.codigo), serie: String(data.serie),
        evento: String(data.evento), club: String(data.club),
        persona: String(data.persona ?? "Invitado"), inicio: String(data.inicio),
        fecha: String(data.fecha), hora: String(data.hora),
        lugar: data.lat != null && data.lng != null
          ? { lat: Number(data.lat), lng: Number(data.lng) } : null,
      }, env("WALLET_GOOGLE_ISSUER")!, cuenta);
      // se lo manda derecho a Google, que es donde se guarda
      return new Response(null, { status: 302, headers: { ...CORS, Location: enlace } });
    }

    const pkpass = await paseApple(data as Record<string, unknown>);
    return new Response(pkpass, {
      headers: {
        ...CORS,
        "Content-Type": "application/vnd.apple.pkpass",
        "Content-Disposition": `attachment; filename="entrada-aftr.pkpass"`,
        "Cache-Control": "no-store",
      },
    });
  } catch (e) {
    console.error(JSON.stringify({ evento: "wallet", motivo: e instanceof Error ? e.message : "?" }));
    return json({ error: "No pudimos armar el pase. Tu entrada sigue en AFTR." }, 500);
  }
});
