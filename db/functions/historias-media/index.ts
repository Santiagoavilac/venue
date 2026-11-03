import { validarMedio } from './media.ts';
const cors = { 'Access-Control-Allow-Origin': '*', 'Access-Control-Allow-Headers': 'authorization, apikey, content-type, x-client-info', 'Access-Control-Allow-Methods': 'POST, OPTIONS' };
const respuesta = (data: unknown, status = 200) => new Response(JSON.stringify(data), { status, headers: { ...cors, 'Content-Type': 'application/json' } });
Deno.serve(async req => {
  if (req.method === 'OPTIONS') return new Response(null, { headers: cors });
  if (req.method !== 'POST') return respuesta({ error: 'Método no permitido.' }, 405);
  try {
    const url = Deno.env.get('SUPABASE_URL')!, key = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;
    const body = await req.json();
    if (body.accion === 'limpiar' || body.accion === 'verificar_limpieza') {
      const token = Deno.env.get('BANECO_CRON_TOKEN');
      if (!token || token.length < 32 || req.headers.get('x-social-cron') !== token) return respuesta({ error: 'No autorizado.' }, 401);
      const headers = { apikey: key, Authorization: `Bearer ${key}`, 'Content-Type': 'application/json' };
      const candidatos = await fetch(`${url}/rest/v1/rpc/aftr_social_limpieza`, { method: 'POST', headers, body: '{}', signal: AbortSignal.timeout(10000) });
      if (!candidatos.ok) throw new Error('No se pudo consultar la limpieza.');
      const archivos = await candidatos.json() as { name: string }[];
      if (body.accion === 'verificar_limpieza') {
        return respuesta({ candidatos: archivos.length, dry_run: true });
      }
      if (archivos.length) {
        const borrado = await fetch(`${url}/storage/v1/object/aftr-historias`, { method: 'DELETE', headers, body: JSON.stringify({ prefixes: archivos.map(x => x.name) }), signal: AbortSignal.timeout(20000) });
        if (!borrado.ok) throw new Error('La limpieza se reintentará en la próxima ejecución.');
      }
      return respuesta({ borrados: archivos.length });
    }
    const bearer = req.headers.get('authorization');
    if (!bearer) return respuesta({ error: 'Iniciá sesión.' }, 401);
    const userResponse = await fetch(`${url}/auth/v1/user`, { headers: { apikey: key, Authorization: bearer }, signal: AbortSignal.timeout(10000) });
    if (!userResponse.ok) return respuesta({ error: 'Tu sesión venció.' }, 401);
    const user = await userResponse.json();
    const { path } = body;
    if (typeof path !== 'string' || !path.startsWith(`${user.id}/`) || !/^[a-f0-9-]{36}\/[a-f0-9-]{36}\.(jpg|jpeg|png|webp|mp4|mov)$/.test(path)) return respuesta({ error: 'El archivo no pertenece a tu cuenta.' }, 403);
    const headers = { apikey: key, Authorization: `Bearer ${key}` };
    const media = await fetch(`${url}/storage/v1/object/authenticated/aftr-historias/${path}`, { headers, signal: AbortSignal.timeout(20000) });
    if (!media.ok || !media.body) return respuesta({ error: 'Primero subí el archivo.' }, 400);
    const reader = media.body.getReader(), partes: Uint8Array[] = []; let total = 0;
    for (;;) {
      const { done, value } = await reader.read(); if (done) break;
      total += value.byteLength;
      if (total > 30 * 1024 * 1024) { await reader.cancel(); throw new Error('El archivo supera 30 MB.'); }
      partes.push(value);
    }
    const bytes = new Uint8Array(total); let offset = 0;
    for (const parte of partes) { bytes.set(parte, offset); offset += parte.length; }
    const validacion = validarMedio(bytes);
    const sha256 = [...new Uint8Array(await crypto.subtle.digest('SHA-256', bytes))].map(x => x.toString(16).padStart(2, '0')).join('');
    const registro = await fetch(`${url}/rest/v1/aftr_media_validada?on_conflict=storage_path`, { method: 'POST', headers: { ...headers, 'Content-Type': 'application/json', Prefer: 'resolution=ignore-duplicates' }, body: JSON.stringify({ storage_path: path, autor_id: user.id, tipo: validacion.tipo, duracion_ms: validacion.duracion_ms, size_bytes: total, sha256 }), signal: AbortSignal.timeout(10000) });
    if (!registro.ok) throw new Error('No se pudo registrar la validación. Reintentá.');
    return respuesta({ path, ...validacion, size: total, valido: true });
  } catch (error) {
    return respuesta({ error: error instanceof Error ? error.message : 'No se pudo verificar el archivo.' }, 400);
  }
});
