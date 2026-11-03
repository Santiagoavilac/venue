import { Banco, cifrar, configuracion, diaBolivia, estadoQr, pagoQr } from "../bank.ts";

export function igual(actual: unknown, esperado: unknown) {
  if (JSON.stringify(actual) !== JSON.stringify(esperado)) throw new Error(`Esperado ${JSON.stringify(esperado)}, recibido ${JSON.stringify(actual)}`);
}
async function rechaza(f: () => unknown | Promise<unknown>) {
  try { await f(); } catch { return; } throw new Error("Debió rechazar la operación");
}
export const valores: Record<string, string> = {
  BANECO_BASE_URL: "https://apimktdesa.baneco.com.bo/ApiGateway/",
  BANECO_USER: "usuario-simulado", BANECO_PASSWORD: "secreto-simulado",
  BANECO_AES_KEY: "40A318B299F245C2B697176723088629", BANECO_ACCOUNT: "cuenta-simulada",
  BANECO_CREDENTIALS_EXPIRES_AT: "2030-01-01T00:00:00Z",
};
const json = (body: unknown, status = 200) => new Response(JSON.stringify(body), { status });

Deno.test("AES: el ejemplo público del manual se descifra como 1234", async () => {
  const todo = Uint8Array.from(atob("KJAzqjmwjxIOqVo5J3IH0/7fGmNdzuyszrlqexVSeos="), (x) => x.charCodeAt(0));
  const key = await crypto.subtle.importKey("raw", new TextEncoder().encode(valores.BANECO_AES_KEY), "AES-CBC", false, ["decrypt"]);
  const resultado = await crypto.subtle.decrypt({ name: "AES-CBC", iv: todo.slice(0, 16) }, key, todo.slice(16));
  igual(new TextDecoder().decode(resultado), "1234");
});
Deno.test("AES: conserva formato IV+cifrado y usa un IV distinto", async () => {
  const a = await cifrar("1234", valores.BANECO_AES_KEY), b = await cifrar("1234", valores.BANECO_AES_KEY);
  igual(atob(a).length, 32); if (a === b) throw new Error("IV repetido");
  await rechaza(() => cifrar("1234", "corta"));
});
Deno.test("ambientes: producción falla sin aprobación y host explícitos", async () => {
  igual(configuracion((k) => valores[k]).ambiente, "certificacion");
  await rechaza(() => configuracion((k) => ({ ...valores, BANECO_BASE_URL: "https://apimkt.baneco.com.bo/ApiGateway/" })[k]));
  await rechaza(() => configuracion((k) => ({ ...valores, BANECO_AMBIENTE: "produccion" })[k]));
  await rechaza(() => configuracion((k) => ({ ...valores, BANECO_BASE_URL: "http://apimktdesa.baneco.com.bo/ApiGateway/" })[k]));
});
Deno.test("credenciales vencidas no hacen llamadas al banco", async () => {
  let llamadas = 0;
  const b = new Banco((k) => ({ ...valores, BANECO_CREDENTIALS_EXPIRES_AT: "2026-10-30T00:00:00Z" })[k], () => { llamadas++; throw new Error(); });
  await rechaza(() => b.autenticar()); igual(llamadas, 0);
});
Deno.test("autenticación: solicitudes simultáneas comparten un token", async () => {
  let llamadas = 0;
  const b = new Banco((k) => valores[k], () => { llamadas++; return Promise.resolve(json({ responseCode: 0, token: "token-simulado" })); });
  igual(await Promise.all([b.autenticar(), b.autenticar(), b.autenticar()]), ["token-simulado", "token-simulado", "token-simulado"]);
  igual(llamadas, 1);
});
Deno.test("HTTP 200 con responseCode 404 sigue siendo rechazo", async () => {
  let llamadas = 0;
  const b = new Banco((k) => valores[k], () => { llamadas++; return Promise.resolve(json({ responseCode: 404, message: "Usuario no habilitado" })); });
  await rechaza(() => b.autenticar()); igual(llamadas, 1);
});
Deno.test("token rechazado se renueva una sola vez", async () => {
  let auth = 0, estados = 0;
  const b = new Banco((k) => valores[k], (url) => {
    if (String(url).endsWith("authenticate")) return Promise.resolve(json({ responseCode: 0, token: `t${++auth}` }));
    estados++; return Promise.resolve(estados === 1 ? json({ responseCode: 401 }, 401) : json({ responseCode: 0, statusQrCode: 0 }));
  });
  igual((await b.estado("qr")).estado, 0); igual(auth, 2); igual(estados, 2);
});
Deno.test("QR: importe fijo, un uso, cuerpo sólo en POST y cuenta cifrada", async () => {
  let cuerpo: Record<string, unknown> = {};
  const b = new Banco((k) => valores[k], (url, init) => {
    if (String(url).endsWith("authenticate")) return Promise.resolve(json({ responseCode: 0, token: "t" }));
    cuerpo = JSON.parse(String(init?.body)); igual(init?.method, "POST");
    return Promise.resolve(json({ responseCode: 0, qrId: "qr", qrImage: "aW1hZ2Vu" }));
  });
  await b.generar({ transaction_id: "comercio", monto: 10.25, vence: "2026-11-01" }, await b.prepararCuenta());
  igual(cuerpo.amount, 10.25); igual(cuerpo.modifyAmount, false); igual(cuerpo.singleUse, true);
  igual(cuerpo.currency, "BOB"); if (cuerpo.accountCredit === valores.BANECO_ACCOUNT) throw new Error("Cuenta sin cifrar");
});
Deno.test("estado: soporta las dos grafías del manual y rechaza respuestas incompletas", async () => {
  igual(estadoQr({ statusQRCode: 1 }), 1); igual(estadoQr({ statusQrCode: 9 }), 9);
  await rechaza(() => estadoQr({})); await rechaza(() => estadoQr({ statusQRCode: null }));
});
Deno.test("pago: exige QR correcto y número de transacción bancaria", async () => {
  const p = { qrId: "correcto", transactionId: "banco" };
  igual(pagoQr({ payment: p }, "correcto"), p);
  igual(pagoQr({ payment: [{ qrId: "otro" }, p] }, "correcto"), p);
  await rechaza(() => pagoQr({ payment: p }, "otro"));
  await rechaza(() => pagoQr({ payment: { qrId: "correcto" } }, "correcto"));
});
Deno.test("paidQR: comprueba responseCode y usa yyyyMMdd sin body", async () => {
  const b = new Banco((k) => valores[k], (url, init) => {
    if (String(url).endsWith("authenticate")) return Promise.resolve(json({ responseCode: 0, token: "t" }));
    igual(String(url).endsWith("/v2/paidQR/20261031"), true); igual(init?.body, undefined);
    return Promise.resolve(json({ responseCode: 99, paymentList: [] }));
  });
  await rechaza(() => b.pagados("2026-10-31"));
});
Deno.test("fecha bancaria usa Bolivia al cruzar medianoche UTC", () => {
  igual(diaBolivia(Date.parse("2026-11-01T02:00:00Z")), "2026-10-31");
});

Deno.test("certificación admite las credenciales de prueba sin vencimiento informado", async () => {
  const b = new Banco((k) => k === "BANECO_CREDENTIALS_EXPIRES_AT" ? undefined : valores[k], () => Promise.resolve(new Response(JSON.stringify({responseCode:0,token:"simulado"}))));
  igual(await b.autenticar(), "simulado");
});
