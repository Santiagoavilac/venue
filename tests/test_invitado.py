#!/usr/bin/env python3
"""La puerta del invitado, contra la API real del proyecto de .env.local.

    python3 tests/test_invitado.py

Qué prueba y por qué así: comprar no pide cuenta, y todo lo demás —PULSE,
mesas, historias, reventa, rachas— sí. Eso se prueba llamando al REST con una
sesión anónima de verdad, no con la app: esconder un botón en Flutter o en la
web no protege nada, la llamada sale igual con la sesión propia. Así se
encontraron los dos agujeros del 06/11 (`aftr_pulse` y `aftr_mis_mesas`
contestando 200 a un invitado) y la guarda que quedaba detrás del `declare` en
`aftr_reservar_historia`.

Crea una sesión anónima y un perfil de prueba, y los borra al terminar, pase
lo que pase. No deja nada en la base.
"""
import sys, uuid

sys.path.insert(0, "tools")
from venue_api import http, rpc, servicio  # noqa: E402

CERO = "00000000-0000-0000-0000-000000000000"
CORREO_PRUEBA = "invitado.prueba@example.invalid"
res = []


def caso(nombre, cond, detalle=""):
    res.append((nombre, bool(cond)))
    print(("  ok   " if cond else "  FALLA") + " " + nombre + ("" if cond else f"   → {detalle}"))


def pide_cuenta(r):
    """La respuesta de impl.aftr_cuenta_real: 28000 y el mensaje de la app."""
    s, j = r
    m = (j or {}).get("message", "") if isinstance(j, dict) else ""
    return s >= 400 and (j or {}).get("code") == "28000" and "Google o Apple" in m


def main():
    # ── lo público, sin ninguna sesión ──────────────────────────────────
    # Es la puerta de entrada de la app. Ya la cerré una vez sin querer al
    # poner la guarda arriba de todo en aftr_historias y aftr_reventa.
    print("sin sesión, lo público sigue abierto")
    for fn, params in [("aftr_reventa", {"p_accion": "mercado"}),
                       ("aftr_historias", {"p_accion": "feed"}),
                       ("aftr_eventos", {}), ("aftr_lugares", {}), ("aftr_calor", {})]:
        s, j = rpc(fn, params)
        caso(f"{fn} abierto", s == 200, f"{s} {j}")

    # ── la sesión del invitado ──────────────────────────────────────────
    s, j = http("POST", "/auth/v1/signup", {})
    tok, uid = (j or {}).get("access_token"), ((j or {}).get("user") or {}).get("id")
    caso("se puede crear una sesión anónima", bool(tok and uid), f"{s} {j}")
    if not tok:
        return False

    try:
        print("el invitado deja sus datos y compra")
        datos = {"p_nombre": "Invitado", "p_apellido": "Prueba",
                 "p_email": CORREO_PRUEBA, "p_ci": "1234567",
                 "p_telefono": None, "p_acepta": True}

        # el formulario no deja pasar sin los 18+ ni con un correo inventado
        caso("sin aceptar los términos no entra",
             rpc("aftr_datos_de_compra", {**datos, "p_acepta": False}, tok)[0] >= 400)
        caso("con un correo malo no entra",
             rpc("aftr_datos_de_compra", {**datos, "p_email": "no-es-correo"}, tok)[0] >= 400)

        s, j = rpc("aftr_datos_de_compra", datos, tok)
        caso("el formulario guarda", s == 200, f"{s} {j}")
        if s == 200:
            caso("queda la constancia de los 18+ y los términos",
                 j.get("mayor_edad") is True and bool(j.get("acepto_at")), str(j))
            caso("quedan apellido, correo y carnet",
                 j.get("apellido") == "Prueba" and j.get("email") == CORREO_PRUEBA
                 and j.get("ci") == "1234567", str(j))

        for fn in ("aftr_mi_perfil", "aftr_mis_accesos"):
            s, j = rpc(fn, {}, tok)
            caso(f"{fn} le sirve al invitado", s == 200, f"{s} {j}")

        print("y todo lo que no es comprar le pide cuenta de verdad")
        puertas = [
            ("aftr_pulse", {}),
            ("aftr_recargar_pulse", {"p_centavos": 10000, "p_client_key": str(uuid.uuid4())}),
            ("aftr_mis_mesas", {}),
            ("aftr_carta_mesa", {"p_mesa": CERO}),
            ("aftr_mis_pedidos_mesa", {"p_mesa": CERO}),
            ("aftr_reservar_mesa", {"p_evento": CERO, "p_mesa": CERO,
                                    "p_combo": None, "p_client_key": str(uuid.uuid4())}),
            # con un id de historia que no existe: si la guarda quedara detrás
            # del declare, contestaría "La historia ya no está disponible"
            ("aftr_reservar_historia", {"p_historia": CERO, "p_evento": CERO, "p_mesa": None,
                                        "p_combo": None, "p_client_key": str(uuid.uuid4())}),
            ("aftr_historias", {"p_accion": "mias"}),
            ("aftr_reventa", {"p_accion": "mis_ofertas"}),
            ("aftr_rachas", {}),
            ("aftr_amistad", {"p_accion": "pedir", "p_usuario": "alguien"}),
            ("aftr_buscar_usuario", {"p_q": "ana"}),
            ("aftr_transferir", {"p_entrada": CERO, "p_usuario": "alguien"}),
            ("aftr_anotarme_lista", {"p_evento": CERO, "p_lista": CERO}),
            ("aftr_guardar", {"p_evento": CERO}),
            ("aftr_seguir", {"p_club": "burtown"}),
            ("aftr_cambiar_foto", {"p_archivo": "x/y.jpg"}),
        ]
        for fn, params in puertas:
            r = rpc(fn, params, tok)
            caso(f"{fn} le pide cuenta", pide_cuenta(r), f"{r[0]} {r[1]}")
    finally:
        # No queda nada: ni el perfil ni el usuario anónimo.
        servicio("DELETE", f"/rest/v1/aftr_clientes?user_id=eq.{uid}")
        servicio("DELETE", f"/auth/v1/admin/users/{uid}")
        s, j = servicio("GET", f"/rest/v1/aftr_clientes?user_id=eq.{uid}&select=user_id")
        caso("la prueba no deja residuo", s == 200 and not j, f"{s} {j}")

    mal = [n for n, b in res if not b]
    print()
    print(f"{len(res) - len(mal)}/{len(res)} bien" + (f", FALLAN: {mal}" if mal else ""))
    return not mal


if __name__ == "__main__":
    sys.exit(0 if main() else 1)
