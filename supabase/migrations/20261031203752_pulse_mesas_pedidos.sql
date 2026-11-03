-- PULSE: 100 centavos = 1 PULSE = Bs 1. Sin comisiones ni transferencias automáticas.
begin;
create table pulse_cuentas (
  cliente_id uuid primary key references aftr_clientes(user_id),
  saldo_centavos bigint not null default 0 check (saldo_centavos >= 0)
);
create table pulse_movimientos (
  id uuid primary key default gen_random_uuid(), cliente_id uuid not null references pulse_cuentas(cliente_id),
  referencia text not null unique, importe_centavos bigint not null check (importe_centavos <> 0),
  concepto text not null, created_at timestamptz not null default now()
);
create index on pulse_movimientos(cliente_id, created_at desc);
create table pulse_recargas (
  id uuid primary key default gen_random_uuid(), cliente_id uuid not null references aftr_clientes(user_id),
  importe_centavos bigint not null check (importe_centavos between 100 and 999999999999),
  client_key uuid not null, estado text not null default 'pendiente' check (estado in ('pendiente','confirmada','cancelada')),
  vence_at timestamptz not null default now()+interval '10 minutes', created_at timestamptz not null default now(),
  unique(cliente_id,client_key)
);
create table aftr_mesa_config (
  club_id text primary key references clubs(id), habilitado boolean not null default false,
  desde time not null default '21:00', hasta time not null default '06:00',
  roles_asignan text[] not null default array['admin','propietario'],
  check (roles_asignan <@ array['admin','propietario','jefe','rrpp','caja']::text[])
);
alter table mesas add column if not exists capacidad int check (capacidad between 1 and 100);
alter table mesas add column if not exists barra_id uuid references barras(id);
create table aftr_mesa_miembros (
  mesa_id uuid not null references mesas(id), cliente_id uuid not null references aftr_clientes(user_id),
  estado text not null check (estado in ('invitado','aceptado','retirado')),
  invitado_por uuid not null references aftr_clientes(user_id), created_at timestamptz not null default now(),
  primary key(mesa_id,cliente_id)
);
create table aftr_avisos (
  id uuid primary key default gen_random_uuid(), cliente_id uuid not null references aftr_clientes(user_id),
  mesa_id uuid references mesas(id), texto text not null, created_at timestamptz not null default now()
);
alter table bebidas add column if not exists foto_url text;
alter table bebidas add column if not exists foto_fuente text;
alter table tragos add column if not exists foto_url text;
alter table tragos add column if not exists foto_fuente text;
alter table tragos add column if not exists presentacion text;
alter table tragos add column if not exists categoria_aftr text not null default 'Tragos';
alter table tragos add column if not exists publicado_aftr boolean not null default false;
alter table tragos add column if not exists catalogo_clave text;
create unique index on tragos(club_id,catalogo_clave) where catalogo_clave is not null;
create table aftr_bar_pedidos (
  id uuid primary key default gen_random_uuid(), cliente_id uuid not null references aftr_clientes(user_id),
  mesa_id uuid not null references mesas(id), evento_id uuid not null references eventos(id),
  club_id text not null references clubs(id), barra_id uuid not null references barras(id),
  client_key uuid not null, metodo text not null check (metodo in ('pulse','qr')),
  total_centavos bigint not null check (total_centavos > 0), observaciones text not null default '',
  estado text not null default 'pendiente' check (estado in ('pendiente','recibido','en_preparacion','listo','entregado','cancelado')),
  venta_id uuid unique references bar_ventas(id), vence_at timestamptz not null default now()+interval '10 minutes',
  created_at timestamptz not null default now(), updated_at timestamptz not null default now(),
  unique(cliente_id,client_key)
);
create index on aftr_bar_pedidos(evento_id,barra_id,created_at);
create table aftr_bar_items (
  pedido_id uuid not null references aftr_bar_pedidos(id), trago_id uuid not null references tragos(id),
  nombre text not null, qty int not null check (qty between 1 and 50),
  precio_centavos bigint not null check (precio_centavos > 0), primary key(pedido_id,trago_id)
);
-- ml_actual representa lo disponible para POS; las reservas quedan separadas hasta resolver el banco.
create table aftr_stock_reservas (
  pedido_id uuid not null references aftr_bar_pedidos(id), lote_id uuid not null references lotes(id),
  ml numeric not null check (ml > 0), estado text not null default 'retenido' check (estado in ('retenido','consumido','liberado')),
  primary key(pedido_id,lote_id)
);
create table aftr_ventas_saldos (
  referencia text primary key, club_id text not null references clubs(id),
  importe_centavos bigint not null check (importe_centavos > 0), metodo text not null check (metodo in ('pulse','qr')),
  created_at timestamptz not null default now()
);
create table aftr_liquidaciones (
  id uuid primary key default gen_random_uuid(), club_id text not null references clubs(id),
  importe_centavos bigint not null check (importe_centavos > 0), fecha date not null,
  comprobante text not null check (length(trim(comprobante)) between 1 and 500),
  client_key uuid not null unique, registrado_por uuid not null references profiles(id),
  created_at timestamptz not null default now()
);
create table aftr_incidencias (
  id uuid primary key default gen_random_uuid(), pedido_id uuid references aftr_bar_pedidos(id),
  pago_id uuid references pago_qr(id), club_id text references clubs(id),
  detalle text not null, creado_por uuid, created_at timestamptz not null default now()
);
alter table pago_qr alter column orden_id drop not null;
alter table pago_qr add column recarga_id uuid unique references pulse_recargas(id);
alter table pago_qr add column pedido_id uuid unique references aftr_bar_pedidos(id);
alter table pago_qr add constraint pago_qr_un_destino check (num_nonnulls(orden_id,recarga_id,pedido_id)=1);

create function impl.pulse_inmutable() returns trigger language plpgsql set search_path=public as $$
begin raise exception 'El historial monetario es inmutable'; end $$;
create trigger pulse_historial before update or delete on pulse_movimientos for each row execute function impl.pulse_inmutable();
create trigger aftr_ventas_historial before update or delete on aftr_ventas_saldos for each row execute function impl.pulse_inmutable();
create trigger aftr_liquidaciones_historial before update or delete on aftr_liquidaciones for each row execute function impl.pulse_inmutable();

create function impl.pulse_mover(p_cliente uuid,p_centavos bigint,p_ref text,p_concepto text)
returns void language plpgsql security definer set search_path=public as $$
begin
  insert into pulse_cuentas(cliente_id) values(p_cliente) on conflict do nothing;
  perform 1 from pulse_cuentas where cliente_id=p_cliente for update;
  if exists(select 1 from pulse_movimientos where referencia=p_ref) then return; end if;
  update pulse_cuentas set saldo_centavos=saldo_centavos+p_centavos where cliente_id=p_cliente and saldo_centavos+p_centavos>=0;
  if not found then raise exception 'Saldo PULSE insuficiente. Podés recargar o pagar con QR.'; end if;
  insert into pulse_movimientos(cliente_id,referencia,importe_centavos,concepto) values(p_cliente,p_ref,p_centavos,p_concepto);
end $$;
create function aftr_pulse() returns jsonb language plpgsql security definer set search_path=public as $$
declare c aftr_clientes:=impl.aftr_yo(); begin
  return jsonb_build_object('saldo_centavos',coalesce((select saldo_centavos from pulse_cuentas where cliente_id=c.user_id),0),
    'movimientos',coalesce((select jsonb_agg(to_jsonb(x) order by x.created_at desc) from
      (select * from pulse_movimientos where cliente_id=c.user_id order by created_at desc limit 100)x),'[]'::jsonb),
    'recargas',coalesce((select jsonb_agg(to_jsonb(x)) from (select * from pulse_recargas where cliente_id=c.user_id and estado='pendiente' order by created_at desc limit 10)x),'[]'::jsonb));
