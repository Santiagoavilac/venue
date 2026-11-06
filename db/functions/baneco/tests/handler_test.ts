import type { SupabaseClient } from "@supabase/supabase-js";
import { Banco, type Datos, ErrorBanco } from "../bank.ts";
import { crearHandler } from "../handler.ts";
const id = "11111111-1111-4111-8111-111111111111";
const VIVOS = ["generando", "activo", "pagado", "revisar"];
const igual = (a: unknown, b: unknown) => { if (JSON.stringify(a) !== JSON.stringify(b)) throw new Error(`${JSON.stringify(a)} != ${JSON.stringify(b)}`); };

function escenario(pasarelas: string[] = [""], pasarelaDelPedido = "") {
  const tablas: Record<string, Datos[]> = {
    aftr_ordenes: [{ id, cliente_id: "cliente", estado: "pendiente", total: 25.50, vence_at: "2030-01-01T00:00:00Z" }], pago_qr: [],
  };
  const llamadas: string[] = [], logs: Datos[] = [], tomas: Datos[] = [];
  const admin = {
    auth: { getUser: (jwt: string) => Promise.resolve({ data: { user: jwt === "sesion" ? { id: "cliente" } : null }, error: null }) },
    from(tabla: string) {
      let filas = [...(tablas[tabla] ?? [])], cambios: Datos | null = null, singular = false;
      const query = {
        select: (_?: string) => query,
        eq: (campo: string, valor: unknown) => { filas = filas.filter((x) => x[campo] === valor); return query; },
        not: (campo: string, _: string, valor: unknown) => { filas = filas.filter((x) => x[campo] !== valor); return query; },
        // el handler pide el último QR: acá "último" es el insertado al final
        order: () => { filas = [...filas].reverse(); return query; },
        limit: () => query,
        update: (datos: Datos) => { cambios = datos; return query; },
        single: () => { singular = true; return query; },
        maybeSingle: () => { singular = true; return query; },
        then(resolve: (r: { data: unknown; error: unknown }) => void) {
          if (cambios) for (const fila of filas) Object.assign(fila, cambios);
          resolve({ data: singular ? filas[0] ?? null : filas, error: null });
        },
      };
      return query;
    },
    rpc(nombre: string, p: Datos) {
      llamadas.push(nombre);
      if (nombre === "baneco_reservar_qr" || nombre === "baneco_reservar_destino") {
        // como el SQL: devuelve el cobro VIVO si lo hay, y si no crea otro.
        // Los anulados quedan de histórico y no bloquean un QR nuevo.
        let q = [...tablas.pago_qr].reverse().find((x) => VIVOS.includes(String(x.estado)));
        const reservado = !q;
        q ??= { id: `fila${tablas.pago_qr.length}`, [p.p_tipo === 'recarga' ? 'recarga_id' : p.p_tipo === 'pedido' ? 'pedido_id' : 'orden_id']: id, estado: "generando", generacion_id: "generacion",
          transaction_id: "comercio", monto: 25.50, moneda: "BOB", vence: "2030-01-01", ambiente: "certificacion", pasarela: "" };
        if (reservado) tablas.pago_qr.push(q);
        return Promise.resolve({ data: { reservado, pago: { ...q } }, error: null });
      }
      // Las pasarelas en uso: por omisión sólo la de la plataforma, que es la vacía.
      if (nombre === "baneco_pasarelas") return Promise.resolve({ data: pasarelas, error: null });
      if (nombre === "baneco_pasarela_de") return Promise.resolve({ data: pasarelaDelPedido, error: null });
      if (nombre === "baneco_tomar_barrido") { tomas.push(p); return Promise.resolve({ data: { dia: "2026-10-29", token: "lease" }, error: null }); }
      if (nombre === "baneco_finalizar_barrido") {
        tablas.finalizacion = [...(tablas.finalizacion ?? []), p]; return Promise.resolve({ data: null, error: null });
      }
      return Promise.resolve({ data: { estado: "pagado", nuevo: true }, error: null });
    },
  } as unknown as SupabaseClient;
  const config: Record<string, string> = { BANECO_CRON_TOKEN: "c".repeat(32), BANECO_WEBHOOK_TOKEN: "a".repeat(32) };
  // Un banco falso por pasarela: así se ve a qué cuenta fue cada cobro.
  const bancos = new Map<string, ReturnType<typeof bancoFalso>>();
  function bancoFalso(nombre: string) {
    return {
      nombre,
      config: { ambiente: "certificacion" }, prepararCuenta: () => Promise.resolve(`cifrado:${nombre}`), autenticar: () => Promise.resolve("t"),
      generar: (_q: Datos, _c: string) => Promise.resolve({ qrId: `qr${nombre}`, imagen: "aW1hZ2Vu" }),
      estado: (_qr: string) => Promise.resolve({ estado: 0, pago: undefined }),
      pagados: (_dia: string) => Promise.resolve([] as Datos[]), anular: (_qr: string) => Promise.resolve(),
    };
  }
  const bancoDe = (nombre: string) => {
    let b = bancos.get(nombre);
    if (!b) { b = bancoFalso(nombre); bancos.set(nombre, b); }
    return b;
  };
  const banco = bancoDe("");
  const handler = crearHandler(admin, bancoDe as unknown as (p: string) => Banco, (k) => config[k], Date.now, (d) => logs.push(d));
  const request = (body: unknown, headers: Record<string, string> = {}) => handler(new Request("https://local/baneco", {
    method: "POST", headers: { "Content-Type": "application/json", ...headers }, body: JSON.stringify(body),
  }));
  return { handler, request, tablas, llamadas, banco, logs, config, tomas, bancos };
}
Deno.test("una recarga usa el destino propio y el importe persistido", async () => {
  const s = escenario(); s.tablas.pulse_recargas = [{ id, cliente_id: 'cliente', estado: 'pendiente', importe_centavos: 2550, vence_at: '2030-01-01' }];
  igual((await s.request({ accion: 'qr', tipo: 'recarga', orden: id, amount: 1 }, { Authorization: 'Bearer sesion' })).status, 200);
  igual(s.llamadas.includes('baneco_reservar_destino'), true); igual(s.tablas.pago_qr[0].recarga_id, id);
});
Deno.test("un pedido de bebidas ajeno no se puede pagar ni consultar", async () => {
  const s = escenario(); s.tablas.aftr_bar_pedidos = [{ id, cliente_id: 'otro', estado: 'pendiente' }];
  igual((await s.request({ accion: 'qr', tipo: 'pedido', orden: id }, { Authorization: 'Bearer sesion' })).status, 404);
  igual(s.llamadas.length, 0);
});
Deno.test("el tipo de destino no acepta propiedades heredadas ni tablas arbitrarias", async () => {
  for (const tipo of ['__proto__', 'constructor', 'pulse_cuentas']) {
    const s = escenario(); igual((await s.request({ accion: 'qr', tipo, orden: id }, { Authorization: 'Bearer sesion' })).status, 400);
  }
});
Deno.test("estado sin sesión se rechaza antes de consultar al banco", async () => {
  const s = escenario(); let consultas = 0; s.banco.estado = () => { consultas++; throw new Error(); };
  igual((await s.request({ accion: "estado", orden: id })).status, 401); igual(consultas, 0);
});
Deno.test("un cliente no accede al pedido de otro", async () => {
  const s = escenario(); s.tablas.aftr_ordenes[0].cliente_id = "otro";
  igual((await s.request({ accion: "qr", orden: id }, { Authorization: "Bearer sesion" })).status, 404); igual(s.llamadas.length, 0);
});
Deno.test("un importe enviado por el cliente no cambia el QR", async () => {
  const s = escenario(); let monto: unknown;
  s.banco.generar = (q) => { monto = q.monto; return Promise.resolve({ qrId: "qr", imagen: "aW1hZ2Vu" }); };
  igual((await s.request({ accion: "qr", orden: id, amount: 0.01 }, { Authorization: "Bearer sesion" })).status, 200);
  igual(monto, 25.50);
});
Deno.test("dos solicitudes de QR simultáneas generan una sola vez", async () => {
  const s = escenario(); let cantidad = 0;
  let liberar!: () => void, inicio!: () => void;
  const comenzo = new Promise<void>((r) => inicio = r), espera = new Promise<void>((r) => liberar = r);
  s.banco.generar = async () => { cantidad++; inicio(); await espera; return { qrId: "qr", imagen: "aW1hZ2Vu" }; };
  const primero = s.request({ accion: "qr", orden: id }, { Authorization: "Bearer sesion" });
  await comenzo;
  igual((await s.request({ accion: "qr", orden: id }, { Authorization: "Bearer sesion" })).status, 409);
  liberar(); igual((await primero).status, 200); igual(cantidad, 1);
});
Deno.test("timeout al generar queda para revisión y no borra el pedido", async () => {
  const s = escenario(); s.banco.generar = () => Promise.reject(new ErrorBanco("generateQR", "RED", true));
  igual((await s.request({ accion: "qr", orden: id }, { Authorization: "Bearer sesion" })).status, 502);
  igual(s.tablas.pago_qr[0].estado, "revisar"); igual(s.tablas.aftr_ordenes[0].estado, "pendiente");
});
Deno.test("no devuelve el QR de un pedido vencido", async () => {
  const s = escenario(); s.tablas.aftr_ordenes[0].vence_at = "2026-10-30T00:00:00Z";
  s.tablas.pago_qr.push({ orden_id: id, qr_id: "qr", estado: "activo", ambiente: "certificacion", pasarela: "" });
  igual((await s.request({ accion: "qr", orden: id }, { Authorization: "Bearer sesion" })).status, 409);
});
Deno.test("un QR anulado a los diez minutos no impide pedir otro", async () => {
  const s = escenario();
  s.tablas.pago_qr.push({ id: "viejo", orden_id: id, qr_id: "qr-viejo", estado: "anulado", ambiente: "certificacion", pasarela: "" });
  igual((await s.request({ accion: "qr", orden: id }, { Authorization: "Bearer sesion" })).status, 200);
  igual(s.tablas.pago_qr.length, 2);
  igual(s.tablas.pago_qr[1].estado, "activo");
  igual(s.tablas.pago_qr[0].estado, "anulado");
});
Deno.test("el estado y el QR informan el límite y la nota del cobro", async () => {
  const s = escenario();
  s.tablas.pago_qr.push({ id: "fila", orden_id: id, qr_id: "qr", estado: "revisar", ambiente: "certificacion", pasarela: "",
    monto: 25.50, moneda: "BOB", vence: "2030-01-01", limite_at: "2026-11-05T15:00:00Z", nota: "PAGADO_FUERA_DE_PLAZO" });
  const r = await (await s.request({ accion: "estado", orden: id }, { Authorization: "Bearer sesion" })).json();
  igual(r.pago.nota, "PAGADO_FUERA_DE_PLAZO");
  igual(r.pago.limite, "2026-11-05T15:00:00Z");
});
Deno.test("notificación falsificada no consulta banco ni confirma entradas", async () => {
  const s = escenario();
  igual((await s.request({ payment: { qrId: "qr", amount: 25.50 } })).status, 401); igual(s.llamadas.length, 0);
});
Deno.test("notificación autorizada reconsulta al banco y nunca confía en amount recibido", async () => {
  const s = escenario(); s.tablas.pago_qr.push({ id: "fila", qr_id: "qr", estado: "activo", ambiente: "certificacion", pasarela: "" });
  let consultas = 0; s.banco.estado = () => { consultas++; return Promise.resolve({ estado: 0, pago: undefined }); };
  igual((await s.request({ payment: { qrId: "qr", amount: 999 } }, { "x-baneco-token": "a".repeat(32) })).status, 200);
  igual(consultas, 1); igual(s.llamadas.includes("aftr_pago_confirmado"), false);
});
Deno.test("cron requiere su secreto y no acepta acciones desconocidas", async () => {
  const s = escenario(); igual((await s.request({ accion: "barrido" })).status, 401);
  igual((await s.request({ accion: "pagar" })).status, 400); igual(s.llamadas.length, 0);
});
Deno.test("conciliación corre sin QR activos y utiliza el día persistido", async () => {
  const s = escenario(); let dia: unknown;
  s.banco.pagados = (fecha) => { dia = fecha; return Promise.resolve([]); };
  igual((await s.request({ accion: "barrido" }, { "x-cron": "c".repeat(32) })).status, 200);
  igual(dia, "2026-10-29"); igual(s.tablas.finalizacion[0].p_dia_ok, "2026-10-29");
});
Deno.test("error de conciliación no avanza el cursor ni expone secretos", async () => {
  const s = escenario(); s.banco.pagados = () => Promise.reject(new Error("secreto y datos bancarios"));
  await s.request({ accion: "barrido" }, { "x-cron": "c".repeat(32) });
  igual(s.tablas.finalizacion[0].p_dia_ok, null); igual(s.tablas.finalizacion[0].p_errores, 1);
  igual(JSON.stringify(s.logs).includes("secreto y datos bancarios"), false);
});
Deno.test("rechaza GET y JSON inválido sin tocar base ni banco", async () => {
  const s = escenario(); igual((await s.handler(new Request("https://local"))).status, 405);
  igual((await s.handler(new Request("https://local", { method: "POST", body: "{" }))).status, 400); igual(s.llamadas.length, 0);
});

