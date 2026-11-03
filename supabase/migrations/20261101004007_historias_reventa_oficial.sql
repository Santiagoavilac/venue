begin;

-- Stories and official P2P share the existing identity and event authority.
create table public.aftr_media_validada (
 storage_path text primary key, autor_id uuid not null references auth.users(id) on delete cascade,
 tipo text not null check(tipo in ('imagen','video')), duracion_ms int not null check(duracion_ms between 1 and 30000),
 size_bytes int not null check(size_bytes between 1 and 31457280), sha256 text not null,
 created_at timestamptz not null default now()
);
create table public.aftr_historias (
 id uuid primary key default gen_random_uuid(), autor_id uuid not null references auth.users(id) on delete cascade,
 identidad text not null check(identidad in ('usuario','club','rrpp')), club_id text references public.clubs(id),
 evento_id uuid references public.eventos(id), storage_path text not null unique references public.aftr_media_validada(storage_path) on delete cascade,
 tipo text not null check(tipo in ('imagen','video')), duracion_ms int not null,
 cta text check(cta in ('entrada','mesa')), created_at timestamptz not null default now(),
 vence_at timestamptz not null default now()+interval '24 hours', retirada_at timestamptz,
 retirada_por uuid, check(vence_at=created_at+interval '24 hours'), check(cta is null or evento_id is not null)
);
create index on public.aftr_historias(vence_at) where retirada_at is null;
create index on public.aftr_historias(autor_id,created_at desc);
create index on public.aftr_historias(evento_id);
create table public.aftr_historia_reportes (
 id uuid primary key default gen_random_uuid(), historia_id uuid not null references public.aftr_historias(id) on delete cascade,
 autor_id uuid not null references auth.users(id) on delete cascade, motivo text not null check(length(motivo) between 5 and 1000),
 created_at timestamptz not null default now(), unique(historia_id,autor_id)
);
alter table public.aftr_ordenes add column historia_id uuid references public.aftr_historias(id) on delete set null;
alter table public.aftr_ordenes add column referido_rrpp_id uuid references public.profiles(id);

create table public.aftr_reventa_config (
 club_id text primary key references public.clubs(id), habilitada boolean not null default false,
 max_precio_pct int check(max_precio_pct between 1 and 1000), pago_minutos int not null default 15 check(pago_minutos between 5 and 30),
 confirmacion_minutos int not null default 30 check(confirmacion_minutos between 5 and 120),
 cierre_minutos int not null default 0 check(cierre_minutos between 0 and 1440),
 condiciones text not null default '' check(length(condiciones)<=3000), updated_at timestamptz not null default now()
);
alter table public.entradas add column reventa_oferta_id uuid;
alter table public.entradas add column reventa_anterior_id uuid references public.entradas(id);
alter table public.entradas add column reventa_sucesora_id uuid references public.entradas(id) deferrable initially deferred;
alter table public.entradas add column reventa_raiz_id uuid references public.entradas(id);
create unique index entradas_credencial_vigente_uq on public.entradas((coalesce(reventa_raiz_id,id)))
 where reventa_sucesora_id is null;
create index on public.entradas(reventa_anterior_id);
create index on public.entradas(reventa_oferta_id);

create table public.aftr_reventa_ofertas (
 id uuid primary key default gen_random_uuid(), entrada_id uuid not null references public.entradas(id),
 evento_id uuid not null references public.eventos(id), club_id text not null references public.clubs(id),
 vendedor_id uuid not null, precio_centavos bigint not null check(precio_centavos between 100 and 100000000),
 estado text not null default 'publicada' check(estado in ('publicada','reservada','vendida','retirada')),
 pago_minutos int not null, confirmacion_minutos int not null, cierre_at timestamptz not null,
 condiciones text not null, client_key uuid not null, created_at timestamptz not null default now(),
 unique(vendedor_id,client_key)
);
create unique index reventa_una_oferta_activa on public.aftr_reventa_ofertas(entrada_id) where estado in ('publicada','reservada');
create index on public.aftr_reventa_ofertas(evento_id,estado);
create index on public.aftr_reventa_ofertas(vendedor_id,created_at desc);
alter table public.entradas add constraint entradas_reventa_oferta_fk foreign key(reventa_oferta_id) references public.aftr_reventa_ofertas(id);
create table public.aftr_reventa_metodos (
 oferta_id uuid primary key references public.aftr_reventa_ofertas(id), metodo jsonb not null
);
create table public.aftr_reventa_ordenes (
 id uuid primary key default gen_random_uuid(), oferta_id uuid not null references public.aftr_reventa_ofertas(id),
 entrada_id uuid not null references public.entradas(id), evento_id uuid not null references public.eventos(id),
 club_id text not null references public.clubs(id), vendedor_id uuid not null,
 comprador_id uuid not null, precio_centavos bigint not null,
 estado text not null default 'pendiente_pago' check(estado in ('pendiente_pago','pago_informado','completada','cancelada','vencida','en_disputa')),
 vence_at timestamptz not null, confirmar_hasta timestamptz, comprobante_path text, referencia text,
 motivo text, resolucion text, resuelta_por uuid, nueva_entrada_id uuid references public.entradas(id),
 client_key uuid not null, created_at timestamptz not null default now(), updated_at timestamptz not null default now(),
 unique(comprador_id,client_key), check(comprador_id<>vendedor_id)
);
create unique index reventa_una_orden_activa on public.aftr_reventa_ordenes(oferta_id) where estado in ('pendiente_pago','pago_informado','en_disputa');
create index on public.aftr_reventa_ordenes(evento_id,estado);
create index on public.aftr_reventa_ordenes(comprador_id,created_at desc);
create index on public.aftr_reventa_ordenes(vendedor_id,created_at desc);
create index on public.aftr_reventa_ordenes(vence_at) where estado='pendiente_pago';
create table public.aftr_reventa_historial (
 id bigint generated always as identity primary key, orden_id uuid not null references public.aftr_reventa_ordenes(id),
 evento_id uuid not null references public.eventos(id), autor_id uuid, tipo text not null,
 texto text not null check(length(texto) between 1 and 3000), archivo_path text,
 created_at timestamptz not null default now()
);
create index on public.aftr_reventa_historial(orden_id,id);

