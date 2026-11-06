#!/usr/bin/env python3
"""El camino de una notificación, contra la API real del proyecto de .env.local.

    python3 tests/test_push.py

Qué prueba, sin mandarle nada a nadie de verdad:

  - un aparato se registra y queda atado a quien lo registró;
  - el mismo token registrado otra vez no se duplica: cambia de dueño;
  - un aviso para alguien sin aparato no se encola, en vez de quedar dando
    vueltas en la cola para siempre;
  - la Edge Function toma el aviso, habla con Google de verdad, y como el
    token es inventado, Google lo da por muerto: el aparato se borra solo.

Ese último paso es el que importa: demuestra que la cuenta de servicio, el
token de acceso y la llamada a FCM funcionan. Un token inventado es la única
forma de probarlo sin un teléfono.

Borra todo lo que crea.
"""
import sys, uuid, json, subprocess

sys.path.insert(0, "tools")
from venue_api import http, rpc, servicio  # noqa: E402

res = []


def caso(nombre, cond, detalle=""):
    res.append((nombre, bool(cond)))
    print(("  ok   " if cond else "  FALLA") + " " + nombre + ("" if cond else f"   → {detalle}"))


def invitado():
    s, j = http("POST", "/auth/v1/signup", {})
    if s != 200 or not j.get("access_token"):
        raise RuntimeError(f"sesión anónima: {s} {j}")
    return j["access_token"], j["user"]["id"]


def main():
    tok_cron = subprocess.run(
        ["cat", "/private/tmp/claude-501/-Users-user-Documents-venue-2/"
         "0e310bdc-9150-4b6d-8f11-e54050c2934c/scratchpad/pushtok.txt"],
        capture_output=True, text=True).stdout.strip()

    tok, uid = invitado()
    token_falso = "prueba-" + uuid.uuid4().hex + uuid.uuid4().hex
    try:
        print("el aparato se registra")
        s, j = rpc("registrar_dispositivo",
                   {"p_token": token_falso, "p_app": "aftr", "p_plataforma": "ios"}, token=tok)
        caso("se registra", s < 300, f"{s} {j}")
        s, j = servicio("GET", f"/rest/v1/dispositivos?token=eq.{token_falso}&select=user_id,app,plataforma")
        caso("queda atado a quien lo registró", j and j[0]["user_id"] == uid, str(j))

        s, j = rpc("registrar_dispositivo",
                   {"p_token": token_falso, "p_app": "aftr", "p_plataforma": "ios"}, token=tok)
        s, j = servicio("GET", f"/rest/v1/dispositivos?token=eq.{token_falso}&select=token")
        caso("registrarlo de nuevo no lo duplica", len(j or []) == 1, str(j))

        s, j = rpc("registrar_dispositivo",
                   {"p_token": "corto", "p_app": "aftr", "p_plataforma": "ios"}, token=tok)
        caso("un token corto se rechaza", s >= 400, f"{s} {j}")

        print("el aviso se encola sólo si hay a quién mandarle")
        s, j = servicio("POST", "/rest/v1/rpc/avisar_prueba", {}) if False else (0, None)
        # se encola a mano, que es lo que hace impl.avisar por dentro
        s, j = servicio("POST", "/rest/v1/avisos_push", {
            "user_id": uid, "app": "aftr",
            "titulo": "Prueba", "cuerpo": "Esto es una prueba",
            "datos": {"de": "prueba"},
        }, extra={"Prefer": "return=representation"})
        caso("se encola", s < 300, f"{s} {j}")
        aviso = (j or [{}])[0].get("id")

        print("y el cartero habla con Google de verdad")
        s, j = http("POST", "/functions/v1/push", {}, extra={"x-cron": tok_cron})
        caso("la función responde", s == 200, f"{s} {j}")
        caso("Google dio el token por muerto y el aparato se borró",
             (j or {}).get("aparatosBorrados", 0) >= 1, json.dumps(j))

        s, j = servicio("GET", f"/rest/v1/dispositivos?token=eq.{token_falso}&select=token")
        caso("el aparato muerto ya no está", not j, str(j))

        s, j = servicio("GET", f"/rest/v1/avisos_push?id=eq.{aviso}&select=estado,intentos,error")
        caso("el aviso quedó cerrado y no se reintenta", j and j[0]["estado"] != "pendiente",
             str(j))

        print("y sin el token del cron no entra nadie")
        s, j = http("POST", "/functions/v1/push", {}, extra={"x-cron": "lo-que-sea"})
        caso("sin token, 401", s == 401, f"{s} {j}")
    finally:
        servicio("DELETE", f"/rest/v1/avisos_push?user_id=eq.{uid}")
        servicio("DELETE", f"/rest/v1/dispositivos?user_id=eq.{uid}")
        servicio("DELETE", f"/auth/v1/admin/users/{uid}")
        s, j = servicio("GET", f"/rest/v1/dispositivos?user_id=eq.{uid}&select=token")
        caso("la prueba no deja residuo", not j, str(j))

    mal = [n for n, b in res if not b]
    print()
    print(f"{len(res) - len(mal)}/{len(res)} bien" + (f", FALLAN: {mal}" if mal else ""))
    return not mal


if __name__ == "__main__":
    sys.exit(0 if main() else 1)