end $$;
create function aftr_recargar_pulse(p_centavos bigint,p_client_key uuid) returns jsonb
language plpgsql security definer set search_path=public as $$
declare c aftr_clientes:=impl.aftr_yo(); r pulse_recargas; begin
  if p_centavos is null or p_centavos<100 or p_client_key is null then raise exception 'La recarga mínima es Bs 1'; end if;
  insert into pulse_recargas(cliente_id,importe_centavos,client_key) values(c.user_id,p_centavos,p_client_key)
    on conflict(cliente_id,client_key) do nothing;
  select * into r from pulse_recargas where cliente_id=c.user_id and client_key=p_client_key;
  if r.importe_centavos<>p_centavos then raise exception 'La operación ya tiene otro importe'; end if;
  return to_jsonb(r);
end $$;
create function impl.aftr_venta(p_ref text,p_club text,p_total bigint,p_metodo text) returns void
language plpgsql security definer set search_path=public as $$ begin
  perform pg_advisory_xact_lock(hashtextextended('liquidacion:'||p_club,0));
  insert into aftr_ventas_saldos values(p_ref,p_club,p_total,p_metodo,now()) on conflict do nothing;
end $$;
create function aftr_pagar_pulse(p_orden uuid) returns jsonb language plpgsql security definer set search_path=public as $$
declare c aftr_clientes:=impl.aftr_yo(); o aftr_ordenes; n int; v_club text;
begin
  -- Mismo orden de bloqueo que la confirmación bancaria: QR, orden, saldo.
  perform 1 from pago_qr where orden_id=p_orden for update;
  select * into o from aftr_ordenes where id=p_orden and cliente_id=c.user_id for update;
  if not found then raise exception 'Pedido no encontrado'; end if;
  if o.estado='confirmada' then return jsonb_build_object('estado','confirmada'); end if;
  if o.estado<>'pendiente' or o.vence_at<=now() or o.total<=0 then raise exception 'Pedido vencido o no disponible'; end if;
  if exists(select 1 from pago_qr where orden_id=o.id and (estado not in ('anulado','fallido') or qr_id is not null)) then
    raise exception 'Este pedido ya tiene un QR. Esperá su cancelación antes de cambiar de método.';
  end if;
  perform impl.pulse_mover(c.user_id,-(o.total*100)::bigint,'orden:'||o.id,'Compra '||o.tipo);
  n:=impl.aftr_emitir_orden(o.id,null);
  select club_id into v_club from eventos where id=o.evento_id;
  perform impl.aftr_venta('orden:'||o.id,v_club,(o.total*100)::bigint,'pulse');
  return jsonb_build_object('estado','confirmada','emitidas',n);
end $$;
create function impl.aftr_mesa_acceso(p_mesa uuid,p_cliente uuid) returns boolean
language sql stable security definer set search_path=public as $$
  select exists(select 1 from mesas m where m.id=p_mesa and m.estado='pagada' and
    (m.cliente_id=p_cliente or exists(select 1 from aftr_mesa_miembros i where i.mesa_id=m.id and i.cliente_id=p_cliente and i.estado='aceptado')))
$$;
create function impl.aftr_bar_staff(p_evento uuid,p_barra uuid) returns boolean
language sql stable security definer set search_path=public as $$
 select exists(select 1 from eventos e join barras b on b.id=p_barra and b.club_id=e.club_id where e.id=p_evento and
   (rol_en_club(e.club_id) in ('admin','propietario') or (rol_en_club(e.club_id)='barra' and exists
     (select 1 from bar_staff s where s.evento_id=e.id and s.barra_id=b.id and s.user_id=auth.uid()))))
$$;
create function impl.aftr_abierto(p_club text,p_evento uuid) returns boolean
language sql stable set search_path=public as $$
 select exists(select 1 from aftr_mesa_config c join eventos e on e.id=p_evento and e.club_id=c.club_id
 where c.club_id=p_club and c.habilitado
   and now() between impl.aftr_inicio(e.fecha,e.hora_inicio) and impl.aftr_fin(e.fecha,e.hora_inicio,e.hora_fin)
   and (c.desde=c.hasta or (c.desde<c.hasta and (now() at time zone 'America/La_Paz')::time between c.desde and c.hasta)
     or (c.desde>c.hasta and ((now() at time zone 'America/La_Paz')::time>=c.desde or (now() at time zone 'America/La_Paz')::time<=c.hasta))))
$$;
create function venue_configurar_pedidos(p_club text,p_habilitado boolean,p_desde time,p_hasta time,p_roles text[])
returns void language plpgsql security definer set search_path=public as $$ begin
 if coalesce(rol_en_club(p_club),'') not in ('admin','propietario') then raise exception 'Sin permiso'; end if;
 insert into aftr_mesa_config values(p_club,p_habilitado,p_desde,p_hasta,p_roles)
 on conflict(club_id) do update set habilitado=excluded.habilitado,desde=excluded.desde,hasta=excluded.hasta,roles_asignan=excluded.roles_asignan;
end $$;
create function venue_asignar_mesa_aftr(p_mesa uuid,p_cliente uuid,p_capacidad int,p_barra uuid)
returns void language plpgsql security definer set search_path=public as $$
declare m mesas; v_club text; v_rol text; begin
 select * into m from mesas where id=p_mesa for update;
 select club_id into v_club from eventos where id=m.evento_id;
 v_rol:=rol_en_club(v_club);
 if v_rol is null or not (v_rol in ('admin','propietario') or exists(select 1 from aftr_mesa_config where club_id=v_club and v_rol=any(roles_asignan))) then raise exception 'Sin permiso para asignar mesas'; end if;
 if m.estado<>'pagada' then raise exception 'La mesa debe estar pagada antes de asignarla'; end if;
 if not exists(select 1 from barras where id=p_barra and club_id=v_club and activo) then raise exception 'Barra no válida'; end if;
 if p_cliente is not null and not exists(select 1 from aftr_clientes where user_id=p_cliente) then raise exception 'Cuenta AFTR no encontrada'; end if;
 if m.cliente_id is distinct from p_cliente then update aftr_mesa_miembros set estado='retirado' where mesa_id=m.id; end if;
 if p_capacidad<1 or p_capacidad is null or p_capacidad<1+(select count(*) from aftr_mesa_miembros where mesa_id=m.id and estado in ('aceptado','invitado')) then raise exception 'Capacidad insuficiente'; end if;
 update mesas set cliente_id=p_cliente,capacidad=p_capacidad,barra_id=p_barra where id=m.id;
 if p_cliente is not null then insert into aftr_avisos(cliente_id,mesa_id,texto) values(p_cliente,m.id,'Tu mesa ya está asignada.'); end if;
end $$;
create function aftr_mesa_invitar(p_mesa uuid,p_usuario text) returns void language plpgsql security definer set search_path=public as $$
declare c aftr_clientes:=impl.aftr_yo(); m mesas; v_uid uuid; begin
 select * into m from mesas where id=p_mesa and cliente_id=c.user_id and estado='pagada' for update;
 if not found then raise exception 'Solo el titular puede invitar'; end if;
 select user_id into v_uid from aftr_clientes where usuario=lower(trim(p_usuario));
 if v_uid is null or v_uid=c.user_id then raise exception 'Cuenta AFTR no válida'; end if;
 if exists(select 1 from aftr_mesa_miembros where mesa_id=m.id and cliente_id=v_uid and estado in ('aceptado','invitado')) then return; end if;
 if m.capacidad is null or 1+(select count(*) from aftr_mesa_miembros where mesa_id=m.id and estado in ('aceptado','invitado'))>=m.capacidad then raise exception 'La mesa no tiene lugares disponibles'; end if;
 insert into aftr_mesa_miembros(mesa_id,cliente_id,estado,invitado_por) values(m.id,v_uid,'invitado',c.user_id)
 on conflict(mesa_id,cliente_id) do update set estado='invitado',invitado_por=excluded.invitado_por,created_at=now();
 insert into aftr_avisos(cliente_id,mesa_id,texto) values(v_uid,m.id,'Te invitaron a una mesa.');
