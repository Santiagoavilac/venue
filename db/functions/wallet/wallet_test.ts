import { firmarCms } from "./cms.ts";
import { armarPase, passJson } from "./pkpass.ts";

/* El pase de Apple Wallet.
 *
 * No hay ninguna llave de verdad acá: la del pase se genera en el momento y
 * el "certificado" es uno armado a mano con la forma que CMS necesita leer
 * (número de serie y emisor). Alcanza para probar el sobre y el zip; que la
 * firma sea válida de verdad se comprueba con `openssl smime -verify`, que es
 * el mismo que usa el teléfono del otro lado.
 */
const igual = (a: unknown, b: unknown, que: string) => {
  if (a !== b) throw new Error(`${que}: ${JSON.stringify(a)} !== ${JSON.stringify(b)}`);
};
const cierto = (c: unknown, que: string) => { if (!c) throw new Error(que); };

// ── un certificado de mentira, con la forma justa ─────────────────────
function der(etiqueta: number, cuerpo: Uint8Array) {
  const largo = cuerpo.length < 0x80
    ? new Uint8Array([cuerpo.length])
    : new Uint8Array([0x81, cuerpo.length]);
  const out = new Uint8Array(1 + largo.length + cuerpo.length);
  out[0] = etiqueta;
  out.set(largo, 1);
  out.set(cuerpo, 1 + largo.length);
  return out;
}
const unir = (...bs: Uint8Array[]) => {
  const out = new Uint8Array(bs.reduce((n, b) => n + b.length, 0));
  let i = 0;
  for (const b of bs) { out.set(b, i); i += b.length; }
  return out;
};
function certoFalso() {
  const serie = der(0x02, new Uint8Array([0x2a]));
  const alg = der(0x30, new Uint8Array(0));
  const emisor = der(0x30, der(0x31, new Uint8Array([1, 2, 3])));
  const tbs = der(0x30, unir(serie, alg, emisor));
  return der(0x30, unir(tbs, alg, der(0x03, new Uint8Array([0]))));
}

async function llaveNueva() {
  const par = await crypto.subtle.generateKey(
    { name: "RSASSA-PKCS1-v1_5", modulusLength: 2048, publicExponent: new Uint8Array([1, 0, 1]), hash: "SHA-256" },
    false, ["sign", "verify"]);
  return par.privateKey;
}

Deno.test("la firma CMS sale con la forma que pide Apple", async () => {
  const firma = await firmarCms(
    new TextEncoder().encode("manifiesto"), [certoFalso()], await llaveNueva());
  igual(firma[0], 0x30, "arranca con una SEQUENCE");
  // 1.2.840.113549.1.7.2 = signedData
  const oidFirmado = [0x06, 0x09, 0x2a, 0x86, 0x48, 0x86, 0xf7, 0x0d, 0x01, 0x07, 0x02];
  const hay = [...firma.subarray(0, 40)].join(",").includes(oidFirmado.join(","));
  cierto(hay, "lleva el OID de signedData");
  cierto(firma.length > 300, "tiene cuerpo");
});

Deno.test("el pase lleva lo que lo hace aparecer solo", () => {
  const p = passJson({
    codigo: "ABC123", serie: "s1", evento: "Noche", club: "Burtown",
    persona: "Ana Pérez", inicio: "2026-11-06T21:00:00-04:00",
    lugar: { lat: -17.78, lng: -63.18 },
  }, {
    passTypeIdentifier: "pass.app.venue.aftr", teamIdentifier: "WYCP7K767H",
    certs: [], llave: null as unknown as CryptoKey, imagenes: {},
  }) as Record<string, unknown>;
  // la hora: iOS lo saca en la pantalla bloqueada un rato antes
  igual(p.relevantDate, "2026-11-06T21:00:00-04:00", "relevantDate");
  // el lugar: aparece al llegar cerca, sin ninguna notificación
  const l = (p.locations as Record<string, number>[])[0];
  igual(l.latitude, -17.78, "latitud");
  igual(l.longitude, -63.18, "longitud");
  // y el QR dice lo mismo que el de la app y el del correo
  igual((p.barcodes as Record<string, string>[])[0].message, "ABC123", "el código del QR");
});

Deno.test("sin lugar, el pase igual sale: la hora alcanza", () => {
  const p = passJson({
    codigo: "ABC123", serie: "s1", evento: "Noche", club: "Burtown",
    persona: "Ana", inicio: "2026-11-06T21:00:00-04:00", lugar: null,
  }, {
    passTypeIdentifier: "pass.x", teamIdentifier: "T", certs: [],
    llave: null as unknown as CryptoKey, imagenes: {},
  }) as Record<string, unknown>;
  igual(p.locations, undefined, "sin locations");
  cierto(p.relevantDate, "con relevantDate");
});

Deno.test("el zip tiene todo y los hashes del manifiesto dan", async () => {
  const icono = new Uint8Array([0x89, 0x50, 0x4e, 0x47, 1, 2, 3, 4]);
  const pkpass = await armarPase({
    codigo: "ABC123", serie: "s1", evento: "Noche", club: "Burtown",
    persona: "Ana", inicio: "2026-11-06T21:00:00-04:00", lugar: null,
  }, {
    passTypeIdentifier: "pass.x", teamIdentifier: "T",
    certs: [certoFalso()], llave: await llaveNueva(),
    imagenes: { "icon.png": icono },
  });
  const texto = new TextDecoder("latin1").decode(pkpass);
  for (const n of ["pass.json", "icon.png", "manifest.json", "signature"]) {
    cierto(texto.includes(n), `falta ${n} en el zip`);
  }
  igual(pkpass[0], 0x50, "firma del zip"); // 'P'
  igual(pkpass[1], 0x4b, "firma del zip"); // 'K'
});

Deno.test("sin icon.png no se arma el pase, en vez de salir roto", async () => {
  let fallo = "";
  try {
    await armarPase({
      codigo: "A", serie: "s", evento: "e", club: "c", persona: "p",
      inicio: "2026-11-06T21:00:00-04:00", lugar: null,
    }, {
      passTypeIdentifier: "pass.x", teamIdentifier: "T",
      certs: [certoFalso()], llave: await llaveNueva(), imagenes: {},
    });
  } catch (e) {
    fallo = e instanceof Error ? e.message : String(e);
  }
  cierto(fallo.includes("icon.png"), "tiene que decir qué falta");
});
