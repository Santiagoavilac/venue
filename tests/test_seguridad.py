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
r = get("telefono_usuario?select=*", J)
caso("jefe lee de la tabla de teléfonos solo el suyo", all(x["user_id"] == uid["jefe.aurora"] for x in r[1]), r)

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


print("\n── códigos, auditoría y límite de intentos ──")
r = rpc("generar_entrada", {"p_evento": ev_a, "p_cliente": "Prueba Código"}, R)
nueva = servicio("GET", f"/rest/v1/entradas?evento_id=eq.{ev_a}&cliente=eq.Prueba%20C%C3%B3digo&select=id,code&order=created_at.desc&limit=1")[1]
cod = nueva[0]["code"] if nueva else ""
caso("código nuevo: 10 caracteres sin ambiguos", permitido(r) and len(cod) == 10 and not set(cod) & set("ILOU01"), (r, cod))
r = rpc("validar_entrada", {"p_evento": ev_a, "p_code": cod}, P); caso("el código nuevo valida en puerta", permitido(r) and r[1]["resultado"] == "valida", r)
r = get(f"audit_log?tabla=eq.entradas&fila_id=eq.{nueva[0]['id']}&select=op,actor,club_id", T["admin.aurora"])
caso("la validación quedó auditada (quién y en qué boliche)", r[1] and r[1][0]["actor"] == uid["portero.aurora"] and r[1][0]["club_id"] == "aurora", r)
r = get("audit_log?club_id=eq.aurora&select=id&limit=1", AN); caso("admin de Nebula no lee la auditoría de Aurora", r[1] == [], r)
r = get("audit_log?select=id&limit=1", R); caso("rrpp no lee la auditoría", r[1] == [], r)
r = http("POST", "/rest/v1/audit_log", {"tabla": "x", "op": "INSERT"}, token=AA); caso("nadie escribe la auditoría por la API", not permitido(r), r)
rpc("eliminar_entrada", {"p_entrada": nueva[0]["id"]}, T["admin.aurora"])
servicio("DELETE", f"/rest/v1/entradas?id=eq.{nueva[0]['id']}")
PN = T["portero.nebula"]
ult = None
for i in range(42):
    ult = rpc("validar_entrada", {"p_evento": ev_n, "p_code": f"NOPE{i:04d}"}, PN)
caso("tras 40 códigos inexistentes la puerta corta al que prueba al azar", not permitido(ult) and "Demasiados" in str(ult[1]), ult)

print("\n── comprobantes privados ──")
import urllib.request, urllib.error
from venue_api import URL
def crudo(metodo, ruta, tok, datos=None, tipo="image/jpeg"):
    h = {"apikey": ANON, "Authorization": f"Bearer {tok or ANON}"}
    if datos is not None: h["Content-Type"] = tipo; h["x-upsert"] = "true"
    try:
        with urllib.request.urlopen(urllib.request.Request(URL + ruta, method=metodo, headers=h, data=datos), timeout=60) as x: return x.status
    except urllib.error.HTTPError as e: return e.code
ruta = f"{uid['rrpp.aurora']}/prueba.jpg"
caso("rrpp sube su comprobante", crudo("POST", f"/storage/v1/object/comprobantes/{ruta}", R, b"\xff\xd8\xff\xd9") < 300)
caso("rrpp no sube en la carpeta de otro", crudo("POST", f"/storage/v1/object/comprobantes/{uid['jefe.aurora']}/x.jpg", R, b"\xff\xd8\xff\xd9") >= 400)
caso("la URL pública ya no abre el comprobante", crudo("GET", f"/storage/v1/object/public/comprobantes/{ruta}", None) >= 400)
firmar = lambda tok: http("POST", f"/storage/v1/object/sign/comprobantes/{ruta}", {"expiresIn": 60}, token=tok)
caso("quien lo subió obtiene URL firmada", permitido(firmar(R)), firmar(R))
caso("su jefe de team obtiene URL firmada", permitido(firmar(J)))
caso("el admin de su boliche obtiene URL firmada", permitido(firmar(AA)))
caso("otro rrpp del mismo team NO", not permitido(firmar(T["rrpp2.aurora"])))
caso("el admin de otro boliche NO", not permitido(firmar(AN)))
caso("el portero NO", not permitido(firmar(P)))

print("\n── alta de usuarios (Edge Function) ──")
fn = lambda cuerpo, tok=None: http("POST", "/functions/v1/crear-usuario", cuerpo, token=tok)
r = fn({"action": "registro", "invite": "abc123", "nombre": "X", "usuario": "intruso1", "clave": "secreta1"})
caso("registro con invitación inventada → rechazado", r[0] == 400, r)
r = fn({"usuario": "pirata.admin", "nombre": "Pirata", "clave": "secreta1", "rol": "admin"}, AA)
caso("admin de boliche no crea administradores", r[0] == 403, r)
r = fn({"usuario": "pirata.rrpp", "nombre": "Pirata", "clave": "secreta1", "rol": "rrpp"}, R)
caso("rrpp no crea usuarios", r[0] == 403, r)
r = fn({"action": "reset", "user_id": uid["rrpp.aurora"], "clave": "secreta1"}, AN)
caso("admin de otro boliche no resetea claves", r[0] == 403, r)
inv = servicio("GET", f"/rest/v1/teams?id=eq.{team_a}&select=invite_code")[1][0]["invite_code"]
caso("invitación de team: 32 hex", len(inv) == 32, inv)
servicio("DELETE", "/rest/v1/profiles?usuario=eq.prueba.invitado")
r = fn({"action": "registro", "invite": inv, "nombre": "Invitado Prueba", "usuario": "prueba.invitado", "clave": "secreta1"})
nuevo = servicio("GET", "/rest/v1/profiles?usuario=eq.prueba.invitado&select=id,rol,clubs,team_id")[1]
caso("registro con invitación válida → rrpp del team, solo en su boliche",
     r[0] == 200 and nuevo and nuevo[0]["rol"] == "rrpp" and nuevo[0]["clubs"] == ["aurora"] and nuevo[0]["team_id"] == team_a, (r, nuevo))
if nuevo:
    servicio("DELETE", f"/rest/v1/profiles?id=eq.{nuevo[0]['id']}"); servicio("DELETE", f"/auth/v1/admin/users/{nuevo[0]['id']}")

bien = sum(1 for _, k in res if k)
print(f"\n{bien}/{len(res)} casos pasan")
sys.exit(0 if bien == len(res) else 1)
