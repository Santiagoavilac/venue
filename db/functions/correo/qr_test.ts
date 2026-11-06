import { qrPng, modulos } from "./qr.ts";

/* Que el PNG sea un PNG de verdad.
 *
 * Qué se rompía: el escritor de trozos reservaba cuatro bytes de más en cada
 * uno. El archivo arrancaba bien -la firma y el IHDR eran correctos, y por eso
 * `file` decía "PNG 328x328"- pero esos cuatro ceros empujaban al trozo
 * siguiente y el resto quedaba corrido. Ningún lector podía abrirlo, y en el
 * correo salía el cuadrito roto. Se me escapó porque la primera prueba
 * decodificaba la matriz del QR, no el PNG.
 */
const igual = (a: unknown, b: unknown, que: string) => {
  if (a !== b) throw new Error(`${que}: ${a} !== ${b}`);
};

function trozos(png: Uint8Array) {
  const v = new DataView(png.buffer, png.byteOffset, png.byteLength);
  const out: { tipo: string; largo: number; crcOk: boolean }[] = [];
  let i = 8;
  while (i < png.length) {
    const largo = v.getUint32(i);
    const tipo = new TextDecoder().decode(png.subarray(i + 4, i + 8));
    const crc = v.getUint32(i + 8 + largo);
    out.push({ tipo, largo, crcOk: crc === crc32(png.subarray(i + 4, i + 8 + largo)) });
    i += 12 + largo;
    if (tipo === "IEND") break;
  }
  if (i !== png.length) throw new Error(`sobran ${png.length - i} bytes después del IEND`);
  return out;
}

function crc32(b: Uint8Array) {
  let c = ~0;
  for (const x of b) { c ^= x; for (let k = 0; k < 8; k++) c = (c >>> 1) ^ (0xedb88320 & -(c & 1)); }
  return ~c >>> 0;
}

Deno.test("el PNG del QR es un PNG válido, trozo por trozo", async () => {
  const png = await qrPng("AFTR-PRUEBA-01");
  igual(png[0], 0x89, "firma"); igual(png[1], 0x50, "firma");
  const t = trozos(png);
  igual(t.map((x) => x.tipo).join(","), "IHDR,IDAT,IEND", "los trozos y su orden");
  for (const x of t) igual(x.crcOk, true, `crc de ${x.tipo}`);
  igual(t[0].largo, 13, "largo del IHDR");
});

Deno.test("el IDAT descomprime exactamente los píxeles que dice el IHDR", async () => {
  const png = await qrPng("AFTR-PRUEBA-01");
  const v = new DataView(png.buffer, png.byteOffset, png.byteLength);
  const ancho = v.getUint32(16), alto = v.getUint32(20);
  const largoIdat = v.getUint32(33);
  const idat = png.subarray(41, 41 + largoIdat);
  const crudo = new Uint8Array(await new Response(
    new Blob([idat.slice().buffer]).stream().pipeThrough(new DecompressionStream("deflate")),
  ).arrayBuffer());
  // una fila por píxel, más el byte de filtro de cada una
  igual(crudo.length, (ancho + 1) * alto, "píxeles descomprimidos");
});

Deno.test("el QR dice lo que tiene que decir", () => {
  const m = modulos("AFTR-PRUEBA-01");
  igual(m.length, 33, "lado");
  // los tres ojos: la fila de arriba de cada uno va entera oscura
  for (const [x, y] of [[0, 0], [26, 0], [0, 26]]) {
    for (let i = 0; i < 7; i++) igual(m[y][x + i], true, `ojo en ${x},${y}`);
  }
});
