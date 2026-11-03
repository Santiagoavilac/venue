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
Deno.serve(crearHandler(admin, new Banco(env), env));
