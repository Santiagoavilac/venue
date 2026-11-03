"""Dinero, stock y RLS sobre PostgreSQL descartable, sin red ni credenciales."""
from pathlib import Path
import concurrent.futures
import json
import subprocess
import sys
import unittest

SOCKET, ROOT = sys.argv[1:3]
assert SOCKET.startswith('/private/tmp/venue-pulse-')
ROOT = Path(ROOT)
PSQL = ['/opt/homebrew/opt/postgresql@17/bin/psql', '-XqAt', '-v', 'ON_ERROR_STOP=1', '-h', SOCKET, '-p', '55440', '-d', 'pulse_test']
def sql(query, user=None, role=None):
    prefix = "set check_function_bodies=off;"
    if user:
        prefix += f"set request.jwt.claim.sub='{user}';"
    if role:
        prefix += f"set role {role};"
    r = subprocess.run(PSQL, input=prefix+query, text=True, capture_output=True)
    if r.returncode:
        raise AssertionError(r.stderr)
    return r.stdout.strip()

sql('''create role anon; create role authenticated; create role service_role bypassrls;
create schema impl; create schema auth; create table auth.users(id uuid primary key);
create publication supabase_realtime;
create function auth.uid() returns uuid language sql stable as $$select nullif(current_setting('request.jwt.claim.sub',true),'')::uuid$$;
grant usage on schema public,impl,auth to authenticated,anon,service_role;
grant execute on function auth.uid() to public;
''')
sql((ROOT/'db/01-tablas.sql').read_text())
fases=(ROOT/'db/02d-rpc-fases.sql').read_text()
sql(fases[fases.index('create table if not exists evento_fase'):fases.index('create or replace function')])
sql((ROOT/'db/03-barra.sql').read_text())
sql((ROOT/'db/18-helpers-permiso.sql').read_text())
sql((ROOT/'db/35-aftr.sql').read_text())
base=(ROOT/'db/44-pagos-banco.sql').read_text()
sql(base[base.index('create table if not exists pago_qr'):base.index('-- ── emisión:')])
sql((ROOT/'supabase/migrations/20261031172015_baneco_seguro.sql').read_text())
sql('set check_function_bodies=on;'+(ROOT/'supabase/migrations/20261031203752_pulse_mesas_pedidos.sql').read_text())
sql('''create function gen_code_evento(uuid) returns text language sql as $$select gen_random_uuid()::text$$;
alter table entradas alter column rrpp_id drop not null;
alter table entradas alter column precio type numeric;
''')

def uid(n): return f'00000000-0000-4000-8000-{n:012d}'
C, G, OTHER, STAFF, ADMIN = [uid(n) for n in range(1,6)]
EV, M, B, D, T, L, ORDEN, FASE = [uid(n) for n in range(10,18)]
KEY=uid(50)

def pedido(metodo='pulse',key=KEY,qty=1,user=C):
    revision=sql(f"select md5(xmin::text) from tragos where id='{T}'")
    return json.loads(sql(f"select aftr_pedir_mesa('{M}','[{{\"trago_id\":\"{T}\",\"qty\":{qty},\"revision\":\"{revision}\"}}]','{metodo}','{key}')",user))
def qr(tipo,ident,amount):
    sql(f"select baneco_reservar_destino('{tipo}','{ident}','{C}','produccion')")
    sql(f"update pago_qr set qr_id='qr-{ident}',estado='activo' where transaction_id=left(replace('{ident}','-',''),30)")
    return {'qrId':f'qr-{ident}','transactionId':f'banco-{ident}','amount':amount,'currency':'BOB'}
def confirmar(pago):
    return json.loads(sql("select aftr_pago_confirmado('%s','%s')" % (pago['qrId'],json.dumps(pago))))

