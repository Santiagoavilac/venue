/* El QR de la entrada, como PNG, sin depender de nadie.
 *
 * Por qué acá y no una librería: el correo lo abre Gmail, Outlook y el cliente
 * del iPhone, y ninguno dibuja SVG. Hace falta PNG. Las librerías que generan
 * PNG en Deno traen compatibilidad de Node y pesan; esto son dos piezas
 * chicas y previsibles -el código QR y el PNG- y no se puede romper solo
 * porque un CDN cambie.
 *
 * El QR es versión 4-L con máscara 0, que entra hasta 78 caracteres
 * alfanuméricos: los códigos de entrada son mucho más cortos.
 */

// ── Galois field de 256, para la corrección de errores ────────────────
const EXP = new Uint8Array(512), LOG = new Uint8Array(256);
for (let i = 0, x = 1; i < 255; i++) {
  EXP[i] = x; LOG[x] = i;
  x <<= 1; if (x & 0x100) x ^= 0x11d;
}
for (let i = 255; i < 512; i++) EXP[i] = EXP[i - 255];
const mul = (a: number, b: number) => (a === 0 || b === 0) ? 0 : EXP[LOG[a] + LOG[b]];

function polinomioGenerador(grado: number) {
  let p = new Uint8Array([1]);
  for (let i = 0; i < grado; i++) {
    const n = new Uint8Array(p.length + 1);
    for (let j = 0; j < p.length; j++) {
      n[j] ^= p[j];
      n[j + 1] ^= mul(p[j], EXP[i]);
    }
    p = n;
  }
  return p;
}

function correccion(datos: Uint8Array, cuantos: number) {
  const gen = polinomioGenerador(cuantos);
  const r = new Uint8Array(cuantos);
  for (const b of datos) {
    const factor = b ^ r[0];
    r.copyWithin(0, 1); r[r.length - 1] = 0;
    if (factor !== 0) for (let i = 0; i < gen.length - 1; i++) r[i] ^= mul(gen[i + 1], factor);
  }
  return r;
}

// ── el código QR ──────────────────────────────────────────────────────
const VERSION = 4, LADO = 33, DATOS = 64, ECC = 20; // 4-L: 64 bytes de datos, 20 de corrección

function bits(texto: string) {
  const bytes = new TextEncoder().encode(texto);
  if (bytes.length > DATOS - 3) throw new Error("El código no entra en el QR.");
  const out: number[] = [];
  const poner = (v: number, n: number) => { for (let i = n - 1; i >= 0; i--) out.push((v >> i) & 1); };
  poner(0b0100, 4);            // modo byte
  poner(bytes.length, 8);      // longitud (versiones 1 a 9)
  for (const b of bytes) poner(b, 8);
  poner(0, Math.min(4, DATOS * 8 - out.length));
  while (out.length % 8) out.push(0);
  const datos = new Uint8Array(DATOS);
  for (let i = 0; i < out.length; i += 8) {
    datos[i / 8] = out.slice(i, i + 8).reduce((a, b) => (a << 1) | b, 0);
  }
  // relleno alterno, como manda la norma
  for (let i = out.length / 8, alterna = true; i < DATOS; i++, alterna = !alterna) {
    datos[i] = alterna ? 0xec : 0x11;
  }
  const ecc = correccion(datos, ECC);
  const todo = new Uint8Array(DATOS + ECC);
  todo.set(datos); todo.set(ecc, DATOS);
  return todo;
}

function patrones(m: (number | null)[][]) {
  const fijo = (fx: number, fy: number) => {
    for (let y = -1; y <= 7; y++) for (let x = -1; x <= 7; x++) {
      const px = fx + x, py = fy + y;
      if (px < 0 || py < 0 || px >= LADO || py >= LADO) continue;
      const borde = x === -1 || y === -1 || x === 7 || y === 7;
      const anillo = (x >= 0 && x <= 6 && (y === 0 || y === 6)) || (y >= 0 && y <= 6 && (x === 0 || x === 6));
      const centro = x >= 2 && x <= 4 && y >= 2 && y <= 4;
      m[py][px] = borde ? 0 : (anillo || centro) ? 1 : 0;
    }
  };
  fijo(0, 0); fijo(LADO - 7, 0); fijo(0, LADO - 7);
  // patrón de alineación de la versión 4, en (26, 26)
  for (let y = -2; y <= 2; y++) for (let x = -2; x <= 2; x++) {
    m[26 + y][26 + x] = (Math.max(Math.abs(x), Math.abs(y)) !== 1) ? 1 : 0;
  }
  for (let i = 8; i < LADO - 8; i++) {
    m[6][i] = m[i][6] = i % 2 === 0 ? 1 : 0;
  }
  m[LADO - 8][8] = 1; // el módulo que siempre va oscuro
}

