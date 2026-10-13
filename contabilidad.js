/* ============================================================
   CONTABILIDAD · exportación del cierre a un libro de Excel
   ============================================================

   Genera un .xlsx real —no CSV— con hoja Resumen + una hoja por team,
   fórmulas vivas, hipervínculos de ida y vuelta y formato de reporte
   contable.

   QUIÉN PUEDE (decisión del dueño, 2026-08-21):
   · contabilidad GENERAL: sólo las cuentas con `profiles.contabilidad_total`
     (hoy @aqueirolo y @IpadQueirolo). Un admin sin la marca NO exporta —el
     caso de Horacio, que es rol='admin' igual que el iPad: el rol no
     alcanzaba para distinguirlos, por eso la marca.
   · cada JEFE de team: su propio team y nada más.
   · el resto: nada.
   El filtro REAL vive en la RPC `contabilidad_evento`
   (db/14-contabilidad-acceso.sql), que decide por auth.uid() del lado del
   servidor. Lo de acá sólo evita pedir en vano.

   ESTE LIBRO ES SOLO PUERTA. Cuenta prepagadas y lista INGRESADAS, y nada
   más. No hay mesas en ninguna parte: ni bloque, ni fórmula, ni nota, ni
   fila de control — decisión del dueño (2026-08-21).

   FÓRMULA CONTABLE · rige `liquidacion_evento` (la RPC de la base), en su
   parte de puerta:

     manillas_netas = manillas_usadas − manillas_externas
     por_manilla    = precio_manilla × pct_boliche / 100
     Rendición      = manillas_netas × por_manilla   (= total_manillas)
     Total a depositar = Rendición − Pago de Lista

   OJO al comparar contra la app: `liquidacion_evento.total_a_pagar` suma
   además las mesas, así que NO coincide con el total de este libro. Es a
   propósito: acá las mesas no existen.

   PREPAGADAS / LISTA · las mismas definiciones que ya usa la plataforma:
   · prepagadas = `v_stats_rrpp.entradas_usadas` (entradas sin mesa_id, en
     estado 'usada' — el que pone el escáner). Verificado: su suma da
     exactamente `manillas_usadas` de la RPC.
   · lista = `v_stats_rrpp.ingresaron` (registros con ingreso_at, que pone
     el check-in), igual que copyDesgloseTeam.

   PAGO DE LISTA · lista ingresada × precio de "Compra en Puerta"
   (lista_tipos.precio) × % del local. Sin precio cargado da 0, igual que
   hace el cierre de la app.
*/

/* Este archivo puede llegar por DOS caminos: el <script> del index, o el
   cargador de app.js cuando el index del hosting todavía no lo trae. Si
   entrara dos veces, los `const` de abajo tirarían "already declared" y el
   botón moriría — así que la segunda vez no hace nada. */
