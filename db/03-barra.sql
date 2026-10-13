-- MÓDULO BARRA completo · tablas, vistas y RPCs (fases 1-3).
--
-- ETAPA 1: paridad. Nada de mejoras acá.
--
-- EVIDENCIA (2026-08-20): las 11 tablas EXISTEN en el origen con las
-- columnas verificadas por sondeo REST (todas vacías: el módulo nunca se
-- usó en producción). bar_cortesia_cupo (club_id, user_id, cupo) apareció
-- por un hint. Las RPCs de fase 1-2 existen en el origen (verificado por
-- hint sin ejecutarlas) y devuelven [] con las tablas vacías (capturado);
-- las de fase 3 (bar_conteo_pendiente, bar_conteo_masivo) NO existen allá:
-- app.js es la única especificación. Los textos de error de negocio están
-- citados EN el cliente: el regex /no hay stock/i (app.js:7596) y el
-- literal 'CUPO AGOTADO' (app.js:7592) son fragmentos del mensaje real.
--
-- SUPUESTOS estructurales (documentados en cada lugar): bar_ventas.estado
-- guarda la forma de pago ('efectivo'/'qr'/'cortesia') y 'anulada' — es la
-- única columna sondeada que puede cumplir ese rol; el origen no mostró
-- ninguna columna para p_client_key, pero el contrato del cliente EXIGE
-- idempotencia (cola offline con reintento), así que se agrega client_key
-- único; el vínculo venta→movimientos va en stock_mov.motivo ('venta:<id>')
-- porque stock_mov no tiene venta_id; el formato del código de lote
-- autogenerado es inventado (el real nunca se generó).

-- ============================================================
-- TABLAS (columnas verificadas contra el origen por sondeo)
-- ============================================================
create table if not exists bar_categorias (
  id     uuid primary key default gen_random_uuid(),
  nombre text not null,
  orden  int not null default 0,
  activo boolean not null default true
);

create table if not exists bebidas (
  id           uuid primary key default gen_random_uuid(),
  club_id      text not null references clubs(id),
  categoria_id uuid references bar_categorias(id),
  nombre       text not null,
  volumen_ml   int not null,
  unidad       text not null default 'botella',
  umbral_bajo  int,
  activo       boolean not null default true,
  created_at   timestamptz not null default now(),
  unique (club_id, nombre)          -- la UI traduce el 23505 a "Ya tenés una bebida llamada..."
);

create table if not exists barras (
  id      uuid primary key default gen_random_uuid(),
  club_id text not null references clubs(id),
  nombre  text not null,
  planta  int not null default 1,
  activo  boolean not null default true,
  unique (club_id, nombre)          -- 23505 -> "Ya existe una barra con ese nombre"
);

create table if not exists lotes (
  id             uuid primary key default gen_random_uuid(),
  bebida_id      uuid not null references bebidas(id),
  club_id        text references clubs(id),
  codigo         text not null,
  cant_inicial   int not null,
  volumen_ml     int not null,
  ml_actual      numeric not null,
  costo_unitario numeric,
  recibido_at    timestamptz not null default now(),
  recibido_por   uuid default auth.uid(),
  notas          text
);

create table if not exists tragos (
  id           uuid primary key default gen_random_uuid(),
  club_id      text not null references clubs(id),
  nombre       text not null,
  precio_venta numeric not null,
  barra_id     uuid references barras(id),
  activo       boolean not null default false,   -- "se activa recién cuando tiene receta"
  orden        int not null default 0,
  created_at   timestamptz not null default now()
);

create table if not exists receta_items (
  id        uuid primary key default gen_random_uuid(),
  trago_id  uuid not null references tragos(id) on delete cascade,
  bebida_id uuid not null references bebidas(id),
  ml        numeric not null,
  unique (trago_id, bebida_id)      -- 23505 -> "Esa bebida ya está en la receta"
);