end $$;
create function aftr_mesa_responder(p_mesa uuid,p_aceptar boolean) returns void language plpgsql security definer set search_path=public as $$
declare c aftr_clientes:=impl.aftr_yo(); begin
 perform 1 from mesas where id=p_mesa and estado='pagada' for update;
 if not found then raise exception 'Mesa no disponible'; end if;
 update aftr_mesa_miembros set estado=case when p_aceptar then 'aceptado' else 'retirado' end
 where mesa_id=p_mesa and cliente_id=c.user_id and estado='invitado';
 if not found then raise exception 'Invitación no disponible'; end if;
end $$;
create function aftr_mesa_retirar(p_mesa uuid,p_cliente uuid) returns void language plpgsql security definer set search_path=public as $$
declare c aftr_clientes:=impl.aftr_yo(); begin
 perform 1 from mesas where id=p_mesa and cliente_id=c.user_id for update;
 if not found then raise exception 'Solo el titular puede retirar invitados'; end if;
 update aftr_mesa_miembros set estado='retirado' where mesa_id=p_mesa and cliente_id=p_cliente;
end $$;
create function aftr_mis_mesas() returns jsonb language plpgsql security definer set search_path=public as $$
declare c aftr_clientes:=impl.aftr_yo(); begin
 return jsonb_build_object('mesas',coalesce((select jsonb_agg(jsonb_build_object(
 'id',m.id,'etiqueta',m.etiqueta,'evento_id',m.evento_id,'evento',e.nombre,'fecha',e.fecha,'club',cl.nombre,
 'titular',m.cliente_id=c.user_id,'capacidad',m.capacidad,'planta',m.planta,'barra_id',m.barra_id,
 'mi_estado',case when m.cliente_id=c.user_id then 'titular' else i.estado end,
 'pedidos_habilitados',impl.aftr_abierto(e.club_id,e.id),
 'miembros',case when m.cliente_id=c.user_id then (select coalesce(jsonb_agg(jsonb_build_object('cliente_id',a.user_id,'nombre',a.nombre,'usuario',a.usuario,'estado',mi.estado)),'[]'::jsonb)
   from aftr_mesa_miembros mi join aftr_clientes a on a.user_id=mi.cliente_id where mi.mesa_id=m.id and mi.estado<>'retirado') else '[]'::jsonb end) order by e.fecha desc)
 from mesas m join eventos e on e.id=m.evento_id join clubs cl on cl.id=e.club_id
 left join aftr_mesa_miembros i on i.mesa_id=m.id and i.cliente_id=c.user_id
 where m.estado='pagada' and (m.cliente_id=c.user_id or i.estado in ('invitado','aceptado'))),'[]'::jsonb),
 'avisos',coalesce((select jsonb_agg(to_jsonb(x)) from(select * from aftr_avisos where cliente_id=c.user_id order by created_at desc limit 30)x),'[]'::jsonb));
end $$;
create function aftr_carta_mesa(p_mesa uuid) returns jsonb language plpgsql security definer set search_path=public as $$
declare c aftr_clientes:=impl.aftr_yo(); m mesas; v_club text; begin
 if not impl.aftr_mesa_acceso(p_mesa,c.user_id) then raise exception 'No tenés acceso a esta mesa'; end if;
 select * into m from mesas where id=p_mesa;
 select club_id into v_club from eventos where id=m.evento_id;
 return jsonb_build_object('abierto',impl.aftr_abierto(v_club,m.evento_id),'productos',coalesce((select jsonb_agg(jsonb_build_object(
 'id',t.id,'revision',md5(t.xmin::text),'nombre',t.nombre,'precio_centavos',(t.precio_venta*100)::bigint,'foto_url',t.foto_url,'presentacion',t.presentacion,
 'categoria',t.categoria_aftr,'disponibles',coalesce((select min(floor(coalesce(s.ml,0)/r.ml))::int from receta_items r
 left join lateral(select sum(ml_actual) ml from lotes where bebida_id=r.bebida_id)s on true where r.trago_id=t.id),0)) order by t.orden,t.nombre)
 from tragos t where t.club_id=v_club and t.publicado_aftr and t.activo and t.precio_venta>0
 and (t.barra_id is null or t.barra_id=m.barra_id) and exists(select 1 from receta_items where trago_id=t.id)),'[]'::jsonb));
end $$;

-- Serialización por boliche, compartida por el POS y las reservas AFTR.
create function impl.aftr_stock_lock() returns trigger language plpgsql security definer set search_path=public as $$ begin
 perform pg_advisory_xact_lock(hashtextextended('stock:'||new.club_id,0)); return new;
end $$;
create trigger aftr_pos_lock before insert on bar_ventas for each row execute function impl.aftr_stock_lock();
create function impl.aftr_lote_guard() returns trigger language plpgsql security definer set search_path=public as $$ begin
 if new.ml_actual<0 then raise exception 'no hay stock suficiente'; end if;
 if current_setting('venue.reserva_interna',true) is distinct from 'on' and new.ml_actual>old.ml_actual
   and exists(select 1 from aftr_stock_reservas where lote_id=old.id and estado='retenido') then
   raise exception 'Este lote tiene un pago pendiente. Resolvé el QR antes del conteo o ajuste.';
 end if;
 return new;
end $$;
create trigger aftr_lote_guard before update on lotes for each row execute function impl.aftr_lote_guard();

create function impl.aftr_bar_emitir(p_pedido uuid) returns void language plpgsql security definer set search_path=public as $$
declare p aftr_bar_pedidos; v uuid; r record; begin
 select * into p from aftr_bar_pedidos where id=p_pedido for update;
 if p.venta_id is not null then return; end if;
 if p.estado<>'pendiente' then raise exception 'Pedido no emitible'; end if;
 perform pg_advisory_xact_lock(hashtextextended('stock:'||p.club_id,0));
 if not exists(select 1 from aftr_stock_reservas where pedido_id=p.id and estado='retenido') then raise exception 'Reserva de stock no disponible'; end if;
 insert into bar_ventas(club_id,evento_id,barra_id,total,estado,client_key) values(p.club_id,p.evento_id,p.barra_id,p.total_centavos::numeric/100,p.metodo,'aftr:'||p.id) returning id into v;
 insert into bar_venta_items(venta_id,trago_id,qty,precio_unit) select v,trago_id,qty,precio_centavos::numeric/100 from aftr_bar_items where pedido_id=p.id;
 for r in select s.*,l.bebida_id,l.costo_unitario,l.volumen_ml from aftr_stock_reservas s join lotes l on l.id=s.lote_id where s.pedido_id=p.id and s.estado='retenido' loop
 insert into stock_mov(club_id,bebida_id,lote_id,tipo,ml_delta,costo,motivo,evento_id,barra_id,creado_por)
 values(p.club_id,r.bebida_id,r.lote_id,'salida',-r.ml,r.ml*coalesce(r.costo_unitario,0)/nullif(r.volumen_ml,0),'venta:'||v,p.evento_id,p.barra_id,null);
 end loop;
 update aftr_stock_reservas set estado='consumido' where pedido_id=p.id;
 update aftr_bar_pedidos set estado='recibido',venta_id=v,updated_at=now() where id=p.id;
 perform impl.aftr_venta('barra:'||p.id,p.club_id,p.total_centavos,p.metodo);
 insert into aftr_avisos(cliente_id,mesa_id,texto) values(p.cliente_id,p.mesa_id,'Tu pedido fue recibido por la barra.');