-- Reading offers never exposes a ticket code or seller bank details.
do $$ declare t text; begin
 foreach t in array array['aftr_media_validada','aftr_historias','aftr_historia_reportes','aftr_reventa_config','aftr_reventa_ofertas','aftr_reventa_metodos','aftr_reventa_ordenes','aftr_reventa_historial'] loop
  execute format('alter table public.%I enable row level security',t);
  execute format('revoke all on public.%I from public,anon,authenticated',t);
  execute format('grant all on public.%I to service_role',t);
 end loop;
end $$;
grant select on public.aftr_historias,public.aftr_reventa_ofertas to anon,authenticated;
grant select on public.aftr_reventa_ordenes,public.aftr_reventa_historial to authenticated;
create function public.aftr_historia_visible(p_historia uuid) returns boolean
language sql stable security definer set search_path=public,pg_temp as $$
 select exists(select 1 from aftr_historias h where h.id=p_historia and h.retirada_at is null and h.vence_at>now()
 and (h.evento_id is null or impl.aftr_visible(h.evento_id)))
$$;
revoke all on function public.aftr_historia_visible(uuid) from public;
grant execute on function public.aftr_historia_visible(uuid) to anon,authenticated;
create policy historias_visibles on public.aftr_historias for select to anon,authenticated
 using(public.aftr_historia_visible(id) or autor_id=auth.uid() or es_platform_admin()
 or (identidad='club' and rol_en_club(club_id) in ('admin','propietario')));
create policy ofertas_visibles on public.aftr_reventa_ofertas for select to anon,authenticated
 using((estado='publicada' and cierre_at>now()) or vendedor_id=auth.uid() or es_platform_admin()
 or rol_en_club(club_id) in ('admin','propietario'));
create policy ordenes_propias on public.aftr_reventa_ordenes for select to authenticated
 using(auth.uid() in (comprador_id,vendedor_id) or es_platform_admin());
create policy historial_privado on public.aftr_reventa_historial for select to authenticated
 using(exists(select 1 from aftr_reventa_ordenes o where o.id=orden_id and
 (auth.uid() in (o.comprador_id,o.vendedor_id) or es_platform_admin())));

create function public.aftr_social_archivo(p_bucket text,p_path text) returns boolean
language sql stable security definer set search_path=public,pg_temp as $$
 select case when p_bucket='aftr-historias' then
  split_part(p_path,'/',1)=auth.uid()::text or es_platform_admin() or exists(
   select 1 from aftr_historias h where h.storage_path=p_path and
    (aftr_historia_visible(h.id) or (h.identidad='club' and rol_en_club(h.club_id) in ('admin','propietario'))))
 when p_bucket='aftr-p2p' then split_part(p_path,'/',1)=auth.uid()::text or es_platform_admin() or exists(
  select 1 from aftr_reventa_ordenes o where auth.uid() in(o.comprador_id,o.vendedor_id) and
   (o.comprobante_path=p_path or exists(select 1 from aftr_reventa_historial h where h.orden_id=o.id and h.archivo_path=p_path)
    or exists(select 1 from aftr_reventa_metodos m where m.oferta_id=o.oferta_id and m.metodo->>'qr_path'=p_path)))
 else false end
$$;
revoke all on function public.aftr_social_archivo(text,text) from public;
grant execute on function public.aftr_social_archivo(text,text) to anon,authenticated;
create function public.aftr_social_ruta_nueva(p_path text) returns boolean
language sql stable security definer set search_path=public,pg_temp as $$
 select split_part(p_path,'/',1)=auth.uid()::text and not exists(select 1 from aftr_media_validada where storage_path=p_path)
$$;
create function public.aftr_social_borrable(p_bucket text,p_path text) returns boolean
language sql stable security definer set search_path=public,pg_temp as $$
 select split_part(p_path,'/',1)=auth.uid()::text and
 not exists(select 1 from aftr_historias h where h.storage_path=p_path) and
 not exists(select 1 from aftr_reventa_ordenes o where o.comprobante_path=p_path) and
 not exists(select 1 from aftr_reventa_historial h where h.archivo_path=p_path) and
 not exists(select 1 from aftr_reventa_metodos m where m.metodo->>'qr_path'=p_path)
$$;
revoke all on function public.aftr_social_ruta_nueva(text),public.aftr_social_borrable(text,text) from public;
grant execute on function public.aftr_social_ruta_nueva(text),public.aftr_social_borrable(text,text) to authenticated;
insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types) values
 ('aftr-historias','aftr-historias',false,31457280,array['image/jpeg','image/png','image/webp','video/mp4','video/quicktime']),
 ('aftr-p2p','aftr-p2p',false,8388608,array['image/jpeg','image/png','image/webp'])
on conflict(id) do update set public=false,file_size_limit=excluded.file_size_limit,allowed_mime_types=excluded.allowed_mime_types;
create policy social_archivo_leer on storage.objects for select to anon,authenticated
 using(bucket_id in ('aftr-historias','aftr-p2p') and public.aftr_social_archivo(bucket_id,name));
create policy social_archivo_crear on storage.objects for insert to authenticated with check(
 bucket_id in ('aftr-historias','aftr-p2p') and split_part(name,'/',1)=auth.uid()::text
 and public.aftr_social_ruta_nueva(name) and name ~ '^[a-f0-9-]{36}/[a-f0-9-]{36}\.(jpg|jpeg|png|webp|mp4|mov)$'
 and (exists(select 1 from public.aftr_clientes c where c.user_id=auth.uid()) or exists(
 select 1 from public.profiles p where p.id=auth.uid() and p.activo and p.eliminado_at is null)));
-- No UPDATE/upsert: validation always binds immutable bytes to a unique path.
create policy social_archivo_borrar on storage.objects for delete to authenticated using(
 bucket_id in ('aftr-historias','aftr-p2p') and public.aftr_social_borrable(bucket_id,name));

