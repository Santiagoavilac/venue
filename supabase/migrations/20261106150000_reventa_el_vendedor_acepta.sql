-- Los datos bancarios del vendedor dejan de ser gratis.
--
-- Hoy, para ver titular, banco, número de cuenta y QR de cobro de cualquiera
-- que esté vendiendo una entrada, alcanza con *iniciar* una orden: no cuesta
-- nada, no exige pagar y se puede cancelar enseguida. Con tres órdenes
-- simultáneas renovables se junta el mercado entero, y de paso se bloquean las
-- ofertas ajenas mientras se las mira.
--
-- Decidido: el vendedor acepta primero. Iniciar una orden le avisa y no muestra
-- ningún dato de cobro; recién cuando él acepta arranca el plazo de pago y
-- aparecen titular, banco y QR. Cada vez que se muestran queda anotado en el
-- historial, que el vendedor lee.
--
-- Y las reglas dejan de ser del boliche. Al boliche le queda prender y apagar
-- la reventa y escribir sus condiciones; los plazos y el techo de precio los
-- fija la plataforma, en una tabla sola. Un boliche no tiene por qué poder
-- poner el plazo de pago en 30 minutos, que es media hora de entrada bloqueada
-- por alguien que puede no pagar nunca.
--
-- Lo que NO cambia: la entrada publicada sigue bloqueada mientras se paga.
-- Soltarla invitaría a dos pagos reales por la misma entrada, que es peor. Lo
-- que cambia es que el mercado la muestra como "en pago, vuelve en N minutos"
-- en vez de esconderla, y que la ventana de daño baja de infinita a un plazo
-- corto, pocas veces por día.

-- ── 1 · las reglas son de la plataforma ───────────────────────────────
create table if not exists public.aftr_reventa_politica (
  unica                 boolean primary key default true check (unica),
  -- techo de precio, en % del precio original de la entrada
  max_precio_pct        int not null default 120 check (max_precio_pct between 100 and 300),
  -- lo que tiene el vendedor para aceptar o rechazar
  aceptacion_minutos    int not null default 30 check (aceptacion_minutos between 5 and 120),
  -- lo que tiene el comprador para pagar, desde que el vendedor aceptó
  pago_minutos          int not null default 15 check (pago_minutos between 5 and 30),
  -- lo que tiene el vendedor para confirmar que la plata llegó
  confirmacion_minutos  int not null default 30 check (confirmacion_minutos between 5 and 120),
  -- cuánto antes del evento se deja de poder revender
  cierre_minutos        int not null default 0 check (cierre_minutos between 0 and 1440),
  -- órdenes abiertas a la vez, y por día contando las que no salieron
  max_abiertas          int not null default 1 check (max_abiertas between 1 and 5),
  max_dia               int not null default 5 check (max_dia between 1 and 50),
  -- espera antes de volver a intentar sobre la MISMA oferta
  espera_horas          int not null default 6 check (espera_horas between 0 and 48),
  updated_at            timestamptz not null default now()
);
insert into public.aftr_reventa_politica (unica) values (true) on conflict do nothing;
alter table public.aftr_reventa_politica enable row level security;  -- se lee por las funciones
comment on table public.aftr_reventa_politica is
  'Las reglas de la reventa, iguales para todos. Al boliche le queda habilitada y condiciones.';

create or replace function impl.reventa_politica() returns aftr_reventa_politica
language sql stable security definer set search_path = public as $$
  select * from aftr_reventa_politica
$$;

-- ── 2 · el estado nuevo ───────────────────────────────────────────────
alter table public.aftr_reventa_ordenes drop constraint if exists aftr_reventa_ordenes_estado_check;
alter table public.aftr_reventa_ordenes add constraint aftr_reventa_ordenes_estado_check
  check (estado in ('esperando_vendedor', 'pendiente_pago', 'pago_informado',
                    'completada', 'cancelada', 'vencida', 'en_disputa'));