create table if not exists bar_staff (
  evento_id uuid not null references eventos(id),
  barra_id  uuid not null references barras(id),
  user_id   uuid not null references profiles(id),
  primary key (evento_id, barra_id, user_id)
);

create table if not exists bar_cortesia_config (
  club_id      text primary key references clubs(id),
  cupo_default int not null default 0,
  updated_at   timestamptz not null default now()
);

create table if not exists bar_cortesia_cupo (
  club_id text not null references clubs(id),
  user_id uuid not null references profiles(id),
  cupo    int not null,
  primary key (club_id, user_id)
);

create table if not exists bar_ventas (
  id          uuid primary key default gen_random_uuid(),
  club_id     text references clubs(id),
  evento_id   uuid not null references eventos(id),
  barra_id    uuid not null references barras(id),
  total       numeric not null default 0,
  cortesia_de uuid references profiles(id),
  estado      text not null,                  -- 'efectivo' | 'qr' | 'cortesia' | 'anulada' (SUPUESTO)
  client_key  text unique,                    -- idempotencia de la cola offline (contrato del cliente)
  created_at  timestamptz not null default now()
);

create table if not exists bar_venta_items (
  id          uuid primary key default gen_random_uuid(),
  venta_id    uuid not null references bar_ventas(id) on delete cascade,
  trago_id    uuid not null references tragos(id),
  qty         int not null,
  precio_unit numeric not null
);

create table if not exists stock_mov (
  id         uuid primary key default gen_random_uuid(),
  club_id    text references clubs(id),
  bebida_id  uuid not null references bebidas(id),
  lote_id    uuid references lotes(id),
  tipo       text not null,        -- entrada | salida | ajuste | baja | anulacion (íconos de la UI)
  ml_delta   numeric not null,
  costo      numeric,
  motivo     text,
  evento_id  uuid,
  barra_id   uuid,
  creado_por uuid default auth.uid(),
  created_at timestamptz not null default now()
);

/* fase 3 · conteos de apertura/cierre — NO existe en el origen: deducida
 * de screenBarConteo/bar_conteo_pendiente en app.js */
create table if not exists bar_conteos (
  evento_id  uuid not null references eventos(id),
  momento    text not null,        -- 'apertura' | 'cierre'
  lote_id    uuid not null references lotes(id),
  ml_contado numeric not null,
  creado_por uuid default auth.uid(),
  created_at timestamptz not null default now(),
  primary key (evento_id, momento, lote_id)
);

-- ============================================================
-- VISTAS (contratos tomados de las pantallas que las consumen)
-- ============================================================
create or replace view v_bar_stock as
select b.id as bebida_id, b.club_id, b.nombre, c.nombre as categoria,
       b.volumen_ml, b.umbral_bajo as umbral,
       coalesce(s.ml, 0) as ml_total,
       coalesce(s.ml, 0) / nullif(b.volumen_ml, 0) as botellas_equiv,
       coalesce(s.abiertos, 0) as lotes_abiertos,
       coalesce(s.valor, 0) as valor_bs,
       (b.umbral_bajo is not null
        and coalesce(s.ml, 0) / nullif(b.volumen_ml, 0) < b.umbral_bajo) as bajo_stock
  from bebidas b
  left join bar_categorias c on c.id = b.categoria_id
  left join lateral (
    select sum(l.ml_actual) as ml,
           count(*) filter (where l.ml_actual > 0) as abiertos,
           sum(l.ml_actual * coalesce(l.costo_unitario, 0) / nullif(l.volumen_ml, 0)) as valor
      from lotes l where l.bebida_id = b.id
  ) s on true
 where b.activo;

create or replace view v_bar_movimientos as
select m.club_id, m.created_at, m.tipo, m.motivo, m.ml_delta, coalesce(m.costo, 0) as costo,
       b.nombre as bebida, p.nombre as quien
  from stock_mov m
  join bebidas b on b.id = m.bebida_id
  left join profiles p on p.id = m.creado_por;