create function impl.social_historia_json(h public.aftr_historias) returns jsonb
language sql stable security definer set search_path=public,pg_temp as $$
 select jsonb_build_object('id',h.id,'autor_id',h.autor_id,'autor',coalesce(c.nombre,p.nombre,'AFTR'),
 'nombre',case when h.identidad='club' then cl.nombre else coalesce(c.nombre,p.nombre,'AFTR') end,
 'identidad',h.identidad,'club_id',h.club_id,'evento_id',h.evento_id,'evento',e.nombre,
 'cta',h.cta,'storage_path',h.storage_path,'tipo',h.tipo,'duracion_ms',h.duracion_ms,
 'created_at',h.created_at,'vence_at',h.vence_at,'retirada_at',h.retirada_at,
 'can_retirar',h.autor_id=auth.uid() or es_platform_admin() or (h.identidad='club' and rol_en_club(h.club_id) in ('admin','propietario')))
 from (select 1) b left join aftr_clientes c on c.user_id=h.autor_id left join profiles p on p.id=h.autor_id
 left join clubs cl on cl.id=h.club_id left join eventos e on e.id=h.evento_id
$$;
create function public.aftr_historias(p_accion text,p_datos jsonb default '{}') returns jsonb
language plpgsql volatile security definer set search_path=public,pg_temp as $$
declare u uuid:=auth.uid(); h aftr_historias; m aftr_media_validada; v_identidad text; v_club text;
 v_evento uuid; v_id uuid; v_cta text; r jsonb; v_rol text;
begin
 if p_accion='feed' then
  return jsonb_build_object('historias',coalesce((select jsonb_agg(impl.social_historia_json(x) order by x.created_at)
   from (select * from aftr_historias where aftr_historia_visible(id) order by created_at desc limit 300) x),'[]'::jsonb),'ahora',now());
 end if;
 if u is null then raise exception 'Iniciá sesión.' using errcode='28000'; end if;
 if p_accion in ('mias','gestion') then
  return jsonb_build_object('historias',coalesce((select jsonb_agg(impl.social_historia_json(x) order by x.created_at desc)
   from (select * from aftr_historias where (p_datos->>'club_id' is null or club_id=p_datos->>'club_id') and
   (autor_id=u or (p_accion='gestion' and (es_platform_admin() or (identidad='club' and rol_en_club(club_id) in ('admin','propietario')))))
   and created_at>now()-interval '30 days' order by created_at desc limit 300) x),'[]'::jsonb),
   'reportes',case when es_platform_admin() then coalesce((select jsonb_agg(to_jsonb(x)) from
   (select * from aftr_historia_reportes order by created_at desc limit 200) x),'[]'::jsonb) else '[]'::jsonb end,'ahora',now());
 elsif p_accion='publicar' then
  v_identidad:=coalesce(p_datos->>'identidad','usuario'); v_club:=nullif(p_datos->>'club_id','');
  v_evento:=nullif(p_datos->>'evento_id','')::uuid; v_cta:=nullif(p_datos->>'cta','');
  if v_identidad='usuario' then
   perform impl.aftr_yo(); v_club:=null;
  elsif v_identidad in ('club','rrpp') then
   v_rol:=rol_en_club(v_club);
   if (v_identidad='club' and coalesce(v_rol,'') not in ('admin','propietario')) or
      (v_identidad='rrpp' and coalesce(v_rol,'') not in ('rrpp','jefe','admin')) then
    raise exception 'No podés publicar con esa identidad.' using errcode='42501';
   end if;
  else raise exception 'Identidad no válida.'; end if;
  if v_evento is not null and (not impl.aftr_visible(v_evento) or
   (v_club is not null and not exists(select 1 from eventos where id=v_evento and club_id=v_club))) then
   raise exception 'Este evento no está disponible para esta historia.';
  end if;
  if (select count(*) from aftr_historias where autor_id=u and created_at>now()-interval '24 hours')>=30 then
   raise exception 'Podés publicar hasta 30 historias por día.';
  end if;
  select * into m from aftr_media_validada where storage_path=p_datos->>'storage_path' and autor_id=u;
  if not found or not exists(select 1 from storage.objects where bucket_id='aftr-historias' and name=m.storage_path) then
   raise exception 'Primero subí y validá el archivo de la historia.';
  end if;
  insert into aftr_historias(autor_id,identidad,club_id,evento_id,cta,storage_path,tipo,duracion_ms)
  values(u,v_identidad,v_club,v_evento,v_cta,m.storage_path,m.tipo,m.duracion_ms) returning * into h;
  return impl.social_historia_json(h);
 elsif p_accion in ('retirar','reportar') then
  v_id:=(p_datos->>'id')::uuid; select * into h from aftr_historias where id=v_id for update;
  if not found then raise exception 'Historia no encontrada.'; end if;
  if p_accion='retirar' then
   if not coalesce(h.autor_id=u or es_platform_admin() or (h.identidad='club' and rol_en_club(h.club_id) in ('admin','propietario')),false) then
    raise exception 'No autorizado.' using errcode='42501'; end if;
   update aftr_historias set retirada_at=coalesce(retirada_at,now()),retirada_por=u where id=h.id;
  else
   if not aftr_historia_visible(h.id) then raise exception 'Esta historia ya no está disponible.'; end if;
   insert into aftr_historia_reportes(historia_id,autor_id,motivo) values(h.id,u,trim(p_datos->>'motivo'))
    on conflict(historia_id,autor_id) do nothing;
  end if;
  return jsonb_build_object('ok',true);
 end if;
 raise exception 'Acción de historias no válida.';
end $$;