end $$;
create function aftr_pedir_mesa(p_mesa uuid,p_items jsonb,p_metodo text,p_client_key uuid,p_observaciones text default '')
returns jsonb language plpgsql security definer set search_path=public as $$
declare c aftr_clientes:=impl.aftr_yo(); m mesas; p aftr_bar_pedidos; v_club text; v_total bigint:=0;
 it record; t tragos; r record; l lotes; v_necesito numeric; v_toma numeric;
begin
 if p_client_key is null or p_metodo is null or p_metodo not in ('pulse','qr') then raise exception 'Método de pago inválido'; end if;
 perform pg_advisory_xact_lock(hashtextextended(c.user_id::text||p_client_key::text,0));
 select * into p from aftr_bar_pedidos where cliente_id=c.user_id and client_key=p_client_key;
 if found then return to_jsonb(p); end if;
 select * into m from mesas where id=p_mesa for update;
 if not impl.aftr_mesa_acceso(p_mesa,c.user_id) then raise exception 'No tenés acceso a esta mesa'; end if;
 select club_id into v_club from eventos where id=m.evento_id;
 perform pg_advisory_xact_lock(hashtextextended('stock:'||v_club,0));
 if not impl.aftr_abierto(v_club,m.evento_id) or m.capacidad is null or not exists(select 1 from barras where id=m.barra_id and club_id=v_club and activo) then raise exception 'Los pedidos no están disponibles ahora'; end if;
 if jsonb_typeof(p_items) is distinct from 'array' or jsonb_array_length(p_items) not between 1 and 30 or length(coalesce(p_observaciones,''))>300 then raise exception 'Pedido inválido'; end if;
 insert into aftr_bar_pedidos(cliente_id,mesa_id,evento_id,club_id,barra_id,client_key,metodo,total_centavos,observaciones)
 values(c.user_id,m.id,m.evento_id,v_club,m.barra_id,p_client_key,p_metodo,1,coalesce(p_observaciones,'')) returning * into p;
 for it in select (x->>'trago_id')::uuid id,(x->>'qty')::int qty,x->>'revision' revision from jsonb_array_elements(p_items)x loop
 if it.qty is null or it.qty not between 1 and 50 then raise exception 'Cantidad inválida'; end if;
 select * into t from tragos where id=it.id and club_id=v_club and activo and publicado_aftr and precio_venta>0 and (barra_id is null or barra_id=m.barra_id) for share;
 if not found then raise exception 'Producto no disponible'; end if;
 if it.revision is distinct from (select md5(x.xmin::text) from tragos x where x.id=t.id) then raise exception 'La carta cambió. Actualizala y revisá el precio antes de comprar.'; end if;
 if t.precio_venta*100<>trunc(t.precio_venta*100) or not exists(select 1 from receta_items where trago_id=t.id) then raise exception 'Producto no disponible'; end if;
 if exists(select 1 from receta_items ri join bebidas b on b.id=ri.bebida_id where ri.trago_id=t.id and (b.club_id<>v_club or not b.activo or b.volumen_ml<=0 or ri.ml<=0)) then raise exception 'Receta inválida'; end if;
 insert into aftr_bar_items values(p.id,t.id,t.nombre,it.qty,(t.precio_venta*100)::bigint);
 v_total:=v_total+(t.precio_venta*100)::bigint*it.qty;
 end loop;
 for r in select ri.bebida_id,sum(ri.ml*i.qty) ml from aftr_bar_items i join receta_items ri on ri.trago_id=i.trago_id where i.pedido_id=p.id group by ri.bebida_id order by ri.bebida_id loop
 v_necesito:=r.ml;
 for l in select * from lotes where bebida_id=r.bebida_id and club_id=v_club and ml_actual>0 order by recibido_at,id for update loop
 exit when v_necesito<=0; v_toma:=least(v_necesito,l.ml_actual);
 update lotes set ml_actual=ml_actual-v_toma where id=l.id;
 insert into aftr_stock_reservas values(p.id,l.id,v_toma,'retenido');
 v_necesito:=v_necesito-v_toma;
 end loop;
 if v_necesito>0 then raise exception 'no hay stock suficiente para este pedido'; end if;
 end loop;
 update aftr_bar_pedidos set total_centavos=v_total where id=p.id;
 if p_metodo='pulse' then
 perform impl.pulse_mover(c.user_id,-v_total,'barra:'||p.id,'Pedido de bebidas');
 perform impl.aftr_bar_emitir(p.id);
 end if;
 return (select to_jsonb(x) from aftr_bar_pedidos x where id=p.id);
end $$;
create function impl.aftr_bar_liberar(p_pedido uuid) returns void language plpgsql security definer set search_path=public as $$
declare p aftr_bar_pedidos; r record; begin
 select * into p from aftr_bar_pedidos where id=p_pedido for update;
 if p.estado<>'pendiente' then return; end if;
 perform pg_advisory_xact_lock(hashtextextended('stock:'||p.club_id,0));
 perform set_config('venue.reserva_interna','on',true);
 for r in select * from aftr_stock_reservas where pedido_id=p.id and estado='retenido' order by lote_id loop
 update lotes set ml_actual=ml_actual+r.ml where id=r.lote_id;
 end loop;
 perform set_config('venue.reserva_interna','off',true);
 update aftr_stock_reservas set estado='liberado' where pedido_id=p.id and estado='retenido';
 update aftr_bar_pedidos set estado='cancelado',updated_at=now() where id=p.id;
end $$;
create function aftr_mis_pedidos_mesa(p_mesa uuid) returns jsonb language plpgsql security definer set search_path=public as $$
declare c aftr_clientes:=impl.aftr_yo(); begin
 return coalesce((select jsonb_agg(to_jsonb(p)||jsonb_build_object('items',(select jsonb_agg(to_jsonb(i)) from aftr_bar_items i where pedido_id=p.id)) order by p.created_at desc)
 from aftr_bar_pedidos p where p.mesa_id=p_mesa and p.cliente_id=c.user_id),'[]'::jsonb);
end $$;
create function venue_pedidos_mesa(p_evento uuid) returns jsonb language plpgsql security definer set search_path=public as $$ begin
 return coalesce((select jsonb_agg(to_jsonb(p)||jsonb_build_object('mesa',m.etiqueta,'cliente',c.nombre,
 'items',(select jsonb_agg(to_jsonb(i)) from aftr_bar_items i where pedido_id=p.id)) order by p.created_at)
 from aftr_bar_pedidos p join mesas m on m.id=p.mesa_id join aftr_clientes c on c.user_id=p.cliente_id
 where p.evento_id=p_evento and p.estado not in ('pendiente','cancelado') and impl.aftr_bar_staff(p.evento_id,p.barra_id)),'[]'::jsonb);
end $$;
create function venue_avanzar_pedido(p_pedido uuid,p_estado text) returns void language plpgsql security definer set search_path=public as $$
declare p aftr_bar_pedidos; begin
 select * into p from aftr_bar_pedidos where id=p_pedido for update;
 if not found or not impl.aftr_bar_staff(p.evento_id,p.barra_id) then raise exception 'Sin permiso'; end if;
 if p.estado=p_estado then return; end if;
 if p_estado is null or p_estado is distinct from (case p.estado when 'recibido' then 'en_preparacion' when 'en_preparacion' then 'listo' when 'listo' then 'entregado' end) then raise exception 'Transición de pedido no válida'; end if;
 update aftr_bar_pedidos set estado=p_estado,updated_at=now() where id=p.id;
 insert into aftr_avisos(cliente_id,mesa_id,texto) values(p.cliente_id,p.mesa_id,'Tu pedido: '||replace(p_estado,'_',' '));
