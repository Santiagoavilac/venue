/* La entrada en PDF, para descargar o imprimir.
 *
 * Se escribe el PDF a mano por la misma razón que el QR: las librerías que
 * arman PDF en Deno arrastran compatibilidad de Node y pesan más que todo
 * esto junto. Acá sólo hacen falta cuatro cosas -una imagen JPEG de fondo, un
 * velo oscuro, texto con una tipografía de las que todo lector ya trae, y el
 * QR- y las cuatro son unas pocas líneas.
 *
 * El arte del evento entra tal cual, sin decodificar: PDF sabe leer JPEG
 * (DCTDecode). Por eso el fondo tiene que ser JPEG; si no lo es, o si no se
 * puede bajar, la entrada sale igual con fondo negro.
 */
import { modulos } from "./qr.ts";

const enc = new TextEncoder();

/** WinAnsi: lo que entienden Helvetica y compañía sin incrustar nada. */
function winansi(s: string) {
  const extra: Record<string, number> = {
    "€": 128, "‘": 145, "’": 146, "“": 147, "”": 148,
    "•": 149, "–": 150, "—": 151, "·": 183,
  };
  const out: number[] = [];
  for (const ch of s) {
    const c = ch.codePointAt(0)!;
    if (c < 256) out.push(c);
    else if (extra[ch] !== undefined) out.push(extra[ch]);
    else out.push(63); // '?'
  }
  return out;
}

const textoPdf = (s: string) =>
  "(" + winansi(s).map((b) =>
    b === 40 || b === 41 || b === 92 ? "\\" + String.fromCharCode(b)
      : b < 32 || b > 126 ? "\\" + b.toString(8).padStart(3, "0")
        : String.fromCharCode(b)).join("") + ")";

async function desinflar(b: Uint8Array) {
  return new Uint8Array(await new Response(
    new Blob([b.slice().buffer]).stream().pipeThrough(new CompressionStream("deflate")),
  ).arrayBuffer());
}

/** Ancho y alto de un JPEG, leídos de su marcador SOF. */
function medidaJpeg(b: Uint8Array) {
  if (b[0] !== 0xff || b[1] !== 0xd8) return null;
  let i = 2;
  while (i < b.length - 9) {
    if (b[i] !== 0xff) { i++; continue; }
    const m = b[i + 1];
    if (m >= 0xc0 && m <= 0xcf && m !== 0xc4 && m !== 0xc8 && m !== 0xcc) {
      return { alto: (b[i + 5] << 8) | b[i + 6], ancho: (b[i + 7] << 8) | b[i + 8], canales: b[i + 9] };
    }
    if (m === 0xd8 || (m >= 0xd0 && m <= 0xd9)) { i += 2; continue; }
    i += 2 + ((b[i + 2] << 8) | b[i + 3]);
  }
  return null;
}

/** El QR como imagen en escala de grises, lista para el PDF. */
async function imagenQr(texto: string) {
  const m = modulos(texto);
  const lado = m.length;
  const crudo = new Uint8Array(lado * lado);
  for (let y = 0; y < lado; y++) {
    for (let x = 0; x < lado; x++) crudo[y * lado + x] = m[y][x] ? 0 : 255;
  }
  return { lado, datos: await desinflar(crudo) };
}

export type Entrada = {
  evento: string; club: string; fecha: string; hora: string;
  persona: string; codigo: string; nota?: string;
};

const A = 595, ALTO = 842; // A4 en puntos