-- Freeze attribution at order creation, never at a later page visit.
create function impl.historia_atribucion(p_historia uuid,p_cta text) returns public.aftr_historias
language plpgsql security definer set search_path=public,pg_temp as $$
declare h aftr_historias; begin
 select * into h from aftr_historias where id=p_historia;
 if not found or not aftr_historia_visible(h.id) or h.cta is distinct from p_cta then
  raise exception 'La historia ya no está disponible. Abrí el evento para continuar.'; end if;
 if h.identidad='rrpp' and not exists(select 1 from profiles p left join club_membership cm on cm.user_id=p.id and cm.club_id=h.club_id
 where p.id=h.autor_id and p.activo and p.eliminado_at is null and
 (p.admin_principal or exists(select 1 from platform_admins pa where pa.user_id=p.id) or
 case when p.rol='admin' then h.club_id=any(p.clubs)
 when cm.user_id is not null then cm.rol in ('rrpp','jefe','admin')
 else h.club_id=any(p.clubs) and p.rol in ('rrpp','jefe') end)) then
  raise exception 'La promoción del relacionador ya no está vigente.'; end if;
 return h;
end $$;
create function public.aftr_comprar_historia(p_historia uuid,p_evento uuid,p_fase uuid,p_cantidad int) returns jsonb
language plpgsql security definer set search_path=public,pg_temp as $$
declare h aftr_historias:=impl.historia_atribucion(p_historia,'entrada'); r jsonb; begin
 if h.evento_id is distinct from p_evento then raise exception 'La historia no pertenece a este evento.'; end if;
 r:=aftr_comprar(h.evento_id,p_fase,p_cantidad);
 update aftr_ordenes set historia_id=h.id,referido_rrpp_id=case when h.identidad='rrpp' then h.autor_id end where id=(r->>'id')::uuid;
 return r;
end $$;
create function public.aftr_reservar_historia(p_historia uuid,p_evento uuid,p_mesa uuid,p_combo uuid default null) returns jsonb
language plpgsql security definer set search_path=public,pg_temp as $$
declare h aftr_historias:=impl.historia_atribucion(p_historia,'mesa'); r jsonb; begin
 if h.evento_id is distinct from p_evento then raise exception 'La historia no pertenece a este evento.'; end if;
 r:=aftr_reservar_mesa(h.evento_id,p_mesa,p_combo);
 update aftr_ordenes set historia_id=h.id,referido_rrpp_id=case when h.identidad='rrpp' then h.autor_id end where id=(r->>'id')::uuid;
 update mesas set vendido_por=case when h.identidad='rrpp' then h.autor_id end where id=p_mesa;
 return r;
end $$;
-- Emission from bank and PULSE use this same trigger, including delayed payments.
create function impl.historia_entrada_atribuir() returns trigger language plpgsql security definer set search_path=public,pg_temp as $$
begin
 if old.estado is distinct from 'confirmada' and new.estado='confirmada' and new.referido_rrpp_id is not null then
  update entradas set rrpp_id=new.referido_rrpp_id where cliente_id=new.cliente_id and evento_id=new.evento_id
   and canal='aftr' and rrpp_id is null and reventa_anterior_id is null
   and ((new.tipo='entrada' and mesa_id is null and created_at>=transaction_timestamp()) or (new.tipo='mesa' and mesa_id=new.mesa_id));
 end if;
 return new;
end $$;
create trigger aftr_historia_emitida after update on public.aftr_ordenes for each row execute function impl.historia_entrada_atribuir();

create function impl.reventa_anotar(p_orden uuid,p_tipo text,p_texto text,p_archivo text default null) returns void
language sql security definer set search_path=public,pg_temp as $$
 insert into aftr_reventa_historial(orden_id,evento_id,autor_id,tipo,texto,archivo_path)
 select id,evento_id,auth.uid(),p_tipo,p_texto,p_archivo from aftr_reventa_ordenes where id=p_orden
$$;
create function impl.reventa_finalizar(p_orden uuid) returns uuid
language plpgsql security definer set search_path=public,pg_temp as $$
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
 insert into entradas(id,evento_id,code,cliente,rrpp_id,precio,estado,created_at,fase_id,cliente_id,canal,
 reventa_anterior_id,reventa_raiz_id)
 values(n,x.evento_id,upper(replace(gen_random_uuid()::text,'-','')),v_nombre,x.rrpp_id,x.precio,'valida',x.created_at,
 x.fase_id,o.comprador_id,'aftr',x.id,coalesce(x.reventa_raiz_id,x.id));
 update aftr_reventa_ofertas set estado='vendida' where id=o.oferta_id;
 update aftr_reventa_ordenes set estado='completada',nueva_entrada_id=n,updated_at=now() where id=o.id;
 perform impl.reventa_anotar(o.id,'completada','Entrada entregada. El QR anterior quedó invalidado definitivamente.');
 perform set_config('aftr.reventa_interna','',true);
 return n;
end $$;
create function impl.reventa_liberar(p_oferta uuid,p_estado text default 'retirada') returns void
language plpgsql security definer set search_path=public,pg_temp as $$
begin
 perform set_config('aftr.reventa_interna',p_oferta::text,true);
 update aftr_reventa_ofertas set estado=p_estado where id=p_oferta;
 update entradas set reventa_oferta_id=null where reventa_oferta_id=p_oferta;
 perform set_config('aftr.reventa_interna','',true);
end $$;
create function impl.reventa_vencer() returns void language plpgsql security definer set search_path=public,pg_temp as $$
declare r record; o aftr_reventa_ordenes;
begin
 -- Consistent lock order everywhere: ticket, offer, order. SKIP LOCKED lets cron retry safely.
 for r in select entrada_id,oferta_id,id from aftr_reventa_ordenes where
  (estado='pendiente_pago' and vence_at<=now()) or (estado='pago_informado' and confirmar_hasta<=now()) loop
  perform 1 from entradas where id=r.entrada_id for update skip locked; if not found then continue; end if;
  perform 1 from aftr_reventa_ofertas where id=r.oferta_id for update;
  select * into o from aftr_reventa_ordenes where id=r.id for update;
  if o.estado='pendiente_pago' and o.vence_at<=now() then
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
end $$;