end $$;
create function venue_incidencia_pedido(p_pedido uuid,p_detalle text) returns void language plpgsql security definer set search_path=public as $$
declare p aftr_bar_pedidos; begin
 select * into p from aftr_bar_pedidos where id=p_pedido;
 if not found or not impl.aftr_bar_staff(p.evento_id,p.barra_id) or length(trim(p_detalle)) not between 1 and 1000 then raise exception 'Incidencia no válida'; end if;
 insert into aftr_incidencias(pedido_id,club_id,detalle,creado_por) values(p.id,p.club_id,p_detalle,auth.uid());
end $$;
create function impl.aftr_no_anular_pagado() returns trigger language plpgsql set search_path=public as $$ begin
 if old.client_key like 'aftr:%' and (new.estado is distinct from old.estado or new.total is distinct from old.total) then raise exception 'Venta AFTR pagada. Registrá una incidencia para administración.'; end if; return new;
end $$;
create trigger aftr_venta_pagada before update on bar_ventas for each row execute function impl.aftr_no_anular_pagado();
create function venue_liquidaciones(p_club text) returns jsonb language plpgsql security definer set search_path=public as $$ begin
 if coalesce(rol_en_club(p_club),'') not in ('admin','propietario') then raise exception 'Sin permiso'; end if;
 return jsonb_build_object('puede_liquidar',es_platform_admin(),
 'ventas_centavos',coalesce((select sum(importe_centavos) from aftr_ventas_saldos where club_id=p_club),0),
 'liquidado_centavos',coalesce((select sum(importe_centavos) from aftr_liquidaciones where club_id=p_club),0),
 'ventas',coalesce((select jsonb_agg(to_jsonb(x)) from(select * from aftr_ventas_saldos where club_id=p_club order by created_at desc limit 100)x),'[]'::jsonb),
 'liquidaciones',coalesce((select jsonb_agg(to_jsonb(x)) from(select * from aftr_liquidaciones where club_id=p_club order by created_at desc limit 100)x),'[]'::jsonb));
end $$;
create function venue_registrar_liquidacion(p_club text,p_centavos bigint,p_fecha date,p_comprobante text,p_client_key uuid)
returns uuid language plpgsql security definer set search_path=public as $$
declare v uuid; v_pendiente bigint; begin
 if not es_platform_admin() then raise exception 'Solo administración de plataforma'; end if;
 perform pg_advisory_xact_lock(hashtextextended('liquidacion:'||p_club,0));
 select id into v from aftr_liquidaciones where client_key=p_client_key;
 if found then return v; end if;
 select coalesce((select sum(importe_centavos) from aftr_ventas_saldos where club_id=p_club),0)-coalesce((select sum(importe_centavos) from aftr_liquidaciones where club_id=p_club),0) into v_pendiente;
 if p_centavos is null or p_centavos<=0 or p_centavos>v_pendiente then raise exception 'Importe superior al pendiente de liquidar'; end if;
 insert into aftr_liquidaciones(club_id,importe_centavos,fecha,comprobante,client_key,registrado_por) values(p_club,p_centavos,p_fecha,p_comprobante,p_client_key,auth.uid()) returning id into v; return v;
end $$;

alter table pago_qr add column limite_at timestamptz;
update pago_qr q set limite_at=o.vence_at from aftr_ordenes o where o.id=q.orden_id;
create function baneco_reservar_destino(p_tipo text,p_id uuid,p_cliente uuid,p_ambiente text) returns jsonb
language plpgsql security definer set search_path=public as $$
declare q pago_qr; v_total numeric; v_vence timestamptz; v_estado text; begin
 if p_ambiente is null or p_ambiente not in ('certificacion','produccion') or p_tipo is null or p_tipo not in ('orden','recarga','pedido') then raise exception 'Destino no válido'; end if;
 select * into q from pago_qr where (p_tipo='orden' and orden_id=p_id) or (p_tipo='recarga' and recarga_id=p_id) or (p_tipo='pedido' and pedido_id=p_id) for update;
 if p_tipo='orden' then
 select total,vence_at,estado into v_total,v_vence,v_estado from aftr_ordenes where id=p_id and cliente_id=p_cliente for update;
 elsif p_tipo='recarga' then
 select importe_centavos::numeric/100,vence_at,estado into v_total,v_vence,v_estado from pulse_recargas where id=p_id and cliente_id=p_cliente for update;
 else
 select total_centavos::numeric/100,vence_at,estado into v_total,v_vence,v_estado from aftr_bar_pedidos where id=p_id and cliente_id=p_cliente and metodo='qr' for update;
 end if;
 if v_total is null then raise exception 'Pedido no encontrado'; end if;
 if q.id is not null and (q.estado<>'fallido' or q.qr_id is not null) then
 if q.ambiente<>p_ambiente then raise exception 'Ambiente diferente'; end if;
 return jsonb_build_object('reservado',false,'pago',to_jsonb(q)); end if;
 if v_estado<>'pendiente' or v_vence<=now() or v_total<=0 then raise exception 'Pedido no disponible'; end if;
 if q.id is not null then
 if q.ambiente<>p_ambiente then raise exception 'Ambiente diferente'; end if;
 update pago_qr set estado='generando',generacion_id=gen_random_uuid(),generacion_iniciada_at=now(),nota=null where id=q.id returning * into q;
 else
 insert into pago_qr(orden_id,recarga_id,pedido_id,ambiente,transaction_id,monto,moneda,vence,limite_at,estado,generacion_id,generacion_iniciada_at)
 values(case when p_tipo='orden' then p_id end,case when p_tipo='recarga' then p_id end,case when p_tipo='pedido' then p_id end,p_ambiente,
 left(replace(p_id::text,'-',''),30),v_total,'BOB',(v_vence at time zone 'America/La_Paz')::date,v_vence,'generando',gen_random_uuid(),now()) returning * into q;
 end if;
 return jsonb_build_object('reservado',true,'pago',to_jsonb(q));
end $$;
create or replace function baneco_reservar_qr(p_orden uuid,p_cliente uuid,p_ambiente text) returns jsonb
language sql security definer set search_path=public as $$ select baneco_reservar_destino('orden',p_orden,p_cliente,p_ambiente) $$;

