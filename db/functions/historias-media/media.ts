const ascii = (b: Uint8Array, a: number, n: number) => new TextDecoder().decode(b.subarray(a, a + n));
export function validarMedio(b: Uint8Array): { tipo: string; duracion_ms: number; mime: string } {
  if (!b.length || b.length > 30 * 1024 * 1024) throw new Error('El archivo debe pesar entre 1 byte y 30 MB.');
  if (b.length >= 24 && ascii(b, 1, 3) === 'PNG' && b[0] === 137) {
    const v = new DataView(b.buffer, b.byteOffset, b.byteLength);
    if (ascii(b, 12, 4) !== 'IHDR' || !v.getUint32(16) || !v.getUint32(20) || v.getUint32(16) > 12000 || v.getUint32(20) > 12000) throw new Error('La imagen PNG no es válida.');
    return { tipo: 'imagen', duracion_ms: 5000, mime: 'image/png' };
  }
  if (b.length >= 12 && ascii(b, 0, 4) === 'RIFF' && ascii(b, 8, 4) === 'WEBP') {
    if (b.length < 30) throw new Error('La imagen WebP está incompleta.');
    return { tipo: 'imagen', duracion_ms: 5000, mime: 'image/webp' };
  }
  if (b.length > 12 && b[0] === 255 && b[1] === 216 && b[b.length - 2] === 255 && b[b.length - 1] === 217) {
    return { tipo: 'imagen', duracion_ms: 5000, mime: 'image/jpeg' };
  }
  if (b.length < 32 || ascii(b, 4, 4) !== 'ftyp') throw new Error('Usá JPG, PNG, WebP o video MP4/MOV compatible.');
  const v = new DataView(b.buffer, b.byteOffset, b.byteLength);
  let segundos = 0, pelicula = false, datos = false, video = false, cajas = 0;
  function leer(inicio: number, fin: number, nivel = 0) {
    if (nivel > 8) throw new Error('El video tiene una estructura no válida.');
    for (let p = inicio; p + 8 <= fin;) {
      if (++cajas > 20000) throw new Error('El video tiene demasiadas secciones.');
      let size = v.getUint32(p), header = 8;
      if (size === 1) {
        if (p + 16 > fin) throw new Error('El video está incompleto.');
        const big = v.getBigUint64(p + 8);
        if (big > BigInt(b.length)) throw new Error('El video está incompleto.');
        size = Number(big); header = 16;
      } else if (size === 0) size = fin - p;
      if (size < header || p + size > fin) throw new Error('El video está incompleto.');
      const type = ascii(b, p + 4, 4), d = p + header, end = p + size;
      if (type === 'mdat' && size > header) datos = true;
      if (type === 'mvhd' || type === 'mdhd') {
        const ver = b[d], escalaPos = d + (ver === 1 ? 20 : 12), durPos = escalaPos + 4;
        if (![0, 1].includes(ver) || durPos + (ver === 1 ? 8 : 4) > end) throw new Error('Duración de video no válida.');
        const escala = v.getUint32(escalaPos), dur = ver === 1 ? Number(v.getBigUint64(durPos)) : v.getUint32(durPos);
        if (!escala || !Number.isSafeInteger(dur) || dur <= 0) throw new Error('No se pudo verificar la duración del video.');
        segundos = Math.max(segundos, dur / escala);
        if (type === 'mvhd') pelicula = true;
      }
      if (type === 'hdlr' && d + 12 <= end && ascii(b, d + 8, 4) === 'vide') video = true;
      if (['moov', 'trak', 'mdia', 'minf', 'stbl', 'edts'].includes(type)) leer(d, end, nivel + 1);
      p = end;
    }
  }
  leer(0, b.length);
  if (!pelicula || !datos || !video || !segundos || segundos > 30) throw new Error('El video debe durar como máximo 30 segundos y contener una pista de video válida.');
  return { tipo: 'video', duracion_ms: Math.ceil(segundos * 1000), mime: 'video/mp4' };
}