-- ── 3 · el techo, contra lo que se pagó de verdad ─────────────────────
-- Antes se medía siempre contra `entradas.precio`, que al re-emitir se copia
-- del original: una cadena de reventas conservaba el mismo techo para siempre
-- aunque cada paso cobrara más. Ahora la entrada arrastra el precio con el que
-- entró al mercado.
alter table public.entradas add column if not exists precio_base int;
comment on column public.entradas.precio_base is
  'Lo que pago quien la tiene. Se hereda al re-emitir por reventa: el techo se mide contra esto.';

/* El techo en centavos. Estaba escrito como `v_precio > x.precio * pct`, que
   da bien sólo porque precio está en Bs y el otro en centavos: funcionaba por
   casualidad. Acá queda una sola cuenta, explícita. */
create or replace function impl.reventa_techo(p_entrada entradas, p_pct int)
returns bigint language sql immutable as $$
  select (coalesce(p_entrada.precio_base, p_entrada.precio)::bigint * 100 * p_pct) / 100
$$;

-- ── 4 · lo que se muestra ─────────────────────────────────────────────
-- El método de cobro no sale hasta que el vendedor aceptó. Antes salía con la
-- orden recién creada, que es lo que hacía gratis juntar datos bancarios.
create or replace function impl.reventa_orden_json(o aftr_reventa_ordenes)
returns jsonb language sql stable security definer set search_path to 'public', 'pg_temp'
as $function$
 select jsonb_build_object('id',o.id,'oferta_id',o.oferta_id,'entrada_id',o.entrada_id,'evento_id',o.evento_id,
 'club_id',o.club_id,'evento',e.nombre,'club',c.nombre,'estado',o.estado,'comprador_id',o.comprador_id,
 'vendedor_id',o.vendedor_id,'comprador',coalesce(b.usuario,'Cuenta eliminada'),'vendedor',coalesce(s.usuario,'Cuenta eliminada'),'precio_centavos',o.precio_centavos,
 'vence_at',o.vence_at,'confirmar_hasta',o.confirmar_hasta,'created_at',o.created_at,'motivo',o.motivo,
 'resolucion',o.resolucion,'puede_resolver',es_platform_admin(),'nueva_entrada_id',o.nueva_entrada_id,'ahora',now(),
 'condiciones',f.condiciones,
 -- los datos de cobro, sólo a las partes y sólo después de que el vendedor
 -- aceptó: en esperando_vendedor no hay nada que mirar
 'metodo',case when o.estado<>'esperando_vendedor'
                and (auth.uid() in(o.comprador_id,o.vendedor_id) or es_platform_admin())
               then m.metodo end,
 'comprobante_path',case when auth.uid() in(o.comprador_id,o.vendedor_id) or es_platform_admin() then o.comprobante_path end,
 'referencia',case when auth.uid() in(o.comprador_id,o.vendedor_id) or es_platform_admin() then o.referencia end,
 'historial',case when auth.uid() in(o.comprador_id,o.vendedor_id) or es_platform_admin() then coalesce((
 select jsonb_agg(jsonb_build_object('id',h.id,'tipo',h.tipo,'texto',h.texto,'archivo_path',h.archivo_path,
 'created_at',h.created_at,'autor_id',h.autor_id,'autor',coalesce(ac.usuario,p.nombre,'AFTR')) order by h.id)
 from aftr_reventa_historial h left join aftr_clientes ac on ac.user_id=h.autor_id left join profiles p on p.id=h.autor_id
 where h.orden_id=o.id),'[]'::jsonb) else '[]'::jsonb end)
 from eventos e join clubs c on c.id=e.club_id left join aftr_clientes b on b.user_id=o.comprador_id
 left join aftr_clientes s on s.user_id=o.vendedor_id join aftr_reventa_ofertas f on f.id=o.oferta_id
 join aftr_reventa_metodos m on m.oferta_id=o.oferta_id where e.id=o.evento_id