-- Emit a safe offer change for club dashboards; private order rows remain participant-only.
create function impl.reventa_notificar() returns trigger language plpgsql security definer set search_path=public,pg_temp as $$
begin update aftr_reventa_ofertas set estado=estado where id=new.oferta_id; return new; end $$;
create trigger aftr_reventa_notificar after insert or update on public.aftr_reventa_ordenes for each row execute function impl.reventa_notificar();

create function impl.reventa_entrada_guard() returns trigger language plpgsql security definer set search_path=public,pg_temp as $$
begin
 if tg_op='UPDATE' and new.cliente_id is null and old.cliente_id is not null and
  (to_jsonb(new)-'cliente_id')=(to_jsonb(old)-'cliente_id') and (auth.uid()=old.cliente_id or es_servicio()) then return new; end if;
 if old.reventa_sucesora_id is not null then raise exception 'Esta entrada fue reemplazada y no se puede modificar.'; end if;
 if old.reventa_oferta_id is not null and coalesce(current_setting('aftr.reventa_interna',true),'')<>old.reventa_oferta_id::text then
  raise exception 'La entrada está bloqueada por una reventa. Resolvé la operación antes de modificarla.';
 end if;
 if tg_op='DELETE' then return old; end if; return new;
end $$;
create trigger aftr_reventa_entrada_guard before update or delete on public.entradas for each row execute function impl.reventa_entrada_guard();
-- Closing an account cannot abandon an active payment; closed operations retain their audit IDs.
create function impl.reventa_cerrar_cuenta() returns trigger language plpgsql security definer set search_path=public,pg_temp as $$
begin
 if exists(select 1 from aftr_reventa_ofertas where vendedor_id=old.user_id and estado in ('publicada','reservada'))
 or exists(select 1 from aftr_reventa_ordenes where old.user_id in(comprador_id,vendedor_id) and estado in ('pendiente_pago','pago_informado','en_disputa')) then
  raise exception 'Resolvé tus operaciones y retirá tus publicaciones de reventa antes de eliminar tu cuenta.';
 end if;
 return old;
end $$;
create trigger aftr_reventa_cerrar_cuenta before delete on public.aftr_clientes for each row execute function impl.reventa_cerrar_cuenta();

create function impl.reventa_historial_inmutable() returns trigger language plpgsql set search_path=public,pg_temp as $$
begin raise exception 'El historial de reventa es inmutable.'; end $$;
create trigger aftr_reventa_historial_inmutable before update or delete on public.aftr_reventa_historial
 for each row execute function impl.reventa_historial_inmutable();

create function impl.reventa_oferta_json(o public.aftr_reventa_ofertas) returns jsonb
language sql stable security definer set search_path=public,pg_temp as $$
 select jsonb_build_object('id',o.id,'entrada_id',o.entrada_id,'evento_id',o.evento_id,'club_id',o.club_id,
 'evento',e.nombre,'club',c.nombre,'fecha',e.fecha,'precio_centavos',o.precio_centavos,'vendedor',coalesce(u.usuario,'Cuenta eliminada'),
 'vendedor_id',o.vendedor_id,'estado',o.estado,'created_at',o.created_at,'cierre_at',o.cierre_at,
 'condiciones',o.condiciones,'pago_minutos',o.pago_minutos,'confirmacion_minutos',o.confirmacion_minutos)
 from eventos e join clubs c on c.id=e.club_id left join aftr_clientes u on u.user_id=o.vendedor_id where e.id=o.evento_id
