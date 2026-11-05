-- El precio de la reventa lo pone el boliche, y PULSE son Bs 300 por semana.
--
-- Dos números que puse yo sin que nadie me los pidiera, y los dos están mal:
--
-- * la Fase 3 movió el techo de precio de la reventa a la política de la
--   plataforma, con un 120 % por defecto. Los PLAZOS sí son de la plataforma
--   -un boliche poniendo 30 minutos de pago es media hora de entrada bloqueada
--   por alguien que puede no pagar nunca-, pero el precio no: es su mercado y
--   su decisión. Vuelve a `aftr_reventa_config.max_precio_pct`, y vacío sigue
--   siendo precio libre, como era antes de que lo tocara.
-- * el tope de recarga de PULSE quedó en Bs 2.000 por vez y Bs 10.000 por día.
--   El tope real es Bs 300 por semana.
--
-- Lo único que se conserva del cambio de precio es contra QUÉ se mide el techo
-- cuando el boliche pone uno: `precio_base`, lo que pagó quien revende, en vez
-- del precio original de siempre. Si no, una cadena de reventas conservaba para
-- siempre el techo del primero, que era el bug que el plan señalaba.

-- El precio de la reventa NO lo decide la plataforma.
--
-- La Fase 3 movió los plazos y el techo de precio a una política única. Los
-- plazos sí: un boliche poniendo 30 minutos de pago es media hora de entrada
-- bloqueada. El precio no: lo pone cada boliche -y vacío sigue siendo precio
-- libre, como era antes-, porque es su mercado y su decisión, no la nuestra.
alter table public.aftr_reventa_politica
  alter column max_precio_pct drop not null,
  alter column max_precio_pct drop default;
alter table public.aftr_reventa_politica drop constraint if exists aftr_reventa_politica_max_precio_pct_check;
update public.aftr_reventa_politica set max_precio_pct = null;
comment on column public.aftr_reventa_politica.max_precio_pct is
  'Sin uso: el techo de precio es de cada boliche (aftr_reventa_config). Queda la columna para no romper la fila unica.';

-- El techo vuelve a salir de la configuración del boliche, y vacío es libre.
-- Lo que sí se conserva es contra QUÉ se mide: `precio_base`, lo que pagó quien
-- revende, en vez del precio original de siempre. Si no, una cadena de reventas
-- conservaba para siempre el techo del primero.
create or replace function impl.reventa_techo(p_entrada entradas, p_pct int)
returns bigint language sql immutable as $$
  select case when p_pct is null then null
              else (coalesce(p_entrada.precio_base, p_entrada.precio)::bigint * 100 * p_pct) / 100 end
$$;

create or replace function public.aftr_reventa(p_accion text, p_datos jsonb default '{}'::jsonb)
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp'
as $function$
#variable_conflict use_column
declare u uuid:=auth.uid(); v_id uuid; v_oferta uuid; v_entrada uuid; v_club text; v_precio bigint;
 v_key uuid; x entradas; e eventos; f aftr_reventa_ofertas; o aftr_reventa_ordenes; cfg aftr_reventa_config;
 pol aftr_reventa_politica; v_metodo jsonb; v_path text; v_texto text; v_accion text; v_fin timestamptz;
 r jsonb; z record; v_desde timestamptz; v_techo bigint;
