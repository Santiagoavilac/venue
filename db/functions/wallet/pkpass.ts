/* La entrada en Apple Wallet.
 *
 * Un `.pkpass` es un zip con: `pass.json` (lo que se ve), las imágenes, un
 * `manifest.json` con el SHA-1 de cada archivo, y `signature`, que es la firma
 * CMS del manifiesto. Si falta uno, o si un hash no da, el teléfono lo
 * rechaza sin decir por qué.
 *
 * Lo que hace que el pase avise solo, sin ninguna notificación:
 *
 *   relevantDate  la hora del evento. iOS lo muestra en la pantalla bloqueada
 *                 un rato antes.
 *   locations     dónde queda el boliche. Al llegar cerca, el pase aparece
 *                 solo en la pantalla bloqueada.
 *
 * Las dos vienen en el pase: no hace falta servidor ni push para eso.
 */
import { firmarCms } from "./cms.ts";

// ── SHA-1, que es el que pide el manifiesto ───────────────────────────
async function sha1(b: Uint8Array) {
  const h = new Uint8Array(await crypto.subtle.digest("SHA-1", b.slice().buffer));
  return [...h].map((x) => x.toString(16).padStart(2, "0")).join("");
}

// ── zip, guardando sin comprimir ──────────────────────────────────────
// Sin comprimir a propósito: un pase pesa unos pocos kilobytes y así el zip
// es un formato de diez líneas en vez de uno de cien.
function crc32(b: Uint8Array) {
  let c = ~0;
  for (const x of b) { c ^= x; for (let k = 0; k < 8; k++) c = (c >>> 1) ^ (0xedb88320 & -(c & 1)); }
  return ~c >>> 0;
}

const unir = (...bs: Uint8Array[]) => {
  const out = new Uint8Array(bs.reduce((n, b) => n + b.length, 0));
  let i = 0;
  for (const b of bs) { out.set(b, i); i += b.length; }
  return out;
};

function zip(archivos: { nombre: string; datos: Uint8Array }[]) {
  const partes: Uint8Array[] = [];
  const central: Uint8Array[] = [];
  let posicion = 0;
  for (const a of archivos) {
    const nombre = new TextEncoder().encode(a.nombre);
    const crc = crc32(a.datos);
    const cabecera = new Uint8Array(30 + nombre.length);
    const v = new DataView(cabecera.buffer);
    v.setUint32(0, 0x04034b50, true);
    v.setUint16(4, 20, true);        // versión mínima
    v.setUint16(8, 0, true);         // sin compresión
    v.setUint32(14, crc, true);
    v.setUint32(18, a.datos.length, true);
    v.setUint32(22, a.datos.length, true);
    v.setUint16(26, nombre.length, true);
    cabecera.set(nombre, 30);

    const entrada = new Uint8Array(46 + nombre.length);
    const w = new DataView(entrada.buffer);
    w.setUint32(0, 0x02014b50, true);
    w.setUint16(4, 20, true);
    w.setUint16(6, 20, true);
    w.setUint16(10, 0, true);
    w.setUint32(16, crc, true);
    w.setUint32(20, a.datos.length, true);
    w.setUint32(24, a.datos.length, true);
    w.setUint16(28, nombre.length, true);
    w.setUint32(42, posicion, true);
    entrada.set(nombre, 46);

    partes.push(cabecera, a.datos);
    central.push(entrada);
    posicion += cabecera.length + a.datos.length;
  }
  const dir = unir(...central);
  const fin = new Uint8Array(22);
  const f = new DataView(fin.buffer);
  f.setUint32(0, 0x06054b50, true);
  f.setUint16(8, archivos.length, true);
  f.setUint16(10, archivos.length, true);
  f.setUint32(12, dir.length, true);
  f.setUint32(16, posicion, true);
  return unir(...partes, dir, fin);
}

// ── el pase ───────────────────────────────────────────────────────────
export type Entrada = {
  codigo: string;          // lo que lee la puerta
  serie: string;           // único por pase
  evento: string;
  club: string;
  persona: string;
  /** Cuándo empieza, en ISO con zona. Es lo que hace que aparezca solo. */
  inicio: string;
  /** Dónde queda el boliche, para que aparezca al llegar. */
  lugar?: { lat: number; lng: number } | null;
  nota?: string;
};

export type Credenciales = {
  passTypeIdentifier: string;
  teamIdentifier: string;
  certs: Uint8Array[];     // el del pase primero, el intermedio de Apple después
  llave: CryptoKey;
  /** Las imágenes del pase: icon.png es obligatoria, logo.png casi. */
  imagenes: Record<string, Uint8Array>;
};

export function passJson(e: Entrada, c: Credenciales) {
  const pase: Record<string, unknown> = {
    formatVersion: 1,
    passTypeIdentifier: c.passTypeIdentifier,
    teamIdentifier: c.teamIdentifier,
    serialNumber: e.serie,
    organizationName: "AFTR",
    description: `Entrada · ${e.evento}`,
    logoText: "AFTR",
    foregroundColor: "rgb(244,244,245)",
    backgroundColor: "rgb(11,11,13)",
    labelColor: "rgb(232,194,106)",
    // el QR dice exactamente lo mismo que el de la app y el del correo
    barcodes: [{
      format: "PKBarcodeFormatQR",
      message: e.codigo,
      messageEncoding: "iso-8859-1",
      altText: e.persona,
    }],
    // la hora del evento: iOS lo saca solo en la pantalla bloqueada
    relevantDate: e.inicio,
    eventTicket: {
      primaryFields: [{ key: "evento", label: "EVENTO", value: e.evento }],
      secondaryFields: [
        { key: "lugar", label: "DÓNDE", value: e.club },
        {
          key: "cuando", label: "CUÁNDO", value: e.inicio,
          dateStyle: "PKDateStyleMedium", timeStyle: "PKDateStyleShort",
        },
      ],
      auxiliaryFields: [{ key: "persona", label: "A NOMBRE DE", value: e.persona }],
      backFields: [
        { key: "aviso", label: "En la puerta", value: "Mostrá este QR. Entra una sola vez." },
        ...(e.nota ? [{ key: "nota", label: "Nota", value: e.nota }] : []),
      ],
    },
  };
  // y dónde queda: al llegar cerca, el pase aparece solo
  if (e.lugar && Number.isFinite(e.lugar.lat) && Number.isFinite(e.lugar.lng)) {
    pase.locations = [{
      latitude: e.lugar.lat,
      longitude: e.lugar.lng,
      relevantText: `${e.evento} · mostrá tu entrada`,
    }];
    pase.maxDistance = 500;
  }
  return pase;
}

/** El `.pkpass` entero, firmado y listo para mandar. */
export async function armarPase(e: Entrada, c: Credenciales) {
  const enc = new TextEncoder();
  const archivos: { nombre: string; datos: Uint8Array }[] = [
    { nombre: "pass.json", datos: enc.encode(JSON.stringify(passJson(e, c))) },
  ];
  for (const [nombre, datos] of Object.entries(c.imagenes)) {
    archivos.push({ nombre, datos });
  }
  if (!archivos.some((a) => a.nombre === "icon.png")) {
    throw new Error("El pase necesita icon.png.");
  }

  const manifiesto: Record<string, string> = {};
  for (const a of archivos) manifiesto[a.nombre] = await sha1(a.datos);
  const manifestoBytes = enc.encode(JSON.stringify(manifiesto));

  const firma = await firmarCms(manifestoBytes, c.certs, c.llave);
  archivos.push({ nombre: "manifest.json", datos: manifestoBytes });
  archivos.push({ nombre: "signature", datos: firma });
  return zip(archivos);
}