$$;
create function impl.reventa_orden_json(o public.aftr_reventa_ordenes) returns jsonb
language sql stable security definer set search_path=public,pg_temp as $$
 select jsonb_build_object('id',o.id,'oferta_id',o.oferta_id,'entrada_id',o.entrada_id,'evento_id',o.evento_id,
 'club_id',o.club_id,'evento',e.nombre,'club',c.nombre,'estado',o.estado,'comprador_id',o.comprador_id,
 'vendedor_id',o.vendedor_id,'comprador',coalesce(b.usuario,'Cuenta eliminada'),'vendedor',coalesce(s.usuario,'Cuenta eliminada'),'precio_centavos',o.precio_centavos,
 'vence_at',o.vence_at,'confirmar_hasta',o.confirmar_hasta,'created_at',o.created_at,'motivo',o.motivo,
 'resolucion',o.resolucion,'puede_resolver',es_platform_admin(),'nueva_entrada_id',o.nueva_entrada_id,'ahora',now(),
 'condiciones',f.condiciones,
 'metodo',case when auth.uid() in(o.comprador_id,o.vendedor_id) or es_platform_admin() then m.metodo end,
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
$$;

create function public.aftr_reventa(p_accion text,p_datos jsonb default '{}') returns jsonb
language plpgsql volatile security definer set search_path=public,pg_temp as $$
#variable_conflict use_column
declare u uuid:=auth.uid(); v_id uuid; v_oferta uuid; v_entrada uuid; v_club text; v_precio bigint;
 v_key uuid; x entradas; e eventos; f aftr_reventa_ofertas; o aftr_reventa_ordenes; cfg aftr_reventa_config;
 v_metodo jsonb; v_path text; v_texto text; v_accion text; v_fin timestamptz; r jsonb; z record;
begin
 if p_datos is null or jsonb_typeof(p_datos)<>'object' or octet_length(p_datos::text)>16000 then raise exception 'Datos no válidos.'; end if;
 perform impl.reventa_vencer();
 if p_accion='mercado' then
  return jsonb_build_object('ofertas',coalesce((select jsonb_agg(impl.reventa_oferta_json(t)) from
   (select f.* from aftr_reventa_ofertas f join aftr_reventa_config c on c.club_id=f.club_id and c.habilitada
    where f.estado='publicada' and f.cierre_at>now() and impl.aftr_visible(f.evento_id)
    and (p_datos->>'evento_id' is null or f.evento_id=(p_datos->>'evento_id')::uuid)
    order by f.created_at desc limit 200) t),'[]'::jsonb),'ahora',now());
 end if;
 if u is null then raise exception 'Iniciá sesión.' using errcode='28000'; end if;
 if p_accion='mias' then
  perform impl.aftr_yo();
  return jsonb_build_object('ofertas',coalesce((select jsonb_agg(impl.reventa_oferta_json(f) order by f.created_at desc)
   from aftr_reventa_ofertas f where f.vendedor_id=u),'[]'::jsonb),
  'ordenes',coalesce((select jsonb_agg(impl.reventa_orden_json(o) order by o.created_at desc) from aftr_reventa_ordenes o
   where u in(o.comprador_id,o.vendedor_id)),'[]'::jsonb),
  'entradas',coalesce((select jsonb_agg(jsonb_build_object('id',t.id,'evento_id',t.evento_id,'evento',e.nombre,
  'precio',t.precio,'estado',case when t.reventa_oferta_id is not null then 'bloqueada' else t.estado end,
  'club_id',e.club_id,'reventa_habilitada',coalesce(c.habilitada,false))) from entradas t join eventos e on e.id=t.evento_id
  left join aftr_reventa_config c on c.club_id=e.club_id where t.cliente_id=u and t.estado='valida' and t.mesa_id is null
  and t.precio>0 and t.reventa_sucesora_id is null and impl.aftr_fin(e.fecha,e.hora_inicio,e.hora_fin)>now()),'[]'::jsonb),'ahora',now());
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
   update aftr_reventa_config set habilitada=coalesce((p_datos->>'habilitada')::boolean,false),
   max_precio_pct=nullif(p_datos->>'max_precio_pct','')::int,
   pago_minutos=coalesce((p_datos->>'pago_minutos')::int,15),
   confirmacion_minutos=coalesce((p_datos->>'confirmacion_minutos')::int,30),
   cierre_minutos=coalesce((p_datos->>'cierre_minutos')::int,0),condiciones=coalesce(p_datos->>'condiciones',''),updated_at=now()
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
   'ofertas',coalesce((select jsonb_agg(impl.reventa_oferta_json(f) order by f.created_at desc) from aftr_reventa_ofertas f
    where (v_club is null or f.club_id=v_club)),'[]'::jsonb),
   'ordenes',coalesce((select jsonb_agg(impl.reventa_orden_json(o) order by o.created_at desc) from aftr_reventa_ordenes o
    where (v_club is null or o.club_id=v_club)),'[]'::jsonb),
   'disputas',coalesce((select jsonb_agg(impl.reventa_orden_json(o) order by o.updated_at) from aftr_reventa_ordenes o
    where o.estado='en_disputa' and (v_club is null or o.club_id=v_club)),'[]'::jsonb),'ahora',now());
 elsif p_accion='publicar' then
  perform impl.aftr_yo();
  v_entrada:=(p_datos->>'entrada_id')::uuid;v_key:=(p_datos->>'client_key')::uuid;v_precio:=(p_datos->>'precio_centavos')::bigint;
  if v_key is null or v_precio is null or v_precio<100 or v_precio>100000000 then raise exception 'Ingresá un precio válido en Bs.'; end if;
  -- Serialize the idempotency key, including attempts with different ticket IDs.
  perform pg_advisory_xact_lock(hashtextextended('reventa-publicar:'||u||':'||v_key,0));
  select * into f from aftr_reventa_ofertas where vendedor_id=u and client_key=v_key;
  if found then
   if f.entrada_id<>v_entrada or f.precio_centavos<>v_precio then raise exception 'Esta operación ya tiene otros datos.'; end if;
   return impl.reventa_oferta_json(f);
  end if;
  select e.club_id into v_club from entradas t join eventos e on e.id=t.evento_id where t.id=v_entrada;
  perform pg_advisory_xact_lock(hashtextextended('reventa-config:'||coalesce(v_club,''),0));
  select * into x from entradas where id=v_entrada for update;
  if not found or x.cliente_id is distinct from u then raise exception 'Esta entrada no es tuya.' using errcode='42501'; end if;
  if x.estado<>'valida' or x.reventa_oferta_id is not null or x.reventa_sucesora_id is not null or x.mesa_id is not null
   or x.precio<=0 or x.canal<>'aftr' or x.filtro_at is not null then raise exception 'Esta entrada no está disponible para reventa.'; end if;
  select * into e from eventos where id=x.evento_id;
  select * into cfg from aftr_reventa_config where club_id=e.club_id;
  if not found or not cfg.habilitada or not impl.aftr_visible(e.id) then raise exception 'El boliche no habilitó la reventa para este evento.'; end if;
  v_fin:=least(coalesce(e.entrada_hasta,impl.aftr_fin(e.fecha,e.hora_inicio,e.hora_fin)),impl.aftr_fin(e.fecha,e.hora_inicio,e.hora_fin))-make_interval(mins=>cfg.cierre_minutos);
  if v_fin<=now()+make_interval(mins=>cfg.pago_minutos) then raise exception 'Ya cerró el plazo para revender esta entrada.'; end if;
  if cfg.max_precio_pct is not null and v_precio>x.precio*cfg.max_precio_pct then raise exception 'El precio supera el máximo permitido por el boliche.'; end if;
  v_metodo:=p_datos->'metodo';
  if jsonb_typeof(v_metodo) is distinct from 'object' or length(trim(coalesce(v_metodo->>'titular','')))<3 or
  length(trim(coalesce(v_metodo->>'banco','')))<2 or
  (length(trim(coalesce(v_metodo->>'cuenta','')))<3 and nullif(v_metodo->>'qr_path','') is null) or octet_length(v_metodo::text)>4000 then
   raise exception 'Completá titular, banco y cuenta o QR de cobro.'; end if;
  if nullif(v_metodo->>'qr_path','') is not null and not exists(select 1 from storage.objects where bucket_id='aftr-p2p'
    and name=v_metodo->>'qr_path' and split_part(name,'/',1)=u::text) then raise exception 'El QR de cobro no pertenece a tu cuenta.'; end if;
  insert into aftr_reventa_ofertas(entrada_id,evento_id,club_id,vendedor_id,precio_centavos,pago_minutos,confirmacion_minutos,cierre_at,condiciones,client_key)
  values(x.id,e.id,e.club_id,u,v_precio,cfg.pago_minutos,cfg.confirmacion_minutos,v_fin,cfg.condiciones,v_key) returning * into f;
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
  if (select count(*) from aftr_reventa_ordenes where comprador_id=u and estado='pendiente_pago')>=3 then
   raise exception 'Resolvé tus operaciones pendientes antes de iniciar otra.'; end if;
  insert into aftr_reventa_ordenes(oferta_id,entrada_id,evento_id,club_id,vendedor_id,comprador_id,precio_centavos,vence_at,client_key)
  values(f.id,f.entrada_id,f.evento_id,f.club_id,f.vendedor_id,u,f.precio_centavos,least(now()+make_interval(mins=>f.pago_minutos),f.cierre_at),v_key) returning * into o;
  update aftr_reventa_ofertas set estado='reservada' where id=f.id;
  perform impl.reventa_anotar(o.id,'pendiente_pago','Orden creada. Pagá al vendedor y adjuntá el comprobante dentro del plazo.');
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
 if p_accion='informar_pago' then
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
  if o.estado<>'pendiente_pago' then raise exception 'Hay un pago informado. Abrí una disputa para resolverlo.'; end if;
  update aftr_reventa_ordenes set estado='cancelada',updated_at=now() where id=o.id;
  perform impl.reventa_liberar(o.oferta_id);
  perform impl.reventa_anotar(o.id,'cancelada','Operación cancelada antes de informar pago.');
 elsif p_accion='disputar' then
  if o.resolucion is not null then raise exception 'AFTR ya resolvió esta disputa.'; end if;
  v_texto:=trim(p_datos->>'motivo');
  if length(coalesce(v_texto,'')) not between 5 and 1000 then raise exception 'Describí el problema (5 a 1000 caracteres).'; end if;
  if o.estado='en_disputa' then return impl.reventa_orden_json(o); end if;
  if o.estado='completada' then raise exception 'La operación ya fue entregada. Su historial permanece disponible.'; end if;
  -- Late external payments cannot revoke an already reassigned ticket. AFTR arbitrates a refund instead.
  if o.estado in ('cancelada','vencida') then
   update aftr_reventa_ordenes set estado='en_disputa',motivo='Pago tardío: '||v_texto,updated_at=now() where id=o.id;
   if not exists(select 1 from aftr_reventa_ofertas where id=o.oferta_id and estado in ('publicada','reservada','vendida')) and
    exists(select 1 from entradas where id=o.entrada_id and estado='valida' and cliente_id=o.vendedor_id and reventa_oferta_id is null) then
    update entradas set reventa_oferta_id=o.oferta_id where id=o.entrada_id;
   end if;
  else update aftr_reventa_ordenes set estado='en_disputa',motivo=v_texto,updated_at=now() where id=o.id; end if;
  perform impl.reventa_anotar(o.id,'en_disputa',v_texto);
 elsif p_accion='mensaje' then
  if o.estado not in ('pendiente_pago','pago_informado','en_disputa') then raise exception 'Esta operación ya está cerrada.'; end if;
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
end $$;

