-- AFTR · la app del público conectada a Venue.
--
-- Venue (B2B) crea el evento; si el boliche lo marca "Publicar en AFTR",
-- el público lo ve, compra, reserva mesa o se anota en una lista desde
-- AFTR, y la puerta lo valida con el mismo escáner de siempre: el QR sigue
-- siendo EVT:<evento>:<code> / LST:<evento>:<code>.
--
-- Los clientes NO son staff: viven en aftr_clientes, nunca en profiles, así
-- que rol_en_club() les da null y no ven nada de Venue. Todo lo que hacen
-- pasa por las RPC aftr_* (security definer) de este archivo.
--
-- El pago todavía no está definido: una compra crea una orden "pendiente"
-- y el boliche la confirma desde Venue (aftr_confirmar_orden), que es
-- quien emite las entradas. Cuando haya pasarela o comprobante, ese paso
-- llama a la misma confirmación.
--
-- Pasarle una entrada a un amigo cambia el dueño y ROTA el código: la
-- captura vieja deja de servir.
--
-- Re-ejecutable.

-- ── datos para el público ──────────────────────────────────────────────
alter table clubs add column if not exists direccion    text;
alter table clubs add column if not exists zona         text;
alter table clubs add column if not exists ciudad       text;
alter table clubs add column if not exists lat          double precision;
alter table clubs add column if not exists lng          double precision;
alter table clubs add column if not exists descripcion  text;
alter table clubs add column if not exists fotos        text[] not null default '{}';
alter table clubs add column if not exists aftr_visible boolean not null default false;

alter table eventos add column if not exists aftr_publico boolean not null default false;
alter table eventos add column if not exists descripcion  text;
alter table eventos add column if not exists generos      text[] not null default '{}';

-- qué listas se pueden pedir desde AFTR (las demás siguen siendo de los rrpp)
alter table lista_tipos add column if not exists aftr_publica boolean not null default false;

-- ── clientes ───────────────────────────────────────────────────────────
create table if not exists aftr_clientes (
  user_id    uuid primary key references auth.users (id) on delete cascade,
  usuario    text not null unique check (usuario ~ '^[a-z0-9_.]{3,24}$'),
  nombre     text not null check (length(trim(nombre)) between 1 and 60),
  foto_url   text,
  created_at timestamptz not null default now()
);
alter table aftr_clientes enable row level security;
drop policy if exists aftr_clientes_leer on aftr_clientes;
create policy aftr_clientes_leer on aftr_clientes for select to authenticated
  using (user_id = auth.uid());

-- ── dueño y canal de lo que se vende ───────────────────────────────────
alter table entradas  add column if not exists cliente_id uuid references aftr_clientes (user_id) on delete set null;
alter table registros add column if not exists cliente_id uuid references aftr_clientes (user_id) on delete set null;
alter table mesas     add column if not exists cliente_id uuid references aftr_clientes (user_id) on delete set null;
alter table entradas  add column if not exists canal text not null default 'venue';
alter table registros add column if not exists canal text not null default 'venue';
alter table mesas     add column if not exists canal text not null default 'venue';

-- lo vendido por AFTR no tiene rrpp: no paga comisión a nadie
alter table entradas  alter column rrpp_id drop not null;
alter table registros alter column rrpp_id drop not null;

do $$
begin
  if not exists (select 1 from pg_constraint where conname = 'entradas_canal_chk') then
    alter table entradas add constraint entradas_canal_chk
      check (canal in ('venue', 'aftr') and (rrpp_id is not null or canal = 'aftr'));
  end if;
  if not exists (select 1 from pg_constraint where conname = 'registros_canal_chk') then
    alter table registros add constraint registros_canal_chk
      check (canal in ('venue', 'aftr') and (rrpp_id is not null or canal = 'aftr'));
  end if;
  if not exists (select 1 from pg_constraint where conname = 'mesas_canal_chk') then
    alter table mesas add constraint mesas_canal_chk check (canal in ('venue', 'aftr'));
  end if;
end $$;

create index if not exists entradas_cliente_idx  on entradas  (cliente_id) where cliente_id is not null;
create index if not exists registros_cliente_idx on registros (cliente_id) where cliente_id is not null;
create index if not exists mesas_cliente_idx     on mesas     (cliente_id) where cliente_id is not null;
-- una persona, una vez por lista
create unique index if not exists registros_cliente_lista_uq
  on registros (lista_tipo_id, cliente_id) where cliente_id is not null;

-- el cliente ve lo suyo (también por realtime)
drop policy if exists entradas_cliente_leer on entradas;
create policy entradas_cliente_leer on entradas for select to authenticated
  using (cliente_id = auth.uid());
drop policy if exists registros_cliente_leer on registros;
create policy registros_cliente_leer on registros for select to authenticated
  using (cliente_id = auth.uid());
drop policy if exists mesas_cliente_leer on mesas;
create policy mesas_cliente_leer on mesas for select to authenticated
  using (cliente_id = auth.uid());