Deno.test("una consulta individual fallida no bloquea un día ya conciliado", async () => {
  const s = escenario();
  s.tablas.pago_qr.push({id: "fila", qr_id: "qr", estado: "activo", ambiente: "certificacion", pasarela: "", intentos: 0});
  s.banco.estado = () => Promise.reject(new Error("fallo simulado"));
  await s.request({accion: "barrido"}, {"x-cron": "c".repeat(32)});
  igual(s.tablas.finalizacion[0].p_dia_ok, "2026-10-29");
  igual(s.tablas.finalizacion[0].p_errores, 1);
});
Deno.test("CORS: sólo los dominios propios, y sin Origin no se autoriza a nadie", async () => {
  const s = escenario();
  const con = async (origin?: string) => {
    const r = await s.handler(new Request("https://local/baneco", {
      method: "OPTIONS", headers: origin ? { Origin: origin } : {},
    }));
    return r.headers.get("access-control-allow-origin");
  };
  igual(await con("https://aftrvenue.com"), "https://aftrvenue.com");
  igual(await con("https://malicioso.example"), null);
  igual(await con(), null);
});

/* ── una pasarela por boliche ───────────────────────────────────────────
 * Qué se rompía: había una sola pasarela para toda la plataforma, así que
 * todo lo cobrado con QR caía en la misma cuenta. Con dos boliches que traen
 * su propia cuenta del banco, la plata de uno terminaría en la del otro.
 */