-- A replaced credential is not another sale or another seat in a phase.
create view impl.entradas_vigentes with (security_invoker=true) as
 select * from public.entradas where reventa_sucesora_id is null;
revoke all on impl.entradas_vigentes from public,anon,authenticated;
-- Keep existing report and capacity formulas, replacing their ticket read source only.
-- INSERT/UPDATE destinations remain public.entradas, preserving triggers and constraints.
do $$ declare f record; d text; begin
 for f in select p.oid,p.proname,n.nspname,pg_get_functiondef(p.oid) as def from pg_proc p
 join pg_namespace n on n.oid=p.pronamespace where n.nspname in ('public','impl') and p.prokind='f'
 and p.proname not like 'reventa_%' and p.proname not like 'social_%'
 and p.proname not in ('gen_code_evento','club_de','aftr_reventa','aftr_historias','aftr_historia_visible','aftr_social_archivo','reventa_entrada_guard','validar_entrada') loop
  d:=regexp_replace(f.def,'\m(from|join)\s+(public\.)?entradas\M','\1 impl.entradas_vigentes','gi');
  if d<>f.def and f.def !~* 'delete\s+from\s+(public\.)?entradas\M' then execute d; end if;
 end loop;
end $$;

-- Preserve the public scanner's permission and attempt guards; fix the internal atomic operation.
create or replace function impl.validar_entrada(p_evento uuid,p_code text) returns json
language plpgsql volatile security definer set search_path=public,pg_temp as $$
declare x entradas; v_club text; v_tope timestamptz; v_rrpp text;v_team text;v_mesa text;v_sin_tope boolean;
begin
 select * into x from entradas where evento_id=p_evento and code=upper(p_code) for update;
 if not found then return json_build_object('resultado','no_existe'); end if;
 if x.reventa_sucesora_id is not null then return json_build_object('resultado','reemplazada','cliente',x.cliente,'code',x.code); end if;
 if x.reventa_oferta_id is not null then return json_build_object('resultado','bloqueada','cliente',x.cliente,'code',x.code); end if;
 select club_id,entrada_hasta into v_club,v_tope from eventos where id=p_evento;
 select p.nombre,t.nombre into v_rrpp,v_team from profiles p left join teams t on t.id=p.team_id where p.id=x.rrpp_id;
 select etiqueta into v_mesa from mesas where id=x.mesa_id;
 v_sin_tope:=exists(select 1 from ingreso_sin_tope where user_id=x.rrpp_id and club_id=v_club);
 if x.estado='anulada' then return json_build_object('resultado','anulada','cliente',x.cliente,'code',x.code); end if;
 if x.estado='usada' then return json_build_object('resultado','usada','cliente',x.cliente,'code',x.code,'used_at',x.used_at,'rrpp',v_rrpp,'team',v_team,'mesa',v_mesa); end if;
 if v_tope is not null and now()>v_tope and not v_sin_tope then return json_build_object('resultado','fuera_hora','cliente',x.cliente,'code',x.code); end if;
 update entradas set estado='usada',used_at=now(),portero_id=auth.uid() where id=x.id and code=upper(p_code) and estado='valida'
 and reventa_oferta_id is null and reventa_sucesora_id is null;
 if not found then return json_build_object('resultado','no_existe'); end if;
 return json_build_object('resultado','valida','cliente',x.cliente,'code',x.code,'rrpp',v_rrpp,'team',v_team,'mesa',v_mesa,'sin_tope',v_sin_tope);
