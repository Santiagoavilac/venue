#!/usr/bin/env python3
"""Matriz de permisos contra el proyecto de .env.local (usar SOLO en demo).

    python3 tools/seed_demo.py && python3 tests/test_seguridad.py

Cada caso llama a la API real con la sesión de un usuario sembrado y
comprueba que el SERVIDOR permita o rechace. No hay mocks.
"""
import sys, threading
sys.path.insert(0, "tools")
from venue_api import http, rpc, servicio, login, q, ANON

CLAVE = "Venue2026!"
CERO = "00000000-0000-0000-0000-000000000000"
res = []

def caso(nombre, cond, detalle=""):
    res.append((nombre, bool(cond)))
    print(("  ok   " if cond else "  FALLA") + " " + nombre + ("" if cond else f"   → {detalle}"))

def negado(r):
    s, j = r
    cod = (j or {}).get("code") if isinstance(j, dict) else None
    return s in (401, 403) or cod in ("42501", "28000", "PGRST301", "PGRST302")

def permitido(r):
    return r[0] < 300

def get(ruta, tok):
    return http("GET", "/rest/v1/" + ruta, token=tok)

T = {u: login(u, CLAVE) for u in [
    "superadmin", "admin.aurora", "admin.nebula", "jefe.aurora", "rrpp.aurora", "rrpp2.aurora",
    "portero.aurora", "caja.aurora", "propietario.aurora", "barra.aurora", "deposito.aurora",
    "rrpp.nebula", "portero.nebula"]}
uid = {r["usuario"]: r["id"] for r in servicio("GET", "/rest/v1/profiles?select=id,usuario")[1]}
ev_a = servicio("GET", "/rest/v1/eventos?club_id=eq.aurora&select=id")[1][0]["id"]
ev_n = servicio("GET", "/rest/v1/eventos?club_id=eq.nebula&select=id")[1][0]["id"]
team_a = servicio("GET", "/rest/v1/teams?nombre=eq.Team%20Norte&select=id")[1][0]["id"]

print("\n── anónimo (solo anon key) ──")
for fn, p in [("eliminar_evento", {"p_evento": ev_a}), ("eliminar_usuario", {"p_user": uid["rrpp.aurora"]}),
              ("validar_entrada", {"p_evento": ev_a, "p_code": "AAAAAA"}), ("telefonos_equipo", {"p_club": "aurora"}),
              ("resumen_evento", {"p_evento": ev_a}), ("estado_mesa", {"p_mesa": CERO, "p_estado": "disponible"}),
              ("rol_en_club", {"p_club": "aurora"}), ("roster_caja", {"p_club": "aurora"})]:
    r = rpc(fn, p); caso(f"anónimo no ejecuta {fn}", negado(r), r)
for t in ["eventos", "entradas", "registros", "profiles", "pagos", "mesas", "clubs", "telefono_usuario"]:
    r = get(f"{t}?select=*&limit=1", None); caso(f"anónimo no lee {t}", negado(r) or r[1] == [], r)

print("\n── rrpp: no toca nada administrativo ──")
R = T["rrpp.aurora"]
for fn, p in [("eliminar_evento", {"p_evento": ev_a}), ("eliminar_usuario", {"p_user": uid["portero.aurora"]}),
              ("eliminar_team", {"p_team": team_a}), ("validar_entrada", {"p_evento": ev_a, "p_code": "AAAAAA"}),
              ("telefonos_equipo", {"p_club": "aurora"}), ("liquidacion_evento", {"p_evento": ev_a}),
              ("publicar_evento", {"p_evento": ev_a}), ("set_manillas_externas", {"p_evento": ev_a, "p_cant": 99}),
              ("estado_pago", {"p_pago": CERO, "p_estado": "verificado"}), ("verificar_mesa", {"p_mesa": CERO, "p_ok": True}),
              ("historico_eventos", {"p_club": "aurora"}), ("bar_disponibilidad", {"p_club": "aurora"}),
              ("guardar_telefono_de", {"p_tel": "70000000", "p_user": uid["jefe.aurora"]})]:
    r = rpc(fn, p, R); caso(f"rrpp no ejecuta {fn}", negado(r), r)
for fn, p in [("resumen_evento", {"p_evento": ev_a}), ("mis_cupos", {"p_evento": ev_a}), ("mi_telefono", {})]:
    r = rpc(fn, p, R); caso(f"rrpp sí ejecuta {fn}", permitido(r), r)