alter function aftr_pago_confirmado(text,jsonb) rename to aftr_pago_confirmado_entradas;
create function aftr_pago_confirmado(p_qr text,p_pago jsonb) returns jsonb language plpgsql security definer set search_path=public as $$
declare q pago_qr; r pulse_recargas; p aftr_bar_pedidos; o aftr_ordenes; v numeric; resultado jsonb; v_club text;
begin
 select * into q from pago_qr where qr_id=p_qr for update;
 if not found then raise exception 'QR desconocido'; end if;
 if q.estado='pagado' then return jsonb_build_object('estado','pagado','nuevo',false); end if;
 begin v:=(p_pago->>'amount')::numeric; exception when others then v:=null; end;
 if p_pago->>'qrId' is distinct from q.qr_id or nullif(trim(p_pago->>'transactionId'),'') is null or v is distinct from q.monto or upper(coalesce(p_pago->>'currency',''))<>q.moneda then
 update pago_qr set estado='revisar',pago=p_pago,nota='DATOS_BANCARIOS_NO_COINCIDEN',ultimo_chequeo=now() where id=q.id;
 return jsonb_build_object('estado','revisar','nuevo',false); end if;
 -- Certificación nunca acredita dinero ni emite productos en la base real.
 if q.ambiente<>'produccion' then
 update pago_qr set estado='revisar',pago=p_pago,banco_tx=p_pago->>'transactionId',pagado_at=now(),nota='CERTIFICACION_SIN_EFECTO_MONETARIO' where id=q.id;
 return jsonb_build_object('estado','revisar','nuevo',false); end if;
 if q.orden_id is not null then
 resultado:=aftr_pago_confirmado_entradas(p_qr,p_pago);
 select * into o from aftr_ordenes where id=q.orden_id;
 if o.estado='confirmada' then
 select club_id into v_club from eventos where id=o.evento_id;
 perform impl.aftr_venta('orden:'||o.id,v_club,(o.total*100)::bigint,'qr');
 end if;
 return resultado;
 end if;
 update pago_qr set estado='pagado',pago=p_pago,banco_tx=p_pago->>'transactionId',pagado_at=now(),ultimo_chequeo=now(),nota=null where id=q.id;
 begin
 if q.recarga_id is not null then
 select * into r from pulse_recargas where id=q.recarga_id for update;
 perform impl.pulse_mover(r.cliente_id,r.importe_centavos,'recarga:'||r.id,'Recarga PULSE por QR');
 update pulse_recargas set estado='confirmada' where id=r.id;
 else
 select * into p from aftr_bar_pedidos where id=q.pedido_id for update;
 perform impl.aftr_bar_emitir(p.id);
 end if;
 exception when others then
 update pago_qr set estado='revisar',nota='PAGADO_SIN_EMISION' where id=q.id;
 insert into aftr_incidencias(pago_id,pedido_id,club_id,detalle) values(q.id,q.pedido_id,p.club_id,'Pago confirmado sin completar la venta. Revisión requerida.');
 return jsonb_build_object('estado','revisar','nuevo',false);
 end;
 return jsonb_build_object('estado','pagado','nuevo',true);
end $$;
create function baneco_qr_anulado(p_qr text) returns void language plpgsql security definer set search_path=public as $$
declare q pago_qr; begin
 select * into q from pago_qr where qr_id=p_qr for update;
 if not found or q.estado in ('pagado','revisar') or q.banco_tx is not null then return; end if;
 update pago_qr set estado='anulado',ultimo_chequeo=now() where id=q.id;
 if q.pedido_id is not null then perform impl.aftr_bar_liberar(q.pedido_id); end if;
 if q.recarga_id is not null then update pulse_recargas set estado='cancelada' where id=q.recarga_id and estado='pendiente'; end if;
end $$;
create function baneco_liberar_sin_qr() returns int language plpgsql security definer set search_path=public as $$
declare p aftr_bar_pedidos; n int:=0; begin
 -- La fila se bloquea antes de comprobar que no se inició ninguna generación.
 for p in select * from aftr_bar_pedidos where estado='pendiente' and vence_at<=now() order by id for update skip locked loop
 if not exists(select 1 from pago_qr where pedido_id=p.id and (estado<>'fallido' or qr_id is not null)) then
 perform impl.aftr_bar_liberar(p.id); n:=n+1;
 end if; end loop; return n;
end $$;
create function aftr_cancelar_cobro(p_tipo text,p_id uuid) returns void language plpgsql security definer set search_path=public as $$
declare c aftr_clientes:=impl.aftr_yo(); q pago_qr; begin
 select * into q from pago_qr where (p_tipo='orden' and orden_id=p_id) or (p_tipo='recarga' and recarga_id=p_id) or (p_tipo='pedido' and pedido_id=p_id) for update;
 if p_tipo='orden' then
 perform 1 from aftr_ordenes where id=p_id and cliente_id=c.user_id for update;
 elsif p_tipo='recarga' then
 perform 1 from pulse_recargas where id=p_id and cliente_id=c.user_id for update;
 elsif p_tipo='pedido' then
 perform 1 from aftr_bar_pedidos where id=p_id and cliente_id=c.user_id for update;
 else raise exception 'Destino no válido'; end if;
 if not found then raise exception 'Pedido no encontrado'; end if;
 if q.banco_tx is not null or q.estado in ('pagado','revisar','generando') then raise exception 'El pago necesita resolución bancaria antes de cancelarse'; end if;
 if q.qr_id is not null and q.estado<>'anulado' then
 update pago_qr set limite_at=now()-interval '1 second' where id=q.id;
 return;
 end if;
 if p_tipo='pedido' then perform impl.aftr_bar_liberar(p_id);
 elsif p_tipo='recarga' then update pulse_recargas set estado='cancelada' where id=p_id and estado='pendiente';
 else update aftr_ordenes set estado='cancelada' where id=p_id and estado='pendiente'; end if;
end $$;

create function venue_catalogo_aftr(p_club text) returns jsonb language plpgsql security definer set search_path=public as $$ begin
 if coalesce(rol_en_club(p_club),'') not in ('admin','propietario') then raise exception 'Sin permiso'; end if;
 return jsonb_build_object('config',coalesce((select to_jsonb(c) from aftr_mesa_config c where club_id=p_club),jsonb_build_object('habilitado',false,'desde','21:00','hasta','06:00','roles_asignan',array['admin','propietario'])),
 'barras',coalesce((select jsonb_agg(jsonb_build_object('id',id,'nombre',nombre)) from barras where club_id=p_club and activo),'[]'::jsonb),
 'productos',coalesce((select jsonb_agg(to_jsonb(t)||jsonb_build_object('receta',coalesce((select jsonb_agg(jsonb_build_object('bebida_id',ri.bebida_id,'ml',ri.ml)) from receta_items ri where ri.trago_id=t.id),'[]'::jsonb)) order by t.nombre) from tragos t where t.club_id=p_club),'[]'::jsonb),
 'bebidas',coalesce((select jsonb_agg(jsonb_build_object('id',id,'nombre',nombre,'volumen_ml',volumen_ml,'foto_url',foto_url,'foto_fuente',foto_fuente)) from bebidas where club_id=p_club),'[]'::jsonb));
end $$;
create function venue_guardar_producto_aftr(p_trago uuid,p_nombre text,p_centavos bigint,p_foto text,p_fuente text,p_presentacion text,p_categoria text,p_publicado boolean,p_receta jsonb)
returns void language plpgsql security definer set search_path=public as $$
declare t tragos; begin
 select * into t from tragos where id=p_trago for update;
 if not found or coalesce(rol_en_club(t.club_id),'') not in ('admin','propietario') then raise exception 'Sin permiso'; end if;
 if length(trim(p_nombre)) not between 1 and 120 or p_centavos is null or p_centavos<0 or p_foto is not null and p_foto !~ '^https://' then raise exception 'Datos de producto inválidos'; end if;
 if jsonb_typeof(p_receta) is distinct from 'array' then raise exception 'Receta inválida'; end if;
 if exists(select 1 from jsonb_array_elements(p_receta)x left join bebidas b on b.id=(x->>'bebida_id')::uuid where b.club_id is distinct from t.club_id or coalesce((x->>'ml')::numeric,0)<=0) then raise exception 'La receta debe usar bebidas del boliche y cantidades positivas'; end if;
 if p_publicado and (p_centavos<=0 or jsonb_array_length(p_receta)=0 or nullif(trim(p_presentacion),'') is null or nullif(trim(p_foto),'') is null) then raise exception 'Completá precio, foto, presentación y receta antes de publicar'; end if;
 delete from receta_items where trago_id=t.id;
 insert into receta_items(trago_id,bebida_id,ml) select t.id,(x->>'bebida_id')::uuid,(x->>'ml')::numeric from jsonb_array_elements(p_receta)x;
 update tragos set nombre=trim(p_nombre),precio_venta=p_centavos::numeric/100,foto_url=nullif(p_foto,''),foto_fuente=p_fuente,
 presentacion=p_presentacion,categoria_aftr=coalesce(nullif(p_categoria,''),'Tragos'),publicado_aftr=p_publicado,
 activo=case when p_publicado then true else activo end where id=t.id;
