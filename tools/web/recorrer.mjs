// Recorre la web con un navegador real, entrando con cada rol.
// Uso: (cd tools/web && npm i playwright-core@1.56.0), `node dev.mjs 5173` y
//      node tools/web/recorrer.mjs [base] [dirCapturas] [roles separados por coma]
// REDUCIR=1 lo corre con prefers-reduced-motion. Usa el Chrome instalado.
import { chromium } from "playwright-core";
import { mkdirSync } from "node:fs";

const BASE = process.argv[2] || "http://localhost:5173";
const OUT = process.argv[3] || "capturas";
const SOLO = (process.argv[4] || "").split(",").filter(Boolean);
const CLAVE = "Venue2026!";
const ROLES = ["superadmin", "admin.aurora", "jefe.aurora", "rrpp.aurora", "portero.aurora",
  "caja.aurora", "propietario.aurora", "barra.aurora", "deposito.aurora"].filter(r => !SOLO.length || SOLO.includes(r));
mkdirSync(OUT, { recursive: true });

const browser = await chromium.launch({ channel: "chrome", headless: true });
let fallas = 0;
for (const rol of ROLES) {
  for (const [nombre, vp] of [["movil", { width: 390, height: 844 }], ["escritorio", { width: 1440, height: 900 }]]) {
    const ctx = await browser.newContext({ viewport: vp, deviceScaleFactor: 2, reducedMotion: process.env.REDUCIR ? "reduce" : "no-preference" });
    const page = await ctx.newPage();
    const errores = [];
    page.on("console", m => { if (m.type() === "error" || /GSAP/.test(m.text())) errores.push(m.text().slice(0, 220)); });
    page.on("pageerror", e => errores.push("EXCEPCIÓN " + String(e).slice(0, 220)));
    await page.goto(BASE, { waitUntil: "networkidle" });
    if (rol === ROLES[0] && nombre === "movil") await page.screenshot({ path: `${OUT}/login-${nombre}.png` });
    await page.fill("#lgUser", rol); await page.fill("#lgPass", CLAVE); await page.click("#btnLogin");
    await page.waitForFunction(() => document.querySelector("#clubPick:not(.hidden) [data-cp]") || document.querySelectorAll("#tabbar button").length, null, { timeout: 15000 }).catch(() => {});
    await page.waitForTimeout(900);
    // selector de boliche (los que tienen más de uno)
    const cp = page.locator("#clubPick:not(.hidden) [data-cp]").first();
    if (await cp.count()) {
      if (nombre === "movil") await page.screenshot({ path: `${OUT}/${rol}-boliches.png` });
      await cp.click(); await page.waitForTimeout(2200);
    }
    // avisos / pedido de teléfono que tapen la pantalla
    for (const sel of ["#avOk", "#telLuego"]) { const b = page.locator(sel); if (await b.count() && await b.isVisible()) { await b.click(); await page.waitForTimeout(500); } }
    await page.waitForFunction(() => document.querySelectorAll("#tabbar button").length, null, { timeout: 10000 }).catch(() => {});
    const tabs = await page.evaluate(() => [...document.querySelectorAll("#tabbar button[data-t]")].map(b => [b.dataset.t, b.textContent.trim()]));
    const visto = [];
    for (const [t, etiqueta] of tabs) {
      await page.evaluate(x => irATab(x), t);
      await page.waitForTimeout(1900);
      const roto = await page.evaluate(() => /No pudimos cargar esta sección/.test(document.querySelector("#main")?.innerText || ""));
      const cargando = await page.evaluate(() => !!document.querySelector("#main .sk-wrap"));
      if (roto || cargando) { fallas++; errores.push(`SECCIÓN ${t}: ${roto ? "no cargó" : "quedó cargando"}`); }
      visto.push(etiqueta + (roto ? "✗" : cargando ? "…" : "✓"));
      await page.screenshot({ path: `${OUT}/${rol}-${t}-${nombre}.png`, fullPage: false });
    }
    // accesos de "Más": cada uno abre su hoja con contenido real
    const extras = await page.evaluate(() => [...document.querySelectorAll("#tabbar button[data-x]")].map(b => b.dataset.x));
    for (const x of extras) {
      await page.evaluate(k => document.querySelector(`#tabbar [data-x="${k}"]`).click(), x);
      await page.waitForTimeout(1800);
      // "Usuarios y equipos" es una pantalla completa; el resto, hojas
      const h = await page.evaluate(() => document.querySelector("#sheet.open")
        ? { abierta: true, txt: document.querySelector("#sheetBody").innerText }
        : { abierta: !document.querySelector("#main .sk-wrap") && !!document.querySelector("#main")?.innerText.trim(), txt: document.querySelector("#main")?.innerText || "" });
      const malo = !h.abierta || /\$\{|undefined|No pudimos/.test(h.txt);
      if (malo) { fallas++; errores.push(`MÁS ${x}: ${h.abierta ? h.txt.slice(0, 80) : "no abrió"}`); }
      visto.push("+" + x + (malo ? "✗" : "✓"));
      if (nombre === "movil") await page.screenshot({ path: `${OUT}/${rol}-mas-${x}.png` });
      await page.evaluate(() => closeSheet()); await page.waitForTimeout(300);
    }
    // texto de plantilla sin resolver en cualquier pantalla
    const crudo = await page.evaluate(() => /\$\{ico/.test(document.body.innerHTML));
    if (crudo) { fallas++; errores.push("hay ${ico(...)} sin resolver en la página"); }
    const st = await page.evaluate(() => window.ScrollTrigger ? ScrollTrigger.getAll().length : -1);
    const huerf = await page.evaluate(() => window.ScrollTrigger ? ScrollTrigger.getAll().filter(t => t.trigger && !t.trigger.isConnected).length : 0);
    const ocultos = await page.evaluate(() => [...document.querySelectorAll("#main *")].filter(e => e.style.visibility === "hidden").length);
    if (huerf) { fallas++; errores.push(`ScrollTriggers huérfanos: ${huerf}`); }
    console.log(`${rol.padEnd(19)} ${nombre.padEnd(10)} ${visto.join(" ")}  | ST vivos: ${st} · huérfanos: ${huerf} · ocultos esperando scroll: ${ocultos}`);
    const unicos = [...new Set(errores)];
    if (unicos.length) { fallas += unicos.length; unicos.forEach(e => console.log("     ⚠ " + e)); }
    await ctx.close();
  }
}
await browser.close();
console.log(fallas ? `\n${fallas} problema(s)` : "\nSin errores de consola ni secciones rotas");
process.exit(fallas ? 1 : 0);