r = http("PATCH", f"/rest/v1/eventos?id=eq.{ev_a}", {"precio_manilla": 1}, token=R, extra={"Prefer": "return=representation"})
caso("rrpp no edita eventos por REST", negado(r) or r[1] == [], r)
r = http("PATCH", f"/rest/v1/profiles?id=eq.{uid['rrpp.aurora']}", {"rol": "admin"}, token=R)
caso("rrpp no se cambia el rol", not permitido(r), r)
r = http("PATCH", f"/rest/v1/profiles?id=eq.{uid['rrpp.aurora']}", {"clubs": ["aurora", "nebula"]}, token=R)
caso("rrpp no se agrega boliches", not permitido(r), r)
r = http("POST", "/rest/v1/club_membership", {"user_id": uid["rrpp.aurora"], "club_id": "aurora", "rol": "admin", "team_id": team_a}, token=R)
caso("rrpp no se da una membresía de admin", not permitido(r), r)
r = http("POST", "/rest/v1/platform_admins", {"user_id": uid["rrpp.aurora"]}, token=R)
caso("rrpp no se hace platform admin", not permitido(r), r)

print("\n── aislamiento entre boliches ──")
N = T["rrpp.nebula"]
for fn, p in [("resumen_evento", {"p_evento": ev_a}), ("generar_entrada", {"p_evento": ev_a, "p_cliente": "Intruso"}),
              ("mis_cupos", {"p_evento": ev_a}), ("roster_mi_team", {"p_club": "aurora"})]:
    r = rpc(fn, p, N); caso(f"rrpp de Nebula no ejecuta {fn} en Aurora", negado(r), r)
for ruta in [f"entradas?evento_id=eq.{ev_a}&select=id", f"registros?evento_id=eq.{ev_a}&select=id",
             f"mesas?evento_id=eq.{ev_a}&select=id", "eventos?club_id=eq.aurora&select=id",
             "clubs?id=eq.aurora&select=id", "combos?club_id=eq.aurora&select=id",
             f"v_stats_rrpp?evento_id=eq.{ev_a}&select=*", f"profiles?id=eq.{uid['portero.aurora']}&select=id"]:
    r = get(ruta, N); caso(f"rrpp de Nebula no ve Aurora: {ruta.split('?')[0]}", r[1] == [], r)
r = get("clubs?select=id", N); caso("rrpp de Nebula ve solo su boliche", [c["id"] for c in r[1]] == ["nebula"], r)
AN = T["admin.nebula"]
for fn, p in [("eliminar_evento", {"p_evento": ev_a}), ("eliminar_usuario", {"p_user": uid["rrpp.aurora"]}),
              ("telefonos_equipo", {"p_club": "aurora"}), ("eliminar_team", {"p_team": team_a})]:
    r = rpc(fn, p, AN); caso(f"admin de Nebula no ejecuta {fn} en Aurora", negado(r), r)
r = http("PATCH", f"/rest/v1/eventos?id=eq.{ev_a}", {"nombre": "hack"}, token=AN, extra={"Prefer": "return=representation"})
caso("admin de Nebula no edita eventos de Aurora", negado(r) or r[1] == [], r)
r = http("POST", "/rest/v1/clubs", {"id": "pirata", "nombre": "Pirata"}, token=AN)
caso("admin de boliche no crea boliches", not permitido(r), r)
r = rpc("validar_entrada", {"p_evento": ev_a, "p_code": "AAAAAA"}, T["portero.nebula"])
caso("portero de Nebula no valida en Aurora", negado(r), r)

print("\n── cuentas administrativas ──")
AA = T["admin.aurora"]
r = http("PATCH", f"/rest/v1/profiles?id=eq.{uid['superadmin']}", {"nombre": "x"}, token=AA, extra={"Prefer": "return=representation"})
caso("admin no modifica la cuenta protegida", not permitido(r) or r[1] == [], r)
r = rpc("eliminar_usuario", {"p_user": uid["superadmin"]}, AA); caso("admin no elimina la cuenta protegida", not permitido(r), r)
r = http("PATCH", f"/rest/v1/profiles?id=eq.{uid['rrpp.aurora']}", {"rol": "admin"}, token=AA)
caso("admin de boliche no nombra admins", not permitido(r), r)
J = T["jefe.aurora"]
r = http("PATCH", f"/rest/v1/profiles?id=eq.{uid['jefe.aurora']}", {"rol": "admin"}, token=J)
caso("jefe no se asciende a admin", not permitido(r), r)
r = http("PATCH", f"/rest/v1/profiles?id=eq.{uid['rrpp2.aurora']}", {"rol": "jefe"}, token=J)
caso("jefe no cambia el rol de su gente", not permitido(r), r)
r = http("PATCH", f"/rest/v1/profiles?id=eq.{uid['rrpp2.aurora']}", {"activo": False}, token=J, extra={"Prefer": "return=representation"})
caso("jefe sí pausa a alguien de su team", permitido(r) and r[1] and r[1][0]["activo"] is False, r)
http("PATCH", f"/rest/v1/profiles?id=eq.{uid['rrpp2.aurora']}", {"activo": True}, token=J)
servicio("POST", "/rest/v1/telefono_usuario?on_conflict=user_id", [
    {"user_id": uid["rrpp.aurora"], "telefono": "59170000001"}, {"user_id": uid["portero.aurora"], "telefono": "59170000002"}],
    extra={"Prefer": "resolution=merge-duplicates"})
