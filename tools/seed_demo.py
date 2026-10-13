#!/usr/bin/env python3
"""Datos de demostración: 2 boliches, un usuario por rol, eventos, listas,
entradas, mesas y barra. SOLO para proyectos de prueba.

    python3 tools/seed_demo.py

Idempotente: lo que ya existe no se duplica. Las entradas, invitados, mesas
vendidas y stock se cargan llamando a las RPC con la sesión de cada usuario,
igual que lo haría la app.
"""
import sys, datetime
sys.path.insert(0, "tools")
from venue_api import servicio, rpc, login, q, DOMINIO

CLAVE = "Venue2026!"
HOY = datetime.date.today().isoformat()

def ok(s, j, que):
    if s >= 300:
        raise SystemExit(f"FALLA {que}: {s} {j}")
    return j

def upsert(tabla, filas, conflicto):
    return ok(*servicio("POST", f"/rest/v1/{tabla}?on_conflict={conflicto}", filas,
                        extra={"Prefer": "resolution=merge-duplicates,return=representation"}), tabla)

# ── boliches ────────────────────────────────────────────────────────
upsert("clubs", [
    {"id": "aurora", "nombre": "Aurora Club", "subtitulo": "Equipetrol", "inicial": "A",
     "color_primario": "#7C3AED", "color_secundario": "#A855F7", "color_accent": "#22D3EE", "activo": True},
    {"id": "nebula", "nombre": "Nebula", "subtitulo": "Zona Norte", "inicial": "N",
     "color_primario": "#F97316", "color_secundario": "#FB923C", "color_accent": "#FACC15", "activo": True},
], "id")

# ── teams ───────────────────────────────────────────────────────────
def team(nombre, clubs):
    s, j = servicio("GET", f"/rest/v1/teams?nombre=eq.{q(nombre)}&select=id")
    if j: return j[0]["id"]
    return ok(*servicio("POST", "/rest/v1/teams", {"nombre": nombre, "activo": True, "clubs": clubs},
                        extra={"Prefer": "return=representation"}), "team")[0]["id"]

# ── usuarios ────────────────────────────────────────────────────────
USUARIOS = [
    # usuario, nombre, rol, clubs, team, extras
    ("superadmin",        "Sofía Plataforma",   "admin",       ["aurora", "nebula"], None,    {"admin_principal": True, "contabilidad_total": True}),
    ("admin.aurora",      "Andrés Aurora",      "admin",       ["aurora"],           None,    {}),
    ("admin.nebula",      "Nadia Nebula",       "admin",       ["nebula"],           None,    {}),
    ("jefe.aurora",       "Julián Jefe",        "jefe",        ["aurora"],           "norte", {"puede_tickear": True}),
    ("rrpp.aurora",       "Mateo Relaciones",   "rrpp",        ["aurora"],           "norte", {"puede_tickear": True}),
    ("rrpp2.aurora",      "Renata Relaciones",  "rrpp",        ["aurora"],           "norte", {}),
    ("portero.aurora",    "Pablo Puerta",       "portero",     ["aurora"],           None,    {}),
    ("caja.aurora",       "Camila Caja",        "caja",        ["aurora"],           None,    {}),
    ("propietario.aurora","Olga Propietaria",   "propietario", ["aurora"],           None,    {}),
    ("barra.aurora",      "Bruno Barra",        "barra",       ["aurora"],           None,    {}),
    ("deposito.aurora",   "Diego Depósito",     "deposito",    ["aurora"],           None,    {}),
    ("jefe.nebula",       "Jimena Jefa",        "jefe",        ["nebula"],           "sur",   {"puede_tickear": True}),
    ("rrpp.nebula",       "Nicolás Relaciones", "rrpp",        ["nebula"],           "sur",   {"puede_tickear": True}),
    ("portero.nebula",    "Paula Puerta",       "portero",     ["nebula"],           None,    {}),
]

