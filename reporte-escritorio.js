/* ===================================================================
   VENUE · REPORTE DE ESCRITORIO
   Lo que en el celular no entra por espacio: tablas anchas por team y por
   relacionador, ingresos por hora, cuándo se anotó la gente y la lista
   completa de invitados con filtros. Solo información: no cambia nada.

   Se carga después de app.js y usa sus globales (sb, ev, me, esc, fmtBs,
   hora, traerTodo, teamsCache, listaTipos, sheetRrppDetalle, inicial…).
   screenStats() deja un <div id="rpEsc"> y llama a pintarReporteEscritorio.
   =================================================================== */
(() => {
  const PESTANAS = [["teams", "Teams"], ["rrpp", "Relacionadores"], ["hora", "Por hora"], ["inv", "Invitados"], ["listas", "Listas"]];
  let pestana = "teams";
  // orden y filtros: viven mientras dure la sesión, como el resto de la app
  const orden = { teams: ["vendido", -1], rrpp: ["vendido", -1], listas: ["anotados", -1] };
  const filtro = { team: "", rrpp: "", lista: "", estado: "", q: "" };
  let invVer = 200;
  let datos = null;   // lo que se trajo para el evento actual

  const pct = (a, b) => b ? Math.round(a / b * 100) : 0;
  const fmtDiaHora = ts => ts ? new Date(ts).toLocaleString("es-BO", { day: "numeric", month: "short", hour: "2-digit", minute: "2-digit", hour12: false }) : "";
  const fmtDia = ts => new Date(ts).toLocaleDateString("es-BO", { weekday: "short", day: "numeric", month: "short" });
  // la noche ordenada: 12:00 → 11:59 del día siguiente
  const ordenNoche = h => (h - 12 + 24) % 24;
  const horaDe = ts => new Date(ts).getHours();
  const etqHora = h => `${String(h).padStart(2, "0")}:00`;

  /* hora con más ingresos y primer/último ingreso de un conjunto de timestamps */
  function resumenHoras(tss) {
    const t = tss.filter(Boolean).map(x => new Date(x).getTime()).sort((a, b) => a - b);
    if (!t.length) return { primero: null, ultimo: null, pico: null };
    const cuenta = {};
    t.forEach(x => { const h = new Date(x).getHours(); cuenta[h] = (cuenta[h] || 0) + 1; });
    const pico = +Object.entries(cuenta).sort((a, b) => b[1] - a[1])[0][0];
    return { primero: t[0], ultimo: t[t.length - 1], pico };
  }

  async function cargar(visibles) {
    const [{ data: regs }, { data: ents }, { data: pagos }] = await Promise.all([
      traerTodo(() => sb.from("registros")
        .select("id, nombre, rrpp_id, lista_tipo_id, ingreso_at, created_at, filtro_at, rrpp:profiles!registros_rrpp_id_fkey(nombre,team_id)")
        .eq("evento_id", ev.id).order("id")),
      traerTodo(() => sb.from("entradas")
        .select("id, cliente, code, rrpp_id, precio, estado, created_at, used_at, mesa_id, fase_id, filtro_at")
        .eq("evento_id", ev.id).order("id")),
      sb.from("pagos").select("rrpp_id, monto, estado").eq("evento_id", ev.id),
    ]);
    // nombre y team de cada persona: lo de stats manda; si no está, lo del registro
    const gente = {};
    (regs || []).forEach(r => { if (r.rrpp) gente[r.rrpp_id] = { nombre: r.rrpp.nombre, team_id: r.rrpp.team_id }; });
    visibles.forEach(v => { gente[v.rrpp_id] = { nombre: v.rrpp, team_id: v.team_id }; });
    const pagado = {};
    (pagos || []).forEach(p => {
      const o = pagado[p.rrpp_id] = pagado[p.rrpp_id] || { ok: 0, pend: 0 };
      if (p.estado === "verificado") o.ok += +p.monto || 0; else o.pend += +p.monto || 0;
    });
    return { evId: ev.id, regs: regs || [], ents: (ents || []).filter(e => e.estado !== "anulada"), gente, pagado };
  }

  /* filas por persona, con lo de v_stats_rrpp más horarios */
  function filasPersona(visibles) {
    const regsDe = {}, entsDe = {};
    datos.regs.forEach(r => (regsDe[r.rrpp_id] = regsDe[r.rrpp_id] || []).push(r));
    datos.ents.forEach(e => (entsDe[e.rrpp_id] = entsDe[e.rrpp_id] || []).push(e));
    return visibles.map(v => {
      const rs = regsDe[v.rrpp_id] || [], es = (entsDe[v.rrpp_id] || []).filter(e => !e.mesa_id);
      const ing = resumenHoras([...rs.map(r => r.ingreso_at), ...es.map(e => e.used_at)]);
      const anot = resumenHoras([...rs.map(r => r.created_at), ...es.map(e => e.created_at)]);
      const pg = datos.pagado[v.rrpp_id] || { ok: 0, pend: 0 };
      return {
        id: v.rrpp_id, nombre: v.rrpp, team_id: v.team_id,
        team: teamsCache.find(t => t.id === v.team_id)?.nombre || "Sin team",
        anotados: +v.anotados, entraron: +v.ingresaron, pctLista: pct(+v.ingresaron, +v.anotados),
        qrV: +v.entradas_vendidas, qrU: +v.entradas_usadas, pctQr: pct(+v.entradas_usadas, +v.entradas_vendidas),
        rechazados: rs.filter(r => r.filtro_at).length + es.filter(e => e.filtro_at).length,
        mesas: v.mv, brutoEnt: +v.bruto_entradas, brutoMesas: v.bm, vendido: vendidoDe(v),
        comR: +v.comision_rrpp + (v.cm_r || 0), comJ: +v.comision_jefe + (v.cm_j || 0), bono: v.bono || 0,
        aPagar: aPagarDe(v), pagoOk: pg.ok, pagoPend: pg.pend,
        primerIng: ing.primero, ultimoIng: ing.ultimo, pico: ing.pico,
        primerAnot: anot.primero, ultimoAnot: anot.ultimo,
      };
    });
  }

  function filasTeam(personas) {
    const g = new Map();
    personas.forEach(p => { const k = p.team_id || ""; if (!g.has(k)) g.set(k, []); g.get(k).push(p); });
    const s = (l, k) => l.reduce((a, p) => a + (+p[k] || 0), 0);
    return [...g.entries()].map(([id, l]) => {
      const ids = new Set(l.map(p => p.id));
      const ing = resumenHoras([
        ...datos.regs.filter(r => ids.has(r.rrpp_id)).map(r => r.ingreso_at),
        ...datos.ents.filter(e => ids.has(e.rrpp_id) && !e.mesa_id).map(e => e.used_at)]);
      const mejor = [...l].sort((a, b) => b.vendido - a.vendido)[0];
      return {
        id, team: id ? (teamsCache.find(t => t.id === id)?.nombre || "Team") : "Sin team", personas: l.length,
        anotados: s(l, "anotados"), entraron: s(l, "entraron"), pctLista: pct(s(l, "entraron"), s(l, "anotados")),
        qrV: s(l, "qrV"), qrU: s(l, "qrU"), pctQr: pct(s(l, "qrU"), s(l, "qrV")), rechazados: s(l, "rechazados"),
        mesas: s(l, "mesas"), brutoEnt: s(l, "brutoEnt"), brutoMesas: s(l, "brutoMesas"), vendido: s(l, "vendido"),
        comR: s(l, "comR"), comJ: s(l, "comJ"), bono: s(l, "bono"), aPagar: s(l, "aPagar"),
        promedio: l.length ? Math.round(s(l, "vendido") / l.length) : 0, mejor: mejor?.nombre || "",
        primerIng: ing.primero, ultimoIng: ing.ultimo, pico: ing.pico,
      };
    });
  }

  /* tabla genérica con cabecera que ordena. cols: [clave, título, tipo] */
  function tabla(id, filas, cols, { totales = true, filaAttrs = () => "" } = {}) {
    const [k, dir] = orden[id] || [cols[0][0], 1];
    const ord = [...filas].sort((a, b) => {
      const x = a[k], y = b[k];
      if (typeof x === "string" || typeof y === "string") return String(x ?? "").localeCompare(String(y ?? "")) * dir;
      return ((x ?? -Infinity) - (y ?? -Infinity)) * dir;
    });
    const celda = (v, t) => t === "bs" ? `${fmtBs(v)}` : t === "pct" ? `${v}%` : t === "hora" ? (v ? hora(v) : "—")
      : t === "diahora" ? (v ? fmtDiaHora(v) : "—") : t === "h" ? (v == null ? "—" : etqHora(v)) : t === "txt" ? esc(v ?? "") : v ?? 0;
    const suma = c => filas.reduce((a, f) => a + (+f[c] || 0), 0);
    return `<div class="re-tabla-caja"><table class="re-tabla">
      <thead><tr>${cols.map(([c, t, tipo]) => `<th data-ord="${id}:${c}" class="${["txt"].includes(tipo) ? "" : "num"}${c === k ? " on" : ""}">${t}${c === k ? (dir > 0 ? " ↑" : " ↓") : ""}</th>`).join("")}</tr></thead>
      <tbody>${ord.map(f => `<tr ${filaAttrs(f)}>${cols.map(([c, , tipo]) => `<td class="${tipo === "txt" ? "" : "num"}">${celda(f[c], tipo)}</td>`).join("")}</tr>`).join("")}</tbody>
      ${totales && filas.length > 1 ? `<tfoot><tr>${cols.map(([c, , tipo], i) => `<td class="${tipo === "txt" ? "" : "num"}">${i === 0 ? "Total"
        : ["bs", "n"].includes(tipo) ? celda(suma(c), tipo) : ""}</td>`).join("")}</tr></tfoot>` : ""}
    </table></div>`;
  }

  const selectTeam = personas => {
    const teams = [...new Map(personas.map(p => [p.team_id || "", p.team])).entries()].sort((a, b) => a[1].localeCompare(b[1]));
    return `<select data-f="team"><option value="">Todos los teams</option>${teams.map(([id, n]) =>
      `<option value="${esc(id)}" ${filtro.team === id ? "selected" : ""}>${esc(n)}</option>`).join("")}</select>`;
  };

  function vistaTeams(personas) {
    const filas = filasTeam(personas);
    return `<p class="re-nota">Tocá un team para ver a sus relacionadores. Las cabeceras ordenan.</p>` + tabla("teams", filas, [
      ["team", "Team", "txt"], ["personas", "RRPPs", "n"], ["anotados", "Anotados", "n"], ["entraron", "Entraron", "n"], ["pctLista", "% lista", "pct"],
      ["qrV", "QR vend.", "n"], ["qrU", "QR usadas", "n"], ["pctQr", "% QR", "pct"], ["rechazados", "Rechaz.", "n"], ["mesas", "Mesas", "n"],
      ["brutoEnt", "Bruto ent.", "bs"], ["brutoMesas", "Bruto mesas", "bs"], ["vendido", "Vendido", "bs"], ["promedio", "Prom./RRPP", "bs"],
      ["comR", "Com. RRPP", "bs"], ["comJ", "Com. jefe", "bs"], ["bono", "Bonos", "bs"], ["aPagar", "A pagar", "bs"],
      ["mejor", "Mejor RRPP", "txt"], ["primerIng", "1er ingreso", "hora"], ["ultimoIng", "Último", "hora"], ["pico", "Hora pico", "h"],
    ], { filaAttrs: f => `data-ir-team="${esc(f.id)}" class="re-click"` });
  }

  function vistaRrpp(personas) {
    let l = personas;
    if (filtro.team) l = l.filter(p => (p.team_id || "") === filtro.team);
    if (filtro.q) { const q = filtro.q.toLowerCase(); l = l.filter(p => p.nombre.toLowerCase().includes(q)); }
    return `<div class="re-filtros">${selectTeam(personas)}
      <input type="search" data-f="q" placeholder="Buscar relacionador" value="${esc(filtro.q)}">
      <span class="re-cuenta">${l.length} de ${personas.length}</span></div>` + tabla("rrpp", l, [
      ["nombre", "Relacionador", "txt"], ["team", "Team", "txt"], ["anotados", "Anotados", "n"], ["entraron", "Entraron", "n"], ["pctLista", "% lista", "pct"],
      ["qrV", "QR vend.", "n"], ["qrU", "QR usadas", "n"], ["pctQr", "% QR", "pct"], ["rechazados", "Rechaz.", "n"], ["mesas", "Mesas", "n"],
      ["brutoEnt", "Bruto ent.", "bs"], ["brutoMesas", "Bruto mesas", "bs"], ["vendido", "Vendido", "bs"],
      ["comR", "Comisión", "bs"], ["comJ", "Com. jefe", "bs"], ["bono", "Bono", "bs"], ["aPagar", "A pagar", "bs"],
      ["pagoOk", "Pagado verif.", "bs"], ["pagoPend", "Sin verificar", "bs"],
      ["primerAnot", "Anotó desde", "diahora"], ["ultimoAnot", "Anotó hasta", "diahora"],
      ["primerIng", "1er ingreso", "hora"], ["ultimoIng", "Último", "hora"], ["pico", "Hora pico", "h"],
    ], { filaAttrs: f => `data-rrpp="${f.id}" data-nom="${esc(f.nombre)}" class="re-click"` });
  }

  function vistaHora(personas) {
    let ids = null;
    if (filtro.team) ids = new Set(personas.filter(p => (p.team_id || "") === filtro.team).map(p => p.id));
    const de = x => !ids || ids.has(x.rrpp_id);
    const ingL = datos.regs.filter(r => r.ingreso_at && de(r)).map(r => r.ingreso_at);
    const ingQ = datos.ents.filter(e => e.used_at && !e.mesa_id && de(e)).map(e => e.used_at);
    // ingresos por hora, lista y QR apilados
    const porH = {};
    ingL.forEach(t => { const h = horaDe(t); (porH[h] = porH[h] || { l: 0, q: 0 }).l++; });
    ingQ.forEach(t => { const h = horaDe(t); (porH[h] = porH[h] || { l: 0, q: 0 }).q++; });
    const horas = Object.keys(porH).map(Number).sort((a, b) => ordenNoche(a) - ordenNoche(b));
    const max = Math.max(1, ...horas.map(h => porH[h].l + porH[h].q));
    let acum = 0;
    const total = ingL.length + ingQ.length;
    const r = resumenHoras([...ingL, ...ingQ]);
    const antesMedianoche = [...ingL, ...ingQ].filter(t => { const h = horaDe(t); return h >= 12; }).length;
    // cuándo se anotaron (por día)
    const anot = [...datos.regs.filter(de).map(r => r.created_at), ...datos.ents.filter(e => de(e) && !e.mesa_id).map(e => e.created_at)];
    const porDia = {};
    anot.forEach(t => { const d = new Date(t).toLocaleDateString("sv-SE"); porDia[d] = (porDia[d] || 0) + 1; });
    const dias = Object.keys(porDia).sort();
    const maxD = Math.max(1, ...dias.map(d => porDia[d]));
    return `<div class="re-filtros">${selectTeam(personas)}</div>
      <div class="re-kpis">
        <div><small>Ingresaron</small><b>${total}</b><span>${ingL.length} de lista · ${ingQ.length} con QR</span></div>
        <div><small>Primer ingreso</small><b>${r.primero ? hora(r.primero) : "—"}</b></div>
        <div><small>Último ingreso</small><b>${r.ultimo ? hora(r.ultimo) : "—"}</b></div>
        <div><small>Hora pico</small><b>${r.pico == null ? "—" : etqHora(r.pico)}</b><span>${r.pico == null ? "" : `${porH[r.pico].l + porH[r.pico].q} ingresos`}</span></div>
        <div><small>Antes de medianoche</small><b>${pct(antesMedianoche, total)}%</b><span>${antesMedianoche} personas</span></div>
      </div>
      <div class="re-dos">
        <div class="tarjeta"><div class="re-h">Ingresos por hora <span class="re-ley"><i style="background:var(--warning)"></i>Lista <i style="background:var(--brand-primary)"></i>QR</span></div>
          ${horas.length ? `<div class="re-barras">${horas.map(h => {
            const v = porH[h]; acum += v.l + v.q;
            return `<div class="re-col" title="${etqHora(h)} · ${v.l} lista · ${v.q} QR · acumulado ${acum}">
              <span class="re-col-n">${v.l + v.q}</span>
              <div class="re-col-b"><i style="height:${v.q / max * 100}%;background:var(--brand-primary)"></i><i style="height:${v.l / max * 100}%;background:var(--warning)"></i></div>
              <span class="re-col-h">${etqHora(h).slice(0, 2)}</span></div>`;
          }).join("")}</div>` : `<p class="re-vacio">Todavía no entró nadie.</p>`}</div>
        <div class="tarjeta"><div class="re-h">Cuándo se anotaron <span class="re-ley">${anot.length} anotaciones</span></div>
          ${dias.length ? `<div class="re-barras">${dias.map(d => `<div class="re-col" title="${fmtDia(d + "T12:00")} · ${porDia[d]}">
              <span class="re-col-n">${porDia[d]}</span>
              <div class="re-col-b"><i style="height:${porDia[d] / maxD * 100}%;background:var(--info)"></i></div>
              <span class="re-col-h">${new Date(d + "T12:00").getDate()}/${new Date(d + "T12:00").getMonth() + 1}</span></div>`).join("")}</div>` : `<p class="re-vacio">Sin anotaciones.</p>`}</div>
      </div>
      ${horas.length ? tabla("hora", horas.map(h => ({ h, l: porH[h].l, q: porH[h].q, t: porH[h].l + porH[h].q })), [
        ["h", "Hora", "h"], ["l", "De lista", "n"], ["q", "Con QR", "n"], ["t", "Total", "n"]]) : ""}`;
  }

  function vistaInvitados(personas) {
    const nombreLista = id => listaTipos.find(l => l.id === id)?.nombre || "Lista";
    const persona = id => datos.gente[id] || { nombre: "—", team_id: null };
    const teamNm = id => teamsCache.find(t => t.id === id)?.nombre || "Sin team";
    let filas = [
      ...datos.regs.map(r => ({ nombre: r.nombre, tipo: nombreLista(r.lista_tipo_id), k: "l:" + r.lista_tipo_id, rrpp_id: r.rrpp_id,
        anotado: r.created_at, ingreso: r.ingreso_at, rechazo: r.filtro_at, precio: null })),
      ...datos.ents.filter(e => !e.mesa_id).map(e => ({ nombre: e.cliente, tipo: `QR${e.fase_id && fasesMap[e.fase_id] ? " · " + fasesMap[e.fase_id] : ""}`, k: "qr", rrpp_id: e.rrpp_id,
        anotado: e.created_at, ingreso: e.used_at, rechazo: e.filtro_at, precio: e.precio, code: e.code })),
    ].map(f => ({ ...f, rrpp: persona(f.rrpp_id).nombre, team_id: persona(f.rrpp_id).team_id, team: teamNm(persona(f.rrpp_id).team_id) }));
    const total = filas.length;
    if (filtro.team) filas = filas.filter(f => (f.team_id || "") === filtro.team);
    if (filtro.rrpp) filas = filas.filter(f => f.rrpp_id === filtro.rrpp);
    if (filtro.lista) filas = filas.filter(f => f.k === filtro.lista);
    if (filtro.estado === "si") filas = filas.filter(f => f.ingreso);
    if (filtro.estado === "no") filas = filas.filter(f => !f.ingreso && !f.rechazo);
    if (filtro.estado === "rech") filas = filas.filter(f => f.rechazo);
    if (filtro.q) { const q = filtro.q.toLowerCase(); filas = filas.filter(f => f.nombre.toLowerCase().includes(q) || (f.code || "").toLowerCase().includes(q)); }
    // los que entraron primero arriba por hora; el resto por nombre
    filas.sort((a, b) => (a.ingreso ? 0 : 1) - (b.ingreso ? 0 : 1) || (a.ingreso && b.ingreso ? new Date(a.ingreso) - new Date(b.ingreso) : a.nombre.localeCompare(b.nombre)));
    const rrppOpts = personas.filter(p => !filtro.team || (p.team_id || "") === filtro.team).sort((a, b) => a.nombre.localeCompare(b.nombre));
    const entraron = filas.filter(f => f.ingreso).length;
    return `<div class="re-filtros">${selectTeam(personas)}
      <select data-f="rrpp"><option value="">Todos los relacionadores</option>${rrppOpts.map(p => `<option value="${p.id}" ${filtro.rrpp === p.id ? "selected" : ""}>${esc(p.nombre)}</option>`).join("")}</select>
      <select data-f="lista"><option value="">Todas las listas y QR</option>${listaTipos.map(l => `<option value="l:${l.id}" ${filtro.lista === "l:" + l.id ? "selected" : ""}>${esc(l.nombre)}</option>`).join("")}<option value="qr" ${filtro.lista === "qr" ? "selected" : ""}>Entradas QR</option></select>
      <select data-f="estado"><option value="">Todos</option><option value="si" ${filtro.estado === "si" ? "selected" : ""}>Entraron</option><option value="no" ${filtro.estado === "no" ? "selected" : ""}>No entraron</option><option value="rech" ${filtro.estado === "rech" ? "selected" : ""}>Rechazados</option></select>
      <input type="search" data-f="q" placeholder="Buscar nombre o código" value="${esc(filtro.q)}">
      <span class="re-cuenta">${filas.length} de ${total} · ${entraron} entraron</span></div>
      <div class="re-tabla-caja"><table class="re-tabla">
        <thead><tr><th>#</th><th>Nombre</th><th>Lista / tipo</th><th>Relacionador</th><th>Team</th><th class="num">Anotado</th><th class="num">Ingresó</th><th class="num">Precio</th></tr></thead>
        <tbody>${filas.slice(0, invVer).map((f, i) => `<tr>
          <td class="num re-tenue">${i + 1}</td><td>${esc(f.nombre)}${f.code ? ` <span class="re-tenue">#${esc(f.code)}</span>` : ""}</td><td>${esc(f.tipo)}</td>
          <td>${esc(f.rrpp)}</td><td>${esc(f.team)}</td><td class="num">${fmtDiaHora(f.anotado)}</td>
          <td class="num">${f.rechazo ? `<span class="pill-est bad">rechazado ${hora(f.rechazo)}</span>` : f.ingreso ? `<span class="pill-est ok">${hora(f.ingreso)}</span>` : `<span class="re-tenue">no entró</span>`}</td>
          <td class="num">${f.precio == null ? "—" : fmtBs(f.precio)}</td></tr>`).join("")}</tbody>
      </table></div>
      ${filas.length > invVer ? `<button class="btn ghost2 re-mas" data-inv-mas="1">Ver ${Math.min(200, filas.length - invVer)} más</button>` : ""}`;
  }

  function vistaListas() {
    const filas = listaTipos.map(l => {
      const rs = datos.regs.filter(r => r.lista_tipo_id === l.id);
      const quien = {};
      rs.forEach(r => quien[r.rrpp_id] = (quien[r.rrpp_id] || 0) + 1);
      const top = Object.entries(quien).sort((a, b) => b[1] - a[1])[0];
      const h = resumenHoras(rs.map(r => r.ingreso_at));
      const ent = rs.filter(r => r.ingreso_at).length;
      return { nombre: l.nombre, anotados: rs.length, entraron: ent, pct: pct(ent, rs.length), rechazados: rs.filter(r => r.filtro_at).length,
        rrpps: Object.keys(quien).length, top: top ? `${datos.gente[top[0]]?.nombre || "—"} (${top[1]})` : "—",
        primerIng: h.primero, ultimoIng: h.ultimo, pico: h.pico };
    }).filter(f => f.anotados);
    return tabla("listas", filas, [
      ["nombre", "Lista", "txt"], ["anotados", "Anotados", "n"], ["entraron", "Entraron", "n"], ["pct", "% entró", "pct"], ["rechazados", "Rechaz.", "n"],
      ["rrpps", "Anotaron", "n"], ["top", "Más anotó", "txt"], ["primerIng", "1er ingreso", "hora"], ["ultimoIng", "Último", "hora"], ["pico", "Hora pico", "h"]]);
  }

  function pintar(visibles) {
    const caja = document.getElementById("rpEsc");
    if (!caja || !datos) return;
    const personas = filasPersona(visibles);
    const cuerpo = pestana === "teams" ? vistaTeams(personas) : pestana === "rrpp" ? vistaRrpp(personas)
      : pestana === "hora" ? vistaHora(personas) : pestana === "inv" ? vistaInvitados(personas) : vistaListas();
    caja.innerHTML = `
      <div class="tit-bloque"><h2>Análisis detallado</h2><span class="re-tenue" style="font-size:13px">Solo en computadora</span></div>
      <nav class="re-tabs">${PESTANAS.map(([k, l]) => `<button data-re-tab="${k}" class="${pestana === k ? "on" : ""}">${l}</button>`).join("")}</nav>
      <div class="re-cuerpo">${cuerpo}</div>`;
    caja.querySelectorAll("[data-re-tab]").forEach(b => b.onclick = () => { pestana = b.dataset.reTab; invVer = 200; pintar(visibles); });
    caja.querySelectorAll("[data-ord]").forEach(th => th.onclick = () => {
      const [id, c] = th.dataset.ord.split(":");
      const [k, d] = orden[id] || [];
      orden[id] = [c, k === c ? -d : -1];
      pintar(visibles);
    });
    caja.querySelectorAll("[data-f]").forEach(el => {
      const ev_ = el.tagName === "INPUT" ? "input" : "change";
      el.addEventListener(ev_, () => {
        filtro[el.dataset.f] = el.value;
        if (el.dataset.f === "team") filtro.rrpp = "";
        invVer = 200;
        const foco = el.tagName === "INPUT" ? el.selectionStart : null;
        pintar(visibles);
        // buscar no pierde el foco al repintar
        if (foco != null) { const n = caja.querySelector(`input[data-f="${el.dataset.f}"]`); n?.focus(); n?.setSelectionRange(foco, foco); }
      });
    });
    caja.querySelectorAll("[data-ir-team]").forEach(tr => tr.onclick = () => { filtro.team = tr.dataset.irTeam; pestana = "rrpp"; pintar(visibles); });
    caja.querySelectorAll("[data-rrpp]").forEach(tr => tr.onclick = () => sheetRrppDetalle(tr.dataset.rrpp, tr.dataset.nom));
    caja.querySelector("[data-inv-mas]")?.addEventListener("click", () => { invVer += 200; pintar(visibles); });
  }

  window.pintarReporteEscritorio = async visibles => {
    const caja = document.getElementById("rpEsc");
    if (!caja) return;
    caja.innerHTML = `<div class="tit-bloque"><h2>Análisis detallado</h2></div><div class="sk" style="height:220px;border-radius:18px"></div>`;
    try {
      // se trae cada vez que se pinta el reporte; ordenar y filtrar no vuelve a pedir
      datos = await cargar(visibles);
      pintar(visibles);
    } catch (e) {
      console.error(e);
      caja.innerHTML = `<div class="tit-bloque"><h2>Análisis detallado</h2></div><div class="empty">No se pudo cargar el análisis. ${esc(e?.message || "")}</div>`;
    }
  };
})();
