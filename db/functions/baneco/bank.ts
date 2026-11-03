/** API Market 1.3.0. Sin acceso a Supabase ni credenciales del cliente. */
export type Datos = Record<string, unknown>;
export type Entorno = (nombre: string) => string | undefined;
export class ErrorBanco extends Error {
  constructor(public paso: string, public codigo: string | number, public incierto = false) {
    super(`Banco no disponible (${paso}).`);
  }
}

export function configuracion(env: Entorno) {
  const url = new URL(env("BANECO_BASE_URL") || "https://apimktdesa.baneco.com.bo/ApiGateway/");
  if (url.protocol !== "https:" || url.username || url.password || url.search || url.hash ||
      url.pathname.replace(/\/+$/, "") !== "/ApiGateway" || url.port) throw new Error("Configuración bancaria inválida.");
  const ambiente = env("BANECO_AMBIENTE") || "certificacion";
  if (ambiente === "certificacion" && url.hostname !== "apimktdesa.baneco.com.bo") throw new Error("El host no corresponde a certificación.");
  if (ambiente !== "certificacion" && ambiente !== "produccion") throw new Error("Ambiente bancario inválido.");
  // El manual sólo publica certificación. Producción requiere confirmación externa.
  if (ambiente === "produccion" && (env("BANECO_PRODUCTION_APPROVED") !== "true" ||
      env("BANECO_PRODUCTION_HOST") !== url.hostname || url.hostname === "apimktdesa.baneco.com.bo")) {
    throw new Error("Producción bancaria sin habilitación confirmada.");
  }
  return { base: url.href.replace(/\/+$/, ""), ambiente };
}

export function diaBolivia(fecha = Date.now()) {
  return new Date(fecha - 4 * 3600_000).toISOString().slice(0, 10);
}

export async function cifrar(texto: string, secreto: string) {
  const bytes = new TextEncoder().encode(secreto);
  if (bytes.length !== 32) throw new Error("La llave AES debe tener 32 bytes.");
  const key = await crypto.subtle.importKey("raw", bytes, "AES-CBC", false, ["encrypt"]);
  const iv = crypto.getRandomValues(new Uint8Array(16));
  const cifrado = new Uint8Array(await crypto.subtle.encrypt({ name: "AES-CBC", iv }, key, new TextEncoder().encode(texto)));
  const resultado = new Uint8Array(16 + cifrado.length);
  resultado.set(iv); resultado.set(cifrado, 16);
  return btoa(String.fromCharCode(...resultado));
}

export function estadoQr(r: Datos) {
  const codigo = r.statusQRCode ?? r.statusQrCode ?? r.statusQRcode;
  if (codigo === undefined || codigo === null || ![0, 1, 9].includes(Number(codigo))) throw new ErrorBanco("statusQR", "RESPUESTA_INVALIDA");
  return Number(codigo);
}

export function pagoQr(r: Datos, esperado: string): Datos {
  const pagos = Array.isArray(r.payment) ? r.payment : [r.payment];
  const candidatos = pagos.filter((p): p is Datos => !!p && typeof p === "object" && String(p.qrId ?? "") === esperado);
  if (candidatos.length !== 1 || !String(candidatos[0].transactionId ?? "").trim()) throw new ErrorBanco("statusQR", "IDENTIFICADOR_INVALIDO");
  return candidatos[0];
}

