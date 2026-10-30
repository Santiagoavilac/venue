/* crear-usuario · edge function RECONSTRUIDA del origen (fuente no visible;
 * comportamiento derivado de los 4 sitios de llamada en app.js y de los
 * perfiles reales que dejó).
 *
 * Acciones (todas POST JSON):
 *  - {action:'registro', invite, nombre, usuario, clave}
 *      autoregistro con link de invitación de un team (Bearer = anon key).
 *      Responde {team: <nombre>} — el cliente toastea "Bienvenido al X" y
 *      luego se loguea solo con usuario@plataforma.local + clave.
 *  - {usuario, nombre, clave, rol, team_id}   (sin action)
 *      alta por un ADMIN (cualquier rol/team; el cliente después pisa
 *      profiles.clubs según el boliche elegido) o por un JEFE (el cliente
 *      manda rol:'rrpp' y su propio team; acá se EXIGE eso mismo).
 *  - {action:'reset', user_id, clave}
 *      "admin cualquiera; jefe sus RRPP" (comentario del cliente, L6653).
 *  - {action:'link', user_id, volver}
 *      link para entrar sin contraseña (un uso, 1 h), mismas reglas que
 *      reset y nunca para admins. Responde {link}.
 *
 * Contratos del cliente: usuario en minúsculas (el cliente busca
 * .eq('usuario', usuario.toLowerCase())); clave mínimo 6; errores como
 * {error} con status != 2xx (el cliente muestra out.error tal cual).
 * TEXTOS de error SUPUESTOS (los reales del origen no son observables).
 * clubs del perfil: los del team; sin team queda sin boliches y el admin
 * que lo creó se los asigna después.
 *
 * ENDURECIDO (ver IMPLEMENTATION_STATUS.md): límite de intentos e
 * invitaciones con vencimiento en el registro; rol validado; crear admins
 * es solo de la plataforma; el admin de boliche no sale de sus locales.
 */
import { createClient } from "jsr:@supabase/supabase-js@2";

const CORS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, apikey, content-type",
};
const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), { status, headers: { ...CORS, "Content-Type": "application/json" } });

const admin = createClient(
  Deno.env.get("SUPABASE_URL")!,
  Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
  { auth: { persistSession: false } },
);

const ROLES = ["admin", "jefe", "rrpp", "portero", "caja", "propietario", "barra", "deposito"];

/* Límite de intentos por IP para lo que se llama sin sesión. */
async function demasiadosIntentos(req: Request, accion: string, max: number, minutos: number) {
  const ip = (req.headers.get("x-forwarded-for") ?? "desconocida").split(",")[0].trim();
  const clave = `${accion}:${ip}`;
  const desde = new Date(Date.now() - minutos * 60_000).toISOString();
  const { count } = await admin.from("rate_limit")
    .select("id", { count: "exact", head: true }).eq("clave", clave).gte("at", desde);
  await admin.from("rate_limit").insert({ clave });
  return (count ?? 0) >= max;
}

async function crearCuenta(usuario: string, nombre: string, clave: string, rol: string,
  team_id: string | null, creado_por: string | null, clubsIniciales: string[] | null = null) {
  if (!ROLES.includes(rol)) return json({ error: "Rol inválido" }, 400);
  usuario = usuario.trim().toLowerCase();
  if (!/^[a-z0-9._-]{3,30}$/.test(usuario)) return json({ error: "Usuario inválido (3-30, letras/números/._-)" }, 400);
  if (!nombre?.trim() || (clave ?? "").length < 6) return json({ error: "Completá nombre y clave (6+)" }, 400);

  const { data: dupe } = await admin.from("profiles").select("id").eq("usuario", usuario).maybeSingle();
  if (dupe) return json({ error: `El usuario @${usuario} ya existe` }, 409);

  // Boliches del perfil: los del team. Sin team queda SIN boliches y el
  // admin que lo creó le asigna el suyo (antes se le daban "todos los
  // boliches activos", es decir acceso a locales ajenos).
  let clubs: string[] = clubsIniciales ?? [];
  if (team_id) {
    const { data: team } = await admin.from("teams").select("clubs").eq("id", team_id).maybeSingle();
    if (!team) return json({ error: "Team inexistente" }, 400);
    clubs = team.clubs ?? [];
  }
  const { data: creado, error: eAuth } = await admin.auth.admin.createUser({
    email: `${usuario}@plataforma.local`, password: clave, email_confirm: true,
  });
  if (eAuth) return json({ error: eAuth.message }, 400);
  const { error: ePerfil } = await admin.from("profiles").insert({
    id: creado.user.id, usuario, nombre: nombre.trim(), rol, team_id, created_at: new Date().toISOString(),
    activo: true, clubs, puede_tickear: false, admin_principal: false, creado_por,
  });
  if (ePerfil) {
    await admin.auth.admin.deleteUser(creado.user.id);
    return json({ error: ePerfil.message }, 400);
  }
  return { usuario, id: creado.user.id };
}