create or replace view v_bar_cierre as
select v.evento_id, br.nombre as barra,
       sum(v.total) filter (where v.estado <> 'anulada') as bs,
       coalesce(sum(i.qty) filter (where v.estado <> 'anulada'), 0) as tragos,
       count(distinct v.id) filter (where v.estado <> 'anulada') as ventas,
       coalesce(sum(i.qty) filter (where v.estado <> 'anulada' and v.cortesia_de is not null), 0) as cortesias
  from bar_ventas v
  join barras br on br.id = v.barra_id
  left join bar_venta_items i on i.venta_id = v.id
 group by v.evento_id, br.nombre;

create or replace view v_bar_evento as
select v.evento_id,
       coalesce(sum(i.qty) filter (where v.estado <> 'anulada'), 0) as vasos,
       count(distinct v.id) filter (where v.estado <> 'anulada') as pedidos,
       coalesce(sum(v.total) filter (where v.estado <> 'anulada'), 0) as ingresos,
       round(coalesce(sum(v.total) filter (where v.estado <> 'anulada'), 0)
             / nullif(count(distinct v.id) filter (where v.estado <> 'anulada' and v.cortesia_de is null), 0)) as ticket_promedio,
       count(distinct v.barra_id) filter (where v.estado <> 'anulada') as barras_activas,
       coalesce(sum(i.qty) filter (where v.estado <> 'anulada' and v.cortesia_de is not null), 0) as vasos_cortesia
  from bar_ventas v
  left join bar_venta_items i on i.venta_id = v.id
 group by v.evento_id;

create or replace view v_bar_por_barra as
select c.evento_id, c.barra, c.tragos as vasos, c.ventas as pedidos, c.bs as ingresos,
       round(c.bs / nullif(c.ventas, 0)) as ticket_promedio,
       round(c.bs * 100 / nullif(e.ingresos, 0)) as pct_del_evento
  from v_bar_cierre c
  join v_bar_evento e on e.evento_id = c.evento_id;

/* costo de lo servido: los movimientos 'salida' de ventas no anuladas del
 * evento (las anuladas quedan netas por su 'anulacion' espejo). */
create or replace view v_bar_costos_evento as
select m.evento_id,
       sum(coalesce(m.costo, 0)) filter (where m.tipo in ('salida')) as costo_salidas,
       sum(coalesce(m.costo, 0)) filter (where m.tipo = 'anulacion') as costo_devuelto,
       sum(coalesce(m.costo, 0)) filter (where m.tipo = 'salida' and exists (
         select 1 from bar_ventas v where 'venta:' || v.id::text = m.motivo and v.cortesia_de is not null
       )) as costo_cortesias
  from stock_mov m
 where m.evento_id is not null
 group by m.evento_id;

/* fase 3 · merma = (apertura − cierre) − lo explicado entre medio
 * (salidas−anulaciones+bajas−ajustes), valuado al costo medio del lote.
 * RECONSTRUCCIÓN PURA: no existe en el origen. */
create or replace view v_bar_merma as
select ap.evento_id, b.nombre as bebida,
       round((ap.ml - ci.ml - coalesce(mv.explicado, 0)) / nullif(b.volumen_ml, 0), 1) as merma_botellas,
       round((ap.ml - ci.ml - coalesce(mv.explicado, 0)) * 100 / nullif(coalesce(mv.servido, 0), 0)) as merma_pct,
       round((ap.ml - ci.ml - coalesce(mv.explicado, 0)) * coalesce(cu.costo_ml, 0)) as merma_bs
  from (select c.evento_id, l.bebida_id, sum(c.ml_contado) as ml
          from bar_conteos c join lotes l on l.id = c.lote_id
         where c.momento = 'apertura' group by c.evento_id, l.bebida_id) ap
  join (select c.evento_id, l.bebida_id, sum(c.ml_contado) as ml
          from bar_conteos c join lotes l on l.id = c.lote_id
         where c.momento = 'cierre' group by c.evento_id, l.bebida_id) ci
    on ci.evento_id = ap.evento_id and ci.bebida_id = ap.bebida_id
  join bebidas b on b.id = ap.bebida_id
  left join lateral (
    select sum(-m.ml_delta) filter (where m.tipo in ('salida', 'baja')) -
           sum(m.ml_delta)  filter (where m.tipo = 'anulacion') as explicado,
           sum(-m.ml_delta) filter (where m.tipo = 'salida') as servido
      from stock_mov m
     where m.evento_id = ap.evento_id and m.bebida_id = ap.bebida_id
  ) mv on true
  left join lateral (
    select avg(coalesce(l.costo_unitario, 0) / nullif(l.volumen_ml, 0)) as costo_ml
      from lotes l where l.bebida_id = ap.bebida_id
  ) cu on true;