begin
 if p_datos is null or jsonb_typeof(p_datos)<>'object' or octet_length(p_datos::text)>16000 then raise exception 'Datos no válidos.'; end if;
 -- La única acción sin sesión es el mercado. Decidido acá y no por el orden de
 -- los if, para que agregar una acción nueva no abra nada por descuido.
 if p_accion<>'mercado' and u is null then raise exception 'Iniciá sesión.' using errcode='28000'; end if;
 pol:=impl.reventa_politica();
 perform impl.reventa_vencer();
 if p_accion='mercado' then
  return jsonb_build_object('ofertas',coalesce((select jsonb_agg(impl.reventa_oferta_json(t)) from
   (select f.* from aftr_reventa_ofertas f join aftr_reventa_config c on c.club_id=f.club_id and c.habilitada
    where f.estado in ('publicada','reservada') and f.cierre_at>now() and impl.aftr_visible(f.evento_id)
    and (p_datos->>'evento_id' is null or f.evento_id=(p_datos->>'evento_id')::uuid)
    order by f.estado='publicada' desc, f.created_at desc limit 200) t),'[]'::jsonb),'ahora',now());
 end if;
 if p_accion='mias' then
  perform impl.aftr_yo();
  return jsonb_build_object('ofertas',coalesce((select jsonb_agg(impl.reventa_oferta_json(f) order by f.created_at desc)
   from aftr_reventa_ofertas f where f.vendedor_id=u),'[]'::jsonb),
  'ordenes',coalesce((select jsonb_agg(impl.reventa_orden_json(o) order by o.created_at desc) from aftr_reventa_ordenes o
   where u in(o.comprador_id,o.vendedor_id)),'[]'::jsonb),
  'entradas',coalesce((select jsonb_agg(jsonb_build_object('id',t.id,'evento_id',t.evento_id,'evento',e.nombre,
  'precio',t.precio,'estado',case when t.reventa_oferta_id is not null then 'bloqueada' else t.estado end,
  'club_id',e.club_id,'reventa_habilitada',coalesce(c.habilitada,false),
  -- el techo es del boliche; vacío es precio libre
  'max_centavos',impl.reventa_techo(t,c.max_precio_pct))) from entradas t join eventos e on e.id=t.evento_id
  left join aftr_reventa_config c on c.club_id=e.club_id where t.cliente_id=u and t.estado='valida' and t.mesa_id is null
  and t.precio>0 and t.reventa_sucesora_id is null and impl.aftr_fin(e.fecha,e.hora_inicio,e.hora_fin)>now()),'[]'::jsonb),
  'politica',to_jsonb(pol),'ahora',now());
 elsif p_accion in ('gestion','configurar') then
  v_club:=nullif(p_datos->>'club_id','');
  if (v_club is null and not es_platform_admin()) or
     (v_club is not null and coalesce(rol_en_club(v_club),'') not in ('admin','propietario')) then
   raise exception 'No autorizado.' using errcode='42501'; end if;
  if v_club is not null then
   perform pg_advisory_xact_lock(hashtextextended('reventa-config:'||v_club,0));
   insert into aftr_reventa_config(club_id) values(v_club) on conflict do nothing;
   select * into cfg from aftr_reventa_config where club_id=v_club;
  end if;
  if p_accion='configurar' then
   if v_club is null then raise exception 'Elegí un boliche.'; end if;
   -- Del boliche: si vende por reventa, su techo de precio y sus condiciones.
   -- Los plazos son de la plataforma: si llegan en p_datos, se ignoran.
   if (p_datos->>'max_precio_pct') is not null and
      ((p_datos->>'max_precio_pct')::int < 100 or (p_datos->>'max_precio_pct')::int > 1000) then
    raise exception 'El techo va de 100 %% (el precio pagado) a 1000 %%, o vacío para precio libre.';
   end if;
   update aftr_reventa_config set habilitada=coalesce((p_datos->>'habilitada')::boolean,false),
    max_precio_pct=nullif(p_datos->>'max_precio_pct','')::int,
    condiciones=coalesce(p_datos->>'condiciones',''),updated_at=now()
   where club_id=v_club returning * into cfg;
   if not cfg.habilitada then
    for z in select id,entrada_id from aftr_reventa_ofertas where club_id=v_club and estado='publicada' loop
     perform 1 from entradas where id=z.entrada_id for update;
     perform 1 from aftr_reventa_ofertas where id=z.id and estado='publicada' for update;
     if found then perform impl.reventa_liberar(z.id); end if;
    end loop;
   end if;
  end if;
  return jsonb_build_object('config',coalesce(to_jsonb(cfg),'{}'::jsonb),'admin_principal',es_platform_admin(),
   'politica',to_jsonb(pol),
   'ofertas',coalesce((select jsonb_agg(impl.reventa_oferta_json(f) order by f.created_at desc) from aftr_reventa_ofertas f
    where (v_club is null or f.club_id=v_club)),'[]'::jsonb),
   'ordenes',coalesce((select jsonb_agg(impl.reventa_orden_json(o) order by o.created_at desc) from aftr_reventa_ordenes o
    where (v_club is null or o.club_id=v_club)),'[]'::jsonb),
   'disputas',coalesce((select jsonb_agg(impl.reventa_orden_json(o) order by o.updated_at) from aftr_reventa_ordenes o
    where o.estado='en_disputa' and (v_club is null or o.club_id=v_club)),'[]'::jsonb),'ahora',now());
 elsif p_accion='politica' then
  if not es_platform_admin() then raise exception 'Solo AFTR define los plazos de la reventa.' using errcode='42501'; end if;
  if p_datos ? 'pago_minutos' or p_datos ? 'aceptacion_minutos' then
   update aftr_reventa_politica set
    aceptacion_minutos=coalesce((p_datos->>'aceptacion_minutos')::int,aceptacion_minutos),
    pago_minutos=coalesce((p_datos->>'pago_minutos')::int,pago_minutos),
    confirmacion_minutos=coalesce((p_datos->>'confirmacion_minutos')::int,confirmacion_minutos),
    cierre_minutos=coalesce((p_datos->>'cierre_minutos')::int,cierre_minutos),
    max_abiertas=coalesce((p_datos->>'max_abiertas')::int,max_abiertas),
    max_dia=coalesce((p_datos->>'max_dia')::int,max_dia),
    espera_horas=coalesce((p_datos->>'espera_horas')::int,espera_horas),
    updated_at=now();
   pol:=impl.reventa_politica();
  end if;
  return jsonb_build_object('politica',to_jsonb(pol),'ahora',now());
 elsif p_accion='publicar' then
  perform impl.aftr_yo();
  v_entrada:=(p_datos->>'entrada_id')::uuid;v_key:=(p_datos->>'client_key')::uuid;v_precio:=(p_datos->>'precio_centavos')::bigint;
  if v_key is null or v_precio is null or v_precio<100 or v_precio>100000000 then raise exception 'Ingresá un precio válido en Bs.'; end if;
  perform pg_advisory_xact_lock(hashtextextended('reventa-publicar:'||u||':'||v_key,0));
  select * into f from aftr_reventa_ofertas where vendedor_id=u and client_key=v_key;
  if found then
   if f.entrada_id<>v_entrada or f.precio_centavos<>v_precio then raise exception 'Esta operación ya tiene otros datos.'; end if;
   return impl.reventa_oferta_json(f);
  end if;
  perform impl.aftr_limite('reventa_publicar',10,interval '1 hour','Publicaste muchas entradas en poco tiempo. Esperá un rato.');
  select e.club_id into v_club from entradas t join eventos e on e.id=t.evento_id where t.id=v_entrada;
  perform pg_advisory_xact_lock(hashtextextended('reventa-config:'||coalesce(v_club,''),0));
  select * into x from entradas where id=v_entrada for update;
  if not found or x.cliente_id is distinct from u then raise exception 'Esta entrada no es tuya.' using errcode='42501'; end if;
  if x.estado<>'valida' or x.reventa_oferta_id is not null or x.reventa_sucesora_id is not null or x.mesa_id is not null
   or x.precio<=0 or x.canal<>'aftr' or x.filtro_at is not null then raise exception 'Esta entrada no está disponible para reventa.'; end if;
  select * into e from eventos where id=x.evento_id;
  select * into cfg from aftr_reventa_config where club_id=e.club_id;
  if not found or not cfg.habilitada or not impl.aftr_visible(e.id) then raise exception 'El boliche no habilitó la reventa para este evento.'; end if;
  v_fin:=least(coalesce(e.entrada_hasta,impl.aftr_fin(e.fecha,e.hora_inicio,e.hora_fin)),impl.aftr_fin(e.fecha,e.hora_inicio,e.hora_fin))-make_interval(mins=>pol.cierre_minutos);
  if v_fin<=now()+make_interval(mins=>pol.aceptacion_minutos+pol.pago_minutos) then raise exception 'Ya cerró el plazo para revender esta entrada.'; end if;
  -- el techo lo pone el boliche; si no puso ninguno, el precio es libre
  v_techo:=impl.reventa_techo(x,cfg.max_precio_pct);
  if v_techo is not null and v_precio>v_techo then
   raise exception 'El máximo para esta entrada es Bs %.', round(v_techo/100.0,2); end if;
  v_metodo:=p_datos->'metodo';
  if jsonb_typeof(v_metodo) is distinct from 'object' or length(trim(coalesce(v_metodo->>'titular','')))<3 or
  length(trim(coalesce(v_metodo->>'banco','')))<2 or
  (length(trim(coalesce(v_metodo->>'cuenta','')))<3 and nullif(v_metodo->>'qr_path','') is null) or octet_length(v_metodo::text)>4000 then
   raise exception 'Completá titular, banco y cuenta o QR de cobro.'; end if;
  if nullif(v_metodo->>'qr_path','') is not null and not exists(select 1 from storage.objects where bucket_id='aftr-p2p'
    and name=v_metodo->>'qr_path' and split_part(name,'/',1)=u::text) then raise exception 'El QR de cobro no pertenece a tu cuenta.'; end if;
  insert into aftr_reventa_ofertas(entrada_id,evento_id,club_id,vendedor_id,precio_centavos,pago_minutos,confirmacion_minutos,cierre_at,condiciones,client_key)
  values(x.id,e.id,e.club_id,u,v_precio,pol.pago_minutos,pol.confirmacion_minutos,v_fin,cfg.condiciones,v_key) returning * into f;
  insert into aftr_reventa_metodos(oferta_id,metodo) values(f.id,jsonb_build_object('titular',trim(v_metodo->>'titular'),
   'banco',trim(v_metodo->>'banco'),'cuenta',trim(v_metodo->>'cuenta'),'qr_path',nullif(v_metodo->>'qr_path','')));
  update entradas set reventa_oferta_id=f.id where id=x.id;
  return impl.reventa_oferta_json(f);
 elsif p_accion='comprar' then
  perform impl.aftr_yo();v_oferta:=(p_datos->>'oferta_id')::uuid;v_key:=(p_datos->>'client_key')::uuid;
  if v_key is null then raise exception 'Falta la identificación de la operación.'; end if;
  perform pg_advisory_xact_lock(hashtextextended('reventa-comprar:'||u||':'||v_key,0));
  select * into o from aftr_reventa_ordenes where comprador_id=u and client_key=v_key;
  if found then
   if o.oferta_id<>v_oferta then raise exception 'La operación ya pertenece a otra oferta.'; end if;
   return impl.reventa_orden_json(o); end if;
  select entrada_id into v_entrada from aftr_reventa_ofertas where id=v_oferta;
  perform 1 from entradas where id=v_entrada for update;
  select * into f from aftr_reventa_ofertas where id=v_oferta for update;
  if not found or f.estado<>'publicada' or f.cierre_at<=now() or not impl.aftr_visible(f.evento_id)
   or not exists(select 1 from aftr_reventa_config where club_id=f.club_id and habilitada) then raise exception 'Esta oferta ya no está disponible.'; end if;
  if f.vendedor_id=u then raise exception 'No podés comprar tu propia entrada.'; end if;
  if (select count(*) from aftr_reventa_ordenes where comprador_id=u
       and estado in ('esperando_vendedor','pendiente_pago','pago_informado'))>=pol.max_abiertas then
   raise exception 'Resolvé tu operación pendiente antes de iniciar otra.'; end if;
  if (select count(*) from aftr_reventa_ordenes where comprador_id=u and created_at>now()-interval '24 hours')>=pol.max_dia then
   raise exception 'Llegaste al máximo de operaciones por día.'; end if;
  select max(created_at) into v_desde from aftr_reventa_ordenes where comprador_id=u and oferta_id=v_oferta;
  if v_desde is not null and v_desde>now()-make_interval(hours=>pol.espera_horas) then
   raise exception 'Ya intentaste esta oferta. Probá de nuevo más tarde.'; end if;
  insert into aftr_reventa_ordenes(oferta_id,entrada_id,evento_id,club_id,vendedor_id,comprador_id,precio_centavos,vence_at,client_key,estado)
  values(f.id,f.entrada_id,f.evento_id,f.club_id,f.vendedor_id,u,f.precio_centavos,
   least(now()+make_interval(mins=>pol.aceptacion_minutos),f.cierre_at),v_key,'esperando_vendedor') returning * into o;
  update aftr_reventa_ofertas set estado='reservada' where id=f.id;
  perform impl.reventa_anotar(o.id,'esperando_vendedor','Pedido enviado al vendedor. Cuando acepte vas a ver sus datos de cobro y arranca el plazo para pagar.');
  return impl.reventa_orden_json(o);
 end if;

 if p_accion in ('cancelar','retirar_oferta') and p_datos->>'oferta_id' is not null then
  select * into f from aftr_reventa_ofertas where id=(p_datos->>'oferta_id')::uuid;
  perform 1 from entradas where id=f.entrada_id for update;
  select * into f from aftr_reventa_ofertas where id=f.id for update;
  if not found or not coalesce(f.vendedor_id=u or es_platform_admin() or
   (p_accion='retirar_oferta' and rol_en_club(f.club_id) in ('admin','propietario')),false) then raise exception 'No autorizado.' using errcode='42501'; end if;
  if f.estado='retirada' then return jsonb_build_object('ok',true); end if;
  if f.estado<>'publicada' then raise exception 'Hay una operación en curso. Resolvela desde la orden.'; end if;
  perform impl.reventa_liberar(f.id); return jsonb_build_object('ok',true);
 end if;

 v_id:=nullif(p_datos->>'id','')::uuid;
 select * into o from aftr_reventa_ordenes where id=v_id;
 if not found or not coalesce(u in(o.comprador_id,o.vendedor_id) or es_platform_admin() or
  (p_accion='orden' and rol_en_club(o.club_id) in ('admin','propietario')),false) then raise exception 'Operación no encontrada.' using errcode='42501'; end if;
 if p_accion='orden' then return impl.reventa_orden_json(o); end if;
 perform 1 from entradas where id=o.entrada_id for update;
 select * into f from aftr_reventa_ofertas where id=o.oferta_id for update;
 select * into o from aftr_reventa_ordenes where id=v_id for update;
 if p_accion in ('aceptar','rechazar') then
  if u<>o.vendedor_id then raise exception 'Solo el vendedor puede responder este pedido.' using errcode='42501'; end if;
  if p_accion='aceptar' then
   if o.estado='pendiente_pago' then return impl.reventa_orden_json(o); end if;
   if o.estado<>'esperando_vendedor' or o.vence_at<=now() then raise exception 'Este pedido ya no se puede aceptar.'; end if;
   update aftr_reventa_ordenes set estado='pendiente_pago',
    vence_at=least(now()+make_interval(mins=>f.pago_minutos),f.cierre_at),updated_at=now() where id=o.id;
   perform impl.reventa_anotar(o.id,'pendiente_pago','El vendedor aceptó y se mostraron sus datos de cobro al comprador. Pagá y adjuntá el comprobante dentro del plazo.');
  else
   if o.estado in ('cancelada','vencida') then return impl.reventa_orden_json(o); end if;
   if o.estado<>'esperando_vendedor' then raise exception 'Este pedido ya no se puede rechazar.'; end if;
   update aftr_reventa_ordenes set estado='cancelada',updated_at=now() where id=o.id;
   perform impl.reventa_liberar(o.oferta_id);
   perform impl.reventa_anotar(o.id,'cancelada','El vendedor rechazó el pedido. No se mostró ningún dato de cobro.');
  end if;
 elsif p_accion='informar_pago' then
  if u<>o.comprador_id then raise exception 'Solo el comprador puede informar el pago.' using errcode='42501'; end if;
  if o.estado='pago_informado' then return impl.reventa_orden_json(o); end if;
  if o.estado<>'pendiente_pago' or o.vence_at<=now() then raise exception 'El plazo venció. No transfieras dinero. Si ya pagaste, abrí una disputa.'; end if;
  v_path:=p_datos->>'comprobante_path';v_texto:=trim(p_datos->>'referencia');
  if length(coalesce(v_texto,'')) not between 2 and 200 or not exists(select 1 from storage.objects where bucket_id='aftr-p2p'
   and name=v_path and split_part(name,'/',1)=u::text) then raise exception 'Adjuntá tu comprobante y la referencia del pago.'; end if;
  update aftr_reventa_ordenes set estado='pago_informado',comprobante_path=v_path,referencia=v_texto,
   confirmar_hasta=now()+make_interval(mins=>f.confirmacion_minutos),updated_at=now() where id=o.id;
  perform impl.reventa_anotar(o.id,'pago_informado','El comprador informó el pago. El vendedor debe verificar la recepción real.',v_path);
 elsif p_accion='confirmar' then
  if u<>o.vendedor_id then raise exception 'Solo el vendedor puede confirmar la recepción.' using errcode='42501'; end if;
  if o.estado='completada' then return impl.reventa_orden_json(o); end if;
  if o.estado<>'pago_informado' then raise exception 'La orden requiere revisión de AFTR o no tiene pago informado.'; end if;
  perform impl.reventa_finalizar(o.id);
 elsif p_accion='cancelar' then
  if o.estado in ('cancelada','vencida') then return impl.reventa_orden_json(o); end if;
  if o.estado not in ('esperando_vendedor','pendiente_pago') then raise exception 'Hay un pago informado. Abrí una disputa para resolverlo.'; end if;
  update aftr_reventa_ordenes set estado='cancelada',updated_at=now() where id=o.id;
  perform impl.reventa_liberar(o.oferta_id);
  perform impl.reventa_anotar(o.id,'cancelada','Operación cancelada antes de informar pago.');
 elsif p_accion='disputar' then
  if o.resolucion is not null then raise exception 'AFTR ya resolvió esta disputa.'; end if;
  v_texto:=trim(p_datos->>'motivo');
  if length(coalesce(v_texto,'')) not between 5 and 1000 then raise exception 'Describí el problema (5 a 1000 caracteres).'; end if;
  if o.estado='en_disputa' then return impl.reventa_orden_json(o); end if;
  if o.estado='completada' then raise exception 'La operación ya fue entregada. Su historial permanece disponible.'; end if;
  if o.estado='esperando_vendedor' then raise exception 'Todavía no hay nada que disputar: el vendedor no aceptó y no se mostró ningún dato de cobro.'; end if;
  if o.estado in ('cancelada','vencida') then
   update aftr_reventa_ordenes set estado='en_disputa',motivo='Pago tardío: '||v_texto,updated_at=now() where id=o.id;
   if not exists(select 1 from aftr_reventa_ofertas where id=o.oferta_id and estado in ('publicada','reservada','vendida')) and
    exists(select 1 from entradas where id=o.entrada_id and estado='valida' and cliente_id=o.vendedor_id and reventa_oferta_id is null) then
    update entradas set reventa_oferta_id=o.oferta_id where id=o.entrada_id;
   end if;
  else update aftr_reventa_ordenes set estado='en_disputa',motivo=v_texto,updated_at=now() where id=o.id; end if;
  perform impl.reventa_anotar(o.id,'en_disputa',v_texto);
 elsif p_accion='mensaje' then
  if o.estado not in ('esperando_vendedor','pendiente_pago','pago_informado','en_disputa') then raise exception 'Esta operación ya está cerrada.'; end if;
  v_texto:=trim(p_datos->>'texto');v_path:=nullif(p_datos->>'archivo_path','');
  if length(coalesce(v_texto,'')) not between 1 and 2000 then raise exception 'Escribí un mensaje de hasta 2000 caracteres.'; end if;
  if (select count(*) from aftr_reventa_historial where autor_id=u and created_at>now()-interval '1 minute')>=20 then raise exception 'Esperá un momento antes de enviar otro mensaje.'; end if;
  if v_path is not null and not exists(select 1 from storage.objects where bucket_id='aftr-p2p' and name=v_path and split_part(name,'/',1)=u::text) then
   raise exception 'El archivo no pertenece a tu cuenta.'; end if;
  perform impl.reventa_anotar(o.id,'mensaje',v_texto,v_path);
 elsif p_accion='resolver' then
  if not es_platform_admin() then raise exception 'Solo AFTR puede resolver disputas.' using errcode='42501'; end if;
  v_texto:=trim(p_datos->>'motivo');v_accion:=p_datos->>'resolucion';
  if o.estado<>'en_disputa' or length(coalesce(v_texto,'')) not between 10 and 2000 then raise exception 'Se requiere una disputa abierta y un motivo de resolución.'; end if;
  if v_accion='entregar' then perform impl.reventa_finalizar(o.id);
  elsif v_accion='cancelar' then
   update aftr_reventa_ordenes set estado='cancelada',updated_at=now() where id=o.id;
   if exists(select 1 from entradas where id=o.entrada_id and reventa_oferta_id=o.oferta_id) then perform impl.reventa_liberar(o.oferta_id); end if;
  else raise exception 'Resolución no válida.'; end if;
  update aftr_reventa_ordenes set resolucion=v_accion||': '||v_texto,resuelta_por=u where id=o.id;
  perform impl.reventa_anotar(o.id,'resolucion','AFTR resolvió: '||v_accion||'. '||v_texto);
 else raise exception 'Acción de reventa no válida.';
 end if;
 select * into o from aftr_reventa_ordenes where id=v_id;
 return impl.reventa_orden_json(o);