$function$;

-- La oferta reservada no desaparece del mercado: dice cuándo vuelve.
create or replace function impl.reventa_oferta_json(o aftr_reventa_ofertas)
returns jsonb language sql stable security definer set search_path to 'public', 'pg_temp'
as $function$
 select jsonb_build_object('id',o.id,'entrada_id',o.entrada_id,'evento_id',o.evento_id,'club_id',o.club_id,
 'evento',e.nombre,'club',c.nombre,'fecha',e.fecha,'precio_centavos',o.precio_centavos,'vendedor',coalesce(u.usuario,'Cuenta eliminada'),
 'vendedor_id',o.vendedor_id,'estado',o.estado,'created_at',o.created_at,'cierre_at',o.cierre_at,
 'condiciones',o.condiciones,'pago_minutos',o.pago_minutos,'confirmacion_minutos',o.confirmacion_minutos,
 -- cuándo se libera si la operación en curso no sale
 'vuelve_at',(select min(d.vence_at) from aftr_reventa_ordenes d
               where d.oferta_id=o.id and d.estado in ('esperando_vendedor','pendiente_pago')))
 from eventos e join clubs c on c.id=e.club_id left join aftr_clientes u on u.user_id=o.vendedor_id where e.id=o.evento_id
$function$;

-- ── 5 · los vencimientos del estado nuevo ─────────────────────────────
create or replace function impl.reventa_vencer() returns void
language plpgsql security definer set search_path to 'public', 'pg_temp'
as $function$
declare r record; o aftr_reventa_ordenes;
begin
 -- Mismo orden de bloqueo siempre: entrada, oferta, orden.
 for r in select entrada_id,oferta_id,id from aftr_reventa_ordenes where
  (estado in ('esperando_vendedor','pendiente_pago') and vence_at<=now())
  or (estado='pago_informado' and confirmar_hasta<=now()) loop
  perform 1 from entradas where id=r.entrada_id for update skip locked; if not found then continue; end if;
  perform 1 from aftr_reventa_ofertas where id=r.oferta_id for update;
  select * into o from aftr_reventa_ordenes where id=r.id for update;
  if o.estado='esperando_vendedor' and o.vence_at<=now() then
   update aftr_reventa_ordenes set estado='vencida',updated_at=now() where id=o.id;
   perform impl.reventa_liberar(o.oferta_id);
   perform impl.reventa_anotar(o.id,'vencida','El vendedor no respondió en el plazo. No se mostró ningún dato de cobro y no hay nada que pagar.');
  elsif o.estado='pendiente_pago' and o.vence_at<=now() then
   update aftr_reventa_ordenes set estado='vencida',updated_at=now() where id=o.id;
   perform impl.reventa_liberar(o.oferta_id);
   perform impl.reventa_anotar(o.id,'vencida','Venció el plazo sin pago informado. No realices una transferencia.');
  elsif o.estado='pago_informado' and o.confirmar_hasta<=now() then
   update aftr_reventa_ordenes set estado='en_disputa',motivo='El vendedor no confirmó la recepción dentro del plazo.',updated_at=now() where id=o.id;
   perform impl.reventa_anotar(o.id,'en_disputa','Se abrió una disputa automática. La entrada continúa bloqueada hasta la resolución de AFTR.');
  end if;
 end loop;
 for r in select id,entrada_id from aftr_reventa_ofertas where estado='publicada' and cierre_at<=now() loop
  perform 1 from entradas where id=r.entrada_id for update skip locked; if not found then continue; end if;
  perform 1 from aftr_reventa_ofertas where id=r.id and estado='publicada' for update;
  if found then perform impl.reventa_liberar(r.id); end if;
 end loop;
end $function$;