create or replace view v_bar_margen as
select e.evento_id,
       e.ingresos - coalesce(c.costo_salidas, 0) + coalesce(c.costo_devuelto, 0)
         - coalesce(mm.merma, 0) as margen_neto,
       coalesce(c.costo_salidas, 0) - coalesce(c.costo_devuelto, 0) as costo_vendido,
       round((e.ingresos - coalesce(c.costo_salidas, 0) + coalesce(c.costo_devuelto, 0)) * 100
             / nullif(e.ingresos, 0)) as margen_pct,
       coalesce(c.costo_cortesias, 0) as costo_cortesias,
       mm.merma as merma_bs
  from v_bar_evento e
  left join v_bar_costos_evento c on c.evento_id = e.evento_id
  left join (select evento_id, sum(merma_bs) as merma from v_bar_merma group by evento_id) mm
    on mm.evento_id = e.evento_id;

create or replace view v_bar_top_trago as
select v.evento_id, t.nombre as trago,
       sum(i.qty) as vasos,
       sum(i.qty * i.precio_unit) as ingresos,
       row_number() over (partition by v.evento_id order by sum(i.qty) desc) as puesto_evento
  from bar_venta_items i
  join bar_ventas v on v.id = i.venta_id and v.estado <> 'anulada'
  join tragos t on t.id = i.trago_id
 group by v.evento_id, t.id, t.nombre;

-- ============================================================
-- RPCs de LECTURA (devuelven [] con tablas vacías, como el origen)
-- ============================================================
create or replace function bar_disponibilidad(p_club text, p_barra uuid default null)
returns table (id uuid, nombre text, precio numeric, categoria text, alcanza_para int)
language sql stable security definer set search_path = public
as $$
  select t.id, t.nombre, t.precio_venta as precio,
         (select c.nombre from receta_items ri
            join bebidas bb on bb.id = ri.bebida_id
            left join bar_categorias c on c.id = bb.categoria_id
           where ri.trago_id = t.id order by ri.ml desc limit 1) as categoria,
         coalesce((select min(floor(coalesce(st.ml, 0) / ri.ml))::int
            from receta_items ri
            left join lateral (select sum(l.ml_actual) as ml from lotes l where l.bebida_id = ri.bebida_id) st on true
           where ri.trago_id = t.id), 0) as alcanza_para
    from tragos t
   where t.club_id = p_club and t.activo
     and exists (select 1 from receta_items ri where ri.trago_id = t.id)
     and (t.barra_id is null or p_barra is null or t.barra_id = p_barra)
   order by t.orden, t.nombre;
$$;