export class Banco {
  private token: { valor: string; vence: number } | null = null;
  private autenticando: Promise<string> | null = null;
  constructor(private env: Entorno, private pedir: typeof fetch = fetch, private ahora = Date.now) {}
  get config() { return configuracion(this.env); }
  private secreto(nombre: string) {
    const valor = this.env(nombre);
    if (!valor) throw new Error(`Falta configurar ${nombre}.`);
    return valor;
  }
  private async llamar(metodo: string, ruta: string, cuerpo?: Datos, token?: string): Promise<Datos> {
    let r: Response;
    try {
      r = await this.pedir(this.config.base + ruta, {
        method: metodo, headers: { "Content-Type": "application/json", Accept: "application/json", ...(token ? { Authorization: `Bearer ${token}` } : {}) },
        body: cuerpo === undefined ? undefined : JSON.stringify(cuerpo),
        signal: AbortSignal.timeout(8000), redirect: "error",
      });
    } catch { throw new ErrorBanco(ruta, "RED", metodo === "POST" && ruta.endsWith("generateQR")); }
    let data: Datos;
    try {
      data = await r.json();
      if (!data || typeof data !== "object" || Array.isArray(data)) throw new Error();
    } catch { throw new ErrorBanco(ruta, "JSON_INVALIDO", ruta.endsWith("generateQR")); }
    if (!r.ok) throw new ErrorBanco(ruta, r.status, ruta.endsWith("generateQR") && r.status >= 500);
    if (data.responseCode !== 0) throw new ErrorBanco(ruta, typeof data.responseCode === "number" ? data.responseCode : "CODIGO_INVALIDO",
      ruta.endsWith("generateQR") && typeof data.responseCode !== "number");
    return data;
  }
  async autenticar(): Promise<string> {
    const caduca = this.env("BANECO_CREDENTIALS_EXPIRES_AT");
    if ((this.config.ambiente === "produccion" && !caduca) || (caduca && (!Number.isFinite(Date.parse(caduca)) || this.ahora() >= Date.parse(caduca)))) throw new Error("Credenciales bancarias sin vigencia confirmada.");
    if (this.token && this.token.vence > this.ahora()) return this.token.valor;
    if (this.autenticando) return this.autenticando;
    this.autenticando = (async () => {
      const r = await this.llamar("POST", "/api/authentication/authenticate", {
        userName: this.secreto("BANECO_USER"), password: await cifrar(this.secreto("BANECO_PASSWORD"), this.secreto("BANECO_AES_KEY")),
      });
      if (typeof r.token !== "string" || !r.token) throw new ErrorBanco("autenticacion", "SIN_TOKEN");
      let vence = this.ahora() + 25 * 60_000;
      try {
        const payload = JSON.parse(atob(r.token.split(".")[1].replace(/-/g, "+").replace(/_/g, "/")));
        if (Number.isFinite(payload.exp)) vence = payload.exp * 1000 - 60_000;
      } catch { /* token opaco: caché de 25 minutos */ }
      this.token = { valor: r.token, vence };
      return r.token;
    })();
    try { return await this.autenticando; } finally { this.autenticando = null; }
  }
  private async autorizado(metodo: string, ruta: string, cuerpo?: Datos) {
    const token = await this.autenticar();
    try { return await this.llamar(metodo, ruta, cuerpo, token); }
    catch (e) {
      if (!(e instanceof ErrorBanco) || ![401, 403].includes(Number(e.codigo))) throw e;
      this.token = null;
      return await this.llamar(metodo, ruta, cuerpo, await this.autenticar());
    }
  }
  async prepararCuenta() { return await cifrar(this.secreto("BANECO_ACCOUNT"), this.secreto("BANECO_AES_KEY")); }
  async generar(q: Datos, cuenta: string) {
    const r = await this.autorizado("POST", "/api/qrsimple/generateQR", {
      transactionId: q.transaction_id, accountCredit: cuenta, currency: "BOB", amount: Number(q.monto),
      description: "Entrada AFTR", dueDate: q.vence, singleUse: true, modifyAmount: false,
    });
    if (!r.qrId || typeof r.qrImage !== "string" || !r.qrImage) throw new ErrorBanco("generateQR", "QR_INCOMPLETO", true);
    try { atob(r.qrImage); } catch { throw new ErrorBanco("generateQR", "IMAGEN_INVALIDA", true); }
    return { qrId: String(r.qrId), imagen: r.qrImage };
  }
  async estado(qrId: string) {
    const r = await this.autorizado("GET", `/api/qrsimple/v2/statusQR/${encodeURIComponent(qrId)}`);
    const estado = estadoQr(r);
    return { estado, pago: estado === 1 ? pagoQr(r, qrId) : undefined };
  }
  async pagados(dia: string) {
    if (!/^\d{4}-\d{2}-\d{2}$/.test(dia)) throw new Error("Fecha de conciliación inválida.");
    const r = await this.autorizado("GET", `/api/qrsimple/v2/paidQR/${dia.replaceAll("-", "")}`);
    if (!Array.isArray(r.paymentList)) throw new ErrorBanco("paidQR", "LISTA_INVALIDA");
    return r.paymentList as Datos[];
  }
  async anular(qrId: string) { await this.autorizado("DELETE", "/api/qrsimple/cancelQR", { qrId }); }
}
