"""Stories/P2P integration tests on disposable PostgreSQL, never on production."""
from pathlib import Path
import sys
# Reuse the existing schema bootstrap, without running its test suite.
root=Path(sys.argv[2])
exec((root/'tests/pulse_database_test.py').read_text().split('\ndef uid(n):')[0])
sql('''alter table clubs add column activo boolean not null default true;
create schema storage;
create table storage.buckets(id text primary key,name text,public boolean,file_size_limit bigint,allowed_mime_types text[]);
create table storage.objects(id uuid default gen_random_uuid(),bucket_id text,name text,metadata jsonb,created_at timestamptz default now());
alter table storage.objects enable row level security;
grant usage on schema storage to anon,authenticated,service_role;
grant select,insert,delete on storage.objects to authenticated;
grant select on storage.objects to anon;
-- stub de storage.foldername: alcanza para [1], la carpeta del dueño
create function storage.foldername(name text) returns text[] language sql immutable as $$select string_to_array(name,'/')$$;
create table link_visita(id bigserial primary key,rrpp_id uuid,evento_id uuid references eventos(id) on delete cascade,cliente_id uuid,at timestamptz default now());
create table ingreso_sin_tope(user_id uuid,club_id text);
create table intento_validacion(user_id uuid,evento_id uuid,ok boolean,at timestamptz default now());
alter table registros add column qr_anulado boolean default false;
''')
sql('set check_function_bodies=on;'+(root/'supabase/migrations/20261101004007_historias_reventa_oficial.sql').read_text())
sql('alter table clubs add column if not exists logo_url text;')
sql((root/'supabase/migrations/20261031234249_aftr_perfil_foto.sql').read_text())
sql('set check_function_bodies=on;'+(root/'supabase/migrations/20261105070000_historias_foto_autor.sql').read_text())
# pg_cron no existe en un PostgreSQL pelado: un stub alcanza, porque acá no se
# prueba que el cron corra sino lo que hacen las funciones que agenda.
sql('''create schema cron;
create table cron.job(jobid bigserial primary key,jobname text,schedule text,command text);
create function cron.schedule(jobname text,schedule text,command text) returns bigint
 language sql as $$insert into cron.job(jobname,schedule,command) values($1,$2,$3) returning jobid$$;''')
# De los límites de uso hace falta la pieza compartida (aftr_intentos y
# impl.aftr_limite), que la reventa usa. La segunda mitad de esa migración
# inyecta el freno en otras RPC que acá no existen.
limites = (root/'supabase/migrations/20261106130000_limites_de_uso.sql').read_text()
sql('set check_function_bodies=on;'+limites.split('-- ── los frenos')[0])
sql('set check_function_bodies=on;'+(root/'supabase/migrations/20261106150000_reventa_el_vendedor_acepta.sql').read_text())
# y la corrección: el precio lo pone el boliche, no la plataforma
sql('set check_function_bodies=on;'+(root/'supabase/migrations/20261106190000_el_precio_lo_pone_el_boliche.sql').read_text())

def uid(n): return f'00000000-0000-4000-8000-{n:012d}'
C,B,OTHER,ADMIN,CLUBADMIN,EV,ENT,FASE=[uid(n) for n in range(1,9)]
def call(action,data=None,user=C,role=None):
    return json.loads(sql("select aftr_reventa('%s','%s'::jsonb)"%(action,json.dumps(data or {}).replace("'","''")),user,role))
def history(action,data=None,user=C,role=None):
    return json.loads(sql("select aftr_historias('%s','%s'::jsonb)"%(action,json.dumps(data or {}).replace("'","''")),user,role))
