#!/usr/bin/env python3
"""Ninguna RPC de `public` queda sin control de permiso. Sin red ni base.

    python3 tests/rpc_con_guarda.py

Toda función `security definer` corre con los permisos del dueño: adentro no
hay RLS que valga. Si no comprueba quién llama, cualquiera con una sesión la
ejecuta con un `curl`, sin pasar por la app.

`db/19-rpc-guardas.sql` tenía un chequeo de cobertura para esto, pero exigía
que cada función estuviera en su matriz `impl.rpc_permiso`, y el sistema
creció por otro lado: hoy 119 de 198 funciones hacen la comprobación adentro
(`impl.exigir`, `rol_en_club`, un `impl.*` que ya la hace). Son dos estilos
válidos; el chequeo de db/19 solo conocía uno, así que quedó sin correr.

Esto comprueba lo que de verdad importa: que cada función esté en la matriz,
compruebe adentro, o esté acá abajo como excepción con su motivo escrito.
Lo que aparece sin nada es un agujero y hay que mirarlo.
"""
import re
import sys
from pathlib import Path

RAIZ = Path(__file__).resolve().parent.parent

# Helpers que solo informan el rol de quien pregunta: no hay nada que abrir.
HELPERS = {
    'rol_actual', 'mi_team_base', 'es_platform_admin', 'rol_en_club',
    'mi_team_en_club', 'mis_clubs', 'rol_en', 'admin_de_clubs', 'comparte_club',
}

# Excepciones, cada una con el motivo por el que no comprueba quién llama.
EXCEPCIONES = {
    '_venue_exec': 'instalador temporal de tools/aplicar.py, solo service_role',
    'aftr_eventos': 'catálogo público de AFTR: mirar no pide cuenta',
    'aftr_lugares': 'catálogo público de AFTR: mirar no pide cuenta',
    'aftr_calor': 'dónde hay movimiento, en intensidad de 0 a 1 y sin números',
    'aftr_historia_visible': 'helper booleano de las políticas de historias',
    'aftr_foto_de_perfil': 'helper booleano de la política del bucket de fotos',
    'aftr_social_ruta_nueva': 'helper booleano de la política de subida',
    'aftr_social_borrable': 'helper booleano de la política de borrado',
    'aftr_social_limpieza': 'tarea programada, solo service_role',
    'baneco_tomar_barrido': 'barrido del banco, solo service_role',
    'baneco_finalizar_barrido': 'barrido del banco, solo service_role',
    'ver_invitacion': 'se resuelve por el token del enlace, que es el permiso',
    'ver_invitacion_rol': 'se resuelve por el token del enlace, que es el permiso',
    'aftr_mis_accesos': 'delega en impl.aftr_mis_accesos_social_base(), que es la '
                        'versión anterior de esta misma función y arranca con '
                        'impl.aftr_yo(): sin sesión no pasa de ahí',
    # Las dos envolturas de historia no comprueban sesión: delegan en la compra
    # real, que arranca con impl.aftr_yo(). Lo que ellas sí validan es que la
    # historia exista y siga vigente.
    'aftr_comprar_historia': 'delega en aftr_comprar, que arranca con impl.aftr_yo()',
    'aftr_reservar_historia': 'delega en aftr_reservar_mesa, que arranca con impl.aftr_yo()',
    # El cobro del banco: lo llama la Edge Function con la llave de servicio.
    # Ninguna está concedida a authenticated ni a anon (db/44 y 20261031172015
    # las revocan), así que el permiso es el grant.
    'aftr_pago_confirmado': 'solo service_role: la llama la Edge Function del banco',
    'aftr_pago_confirmado_entradas': 'solo service_role: la llama la Edge Function del banco',
    'baneco_qr_anulado': 'solo service_role: la llama el barrido del banco',
    'baneco_reservar_destino': 'solo service_role: la llama la Edge Function del banco',
    'baneco_reservar_qr': 'solo service_role: la llama la Edge Function del banco',
    'baneco_liberar_sin_qr': 'solo service_role: la llama la Edge Function del banco',
    'aftr_limite_externo': 'solo service_role: recibe el actor de afuera, porque la '
                           'Edge Function no tiene sesion sino una IP',
}

# Señales de que la función comprueba quién llama.
SEÑALES = (
    'impl.exigir', 'exigir_sesion', 'rol_en_club', 'es_platform_admin',
    'auth.uid()', 'rol_en(', 've_registro', 'impl.aftr_yo', 'impl.aftr_staff',
    'impl.team_en_club', 'mi_team_en_club', 'impl.aftr_bar_staff',
    'impl.incidencias_admin',
)


def funciones():
    """Las funciones `security definer` de public, con su último cuerpo."""
    hallazgo = {}
    archivos = sorted((RAIZ / 'db').glob('*.sql')) + sorted(
        (RAIZ / 'supabase' / 'migrations').glob('*.sql')
    )
    for f in archivos:
        t = f.read_text(encoding='utf-8')
        for m in re.finditer(
            r'create (?:or replace )?function\s+(?:public\.)?([a-z0-9_]+)\s*\(',
            t, re.I,
        ):
            nombre = m.group(1)
            cabecera = t[m.end():m.end() + 400].lower().split('as $')[0]
            if 'security definer' not in cabecera:
                continue
            if 'returns trigger' in cabecera:
                continue  # un trigger no es una RPC: nadie lo llama de afuera
            # El cuerpo termina en SU comilla, no en el próximo `$$;` del
            # archivo: midiendo mal, una función sin control parecía tenerlo
            # porque leía el cuerpo de la de abajo.
            cita = re.search(r'\bas\s+(\$[a-z_]*\$)', t[m.end():], re.I)
            if cita:
                desde = m.end() + cita.end()
                cierre = t.find(cita.group(1), desde)
                cuerpo = t[desde:cierre if cierre != -1 else desde + 8000]
            else:
                cuerpo = t[m.end():m.end() + 8000]
            hallazgo[nombre] = (cuerpo, f.name)
    return hallazgo


def en_la_matriz():
    guardas = (RAIZ / 'db' / '19-rpc-guardas.sql').read_text(encoding='utf-8')
    return set(re.findall(r"^\('([a-z0-9_]+)'", guardas, re.M))


def main():
    todas = funciones()
    matriz = en_la_matriz()
    sin_guarda = []
    por_matriz = por_dentro = por_excepcion = 0
    for nombre, (cuerpo, archivo) in sorted(todas.items()):
        if nombre in HELPERS:
            continue
        if nombre in matriz:
            por_matriz += 1
        elif any(s in cuerpo.lower() for s in SEÑALES):
            por_dentro += 1
        elif nombre in EXCEPCIONES:
            por_excepcion += 1
        else:
            sin_guarda.append((nombre, archivo))

    print(f'  {por_matriz} con guarda generada por la matriz de db/19')
    print(f'  {por_dentro} que comprueban adentro')
    print(f'  {por_excepcion} excepciones con motivo escrito')
    if sin_guarda:
        print('\nFALLA · RPC de public sin control de permiso:')
        for nombre, archivo in sin_guarda:
            print(f'  - {nombre}  ({archivo})')
        print('\nAgregala a impl.rpc_permiso, comprobá adentro con impl.exigir,')
        print('o anotala en EXCEPCIONES con el motivo.')
        return 1
    print('\nok · ninguna RPC de public queda sin control de permiso')
    return 0


if __name__ == '__main__':
    sys.exit(main())
