/* ============================================================
   MOVIMIENTO (GSAP + ScrollTrigger)
   ============================================================
   Todo el movimiento de la web vive acá. app.js no sabe de GSAP: solo
   avisa con window.Motion?.algo() en tres o cuatro lugares, y el resto se
   detecta mirando el DOM. Si GSAP no carga (sin señal, CDN caído) la app
   funciona igual, sin animaciones.

   Reglas:
   · Es una herramienta de trabajo. En puerta, caja y barra el movimiento
     es mínimo (≤150 ms, sin escalonado): manda la velocidad.
   · Solo transformaciones y autoAlpha. Al terminar se limpian para que el
     CSS (hover, estados) vuelva a mandar. Nunca clearProps:"all": borraría
     estilos que app.js escribe inline.
   · Con "reducir movimiento" no se anima nada: todo aparece en su lugar.
   · Al cambiar de sección se matan los ScrollTriggers de la anterior.
   ============================================================ */
(() => {
  if (!window.gsap || !window.ScrollTrigger) return;
  gsap.registerPlugin(ScrollTrigger);
  gsap.defaults({ duration: .35, ease: "power2.out", overwrite: "auto" });
  document.documentElement.classList.add("gsap-on");

  const $1 = s => document.querySelector(s);
  const LIMPIAR = "transform,opacity,visibility";
  let quieto = false, celular = false;

  const mm = gsap.matchMedia();
  mm.add({
    reducir: "(prefers-reduced-motion: reduce)",
    celular: "(max-width: 899px)",
    escritorio: "(min-width: 900px)",
  }, ctx => {
    quieto = ctx.conditions.reducir;
    celular = ctx.conditions.celular;
    if (quieto) return;
    const quitar = barraDeProgreso();
    return () => quitar();
  });

  /* secciones donde manda la velocidad: el que opera no espera a nadie */
  const rapida = () => {
    try {
      return ["escaner", "lista", "rrpps", "caja", "barpos", "recepcion"].includes(tab)
        || ["portero", "caja", "barra", "deposito"].includes(me?.rol);
    } catch { return false; }
  };

  /* --------------------------------------------------------------
     Topbar: se compacta al bajar y muestra cuánto falta de la página
     -------------------------------------------------------------- */
  function barraDeProgreso() {
    const tb = $1(".topbar");
    if (!tb) return () => {};
    let barra = tb.querySelector(".tb-prog");
    if (!barra) { barra = document.createElement("div"); barra.className = "tb-prog"; tb.appendChild(barra); }
    const t1 = gsap.fromTo(barra, { scaleX: 0 }, {
      scaleX: 1, ease: "none",
      scrollTrigger: { id: "tb-prog", start: 0, end: "max", scrub: .25 },
    });
    const t2 = ScrollTrigger.create({
      id: "tb-compacta", start: 12, end: "max",
      toggleClass: { targets: tb, className: "compacta" },
    });
    return () => { t1.scrollTrigger?.kill(); t1.kill(); t2.kill(); barra.remove(); tb.classList.remove("compacta"); };
  }

  /* --------------------------------------------------------------
     Números: conteo animado de la cifra principal de cada KPI
     -------------------------------------------------------------- */
  const NUM = /^(\s*)(\d{1,3}(?:\.\d{3})+|\d+)/;
  function contar(raiz, dur = .7) {
    raiz.querySelectorAll(".stat .v, .cf-nv, .kpi-v, .rp-kpi-v").forEach(el => {
      const nodo = el.firstChild;
      if (!nodo || nodo.nodeType !== 3) return;
      const m = nodo.nodeValue.match(NUM);
      if (!m) return;
      const final = +m[2].replace(/\./g, "");
      if (!final || final > 1e8) return;
      const resto = nodo.nodeValue.slice(m[0].length), pre = m[1];
      const o = { n: 0 };
      gsap.to(o, {
        n: final, duration: dur, ease: "power2.out",
        onUpdate: () => { nodo.nodeValue = pre + Math.round(o.n).toLocaleString("es-BO") + resto; },
        onComplete: () => { nodo.nodeValue = pre + final.toLocaleString("es-BO") + resto; },
      });
    });
  }

  /* --------------------------------------------------------------
     Secciones: entrada del contenido y listas que aparecen al bajar
     -------------------------------------------------------------- */
  const main = $1("#main");
  let tabVisto = null, tabAnimado = null, mesas = new Map(), ocultos = [];

  const esDeMain = t => {
    const el = t.trigger;
    return el && el !== document.documentElement && el !== document.body && (!el.isConnected || main.contains(el));
  };
  /* mata los ScrollTriggers de la sección y devuelve a la vista lo que
     quedó esperando para aparecer (si la pantalla agregó en vez de
     reemplazar, esas filas siguen ahí) */
  const matarDeMain = () => {
    ScrollTrigger.getAll().filter(esDeMain).forEach(t => t.kill());
    const vivos = ocultos.filter(el => el.isConnected);
    if (vivos.length) gsap.set(vivos, { clearProps: LIMPIAR });
    ocultos = [];
  };

  function entrarSeccion() {
    const kids = [...main.children].filter(k => k.offsetParent !== null || k.getClientRects().length);
    if (!kids.length) return;
    const rapido = rapida();
    gsap.fromTo(kids.slice(0, rapido ? 3 : 7), { autoAlpha: 0, y: rapido ? 4 : 14 }, {
      autoAlpha: 1, y: 0, duration: rapido ? .15 : .42, stagger: rapido ? 0 : .045,
      clearProps: LIMPIAR,
    });
    if (rapido) return;
    contar(main);
    planoEntrada();
    listasAlBajar();
  }

  /* Solo lo que está debajo del borde: lo visible ya entra con la sección.
     Con 1.000 invitados no se crean 1.000 animaciones: el tope es 150 y el
     resto se ve normal. */
  function listasAlBajar() {
    const alto = innerHeight;
    const abajo = [...main.querySelectorAll(".list-row, .lst-card, .stat, .rc, .cat-row, .card, .rp-bar")]
      .filter(el => el.getBoundingClientRect().top > alto)
      .slice(0, 150);
    if (!abajo.length) return;
    ocultos = abajo;
    gsap.set(abajo, { autoAlpha: 0, y: 18 });
    ScrollTrigger.batch(abajo, {
      start: "top 96%", once: true, interval: .08, batchMax: 8,
      onEnter: lote => gsap.to(lote, {
        autoAlpha: 1, y: 0, duration: .4, stagger: .04, clearProps: LIMPIAR,
        onStart: () => lote.forEach(barraRp),
      }),
    });
  }

  /* barras del Reporte: se llenan cuando aparecen */
  function barraRp(el) {
    el.querySelectorAll?.(".rp-bar-f").forEach(f =>
      gsap.fromTo(f, { scaleX: 0 }, { scaleX: 1, transformOrigin: "left center", duration: .7, ease: "power3.out", clearProps: "transform" }));
  }

  /* plano de mesas: aparecen desde el centro; las que cambian de estado
     mientras se mira laten una vez */
  const claveMesa = c => c.querySelector(".id")?.textContent || "";
  function planoEntrada() {
    const chips = [...main.querySelectorAll("#cv2 .chip")];
    mesas = new Map(chips.map(c => [claveMesa(c), c.className]));
    if (!chips.length) return;
    chips.forEach(c => c.classList.add("mv"));
    gsap.fromTo(chips, { autoAlpha: 0, scale: .82 }, {
      autoAlpha: 1, scale: 1, duration: .45, ease: "back.out(1.6)",
      stagger: { amount: .35, from: "center", grid: "auto" },
      clearProps: LIMPIAR, onComplete: () => chips.forEach(c => c.classList.remove("mv")),
    });
    main.querySelectorAll(".rp-bar").forEach(el => el.getBoundingClientRect().top <= innerHeight && barraRp(el));
  }
  function planoCambios() {
    const chips = [...main.querySelectorAll("#cv2 .chip")];
    if (!chips.length) { mesas = new Map(); return; }
    const antes = mesas;
    mesas = new Map(chips.map(c => [claveMesa(c), c.className]));
    if (quieto) return;
    chips.forEach(c => {
      const prev = antes.get(claveMesa(c));
      if (prev === undefined || prev.replace(/\bsel\b/, "") === c.className.replace(/\bsel\b/, "")) return;
      c.classList.add("mv");
      gsap.fromTo(c, { scale: 1.14 }, {
        scale: 1, duration: .6, ease: "elastic.out(1, .45)", clearProps: "transform",
        onComplete: () => c.classList.remove("mv"),
      });
    });
  }

  let refrescoPendiente = 0;
  const refrescar = () => {
    cancelAnimationFrame(refrescoPendiente);
    refrescoPendiente = requestAnimationFrame(() => ScrollTrigger.refresh());
  };

  if (main) {
    new MutationObserver(() => {
      let t; try { t = tab; } catch { return; }
      if (t !== tabVisto) { tabVisto = t; tabAnimado = null; matarDeMain(); }
      const primero = main.firstElementChild;
      if (!primero || primero.classList.contains("sk-wrap")) return;
      if (tabAnimado === t) {
        // repintada de la misma sección (tiempo real, filtros): sin entrada,
        // solo lo que cambió en el plano
        matarDeMain();
        planoCambios();
        refrescar();
        return;
      }
      tabAnimado = t;
      if (!quieto) entrarSeccion();
      else mesas = new Map([...main.querySelectorAll("#cv2 .chip")].map(c => [claveMesa(c), c.className]));
      refrescar();
    }).observe(main, { childList: true });
    // imágenes que terminan de cargar, acordeones que se abren
    new ResizeObserver(refrescar).observe(main);
  }

  /* --------------------------------------------------------------
     Hojas: el contenido entra escalonado al abrir o al cambiar
     -------------------------------------------------------------- */
  const hoja = $1("#sheet"), cuerpo = $1("#sheetBody");
  if (hoja && cuerpo) {
    const entrarHoja = () => {
      if (quieto || !hoja.classList.contains("open")) return;
      const kids = [...cuerpo.children].slice(0, 10);
      if (!kids.length) return;
      gsap.fromTo(kids, { autoAlpha: 0, y: 10 }, {
        autoAlpha: 1, y: 0, duration: rapida() ? .14 : .3,
        stagger: rapida() ? 0 : .03, delay: .04, clearProps: LIMPIAR,
      });
    };
    let abierta = false;
    new MutationObserver(() => {
      const ahora = hoja.classList.contains("open");
      if (ahora && !abierta) entrarHoja();
      abierta = ahora;
    }).observe(hoja, { attributes: true, attributeFilter: ["class"] });
    new MutationObserver(() => { if (abierta) entrarHoja(); }).observe(cuerpo, { childList: true });
  }

  /* --------------------------------------------------------------
     Navegación: indicador de la sección activa que se desliza
     -------------------------------------------------------------- */
  const tabbar = $1("#tabbar");
  if (tabbar) {
    const mover = () => {
      const on = tabbar.querySelector("button.on");
      let ind = tabbar.querySelector(".nav-ind");
      if (!on) { ind?.remove(); return; }
      const nuevo = !ind;
      if (nuevo) { ind = document.createElement("span"); ind.className = "nav-ind"; ind.setAttribute("aria-hidden", "true"); tabbar.prepend(ind); }
      const y = on.offsetTop, h = on.offsetHeight;
      ind.style.height = h + "px";
      if (nuevo || quieto || !on.offsetParent) gsap.set(ind, { y });
      else gsap.to(ind, { y, duration: .32, ease: "power3.out" });
    };
    new MutationObserver(mover).observe(tabbar, { subtree: true, attributes: true, attributeFilter: ["class"], childList: true });
    addEventListener("resize", mover);
    new MutationObserver(mover).observe(document.documentElement, { attributes: true, attributeFilter: ["class"] });
  }

  /* --------------------------------------------------------------
     Login: entrada de la marca y sacudida si la clave está mal
     -------------------------------------------------------------- */
  const logo = $1(".login .vn-logo");
  if (logo && !logo.dataset.partido) {
    logo.dataset.partido = "1";
    logo.setAttribute("aria-label", logo.textContent.trim());
    logo.innerHTML = [...logo.textContent.trim()].map(l => `<span class="vn-l" aria-hidden="true">${l}</span>`).join("");
  }
  const loginVisible = () => { const l = $1("#login"); return l && !l.classList.contains("hidden") && l.offsetParent !== null; };
  if (!quieto && loginVisible()) {
    gsap.timeline({ defaults: { ease: "power3.out" } })
      .from(".login .vn-l", { autoAlpha: 0, y: 18, rotationX: -70, duration: .6, stagger: .06, clearProps: LIMPIAR })
      .from(".login .vn-sub", { autoAlpha: 0, y: 8, duration: .4, clearProps: LIMPIAR }, "-=.3")
      .from("#loginCard", { autoAlpha: 0, y: 22, scale: .985, duration: .5, clearProps: LIMPIAR }, "-=.25")
      .from(".login-foot", { autoAlpha: 0, duration: .4, clearProps: LIMPIAR }, "-=.2");
  }
  const lErr = $1("#loginErr");
  if (lErr) new MutationObserver(() => {
    if (quieto || !lErr.textContent.trim()) return;
    gsap.fromTo("#loginCard", { x: 0 }, {
      keyframes: { x: [0, -9, 8, -6, 4, 0] }, duration: .38, ease: "none", clearProps: "transform",
    });
  }).observe(lErr, { childList: true });

  /* --------------------------------------------------------------
     Avisos de app.js
     -------------------------------------------------------------- */
  window.Motion = {
    /* selector de boliche: tarjetas escalonadas */
    selector(ov) {
      if (quieto || !ov) return;
      gsap.timeline()
        .from(ov.querySelectorAll(".cp-brand, .cp-h, .cp-sub"), { autoAlpha: 0, y: 12, stagger: .06, duration: .4, clearProps: LIMPIAR })
        .from(ov.querySelectorAll(".cp-card"), { autoAlpha: 0, y: 20, scale: .97, stagger: .07, duration: .45, ease: "power3.out", clearProps: LIMPIAR }, "-=.2")
        .from(ov.querySelectorAll(".cp-out"), { autoAlpha: 0, duration: .3, clearProps: LIMPIAR }, "-=.15");
    },
    /* entrada a la app: barra lateral y topbar */
    entrarApp() {
      if (quieto) return;
      const nav = celular ? [] : [...document.querySelectorAll("#nav .nav-top, #tabbar button, #nav .nav-bottom")];
      const tl = gsap.timeline();
      tl.from(".topbar", { autoAlpha: 0, y: -10, duration: .35, clearProps: LIMPIAR });
      if (nav.length) tl.from(nav, { autoAlpha: 0, x: -14, stagger: .035, duration: .35, clearProps: LIMPIAR }, 0);
      if (celular) tl.from("#botnav", { yPercent: 100, duration: .4, ease: "power3.out", clearProps: "transform" }, 0);
    },
    /* veredicto del escáner: golpe seco, sin hacer esperar */
    veredicto(el, cls) {
      if (quieto || !el) return;
      el.classList.add("mv");
      gsap.fromTo(el, { scale: .94, autoAlpha: .4 }, {
        scale: 1, autoAlpha: 1, duration: .14, ease: "back.out(2.4)", clearProps: LIMPIAR,
        onComplete: () => el.classList.remove("mv"),
      });
      const vf = $1("#viewfinder");
      if (vf && cls === "bad") gsap.fromTo(vf, { x: 0 }, { keyframes: { x: [0, -6, 5, -3, 0] }, duration: .22, ease: "none", clearProps: "transform" });
    },
    /* avisos (toasts): entran y salen con GSAP */
    toast(el) {
      if (quieto) { el.classList.add("show"); setTimeout(() => el.remove(), 2600); return; }
      el.classList.add("show", "mv");
      gsap.timeline({ onComplete: () => el.remove() })
        .fromTo(el, { autoAlpha: 0, y: 16, scale: .96 }, { autoAlpha: 1, y: 0, scale: 1, duration: .3, ease: "back.out(1.8)" })
        .to(el, { autoAlpha: 0, y: 8, duration: .2, ease: "power2.in" }, "+=2.3");
    },
  };
})();
