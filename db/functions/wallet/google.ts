/* La entrada en Google Wallet.
 *
 * Google no necesita un archivo firmado como Apple: necesita un enlace con un
 * JWT firmado por la cuenta de servicio. Acá el JWT lleva **adentro** la clase
 * y el objeto del pase, así no hace falta crear nada por la API antes: el
 * enlace se arma y ya. Google llama a eso un JWT "gordo", y es justo lo que
 * conviene cuando cada entrada es distinta y se emite una sola vez.
 */
export type Entrada = {
  codigo: string;
  serie: string;
  evento: string;
  club: string;
  persona: string;
  /** ISO con zona: cuándo empieza. */
  inicio: string;
  fecha: string;
  hora: string;
  lugar?: { lat: number; lng: number } | null;
};

const b64url = (b: Uint8Array) =>
  btoa(String.fromCharCode(...b)).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");

const texto = (s: string) => b64url(new TextEncoder().encode(s));

/** La llave de la cuenta de servicio, lista para firmar. */
export async function llaveDeCuenta(privateKeyPem: string) {
  const cuerpo = privateKeyPem
    .replace(/\\n/g, "\n")
    .replace(/-----(BEGIN|END) PRIVATE KEY-----/g, "").replace(/\s+/g, "");
  const der = Uint8Array.from(atob(cuerpo), (c) => c.charCodeAt(0));
  return await crypto.subtle.importKey(
    "pkcs8", der.buffer, { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" }, false, ["sign"]);
}

/** Sólo letras, números, guiones y puntos: es lo que Google acepta en un id. */
const limpio = (s: string) => s.replace(/[^A-Za-z0-9._-]/g, "_").slice(0, 60);

export function pasePayload(e: Entrada, emisor: string) {
  const claseId = `${emisor}.${limpio("ev_" + e.evento)}`;
  const objetoId = `${emisor}.${limpio(e.serie)}`;
  const clase: Record<string, unknown> = {
    id: claseId,
    issuerName: "AFTR",
    eventName: { defaultValue: { language: "es-BO", value: e.evento } },
    venue: {
      name: { defaultValue: { language: "es-BO", value: e.club } },
      address: { defaultValue: { language: "es-BO", value: e.club } },
    },
    dateTime: { start: e.inicio },
    reviewStatus: "UNDER_REVIEW",
    hexBackgroundColor: "#0b0b0d",
  };
  const objeto: Record<string, unknown> = {
    id: objetoId,
    classId: claseId,
    state: "ACTIVE",
    // el mismo código que lee la puerta, igual que en el correo y en el PDF
    barcode: { type: "QR_CODE", value: e.codigo, alternateText: e.persona },
    ticketHolderName: e.persona,
    textModulesData: [
      { header: "Cuándo", body: `${e.fecha} · ${e.hora}`, id: "cuando" },
      { header: "En la puerta", body: "Mostrá este QR. Entra una sola vez.", id: "puerta" },
    ],
  };
  // dónde queda: Google lo usa para mostrarlo cuando la persona está cerca
  if (e.lugar && Number.isFinite(e.lugar.lat) && Number.isFinite(e.lugar.lng)) {
    objeto.locations = [{ latitude: e.lugar.lat, longitude: e.lugar.lng }];
  }
  return { eventTicketClasses: [clase], eventTicketObjects: [objeto] };
}

/** El enlace para guardar la entrada en Google Wallet. */
export async function enlaceGoogle(e: Entrada, emisor: string, cuenta: {
  client_email: string;
  private_key: string;
}) {
  const cabecera = { alg: "RS256", typ: "JWT" };
  const cuerpo = {
    iss: cuenta.client_email,
    aud: "google",
    typ: "savetowallet",
    iat: Math.floor(Date.now() / 1000),
    origins: ["https://www.aftrvenue.com"],
    payload: pasePayload(e, emisor),
  };
  const sinFirma = `${texto(JSON.stringify(cabecera))}.${texto(JSON.stringify(cuerpo))}`;
  const llave = await llaveDeCuenta(cuenta.private_key);
  const firma = new Uint8Array(await crypto.subtle.sign(
    { name: "RSASSA-PKCS1-v1_5" }, llave, new TextEncoder().encode(sinFirma).buffer));
  return `https://pay.google.com/gp/v/save/${sinFirma}.${b64url(firma)}`;
}
