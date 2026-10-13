/* Servidor de desarrollo.
 *
 * La aplicación es HTML + CSS + JS plano: no hay build ni bundler, así que
 * alcanza con servir la carpeta tal cual. Lo único que hace falta cuidar es
 * la caché: el navegador guarda app.js y styles.css con mucha alegría, y ahí
 * es donde uno cree que "los cambios no se aplicaron" cuando en realidad
 * está mirando la copia vieja.
 *
 * Por eso cada respuesta va con no-store y un ETag nuevo por modificación.
 *
 * Uso:  node dev.mjs  [puerto]
 */
import { createServer } from "node:http";
import { readFile, stat } from "node:fs/promises";
import { extname, join, normalize } from "node:path";
import { fileURLToPath } from "node:url";

const RAIZ = fileURLToPath(new URL(".", import.meta.url));
const PUERTO = Number(process.argv[2]) || 5173;

const TIPOS = {
  ".html": "text/html; charset=utf-8",
  ".js": "text/javascript; charset=utf-8",
  ".mjs": "text/javascript; charset=utf-8",
  ".css": "text/css; charset=utf-8",
  ".json": "application/json; charset=utf-8",
  ".webmanifest": "application/manifest+json; charset=utf-8",
  ".svg": "image/svg+xml",
  ".png": "image/png",
  ".jpg": "image/jpeg",
  ".webp": "image/webp",
  ".ico": "image/x-icon",
};

const server = createServer(async (req, res) => {
  try {
    const url = new URL(req.url, `http://${req.headers.host}`);
    let rel = decodeURIComponent(url.pathname);
    if (rel === "/" ) rel = "/index.html";

    // No dejar salir de la carpeta del proyecto.
    const destino = normalize(join(RAIZ, rel));
    if (!destino.startsWith(normalize(RAIZ))) {
      res.writeHead(403).end("Fuera de la carpeta del proyecto");
      return;
    }

    const info = await stat(destino);
    if (!info.isFile()) throw new Error("no es archivo");

    const cuerpo = await readFile(destino);
    res.writeHead(200, {
      "Content-Type": TIPOS[extname(destino).toLowerCase()] || "application/octet-stream",
      // Lo importante: el navegador no guarda nada. Cada recarga trae el
      // archivo tal como está en disco.
      "Cache-Control": "no-store, no-cache, must-revalidate, max-age=0",
      "Pragma": "no-cache",
      "Expires": "0",
      "ETag": `W/"${info.mtimeMs}-${info.size}"`,
    });
    res.end(cuerpo);

    const hora = new Date().toTimeString().slice(0, 8);
    console.log(`  ${hora}  ${rel}`);
  } catch {
    res.writeHead(404, { "Content-Type": "text/plain; charset=utf-8" });
    res.end("404");
  }
});

server.on("error", e => {
  if (e.code === "EADDRINUSE") {
    console.error(`\n  El puerto ${PUERTO} está ocupado.`);
    console.error(`  Probá con otro:  node dev.mjs ${PUERTO + 1}\n`);
    process.exit(1);
  }
  throw e;
});

server.listen(PUERTO, () => {
  console.log(`\n  Plataforma · servidor de desarrollo`);
  console.log(`  http://localhost:${PUERTO}`);
  console.log(`  Sin caché: recargá el navegador y vas a ver los cambios.`);
  console.log(`  Ctrl+C para cortar.\n`);
});