Deno.test("el cobro va a la cuenta del boliche, no a la de la plataforma", async () => {
  const s = escenario([""], "sitroom");
  igual((await s.request({ accion: "qr", orden: id }, { Authorization: "Bearer sesion" })).status, 200);
  // la cuenta cifrada que se mandó al banco es la de sitroom
  igual(s.tablas.pago_qr[0].qr_id, "qrsitroom");
  igual(s.bancos.has("sitroom"), true);
});

Deno.test("sin pasarela propia sigue cobrando la plataforma", async () => {
  const s = escenario([""], "");
  igual((await s.request({ accion: "qr", orden: id }, { Authorization: "Bearer sesion" })).status, 200);
  igual(s.tablas.pago_qr[0].qr_id, "qr");
  igual(s.bancos.has("sitroom"), false);
});

Deno.test("un nombre de pasarela se consulta a la base, no se inventa", async () => {
  const s = escenario([""], "sitcom");
  await s.request({ accion: "qr", orden: id }, { Authorization: "Bearer sesion" });
  igual(s.llamadas.includes("baneco_pasarela_de"), true);
});

Deno.test("el barrido corre una vez por pasarela, con el día de cada una", async () => {
  const s = escenario(["", "sitroom", "sitcom"]);
  await s.request({ accion: "barrido" }, { "x-cron": "c".repeat(32) });
  igual(s.tomas.length, 3);
  igual(s.tomas.map((t) => t.p_pasarela).sort().join(","), ",sitcom,sitroom");
  // y cada una cierra su propio cursor
  igual(s.tablas.finalizacion.length, 3);
  igual(s.tablas.finalizacion.map((t) => t.p_pasarela).sort().join(","), ",sitcom,sitroom");
});

