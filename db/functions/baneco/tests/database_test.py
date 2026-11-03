"""Regresiones sobre un PostgreSQL descartable, sin datos ni conexiones reales.

Uso: python3 database_test.py SOCKET RAIZ_REPO MIGRACION
El socket debe ser /private/tmp/venue-baneco-* y la DB se llama baneco_test.
"""
from pathlib import Path
import concurrent.futures
import json
import subprocess
import sys
import unittest

SOCKET, ROOT, MIGRATION = sys.argv[1:4]
if not SOCKET.startswith('/private/tmp/venue-baneco-'):
    raise SystemExit('Sólo se permite el socket de pruebas local')
PSQL = ['/opt/homebrew/opt/postgresql@17/bin/psql', '-X', '-qAt', '-v', 'ON_ERROR_STOP=1', '-h', SOCKET, '-p', '55439', '-d', 'baneco_test']
def sql(query):
    p = subprocess.run(PSQL, input=query, text=True, capture_output=True)
    if p.returncode:
        raise AssertionError(p.stderr)
    return p.stdout.strip()

fixture = '''
do $$ begin
  if not exists(select 1 from pg_roles where rolname='anon') then create role anon; end if;
  if not exists(select 1 from pg_roles where rolname='authenticated') then create role authenticated; end if;
  if not exists(select 1 from pg_roles where rolname='service_role') then create role service_role bypassrls; end if;
end $$;
create schema impl; create schema auth;
create function auth.uid() returns uuid language sql as $$ select null::uuid $$;
create table aftr_clientes(user_id uuid primary key, nombre text);
create table evento_fase(id uuid primary key, cupo int);
create table aftr_ordenes(id uuid primary key, cliente_id uuid, evento_id uuid,
 tipo text default 'entrada', fase_id uuid, mesa_id uuid, cantidad int default 1,
 precio_unit numeric default 25.50, total numeric default 25.50, estado text default 'pendiente',
 vence_at timestamptz default now()+interval '1 hour', confirmada_por uuid, confirmada_at timestamptz);
create table entradas(id uuid primary key, evento_id uuid, code text, cliente text, rrpp_id uuid,
 precio numeric, estado text, created_at timestamptz, fase_id uuid, cliente_id uuid, canal text, mesa_id uuid);
create table mesas(id uuid primary key, cliente_id uuid, estado text, pagada_por uuid, pagada_at timestamptz,
 pago_verificado boolean, verificado_por uuid, verificado_at timestamptz, reserva_vence_at timestamptz,
 updated_at timestamptz, manillas int);
create function gen_code_evento(uuid) returns text language sql as $$ select gen_random_uuid()::text $$;
create function impl.aftr_staff_orden(p_orden uuid) returns aftr_ordenes language sql as $$ select * from aftr_ordenes where id=p_orden for update $$;
'''
base = (Path(ROOT)/'db/44-pagos-banco.sql').read_text()
fixture += base[base.index('create table if not exists pago_qr'):base.index('-- ── emisión:')]
sql(fixture)
sql(Path(MIGRATION).read_text())
CLIENTE = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'
ORDEN = '11111111-1111-4111-8111-111111111111'
FASE = 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb'
PAGO = {'qrId': 'qr', 'transactionId': 'banco-123', 'amount': 25.50, 'currency': 'BOB'}
def confirmar(pago=None):
    return json.loads(sql("select aftr_pago_confirmado('qr', '%s'::jsonb)" % json.dumps(pago or PAGO)))

