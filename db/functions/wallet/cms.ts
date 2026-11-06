/* La firma PKCS#7 que pide Apple Wallet.
 *
 * Un `.pkpass` es un zip cuyo `manifest.json` va firmado aparte, en formato
 * CMS/PKCS#7 "detached". WebCrypto sabe firmar pero no sabe armar ese sobre,
 * y las librerías que lo hacen traen un ASN.1 entero. Acá se arma a mano: la
 * estructura es fija y lo único que cambia son el certificado y el hash.
 *
 * Se verifica con `openssl smime -verify`, que es el mismo que usa Apple del
 * otro lado, así que si openssl la acepta, el pase instala.
 */

// ── ASN.1 DER, lo mínimo ──────────────────────────────────────────────
const unir = (...bs: Uint8Array[]) => {
  const out = new Uint8Array(bs.reduce((n, b) => n + b.length, 0));
  let i = 0;
  for (const b of bs) { out.set(b, i); i += b.length; }
  return out;
};

/** El largo en DER: corto hasta 127, largo con el conteo de bytes arriba. */
function largo(n: number) {
  if (n < 0x80) return new Uint8Array([n]);
  const bytes: number[] = [];
  for (let v = n; v > 0; v = Math.floor(v / 256)) bytes.unshift(v % 256);
  return new Uint8Array([0x80 | bytes.length, ...bytes]);
}

const tlv = (etiqueta: number, cuerpo: Uint8Array) =>
  unir(new Uint8Array([etiqueta]), largo(cuerpo.length), cuerpo);

const secuencia = (...partes: Uint8Array[]) => tlv(0x30, unir(...partes));
const conjunto = (...partes: Uint8Array[]) => tlv(0x31, unir(...partes));
const octetos = (b: Uint8Array) => tlv(0x04, b);
const entero = (n: number) => tlv(0x02, new Uint8Array([n]));
const nulo = () => new Uint8Array([0x05, 0x00]);
const contexto = (n: number, cuerpo: Uint8Array) => tlv(0xa0 | n, cuerpo);

/** Un OID como "1.2.840.113549.1.7.2" en DER. */
function oid(texto: string) {
  const p = texto.split(".").map(Number);
  const bytes = [p[0] * 40 + p[1]];
  for (const v of p.slice(2)) {
    const chunk: number[] = [];
    let n = v;
    do { chunk.unshift(n % 128); n = Math.floor(n / 128); } while (n > 0);
    for (let i = 0; i < chunk.length - 1; i++) chunk[i] |= 0x80;
    bytes.push(...chunk);
  }
  return tlv(0x06, new Uint8Array(bytes));
}

const OID = {
  datos: "1.2.840.113549.1.7.1",
  firmado: "1.2.840.113549.1.7.2",
  sha256: "2.16.840.1.101.3.4.2.1",
  rsa: "1.2.840.113549.1.1.1",
  tipoContenido: "1.2.840.113549.1.9.3",
  resumen: "1.2.840.113549.1.9.4",
  cuando: "1.2.840.113549.1.9.5",
};

/** La hora, como la pide CMS (UTCTime, aaMMddHHmmssZ). */
function cuando(fecha = new Date()) {
  const d = (n: number) => String(n).padStart(2, "0");
  const s = `${d(fecha.getUTCFullYear() % 100)}${d(fecha.getUTCMonth() + 1)}${d(fecha.getUTCDate())}` +
    `${d(fecha.getUTCHours())}${d(fecha.getUTCMinutes())}${d(fecha.getUTCSeconds())}Z`;
  return tlv(0x17, new TextEncoder().encode(s));
}

// ── PEM ───────────────────────────────────────────────────────────────
export function dePem(pem: string, tipo: string) {
  const re = new RegExp(`-----BEGIN ${tipo}-----([\\s\\S]*?)-----END ${tipo}-----`, "g");
  const out: Uint8Array[] = [];
  for (const m of pem.matchAll(re)) {
    const b = atob(m[1].replace(/\s+/g, ""));
    out.push(Uint8Array.from(b, (c) => c.charCodeAt(0)));
  }
  return out;
}

/** El emisor y el número de serie del certificado, que es como CMS lo nombra. */
function emisorYSerie(cert: Uint8Array) {
  // Certificate ::= SEQUENCE { tbsCertificate SEQUENCE { [0] version,
  //   serialNumber INTEGER, signature AlgorithmIdentifier, issuer Name, ... } }
  const leer = (i: number) => {
    const etiqueta = cert[i];
    let j = i + 1;
    let n = cert[j++];
    if (n & 0x80) {
      const cuantos = n & 0x7f;
      n = 0;
      for (let k = 0; k < cuantos; k++) n = n * 256 + cert[j++];
    }
    return { etiqueta, inicio: i, cuerpo: j, fin: j + n };
  };
  const todo = leer(0);
  const tbs = leer(todo.cuerpo);
  let i = tbs.cuerpo;
  let x = leer(i);
  if (x.etiqueta === 0xa0) { i = x.fin; x = leer(i); } // la versión es opcional
  const serie = cert.subarray(x.inicio, x.fin);        // serialNumber
  i = x.fin;
  const alg = leer(i); i = alg.fin;                    // signature
  const emisor = leer(i);                              // issuer
  return { serie, emisor: cert.subarray(emisor.inicio, emisor.fin) };
}

/**
 * Firma `datos` en CMS detached, como pide Apple Wallet.
 *
 * `cadena` son el certificado del pase y el intermedio de Apple (WWDR), en
 * ese orden. Sin el intermedio el pase no instala: el teléfono no puede
 * encadenar hasta la raíz de Apple.
 */
export async function firmarCms(
  datos: Uint8Array,
  certs: Uint8Array[],
  llave: CryptoKey,
): Promise<Uint8Array> {
  const resumen = new Uint8Array(await crypto.subtle.digest("SHA-256", datos.slice().buffer));

  // Los atributos firmados: es lo que se firma de verdad, no los datos.
  const atributos = [
    secuencia(oid(OID.tipoContenido), conjunto(oid(OID.datos))),
    secuencia(oid(OID.cuando), conjunto(cuando())),
    secuencia(oid(OID.resumen), conjunto(octetos(resumen))),
  ];
  // Para firmar van como SET (0x31); dentro del sobre, como [0] implícito.
  const paraFirmar = conjunto(...atributos);
  const firma = new Uint8Array(await crypto.subtle.sign(
    { name: "RSASSA-PKCS1-v1_5" }, llave, paraFirmar.slice().buffer));

  const { serie, emisor } = emisorYSerie(certs[0]);
  const signerInfo = secuencia(
    entero(1),
    secuencia(emisor, serie),
    secuencia(oid(OID.sha256), nulo()),
    contexto(0, unir(...atributos)),
    secuencia(oid(OID.rsa), nulo()),
    octetos(firma),
  );

  const signedData = secuencia(
    entero(1),
    conjunto(secuencia(oid(OID.sha256), nulo())),
    secuencia(oid(OID.datos)), // detached: sin el contenido adentro
    contexto(0, unir(...certs.map((c) => c))),
    conjunto(signerInfo),
  );

  return secuencia(oid(OID.firmado), contexto(0, signedData));
}

/** La llave privada del `.p12`, ya en PEM, lista para WebCrypto. */
export async function llaveDePem(pem: string) {
  const [der] = dePem(pem, "PRIVATE KEY");
  if (!der) throw new Error("No encuentro la llave privada en el PEM.");
  return await crypto.subtle.importKey(
    "pkcs8", der.slice().buffer, { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" }, false, ["sign"]);
}