create or replace function bar_cortesias_evento(p_evento uuid)
returns table (user_id uuid, nombre text, team text, cupo int, usados bigint)
language sql stable security definer set search_path = public
as $$
  with ev as (select club_id from eventos where id = p_evento),
  base as (
    select p.id, p.nombre,
           coalesce(tef.nombre, 'Sin team') as team,
           coalesce(cc.cupo, cfg.cupo_default, 0) as cupo
      from profiles p
      cross join ev
      left join club_membership cm on cm.user_id = p.id and cm.club_id = ev.club_id
      left join teams tb on tb.id = p.team_id
      left join teams tef on tef.id = coalesce(cm.team_id,
        case when tb.id is not null and (p.rol = 'admin' or tb.clubs is null
             or coalesce(array_length(tb.clubs, 1), 0) = 0 or ev.club_id = any(tb.clubs))
             then p.team_id end)
      left join bar_cortesia_cupo cc on cc.user_id = p.id and cc.club_id = ev.club_id
      left join bar_cortesia_config cfg on cfg.club_id = ev.club_id
     where p.activo and p.eliminado_at is null
       and coalesce(cm.rol, p.rol) in ('rrpp', 'jefe')
       and (coalesce(array_length(p.clubs, 1), 0) = 0 or ev.club_id = any(p.clubs))
  )
  select b.id, b.nombre, b.team, b.cupo,
         coalesce((select sum(i.qty) from bar_ventas v join bar_venta_items i on i.venta_id = v.id
            where v.evento_id = p_evento and v.cortesia_de = b.id and v.estado <> 'anulada'), 0) as usados
    from base b
   where b.cupo > 0
   order by b.nombre;
$$;

/* proyección de compra — FÓRMULA SUPUESTA (fase sin datos reales; la UI
 * solo promete "consumo real de las últimas noches, con 15% de colchón"):
 * consumo medio de ml por evento con ventas, escalado por p_asistentes
 * sobre el promedio de vasos por evento como proxy de asistencia. */
create or replace function bar_proyeccion_compra(p_club text, p_asistentes int default 500)
returns table (bebida text, stock_botellas numeric, necesita_botellas int, comprar_botellas int)
language sql stable security definer set search_path = public
as $$
  with consumo as (
    select m.bebida_id, m.evento_id, sum(-m.ml_delta) as ml
      from stock_mov m
     where m.tipo = 'salida' and m.club_id = p_club and m.evento_id is not null
     group by m.bebida_id, m.evento_id
  ),
  medio as (select bebida_id, avg(ml) as ml_medio from consumo group by bebida_id),
  vasos as (
    select avg(e.vasos) as prom from v_bar_evento e
     where exists (select 1 from eventos ev where ev.id = e.evento_id and ev.club_id = p_club)
  )
  select b.nombre as bebida,
         round(coalesce(s.ml_total, 0) / nullif(b.volumen_ml, 0), 1) as stock_botellas,
         ceil(m.ml_medio * 1.15 * (p_asistentes / nullif((select prom from vasos), 0))
              / nullif(b.volumen_ml, 0))::int as necesita_botellas,
         greatest(ceil(m.ml_medio * 1.15 * (p_asistentes / nullif((select prom from vasos), 0))
              / nullif(b.volumen_ml, 0))::int
              - floor(coalesce(s.ml_total, 0) / nullif(b.volumen_ml, 0))::int, 0) as comprar_botellas
    from medio m
    join bebidas b on b.id = m.bebida_id
    left join (select bebida_id, ml_total from v_bar_stock) s on s.bebida_id = b.id
   order by b.nombre;
$$;

/* fase 3 · qué falta contar — NO existe en el origen; contrato de
 * screenBarConteo: {lote_id, bebida, codigo, categoria, ml_sistema,
 * ml_contado, volumen_ml} */
create or replace function bar_conteo_pendiente(p_evento uuid, p_momento text)
returns table (lote_id uuid, bebida text, codigo text, categoria text,
               ml_sistema numeric, ml_contado numeric, volumen_ml int)
language sql stable security definer set search_path = public
as $$
  select l.id, b.nombre, l.codigo, c.nombre,
         l.ml_actual, ct.ml_contado, l.volumen_ml
    from lotes l
    join bebidas b on b.id = l.bebida_id
    left join bar_categorias c on c.id = b.categoria_id
    left join bar_conteos ct on ct.lote_id = l.id and ct.evento_id = p_evento and ct.momento = p_momento
    join eventos e on e.id = p_evento
   where l.ml_actual > 0 and b.club_id = e.club_id and b.activo
   order by c.nombre nulls last, b.nombre, l.recibido_at;
