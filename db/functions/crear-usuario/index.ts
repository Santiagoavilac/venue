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
 *
 * Contratos del cliente: usuario en minúsculas (el cliente busca
 * .eq('usuario', usuario.toLowerCase())); clave mínimo 6; errores como
 * {error} con status != 2xx (el cliente muestra out.error tal cual).
 * TEXTOS de error SUPUESTOS (los reales del origen no son observables).
 * clubs del perfil: los del team; sin team o sin clubs => todos los
 * boliches activos que existan (consistente con que el admin los pise
 * justo después).
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

async function crearCuenta(usuario: string, nombre: string, clave: string, rol: string,
  team_id: string | null, creado_por: string | null) {
  usuario = usuario.trim().toLowerCase();
  if (!/^[a-z0-9._-]{3,30}$/.test(usuario)) return json({ error: "Usuario inválido (3-30, letras/números/._-)" }, 400);
  if (!nombre?.trim() || (clave ?? "").length < 6) return json({ error: "Completá nombre y clave (6+)" }, 400);

  const { data: dupe } = await admin.from("profiles").select("id").eq("usuario", usuario).maybeSingle();
  if (dupe) return json({ error: `El usuario @${usuario} ya existe` }, 409);

  let clubs: string[] = [];
  if (team_id) {
    const { data: team } = await admin.from("teams").select("clubs").eq("id", team_id).maybeSingle();
    if (!team) return json({ error: "Team inexistente" }, 400);
    clubs = team.clubs?.length ? team.clubs : [];
  }
  if (!clubs.length) {
    const { data: todosLosClubs } = await admin.from("clubs").select("id").eq("activo", true);
    clubs = (todosLosClubs ?? []).map((c: { id: string }) => c.id);
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
    .select("id, rol, team_id, activo").eq("id", data.user.id).maybeSingle();
  return perfil?.activo ? perfil : null;
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: CORS });
  if (req.method !== "POST") return json({ error: "Método no soportado" }, 405);
  let body: Record<string, string | null>;
  try { body = await req.json(); } catch { return json({ error: "JSON inválido" }, 400); }

  /* ---- autoregistro con invitación (sin sesión) ---- */
  if (body.action === "registro") {
    const invite = (body.invite ?? "").trim().toLowerCase();
    if (!invite) return json({ error: "Invitación inválida" }, 400);
    const { data: team } = await admin.from("teams")
      .select("id, nombre").eq("invite_code", invite).maybeSingle();
    if (!team) return json({ error: "Invitación inválida o vencida" }, 400);
    const r = await crearCuenta(body.usuario ?? "", body.nombre ?? "", body.clave ?? "", "rrpp", team.id, null);
    if (r instanceof Response) return r;
    return json({ team: team.nombre });
  }

  /* ---- lo demás exige sesión de admin o jefe ---- */
  const caller = await quienLlama(req);
  if (!caller || !["admin", "jefe"].includes(caller.rol)) return json({ error: "No autorizado" }, 403);

  if (body.action === "reset") {
    if ((body.clave ?? "").length < 6) return json({ error: "Clave mínimo 6 caracteres" }, 400);
    const { data: target } = await admin.from("profiles")
      .select("id, rol, team_id, admin_principal").eq("id", body.user_id).maybeSingle();
    if (!target) return json({ error: "Usuario no encontrado" }, 404);
    // la cuenta con admin_principal es máxima autoridad: nadie más la toca
    // (ni otro admin); solo su dueño puede cambiar su propia clave
    if (target.admin_principal && target.id !== caller.id)
      return json({ error: "Esta cuenta administrativa está protegida." }, 403);
    if (caller.rol === "jefe" && (target.rol !== "rrpp" || target.team_id !== caller.team_id))
      return json({ error: "Solo podés resetear claves de tu team" }, 403);
    const { error } = await admin.auth.admin.updateUserById(target.id, { password: body.clave! });
    if (error) return json({ error: error.message }, 400);
    return json({ ok: true });
  }

  /* alta directa */
  let rol = body.rol ?? "rrpp", team = body.team_id ?? null;
  if (caller.rol === "jefe") { rol = "rrpp"; team = caller.team_id; }   // el jefe solo crea rrpps de SU team
  const r = await crearCuenta(body.usuario ?? "", body.nombre ?? "", body.clave ?? "", rol, team, caller.id);
  if (r instanceof Response) return r;
  return json({ ok: true, usuario: r.usuario });
});
