// Flujos reales de la web contra el demo, con un navegador de verdad.
// Uso: (cd tools/web && npm i playwright-core@1.56.0) y con `node dev.mjs 5173`
// corriendo: node tools/web/flujos.mjs  · Solo lee: no escribe en la base.
import { chromium } from "playwright-core";
const BASE = "http://localhost:5173", OUT = "flujos";
import { mkdirSync } from "node:fs"; mkdirSync(OUT, { recursive: true });
const b = await chromium.launch({ channel: "chrome", headless: true });
let fallas = 0;
const ok = (c, m) => { console.log((c ? "✓ " : "✗ ") + m); if (!c) fallas++; };
async function entrar(rol, w = 390) {
  const ctx = await b.newContext({ viewport: { width: w, height: 844 }, deviceScaleFactor: 2 });
  const p = await ctx.newPage(); const errs = [];
  p.on("console", m => { if (m.type() === "error" || /GSAP/.test(m.text())) errs.push(m.text().slice(0, 200)); });
  p.on("pageerror", e => errs.push(String(e)));
  await p.goto(BASE, { waitUntil: "networkidle" });
  await p.fill("#lgUser", rol); await p.fill("#lgPass", "Venue2026!"); await p.click("#btnLogin");
  await p.waitForFunction(() => document.querySelector("#clubPick:not(.hidden) [data-cp]") || document.querySelectorAll("#tabbar button").length, null, { timeout: 15000 });
  const cp = p.locator("#clubPick:not(.hidden) [data-cp]").first();
  if (await cp.count()) await cp.click();
  await p.waitForTimeout(2500);
  for (const sel of ["#avOk", "#telLuego"]) { const x = p.locator(sel); if (await x.count() && await x.isVisible()) { await x.click(); await p.waitForTimeout(500); } }
  await p.waitForTimeout(1500);
  const hoja = await p.evaluate(() => document.querySelector("#sheet.open") ? document.querySelector("#sheetBody").innerText.slice(0, 80) : "");
  if (hoja) { console.log("  (hoja al entrar: " + hoja.replace(/\n/g, " ") + ")"); await p.evaluate(() => closeSheet()); await p.waitForTimeout(300); }
  return { p, ctx, errs };
}

// 1 · clave equivocada: error y sacudida, sin excepción
{
  const ctx = await b.newContext({ viewport: { width: 390, height: 844 } }); const p = await ctx.newPage();
  const errs = []; p.on("pageerror", e => errs.push(String(e)));
  await p.goto(BASE, { waitUntil: "networkidle" });
  await p.fill("#lgUser", "admin.aurora"); await p.fill("#lgPass", "mal"); await p.click("#btnLogin");
  await p.waitForSelector("#loginErr .err", { timeout: 10000 });
  ok(/incorrectos/.test(await p.textContent("#loginErr")) && !errs.length, "login con clave mala muestra el error");
  await ctx.close();
}

// 2 · portero: código inexistente en el escáner → NO PASA
{
  const { p, ctx, errs } = await entrar("portero.aurora");
  await p.evaluate(() => irATab("escaner")); await p.waitForTimeout(1200);
  await p.fill("#scanCode", "ZZZZZZZZZZ"); await p.click("#btnVal");
  await p.waitForSelector("#scanResult .res", { timeout: 10000 }); await p.waitForTimeout(400);
  const t = await p.textContent("#scanResult");
  ok(/NO PASA/.test(t), "escáner: código inexistente → NO PASA");
  await p.screenshot({ path: `${OUT}/escaner-nopasa.png` });
  ok(!errs.length, "portero sin errores de consola " + errs.join(" | "));
  await ctx.close();
}

// 3 · sin módulo de Pagos; plano de mesas con zoom y mesas que se tocan
{
  const { p, ctx, errs } = await entrar("rrpp.aurora");
  const tabs = await p.$$eval("#tabbar [data-t], #botnav [data-t]", bs => bs.map(b => b.dataset.t));
  ok(!tabs.includes("pagos"), `rrpp sin Pagos en la navegación (${[...new Set(tabs)].join(", ")})`);
  await p.evaluate(() => irATab("mesas")); await p.waitForSelector("#cv2 .chip", { timeout: 15000 }); await p.waitForTimeout(900);
  const z0 = await p.$eval("#cv2", c => c.style.getPropertyValue("--z"));
  const w0 = await p.$eval("#cv2", c => c.getBoundingClientRect().width);
  await p.click('[data-zoom="1"]'); await p.waitForTimeout(300);
  const w1 = await p.$eval("#cv2", c => c.getBoundingClientRect().width);
  ok(w1 > w0, `zoom +: el plano pasa de ${Math.round(w0)} a ${Math.round(w1)} px (arrancó en ${z0})`);
  await p.click('[data-zoom="0"]'); await p.waitForTimeout(300);
  const w2 = await p.$eval("#cv2", c => c.getBoundingClientRect().width), ww = await p.$eval("#cvWrap", c => c.clientWidth);
  ok(Math.abs(w2 - ww) < 4, "ajustar: el plano entra justo en el ancho");
  await p.locator("#cv2 .chip").first().click(); await p.waitForTimeout(800);
  ok(await p.evaluate(() => !!document.querySelector("#sheet.open")), "tocar una mesa abre su hoja");
  await p.screenshot({ path: `${OUT}/mesa-hoja.png` });
  ok(!errs.length, "rrpp sin errores de consola " + errs.join(" | "));
  await ctx.close();
}

// 4 · admin: hoja de Auditoría desde el Reporte, con filtro
for (const w of [390, 1440]) {
  const { p, ctx, errs } = await entrar("admin.aurora", w);
  await p.evaluate(() => irATab("stats")); await p.waitForTimeout(2200);
  await p.click("#rpMas"); await p.waitForTimeout(500);
  await p.click('[data-rpop="audit"]');
  await p.waitForSelector("#audLista .aud-row", { timeout: 15000 }); await p.waitForTimeout(600);
  const n = await p.locator("#audLista .aud-row").count();
  ok(n > 0, `auditoría (${w}px) lista ${n} movimientos`);
  await p.screenshot({ path: `${OUT}/auditoria-${w}.png` });
  await p.click('[data-aud="pagos"]'); await p.waitForTimeout(2000);
  const tipos = await p.$$eval("#audLista .aud-row", rs => rs.map(r => r.textContent.trim().split(/\s/)[0]));
  ok(tipos.length && tipos.every(t => t === "Pago"), `filtro Pagos (${tipos.length} filas, todas de pagos)`);
  await p.screenshot({ path: `${OUT}/auditoria-pagos-${w}.png` });
  ok(!errs.length, "admin sin errores de consola " + errs.join(" | "));
  await ctx.close();
}

// 5 · rrpp no puede leer la auditoría (RLS), aunque llame directo
{
  const { p, ctx } = await entrar("rrpp.aurora");
  const n = await p.evaluate(async () => (await sb.from("audit_log").select("id").limit(5)).data?.length ?? -1);
  ok(n === 0, `rrpp leyendo audit_log por la API obtiene ${n} filas`);
  await ctx.close();
}
await b.close();
console.log(fallas ? `${fallas} falla(s)` : "Todos los flujos OK");
process.exit(fallas ? 1 : 0);