function formato(m: (number | null)[][]) {
  // nivel L (01) con máscara 0 → 0b01000, ya calculado con su BCH y su máscara
  const f = 0b111011111000100;
  for (let i = 0; i < 15; i++) {
    const b = (f >> i) & 1;
    if (i < 6) m[i][8] = b;
    else if (i < 8) m[i + 1][8] = b;
    else if (i === 8) m[8][7] = b;
    else m[8][14 - i] = b;
    if (i < 8) m[8][LADO - 1 - i] = b;
    else m[LADO - 15 + i][8] = b;
  }
}

/** La matriz de módulos del código, true = oscuro. */
export function modulos(texto: string): boolean[][] {
  const m: (number | null)[][] = Array.from({ length: LADO }, () => Array(LADO).fill(null));
  patrones(m);
  formato(m);
  const todo = bits(texto);
  let bit = 0;
  for (let col = LADO - 1; col > 0; col -= 2) {
    if (col === 6) col--; // la columna de sincronismo no lleva datos
    for (let i = 0; i < LADO; i++) {
      const arriba = ((LADO - 1 - col) >> 1) % 2 === 0;
      const fila = arriba ? LADO - 1 - i : i;
      for (const c of [col, col - 1]) {
        if (m[fila][c] !== null) continue;
        const b = bit < todo.length * 8 ? (todo[bit >> 3] >> (7 - (bit & 7))) & 1 : 0;
        bit++;
        // máscara 0: (fila + columna) par
        m[fila][c] = b ^ (((fila + c) % 2 === 0) ? 1 : 0);
      }
    }
  }
  return m.map((f) => f.map((v) => v === 1));
}

// ── el PNG ────────────────────────────────────────────────────────────
function crc32(b: Uint8Array) {
  let c = ~0;
  for (const x of b) {
    c ^= x;
    for (let k = 0; k < 8; k++) c = (c >>> 1) ^ (0xedb88320 & -(c & 1));
  }
  return ~c >>> 0;
}

function trozo(tipo: string, datos: Uint8Array) {
  const nombre = new TextEncoder().encode(tipo);
  const cuerpo = new Uint8Array(nombre.length + datos.length);
  cuerpo.set(nombre); cuerpo.set(datos, nombre.length);
  const out = new Uint8Array(8 + cuerpo.length + 4);
  const v = new DataView(out.buffer);
  v.setUint32(0, datos.length);
  out.set(cuerpo, 4);
  v.setUint32(4 + cuerpo.length, crc32(cuerpo));
  return out;
}

/** El QR del código como PNG en blanco y negro, listo para `<img src>`. */
export async function qrPng(texto: string, escala = 8, margen = 4) {
  const m = modulos(texto);
  const lado = (m.length + margen * 2) * escala;
  // una fila por píxel: el byte de filtro (0) y después un byte por píxel
  const crudo = new Uint8Array((lado + 1) * lado);
  for (let y = 0; y < lado; y++) {
    const fila = (lado + 1) * y;
    crudo[fila] = 0;
    for (let x = 0; x < lado; x++) {
      const mx = Math.floor(x / escala) - margen, my = Math.floor(y / escala) - margen;
      const oscuro = my >= 0 && my < m.length && mx >= 0 && mx < m.length && m[my][mx];
      crudo[fila + 1 + x] = oscuro ? 0 : 255;
    }
  }
  const comprimido = new Uint8Array(await new Response(
    new Blob([crudo.slice().buffer]).stream().pipeThrough(new CompressionStream("deflate")),
  ).arrayBuffer());

  const ihdr = new Uint8Array(13);
  const v = new DataView(ihdr.buffer);
  v.setUint32(0, lado); v.setUint32(4, lado);
  ihdr[8] = 8;   // 8 bits por muestra
  ihdr[9] = 0;   // escala de grises
  const partes = [
    new Uint8Array([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]),
    trozo("IHDR", ihdr),
    trozo("IDAT", comprimido),
    trozo("IEND", new Uint8Array(0)),
  ];
  const total = partes.reduce((n, p) => n + p.length, 0);
  const png = new Uint8Array(total);
  let i = 0;
  for (const p of partes) { png.set(p, i); i += p.length; }
  return png;
}

export const base64 = (b: Uint8Array) => {
  let s = "";
  for (const x of b) s += String.fromCharCode(x);
  return btoa(s);
};