end $$;
create function impl.aftr_publicacion_valida() returns trigger language plpgsql set search_path=public as $$ begin
 if new.publicado_aftr and (not new.activo or new.precio_venta<=0 or new.precio_venta*100<>trunc(new.precio_venta*100) or nullif(trim(new.foto_url),'') is null or nullif(trim(new.presentacion),'') is null or new.foto_url !~ '^https://' or exists(select 1 from receta_items r join bebidas b on b.id=r.bebida_id where r.trago_id=new.id and (b.club_id<>new.club_id or not b.activo or b.volumen_ml<=0 or r.ml<=0)) or not exists(select 1 from receta_items where trago_id=new.id)) then raise exception 'Producto AFTR incompleto. Quitá la publicación antes de editarlo.'; end if; return new;
end $$;
create trigger aftr_publicacion before insert or update on tragos for each row execute function impl.aftr_publicacion_valida();

-- Acceso explícito: ningún cliente escribe saldo, movimientos, ventas o pagos.
do $$ declare t text; begin
 foreach t in array array['pulse_cuentas','pulse_movimientos','pulse_recargas','aftr_mesa_config','aftr_mesa_miembros','aftr_avisos','aftr_bar_pedidos','aftr_bar_items','aftr_stock_reservas','aftr_ventas_saldos','aftr_liquidaciones','aftr_incidencias'] loop
 execute format('alter table public.%I enable row level security',t);
 execute format('revoke all on public.%I from public,anon,authenticated',t);
 execute format('grant select on public.%I to authenticated',t);
 execute format('grant all on public.%I to service_role',t);
 end loop;
end $$;
create policy pulse_cuenta_propia on pulse_cuentas for select to authenticated using(cliente_id=(select auth.uid()));
create policy pulse_movimiento_propio on pulse_movimientos for select to authenticated using(cliente_id=(select auth.uid()));
create policy pulse_recarga_propia on pulse_recargas for select to authenticated using(cliente_id=(select auth.uid()));
create policy aftr_config_staff on aftr_mesa_config for select to authenticated using(rol_en_club(club_id) in ('admin','propietario'));
create policy aftr_miembro_propio on aftr_mesa_miembros for select to authenticated using(cliente_id=(select auth.uid()) or exists(select 1 from mesas where id=mesa_id and cliente_id=(select auth.uid())));
create policy aftr_aviso_propio on aftr_avisos for select to authenticated using(cliente_id=(select auth.uid()));
create policy aftr_pedido_propio on aftr_bar_pedidos for select to authenticated using(cliente_id=(select auth.uid()) or impl.aftr_bar_staff(evento_id,barra_id));
create policy aftr_item_propio on aftr_bar_items for select to authenticated using(exists(select 1 from aftr_bar_pedidos p where p.id=pedido_id));
create policy aftr_venta_staff on aftr_ventas_saldos for select to authenticated using(rol_en_club(club_id) in ('admin','propietario'));
create policy aftr_liquidacion_staff on aftr_liquidaciones for select to authenticated using(rol_en_club(club_id) in ('admin','propietario'));
create policy aftr_incidencia_staff on aftr_incidencias for select to authenticated using(rol_en_club(club_id) in ('admin','propietario'));
-- Permisos de funciones nuevos por nombre, sin tocar el resto de las RPC existentes.
do $$ declare f record; begin
 for f in select p.oid::regprocedure firma,p.proname,n.nspname from pg_proc p join pg_namespace n on n.oid=p.pronamespace
 where (n.nspname='public' and p.proname in ('aftr_pulse','aftr_recargar_pulse','aftr_pagar_pulse','venue_configurar_pedidos','venue_asignar_mesa_aftr','aftr_mesa_invitar','aftr_mesa_responder','aftr_mesa_retirar','aftr_mis_mesas','aftr_carta_mesa','aftr_pedir_mesa','aftr_mis_pedidos_mesa','venue_pedidos_mesa','venue_avanzar_pedido','venue_incidencia_pedido','venue_liquidaciones','venue_registrar_liquidacion','venue_catalogo_aftr','venue_guardar_producto_aftr','aftr_cancelar_cobro','baneco_reservar_destino','baneco_qr_anulado','baneco_liberar_sin_qr','aftr_pago_confirmado','aftr_pago_confirmado_entradas'))
 or (n.nspname='impl' and p.proname in ('pulse_inmutable','pulse_mover','aftr_venta','aftr_mesa_acceso','aftr_bar_staff','aftr_abierto','aftr_stock_lock','aftr_lote_guard','aftr_bar_emitir','aftr_bar_liberar','aftr_no_anular_pagado','aftr_publicacion_valida')) loop
 execute format('revoke all on function %s from public,anon,authenticated',f.firma);
 execute format('grant execute on function %s to service_role',f.firma);
 if f.nspname='public' and f.proname not like 'baneco_%' and f.proname not in ('aftr_pago_confirmado','aftr_pago_confirmado_entradas') then execute format('grant execute on function %s to authenticated',f.firma); end if;
 end loop;
end $$;
-- Helpers usados por RLS no son mutaciones y verifican auth.uid() internamente.
grant execute on function impl.aftr_bar_staff(uuid,uuid) to authenticated;
do $$ declare t text; begin
 if exists(select 1 from pg_publication where pubname='supabase_realtime') then
 foreach t in array array['pulse_cuentas','pulse_movimientos','pulse_recargas','aftr_mesa_miembros','aftr_avisos','aftr_bar_pedidos'] loop
 if not exists(select 1 from pg_publication_tables where pubname='supabase_realtime' and schemaname='public' and tablename=t) then execute format('alter publication supabase_realtime add table public.%I',t); end if;
 end loop; end if;
end $$;
create function venue_buscar_cliente_aftr(p_club text,p_q text) returns jsonb language plpgsql security definer set search_path=public as $$
declare v_rol text:=rol_en_club(p_club); begin
 if v_rol is null or not (v_rol in ('admin','propietario') or exists(select 1 from aftr_mesa_config where club_id=p_club and v_rol=any(roles_asignan))) then raise exception 'Sin permiso'; end if;
 if length(trim(p_q))<3 then return '[]'::jsonb; end if;
 return coalesce((select jsonb_agg(to_jsonb(x)) from(select user_id,usuario,nombre from aftr_clientes
 where usuario like lower(trim(both '@ ' from p_q))||'%' order by usuario limit 10)x),'[]'::jsonb);
end $$;
create function venue_mesas_aftr(p_evento uuid) returns jsonb language plpgsql security definer set search_path=public as $$
declare v_club text; v_rol text; begin
 select club_id into v_club from eventos where id=p_evento; v_rol:=rol_en_club(v_club);
 if v_rol is null or not (v_rol in ('admin','propietario') or exists(select 1 from aftr_mesa_config where club_id=v_club and v_rol=any(roles_asignan))) then raise exception 'Sin permiso'; end if;
 return jsonb_build_object('mesas',coalesce((select jsonb_agg(jsonb_build_object('id',m.id,'etiqueta',m.etiqueta,'capacidad',m.capacidad,'barra_id',m.barra_id,'cliente_id',m.cliente_id,'usuario',c.usuario,'nombre',c.nombre) order by m.etiqueta)
 from mesas m left join aftr_clientes c on c.user_id=m.cliente_id where m.evento_id=p_evento and m.estado='pagada'),'[]'::jsonb),
 'barras',coalesce((select jsonb_agg(jsonb_build_object('id',id,'nombre',nombre)) from barras where club_id=v_club and activo),'[]'::jsonb));