end $function$;
notify pgrst,'reload schema';

-- Bs 300 por semana en PULSE, y nada más.
--
-- Estaba en Bs 2.000 por recarga y Bs 10.000 por día, que los puse yo sin
-- preguntar. El tope real es Bs 300 por semana: PULSE es para la noche, no una
-- cuenta bancaria, y la plata que entra ahí la tenemos nosotros hasta que se
-- gasta.
create or replace function public.aftr_recargar_pulse(p_centavos bigint, p_client_key uuid)
returns jsonb language plpgsql security definer set search_path to 'public'
as $function$
declare c aftr_clientes := impl.aftr_yo(); r pulse_recargas; v_semana bigint;
begin
  perform impl.aftr_limite('recargar', 10, interval '1 hour', 'Muchas recargas en poco tiempo. Esperá un rato.');
  if p_centavos is null or p_centavos < 100 or p_client_key is null then
    raise exception 'La recarga mínima es Bs 1';
  end if;
  if p_centavos > 30000 then raise exception 'El máximo es Bs 300 por semana.'; end if;
  -- Lo ya pedido cuenta, pagado o esperando pago: si no, se evita el tope
  -- dejando diez QR abiertos. La clave de esta misma operación no se cuenta,
  -- para que reintentar no sume dos veces.
  select coalesce(sum(importe_centavos), 0) into v_semana from pulse_recargas
   where cliente_id = c.user_id and created_at > now() - interval '7 days'
     and estado in ('pendiente', 'confirmada') and client_key is distinct from p_client_key;
  if v_semana + p_centavos > 30000 then
    raise exception 'Llegaste al máximo de Bs 300 de recarga por semana. Te quedan Bs %.',
      round(greatest(30000 - v_semana, 0) / 100.0, 2);
  end if;
  insert into pulse_recargas (cliente_id, importe_centavos, client_key)
  values (c.user_id, p_centavos, p_client_key)
    on conflict (cliente_id, client_key) do nothing;
  select * into r from pulse_recargas where cliente_id = c.user_id and client_key = p_client_key;
  if r.importe_centavos <> p_centavos then raise exception 'La operación ya tiene otro importe'; end if;
  return to_jsonb(r);
end $function$;
revoke all on function public.aftr_recargar_pulse(bigint, uuid) from public, anon;
grant execute on function public.aftr_recargar_pulse(bigint, uuid) to authenticated, service_role;
notify pgrst,'reload schema';