class BancoDB(unittest.TestCase):
    def setUp(self):
        sql(f"""truncate pago_qr, aftr_ordenes, entradas, mesas, evento_fase, aftr_clientes, baneco_conciliacion;
          insert into aftr_clientes values('{CLIENTE}','Cliente de prueba');
          insert into evento_fase values('{FASE}', 10);
          insert into aftr_ordenes(id,cliente_id,evento_id,fase_id) values('{ORDEN}','{CLIENTE}','{FASE}','{FASE}');""")
    def qr(self):
        sql(f"""insert into pago_qr(orden_id,ambiente,transaction_id,qr_id,monto,moneda,vence)
          values('{ORDEN}','certificacion','comercio-123','qr',25.50,'BOB',current_date+1)""")
    def test_confirmacion_idempotente(self):
        self.qr(); self.assertTrue(confirmar()['nuevo']); self.assertFalse(confirmar()['nuevo'])
        self.assertEqual(sql('select count(*) from entradas'), '1')
        self.assertEqual(sql('select transaction_id || \'/\' || banco_tx from pago_qr'), 'comercio-123/banco-123')
    def test_rechaza_qr_diferente(self):
        self.qr(); self.assertEqual(confirmar({**PAGO,'qrId':'otro'})['estado'], 'revisar')
        self.assertEqual(sql('select count(*) from entradas'), '0')
    def test_rechaza_monto_moneda_y_tx_faltante(self):
        for cambio in [{'amount':0.01}, {'amount':'invalido'}, {'currency':'USD'}, {'transactionId':''}]:
            self.setUp(); self.qr()
            self.assertEqual(confirmar({**PAGO,**cambio})['estado'], 'revisar')
            self.assertEqual(sql('select count(*) from entradas'), '0')
    def test_pago_tardio_sin_cupo_no_emite(self):
        self.qr(); sql("update aftr_ordenes set estado='vencida'; update evento_fase set cupo=0")
        self.assertEqual(confirmar()['estado'], 'revisar')
        self.assertEqual(sql('select count(*) from entradas'), '0')
        self.assertEqual(sql('select banco_tx from pago_qr'), 'banco-123')
    def test_pago_tardio_con_cupo_emite(self):
        self.qr(); sql("update aftr_ordenes set estado='vencida'")
        self.assertEqual(confirmar()['estado'], 'pagado')
        self.assertEqual(sql('select count(*) from entradas'), '1')
    def test_pago_cancelado_se_conserva_para_revision(self):
        self.qr(); sql("update aftr_ordenes set estado='cancelada'")
        self.assertEqual(confirmar()['estado'], 'revisar')
        self.assertEqual(sql('select count(*) from entradas'), '0')
        self.assertEqual(sql('select banco_tx from pago_qr'), 'banco-123')
    def test_confirmacion_manual_se_registra_sin_duplicar(self):
        self.qr(); sql(f"select impl.aftr_emitir_orden('{ORDEN}',null)")
        self.assertFalse(confirmar()['nuevo']); self.assertEqual(sql('select count(*) from entradas'), '1')
        self.assertEqual(sql('select estado from pago_qr'), 'pagado')
    def test_confirmacion_manual_no_salta_el_banco(self):
        self.qr()
        with self.assertRaises(AssertionError): sql(f"select aftr_confirmar_orden('{ORDEN}')")
        self.assertEqual(sql('select count(*) from entradas'), '0')
    def test_reintento_manual_solo_con_dinero_confirmado(self):
        self.qr(); sql('update evento_fase set cupo=0')
        self.assertEqual(confirmar()['estado'], 'revisar')
        sql('update evento_fase set cupo=10')
        self.assertEqual(json.loads(sql(f"select aftr_confirmar_orden('{ORDEN}')"))['emitidas'], 1)
        self.assertEqual(sql('select estado from pago_qr'), 'pagado')
    def test_confirmaciones_concurrentes(self):
        self.qr()
        with concurrent.futures.ThreadPoolExecutor(max_workers=2) as pool:
            resultados = list(pool.map(lambda _: confirmar(), range(2)))
        self.assertEqual(sum(r['nuevo'] for r in resultados), 1)
        self.assertEqual(sql('select count(*) from entradas'), '1')
    def test_reservas_concurrentes(self):
        consulta=f"select baneco_reservar_qr('{ORDEN}','{CLIENTE}','certificacion')"
        with concurrent.futures.ThreadPoolExecutor(max_workers=2) as pool:
            resultados=list(pool.map(lambda _: json.loads(sql(consulta)),range(2)))
        self.assertEqual(sum(r['reservado'] for r in resultados), 1)
        self.assertEqual(sql('select count(*) from pago_qr'), '1')
    def test_no_regenera_cobro_incierto(self):
        consulta=f"select baneco_reservar_qr('{ORDEN}','{CLIENTE}','certificacion')"
        self.assertTrue(json.loads(sql(consulta))['reservado'])
        sql("update pago_qr set estado='revisar',nota='GENERACION_INCIERTA'")
        self.assertFalse(json.loads(sql(consulta))['reservado'])
    def test_no_reserva_pedido_vencido(self):
        sql("update aftr_ordenes set vence_at=now()-interval '1 minute'")
        with self.assertRaises(AssertionError): sql(f"select baneco_reservar_qr('{ORDEN}','{CLIENTE}','certificacion')")
    def test_lease_y_cursor_persistente(self):
        self.qr(); sql("update pago_qr set created_at=now()-interval '3 days'")
        trabajo=json.loads(sql("select baneco_tomar_barrido('certificacion')"))
        self.assertEqual(sql("select baneco_tomar_barrido('certificacion')"), '')
        sql(f"select baneco_finalizar_barrido('certificacion','{trabajo['token']}',null,1)")
        self.assertEqual(sql('select dia from baneco_conciliacion'),trabajo['dia'])
        segundo=json.loads(sql("select baneco_tomar_barrido('certificacion')"))
        sql(f"select baneco_finalizar_barrido('certificacion','{segundo['token']}','{segundo['dia']}',0)")
        self.assertEqual(sql("select dia = '%s'::date + 1 from baneco_conciliacion" % trabajo['dia']), 't')
    def test_dia_conciliado_avanza_aunque_falle_un_estado_individual(self):
        self.qr(); sql("update pago_qr set created_at=now()-interval '3 days'")
        trabajo=json.loads(sql("select baneco_tomar_barrido('certificacion')"))
        sql(f"select baneco_finalizar_barrido('certificacion','{trabajo['token']}','{trabajo['dia']}',1)")
        self.assertEqual(sql("select dia = '%s'::date + 1 from baneco_conciliacion" % trabajo['dia']), 't')
    def test_permisos_de_confirmacion_y_reserva(self):
        for rol in ['anon','authenticated']:
            self.assertEqual(sql(f"select has_function_privilege('{rol}','aftr_pago_confirmado(text,jsonb)','execute')"),'f')
            self.assertEqual(sql(f"select has_function_privilege('{rol}','baneco_reservar_qr(uuid,uuid,text)','execute')"),'f')
        self.assertEqual(sql("select relrowsecurity from pg_class where relname='baneco_conciliacion'"),'t')
        self.assertEqual(sql("select has_function_privilege('authenticated','impl.aftr_emitir_orden(uuid,uuid)','execute')"),'f')

if __name__ == '__main__':
    unittest.main(argv=[sys.argv[0]], verbosity=2)