def main():
    teams = {"norte": team("Team Norte", ["aurora"]), "sur": team("Team Sur", ["nebula"])}

    s, lista = servicio("GET", "/auth/v1/admin/users?per_page=200")
    existentes = {u["email"]: u["id"] for u in ok(s, lista, "listar usuarios")["users"]}
    ids = {}
    for usuario, nombre, rol, clubs, tm, extra in USUARIOS:
        email = f"{usuario}@{DOMINIO}"
        uid = existentes.get(email)
        if not uid:
            uid = ok(*servicio("POST", "/auth/v1/admin/users",
                               {"email": email, "password": CLAVE, "email_confirm": True}), email)["id"]
        ids[usuario] = uid
        fila = {"id": uid, "usuario": usuario, "nombre": nombre, "rol": rol, "clubs": clubs,
                "team_id": teams.get(tm), "activo": True, "puede_tickear": False,
                "admin_principal": False, "created_at": datetime.datetime.now(datetime.timezone.utc).isoformat()}
        fila.update(extra)
        upsert("profiles", [fila], "id")
    servicio("PATCH", f"/rest/v1/teams?id=eq.{teams['norte']}", {"jefe_id": ids["jefe.aurora"]})
    servicio("PATCH", f"/rest/v1/teams?id=eq.{teams['sur']}", {"jefe_id": ids["jefe.nebula"]})

    # ── eventos ─────────────────────────────────────────────────────
    def evento(club, nombre):
        s, j = servicio("GET", f"/rest/v1/eventos?club_id=eq.{club}&nombre=eq.{q(nombre)}&select=id")
        if j: return j[0]["id"]
        return ok(*servicio("POST", "/rest/v1/eventos", {
            "club_id": club, "nombre": nombre, "fecha": HOY, "hora_inicio": "00:00", "hora_fin": "23:59",
            "edad_min": 18, "precio_manilla": 100, "pct_boliche": 50, "pct_rrpp": 50, "cut_rrpp": 0,
            "estado": "proximo", "publicado": True, "ticket_url": "", "lista_hasta": "23:59",
            "manillas_externas": 0, "venta_por_fases": False, "permite_reserva": True, "horas_reserva": 3,
            "permite_agrupar": True, "combo_obligatorio": True, "combo_por_mesa": False, "cut_base": "usada",
        }, extra={"Prefer": "return=representation"}), f"evento {nombre}")[0]["id"]

    ev_a, ev_n = evento("aurora", "Noche Aurora"), evento("nebula", "Nebula Fest")

    def lista(ev, nombre):
        s, j = servicio("GET", f"/rest/v1/lista_tipos?evento_id=eq.{ev}&nombre=eq.{q(nombre)}&select=id")
        if j: return j[0]["id"]
        hasta = (datetime.datetime.now(datetime.timezone.utc) + datetime.timedelta(days=2)).isoformat()
        return ok(*servicio("POST", "/rest/v1/lista_tipos", {
            "evento_id": ev, "nombre": nombre, "registro_hasta": hasta, "orden": 1, "cupo_por_rrpp": 50,
        }, extra={"Prefer": "return=representation"}), "lista")[0]["id"]

    li_a, li_n = lista(ev_a, "Invitados"), lista(ev_n, "Invitados")

    # ── combos y mesas (catálogo del admin) ─────────────────────────
    s, j = servicio("GET", "/rest/v1/combos?club_id=eq.aurora&select=id")
    combo = j[0]["id"] if j else ok(*servicio("POST", "/rest/v1/combos", {
        "club_id": "aurora", "nombre": "Combo Vodka", "productos": ["Vodka 750", "6 energizantes"],
        "precio": 900, "comision_rrpp": 60, "comision_jefe": 20, "incluye_manillas": 6, "activo": True,
        "categorias": ["vip", "lounge"]}, extra={"Prefer": "return=representation"}), "combo")[0]["id"]
    s, j = servicio("GET", f"/rest/v1/mesas?evento_id=eq.{ev_a}&select=id")
    if not j:
        ok(*servicio("POST", "/rest/v1/mesas", [
            {"evento_id": ev_a, "planta": "alta", "etiqueta": f"A{i+1}", "categoria": "vip",
             "x": 10 + i * 18, "y": 20, "w": 12, "estado": "disponible", "botellas": [],
             "manillas": 0, "combo_qty": 1, "pago_verificado": False, "cortesia": False,
             "updated_at": datetime.datetime.now(datetime.timezone.utc).isoformat()} for i in range(4)]), "mesas")

    # ── operación real, con la sesión de cada usuario ───────────────
    t_rrpp, t_rrpp_n = login("rrpp.aurora", CLAVE), login("rrpp.nebula", CLAVE)
    s, j = servicio("GET", f"/rest/v1/entradas?evento_id=eq.{ev_a}&select=id")
    if not j:
        for cliente in ["Carlos Roca", "Valeria Suárez", "Luis Méndez"]:
            ok(*rpc("generar_entrada", {"p_evento": ev_a, "p_cliente": cliente}, t_rrpp), "generar_entrada")
        ok(*rpc("registrar_lista", {"p_lista": li_a, "p_nombres": ["Ana Paz", "Jorge Vaca", "Lucía Rivero"]}, t_rrpp), "registrar_lista")
        ok(*rpc("generar_entrada", {"p_evento": ev_n, "p_cliente": "Marta Nebula"}, t_rrpp_n), "generar_entrada nebula")
        ok(*rpc("registrar_lista", {"p_lista": li_n, "p_nombres": ["Pedro Nebula"]}, t_rrpp_n), "registrar_lista nebula")

    # ── barra ───────────────────────────────────────────────────────
    t_prop = login("propietario.aurora", CLAVE)
    s, j = servicio("GET", "/rest/v1/barras?club_id=eq.aurora&select=id")
    if not j:
        from venue_api import http
        barra = ok(*http("POST", "/rest/v1/barras", {"club_id": "aurora", "nombre": "Barra principal"},
                         token=t_prop, extra={"Prefer": "return=representation"}), "barra")[0]["id"]
        print("  barra creada por el propietario:", barra)

    print("\nSeed listo.")
    print(f"  evento Aurora: {ev_a}\n  evento Nebula: {ev_n}")
    print(f"\nContraseña de todas las cuentas: {CLAVE}\n")
    for usuario, nombre, rol, clubs, tm, _ in USUARIOS:
        print(f"  {usuario:20s} {rol:12s} {','.join(clubs)}")

main()