-- ── órdenes (el pago se enchufa acá) ───────────────────────────────────
create table if not exists aftr_ordenes (
  id             uuid primary key default gen_random_uuid(),
  cliente_id     uuid not null references aftr_clientes (user_id) on delete cascade,
  evento_id      uuid not null references eventos (id) on delete cascade,
  tipo           text not null check (tipo in ('entrada', 'mesa')),
  fase_id        uuid references evento_fase (id) on delete set null,
  mesa_id        uuid references mesas (id) on delete set null,
  combo_id       uuid,
  cantidad       int  not null default 1 check (cantidad between 1 and 10),
  precio_unit    int  not null default 0,
  total          int  not null default 0,
  estado         text not null default 'pendiente'
                 check (estado in ('pendiente', 'confirmada', 'cancelada', 'vencida')),
  vence_at       timestamptz,
  confirmada_por uuid,
  confirmada_at  timestamptz,
  created_at     timestamptz not null default now()
);
create index if not exists aftr_ordenes_evento_idx  on aftr_ordenes (evento_id, estado);
create index if not exists aftr_ordenes_cliente_idx on aftr_ordenes (cliente_id, created_at desc);
alter table aftr_ordenes enable row level security;
drop policy if exists aftr_ordenes_leer on aftr_ordenes;
create policy aftr_ordenes_leer on aftr_ordenes for select to authenticated
  using (cliente_id = auth.uid()
         or exists (select 1 from eventos e where e.id = evento_id
                     and rol_en_club(e.club_id) in ('admin', 'caja')));

create table if not exists aftr_transferencias (
  id         bigint generated always as identity primary key,
  entrada_id uuid not null references entradas (id) on delete cascade,
  de         uuid not null,
  para       uuid not null,
  created_at timestamptz not null default now()
);
alter table aftr_transferencias enable row level security;   -- sin políticas: solo RPC