-- ── 6 · la entrada re-emitida hereda lo que se pagó ───────────────────
create or replace function impl.reventa_finalizar(p_orden uuid) returns uuid
language plpgsql security definer set search_path to 'public', 'pg_temp'
as $function$
declare o aftr_reventa_ordenes; x entradas; n uuid:=gen_random_uuid(); v_nombre text; v_fin timestamptz;
begin
 select * into o from aftr_reventa_ordenes where id=p_orden;
 select * into x from entradas where id=o.entrada_id for update;
 perform 1 from aftr_reventa_ofertas where id=o.oferta_id for update;
 select * into o from aftr_reventa_ordenes where id=p_orden for update;
 if o.estado='completada' then return o.nueva_entrada_id; end if;
 if o.estado not in ('pago_informado','en_disputa') then raise exception 'Esta operación no está lista para entregar.'; end if;
 select impl.aftr_fin(fecha,hora_inicio,hora_fin) into v_fin from eventos where id=o.evento_id;
 if v_fin<=now() then raise exception 'El evento terminó. Resolvé el reintegro en la disputa.'; end if;
 if x.estado<>'valida' or x.cliente_id<>o.vendedor_id or x.reventa_oferta_id is distinct from o.oferta_id or x.reventa_sucesora_id is not null then
  raise exception 'La entrada no está disponible. Requiere revisión.';
 end if;
 select nombre into v_nombre from aftr_clientes where user_id=o.comprador_id;
 perform set_config('aftr.reventa_interna',o.oferta_id::text,true);
 update entradas set estado='anulada',reventa_sucesora_id=n,reventa_oferta_id=null where id=x.id;
 -- precio_base es lo que pagó el comprador: el techo de la próxima reventa se
 -- mide contra esto y no contra el precio original de siempre
 insert into entradas(id,evento_id,code,cliente,rrpp_id,precio,precio_base,estado,created_at,fase_id,cliente_id,canal,
 reventa_anterior_id,reventa_raiz_id)
 values(n,x.evento_id,upper(replace(gen_random_uuid()::text,'-','')),v_nombre,x.rrpp_id,x.precio,
 greatest((o.precio_centavos/100)::int,1),'valida',x.created_at,
 x.fase_id,o.comprador_id,'aftr',x.id,coalesce(x.reventa_raiz_id,x.id));
 update aftr_reventa_ofertas set estado='vendida' where id=o.oferta_id;
 update aftr_reventa_ordenes set estado='completada',nueva_entrada_id=n,updated_at=now() where id=o.id;
 perform impl.reventa_anotar(o.id,'completada','Entrada entregada. El QR anterior quedó invalidado definitivamente.');
 perform set_config('aftr.reventa_interna','',true);
 return n;
end $function$;