class SocialDB(unittest.TestCase):
 def setUp(self):
  sql('truncate clubs,auth.users,aftr_clientes,profiles,eventos,entradas,aftr_ordenes,aftr_transferencias,evento_fase,storage.objects,aftr_intentos cascade;')
  sql(f"""insert into clubs(id,nombre,aftr_visible) values('uno','Club Uno',true),('dos','Club Dos',true);
  insert into auth.users values('{C}'),('{B}'),('{OTHER}'),('{ADMIN}'),('{CLUBADMIN}');
  insert into aftr_clientes(user_id,usuario,nombre) values('{C}','seller','Seller'),('{B}','buyer','Buyer'),('{OTHER}','other','Other');
  insert into profiles(id,usuario,nombre,rol,activo,created_at,clubs,puede_tickear,admin_principal) values
  ('{ADMIN}','root','Root','admin',true,now(),array['uno'],false,true),('{CLUBADMIN}','club','Club','admin',true,now(),array['uno'],false,false);
  insert into eventos(id,club_id,nombre,fecha,hora_inicio,hora_fin,edad_min,precio_manilla,pct_boliche,pct_rrpp,estado,created_at,ticket_url,lista_hasta,cut_rrpp,manillas_externas,venta_por_fases,publicado,publicado_at,permite_reserva,horas_reserva,permite_agrupar,combo_obligatorio,combo_por_mesa,cut_base,aftr_publico)
  values('{EV}','uno','Noche',((now() at time zone 'America/La_Paz')::date+1),'18:00','23:59',18,50,100,0,'activo',now(),'','23:59',0,0,false,true,now(),true,1,true,false,false,'',true);
  insert into evento_fase(id,evento_id,nombre,precio,cupo) values('{FASE}','{EV}','General',50,10);
  insert into entradas(id,evento_id,code,cliente,rrpp_id,precio,estado,created_at,cliente_id,canal,fase_id)
  values('{ENT}','{EV}','OLDQR','Seller',null,50,'valida',now(),'{C}','aftr','{FASE}');
  insert into aftr_reventa_config(club_id,habilitada) values('uno',true);
  -- el techo es del boliche y arranca vacío (precio libre), así que los casos
  -- que no lo prueban no se enteran de que existe
  """)
 def offer(self):return call('publicar',{'entrada_id':ENT,'precio_centavos':7000,'metodo':{'titular':'Seller Name','banco':'Banco','cuenta':'123456'},'client_key':uid(100)})
 def pedido(self):
  """La orden recién creada: el vendedor todavía no aceptó y no hay datos de cobro."""
  f=self.offer();return call('comprar',{'oferta_id':f['id'],'client_key':uid(101)},B)
 def order(self):
  """La orden pagable: el vendedor ya aceptó, que es lo que la habilita."""
  o=self.pedido();return call('aceptar',{'id':o['id']})
 def paid(self):
  o=self.order();p=f'{B}/{uid(200)}.jpg';sql(f"insert into storage.objects(bucket_id,name) values('aftr-p2p','{p}')")
  return call('informar_pago',{'id':o['id'],'comprobante_path':p,'referencia':'BANK-42'},B)
 def test_01_complete_atomic_replacement(self):
  o=self.paid();r=call('confirmar',{'id':o['id']});self.assertEqual(r['estado'],'completada')
  self.assertEqual(sql(f"select estado from entradas where id='{ENT}'"),'anulada')
  self.assertNotEqual(sql(f"select code from entradas where id='{r['nueva_entrada_id']}'"),'OLDQR')
  self.assertEqual(sql('select count(*) from impl.entradas_vigentes'),'1')
  self.assertEqual(sql('select sum(precio) from impl.entradas_vigentes'),'50')
  self.assertEqual(call('confirmar',{'id':o['id']})['nueva_entrada_id'],r['nueva_entrada_id'])
  self.assertEqual(sql('select count(*) from entradas'),'2')
 def test_02_blocked_scanner_transfer_and_direct_mutation(self):
  self.offer();self.assertEqual(json.loads(sql(f"select impl.validar_entrada('{EV}','OLDQR')"))['resultado'],'bloqueada')
  with self.assertRaisesRegex(AssertionError,'bloqueada'):sql(f"select aftr_transferir('{ENT}','buyer')",C)
  with self.assertRaisesRegex(AssertionError,'bloqueada'):sql(f"update entradas set estado='anulada' where id='{ENT}'")
 def test_03_two_buyers_one_winner(self):
  f=self.offer()
  def buy(u):
   try:return call('comprar',{'oferta_id':f['id'],'client_key':uid(300+int(u[-1]))},u)['id']
   except AssertionError:return None
  with concurrent.futures.ThreadPoolExecutor(2) as ex:r=list(ex.map(buy,[B,OTHER]))
  self.assertEqual(sum(x is not None for x in r),1)
 def test_04_expiry_and_paid_dispute_remain_locked(self):
  o=self.order();sql(f"update aftr_reventa_ordenes set vence_at=now()-interval '1 second' where id='{o['id']}'")
  self.assertEqual(call('orden',{'id':o['id']},B)['estado'],'vencida');self.assertEqual(sql('select reventa_oferta_id is null from entradas'),'t')
 def test_05_only_platform_arbitrates(self):
  o=self.paid();call('disputar',{'id':o['id'],'motivo':'No llegó el dinero'},C)
  with self.assertRaises(AssertionError):call('resolver',{'id':o['id'],'resolucion':'entregar','motivo':'Pruebas verificadas por operador'},CLUBADMIN)
  self.assertIsNone(call('orden',{'id':o['id']},CLUBADMIN)['metodo'])
  self.assertEqual(call('resolver',{'id':o['id'],'resolucion':'entregar','motivo':'Pruebas verificadas por operador'},ADMIN)['estado'],'completada')
 def test_06_history_is_immutable_and_private(self):
  o=self.order()
  with self.assertRaisesRegex(AssertionError,'inmutable'):sql('update aftr_reventa_historial set texto=\'changed\'')
  with self.assertRaises(AssertionError):call('orden',{'id':o['id']},OTHER)
 def test_07_story_verified_media_expiry_identity(self):
  path=f'{C}/{uid(99)}.jpg';sql(f"insert into storage.objects(bucket_id,name) values('aftr-historias','{path}');insert into aftr_media_validada values('{path}','{C}','imagen',5000,500,'sha',now());")
  with self.assertRaisesRegex(AssertionError,'identidad'):history('publicar',{'storage_path':path,'identidad':'club','club_id':'uno'})
  h=history('publicar',{'storage_path':path,'identidad':'usuario','evento_id':EV,'cta':'entrada'})
  self.assertEqual(len(history('feed',user=None,role='anon')['historias']),1)
  history('retirar',{'id':h['id']});self.assertEqual(len(history('feed')['historias']),0)
 def test_08_constraints_and_idempotency(self):
  f=self.offer();self.assertEqual(self.offer()['id'],f['id'])
  with self.assertRaisesRegex(AssertionError,'otros datos'):call('publicar',{'entrada_id':ENT,'precio_centavos':8000,'metodo':{},'client_key':uid(100)})
  with self.assertRaises(AssertionError):call('publicar',{'entrada_id':ENT,'precio_centavos':7000,'metodo':{},'client_key':uid(999)},B)
 def test_09_disabled_market_and_paid_order_survive(self):
  o=self.paid();call('configurar',{'club_id':'uno','habilitada':False},CLUBADMIN)
  self.assertEqual(call('mercado')['ofertas'],[]);self.assertEqual(call('orden',{'id':o['id']},B)['estado'],'pago_informado')
 def test_10_original_qr_permanently_invalid(self):
  o=self.paid();call('confirmar',{'id':o['id']})
  self.assertEqual(json.loads(sql(f"select impl.validar_entrada('{EV}','OLDQR')"))['resultado'],'reemplazada')
 def test_11_paid_timeout_opens_dispute(self):
  o=self.paid();sql(f"update aftr_reventa_ordenes set confirmar_hasta=now()-interval '1 second' where id='{o['id']}'")
  self.assertEqual(call('orden',{'id':o['id']},B)['estado'],'en_disputa');self.assertEqual(sql('select reventa_oferta_id is not null from entradas'),'t')
 def test_12_anonymous_cannot_mutate(self):
  with self.assertRaisesRegex(AssertionError,'Iniciá'):call('publicar',{},None,'anon')
  with self.assertRaisesRegex(AssertionError,'Iniciá'):history('publicar',{},None,'anon')

 def test_13_private_receipts_and_bank_data_are_not_staff_rows(self):
  o=self.paid()
  self.assertEqual(sql('select count(*) from aftr_reventa_ordenes',CLUBADMIN,'authenticated'),'0')
  self.assertEqual(sql('select count(*) from aftr_reventa_historial',OTHER,'authenticated'),'0')
  with self.assertRaises(AssertionError):sql('select * from aftr_reventa_metodos',OTHER,'authenticated')
  self.assertEqual(sql('select count(*) from storage.objects',CLUBADMIN,'authenticated'),'0')
 def test_14_repeated_resale_preserves_one_ticket_and_original_price(self):
  first=self.paid();r=call('confirmar',{'id':first['id']})
  f=call('publicar',{'entrada_id':r['nueva_entrada_id'],'precio_centavos':9000,'metodo':{'titular':'Buyer Name','banco':'Banco','cuenta':'888'},'client_key':uid(410)},B)
  o=call('comprar',{'oferta_id':f['id'],'client_key':uid(411)},OTHER)
  o=call('aceptar',{'id':o['id']},B)
  path=f'{OTHER}/{uid(412)}.jpg';sql(f"insert into storage.objects(bucket_id,name) values('aftr-p2p','{path}')")
  call('informar_pago',{'id':o['id'],'comprobante_path':path,'referencia':'REPAY'},OTHER)
  call('confirmar',{'id':o['id']},B)
  self.assertEqual(sql('select count(*) from impl.entradas_vigentes'),'1')
  self.assertEqual(sql('select sum(precio) from impl.entradas_vigentes'),'50')
  self.assertEqual(sql('select count(*) from entradas'),'3')
 def test_15_no_public_access_after_exact_expiry(self):
  path=f'{C}/{uid(99)}.jpg';sql(f"insert into storage.objects(bucket_id,name) values('aftr-historias','{path}');insert into aftr_media_validada values('{path}','{C}','imagen',5000,500,'sha',now());")
  h=history('publicar',{'storage_path':path,'identidad':'usuario'})
  self.assertEqual(sql('select count(*) from storage.objects',None,'anon'),'1')
  sql("update aftr_historias set created_at=now()-interval '24 hours',vence_at=now()")
  self.assertEqual(len(history('feed',None,None,'anon')['historias']),0)
  self.assertEqual(sql('select count(*) from storage.objects',None,'anon'),'0')
 def test_16_user_cannot_remove_another_authors_club_story(self):
  path=f'{CLUBADMIN}/{uid(99)}.jpg';sql(f"insert into storage.objects(bucket_id,name) values('aftr-historias','{path}');insert into aftr_media_validada values('{path}','{CLUBADMIN}','imagen',5000,500,'sha',now());")
  h=history('publicar',{'storage_path':path,'identidad':'club','club_id':'uno'},CLUBADMIN)
  with self.assertRaises(AssertionError):history('retirar',{'id':h['id']},OTHER)
 def test_17_el_techo_se_mide_contra_lo_que_pago_quien_revende(self):
  # El techo lo pone el boliche -vacío es precio libre- y se mide contra lo que
  # pagó quien revende. Antes se medía siempre contra el precio original, así
  # que una cadena de reventas conservaba para siempre el techo del primero.
  call('configurar',{'club_id':'uno','habilitada':True,'max_precio_pct':120},CLUBADMIN)
  with self.assertRaisesRegex(AssertionError,'máximo'):self.offer()   # 70 > 60
  f=call('publicar',{'entrada_id':ENT,'precio_centavos':6000,
    'metodo':{'titular':'Seller Name','banco':'Banco','cuenta':'123456'},'client_key':uid(730)})
  o=call('comprar',{'oferta_id':f['id'],'client_key':uid(731)},B)
  o=call('aceptar',{'id':o['id']})
  path=f'{B}/{uid(732)}.jpg';sql(f"insert into storage.objects(bucket_id,name) values('aftr-p2p','{path}')")
  call('informar_pago',{'id':o['id'],'comprobante_path':path,'referencia':'REF-1'},B)
  r=call('confirmar',{'id':o['id']})
  nueva=r['nueva_entrada_id']
  # pagó 60: ahora su techo son 72, no 60 otra vez ni 120 para siempre
  self.assertEqual(sql(f"select precio_base from entradas where id='{nueva}'"),'60')
  with self.assertRaisesRegex(AssertionError,'máximo'):call('publicar',{'entrada_id':nueva,
    'precio_centavos':7300,'metodo':{'titular':'Buyer Name','banco':'Banco','cuenta':'123456'},'client_key':uid(733)},B)
  call('publicar',{'entrada_id':nueva,'precio_centavos':7200,
    'metodo':{'titular':'Buyer Name','banco':'Banco','cuenta':'123456'},'client_key':uid(734)},B)

 def test_27_los_datos_de_cobro_no_salen_hasta_que_el_vendedor_acepta(self):
  # Era gratis juntarlos: iniciar una orden no cuesta nada ni exige pagar.
  o=self.pedido()
  self.assertEqual(o['estado'],'esperando_vendedor')
  self.assertIsNone(o['metodo'])
  self.assertIsNone(call('orden',{'id':o['id']},B)['metodo'])
  self.assertIsNone(call('orden',{'id':o['id']})['metodo'])      # ni el vendedor
  with self.assertRaisesRegex(AssertionError,'vendedor'):call('aceptar',{'id':o['id']},B)
  a=call('aceptar',{'id':o['id']})
  self.assertEqual(a['estado'],'pendiente_pago')
  self.assertEqual(a['metodo']['titular'],'Seller Name')
  # y queda escrito que se mostraron
  self.assertTrue(any('datos de cobro' in h['texto'] for h in a['historial']))

 def test_28_el_vendedor_puede_rechazar_y_la_entrada_vuelve_al_mercado(self):
  o=self.pedido()
  r=call('rechazar',{'id':o['id']})
  self.assertEqual(r['estado'],'cancelada')
  self.assertEqual(sql(f"select estado from aftr_reventa_ofertas where id='{o['oferta_id']}'"),'retirada')
  self.assertEqual(sql(f"select reventa_oferta_id from entradas where id='{ENT}'"),'')

 def test_29_una_sola_operacion_abierta_por_comprador(self):
  # Con tres órdenes simultáneas renovables se juntaba el mercado entero.
  sql('insert into entradas(id,evento_id,code,cliente,precio,estado,created_at,cliente_id,canal,fase_id)'
      f" values('{uid(800)}','{EV}','OTROQR','Other',50,'valida',now(),'{OTHER}','aftr','{FASE}')")
  self.offer()
  f2=call('publicar',{'entrada_id':uid(800),'precio_centavos':6000,
    'metodo':{'titular':'Other Name','banco':'Banco','cuenta':'654321'},'client_key':uid(801)},OTHER)
  call('comprar',{'oferta_id':sql(f"select id from aftr_reventa_ofertas where entrada_id='{ENT}'"),
    'client_key':uid(802)},B)
  with self.assertRaisesRegex(AssertionError,'pendiente'):call('comprar',{'oferta_id':f2['id'],'client_key':uid(803)},B)

 def test_30_no_se_insiste_sobre_la_misma_oferta(self):
  o=self.pedido()
  call('rechazar',{'id':o['id']})
  # la oferta vuelve a publicarse para probar el reintento
  sql(f"update aftr_reventa_ofertas set estado='publicada' where id='{o['oferta_id']}'")
  with self.assertRaisesRegex(AssertionError,'más tarde'):call('comprar',{'oferta_id':o['oferta_id'],'client_key':uid(810)},B)

 def test_31_el_tope_diario_cuenta_las_que_no_salieron(self):
  sql('update aftr_reventa_politica set max_dia=2')
  o=self.pedido();call('rechazar',{'id':o['id']})
  sql(f"update aftr_reventa_ofertas set estado='publicada' where id='{o['oferta_id']}'")
  sql(f"update aftr_reventa_ordenes set oferta_id=oferta_id, created_at=now()-interval '1 minute' where comprador_id='{B}'")
  sql("update aftr_reventa_politica set espera_horas=0")
  o=call('comprar',{'oferta_id':o['oferta_id'],'client_key':uid(820)},B)
  call('rechazar',{'id':o['id']})
  sql(f"update aftr_reventa_ofertas set estado='publicada' where id='{o['oferta_id']}'")
  with self.assertRaisesRegex(AssertionError,'por día'):call('comprar',{'oferta_id':o['oferta_id'],'client_key':uid(821)},B)

 def test_32_los_plazos_son_de_la_plataforma_y_el_precio_del_boliche(self):
  with self.assertRaisesRegex(AssertionError,'Solo AFTR'):call('politica',{'pago_minutos':20},CLUBADMIN)
  call('politica',{'pago_minutos':20},ADMIN)
  self.assertEqual(sql('select pago_minutos from aftr_reventa_politica'),'20')
  # el boliche no cambia los plazos por su cuenta, y sí su techo de precio
  call('configurar',{'club_id':'uno','habilitada':True,'pago_minutos':30,'max_precio_pct':150},CLUBADMIN)
  self.assertEqual(sql('select pago_minutos from aftr_reventa_politica'),'20')
  self.assertEqual(sql("select max_precio_pct from aftr_reventa_config where club_id='uno'"),'150')
  # y un techo imposible se rechaza con un mensaje, no se guarda
  with self.assertRaisesRegex(AssertionError,'100'):call('configurar',
    {'club_id':'uno','habilitada':True,'max_precio_pct':5},CLUBADMIN)

 def test_33_la_oferta_en_operacion_sigue_en_el_mercado(self):
  o=self.pedido()
  m=call('mercado',None,None,'anon')['ofertas']
  mia=[x for x in m if x['id']==o['oferta_id']]
  self.assertEqual(len(mia),1)
  self.assertEqual(mia[0]['estado'],'reservada')
  self.assertIsNotNone(mia[0]['vuelve_at'])
 def test_18_seller_cannot_self_buy(self):
  f=self.offer()
  with self.assertRaisesRegex(AssertionError,'propia'):call('comprar',{'oferta_id':f['id'],'client_key':uid(599)},C)

 def test_19_closed_account_preserves_other_partys_history(self):
  o=self.paid();call('confirmar',{'id':o['id']})
  sql(f"select aftr_eliminar_cuenta()",C)
  r=call('orden',{'id':o['id']},B)
  self.assertEqual(r['estado'],'completada');self.assertEqual(r['vendedor'],'Cuenta eliminada')
 def test_20_active_payment_prevents_account_abandonment(self):
  self.paid()
  with self.assertRaisesRegex(AssertionError,'Resolvé'):sql('select aftr_eliminar_cuenta()',C)

 def rrpp_story(self):
  sql(f"insert into profiles(id,usuario,nombre,rol,activo,created_at,clubs,puede_tickear,admin_principal) values('{C}','rrpp','RRPP','rrpp',true,now(),array['uno'],false,false)")
  path=f'{C}/{uid(99)}.jpg';sql(f"insert into storage.objects(bucket_id,name) values('aftr-historias','{path}');insert into aftr_media_validada values('{path}','{C}','imagen',5000,500,'sha',now());")
  return history('publicar',{'storage_path':path,'identidad':'rrpp','club_id':'uno','evento_id':EV,'cta':'entrada'})
 def test_21_story_attribution_survives_emission_and_counts_without_visit(self):
  h=self.rrpp_story()
  r=json.loads(sql(f"select aftr_comprar_historia('{h['id']}','{EV}',null,1)",B))
  self.assertEqual(sql(f"select referido_rrpp_id from aftr_ordenes where id='{r['id']}'"),C)
  sql(f"select impl.aftr_emitir_orden('{r['id']}',null)")
  self.assertEqual(sql(f"select rrpp_id from entradas where cliente_id='{B}'"),C)
  self.assertEqual(json.loads(sql("select row_to_json(r) from rrpp_links() r",C))['compras'],1)
 def test_22_story_cannot_silently_buy_a_different_event(self):
  h=self.rrpp_story()
  with self.assertRaisesRegex(AssertionError,'no pertenece'):sql(f"select aftr_comprar_historia('{h['id']}','{uid(888)}',null,1)",B)

 def test_23_changed_promoter_role_cannot_keep_claiming_sales(self):
  h=self.rrpp_story();sql(f"update profiles set rol='portero' where id='{C}'")
  with self.assertRaisesRegex(AssertionError,'vigente'):sql(f"select aftr_comprar_historia('{h['id']}','{EV}',null,1)",B)

 def story(self,user=C):
  path=f'{user}/{uid(99)}.jpg'
  sql(f"insert into storage.objects(bucket_id,name) values('aftr-historias','{path}');insert into aftr_media_validada values('{path}','{user}','imagen',5000,500,'sha',now());")
  return history('publicar',{'storage_path':path,'identidad':'usuario'},user)
 def test_24_story_carries_author_photo(self):
  foto=f'{C}/0123456789abcdef.png'
  sql(f"insert into storage.objects(bucket_id,name) values('aftr-perfiles','{foto}');update aftr_clientes set foto_archivo='{foto}' where user_id='{C}'")
  self.story()
  h=history('feed',None,B)['historias'][0]
  self.assertEqual(h['foto_archivo'],foto)
  # otro con sesión puede firmar la foto vigente, pero no los restos de una
  # foto cambiada ni archivos que no son foto de nadie
  self.assertEqual(sql(f"select count(*) from storage.objects where name='{foto}'",B,'authenticated'),'1')
  viejo=f'{C}/fedcba9876543210.png'
  sql(f"insert into storage.objects(bucket_id,name) values('aftr-perfiles','{viejo}')")
  self.assertEqual(sql(f"select count(*) from storage.objects where name='{viejo}'",B,'authenticated'),'0')
  self.assertEqual(sql(f"select count(*) from storage.objects where bucket_id='aftr-perfiles'",C,'authenticated'),'2')
 def test_25_story_without_photo_keeps_feed_working(self):
  self.story()
  h=history('feed',None,B)['historias'][0]
  self.assertIsNone(h['foto_archivo']);self.assertIsNone(h['foto'])

 def test_26_offer_without_account_number_needs_qr(self):
  # publicar con QR de cobro y sin número de cuenta tiene que alcanzar
  qr=f'{C}/{uid(700)}.jpg';sql(f"insert into storage.objects(bucket_id,name) values('aftr-p2p','{qr}')")
  metodo={'titular':'Seller Name','banco':'Banco','cuenta':''}
  with self.assertRaisesRegex(AssertionError,'titular'):call('publicar',{'entrada_id':ENT,'precio_centavos':7000,'metodo':metodo,'client_key':uid(701)})
  f=call('publicar',{'entrada_id':ENT,'precio_centavos':7000,'metodo':{**metodo,'qr_path':qr},'client_key':uid(702)})
  o=call('comprar',{'oferta_id':f['id'],'client_key':uid(703)},B)
  # el QR de cobro aparece con todo lo demás: recién cuando el vendedor acepta
  call('aceptar',{'id':o['id']})
  self.assertEqual(call('orden',{'id':o['id']},B)['metodo']['qr_path'],qr)

unittest.main(argv=[sys.argv[0]],verbosity=2)