class PulseDB(unittest.TestCase):
    def setUp(self):
        sql('''truncate aftr_incidencias,pago_qr,aftr_bar_items,aftr_stock_reservas,aftr_bar_pedidos,
        aftr_avisos,aftr_mesa_miembros,pulse_movimientos,pulse_cuentas,pulse_recargas,aftr_ventas_saldos,
        aftr_liquidaciones,bar_venta_items,stock_mov,bar_ventas,receta_items,tragos,lotes,bebidas,barras,
        aftr_mesa_config,aftr_ordenes,entradas,mesas,evento_fase,aftr_clientes,eventos,club_membership,
        platform_admins,profiles,clubs,auth.users cascade;''')
        sql(f"""insert into clubs(id,nombre) values('uno','Club Uno'),('dos','Club Dos');
        insert into auth.users values('{C}'),('{G}'),('{OTHER}');
        insert into aftr_clientes(user_id,usuario,nombre) values('{C}','titular','Titular'),('{G}','invitado','Invitado'),('{OTHER}','otro','Otro');
        insert into profiles(id,usuario,nombre,rol,activo,created_at,clubs,puede_tickear,admin_principal) values
        ('{STAFF}','barra','Barra','barra',true,now(),array['uno'],false,false),('{ADMIN}','admin','Admin','admin',true,now(),array['uno'],false,true);
        insert into eventos(id,club_id,nombre,fecha,hora_inicio,hora_fin,edad_min,precio_manilla,pct_boliche,pct_rrpp,estado,created_at,ticket_url,lista_hasta,cut_rrpp,manillas_externas,venta_por_fases,publicado,publicado_at,permite_reserva,horas_reserva,permite_agrupar,combo_obligatorio,combo_por_mesa,cut_base)
        values('{EV}','uno','Prueba',(now() at time zone 'America/La_Paz')::date,'00:00','23:59',18,50,100,0,'activo',now(),'','23:59',0,0,false,true,now(),true,1,true,false,false,'');
        insert into barras(id,club_id,nombre) values('{B}','uno','Principal');
        insert into mesas(id,evento_id,planta,etiqueta,categoria,x,y,w,estado,botellas,manillas,updated_at,combo_qty,pago_verificado,cortesia,cliente_id,capacidad,barra_id)
        values('{M}','{EV}','1','Mesa 1','VIP',0,0,1,'pagada','{{}}',2,now(),1,true,false,'{C}',3,'{B}');
        insert into aftr_mesa_config values('uno',true,'00:00','00:00',array['admin','propietario']);
        insert into bebidas(id,club_id,nombre,volumen_ml) values('{D}','uno','Bebida',750);
        insert into lotes(id,bebida_id,club_id,codigo,cant_inicial,volumen_ml,ml_actual) values('{L}','{D}','uno','L',1,750,100);
        insert into tragos(id,club_id,nombre,precio_venta,activo,foto_url,presentacion) values('{T}','uno','Trago',50,true,'https://example.com/foto.webp','50 ml');
        insert into receta_items(trago_id,bebida_id,ml) values('{T}','{D}',50);
        update tragos set publicado_aftr=true;
        select impl.pulse_mover('{C}',10000,'fixture','Saldo de prueba local');
        insert into evento_fase(id,evento_id,nombre,precio,cupo) values('{FASE}','{EV}','General',50,10);
        insert into aftr_ordenes(id,cliente_id,evento_id,tipo,fase_id,cantidad,precio_unit,total,vence_at)
        values('{ORDEN}','{C}','{EV}','entrada','{FASE}',1,50,50,now()+interval '1 hour');
        """)
    def test_01_pulse_venta_atomica_y_idempotente(self):
        a=pedido(); b=pedido(); self.assertEqual(a['id'],b['id']); self.assertEqual(a['estado'],'recibido')
        self.assertEqual(sql('select saldo_centavos from pulse_cuentas'),'5000')
        self.assertEqual(sql('select ml_actual from lotes'),'50')
        self.assertEqual(sql('select sum(importe_centavos) from aftr_ventas_saldos'),'5000')
    def test_02_saldo_insuficiente_revierte_stock(self):
        sql('update pulse_cuentas set saldo_centavos=0')
        with self.assertRaisesRegex(AssertionError,'insuficiente'): pedido()
        self.assertEqual(sql('select count(*) from aftr_bar_pedidos'),'0')
        self.assertEqual(sql('select ml_actual from lotes'),'100')
    def test_03_ultimo_stock_concurrente(self):
        sql('update lotes set ml_actual=50')
        def attempt(key):
            try: return pedido(key=key)['estado']
            except AssertionError: return 'sin_stock'
        with concurrent.futures.ThreadPoolExecutor(max_workers=2) as p:
            r=list(p.map(attempt,[uid(51),uid(52)]))
        self.assertCountEqual(r,['recibido','sin_stock']); self.assertEqual(sql('select ml_actual from lotes'),'0')
    def test_04_reserva_qr_se_libera_solo_al_cancelar_banco(self):
        a=pedido('qr'); pago=qr('pedido',a['id'],50)
        self.assertEqual(sql('select ml_actual from lotes'),'50')
        sql(f"select aftr_cancelar_cobro('pedido','{a['id']}')",C)
        self.assertEqual(sql('select ml_actual from lotes'),'50')
        sql(f"select baneco_qr_anulado('{pago['qrId']}')")
        self.assertEqual(sql('select ml_actual from lotes'),'100')
        self.assertEqual(sql('select estado from aftr_bar_pedidos'),'cancelado')
    def test_05_pago_qr_no_debita_wallet_y_no_duplica(self):
        a=pedido('qr'); pago=qr('pedido',a['id'],50)
        self.assertTrue(confirmar(pago)['nuevo']); self.assertFalse(confirmar(pago)['nuevo'])
        self.assertEqual(sql('select saldo_centavos from pulse_cuentas'),'10000')
        self.assertEqual(sql('select count(*) from bar_ventas'),'1')
        self.assertEqual(sql('select ml_actual from lotes'),'50')
    def test_06_recarga_verificada_solo_una_vez(self):
        r=json.loads(sql(f"select aftr_recargar_pulse(12345,'{KEY}')",C)); pago=qr('recarga',r['id'],123.45)
        bad={**pago,'amount':1}; self.assertEqual(confirmar(bad)['estado'],'revisar')
        self.assertEqual(sql('select saldo_centavos from pulse_cuentas'),'10000')
        self.assertTrue(confirmar(pago)['nuevo']); confirmar(pago)
        self.assertEqual(sql('select saldo_centavos from pulse_cuentas'),'22345')
        self.assertEqual(sql('select count(*) from aftr_ventas_saldos'),'0')
    def test_07_certificacion_no_acredita(self):
        r=json.loads(sql(f"select aftr_recargar_pulse(100,'{KEY}')",C)); pago=qr('recarga',r['id'],1)
        sql("update pago_qr set ambiente='certificacion'"); self.assertEqual(confirmar(pago)['estado'],'revisar')
        self.assertEqual(sql('select saldo_centavos from pulse_cuentas'),'10000')
    def test_08_entradas_pulse_y_saldo(self):
        sql(f"select aftr_pagar_pulse('{ORDEN}')",C); sql(f"select aftr_pagar_pulse('{ORDEN}')",C)
        self.assertEqual(sql('select count(*) from entradas'),'1')
        self.assertEqual(sql('select saldo_centavos from pulse_cuentas'),'5000')
    def test_09_qr_existente_impide_doble_metodo(self):
        qr('orden',ORDEN,50)
        with self.assertRaisesRegex(AssertionError,'ya tiene un QR'): sql(f"select aftr_pagar_pulse('{ORDEN}')",C)
    def test_10_invitado_paga_su_propio_saldo(self):
        with self.assertRaises(AssertionError): pedido(user=G)
        sql(f"select aftr_mesa_invitar('{M}','invitado')",C)
        with self.assertRaises(AssertionError): pedido(user=G)
        sql(f"select aftr_mesa_responder('{M}',true)",G)
        sql(f"select impl.pulse_mover('{G}',5000,'guest-fixture','Prueba')")
        pedido(user=G); sql(f"select aftr_mesa_retirar('{M}','{G}')",C)
        self.assertEqual(sql(f"select saldo_centavos from pulse_cuentas where cliente_id='{C}'"),'10000')
        self.assertEqual(len(json.loads(sql(f"select aftr_mis_pedidos_mesa('{M}')",G))),1)
        with self.assertRaises(AssertionError): pedido(key=uid(55),user=G)
    def test_11_venta_pagada_no_se_anula(self):
        a=pedido()
        with self.assertRaisesRegex(AssertionError,'Venta AFTR pagada'): sql(f"select bar_anular_venta('{a['venta_id']}')",STAFF)
        self.assertEqual(sql('select ml_actual from lotes'),'50')
    def test_12_barra_por_turno_y_transiciones(self):
        a=pedido()
        with self.assertRaises(AssertionError): sql(f"select venue_avanzar_pedido('{a['id']}','en_preparacion')",STAFF)
        sql(f"insert into bar_staff values('{EV}','{B}','{STAFF}')")
        for estado in ['en_preparacion','listo','entregado']:
            sql(f"select venue_avanzar_pedido('{a['id']}','{estado}')",STAFF)
        with self.assertRaises(AssertionError): sql(f"select venue_avanzar_pedido('{a['id']}','recibido')",STAFF)
    def test_13_liquidacion_no_debita_cliente(self):
        pedido(); sql(f"select venue_registrar_liquidacion('uno',5000,current_date,'Transferencia 123','{KEY}')",ADMIN)
        sql(f"select venue_registrar_liquidacion('uno',5000,current_date,'Transferencia 123','{KEY}')",ADMIN)
        self.assertEqual(sql('select count(*) from aftr_liquidaciones'),'1')
        self.assertEqual(sql('select saldo_centavos from pulse_cuentas'),'5000')
        with self.assertRaises(AssertionError): sql(f"select venue_registrar_liquidacion('uno',1,current_date,'Otra','{uid(60)}')",ADMIN)
    def test_14_rls_y_rpcs_cerradas(self):
        for table in ['pulse_cuentas','pulse_movimientos','aftr_ventas_saldos','aftr_liquidaciones']:
            self.assertEqual(sql(f"select count(*) from {table}",OTHER,'authenticated'),'0')
            self.assertEqual(sql(f"select has_table_privilege('authenticated','{table}','insert')"),'f')
        for fn in ['aftr_pago_confirmado(text,jsonb)','baneco_qr_anulado(text)','impl.pulse_mover(uuid,bigint,text,text)']:
            self.assertEqual(sql(f"select has_function_privilege('authenticated','{fn}','execute')"),'f')
    def test_15_horario_y_flag_bloquean_antes_del_cobro(self):
        sql('update aftr_mesa_config set habilitado=false')
        with self.assertRaises(AssertionError): pedido()
        self.assertEqual(sql('select saldo_centavos from pulse_cuentas'),'10000')
    def test_16_historial_inmutable(self):
        with self.assertRaises(AssertionError): sql("update pulse_movimientos set importe_centavos=1")
        with self.assertRaises(AssertionError): sql("delete from pulse_movimientos")
    def test_17_catalogo_no_expone_costo_y_valida_publicacion(self):
        carta=json.loads(sql(f"select aftr_carta_mesa('{M}')",C)); self.assertEqual(carta['productos'][0]['precio_centavos'],5000)
        self.assertNotIn('costo',json.dumps(carta))
        with self.assertRaises(AssertionError): sql("update tragos set precio_venta=0")
    def test_18_cambio_stock_no_roba_reserva(self):
        pedido('qr')
        with self.assertRaisesRegex(AssertionError,'pago pendiente'): sql('update lotes set ml_actual=100')
    def test_19_pago_durante_cancelacion_no_se_pierde(self):
        a=pedido('qr'); pago=qr('pedido',a['id'],50)
        confirmar(pago); sql(f"select baneco_qr_anulado('{pago['qrId']}')")
        self.assertEqual(sql('select estado from aftr_bar_pedidos'),'recibido')
        self.assertEqual(sql('select ml_actual from lotes'),'50')
    def test_20_pedido_sin_generacion_puede_vencer(self):
        pedido('qr'); sql("update aftr_bar_pedidos set vence_at=now()-interval '1 minute'")
        sql('select baneco_liberar_sin_qr()'); self.assertEqual(sql('select ml_actual from lotes'),'100')
    def test_21_ultimo_saldo_concurrente(self):
        sql('update pulse_cuentas set saldo_centavos=5000')
        def attempt(key):
            try:return pedido(key=key)['estado']
            except AssertionError:return 'sin_saldo'
        with concurrent.futures.ThreadPoolExecutor(max_workers=2) as p:
            r=list(p.map(attempt,[uid(70),uid(71)]))
        self.assertCountEqual(r,['recibido','sin_saldo'])
        self.assertEqual(sql('select saldo_centavos from pulse_cuentas'),'0')
        self.assertEqual(sql('select ml_actual from lotes'),'50')
    def test_22_pos_compite_con_reserva_aftr(self):
        sql('update lotes set ml_actual=50')
        def attempt(tipo):
            try:
                if tipo=='aftr':pedido('qr')
                else:sql(f"select bar_vender('{EV}','{B}','[{{\"trago_id\":\"{T}\",\"qty\":1}}]',null,'efectivo','pos-local')",STAFF)
                return 'ok'
            except AssertionError:return 'sin_stock'
        with concurrent.futures.ThreadPoolExecutor(max_workers=2) as p:r=list(p.map(attempt,['aftr','pos']))
        self.assertCountEqual(r,['ok','sin_stock']);self.assertEqual(sql('select ml_actual from lotes'),'0')
    def test_23_capacidad_no_se_confunde_con_manillas(self):
        sql('update mesas set capacidad=1,manillas=20')
        with self.assertRaisesRegex(AssertionError,'lugares disponibles'):sql(f"select aftr_mesa_invitar('{M}','invitado')",C)
        self.assertEqual(sql('select count(*) from entradas'),'0')
    def test_24_seed_no_sobrescribe_precios(self):
        sql("insert into aftr_catalogo_base(clave,nombre,categoria) values('skyy','SKYY','Vodka') on conflict do nothing")
        sql("select venue_cargar_catalogo_base('uno')",ADMIN)
        sql("update tragos set precio_venta=123 where catalogo_clave='skyy'")
        sql("select venue_cargar_catalogo_base('uno')",ADMIN)
        self.assertEqual(sql("select count(*) from tragos where catalogo_clave='skyy'"),'1')
        self.assertEqual(sql("select precio_venta from tragos where catalogo_clave='skyy'"),'123')
        self.assertEqual(sql("select publicado_aftr from tragos where catalogo_clave='skyy'"),'f')
    def test_25_correccion_auditada_solo_plataforma(self):
        with self.assertRaises(AssertionError):sql(f"select venue_corregir_pulse('{C}',100,'Corrección de prueba','{KEY}')",STAFF)
        sql(f"select venue_corregir_pulse('{C}',100,'Corrección de prueba','{KEY}')",ADMIN)
        sql(f"select venue_corregir_pulse('{C}',100,'Corrección de prueba','{KEY}')",ADMIN)
        self.assertEqual(sql('select saldo_centavos from pulse_cuentas'),'10100')
        with self.assertRaises(AssertionError):sql('delete from pulse_correcciones')
    def test_26_qr_incierto_no_libera_stock(self):
        p=pedido('qr');qr('pedido',p['id'],50)
        sql("update pago_qr set estado='revisar',nota='GENERACION_INCIERTA';update aftr_bar_pedidos set vence_at=now()-interval '1 minute'")
        sql('select baneco_liberar_sin_qr()')
        self.assertEqual(sql('select ml_actual from lotes'),'50')
    def test_27_identidad_ajena_no_asigna_mesas(self):
        with self.assertRaises(AssertionError):sql(f"select venue_asignar_mesa_aftr('{M}','{G}',3,'{B}')",OTHER)
        sql(f"select venue_asignar_mesa_aftr('{M}','{G}',3,'{B}')",ADMIN)
        self.assertEqual(sql('select cliente_id from mesas'),G)
    def test_28_estado_nulo_no_borra_el_pedido(self):
        p=pedido()
        with self.assertRaises(AssertionError):sql(f"select venue_avanzar_pedido('{p['id']}',null)",ADMIN)
        self.assertEqual(sql('select estado from aftr_bar_pedidos'),'recibido')

if __name__=='__main__': unittest.main(argv=[sys.argv[0]],verbosity=2)