if (!window.__contabilidadCargada) {
window.__contabilidadCargada = true;

/* ExcelJS bajo demanda: no penaliza el arranque de la app. Se necesita un
   libro de verdad (fórmulas + estilos + hipervínculos), y SheetJS libre no
   escribe estilos. */
const EXCELJS_CDN = "https://cdn.jsdelivr.net/npm/exceljs@4.4.0/dist/exceljs.min.js";
let _excelPromise = null;
function cargarExcelJS() {
  if (window.ExcelJS) return Promise.resolve(window.ExcelJS);
  if (_excelPromise) return _excelPromise;
  _excelPromise = new Promise((ok, err) => {
    const s = document.createElement("script");
    s.src = EXCELJS_CDN;
    s.onload = () => window.ExcelJS ? ok(window.ExcelJS) : err(new Error("ExcelJS no se cargó"));
    s.onerror = () => { _excelPromise = null; err(new Error("No se pudo descargar ExcelJS (¿sin internet?)")); };
    document.head.appendChild(s);
  });
  return _excelPromise;
}

/* ---------- lenguaje visual ----------
   Paleta desaturada, de reporte impreso: el color marca la SECCIÓN, no
   decora. Un solo acento fuerte (dorado) reservado al total final, para
   que sea lo último que mira el ojo. */
const XC = {
  tinta:    "FF1F2933",   // texto principal
  suave:    "FF7B8794",   // texto secundario
  linea:    "FFD4DAE0",   // bordes finos
  lineaFte: "FF9AA5B1",   // bordes de sección
  cabecera: "FFEDF2F7",   // fondo de encabezados de tabla
  verde:    "FFEAF3E7",   // prepagadas
  gris:     "FFF2F4F6",   // lista
  ambar:    "FFFBF3DC",   // precios y %
  totalFila:"FFE6EBF0",   // fila TOTAL de la tabla
  acento:   "FFF5C542",   // total a depositar (único fuerte)
  acentoBd: "FFD9A404",
  cero:     "FFFFFFFF",
};
/* Un solo formato de moneda en todo el libro: "Bs 9.450,00".
   es-BO usa punto para miles y coma para decimales. */
const BS = '"Bs" #,##0.00';
const CANT = "#,##0";        // cantidades: sin decimales
const PCT = "0%";

const F = (size, opts = {}) => ({ name: "Calibri", size, color: { argb: XC.tinta }, ...opts });
const borde = (argb = XC.linea, style = "thin") => ({ style, color: { argb } });
const caja = (argb = XC.linea) => ({
  top: borde(argb), left: borde(argb), bottom: borde(argb), right: borde(argb),
});
const pintar = (celda, argb) => { celda.fill = { type: "pattern", pattern: "solid", fgColor: { argb } }; };

/* nombre de hoja válido: Excel prohíbe : \ / ? * [ ] y corta en 31 */
function nombreHoja(base, usados) {
  let n = String(base || "Team").replace(/[:\\/?*[\]]/g, "-").slice(0, 31).trim() || "Team";
  const orig = n;
  let i = 2;
  while (usados.has(n.toLowerCase())) { const suf = " (" + (i++) + ")"; n = orig.slice(0, 31 - suf.length) + suf; }
  usados.add(n.toLowerCase());
  return n;
}
const fechaArchivo = f => { const p = String(f).split("-"); return p[2] + "-" + p[1] + "-" + p[0]; };
const fechaTitulo  = f => { const p = String(f).split("-"); return p[2] + "/" + p[1] + "/" + p[0]; };

/* ---------- datos ----------
   Todo sale de las MISMAS fuentes que ya consume la app. No se inventa
   ninguna lectura nueva ni se toca ninguna lógica existente. */
async function reunirContabilidad(evento) {
  /* UNA sola llamada: `contabilidad_evento` decide del lado del SERVIDOR
     qué le toca a quien pide (total para las cuentas marcadas, sólo su
     team para un jefe, excepción para el resto). No se filtra acá: la
     vista v_stats_rrpp no es security_invoker, así que consultarla desde
     el navegador le entregaría a un jefe las filas de todos los teams
     aunque después las escondiéramos. Ver db/14-contabilidad-acceso.sql. */
  const { data, error } = await sb.rpc("contabilidad_evento", { p_evento: evento.id });
  if (error) throw new Error(error.message || "No autorizado para exportar la contabilidad");
  if (!data) throw new Error("La contabilidad del evento vino vacía");

  const L = data.liq || {};
  const grupos = new Map();
  for (const r of data.filas || []) {
    const pre = +r.prepagadas || 0, lis = +r.lista || 0;
    if (!pre && !lis) continue;                    // sin actividad no entra al libro
    const key = r.team_id || "__sin__";
    if (!grupos.has(key)) {
      const base = r.team || (r.team_id ? "Team" : "Sin team");
      grupos.set(key, {
        nombre: !r.team_id ? base : (/^team/i.test(base) ? base : "Team " + base),
        jefe: r.jefe || "",
        rrpps: [],
      });
    }
    grupos.get(key).rrpps.push({ nombre: r.rrpp || "?", pre, lis });
  }
  for (const g of grupos.values())
    g.rrpps.sort((a, b) => (b.pre + b.lis) - (a.pre + a.lis) || a.nombre.localeCompare(b.nombre));
  const lista = [...grupos.values()].sort((a, b) =>
    b.rrpps.reduce((s, x) => s + x.pre, 0) - a.rrpps.reduce((s, x) => s + x.pre, 0));

  return { L, teams: lista, alcance: data.alcance, teamNombre: data.team };
}

/* ---------- libro ---------- */
async function construirLibro(evento, clubNombre, datos) {
  const ExcelJS = await cargarExcelJS();
  const { L, teams } = datos;
  const wb = new ExcelJS.Workbook();
  wb.creator = "Venue";
  wb.created = new Date();

  const precioManilla = +L.precio_manilla || 0;
  const porManilla    = +L.por_manilla || 0;            // precio × pct_boliche/100
  const externas      = +L.manillas_externas || 0;
  const pctBoliche    = precioManilla > 0 ? porManilla / precioManilla : 0;
  const precioLista   = +datos.precioLista || 0;

  const usados = new Set();
  const R = wb.addWorksheet("Resumen", {
    views: [{ showGridLines: false }],
    pageSetup: {
      paperSize: 9, orientation: "landscape", fitToPage: true, fitToWidth: 1, fitToHeight: 0,
      horizontalCentered: true,
      margins: { left: .5, right: .5, top: .6, bottom: .6, header: .3, footer: .3 },
    },
  });
  /* A vacía = margen izquierdo. El contenido vive en B..H. */
  R.columns = [
    { width: 2.5 },  // A margen
    { width: 30 },   // B team
    { width: 13 },   // C prepagadas
    { width: 13 },   // D lista
    { width: 17 },   // E importe prepago
    { width: 17 },   // F importe lista
    { width: 15 },   // G ver desglose
    { width: 2.5 },  // H margen derecho
  ];

  /* ============ ENCABEZADO ============
     El título manda; la fecha va debajo y el evento aún más discreto. */
  R.mergeCells("B2:G2");
  const t = R.getCell("B2");
  t.value = "Contabilidad " + clubNombre;
  t.font = F(22, { bold: true });
  t.alignment = { horizontal: "left", vertical: "middle" };
  R.getRow(2).height = 32;

  R.mergeCells("B3:G3");
  const fe = R.getCell("B3");
  fe.value = fechaTitulo(evento.fecha);
  fe.font = F(12, { color: { argb: XC.suave } });
  fe.alignment = { horizontal: "left", vertical: "middle" };
  R.getRow(3).height = 18;

  R.mergeCells("B4:G4");
  const sub = R.getCell("B4");
  sub.value = evento.nombre + " · solo ingresados";
  sub.font = F(10, { color: { argb: XC.suave } });
  sub.alignment = { horizontal: "left", vertical: "middle" };
  R.getRow(4).height = 16;

  /* filete bajo el encabezado */
  for (const c of ["B", "C", "D", "E", "F", "G"])
    R.getCell(c + "5").border = { bottom: borde(XC.lineaFte, "medium") };
  R.getRow(5).height = 6;

  /* ============ PARÁMETROS DEL EVENTO ============
     Precios y % viven acá, cada uno en SU celda, y todas las fórmulas del
     libro las apuntan. Cambiar una recalcula todo. */
  /* Tres filas: rótulo de sección, etiquetas, valores. El rótulo NO se
     mergea sobre las columnas de etiquetas — si se mergea la misma fila
     donde después se escriben C/D/E, el merge las tapa y quedan invisibles. */
  const PAR = 7;                            // "PARÁMETROS"
  const PET = PAR + 1;                      // etiquetas
  const P1  = PAR + 2;                      // valores
  const ph = R.getCell("B" + PAR);
  ph.value = "PARÁMETROS";
  ph.font = F(9, { bold: true, color: { argb: XC.suave } });
  ph.alignment = { horizontal: "left", vertical: "middle" };
  R.getRow(PAR).height = 16;

  const params = [
    ["C", "Precio prepago", precioManilla, BS,  XC.ambar],
    ["D", "Precio lista",   precioLista,   BS,  XC.ambar],
    ["E", "% Local",        pctBoliche,    PCT, XC.ambar],
  ];
  const vl = R.getCell("B" + P1);
  vl.value = "Valores del evento";
  vl.font = F(10, { color: { argb: XC.suave } });
  vl.alignment = { horizontal: "left", vertical: "middle" };
  for (const [col, etiqueta, valor, fmt, bg] of params) {
    const et = R.getCell(col + PET);
    et.value = etiqueta;
    et.font = F(9, { bold: true, color: { argb: XC.suave } });
    et.alignment = { horizontal: "center", vertical: "middle" };
    const ce = R.getCell(col + P1);
    ce.value = valor;
    ce.numFmt = fmt;
    ce.font = F(11, { bold: true });
    ce.alignment = { horizontal: "center", vertical: "middle" };
    ce.border = caja();
    pintar(ce, bg);
  }
  R.getRow(PET).height = 16;
  R.getRow(P1).height = 22;
  const CEL_PRE = "$C$" + P1, CEL_LIS = "$D$" + P1, CEL_PCT = "$E$" + P1;

  /* ============ TABLA PRINCIPAL ============ */
  const HDR = P1 + 3;
  const th = R.getCell("B" + (HDR - 1));
  th.value = "DETALLE POR TEAM";
  th.font = F(9, { bold: true, color: { argb: XC.suave } });
  th.alignment = { horizontal: "left", vertical: "middle" };
  R.getRow(HDR - 1).height = 18;

  const cols = [
    ["B", "Team",            "left"],
    ["C", "Prepagadas",      "center"],
    ["D", "Lista",           "center"],
    ["E", "Importe prepago", "right"],
    ["F", "Importe lista",   "right"],
    ["G", "",                "center"],
  ];
  for (const [c, etiqueta, al] of cols) {
    const cel = R.getCell(c + HDR);
    cel.value = etiqueta;
    cel.font = F(10, { bold: true });
    cel.alignment = { horizontal: al === "right" ? "right" : al, vertical: "middle", wrapText: false };
    cel.border = { top: borde(XC.lineaFte), bottom: borde(XC.lineaFte) };
    pintar(cel, XC.cabecera);
  }
  R.getRow(HDR).height = 24;

  const fila0 = HDR + 1;
  const hojas = [];
  teams.forEach((g, i) => {
    const nom = nombreHoja(g.nombre, usados);
    hojas.push({ nombre: g.nombre, jefe: g.jefe, rrpps: g.rrpps, hoja: nom });
    const f = fila0 + i;
    const ref = "'" + nom + "'";
    const desde = 6, hasta = 6 + Math.max(g.rrpps.length, 1) - 1;   // filas de datos en la hoja del team

    R.getCell("B" + f).value = g.nombre;
    R.getCell("B" + f).font = F(11);
    R.getCell("B" + f).alignment = { horizontal: "left", vertical: "middle" };

    R.getCell("C" + f).value = { formula: "SUM(" + ref + "!C" + desde + ":C" + hasta + ")" };
    R.getCell("D" + f).value = { formula: "SUM(" + ref + "!D" + desde + ":D" + hasta + ")" };
    /* parte del LOCAL: cantidad × precio × % */
    R.getCell("E" + f).value = { formula: "C" + f + "*" + CEL_PRE + "*" + CEL_PCT };
    R.getCell("F" + f).value = { formula: "D" + f + "*" + CEL_LIS + "*" + CEL_PCT };

    const vd = R.getCell("G" + f);
    vd.value = { text: "Ver desglose  ›", hyperlink: "#'" + nom + "'!A1" };
    vd.font = F(10, { color: { argb: "FF2A6FB5" }, underline: false });
    vd.alignment = { horizontal: "center", vertical: "middle" };

    for (const [c] of cols) {
      const cel = R.getCell(c + f);
      cel.border = { bottom: borde(XC.linea) };
      if (!cel.alignment) cel.alignment = { horizontal: "center", vertical: "middle" };
    }
    R.getCell("C" + f).numFmt = CANT;
    R.getCell("D" + f).numFmt = CANT;
    R.getCell("C" + f).alignment = { horizontal: "center", vertical: "middle" };
    R.getCell("D" + f).alignment = { horizontal: "center", vertical: "middle" };
    pintar(R.getCell("C" + f), XC.verde);
    pintar(R.getCell("D" + f), XC.gris);
    R.getCell("E" + f).numFmt = BS;
    R.getCell("F" + f).numFmt = BS;
    R.getCell("E" + f).alignment = { horizontal: "right", vertical: "middle" };
    R.getCell("F" + f).alignment = { horizontal: "right", vertical: "middle" };
    R.getRow(f).height = 20;
  });

  const filaFin = fila0 + Math.max(teams.length, 1) - 1;

  /* --- TOTAL de la tabla --- */
  const FT = filaFin + 1;
  R.getCell("B" + FT).value = "TOTAL";
  ["C", "D", "E", "F"].forEach(c =>
    R.getCell(c + FT).value = { formula: "SUM(" + c + fila0 + ":" + c + filaFin + ")" });
  for (const [c, , al] of cols) {
    const cel = R.getCell(c + FT);
    cel.font = F(11, { bold: true });
    cel.alignment = { horizontal: al === "right" ? "right" : al, vertical: "middle" };
    cel.border = { top: borde(XC.lineaFte), bottom: borde(XC.lineaFte, "medium") };
    pintar(cel, XC.totalFila);
  }
  R.getCell("C" + FT).numFmt = CANT;
  R.getCell("D" + FT).numFmt = CANT;
  R.getCell("E" + FT).numFmt = BS;
  R.getCell("F" + FT).numFmt = BS;
  R.getRow(FT).height = 24;

  /* ============ AJUSTES ============ */
  const AJ = FT + 2;
  const ah = R.getCell("B" + AJ);
  ah.value = "AJUSTES";
  ah.font = F(9, { bold: true, color: { argb: XC.suave } });
  ah.alignment = { horizontal: "left", vertical: "middle" };
  R.getRow(AJ).height = 18;

  const FEX = AJ + 1;
  R.mergeCells("B" + FEX + ":D" + FEX);
  const ex = R.getCell("B" + FEX);
  ex.value = "Manillas de externos (se descuentan)";
  ex.font = F(10);
  ex.alignment = { horizontal: "left", vertical: "middle" };
  ex.border = { bottom: borde(XC.linea) };
  const exv = R.getCell("E" + FEX);
  exv.value = externas;
  exv.numFmt = CANT;
  exv.font = F(11);
  exv.alignment = { horizontal: "right", vertical: "middle" };
  exv.border = { bottom: borde(XC.linea) };
  R.getCell("F" + FEX).border = { bottom: borde(XC.linea) };
  R.getCell("G" + FEX).border = { bottom: borde(XC.linea) };
  R.getRow(FEX).height = 20;

  /* ============ CIERRE ============ */
  const CIE = FEX + 2;
  const ch = R.getCell("B" + CIE);
  ch.value = "CIERRE";
  ch.font = F(9, { bold: true, color: { argb: XC.suave } });
  ch.alignment = { horizontal: "left", vertical: "middle" };
  R.getRow(CIE).height = 18;

  /* una línea de cierre: etiqueta + importe (fórmula) + nota discreta */
  let f = CIE + 1;
  const linea = (etiqueta, formula, nota) => {
    R.mergeCells("B" + f + ":D" + f);
    const a = R.getCell("B" + f);
    a.value = etiqueta;
    a.font = F(11);
    a.alignment = { horizontal: "left", vertical: "middle" };
    a.border = { bottom: borde(XC.linea) };
    const v = R.getCell("E" + f);
    v.value = { formula };
    v.numFmt = BS;
    v.font = F(11, { bold: true });
    v.alignment = { horizontal: "right", vertical: "middle" };
    v.border = { bottom: borde(XC.linea) };
    R.getCell("F" + f).border = { bottom: borde(XC.linea) };
    const n = R.getCell("G" + f);
    if (nota) {
      n.value = nota;
      n.font = F(8, { italic: true, color: { argb: XC.suave } });
      n.alignment = { horizontal: "left", vertical: "middle" };
    }
    n.border = { bottom: borde(XC.linea) };
    R.getRow(f).height = 20;
    const usada = f;
    f += 1;
    return usada;
  };

  const fRend = linea("Rendición manillas",
    "MAX(C" + FT + "-E" + FEX + ",0)*" + CEL_PRE + "*" + CEL_PCT,
    "(prepagadas − externos) × precio × %");
  const fLista = linea("Pago de Lista",
    "D" + FT + "*" + CEL_LIS + "*" + CEL_PCT,
    precioLista ? "lista × precio × %" : "sin precio de lista ⇒ 0");

  /* --- TOTAL A DEPOSITAR · el foco de la hoja --- */
  f += 1;
  const FD = f;
  R.mergeCells("B" + FD + ":D" + FD);
  const td = R.getCell("B" + FD);
  td.value = "TOTAL A DEPOSITAR A " + clubNombre.toUpperCase();
  td.font = F(14, { bold: true });
  td.alignment = { horizontal: "left", vertical: "middle" };
  td.border = { top: borde(XC.acentoBd, "medium"), bottom: borde(XC.acentoBd, "medium"), left: borde(XC.acentoBd, "medium") };
  pintar(td, XC.acento);

  R.mergeCells("E" + FD + ":F" + FD);
  const tv = R.getCell("E" + FD);
  tv.value = { formula: "E" + fRend + "-E" + fLista };
  tv.numFmt = BS;
  tv.font = F(16, { bold: true });
  tv.alignment = { horizontal: "right", vertical: "middle" };
  tv.border = { top: borde(XC.acentoBd, "medium"), bottom: borde(XC.acentoBd, "medium"), right: borde(XC.acentoBd, "medium") };
  pintar(tv, XC.acento);
  R.getRow(FD).height = 34;

  const nd = R.getCell("G" + FD);
  nd.value = "Rendición − Pago de Lista";
  nd.font = F(8, { italic: true, color: { argb: XC.suave } });
  nd.alignment = { horizontal: "left", vertical: "middle" };

  /* pie */
  const PIE = FD + 2;
  R.mergeCells("B" + PIE + ":G" + PIE);
  const pie = R.getCell("B" + PIE);
  pie.value = "Venue · " + evento.nombre + " · " + clubNombre + " · " + fechaTitulo(evento.fecha) +
              " — cuenta únicamente a quienes ingresaron.";
  pie.font = F(8, { italic: true, color: { argb: XC.suave } });
  pie.alignment = { horizontal: "left", vertical: "middle" };

  R.pageSetup.printArea = "B1:G" + PIE;

  /* ============ HOJAS POR TEAM ============ */
  for (const g of hojas) {
    const ws = wb.addWorksheet(g.hoja, {
      views: [{ showGridLines: false, state: "frozen", ySplit: 5 }],
      pageSetup: {
        paperSize: 9, orientation: "portrait", fitToPage: true, fitToWidth: 1, fitToHeight: 0,
        horizontalCentered: true,
        margins: { left: .5, right: .5, top: .6, bottom: .6, header: .3, footer: .3 },
      },
    });
    ws.columns = [
      { width: 2.5 },  // A margen
      { width: 30 },   // B relacionador
      { width: 13 },   // C prepagadas
      { width: 13 },   // D lista
      { width: 17 },   // E importe prepago
      { width: 17 },   // F importe lista
      { width: 17 },   // G total
      { width: 2.5 },  // H margen
    ];

    ws.mergeCells("B2:G2");
    const th2 = ws.getCell("B2");
    th2.value = g.nombre;
    th2.font = F(18, { bold: true });
    th2.alignment = { horizontal: "left", vertical: "middle" };
    ws.getRow(2).height = 28;

    ws.mergeCells("B3:G3");
    const sub2 = ws.getCell("B3");
    sub2.value = (g.jefe ? "Jefe: " + g.jefe + "  ·  " : "") +
                 evento.nombre + "  ·  " + clubNombre + "  ·  " + fechaTitulo(evento.fecha);
    sub2.font = F(10, { color: { argb: XC.suave } });
    sub2.alignment = { horizontal: "left", vertical: "middle" };
    ws.getRow(3).height = 18;

    const back = ws.getCell("B4");
    back.value = { text: "‹  Volver al Resumen", hyperlink: "#Resumen!A1" };
    back.font = F(10, { color: { argb: "FF2A6FB5" } });
    back.alignment = { horizontal: "left", vertical: "middle" };
    ws.getRow(4).height = 18;

    const colsT = [
      ["B", "Relacionador",    "left"],
      ["C", "Prepagadas",      "center"],
      ["D", "Lista",           "center"],
      ["E", "Importe prepago", "right"],
      ["F", "Importe lista",   "right"],
      ["G", "Total",           "right"],
    ];
    for (const [c, etiqueta, al] of colsT) {
      const cel = ws.getCell(c + "5");
      cel.value = etiqueta;
      cel.font = F(10, { bold: true });
      cel.alignment = { horizontal: al === "right" ? "right" : al, vertical: "middle" };
      cel.border = { top: borde(XC.lineaFte), bottom: borde(XC.lineaFte) };
      pintar(cel, XC.cabecera);
    }
    ws.getRow(5).height = 24;

    g.rrpps.forEach((p, i) => {
      const r = 6 + i;
      ws.getCell("B" + r).value = p.nombre;
      ws.getCell("B" + r).font = F(11);
      ws.getCell("B" + r).alignment = { horizontal: "left", vertical: "middle" };
      ws.getCell("C" + r).value = p.pre;
      ws.getCell("D" + r).value = p.lis;
      ws.getCell("E" + r).value = { formula: "C" + r + "*Resumen!" + CEL_PRE + "*Resumen!" + CEL_PCT };
      ws.getCell("F" + r).value = { formula: "D" + r + "*Resumen!" + CEL_LIS + "*Resumen!" + CEL_PCT };
      ws.getCell("G" + r).value = { formula: "E" + r + "+F" + r };
      for (const [c] of colsT) ws.getCell(c + r).border = { bottom: borde(XC.linea) };
      ["C", "D"].forEach(c => {
        ws.getCell(c + r).numFmt = CANT;
        ws.getCell(c + r).alignment = { horizontal: "center", vertical: "middle" };
      });
      pintar(ws.getCell("C" + r), XC.verde);
      pintar(ws.getCell("D" + r), XC.gris);
      ["E", "F", "G"].forEach(c => {
        ws.getCell(c + r).numFmt = BS;
        ws.getCell(c + r).alignment = { horizontal: "right", vertical: "middle" };
      });
      ws.getRow(r).height = 20;
    });

    const ult = 6 + Math.max(g.rrpps.length, 1) - 1, tf = ult + 1;
    ws.getCell("B" + tf).value = "TOTAL " + g.nombre;
    ["C", "D", "E", "F", "G"].forEach(c =>
      ws.getCell(c + tf).value = { formula: "SUM(" + c + "6:" + c + ult + ")" });
    for (const [c, , al] of colsT) {
      const cel = ws.getCell(c + tf);
      cel.font = F(11, { bold: true });
      cel.alignment = { horizontal: al === "right" ? "right" : al, vertical: "middle" };
      cel.border = { top: borde(XC.lineaFte), bottom: borde(XC.lineaFte, "medium") };
      pintar(cel, XC.totalFila);
    }
    ["C", "D"].forEach(c => ws.getCell(c + tf).numFmt = CANT);
    ["E", "F", "G"].forEach(c => ws.getCell(c + tf).numFmt = BS);
    ws.getRow(tf).height = 24;

    const pie2 = ws.getCell("B" + (tf + 2));
    pie2.value = "Importes = parte del local (cantidad × precio × %). Solo ingresados.";
    pie2.font = F(8, { italic: true, color: { argb: XC.suave } });
    ws.pageSetup.printArea = "B1:G" + (tf + 2);
  }

  return wb;
}

/* ---------- quién ve el botón ----------
   `contabilidad_total` es la marca de la base (hoy: @aqueirolo y
   @IpadQueirolo). Un admin sin la marca —Horacio— NO exporta. Los jefes
   sí, pero la RPC les devuelve únicamente su team. */
function puedeExportarContabilidad() {
  return !!(me && (me.contabilidad_total === true || me.rol === "jefe"));
}

/* ---------- acción del botón ---------- */
async function exportarContabilidadExcel() {
  /* Quién puede: las cuentas con contabilidad_total (general) y los jefes
     (sólo su team). Esta guarda es cortesía para no pedir en vano — la
     REAL vive en contabilidad_evento, que filtra por auth.uid() del lado
     del servidor y tira excepción a quien no corresponde. */
  if (!puedeExportarContabilidad()) return toast("No autorizado", "warn");
  if (!ev) return toast("No hay evento activo", "warn");

  const btn = $("#btnExcel");
  const etiqueta = btn ? btn.textContent : "";
  if (btn) { btn.disabled = true; btn.textContent = "Generando contabilidad…"; }
  toast("Generando contabilidad…");
  try {
    const clubNombre = clubData(club)?.nombre || club;
    const datos = await reunirContabilidad(ev);
    /* precio de lista con el MISMO criterio que el cierre de la app */
    const pue = await contarPuertaIngresada(listaPuertaDe(listaTipos));
    datos.precioLista = +pue.precio || 0;

    const wb = await construirLibro(ev, clubNombre, datos);
    const buf = await wb.xlsx.writeBuffer();
    if (!buf || !buf.byteLength) throw new Error("El libro salió vacío");

    const blob = new Blob([buf], {
      type: "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
    });
    const url = URL.createObjectURL(blob);
    const a = document.createElement("a");
    a.href = url;
    const suf = datos.alcance === "team" && datos.teamNombre
      ? "_" + String(datos.teamNombre).replace(/[^wsáéíóúñÁÉÍÓÚÑ-]/g, "").trim().replace(/s+/g, "-")
      : "";
    a.download = "Contabilidad_" + clubNombre + suf + "_" + fechaArchivo(ev.fecha) + ".xlsx";
    document.body.appendChild(a);
    a.click();
    a.remove();
    setTimeout(() => URL.revokeObjectURL(url), 4000);
    toast("Excel generado correctamente");
  } catch (e) {
    console.error(e);
    toast(e.message || "No se pudo generar el Excel", "warn");
  } finally {
    if (btn) { btn.disabled = false; btn.textContent = etiqueta || "Exportar contabilidad Excel"; }
  }
}

/* Dentro del if de arriba las `function` quedan en el ámbito del bloque:
   se publican para que app.js (y la suite) las vean. */
window.exportarContabilidadExcel = exportarContabilidadExcel;
window.puedeExportarContabilidad = puedeExportarContabilidad;
window.reunirContabilidad = reunirContabilidad;
window.construirLibro = construirLibro;

}   /* fin del guard __contabilidadCargada */
