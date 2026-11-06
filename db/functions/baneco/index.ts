/* Cobro con QR bancario · Banco Económico (API Market v1.3.0).
 * La lógica existente se separa para probarla sin banco ni Supabase reales.
 */
import { createClient } from "@supabase/supabase-js";
import { Banco } from "./bank.ts";
import { crearHandler } from "./handler.ts";

const env = (nombre: string) => Deno.env.get(nombre);
const admin = createClient(env("SUPABASE_URL")!, env("SUPABASE_SERVICE_ROLE_KEY")!, {
  auth: { persistSession: false },
});

/* Las credenciales de cada boliche viven en los secretos, con el nombre de su
 * pasarela como prefijo: BANECO_SITROOM_USER, BANECO_SITROOM_ACCOUNT, etc. Lo
 * que ese boliche no defina se toma del BANECO_ de siempre, que es el de la
 * plataforma. Así ningún número de cuenta ni ninguna llave entra en la base.
 *
 * El nombre se vuelve a validar acá aunque la base ya lo valide: termina
 * armando el nombre de una variable de entorno y esto es lo último que lo
 * mira. Sin cuenta propia, cobra la plataforma; lo que no puede pasar es que
 * un nombre raro haga leer un secreto que no es.
 */
const pasarelas = new Map<string, Banco>();
function bancoDe(pasarela: string) {
  const nombre = /^[a-z0-9_]{1,24}$/.test(pasarela) ? pasarela : "";
  let banco = pasarelas.get(nombre);
  if (!banco) {
    const prefijo = nombre ? `BANECO_${nombre.toUpperCase()}_` : "BANECO_";
    banco = new Banco((clave) =>
      (clave.startsWith("BANECO_")
        ? env(prefijo + clave.slice("BANECO_".length)) ?? env(clave)
        : env(clave)));
    pasarelas.set(nombre, banco);
  }
  return banco;
}

Deno.serve(crearHandler(admin, bancoDe, env));