Deno.test("el QR se confirma contra la cuenta con la que se generó", async () => {
  const s = escenario(["sitroom"]);
  // un cobro viejo de sitroom: aunque el boliche cambie de cuenta, éste es de
  // la de entonces
  s.tablas.pago_qr.push({ id: "fila", qr_id: "qr", estado: "activo", ambiente: "certificacion",
    pasarela: "sitroom", intentos: 0 });
  let consultada = "";
  s.bancos.get("")!.estado = () => Promise.reject(new Error("no es esta cuenta"));
  await s.request({ accion: "barrido" }, { "x-cron": "c".repeat(32) });
  const b = s.bancos.get("sitroom")!;
  consultada = b.nombre;
  igual(consultada, "sitroom");
  igual(s.tablas.finalizacion[0].p_errores, 0);
});

/* ── CORS: los encabezados que el SDK manda de verdad ───────────────────
 * Qué se rompía: la lista de encabezados permitidos estaba escrita a mano y
 * supabase-js manda además x-client-info. El navegador cancelaba el POST en
 * el preflight, así que pagar con QR desde la web no funcionaba y no quedaba
 * registro de nada.
 */
Deno.test("el preflight permite los encabezados que pide el navegador", async () => {
  const s = escenario();
  s.config.ORIGENES_PERMITIDOS = "https://www.aftrvenue.com";
  const r = await s.handler(new Request("https://local/baneco", {
    method: "OPTIONS",
    headers: {
      Origin: "https://www.aftrvenue.com",
      "Access-Control-Request-Method": "POST",
      "Access-Control-Request-Headers": "authorization,apikey,content-type,x-client-info",
    },
  }));
  igual(r.status, 200);
  igual(r.headers.get("Access-Control-Allow-Origin"), "https://www.aftrvenue.com");
  const permitidos = r.headers.get("Access-Control-Allow-Headers") ?? "";
  igual(permitidos.includes("x-client-info"), true);
  // y la respuesta varía según lo pedido, para que no se cachee la de otro
  igual((r.headers.get("Vary") ?? "").includes("Access-Control-Request-Headers"), true);
});

Deno.test("un origen ajeno no se autoriza aunque pida encabezados", async () => {
  const s = escenario();
  s.config.ORIGENES_PERMITIDOS = "https://www.aftrvenue.com";
  const r = await s.handler(new Request("https://local/baneco", {
    method: "OPTIONS",
    headers: {
      Origin: "https://no-es-nuestro.example",
      "Access-Control-Request-Method": "POST",
      "Access-Control-Request-Headers": "authorization,x-client-info",
    },
  }));
  igual(r.headers.get("Access-Control-Allow-Origin"), null);
});
