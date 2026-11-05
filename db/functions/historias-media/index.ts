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
    // Firmar en lote. El cliente manda claves opacas, nunca rutas: el uid del
    // autor vive en la ruta y no tiene por qué salir de la base. La visibilidad
    // la decide la base con el token de quien pregunta -por eso se reenvía el
    // authorization tal cual, y si no hay, va la apikey anónima-; firmar lo
    // hace esta función con la llave de servicio, que es lo que le faltaba al
    // visitante sin cuenta para poder ver una historia.
    if (body.accion === 'firmar') {
      const claves = Array.isArray(body.claves) ? body.claves : [];
      const uuid = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
      const pedidas = [...new Set(claves.filter((c: unknown) => typeof c === 'string' && uuid.test(c)))];
      if (!pedidas.length) return respuesta({ urls: {} });
      if (pedidas.length > 60) return respuesta({ error: 'Demasiados archivos de una vez.' }, 400);
      const quien = req.headers.get('authorization') ?? `Bearer ${Deno.env.get('SUPABASE_ANON_KEY') ?? ''}`;
      const anon = Deno.env.get('SUPABASE_ANON_KEY') ?? key;
      const rutas = await fetch(`${url}/rest/v1/rpc/aftr_media_rutas`, {
        method: 'POST',
        headers: { apikey: anon, Authorization: quien, 'Content-Type': 'application/json' },
        body: JSON.stringify({ p_claves: pedidas }),
        signal: AbortSignal.timeout(10000),
      });
      if (!rutas.ok) return respuesta({ error: 'No se pudo resolver los archivos.' }, 400);
      const filas = await rutas.json() as { clave: string; bucket: string; ruta: string }[];
      const porBucket = new Map<string, { clave: string; ruta: string }[]>();
      for (const f of filas) {
        if (!f?.bucket || !f?.ruta) continue;
        if (!porBucket.has(f.bucket)) porBucket.set(f.bucket, []);
        porBucket.get(f.bucket)!.push(f);
      }
      const urls: Record<string, string> = {};
      const servicio = { apikey: key, Authorization: `Bearer ${key}`, 'Content-Type': 'application/json' };
      for (const [bucket, items] of porBucket) {
        // Una sola llamada por bucket: el endpoint de storage firma en lote.
        const r = await fetch(`${url}/storage/v1/object/sign/${bucket}`, {
          method: 'POST', headers: servicio,
          body: JSON.stringify({ expiresIn: 600, paths: items.map((i) => i.ruta) }),
          signal: AbortSignal.timeout(15000),
        });
        if (!r.ok) continue;
        const firmadas = await r.json() as { path: string; signedURL?: string; error?: string }[];
        for (const f of firmadas) {
          if (!f.signedURL) continue;
          const item = items.find((i) => i.ruta === f.path);
          if (item) urls[item.clave] = `${url}/storage/v1${f.signedURL}`;
        }
      }
      return respuesta({ urls, vence_en: 600 });
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
    // Validado el archivo, se lo saca de la carpeta del autor: la ruta
    // definitiva no tiene que decir de quién es, porque viaja dentro de la URL
    // firmada que ve cualquiera que pueda mirar la historia. La subida sigue
    // yendo a uid/… porque la política de storage se apoya en ese prefijo para
    // saber que el archivo es tuyo. Si el movimiento falla, se publica con la
    // ruta original: es peor no poder publicar que publicar con la ruta vieja.
    let donde = path;
    const destino = `h/${crypto.randomUUID()}.${path.split('.').pop()}`;
    const movido = await fetch(`${url}/storage/v1/object/move`, {
      method: 'POST',
      headers: { ...headers, 'Content-Type': 'application/json' },
      body: JSON.stringify({ bucketId: 'aftr-historias', sourceKey: path, destinationKey: destino }),
      signal: AbortSignal.timeout(15000),
    });
    if (movido.ok) {
      donde = destino;
      // storage_path es donde ESTA el archivo -la historia le apunta con una
      // clave foránea-, y ruta_subida recuerda de dónde vino, que es la única
      // ruta que conoce el cliente.
      const anotado = await fetch(`${url}/rest/v1/aftr_media_validada?storage_path=eq.${encodeURIComponent(path)}`, {
        method: 'PATCH',
        headers: { ...headers, 'Content-Type': 'application/json' },
        body: JSON.stringify({ storage_path: destino, ruta_subida: path }),
        signal: AbortSignal.timeout(10000),
      });
      // si no se pudo anotar, se vuelve el archivo a su lugar: una validación
      // que apunta a donde el archivo no está no deja publicar nunca
      if (!anotado.ok) {
        await fetch(`${url}/storage/v1/object/move`, {
          method: 'POST', headers: { ...headers, 'Content-Type': 'application/json' },
          body: JSON.stringify({ bucketId: 'aftr-historias', sourceKey: destino, destinationKey: path }),
          signal: AbortSignal.timeout(15000),
        }).catch(() => {});
        donde = path;
      }
    }
    return respuesta({ path, ruta: donde, ...validacion, size: total, valido: true });
  } catch (error) {
    return respuesta({ error: error instanceof Error ? error.message : 'No se pudo verificar el archivo.' }, 400);
  }
});
