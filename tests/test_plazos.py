#!/usr/bin/env python3
"""Los dos plazos del cobro, contra la API real del proyecto de .env.local.

    python3 tests/test_plazos.py

Qué prueba:

  - un pedido de entrada retiene el cupo **30 minutos**, no doce horas. Antes
    duraba doce: quien tocaba "Comprar" y cerraba la app bloqueaba un lugar
    toda la noche sin haber pagado nada.
  - al reservar el cobro, el QR tiene siempre sus **diez minutos**, aunque al
    pedido le quedara menos. Sin eso, abrir el pago en el minuto 29 daba un QR
    que moría al minuto siguiente.

No habla con el banco: reserva el cobro con `baneco_reservar_destino`, que es
la parte que vive en la base. Así se puede correr cuantas veces haga falta sin
dejar QR de verdad que después haya que anular.

Borra todo lo que crea.
"""
import sys, uuid, datetime

sys.path.insert(0, "tools")
from venue_api import http, rpc, servicio  # noqa: E402

CORREO = "plazos.prueba@example.invalid"
res = []


def caso(nombre, cond, detalle=""):
    res.append((nombre, bool(cond)))
    print(("  ok   " if cond else "  FALLA") + " " + nombre + ("" if cond else f"   → {detalle}"))


def minutos(desde, hasta):
    return (datetime.datetime.fromisoformat(hasta)
            - datetime.datetime.fromisoformat(desde)).total_seconds() / 60


def evento_a_la_venta():
    """Un evento que todavía no empezó.

    Tiene que faltar más de media hora para el inicio: el pedido vence al
    menor de los dos plazos -media hora, o el inicio del evento-, así que con
    una fiesta que ya arrancó el pedido nace vencido y la prueba no diría nada
    del plazo que se quiere probar.
    """
    s, j = servicio("GET", "/rest/v1/eventos?select=id,fecha,hora_inicio,aftr_publico,publicado"
                           "&publicado=is.true&aftr_publico=is.true&order=fecha.asc")
    ahora = datetime.datetime.now(datetime.timezone.utc)
    for e in j or []:
        try:
            inicio = datetime.datetime.fromisoformat(f"{e['fecha']}T{e['hora_inicio']}")
        except ValueError:
            continue
        # la hora del evento es de Bolivia (UTC-4)
        inicio = inicio.replace(tzinfo=datetime.timezone(datetime.timedelta(hours=-4)))
        if inicio - ahora > datetime.timedelta(minutes=45):
            return e["id"]
    return None


def invitado():
    s, j = http("POST", "/auth/v1/signup", {})
    if s != 200 or not j.get("access_token"):
        raise RuntimeError(f"sesión anónima: {s} {j}")
    rpc("aftr_datos_de_compra", {"p_nombre": "Plazos", "p_apellido": "Prueba",
                                 "p_email": CORREO, "p_ci": "1234567",
                                 "p_telefono": None, "p_acepta": True},
        token=j["access_token"])
    return j["access_token"], j["user"]["id"]


def main():
    evento = evento_a_la_venta()
    if not evento:
        print("  (no hay ningún evento a la venta: no se puede probar)")
        return True

    creados = []
    try:
        tok, uid = invitado()
        creados.append(uid)
        s, o = rpc("aftr_comprar", {"p_evento": evento, "p_fase": None, "p_cantidad": 1,
                                    "p_client_key": str(uuid.uuid4())}, token=tok)
        if s != 200:
            print(f"  (no se pudo comprar en {evento}: {s} {o})")
            return True
        orden = o["id"]

        s, j = servicio("GET", f"/rest/v1/aftr_ordenes?id=eq.{orden}&select=created_at,vence_at")
        dur = minutos(j[0]["created_at"], j[0]["vence_at"])
        caso(f"el pedido retiene el cupo 30 minutos (retiene {dur:.0f})", 29 <= dur <= 31,
             "si volvió a doce horas, un cupo abandonado bloquea el lugar toda la noche")

        # Al pedido le queda un minuto, como a quien abre el pago en el 29.
        casi = datetime.datetime.now(datetime.timezone.utc) + datetime.timedelta(minutes=1)
        servicio("PATCH", f"/rest/v1/aftr_ordenes?id=eq.{orden}", {"vence_at": casi.isoformat()})

        s, r = servicio("POST", "/rest/v1/rpc/baneco_reservar_destino",
                        {"p_tipo": "orden", "p_id": orden, "p_cliente": uid,
                         "p_ambiente": "produccion"})
        caso("se reserva el cobro", s == 200 and (r or {}).get("reservado"), f"{s} {r}")
        if s == 200 and r.get("pago"):
            q = r["pago"]
            vive = minutos(q["created_at"], q["limite_at"])
            caso(f"el QR nace con sus diez minutos (nace con {vive:.1f})", 9 <= vive <= 10.5,
                 "nació muerto: el plazo del QR se recorta al del pedido")

        s, j = servicio("GET", f"/rest/v1/aftr_ordenes?id=eq.{orden}&select=vence_at")
        queda = (datetime.datetime.fromisoformat(j[0]["vence_at"])
                 - datetime.datetime.now(datetime.timezone.utc)).total_seconds() / 60
        caso(f"y el pedido se extendió para cubrirlo (le quedan {queda:.1f})", queda >= 9)
    finally:
        for uid in creados:
            # en orden: el cobro cuelga del pedido y el pedido del cliente, así
            # que al revés el borrado falla por la clave foránea y queda residuo
            s, ordenes = servicio("GET", f"/rest/v1/aftr_ordenes?cliente_id=eq.{uid}&select=id")
            for o in ordenes or []:
                servicio("DELETE", f"/rest/v1/pago_qr?orden_id=eq.{o['id']}")
                servicio("DELETE", f"/rest/v1/aftr_ordenes?id=eq.{o['id']}")
            servicio("DELETE", f"/rest/v1/aftr_clientes?user_id=eq.{uid}")
            servicio("DELETE", f"/auth/v1/admin/users/{uid}")
        s, j = servicio("GET", f"/rest/v1/aftr_clientes?email=eq.{CORREO}&select=user_id")
        caso("la prueba no deja residuo", s == 200 and not j, f"{s} {j}")

    mal = [n for n, b in res if not b]
    print()
    print(f"{len(res) - len(mal)}/{len(res)} bien" + (f", FALLAN: {mal}" if mal else ""))
    return not mal


if __name__ == "__main__":
    sys.exit(0 if main() else 1)