notify pgrst,'reload schema';
-- ── 7 · el despachador ────────────────────────────────────────────────
-- Dos cambios de forma, además de los de fondo:
--
-- * la sesión se exige ARRIBA, por lista de acciones públicas. Antes lo único
--   que separaba lo público de lo privado era el orden de los `if`: un
--   `p_accion` nuevo puesto por error antes del chequeo abría todo sin sesión.
-- * `publicar` y `comprar` leen los plazos y el techo de la política de la
--   plataforma, no de la configuración del boliche.
create or replace function public.aftr_reventa(p_accion text, p_datos jsonb default '{}'::jsonb)
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp'
as $function$
#variable_conflict use_column
declare u uuid:=auth.uid(); v_id uuid; v_oferta uuid; v_entrada uuid; v_club text; v_precio bigint;
 v_key uuid; x entradas; e eventos; f aftr_reventa_ofertas; o aftr_reventa_ordenes; cfg aftr_reventa_config;
 pol aftr_reventa_politica; v_metodo jsonb; v_path text; v_texto text; v_accion text; v_fin timestamptz;
 r jsonb; z record; v_desde timestamptz;
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
    -- las reservadas se muestran: con 3.2 vuelven solas en minutos, y
    -- esconderlas hacía ver un mercado más chico del que hay
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
  'max_centavos',impl.reventa_techo(t,pol.max_precio_pct))) from entradas t join eventos e on e.id=t.evento_id
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
   -- Del boliche sólo se toman estas dos. Los plazos y el techo son de la
   -- plataforma: si llegan en p_datos, se ignoran.
   update aftr_reventa_config set habilitada=coalesce((p_datos->>'habilitada')::boolean,false),
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
  -- sólo la plataforma, y es lo único que la escribe
  if not es_platform_admin() then raise exception 'Solo AFTR define las reglas de la reventa.' using errcode='42501'; end if;
  if p_datos ? 'max_precio_pct' then
   update aftr_reventa_politica set
    max_precio_pct=coalesce((p_datos->>'max_precio_pct')::int,max_precio_pct),
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
  if v_precio>impl.reventa_techo(x,pol.max_precio_pct) then
   raise exception 'El máximo para esta entrada es Bs %.', round(impl.reventa_techo(x,pol.max_precio_pct)/100.0,2); end if;
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
  -- una sola abierta: antes eran tres, y tres órdenes renovables alcanzaban
  -- para juntar los datos de cobro de todo el mercado
  if (select count(*) from aftr_reventa_ordenes where comprador_id=u
       and estado in ('esperando_vendedor','pendiente_pago','pago_informado'))>=pol.max_abiertas then
   raise exception 'Resolvé tu operación pendiente antes de iniciar otra.'; end if;
  -- el tope diario cuenta también las que no salieron: el abuso es renovar
  if (select count(*) from aftr_reventa_ordenes where comprador_id=u and created_at>now()-interval '24 hours')>=pol.max_dia then
   raise exception 'Llegaste al máximo de operaciones por día.'; end if;
  -- y no se insiste sobre la misma oferta
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
  -- el vendedor decide antes de que se muestre un solo dato suyo
  if u<>o.vendedor_id then raise exception 'Solo el vendedor puede responder este pedido.' using errcode='42501'; end if;
  if p_accion='aceptar' then
   if o.estado='pendiente_pago' then return impl.reventa_orden_json(o); end if;
   if o.estado<>'esperando_vendedor' or o.vence_at<=now() then raise exception 'Este pedido ya no se puede aceptar.'; end if;
   update aftr_reventa_ordenes set estado='pendiente_pago',
    vence_at=least(now()+make_interval(mins=>f.pago_minutos),f.cierre_at),updated_at=now() where id=o.id;
   -- queda escrito que se mostraron: el vendedor ve cuándo y a quién
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

-- ── 8 · lo mismo en historias ─────────────────────────────────────────
-- `aftr_historias` tenía el mismo problema de forma: la sesión se exigía
-- después del branch del feed, así que lo único que separaba lo público de lo
-- privado era el orden de los `if`.
do $migra$
declare v_def text;
begin
  select pg_get_functiondef(p.oid) into v_def from pg_proc p join pg_namespace n on n.oid=p.pronamespace
   where n.nspname='public' and p.proname='aftr_historias';
  if position('La única acción sin sesión' in v_def) > 0 then return; end if;
  v_def := replace(v_def,
    ' if p_accion=''feed'' then' || chr(10),
    ' -- La única acción sin sesión es el feed. Decidido acá y no por el orden' || chr(10) ||
    ' -- de los if: un p_accion nuevo puesto arriba abría todo sin sesión.' || chr(10) ||
    ' if p_accion<>''feed'' and u is null then raise exception ''Iniciá sesión.'' using errcode=''28000''; end if;' || chr(10) ||
    ' if p_accion=''feed'' then' || chr(10));
  v_def := replace(v_def,
    ' if u is null then raise exception ''Iniciá sesión.'' using errcode=''28000''; end if;' || chr(10) ||
    ' if p_accion in (''mias'',''gestion'') then',
    ' if p_accion in (''mias'',''gestion'') then');
  execute v_def;
end $migra$;
notify pgrst,'reload schema';