$$;

-- ============================================================
-- RPCs de ESCRITURA
-- ============================================================
create or replace function bar_recibir_lote(
  p_bebida uuid, p_cantidad int, p_codigo text default null,
  p_costo numeric default null, p_notas text default null)
returns json
language plpgsql volatile security definer set search_path = public
as $$
declare b bebidas%rowtype; v_ml numeric; v_lote uuid;
begin
  select * into b from bebidas where id = p_bebida;
  if not found then raise exception 'Bebida no encontrada'; end if;    -- TEXTO SUPUESTO
  if coalesce(p_cantidad, 0) <= 0 then raise exception 'Cantidad inválida'; end if;
  v_ml := p_cantidad * b.volumen_ml;
  insert into lotes (id, bebida_id, club_id, codigo, cant_inicial, volumen_ml, ml_actual, costo_unitario, recibido_at, recibido_por, notas)
  values (gen_random_uuid(), p_bebida, b.club_id,
          coalesce(nullif(trim(coalesce(p_codigo, '')), ''), 'L-' || upper(substr(md5(random()::text), 1, 6))),
          p_cantidad, b.volumen_ml, v_ml, p_costo, now(), auth.uid(), p_notas)
  returning id into v_lote;
  insert into stock_mov (bebida_id, lote_id, club_id, tipo, ml_delta, costo, motivo, creado_por)
  values (p_bebida, v_lote, b.club_id, 'entrada', v_ml, coalesce(p_costo, 0) * p_cantidad, 'Compra', auth.uid());
  return json_build_object('botellas', p_cantidad, 'ml', v_ml);
end;
$$;

/* bar_vender: idempotente por client_key; FIFO por lote; rechaza sin stock
 * (el mensaje real contiene "no hay stock") y cortesías sobre el cupo (el
 * mensaje real contiene "CUPO AGOTADO"). Respuesta: {venta, total, cortesia}. */
create or replace function bar_vender(
  p_evento uuid, p_barra uuid, p_items jsonb, p_cortesia_de uuid default null,
  p_forma_pago text default 'efectivo', p_client_key text default null)
returns json
language plpgsql volatile security definer set search_path = public
as $$
declare
  v_club text;
  v_venta uuid;
  v_total numeric := 0;
  it record; r record;
  v_necesito numeric; v_disp numeric; v_toma numeric;
  v_lote lotes%rowtype;
  v_cupo int; v_usados int;