end $$;
-- Un reintento manual conserva la misma contabilidad que el callback bancario.
alter function aftr_confirmar_orden(uuid) rename to aftr_confirmar_orden_banco;
create function aftr_confirmar_orden(p_orden uuid) returns jsonb language plpgsql security definer set search_path=public as $$
declare q pago_qr; resultado jsonb; o aftr_ordenes; v_club text; begin
 select * into q from pago_qr where orden_id=p_orden for update;
 if q.ambiente is distinct from 'produccion' then raise exception 'La certificación no emite productos reales'; end if;
 resultado:=aftr_confirmar_orden_banco(p_orden);
 select * into o from aftr_ordenes where id=p_orden;
 select club_id into v_club from eventos where id=o.evento_id;
 perform impl.aftr_venta('orden:'||o.id,v_club,(o.total*100)::bigint,'qr');
 return resultado;
end $$;
-- Un ítem del POS tampoco puede consumir una receta de otro boliche.
create function impl.aftr_pos_item_guard() returns trigger language plpgsql set search_path=public as $$ begin
 if not exists(select 1 from bar_ventas v join tragos t on t.id=new.trago_id and t.club_id=v.club_id where v.id=new.venta_id) or new.qty<=0 then raise exception 'Producto no válido para este boliche'; end if;
 return new;
end $$;
create trigger aftr_pos_item_guard before insert on bar_venta_items for each row execute function impl.aftr_pos_item_guard();
revoke all on function venue_buscar_cliente_aftr(text,text),venue_mesas_aftr(uuid),aftr_confirmar_orden(uuid),aftr_confirmar_orden_banco(uuid),impl.aftr_pos_item_guard() from public,anon,authenticated;
grant execute on function venue_buscar_cliente_aftr(text,text),venue_mesas_aftr(uuid),aftr_confirmar_orden(uuid) to authenticated,service_role;
grant execute on function aftr_confirmar_orden_banco(uuid) to service_role;
create function impl.aftr_ajuste_guard() returns trigger language plpgsql set search_path=public as $$ begin
 if new.tipo in ('ajuste','baja') and exists(select 1 from aftr_stock_reservas where lote_id=new.lote_id and estado='retenido') then raise exception 'El lote tiene un pago QR pendiente. Resolvelo antes del ajuste físico.'; end if;
 return new;
end $$;
create trigger aftr_ajuste_reserva before insert on stock_mov for each row execute function impl.aftr_ajuste_guard();
revoke all on function impl.aftr_ajuste_guard() from public,anon,authenticated;

create table pulse_correcciones (
 id uuid primary key default gen_random_uuid(),cliente_id uuid not null references aftr_clientes(user_id),
 importe_centavos bigint not null check(importe_centavos<>0),motivo text not null check(length(trim(motivo)) between 10 and 1000),
 client_key uuid not null unique,registrado_por uuid not null references profiles(id),created_at timestamptz not null default now()
);
alter table pulse_correcciones enable row level security;
revoke all on pulse_correcciones from public,anon,authenticated;
grant all on pulse_correcciones to service_role;
create trigger pulse_correccion_inmutable before update or delete on pulse_correcciones for each row execute function impl.pulse_inmutable();
create function venue_corregir_pulse(p_cliente uuid,p_centavos bigint,p_motivo text,p_client_key uuid) returns uuid
language plpgsql security definer set search_path=public as $$ declare v uuid; begin
 if not es_platform_admin() then raise exception 'Solo administración de plataforma'; end if;
 perform pg_advisory_xact_lock(hashtextextended('correccion:'||p_client_key::text,0));
 select id into v from pulse_correcciones where client_key=p_client_key; if found then return v; end if;
 insert into pulse_correcciones(cliente_id,importe_centavos,motivo,client_key,registrado_por)
 values(p_cliente,p_centavos,p_motivo,p_client_key,auth.uid()) returning id into v;
 perform impl.pulse_mover(p_cliente,p_centavos,'correccion:'||v,'Corrección autorizada: '||p_motivo); return v;
end $$;
revoke all on function venue_corregir_pulse(uuid,bigint,text,uuid) from public,anon;
grant execute on function venue_corregir_pulse(uuid,bigint,text,uuid) to authenticated,service_role;

create table aftr_catalogo_base (
 clave text primary key,nombre text not null,categoria text not null,
 foto_url text,foto_fuente text,es_bebida boolean not null default true,
 verificacion_pendiente boolean not null default false
);
alter table aftr_catalogo_base enable row level security;
revoke all on aftr_catalogo_base from public,anon,authenticated;
grant all on aftr_catalogo_base to service_role;
create function venue_cargar_catalogo_base(p_club text) returns int language plpgsql security definer set search_path=public as $$
declare b aftr_catalogo_base; n int:=0; begin
 if not es_servicio() and coalesce(rol_en_club(p_club),'') not in ('admin','propietario') then raise exception 'Sin permiso'; end if;
 if not exists(select 1 from clubs where id=p_club) then raise exception 'Boliche no encontrado'; end if;
 for b in select * from aftr_catalogo_base order by clave loop
 if b.es_bebida then
 insert into bebidas(club_id,nombre,volumen_ml,activo,foto_url,foto_fuente)
 values(p_club,b.nombre,0,false,b.foto_url,b.foto_fuente) on conflict(club_id,nombre) do nothing;
 end if;
 if not exists(select 1 from tragos where club_id=p_club and lower(nombre)=lower(b.nombre)) then
 insert into tragos(club_id,nombre,precio_venta,activo,publicado_aftr,categoria_aftr,foto_url,foto_fuente,catalogo_clave)
 values(p_club,b.nombre,0,false,false,b.categoria,b.foto_url,b.foto_fuente,b.clave) on conflict do nothing;
 n:=n+1;
 end if;
 end loop; return n;
end $$;
revoke all on function venue_cargar_catalogo_base(text) from public,anon;
grant execute on function venue_cargar_catalogo_base(text) to authenticated,service_role;
do $$ begin
 if to_regclass('storage.buckets') is not null then
 insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types)
 values('bar-catalogo','bar-catalogo',true,1048576,array['image/webp','image/jpeg','image/png']) on conflict(id) do nothing;
 execute $p$create policy bar_catalogo_insert on storage.objects for insert to authenticated with check(bucket_id='bar-catalogo' and rol_en_club((storage.foldername(name))[1]) in ('admin','propietario'))$p$;
 execute $p$create policy bar_catalogo_select on storage.objects for select to authenticated using(bucket_id='bar-catalogo' and rol_en_club((storage.foldername(name))[1]) in ('admin','propietario'))$p$;
 execute $p$create policy bar_catalogo_update on storage.objects for update to authenticated using(bucket_id='bar-catalogo' and rol_en_club((storage.foldername(name))[1]) in ('admin','propietario')) with check(bucket_id='bar-catalogo' and rol_en_club((storage.foldername(name))[1]) in ('admin','propietario'))$p$;
 end if;
end $$;
create function venue_guardar_bebida_catalogo(p_bebida uuid,p_volumen int) returns void language plpgsql security definer set search_path=public as $$
declare b bebidas; begin
 select * into b from bebidas where id=p_bebida for update;
 if not found or coalesce(rol_en_club(b.club_id),'') not in ('admin','propietario') then raise exception 'Sin permiso'; end if;
 if p_volumen is null or p_volumen not between 1 and 10000 then raise exception 'Indicá el volumen real del envase en ml'; end if;
 if p_volumen<>b.volumen_ml and exists(select 1 from lotes where bebida_id=b.id) then raise exception 'Esta presentación ya tiene lotes. Creá otra bebida para cambiar el volumen.'; end if;
 update bebidas set volumen_ml=p_volumen,activo=true where id=b.id;
end $$;
revoke all on function venue_guardar_bebida_catalogo(uuid,int) from public,anon;
grant execute on function venue_guardar_bebida_catalogo(uuid,int) to authenticated,service_role;
commit;
