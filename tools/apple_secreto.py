#!/usr/bin/env python3
"""Secreto de "Sign in with Apple" para Supabase (Auth → Providers → Apple).

Apple no da un secreto fijo: es un JWT firmado con la clave .p8 de Sign in
with Apple, y vence a los 6 meses como máximo. Hay que regenerarlo antes de
que venza y pegarlo de nuevo en Supabase.

Uso:  python3 tools/apple_secreto.py ~/Downloads/AuthKey_972YCP56Z6.p8 | pbcopy
Necesita PyJWT y cryptography (pip install pyjwt cryptography).

Services ID de las webs: app.venue.aftr.web (team WYCP7K767H). En Supabase,
Client IDs = "app.venue.aftr.web,app.venue.aftr" (el segundo es la app de AFTR).
"""
import sys, time
from pathlib import Path
import jwt

TEAM, CLIENTE, DIAS = "WYCP7K767H", "app.venue.aftr.web", 180

ruta = Path(sys.argv[1]).expanduser()
kid = ruta.stem.replace("AuthKey_", "")
ahora = int(time.time())
print(jwt.encode(
    {"iss": TEAM, "iat": ahora, "exp": ahora + DIAS * 86400, "aud": "https://appleid.apple.com", "sub": CLIENTE},
    ruta.read_text(), algorithm="ES256", headers={"kid": kid}), end="")
