"""Cliente mínimo de Supabase (solo librería estándar) para el seed y los tests."""
import json, re, urllib.request, urllib.error, urllib.parse

_env = dict(re.findall(r"^(\w+)=(.*)$", open(".env.local").read(), re.M))
URL, ANON, SERVICE = _env["SUPABASE_URL"], _env["SUPABASE_ANON_KEY"], _env["SUPABASE_SERVICE_ROLE_KEY"]
DOMINIO = "plataforma.local"


def http(metodo, ruta, cuerpo=None, token=None, apikey=None, extra=None):
    """Devuelve (status, json). `token` None = anónimo."""
    apikey = apikey or ANON
    h = {"apikey": apikey, "Authorization": f"Bearer {token or apikey}",
         "Content-Type": "application/json"}
    h.update(extra or {})
    req = urllib.request.Request(URL + ruta, method=metodo, headers=h,
                                 data=None if cuerpo is None else json.dumps(cuerpo).encode())
    try:
        with urllib.request.urlopen(req, timeout=60) as r:
            t = r.read().decode()
            return r.status, (json.loads(t) if t else None)
    except urllib.error.HTTPError as e:
        t = e.read().decode()
        try: return e.code, json.loads(t)
        except Exception: return e.code, {"message": t}


def servicio(metodo, ruta, cuerpo=None, extra=None):
    return http(metodo, ruta, cuerpo, token=SERVICE, apikey=SERVICE, extra=extra)


def rpc(nombre, params=None, token=None):
    return http("POST", f"/rest/v1/rpc/{nombre}", params or {}, token=token)


def login(usuario, clave):
    s, j = http("POST", "/auth/v1/token?grant_type=password",
                {"email": f"{usuario}@{DOMINIO}", "password": clave})
    if s != 200:
        raise RuntimeError(f"login {usuario}: {j}")
    return j["access_token"]


def q(v):
    return urllib.parse.quote(str(v), safe="")