r = rpc("telefonos_equipo", {"p_club": "aurora"}, J)
caso("jefe ve teléfonos solo de su team", permitido(r) and r[1] and all(x["user_id"] in (uid["jefe.aurora"], uid["rrpp.aurora"], uid["rrpp2.aurora"]) for x in r[1]), r)
r = get("telefono_usuario?select=*", J); caso("jefe no lee la tabla de teléfonos", r[1] == [], r)

print("\n── puerta ──")
P = T["portero.aurora"]
cods = [e["code"] for e in servicio("GET", f"/rest/v1/entradas?evento_id=eq.{ev_a}&estado=eq.valida&select=code&order=code")[1]]
r = rpc("generar_entrada", {"p_evento": ev_a, "p_cliente": "x"}, P); caso("portero no genera entradas", negado(r), r)
r = get(f"pagos?select=id", P); caso("portero no lee pagos", r[1] == [], r)
r = rpc("validar_entrada", {"p_evento": ev_a, "p_code": "ZZZZZZ"}, P)
caso("código inexistente → no_existe", permitido(r) and r[1]["resultado"] == "no_existe", r)
if len(cods) >= 2:
    r = rpc("validar_entrada", {"p_evento": ev_a, "p_code": cods[0]}, P)
    caso("portero valida → valida", permitido(r) and r[1]["resultado"] == "valida", r)
    r = rpc("validar_entrada", {"p_evento": ev_a, "p_code": cods[0]}, P)
    caso("segundo escaneo → usada", permitido(r) and r[1]["resultado"] == "usada", r)
    out = []
    hs = [threading.Thread(target=lambda t=t: out.append(rpc("validar_entrada", {"p_evento": ev_a, "p_code": cods[1]}, t)[1].get("resultado")))
          for t in [P, T["admin.aurora"], P, T["superadmin"], P, T["admin.aurora"]]]
    [h.start() for h in hs]; [h.join() for h in hs]
    caso("6 validaciones simultáneas del mismo QR → entra una sola", out.count("valida") == 1 and out.count("usada") == 5, out)
    for c in cods[:2]:   # dejar el demo como estaba
        rpc("descheckin_entrada", {"p_evento": ev_a, "p_code": c}, T["admin.aurora"])
else:
    caso("hay entradas válidas para probar la puerta", False, cods)

print("\n── mesas: sin doble venta ──")
libre = servicio("GET", f"/rest/v1/mesas?evento_id=eq.{ev_a}&estado=eq.disponible&select=id&limit=1")[1]
combo = servicio("GET", "/rest/v1/combos?club_id=eq.aurora&select=id")[1][0]["id"]
if libre:
    m = libre[0]["id"]; out = []
    def vender(tok, quien):
        out.append(rpc("vender_mesa", {"p_mesa": m, "p_cliente": quien, "p_combo": combo, "p_botellas": [],
                                       "p_manillas": 0, "p_estado": "reservada"}, tok))
    hs = [threading.Thread(target=vender, args=a) for a in [(R, "Cliente A"), (T["rrpp2.aurora"], "Cliente B"), (J, "Cliente C")]]
    [h.start() for h in hs]; [h.join() for h in hs]
    caso("3 ventas simultáneas de la misma mesa → se vende una vez", sum(1 for x in out if permitido(x)) == 1, out)
    r = rpc("estado_mesa", {"p_mesa": m, "p_estado": "disponible"}, N); caso("rrpp de otro boliche no libera la mesa", negado(r), r)
    rpc("estado_mesa", {"p_mesa": m, "p_estado": "disponible"}, T["admin.aurora"])
else:
    caso("hay una mesa libre para probar", False)

print("\n── caja y barra ──")
C = T["caja.aurora"]
r = rpc("roster_caja", {"p_club": "aurora", "p_evento": ev_a}, C); caso("caja ve su roster", permitido(r), r)
r = get(f"entradas?evento_id=eq.{ev_a}&select=id", C); caso("caja no lee entradas", r[1] == [], r)
r = rpc("roster_caja", {"p_club": "nebula"}, C); caso("caja de Aurora no ve Nebula", negado(r), r)
B = T["barra.aurora"]
r = rpc("bar_disponibilidad", {"p_club": "aurora"}, B); caso("barra consulta su carta", permitido(r), r)
r = rpc("bar_disponibilidad", {"p_club": "nebula"}, B); caso("barra de Aurora no ve Nebula", negado(r), r)
r = rpc("bar_proyeccion_compra", {"p_club": "aurora"}, B); caso("bartender no ve la proyección de compra", negado(r), r)
r = http("POST", "/rest/v1/bebidas", {"club_id": "aurora", "nombre": "Pirata"}, token=B); caso("bartender no crea bebidas", not permitido(r), r)
r = get("barras?select=id", T["rrpp.aurora"]); caso("rrpp no lee el módulo barra", r[1] == [], r)

bien = sum(1 for _, k in res if k)
print(f"\n{bien}/{len(res)} casos pasan")
sys.exit(0 if bien == len(res) else 1)