create table if not exists aftr_siguiendo (
  cliente_id uuid not null references aftr_clientes (user_id) on delete cascade,
  club_id    text not null references clubs (id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (cliente_id, club_id)
);
create table if not exists aftr_guardados (
  cliente_id uuid not null references aftr_clientes (user_id) on delete cascade,
  evento_id  uuid not null references eventos (id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (cliente_id, evento_id)
);
alter table aftr_siguiendo enable row level security;
alter table aftr_guardados enable row level security;

do $$
begin
  if not exists (select 1 from pg_publication_tables
                  where pubname = 'supabase_realtime' and tablename = 'aftr_ordenes') then
    alter publication supabase_realtime add table aftr_ordenes;
  end if;
end $$;

-- ── ayudantes ──────────────────────────────────────────────────────────
create schema if not exists impl;

-- inicio y fin del evento en hora de Bolivia (el fin puede caer al día siguiente)
create or replace function impl.aftr_inicio(p_fecha date, p_hora time)
returns timestamptz language sql immutable
as $$ select (p_fecha + p_hora) at time zone 'America/La_Paz' $$;

create or replace function impl.aftr_fin(p_fecha date, p_inicio time, p_fin time)
returns timestamptz language sql immutable
as $$ select (p_fecha + p_fin + case when p_fin <= p_inicio then interval '1 day' else interval '0' end)
             at time zone 'America/La_Paz' $$;

-- el cliente que llama; sin perfil AFTR no hay nada que hacer
create or replace function impl.aftr_yo()
returns aftr_clientes language plpgsql stable security definer set search_path = public
as $$
declare c aftr_clientes;
begin
  if auth.uid() is null then
    raise exception 'Iniciá sesión.' using errcode = '28000';
  end if;
  select * into c from aftr_clientes where user_id = auth.uid();
  if not found then
    raise exception 'Completá tu perfil.' using errcode = 'P0002';
  end if;
  return c;
end;
$$;

-- el evento está a la vista del público
create or replace function impl.aftr_visible(p_evento uuid)
returns boolean language sql stable security definer set search_path = public
as $$
  select exists (
    select 1 from eventos e join clubs c on c.id = e.club_id
     where e.id = p_evento and e.publicado and e.aftr_publico
       and c.activo and c.aftr_visible and e.estado <> 'cerrado'
       and impl.aftr_fin(e.fecha, e.hora_inicio, e.hora_fin) > now())
$$;

-- órdenes vencidas: se marcan al pasar (no hay cron)
create or replace function impl.aftr_vencer(p_evento uuid default null, p_cliente uuid default null)
returns void language sql volatile security definer set search_path = public
as $$
  update aftr_ordenes set estado = 'vencida'
   where estado = 'pendiente' and vence_at < now()
     and (p_evento is null or evento_id = p_evento)
     and (p_cliente is null or cliente_id = p_cliente);
$$;

-- cuántas quedan en una fase: las vendidas y las órdenes pendientes ocupan cupo
create or replace function impl.aftr_quedan_fase(p_fase uuid)
returns int language sql stable security definer set search_path = public
as $$
  select case when f.cupo is null then null else greatest(0, f.cupo
           - (select count(*) from entradas x where x.fase_id = f.id)::int
           - coalesce((select sum(o.cantidad) from aftr_ordenes o
                        where o.fase_id = f.id and o.estado = 'pendiente'
                          and (o.vence_at is null or o.vence_at > now())), 0)::int) end
    from evento_fase f where f.id = p_fase
$$;

-- estado de cada fase como lo ve el público
create or replace function impl.aftr_estado_fase(f evento_fase)
returns text language sql stable security definer set search_path = public
as $$
  select case
           when not f.activo then 'cerrada'
           when f.hasta is not null and now() > f.hasta then 'cerrada'
           when f.desde is not null and now() < f.desde then 'proxima'
           when impl.aftr_quedan_fase(f.id) = 0 then 'agotada'
           else 'abierta' end
$$;

-- tarjeta de evento (lo mismo en la lista, el mapa y el lugar)
create or replace function impl.aftr_tarjeta(p_evento uuid)
returns jsonb language sql stable security definer set search_path = public
as $$
  select jsonb_build_object(
    'id', e.id, 'nombre', e.nombre, 'fecha', e.fecha,
    'hora_inicio', to_char(e.hora_inicio, 'HH24:MI'), 'hora_fin', to_char(e.hora_fin, 'HH24:MI'),
    'inicio', impl.aftr_inicio(e.fecha, e.hora_inicio),
    'edad_min', e.edad_min, 'flyer', coalesce(e.flyer_url, nullif(e.ticket_url, '')),
    'descripcion', e.descripcion, 'generos', e.generos,
    'desde_precio', case when e.venta_por_fases
                         then (select min(f.precio)::int from evento_fase f
                                where f.evento_id = e.id and impl.aftr_estado_fase(f) = 'abierta')
                         else e.precio_manilla end,
    'tiene_lista', exists (select 1 from lista_tipos l where l.evento_id = e.id and l.aftr_publica),
    'mesas_libres', (select count(*) from mesas m where m.evento_id = e.id and m.estado = 'disponible'),
    'club', jsonb_build_object('id', c.id, 'nombre', c.nombre, 'logo', c.logo_url,
                               'zona', c.zona, 'ciudad', c.ciudad, 'lat', c.lat, 'lng', c.lng,
                               'color', c.color_primario))
    from eventos e join clubs c on c.id = e.club_id
   where e.id = p_evento
$$;

-- ── lectura pública (sin sesión) ───────────────────────────────────────
create or replace function aftr_eventos(p_desde date default null, p_hasta date default null, p_ciudad text default null)
returns jsonb language sql stable security definer set search_path = public
as $$
  select coalesce(jsonb_agg(impl.aftr_tarjeta(e.id) order by e.fecha, e.hora_inicio), '[]'::jsonb)
    from eventos e join clubs c on c.id = e.club_id
   where impl.aftr_visible(e.id)
     and e.fecha >= coalesce(p_desde, (now() at time zone 'America/La_Paz')::date - 1)
     and e.fecha <= coalesce(p_hasta, (now() at time zone 'America/La_Paz')::date + 60)
     and (p_ciudad is null or c.ciudad ilike p_ciudad)
$$;

create or replace function aftr_evento(p_id uuid)
returns jsonb language plpgsql stable security definer set search_path = public
as $$
declare e eventos; v jsonb;
begin
  if not impl.aftr_visible(p_id) then
    return null;
  end if;
  select * into e from eventos where id = p_id;
  v := impl.aftr_tarjeta(p_id);
  v := v || jsonb_build_object(
    'venta_por_fases', e.venta_por_fases,
    'precio', e.precio_manilla,
    'venta_abierta', (e.manilla_desde is null or now() >= e.manilla_desde)
                     and (e.manilla_hasta_ts is null or now() <= e.manilla_hasta_ts),
    'fases', coalesce((select jsonb_agg(jsonb_build_object(
                 'id', f.id, 'nombre', f.nombre, 'precio', f.precio::int,
                 'estado', impl.aftr_estado_fase(f),
                 'quedan', case when impl.aftr_quedan_fase(f.id) <= 20 then impl.aftr_quedan_fase(f.id) end)
               order by f.orden)
               from evento_fase f where f.evento_id = p_id and f.activo), '[]'::jsonb),
    'listas', coalesce((select jsonb_agg(jsonb_build_object(
                 'id', l.id, 'nombre', l.nombre, 'precio', l.precio::int,
                 'hasta', to_char(l.ingreso_hasta, 'HH24:MI'),
                 'abierta', (l.registro_desde is null or now() >= l.registro_desde)
                            and (l.registro_hasta is null or now() <= l.registro_hasta)
                            and (l.cupo_total is null
                                 or (select count(*) from registros r where r.lista_tipo_id = l.id) < l.cupo_total))
               order by l.orden)
               from lista_tipos l where l.evento_id = p_id and l.aftr_publica), '[]'::jsonb),
    'mesas', coalesce((select jsonb_agg(jsonb_build_object(
                 'id', m.id, 'etiqueta', m.etiqueta, 'categoria', m.categoria, 'planta', m.planta)
               order by m.categoria, m.etiqueta)
               from mesas m where m.evento_id = p_id and m.estado = 'disponible' and m.grupo_id is null), '[]'::jsonb),
    'combos', coalesce((select jsonb_agg(jsonb_build_object(
                 'id', k.id, 'nombre', k.nombre, 'descripcion', k.descripcion, 'precio', k.precio,
                 'productos', k.productos, 'manillas', coalesce(k.incluye_manillas, 0),
                 'categorias', k.categorias)
               order by k.precio)
               from combos k where coalesce(k.activo, true)
                 and (k.club_id is null or k.club_id = e.club_id)), '[]'::jsonb),
    'combo_obligatorio', e.combo_obligatorio,
    'guardado', exists (select 1 from aftr_guardados g where g.evento_id = p_id and g.cliente_id = auth.uid()));
  return v;
end;
$$;

create or replace function aftr_lugares(p_ciudad text default null)
returns jsonb language sql stable security definer set search_path = public
as $$
  select coalesce(jsonb_agg(jsonb_build_object(
           'id', c.id, 'nombre', c.nombre, 'subtitulo', c.subtitulo, 'logo', c.logo_url,
           'fotos', c.fotos, 'zona', c.zona, 'ciudad', c.ciudad, 'lat', c.lat, 'lng', c.lng,
           'color', c.color_primario,
           'proximo', (select impl.aftr_tarjeta(e.id) from eventos e
                        where e.club_id = c.id and impl.aftr_visible(e.id)
                        order by e.fecha, e.hora_inicio limit 1))
         order by c.nombre), '[]'::jsonb)
    from clubs c
   where c.activo and c.aftr_visible
     and (p_ciudad is null or c.ciudad ilike p_ciudad)
$$;

create or replace function aftr_lugar(p_id text)
returns jsonb language sql stable security definer set search_path = public
as $$
  select jsonb_build_object(
           'id', c.id, 'nombre', c.nombre, 'subtitulo', c.subtitulo, 'logo', c.logo_url,
           'fotos', c.fotos, 'zona', c.zona, 'ciudad', c.ciudad, 'direccion', c.direccion,
           'descripcion', c.descripcion, 'lat', c.lat, 'lng', c.lng, 'color', c.color_primario,
           'siguiendo', exists (select 1 from aftr_siguiendo s where s.club_id = c.id and s.cliente_id = auth.uid()),
           'eventos', coalesce((select jsonb_agg(impl.aftr_tarjeta(e.id) order by e.fecha, e.hora_inicio)
                                  from eventos e where e.club_id = c.id and impl.aftr_visible(e.id)), '[]'::jsonb))
    from clubs c
   where c.id = p_id and c.activo and c.aftr_visible
$$;

-- ── cuenta ─────────────────────────────────────────────────────────────
create or replace function aftr_mi_perfil()
returns jsonb language sql stable security definer set search_path = public
as $$
  select to_jsonb(c) from aftr_clientes c where c.user_id = auth.uid()
$$;

create or replace function aftr_crear_perfil(p_usuario text, p_nombre text)
returns jsonb language plpgsql volatile security definer set search_path = public
as $$
declare v_usuario text := lower(trim(p_usuario)); c aftr_clientes;
begin
  if auth.uid() is null then
    raise exception 'Iniciá sesión.' using errcode = '28000';
  end if;
  if v_usuario !~ '^[a-z0-9_.]{3,24}$' then
    raise exception 'El usuario lleva de 3 a 24 letras, números, punto o guion bajo.';
  end if;
  if exists (select 1 from aftr_clientes where usuario = v_usuario and user_id <> auth.uid()) then
    raise exception 'Ese usuario ya está tomado.' using errcode = '23505';
  end if;
  insert into aftr_clientes (user_id, usuario, nombre)
  values (auth.uid(), v_usuario, trim(p_nombre))
  on conflict (user_id) do update set usuario = excluded.usuario, nombre = excluded.nombre
  returning * into c;
  return to_jsonb(c);
end;
$$;

create or replace function aftr_buscar_usuario(p_q text)
returns jsonb language plpgsql stable security definer set search_path = public
as $$
declare v_q text := lower(trim(both '@ ' from coalesce(p_q, '')));
begin
  perform impl.aftr_yo();
  if length(v_q) < 2 then
    return '[]'::jsonb;
  end if;
  return coalesce((select jsonb_agg(jsonb_build_object('usuario', c.usuario, 'nombre', c.nombre, 'foto', c.foto_url))
                     from (select * from aftr_clientes
                            where user_id <> auth.uid()
                              and (usuario like v_q || '%' or lower(nombre) like '%' || v_q || '%')
                            order by usuario = v_q desc, usuario limit 10) c), '[]'::jsonb);
end;
$$;

-- borra la cuenta AFTR (lo pide la App Store). Si la misma persona es staff
-- de Venue, el usuario de auth queda: solo se va su perfil de cliente.
create or replace function aftr_eliminar_cuenta()
returns void language plpgsql volatile security definer set search_path = public
as $$
declare v_uid uuid := auth.uid();
begin
  perform impl.aftr_yo();
  update mesas set cliente_id = null where cliente_id = v_uid;
  delete from aftr_clientes where user_id = v_uid;
  if not exists (select 1 from profiles where id = v_uid) then
    delete from auth.users where id = v_uid;
  end if;
end;
$$;

create or replace function aftr_seguir(p_club text)
returns boolean language plpgsql volatile security definer set search_path = public
as $$
declare c aftr_clientes := impl.aftr_yo();
begin
  if exists (select 1 from aftr_siguiendo where cliente_id = c.user_id and club_id = p_club) then
    delete from aftr_siguiendo where cliente_id = c.user_id and club_id = p_club;
    return false;
  end if;
  insert into aftr_siguiendo (cliente_id, club_id)
  select c.user_id, x.id from clubs x where x.id = p_club and x.aftr_visible;
  return found;
end;
$$;

create or replace function aftr_guardar(p_evento uuid)
returns boolean language plpgsql volatile security definer set search_path = public
as $$
declare c aftr_clientes := impl.aftr_yo();
begin
  if exists (select 1 from aftr_guardados where cliente_id = c.user_id and evento_id = p_evento) then
    delete from aftr_guardados where cliente_id = c.user_id and evento_id = p_evento;
    return false;
  end if;
  if not impl.aftr_visible(p_evento) then
    raise exception 'Evento no disponible.';
  end if;
  insert into aftr_guardados (cliente_id, evento_id) values (c.user_id, p_evento);
  return true;
end;
$$;

create or replace function aftr_mis_guardados()
returns jsonb language sql stable security definer set search_path = public
as $$
  select jsonb_build_object(
    'eventos', coalesce((select jsonb_agg(impl.aftr_tarjeta(g.evento_id) order by g.created_at desc)
                           from aftr_guardados g where g.cliente_id = auth.uid()
                            and impl.aftr_visible(g.evento_id)), '[]'::jsonb),
    'lugares', coalesce((select jsonb_agg(jsonb_build_object('id', c.id, 'nombre', c.nombre,
                                  'logo', c.logo_url, 'zona', c.zona, 'fotos', c.fotos) order by c.nombre)
                           from aftr_siguiendo s join clubs c on c.id = s.club_id
                          where s.cliente_id = auth.uid()), '[]'::jsonb))
$$;

-- ── comprar, reservar, anotarse ────────────────────────────────────────
create or replace function aftr_comprar(p_evento uuid, p_fase uuid, p_cantidad int)
returns jsonb language plpgsql volatile security definer set search_path = public
as $$
declare
  c aftr_clientes := impl.aftr_yo();
  e eventos; f evento_fase; o aftr_ordenes;
  v_precio int; v_quedan int;
begin
  if p_cantidad is null or p_cantidad < 1 or p_cantidad > 10 then
    raise exception 'Podés comprar de 1 a 10 entradas.';
  end if;
  if not impl.aftr_visible(p_evento) then
    raise exception 'Este evento no está a la venta.';
  end if;
  select * into e from eventos where id = p_evento;
  perform impl.aftr_vencer(p_evento);
  if (select count(*) from aftr_ordenes where cliente_id = c.user_id and evento_id = p_evento
        and estado = 'pendiente') >= 3 then
    raise exception 'Ya tenés pedidos pendientes para este evento.';
  end if;

  if e.venta_por_fases then
    select * into f from evento_fase where id = p_fase and evento_id = p_evento for update;
    if not found or impl.aftr_estado_fase(f) <> 'abierta' then
      raise exception 'Esa fase no está a la venta.';
    end if;
    v_quedan := impl.aftr_quedan_fase(f.id);
    if v_quedan is not null and v_quedan < p_cantidad then
      raise exception 'Quedan % en esta fase.', v_quedan;
    end if;
    v_precio := f.precio::int;
  else
    if (e.manilla_desde is not null and now() < e.manilla_desde)
       or (e.manilla_hasta_ts is not null and now() > e.manilla_hasta_ts) then
      raise exception 'La venta de entradas está cerrada.';
    end if;
    v_precio := e.precio_manilla;
  end if;

  insert into aftr_ordenes (cliente_id, evento_id, tipo, fase_id, cantidad, precio_unit, total, vence_at)
  values (c.user_id, p_evento, 'entrada', case when e.venta_por_fases then f.id end, p_cantidad,
          v_precio, v_precio * p_cantidad,
          least(now() + interval '12 hours', impl.aftr_inicio(e.fecha, e.hora_inicio)))
  returning * into o;
  return to_jsonb(o);
end;
$$;

create or replace function aftr_reservar_mesa(p_evento uuid, p_mesa uuid, p_combo uuid default null)
returns jsonb language plpgsql volatile security definer set search_path = public
as $$
declare
  c aftr_clientes := impl.aftr_yo();
  e eventos; m mesas; k combos; o aftr_ordenes;
  v_precio int; v_vence timestamptz;
begin
  if not impl.aftr_visible(p_evento) then
    raise exception 'Este evento no está a la venta.';
  end if;
  select * into e from eventos where id = p_evento;
  select * into m from mesas where id = p_mesa and evento_id = p_evento for update;
  if not found or m.estado <> 'disponible' or m.grupo_id is not null then
    raise exception 'Esa mesa ya no está disponible.';
  end if;
  if exists (select 1 from aftr_ordenes where cliente_id = c.user_id and evento_id = p_evento
              and tipo = 'mesa' and estado = 'pendiente') then
    raise exception 'Ya tenés una reserva de mesa pendiente en este evento.';
  end if;
  if p_combo is not null then
    select * into k from combos where id = p_combo and coalesce(activo, true)
       and (club_id is null or club_id = e.club_id);
    if not found then
      raise exception 'Ese combo no está disponible.';
    end if;
    if coalesce(array_length(k.categorias, 1), 0) > 0 and not (m.categoria = any (k.categorias)) then
      raise exception 'Ese combo no corresponde a esta mesa.';
    end if;
  elsif e.combo_obligatorio then
    raise exception 'Elegí un combo para la mesa.';
  end if;
  v_precio := coalesce(k.precio, m.precio, 0);
  v_vence := least(now() + make_interval(hours => coalesce(e.horas_reserva, 3)),
                   impl.aftr_inicio(e.fecha, e.hora_inicio));

  update mesas set estado = 'reservada', cliente = c.nombre, cliente_id = c.user_id, canal = 'aftr',
                   combo_id = k.id, combo_qty = 1, precio = v_precio,
                   manillas = coalesce(k.incluye_manillas, 0),
                   reservada_at = now(), reserva_vence_at = v_vence, vendido_por = null,
                   updated_at = now()
   where id = m.id;

  insert into aftr_ordenes (cliente_id, evento_id, tipo, mesa_id, combo_id, cantidad, precio_unit, total, vence_at)
  values (c.user_id, p_evento, 'mesa', m.id, k.id, 1, v_precio, v_precio, v_vence)
  returning * into o;
  return to_jsonb(o) || jsonb_build_object('mesa', m.etiqueta);
end;
$$;

create or replace function aftr_anotarme_lista(p_evento uuid, p_lista uuid)
returns jsonb language plpgsql volatile security definer set search_path = public
as $$
declare
  c aftr_clientes := impl.aftr_yo();
  l lista_tipos; r registros;
begin
  if not impl.aftr_visible(p_evento) then
    raise exception 'Este evento no está disponible.';
  end if;
  select * into l from lista_tipos where id = p_lista and evento_id = p_evento and aftr_publica for update;
  if not found then
    raise exception 'Esa lista no existe.';
  end if;
  if (l.registro_desde is not null and now() < l.registro_desde)
     or (l.registro_hasta is not null and now() > l.registro_hasta) then
    raise exception 'La lista está cerrada.';
  end if;
  select * into r from registros where lista_tipo_id = l.id and cliente_id = c.user_id;
  if found then
    return jsonb_build_object('id', r.id, 'code', r.code, 'qr', 'LST:' || p_evento || ':' || r.code, 'ya', true);
  end if;
  if l.cupo_total is not null
     and (select count(*) from registros x where x.lista_tipo_id = l.id) >= l.cupo_total then
    raise exception 'La lista se llenó.';
  end if;
  insert into registros (id, evento_id, lista_tipo_id, nombre, rrpp_id, created_at, code, cliente_id, canal)
  values (gen_random_uuid(), p_evento, l.id, c.nombre, null, now(), gen_code_evento(p_evento), c.user_id, 'aftr')
  returning * into r;
  return jsonb_build_object('id', r.id, 'code', r.code, 'qr', 'LST:' || p_evento || ':' || r.code, 'ya', false);
end;
$$;

create or replace function aftr_cancelar_mi_orden(p_orden uuid)
returns void language plpgsql volatile security definer set search_path = public
as $$
declare c aftr_clientes := impl.aftr_yo(); o aftr_ordenes;
begin
  select * into o from aftr_ordenes where id = p_orden and cliente_id = c.user_id for update;
  if not found or o.estado <> 'pendiente' then
    raise exception 'Ese pedido ya no se puede cancelar.';
  end if;
  update aftr_ordenes set estado = 'cancelada' where id = o.id;
  if o.tipo = 'mesa' then
    perform mesa_limpiar(o.mesa_id) from mesas
      where id = o.mesa_id and cliente_id = c.user_id and estado = 'reservada';
  end if;
end;
$$;

-- todo lo que el cliente tiene: la billetera
create or replace function aftr_mis_accesos()
returns jsonb language plpgsql volatile security definer set search_path = public
as $$
declare c aftr_clientes := impl.aftr_yo();
begin
  perform impl.aftr_vencer(null, c.user_id);
  return jsonb_build_object(
    'entradas', coalesce((select jsonb_agg(jsonb_build_object(
        'id', x.id, 'code', x.code, 'qr', 'EVT:' || x.evento_id || ':' || x.code,
        'estado', x.estado, 'precio', x.precio, 'usada_at', x.used_at,
        'fase', f.nombre, 'mesa', m.etiqueta,
        'transferible', x.estado = 'valida' and impl.aftr_fin(e.fecha, e.hora_inicio, e.hora_fin) > now(),
        'evento', impl.aftr_tarjeta(x.evento_id))
      order by e.fecha desc, x.created_at)
      from entradas x join eventos e on e.id = x.evento_id
      left join evento_fase f on f.id = x.fase_id
      left join mesas m on m.id = x.mesa_id
      where x.cliente_id = c.user_id), '[]'::jsonb),
    'listas', coalesce((select jsonb_agg(jsonb_build_object(
        'id', r.id, 'code', r.code, 'qr', 'LST:' || r.evento_id || ':' || r.code,
        'estado', case when r.qr_anulado then 'anulada' when r.ingreso_at is not null then 'usada' else 'valida' end,
        'lista', l.nombre, 'hasta', to_char(l.ingreso_hasta, 'HH24:MI'),
        'evento', impl.aftr_tarjeta(r.evento_id))
      order by e.fecha desc)
      from registros r join lista_tipos l on l.id = r.lista_tipo_id join eventos e on e.id = r.evento_id
      where r.cliente_id = c.user_id), '[]'::jsonb),
    'mesas', coalesce((select jsonb_agg(jsonb_build_object(
        'id', m.id, 'etiqueta', m.etiqueta, 'categoria', m.categoria, 'estado', m.estado,
        'precio', m.precio, 'combo', k.nombre, 'manillas', m.manillas, 'vence_at', m.reserva_vence_at,
        'evento', impl.aftr_tarjeta(m.evento_id))
      order by e.fecha desc)
      from mesas m join eventos e on e.id = m.evento_id left join combos k on k.id = m.combo_id
      where m.cliente_id = c.user_id), '[]'::jsonb),
    'ordenes', coalesce((select jsonb_agg(jsonb_build_object(
        'id', o.id, 'tipo', o.tipo, 'estado', o.estado, 'cantidad', o.cantidad, 'total', o.total,
        'vence_at', o.vence_at, 'created_at', o.created_at, 'fase', f.nombre, 'mesa', m.etiqueta,
        'evento', impl.aftr_tarjeta(o.evento_id))
      order by o.created_at desc)
      from aftr_ordenes o left join evento_fase f on f.id = o.fase_id left join mesas m on m.id = o.mesa_id
      where o.cliente_id = c.user_id and o.estado = 'pendiente'), '[]'::jsonb));
end;
$$;

-- ── pasar una entrada a un amigo ───────────────────────────────────────
create or replace function aftr_transferir(p_entrada uuid, p_usuario text)
returns jsonb language plpgsql volatile security definer set search_path = public
as $$
declare
  c aftr_clientes := impl.aftr_yo();
  x entradas; e eventos; d aftr_clientes;
begin
  select * into x from entradas where id = p_entrada and cliente_id = c.user_id for update;
  if not found then
    raise exception 'Esa entrada no es tuya.' using errcode = '42501';
  end if;
  if x.estado <> 'valida' then
    raise exception 'Esa entrada ya no se puede pasar.';
  end if;
  select * into e from eventos where id = x.evento_id;
  if impl.aftr_fin(e.fecha, e.hora_inicio, e.hora_fin) <= now() then
    raise exception 'El evento ya terminó.';
  end if;
  select * into d from aftr_clientes where usuario = lower(trim(both '@ ' from p_usuario));
  if not found then
    raise exception 'No encontramos a @%.', lower(trim(both '@ ' from p_usuario));
  end if;
  if d.user_id = c.user_id then
    raise exception 'Ya es tuya.';
  end if;
  update entradas set cliente_id = d.user_id, cliente = d.nombre, code = gen_code_evento(x.evento_id)
   where id = x.id;
  insert into aftr_transferencias (entrada_id, de, para) values (x.id, c.user_id, d.user_id);
  return jsonb_build_object('para', d.usuario, 'nombre', d.nombre);
end;
$$;

-- ── Venue: los pedidos que llegan de AFTR ──────────────────────────────
create or replace function impl.aftr_staff_orden(p_orden uuid)
returns aftr_ordenes language plpgsql volatile security definer set search_path = public
as $$
declare o aftr_ordenes; v_club text;
begin
  select * into o from aftr_ordenes where id = p_orden for update;
  if not found then
    raise exception 'Pedido no encontrado.';
  end if;
  select club_id into v_club from eventos where id = o.evento_id;
  if rol_en_club(v_club) is distinct from 'admin' and rol_en_club(v_club) is distinct from 'caja' then
    raise exception 'No autorizado.' using errcode = '42501';
  end if;
  return o;
end;
$$;

create or replace function aftr_ordenes_evento(p_evento uuid)
returns jsonb language plpgsql volatile security definer set search_path = public
as $$
begin
  if coalesce(rol_en_club((select club_id from eventos where id = p_evento)), '') not in ('admin', 'caja') then
    raise exception 'No autorizado.' using errcode = '42501';
  end if;
  perform impl.aftr_vencer(p_evento);
  return coalesce((select jsonb_agg(jsonb_build_object(
      'id', o.id, 'tipo', o.tipo, 'estado', o.estado, 'cantidad', o.cantidad,
      'precio_unit', o.precio_unit, 'total', o.total, 'vence_at', o.vence_at,
      'created_at', o.created_at, 'confirmada_at', o.confirmada_at,
      'fase', f.nombre, 'mesa', m.etiqueta, 'combo', k.nombre,
      'cliente', c.nombre, 'usuario', c.usuario)
    order by (o.estado = 'pendiente') desc, o.created_at desc)
    from aftr_ordenes o join aftr_clientes c on c.user_id = o.cliente_id
    left join evento_fase f on f.id = o.fase_id
    left join mesas m on m.id = o.mesa_id
    left join combos k on k.id = o.combo_id
    where o.evento_id = p_evento), '[]'::jsonb);
end;
$$;

-- confirmar = está pago. Emite las entradas (o las manillas de la mesa) a
-- nombre del cliente. La pasarela, cuando exista, llama a esto mismo.
create or replace function aftr_confirmar_orden(p_orden uuid)
returns jsonb language plpgsql volatile security definer set search_path = public
as $$
declare
  o aftr_ordenes := impl.aftr_staff_orden(p_orden);
  c aftr_clientes; m mesas; v_n int;
begin
  if o.estado <> 'pendiente' then
    raise exception 'Este pedido ya está %.', o.estado;
  end if;
  select * into c from aftr_clientes where user_id = o.cliente_id;

  if o.tipo = 'entrada' then
    insert into entradas (id, evento_id, code, cliente, rrpp_id, precio, estado, created_at, fase_id, cliente_id, canal)
    select gen_random_uuid(), o.evento_id, gen_code_evento(o.evento_id), c.nombre, null, o.precio_unit,
           'valida', now(), o.fase_id, c.user_id, 'aftr'
      from generate_series(1, o.cantidad);
    v_n := o.cantidad;
  else
    select * into m from mesas where id = o.mesa_id for update;
    if not found or m.cliente_id is distinct from o.cliente_id or m.estado <> 'reservada' then
      raise exception 'La reserva de esta mesa ya no está vigente.';
    end if;
    update mesas set estado = 'pagada', pagada_por = auth.uid(), pagada_at = now(),
                     pago_verificado = true, verificado_por = auth.uid(), verificado_at = now(),
                     reserva_vence_at = null, updated_at = now()
     where id = m.id;
    insert into entradas (id, evento_id, code, cliente, rrpp_id, precio, estado, created_at, mesa_id, cliente_id, canal)
    select gen_random_uuid(), o.evento_id, gen_code_evento(o.evento_id), c.nombre, null, 0,
           'valida', now(), m.id, c.user_id, 'aftr'
      from generate_series(1, m.manillas);
    v_n := m.manillas;
  end if;

  update aftr_ordenes set estado = 'confirmada', confirmada_por = auth.uid(), confirmada_at = now()
   where id = o.id;
  return jsonb_build_object('emitidas', v_n);
end;
$$;

create or replace function aftr_cancelar_orden(p_orden uuid)
returns void language plpgsql volatile security definer set search_path = public
as $$
declare o aftr_ordenes := impl.aftr_staff_orden(p_orden);
begin
  if o.estado <> 'pendiente' then
    raise exception 'Este pedido ya está %.', o.estado;
  end if;
  update aftr_ordenes set estado = 'cancelada' where id = o.id;
  if o.tipo = 'mesa' then
    perform mesa_limpiar(o.mesa_id) from mesas
      where id = o.mesa_id and cliente_id = o.cliente_id and estado = 'reservada';
  end if;
end;
$$;

-- Una mesa que vuelve a disponible (venció, se liberó o se canceló) deja de
-- ser del cliente, y su pedido pendiente vence.
create or replace function aftr_mesa_liberada()
returns trigger language plpgsql security definer set search_path = public
as $$
begin
  if new.estado = 'disponible' and old.estado <> 'disponible' and old.cliente_id is not null then
    new.cliente_id := null;
    new.canal := 'venue';
    update aftr_ordenes set estado = 'vencida'
     where mesa_id = new.id and estado = 'pendiente';
  end if;
  return new;
end;
$$;
drop trigger if exists aftr_mesa_liberada on mesas;
create trigger aftr_mesa_liberada before update of estado on mesas
  for each row execute function aftr_mesa_liberada();

-- ── permisos ───────────────────────────────────────────────────────────
revoke all on function impl.aftr_inicio(date, time), impl.aftr_fin(date, time, time),
  impl.aftr_yo(), impl.aftr_visible(uuid), impl.aftr_vencer(uuid, uuid),
  impl.aftr_quedan_fase(uuid), impl.aftr_estado_fase(evento_fase), impl.aftr_tarjeta(uuid),
  impl.aftr_staff_orden(uuid)
  from public, anon, authenticated;
revoke all on function aftr_mesa_liberada() from public, anon, authenticated;

revoke all on function
  aftr_eventos(date, date, text), aftr_evento(uuid), aftr_lugares(text), aftr_lugar(text),
  aftr_mi_perfil(), aftr_crear_perfil(text, text), aftr_buscar_usuario(text), aftr_eliminar_cuenta(),
  aftr_seguir(text), aftr_guardar(uuid), aftr_mis_guardados(),
  aftr_comprar(uuid, uuid, int), aftr_reservar_mesa(uuid, uuid, uuid), aftr_anotarme_lista(uuid, uuid),
  aftr_cancelar_mi_orden(uuid), aftr_mis_accesos(), aftr_transferir(uuid, text),
  aftr_ordenes_evento(uuid), aftr_confirmar_orden(uuid), aftr_cancelar_orden(uuid)
  from public, anon;

-- se puede mirar sin cuenta
grant execute on function aftr_eventos(date, date, text), aftr_evento(uuid),
  aftr_lugares(text), aftr_lugar(text) to anon, authenticated;
grant execute on function
  aftr_mi_perfil(), aftr_crear_perfil(text, text), aftr_buscar_usuario(text), aftr_eliminar_cuenta(),
  aftr_seguir(text), aftr_guardar(uuid), aftr_mis_guardados(),
  aftr_comprar(uuid, uuid, int), aftr_reservar_mesa(uuid, uuid, uuid), aftr_anotarme_lista(uuid, uuid),
  aftr_cancelar_mi_orden(uuid), aftr_mis_accesos(), aftr_transferir(uuid, text),
  aftr_ordenes_evento(uuid), aftr_confirmar_orden(uuid), aftr_cancelar_orden(uuid)
  to authenticated;

grant select on aftr_clientes, aftr_ordenes to authenticated;

-- el asesor de Supabase pide search_path fijo también en las SQL puras
alter function impl.aftr_inicio(date, time) set search_path = public;
alter function impl.aftr_fin(date, time, time) set search_path = public;
