#!/usr/bin/env python3
"""Aplica archivos SQL al proyecto Supabase de .env.local.

Uso:  python3 tools/aplicar.py db/18-helpers-permiso.sql [más.sql …]
      python3 tools/aplicar.py --sql "select 1"

Necesita la función temporal public._venue_exec (solo service_role), que se
crea a mano antes de instalar y se elimina al terminar. Cada archivo corre en
una sola transacción: o entra entero o no entra.
"""
import json, re, sys, urllib.request, urllib.error

env = dict(re.findall(r"^(\w+)=(.*)$", open(".env.local").read(), re.M))
URL, KEY = env["SUPABASE_URL"], env["SUPABASE_SERVICE_ROLE_KEY"]

def ejecutar(sql):
    req = urllib.request.Request(
        f"{URL}/rest/v1/rpc/_venue_exec", method="POST",
        data=json.dumps({"q": sql}).encode(),
        headers={"apikey": KEY, "Authorization": f"Bearer {KEY}",
                 "Content-Type": "application/json"})
    try:
        urllib.request.urlopen(req, timeout=120).read()
        return None
    except urllib.error.HTTPError as e:
        try: return json.loads(e.read())
        except Exception: return {"message": str(e)}

args = sys.argv[1:]
pre = ""
if args and args[0] == "--sin-validar-cuerpos":
    pre = "set local check_function_bodies = off;\n"; args = args[1:]
if args and args[0] == "--sql":
    err = ejecutar(args[1]); print("OK" if not err else err); sys.exit(1 if err else 0)
for f in args:
    err = ejecutar(pre + open(f).read())
    if err:
        print(f"FALLA  {f}\n       {err.get('message')}\n       {err.get('details') or ''} {err.get('hint') or ''}")
        sys.exit(1)
    print(f"ok     {f}")
ejecutar("notify pgrst, 'reload schema'")