begin
  -- idempotencia: si esta clave ya entró, se devuelve la misma venta
  if p_client_key is not null then
    select id, total, (cortesia_de is not null) as cort into r
      from bar_ventas where client_key = p_client_key;
    if found then
      return json_build_object('venta', r.id, 'total', r.total, 'cortesia', r.cort);
    end if;
  end if;

  select e.club_id into v_club from eventos e where e.id = p_evento;
  if v_club is null then raise exception 'Evento no encontrado'; end if;

  -- cortesía: cupo del relacionador
  if p_cortesia_de is not null then
    select coalesce(cc.cupo, cfg.cupo_default, 0) into v_cupo
      from (select 1) x
      left join bar_cortesia_cupo cc on cc.user_id = p_cortesia_de and cc.club_id = v_club
      left join bar_cortesia_config cfg on cfg.club_id = v_club;
    select coalesce(sum(i.qty), 0) into v_usados
      from bar_ventas v join bar_venta_items i on i.venta_id = v.id
     where v.evento_id = p_evento and v.cortesia_de = p_cortesia_de and v.estado <> 'anulada';
    if v_usados + (select coalesce(sum((x->>'qty')::int), 0) from jsonb_array_elements(p_items) x) > v_cupo then
      raise exception 'CUPO AGOTADO: ya usó sus % vaso(s) de cortesía', v_cupo;   -- fragmento real
    end if;
  end if;

  v_venta := gen_random_uuid();
  insert into bar_ventas (id, club_id, evento_id, barra_id, total, cortesia_de, estado, client_key)
  values (v_venta, v_club, p_evento, p_barra, 0, p_cortesia_de,
          case when p_cortesia_de is not null then 'cortesia' else coalesce(p_forma_pago, 'efectivo') end,
          p_client_key);

  for it in select (x->>'trago_id')::uuid as trago_id, (x->>'qty')::int as qty
              from jsonb_array_elements(p_items) x
  loop
    if it.qty is null or it.qty <= 0 then continue; end if;
    select t.* into r from tragos t where t.id = it.trago_id and t.activo;
    if not found then raise exception 'Trago no encontrado'; end if;   -- TEXTO SUPUESTO
    if p_cortesia_de is null then v_total := v_total + r.precio_venta * it.qty; end if;
    insert into bar_venta_items (venta_id, trago_id, qty, precio_unit)
    values (v_venta, it.trago_id, it.qty, r.precio_venta);

    -- descuento FIFO por cada ingrediente de la receta
    for r in select ri.bebida_id, ri.ml * it.qty as necesito, b.nombre
               from receta_items ri join bebidas b on b.id = ri.bebida_id
              where ri.trago_id = it.trago_id
    loop
      select coalesce(sum(ml_actual), 0) into v_disp from lotes where bebida_id = r.bebida_id;
      if v_disp < r.necesito then
        raise exception 'no hay stock de %: quedan % ml y hacen falta %', r.nombre, v_disp, r.necesito;  -- fragmento real
      end if;
      v_necesito := r.necesito;
      for v_lote in select * from lotes
                     where bebida_id = r.bebida_id and ml_actual > 0
                     order by recibido_at
                     for update
      loop
        exit when v_necesito <= 0;
        v_toma := least(v_lote.ml_actual, v_necesito);
        update lotes set ml_actual = ml_actual - v_toma where id = v_lote.id;
        insert into stock_mov (bebida_id, lote_id, club_id, tipo, ml_delta, costo, motivo, evento_id, barra_id, creado_por)
        values (r.bebida_id, v_lote.id, v_club, 'salida', -v_toma,
                v_toma * coalesce(v_lote.costo_unitario, 0) / nullif(v_lote.volumen_ml, 0),
                'venta:' || v_venta::text, p_evento, p_barra, auth.uid());
        v_necesito := v_necesito - v_toma;
      end loop;
    end loop;
  end loop;

  update bar_ventas set total = v_total where id = v_venta;
  return json_build_object('venta', v_venta, 'total', v_total, 'cortesia', p_cortesia_de is not null);
end;
$$;

/* bar_anular_venta: devuelve el stock a los MISMOS lotes revirtiendo los
 * movimientos 'salida' de la venta, y la marca anulada. */
create or replace function bar_anular_venta(p_venta uuid, p_motivo text default null)
returns void
language plpgsql volatile security definer set search_path = public
as $$
declare v bar_ventas%rowtype; m record;
begin
  select * into v from bar_ventas where id = p_venta;
  if not found then raise exception 'Venta no encontrada'; end if;     -- TEXTO SUPUESTO
  if v.estado = 'anulada' then raise exception 'La venta ya está anulada'; end if;
  for m in select * from stock_mov where tipo = 'salida' and motivo = 'venta:' || p_venta::text
  loop
    update lotes set ml_actual = ml_actual - m.ml_delta where id = m.lote_id;   -- ml_delta es negativo
    insert into stock_mov (bebida_id, lote_id, club_id, tipo, ml_delta, costo, motivo, evento_id, barra_id, creado_por)
    values (m.bebida_id, m.lote_id, m.club_id, 'anulacion', -m.ml_delta, m.costo,
            coalesce(p_motivo, 'Anulada'), m.evento_id, m.barra_id, auth.uid());
  end loop;
  update bar_ventas set estado = 'anulada' where id = p_venta;
end;
$$;

