/* El que manda las notificaciones.
 *
 * Toma lo que haya en la cola `avisos_push` y lo entrega por FCM, la API v1.
 * Lo llama el cron con su token; no lo llama ningún navegador.
 *
 * Dos proyectos de Firebase, uno por app, así que hay dos cuentas de servicio
 * y la del aviso se elige por su app. Que una app no pueda mandarle una
 * notificación a los usuarios de la otra no depende de que nadie se acuerde:
 * son credenciales distintas.
 *
 * Un token que FCM da por muerto -la app se desinstaló, el token rotó- se
 * borra en el mismo paso. Si no, la cola se llena de aparatos que ya no
 * existen y cada aviso arrastra reintentos que nunca van a llegar.
 */
import { createClient } from "@supabase/supabase-js";

const env = (n: string) => Deno.env.get(n);
const admin = createClient(env("SUPABASE_URL")!, env("SUPABASE_SERVICE_ROLE_KEY")!, {
  auth: { persistSession: false },
});

type Cuenta = { client_email: string; private_key: string; project_id: string };

function cuentaDe(app: string): Cuenta {
  const crudo = env(app === "venue" ? "FCM_VENUE" : "FCM_AFTR");
  if (!crudo) throw new Error(`Falta la cuenta de servicio de ${app}.`);
  return JSON.parse(crudo);
}

const b64url = (b: Uint8Array) =>
  btoa(String.fromCharCode(...b)).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");

/* El token de acceso de Google, a partir de la cuenta de servicio. Se guarda
   mientras viva: pedir uno por notificación sería una llamada de más por cada
   aviso, y duran una hora. */
const tokens = new Map<string, { valor: string; vence: number }>();

async function accessToken(c: Cuenta) {
  const guardado = tokens.get(c.client_email);
  if (guardado && guardado.vence > Date.now()) return guardado.valor;

  const ahora = Math.floor(Date.now() / 1000);
  const cabecera = b64url(new TextEncoder().encode(JSON.stringify({ alg: "RS256", typ: "JWT" })));
  const cuerpo = b64url(new TextEncoder().encode(JSON.stringify({
    iss: c.client_email,
    scope: "https://www.googleapis.com/auth/firebase.messaging",
    aud: "https://oauth2.googleapis.com/token",
    iat: ahora, exp: ahora + 3600,
  })));
  const pem = c.private_key.replace(/\\n/g, "\n")
    .replace(/-----(BEGIN|END) PRIVATE KEY-----/g, "").replace(/\s+/g, "");
  const llave = await crypto.subtle.importKey(
    "pkcs8", Uint8Array.from(atob(pem), (x) => x.charCodeAt(0)).buffer,
    { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" }, false, ["sign"]);
  const firma = b64url(new Uint8Array(await crypto.subtle.sign(
    { name: "RSASSA-PKCS1-v1_5" }, llave,
    new TextEncoder().encode(`${cabecera}.${cuerpo}`).buffer)));

  const r = await fetch("https://oauth2.googleapis.com/token", {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({
      grant_type: "urn:ietf:params:oauth:grant-type:jwt-bearer",
      assertion: `${cabecera}.${cuerpo}.${firma}`,
    }),
    signal: AbortSignal.timeout(10000),
  });
  if (!r.ok) throw new Error(`Google no dio el token: ${r.status}`);
  const d = await r.json();
  // un minuto de margen, para no usar uno que vence en el camino
  tokens.set(c.client_email, { valor: d.access_token, vence: Date.now() + (d.expires_in - 60) * 1000 });
  return d.access_token as string;
}

/** Entrega un aviso a un aparato. Devuelve el token si está muerto. */
async function mandarA(c: Cuenta, token: string, aviso: Record<string, unknown>) {
  const acceso = await accessToken(c);
  const r = await fetch(
    `https://fcm.googleapis.com/v1/projects/${c.project_id}/messages:send`,
    {
      method: "POST",
      headers: { Authorization: `Bearer ${acceso}`, "Content-Type": "application/json" },
      body: JSON.stringify({
        message: {
          token,
          notification: { title: String(aviso.titulo), body: String(aviso.cuerpo) },
          // los datos van como texto: FCM no acepta otra cosa
          data: Object.fromEntries(Object.entries(
            (aviso.datos ?? {}) as Record<string, unknown>,
          ).map(([k, v]) => [k, String(v)])),
          apns: {
            headers: { "apns-priority": "10" },
            payload: { aps: { sound: "default" } },
          },
          android: { priority: "HIGH", notification: { sound: "default" } },
        },
      }),
      signal: AbortSignal.timeout(12000),
    },
  );
  if (r.ok) return null;
  const texto = await r.text();
  // 404 UNREGISTERED o 400 con token inválido: el aparato ya no existe
  if (r.status === 404 || texto.includes("UNREGISTERED") || texto.includes("INVALID_ARGUMENT")) {
    return token;
  }
  throw new Error(`FCM ${r.status}: ${texto.slice(0, 160)}`);
}

Deno.serve(async (req: Request) => {
  const json = (d: unknown, status = 200) =>
    new Response(JSON.stringify(d), { status, headers: { "Content-Type": "application/json" } });
  if (req.method !== "POST") return json({ error: "Método no permitido." }, 405);

  const esperado = env("PUSH_CRON_TOKEN");
  const dado = req.headers.get("x-cron");
  if (!esperado || !dado || dado.length !== esperado.length) {
    return json({ error: "No autorizado." }, 401);
  }
  let d = 0;
  for (let i = 0; i < dado.length; i++) d |= dado.charCodeAt(i) ^ esperado.charCodeAt(i);
  if (d !== 0) return json({ error: "No autorizado." }, 401);

  const { data, error } = await admin.rpc("push_tomar", { p_cuantos: 20 });
  if (error) return json({ error: "No se pudo leer la cola." }, 500);

  const res = { mandados: 0, fallidos: 0, aparatosBorrados: 0 };
  for (const aviso of data ?? []) {
    const tokensDelAviso = (aviso.tokens ?? []) as string[];
    if (!tokensDelAviso.length) {
      // sin aparatos no hay nada que entregar: se cierra y no se reintenta
      await admin.rpc("push_resultado", { p_id: aviso.id, p_ok: true });
      continue;
    }
    const muertos: string[] = [];
    let fallo: string | null = null;
    try {
      const c = cuentaDe(String(aviso.app ?? "aftr"));
      for (const t of tokensDelAviso) {
        const muerto = await mandarA(c, t, aviso);
        if (muerto) muertos.push(muerto);
      }
    } catch (e) {
      fallo = e instanceof Error ? e.message : "error desconocido";
    }
    // Se reintenta sólo si falló la entrega -red, credenciales-. Que todos los
    // aparatos estén muertos no es un fallo: ya se los borró, así que
    // reintentar no tiene a quién mandarle y el aviso quedaría dando vueltas.
    const ok = !fallo;
    if (!ok && fallo) {
      console.error(JSON.stringify({ evento: "push", id: aviso.id, motivo: fallo }));
    }
    await admin.rpc("push_resultado", {
      p_id: aviso.id, p_ok: ok, p_error: fallo,
      p_muertos: muertos.length ? muertos : null,
    });
    res.aparatosBorrados += muertos.length;
    ok ? res.mandados++ : res.fallidos++;
  }
  return json(res);
});