/** Una página por entrada, con el arte de fondo si vino. */
export async function entradasPdf(entradas: Entrada[], arte?: Uint8Array | null) {
  const objetos: (string | Uint8Array)[] = [];
  const nuevo = (cuerpo: string | Uint8Array) => { objetos.push(cuerpo); return objetos.length; };

  const jpeg = arte && medidaJpeg(arte) ? { bytes: arte, ...medidaJpeg(arte)! } : null;
  const idArte = jpeg
    ? nuevo(unir(enc.encode(`<< /Type /XObject /Subtype /Image /Width ${jpeg.ancho} /Height ${jpeg.alto}`
      + ` /ColorSpace ${jpeg.canales === 1 ? "/DeviceGray" : jpeg.canales === 4 ? "/DeviceCMYK" : "/DeviceRGB"}`
      + ` /BitsPerComponent 8 /Filter /DCTDecode /Length ${jpeg.bytes.length} >>\nstream\n`),
      jpeg.bytes, enc.encode("\nendstream")))
    : 0;

  const idVelo = nuevo("<< /Type /ExtGState /ca 0.62 >>");
  const idOpaco = nuevo("<< /Type /ExtGState /ca 1 >>");
  const idNegrita = nuevo("<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica-Bold /Encoding /WinAnsiEncoding >>");
  const idNormal = nuevo("<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica /Encoding /WinAnsiEncoding >>");

  const idsQr: number[] = [];
  for (const e of entradas) {
    const q = await imagenQr(e.codigo);
    idsQr.push(nuevo(unir(
      enc.encode(`<< /Type /XObject /Subtype /Image /Width ${q.lado} /Height ${q.lado}`
        + ` /ColorSpace /DeviceGray /BitsPerComponent 8 /Filter /FlateDecode`
        + ` /Interpolate false /Length ${q.datos.length} >>\nstream\n`),
      q.datos, enc.encode("\nendstream"))));
  }

  const idPaginas = objetos.length + entradas.length * 2 + 1;
  const idsPagina: number[] = [];
  entradas.forEach((e, i) => {
    const contenido = pagina(e, entradas.length > 1 ? `${i + 1} de ${entradas.length}` : null,
      idArte, jpeg, idsQr[i], idVelo, idOpaco);
    const idContenido = nuevo(`<< /Length ${contenido.length} >>\nstream\n${contenido}\nendstream`);
    const recursos = `<< /Font << /B ${idNegrita} 0 R /N ${idNormal} 0 R >>`
      + ` /XObject << ${idArte ? `/Arte ${idArte} 0 R ` : ""}/Qr ${idsQr[i]} 0 R >>`
      + ` /ExtGState << /Velo ${idVelo} 0 R /Opaco ${idOpaco} 0 R >> >>`;
    idsPagina.push(nuevo(`<< /Type /Page /Parent ${idPaginas} 0 R /MediaBox [0 0 ${A} ${ALTO}]`
      + ` /Resources ${recursos} /Contents ${idContenido} 0 R >>`));
  });

  nuevo(`<< /Type /Pages /Kids [${idsPagina.map((n) => `${n} 0 R`).join(" ")}] /Count ${idsPagina.length} >>`);
  const idCatalogo = nuevo(`<< /Type /Catalog /Pages ${idPaginas} 0 R >>`);

  // ── el archivo ──
  const partes: Uint8Array[] = [enc.encode("%PDF-1.4\n%\xE2\xE3\xCF\xD3\n")];
  let largo = partes[0].length;
  const posiciones: number[] = [];
  objetos.forEach((o, i) => {
    posiciones.push(largo);
    const cabeza = enc.encode(`${i + 1} 0 obj\n`);
    const cuerpo = typeof o === "string" ? enc.encode(o) : o;
    const cola = enc.encode("\nendobj\n");
    partes.push(cabeza, cuerpo, cola);
    largo += cabeza.length + cuerpo.length + cola.length;
  });
  let xref = `xref\n0 ${objetos.length + 1}\n0000000000 65535 f \n`;
  for (const p of posiciones) xref += `${String(p).padStart(10, "0")} 00000 n \n`;
  xref += `trailer\n<< /Size ${objetos.length + 1} /Root ${idCatalogo} 0 R >>\nstartxref\n${largo}\n%%EOF\n`;
  partes.push(enc.encode(xref));
  return unir(...partes);
}

function unir(...bs: Uint8Array[]) {
  const total = bs.reduce((n, b) => n + b.length, 0);
  const out = new Uint8Array(total);
  let i = 0;
  for (const b of bs) { out.set(b, i); i += b.length; }
  return out;
}

function recortar(s: string, max: number) {
  return s.length > max ? s.slice(0, max - 1) + "…" : s;
}

function pagina(e: Entrada, deCuantas: string | null, idArte: number,
  jpeg: { ancho: number; alto: number } | null, _idQr: number, _v: number, _o: number) {
  let c = "q\n";
  if (idArte && jpeg) {
    // el arte cubre la página entera, recortado por el lado que sobre
    const escala = Math.max(A / jpeg.ancho, ALTO / jpeg.alto);
    const w = jpeg.ancho * escala, h = jpeg.alto * escala;
    c += `${w.toFixed(2)} 0 0 ${h.toFixed(2)} ${((A - w) / 2).toFixed(2)} ${((ALTO - h) / 2).toFixed(2)} cm\n/Arte Do\n`;
  } else {
    c += `0.043 0.043 0.051 rg\n0 0 ${A} ${ALTO} re f\n`;
  }
  c += "Q\n";
  // velo para que se lea el texto arriba del arte
  c += `q\n/Velo gs\n0 0 0 rg\n0 0 ${A} ${ALTO} re f\nQ\n`;

  const blanco = "1 1 1 rg\n";
  const tenue = "0.72 0.72 0.76 rg\n";
  const oro = "0.91 0.76 0.42 rg\n";
  const txt = (x: number, y: number, fuente: string, tam: number, color: string, s: string) =>
    `BT\n${color}/${fuente} ${tam} Tf\n${x} ${y} Td\n${textoPdf(s)} Tj\nET\n`;

  c += txt(48, ALTO - 62, "B", 11, oro, "AFTR");
  if (deCuantas) c += txt(A - 120, ALTO - 62, "N", 11, tenue, deCuantas);

  c += txt(48, ALTO - 118, "B", 26, blanco, recortar(e.evento, 30));
  c += txt(48, ALTO - 146, "N", 13, tenue, recortar(`${e.club} · ${e.fecha}${e.hora ? ` · ${e.hora}` : ""}`, 52));

  // el QR, sobre blanco para que lo lea cualquier lector
  const lado = 300, x = (A - lado) / 2, y = 320;
  c += `q\n/Opaco gs\n1 1 1 rg\n${x - 22} ${y - 22} ${lado + 44} ${lado + 44} re f\n`;
  c += `${lado} 0 0 ${lado} ${x} ${y} cm\n/Qr Do\nQ\n`;

  c += txt(48, y - 72, "N", 11, tenue, "A nombre de");
  c += txt(48, y - 100, "B", 22, blanco, recortar(e.persona || "Invitado", 32));

  c += txt(48, 92, "N", 10, tenue, "Mostrá este QR en la puerta. Entra una sola vez.");
  if (e.nota) c += txt(48, 74, "N", 10, tenue, recortar(e.nota, 70));
  return c;
}