end $$;

alter function public.aftr_mis_accesos() set schema impl;
alter function impl.aftr_mis_accesos() rename to aftr_mis_accesos_social_base;
create function public.aftr_mis_accesos() returns jsonb language plpgsql volatile security definer set search_path=public,pg_temp as $$
declare r jsonb; v_entradas jsonb; begin
 perform impl.reventa_vencer();
 r:=impl.aftr_mis_accesos_social_base();
 select coalesce(jsonb_agg(case when e.reventa_oferta_id is not null then v||jsonb_build_object(
  'estado','bloqueada','qr',null,'code',null,'transferible',false,'reventa_id',e.reventa_oferta_id) else v end),'[]'::jsonb)
 into v_entradas from jsonb_array_elements(r->'entradas') v join entradas e on e.id=(v->>'id')::uuid;
 return jsonb_set(r,'{entradas}',v_entradas);
end $$;

create function public.aftr_social_limpieza() returns jsonb language sql security definer set search_path=public,pg_temp as $$
 select coalesce(jsonb_agg(jsonb_build_object('name',q.name)),'[]'::jsonb) from (
 select o.name from storage.objects o where o.bucket_id='aftr-historias' and
 (exists(select 1 from aftr_historias h where h.storage_path=o.name and (h.vence_at<now()-interval '5 minutes' or h.retirada_at<now()-interval '5 minutes'))
 or (o.created_at<now()-interval '24 hours' and not exists(select 1 from aftr_historias h where h.storage_path=o.name)))
 limit 100) q
$$;
revoke all on function public.aftr_social_limpieza() from public,anon,authenticated;
grant execute on function public.aftr_social_limpieza() to service_role;

-- Story conversions use the frozen order attribution. Legacy links use one last visit, not every prior visitor.
create or replace function public.rrpp_links(p_desde date default null)
returns table(evento_id uuid,evento text,fecha date,visitas bigint,clientes bigint,compras bigint)
language sql stable security definer set search_path=public,pg_temp as $$
 select e.id,e.nombre,e.fecha,
  (select count(*) from link_visita v where v.evento_id=e.id and v.rrpp_id=auth.uid()),
  (select count(distinct v.cliente_id) from link_visita v where v.evento_id=e.id and v.rrpp_id=auth.uid()),
  (select count(*) from aftr_ordenes o where o.evento_id=e.id and o.estado='confirmada' and
   (o.referido_rrpp_id=auth.uid() or (o.historia_id is null and o.referido_rrpp_id is null and auth.uid()=(
    select v2.rrpp_id from link_visita v2 where v2.evento_id=e.id and v2.cliente_id=o.cliente_id and v2.at<=o.created_at
    order by v2.at desc,v2.id desc limit 1))))
 from eventos e where (p_desde is null or e.fecha>=p_desde) and
 (exists(select 1 from link_visita v where v.evento_id=e.id and v.rrpp_id=auth.uid()) or
  exists(select 1 from aftr_ordenes o where o.evento_id=e.id and o.referido_rrpp_id=auth.uid())) order by e.fecha desc
$$;
revoke all on function public.rrpp_links(date) from public,anon;
grant execute on function public.rrpp_links(date) to authenticated;

-- Explicit privilege boundary: internal helpers cannot be called through the API.
do $$ declare f record; begin
 for f in select p.oid::regprocedure as sig,n.nspname,p.proname from pg_proc p join pg_namespace n on n.oid=p.pronamespace
 where (n.nspname='impl' and (p.proname like 'reventa_%' or p.proname like 'social_%' or p.proname like 'historia_%'
 or p.proname in ('aftr_mis_accesos_social_base','validar_entrada')))
 or (n.nspname='public' and p.proname in ('aftr_historias','aftr_reventa','aftr_comprar_historia','aftr_reservar_historia','aftr_mis_accesos')) loop
  execute format('revoke all on function %s from public,anon,authenticated',f.sig);
  if f.nspname='public' then execute format('grant execute on function %s to authenticated',f.sig); end if;
 end loop;
end $$;
grant execute on function public.aftr_historias(text,jsonb),public.aftr_reventa(text,jsonb) to anon;
-- Anonymous calls are restricted by the dispatcher's explicit action checks.

do $$ declare t text; begin
 foreach t in array array['aftr_historias','aftr_reventa_ofertas','aftr_reventa_ordenes','aftr_reventa_historial'] loop
  if not exists(select 1 from pg_publication_tables where pubname='supabase_realtime' and schemaname='public' and tablename=t) then
   execute format('alter publication supabase_realtime add table public.%I',t); end if;
 end loop;
 if exists(select 1 from pg_namespace where nspname='cron') then
  perform cron.schedule('aftr-reventa-vencer','* * * * *','select impl.reventa_vencer()');
 end if;
end $$;
do $$ begin
 if exists(select 1 from pg_namespace where nspname='cron') and exists(select 1 from pg_namespace where nspname='net')
 and exists(select 1 from pg_namespace where nspname='vault') then
  perform cron.schedule('aftr-historias-limpiar','*/15 * * * *',$job$
   select net.http_post(url:='https://cxksjarupexptfksnptg.supabase.co/functions/v1/historias-media',
    headers:=jsonb_build_object('Content-Type','application/json','x-social-cron',(select decrypted_secret from vault.decrypted_secrets where name='baneco_cron_token' limit 1)),
    body:='{"accion":"limpiar"}'::jsonb,timeout_milliseconds:=30000)
   where exists(select 1 from vault.decrypted_secrets where name='baneco_cron_token')
  $job$);
 end if;
end $$;
notify pgrst,'reload schema';
commit;