/* bar_ajuste_conteo: conteo físico de un lote puntual */
create or replace function bar_ajuste_conteo(p_lote uuid, p_ml_fisico numeric, p_evento uuid default null, p_motivo text default null)
returns json
language plpgsql volatile security definer set search_path = public
as $$
declare l lotes%rowtype; v_delta numeric;
begin
  select * into l from lotes where id = p_lote;
  if not found then raise exception 'Lote no encontrado'; end if;      -- TEXTO SUPUESTO
  v_delta := p_ml_fisico - l.ml_actual;
  if v_delta = 0 then return json_build_object('sin_cambios', true); end if;
  update lotes set ml_actual = p_ml_fisico where id = p_lote;
  insert into stock_mov (bebida_id, lote_id, club_id, tipo, ml_delta, costo, motivo, evento_id, creado_por)
  values (l.bebida_id, p_lote, l.club_id, 'ajuste', v_delta,
          v_delta * coalesce(l.costo_unitario, 0) / nullif(l.volumen_ml, 0),
          coalesce(p_motivo, 'Conteo'), p_evento, auth.uid());
  return json_build_object('delta_ml', v_delta);
end;
$$;

/* bar_baja: merma explicada (rotura, derrame, cortesía, vencida) */
create or replace function bar_baja(p_lote uuid, p_ml numeric, p_motivo text, p_evento uuid default null)
returns void
language plpgsql volatile security definer set search_path = public
as $$
declare l lotes%rowtype;
begin
  select * into l from lotes where id = p_lote;
  if not found then raise exception 'Lote no encontrado'; end if;
  if p_ml <= 0 or p_ml > l.ml_actual then
    raise exception 'Ese lote solo tiene % ml', l.ml_actual;           -- TEXTO SUPUESTO
  end if;
  update lotes set ml_actual = ml_actual - p_ml where id = p_lote;
  insert into stock_mov (bebida_id, lote_id, club_id, tipo, ml_delta, costo, motivo, evento_id, creado_por)
  values (l.bebida_id, p_lote, l.club_id, 'baja', -p_ml,
          p_ml * coalesce(l.costo_unitario, 0) / nullif(l.volumen_ml, 0),
          p_motivo, p_evento, auth.uid());
end;
$$;

/* fase 3 · conteo masivo: guarda el conteo (apertura/cierre, para la
 * merma) y ajusta los lotes que difieren. Devuelve {ajustados}. */
create or replace function bar_conteo_masivo(p_evento uuid, p_momento text, p_lineas jsonb)
returns json
language plpgsql volatile security definer set search_path = public
as $$
declare x record; v_ajustados int := 0; l lotes%rowtype;
begin
  for x in select (i->>'lote_id')::uuid as lote_id, (i->>'ml_fisico')::numeric as ml_fisico
             from jsonb_array_elements(p_lineas) i
  loop
    select * into l from lotes where id = x.lote_id;
    continue when not found;
    insert into bar_conteos (evento_id, momento, lote_id, ml_contado, creado_por)
    values (p_evento, p_momento, x.lote_id, x.ml_fisico, auth.uid())
    on conflict (evento_id, momento, lote_id)
      do update set ml_contado = excluded.ml_contado, creado_por = auth.uid(), created_at = now();
    if x.ml_fisico is distinct from l.ml_actual then
      update lotes set ml_actual = x.ml_fisico where id = x.lote_id;
      insert into stock_mov (bebida_id, lote_id, club_id, tipo, ml_delta, costo, motivo, evento_id, creado_por)
      values (l.bebida_id, x.lote_id, l.club_id, 'ajuste', x.ml_fisico - l.ml_actual,
              (x.ml_fisico - l.ml_actual) * coalesce(l.costo_unitario, 0) / nullif(l.volumen_ml, 0),
              'Conteo de ' || p_momento, p_evento, auth.uid());
      v_ajustados := v_ajustados + 1;
    end if;
  end loop;
  return json_build_object('ajustados', v_ajustados);
end;
$$;