async function quienLlama(req: Request) {
  const jwt = (req.headers.get("Authorization") ?? "").replace(/^Bearer\s+/i, "");
  if (!jwt) return null;
  const { data } = await admin.auth.getUser(jwt);
  if (!data?.user) return null;
  const { data: perfil } = await admin.from("profiles")
    .select("id, rol, team_id, activo, clubs, admin_principal, eliminado_at").eq("id", data.user.id).maybeSingle();
  if (!perfil?.activo || perfil.eliminado_at) return null;
  const { data: pa } = await admin.from("platform_admins").select("user_id").eq("user_id", perfil.id).maybeSingle();
  return { ...perfil, plataforma: !!perfil.admin_principal || !!pa };
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: CORS });
  if (req.method !== "POST") return json({ error: "Método no soportado" }, 405);
  let body: Record<string, string | null>;
  try { body = await req.json(); } catch { return json({ error: "JSON inválido" }, 400); }

  /* ---- autoregistro con invitación (sin sesión) ---- */
  if (body.action === "registro") {
    // 10 intentos cada 10 minutos por IP: frena tanto adivinar el código
    // como crear cuentas en masa con un link filtrado.
    if (await demasiadosIntentos(req, "registro", 10, 10))
      return json({ error: "Demasiados intentos. Probá de nuevo en unos minutos." }, 429);
    const invite = (body.invite ?? "").trim().toLowerCase();
    if (!invite) return json({ error: "Invitación inválida" }, 400);
    const { data: team } = await admin.from("teams")
      .select("id, nombre, activo, invite_expira").eq("invite_code", invite).maybeSingle();
    if (!team || !team.activo || (team.invite_expira && new Date(team.invite_expira) < new Date()))
      return json({ error: "Invitación inválida o vencida" }, 400);
    const r = await crearCuenta(body.usuario ?? "", body.nombre ?? "", body.clave ?? "", "rrpp", team.id, null);
    if (r instanceof Response) return r;
    return json({ team: team.nombre });
  }

  /* ---- lo demás exige sesión de admin o jefe ---- */
  const caller = await quienLlama(req);
  if (!caller || !["admin", "jefe"].includes(caller.rol)) return json({ error: "No autorizado" }, 403);

  /* reset de clave y link de acceso: mismas reglas sobre a quién se toca */
  if (body.action === "reset" || body.action === "link") {
    const { data: target } = await admin.from("profiles")
      .select("id, usuario, rol, team_id, admin_principal, clubs, activo, eliminado_at").eq("id", body.user_id).maybeSingle();
    if (!target) return json({ error: "Usuario no encontrado" }, 404);
    // la cuenta con admin_principal es máxima autoridad: nadie más la toca
    // (ni otro admin); solo su dueño puede cambiar su propia clave
    if (target.admin_principal && target.id !== caller.id)
      return json({ error: "Esta cuenta administrativa está protegida." }, 403);
    if (caller.rol === "jefe" && (target.rol !== "rrpp" || target.team_id !== caller.team_id))
      return json({ error: "Solo podés gestionar a la gente de tu team" }, 403);
    // un admin de boliche no toca a otros admins ni a gente de otro local
    if (caller.rol === "admin" && !caller.plataforma && target.id !== caller.id) {
      const mios = new Set<string>(caller.clubs ?? []);
      const suyos: string[] = target.clubs ?? [];
      if (target.rol === "admin" || !suyos.length || !suyos.every((c) => mios.has(c)))
        return json({ error: "Solo podés gestionar a la gente de tu boliche" }, 403);
    }

    if (body.action === "link") {
      /* Link para entrar sin contraseña: un solo uso y vence a la hora (el
         vencimiento de los códigos de Supabase). Nunca para un admin: esa
         cuenta entra con su clave. No se envía nada: el link vuelve al que
         lo pidió, que lo manda por WhatsApp. */
      if (target.rol === "admin") return json({ error: "Los administradores entran con su contraseña." }, 403);
      if (!target.activo || target.eliminado_at) return json({ error: "La cuenta está pausada." }, 400);
      const { data, error } = await admin.auth.admin.generateLink({
        type: "magiclink",
        email: `${target.usuario}@plataforma.local`,
        options: { redirectTo: body.volver ?? undefined },
      });
      if (error || !data?.properties?.action_link) return json({ error: error?.message ?? "No se pudo crear el link" }, 400);
      return json({ link: data.properties.action_link });
    }

    if ((body.clave ?? "").length < 6) return json({ error: "Clave mínimo 6 caracteres" }, 400);
    const { error } = await admin.auth.admin.updateUserById(target.id, { password: body.clave! });
    if (error) return json({ error: error.message }, 400);
    return json({ ok: true });
  }

  /* alta directa */
  let rol = body.rol ?? "rrpp", team = body.team_id ?? null;
  if (caller.rol === "jefe") { rol = "rrpp"; team = caller.team_id; }   // el jefe solo crea rrpps de SU team
  // nombrar administradores es de la plataforma, no de un admin de boliche
  if (rol === "admin" && !caller.plataforma)
    return json({ error: "Solo un administrador de la plataforma puede crear administradores" }, 403);
  // un admin de boliche solo usa teams que operan en sus boliches
  if (team && caller.rol === "admin" && !caller.plataforma) {
    const { data: t } = await admin.from("teams").select("clubs").eq("id", team).maybeSingle();
    const mios = new Set<string>(caller.clubs ?? []);
    if (!t || !(t.clubs ?? []).length || !(t.clubs as string[]).every((c) => mios.has(c)))
      return json({ error: "Ese team no es de tu boliche" }, 403);
  }
  const r = await crearCuenta(body.usuario ?? "", body.nombre ?? "", body.clave ?? "", rol, team, caller.id);
  if (r instanceof Response) return r;
  return json({ ok: true, usuario: r.usuario });
});
