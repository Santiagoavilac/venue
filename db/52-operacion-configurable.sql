-- 52 · Operación configurable por boliche y por evento
--
-- El admin elige, al crear el boliche (valores por defecto) y en cada evento
-- (lo que rige esa noche), cómo se paga:
--   modo_comision  'jefes'          el boliche le da al team un % y el jefe
--                                   decide cuánto va a sus relacionadores
--                  'relacionadores' cada relacionador cobra el % entero
--                  'ninguno'        nadie cobra comisión
--   manillas       % de la manilla para el team (= 100 − pct_boliche)
--   mesas          sí/no y % del precio de la mesa
--   combos         sí/no: el monto fijo de cada combo
-- El reparto del jefe es un % por evento (team_reparto). Si no lo definió,
-- vale el último que usó; la primera vez, 50 %.
--
-- Todo el cálculo vive acá: la web y las apps solo muestran lo que devuelve
-- el servidor, y los formularios se arman con opciones_operacion(), así una
-- opción nueva no pide actualizar la app.
--
-- Los eventos que ya existían quedan con la cuenta vieja (config_v2 = false)
-- para que ningún total pasado cambie; al editar su operación pasan a la nueva.

-- ── columnas ───────────────────────────────────────────────────────────
alter table clubs add column if not exists pct_boliche_def numeric(5,2) not null default 50
  check (pct_boliche_def between 0 and 100);
alter table clubs add column if not exists comision_mesas boolean not null default false;
alter table clubs add column if not exists pct_comision_mesas numeric(5,2) not null default 0
  check (pct_comision_mesas between 0 and 100);

alter table eventos add column if not exists config_v2 boolean not null default true;
alter table eventos add column if not exists modo_comision text
  check (modo_comision in ('jefes', 'relacionadores', 'ninguno'));
alter table eventos add column if not exists comision_manillas boolean;
alter table eventos add column if not exists comision_mesas boolean;
alter table eventos add column if not exists pct_comision_mesas numeric(5,2)
  check (pct_comision_mesas between 0 and 100);
alter table eventos add column if not exists comision_combos boolean;

-- los eventos que ya existían: cuenta vieja, con los valores del boliche a la vista
update eventos e set
  config_v2 = false,
  modo_comision = case when not coalesce(c.usa_relacionadores, true) then 'ninguno'
                       when not coalesce(c.usa_teams, true) then 'relacionadores' else 'jefes' end,
  comision_manillas = coalesce(c.comision_manillas, true),
  comision_mesas = false,
  pct_comision_mesas = 0,
  comision_combos = coalesce(c.comision_combos, true)
from clubs c where c.id = e.club_id and e.modo_comision is null;

-- un evento nuevo hereda la operación del boliche (también si lo crea una
-- versión vieja de la app que no manda estos campos)
create or replace function impl.evento_operacion_por_defecto()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare c clubs;
begin
  select * into c from clubs where id = new.club_id;
  new.modo_comision := coalesce(new.modo_comision,
    case when not coalesce(c.usa_relacionadores, true) then 'ninguno'
         when not coalesce(c.usa_teams, true) then 'relacionadores' else 'jefes' end);
  new.comision_manillas := coalesce(new.comision_manillas, c.comision_manillas, true);
  new.comision_mesas := coalesce(new.comision_mesas, c.comision_mesas, false);
  new.pct_comision_mesas := coalesce(new.pct_comision_mesas, c.pct_comision_mesas, 0);
  new.comision_combos := coalesce(new.comision_combos, c.comision_combos, true);
  return new;
end;
$$;
drop trigger if exists eventos_operacion_por_defecto on eventos;
create trigger eventos_operacion_por_defecto before insert on eventos
  for each row execute function impl.evento_operacion_por_defecto();

-- ── reparto del jefe por evento ─────────────────────────────────────────
create table if not exists team_reparto (
  team_id      uuid not null references teams (id) on delete cascade,
  evento_id    uuid not null references eventos (id) on delete cascade,
  pct_rrpp     numeric(5,2) not null check (pct_rrpp between 0 and 100),
  definido_por uuid references profiles (id),
  definido_at  timestamptz not null default now(),
  primary key (team_id, evento_id)
);
alter table team_reparto enable row level security;
drop policy if exists team_reparto_leer on team_reparto;
create policy team_reparto_leer on team_reparto for select to authenticated
  using (exists (select 1 from eventos e where e.id = evento_id and rol_en_club(e.club_id) is not null));

-- % del pozo que va a cada relacionador: el del evento, si no el último que
-- usó el team, si no 50
create or replace function impl.reparto_pct(p_team uuid, p_evento uuid)
returns numeric
language sql
stable
security definer
set search_path = public
as $$
  select coalesce(
    (select r.pct_rrpp from team_reparto r where r.team_id = p_team and r.evento_id = p_evento),
    (select r.pct_rrpp from team_reparto r join eventos e on e.id = r.evento_id
      where r.team_id = p_team order by e.fecha desc, r.definido_at desc limit 1),
    50);
$$;

-- ── el cálculo ──────────────────────────────────────────────────────────
-- la cuenta vieja se conserva tal cual para los eventos anteriores
do $$ begin
  if not exists (select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
                  where n.nspname = 'impl' and p.proname = 'comision_manilla_v1') then
    alter function impl.comision_manilla(uuid, uuid) rename to comision_manilla_v1;
  end if;
end $$;

-- reparte un pozo entre quien vendió y su jefe según el modo del evento
create or replace function impl.repartir(p_evento uuid, p_persona uuid, p_pozo numeric,
  out rrpp numeric, out jefe numeric)
language plpgsql
stable
security definer
set search_path = public
as $$
declare e eventos; p profiles; v_team uuid; v_jefe uuid;
begin
  rrpp := 0; jefe := 0;
  select * into e from eventos where id = p_evento;
  select * into p from profiles where id = p_persona;
  -- los admin no cobran comisión (regla de siempre); sin pozo no hay nada
  if not found or p.rol = 'admin' or coalesce(p_pozo, 0) <= 0 or e.modo_comision = 'ninguno' then return; end if;
  if e.modo_comision = 'relacionadores' then
    rrpp := p_pozo; return;
  end if;
  v_team := impl.team_efectivo(p_persona, e.club_id);
  if v_team is not null then select t.jefe_id into v_jefe from teams t where t.id = v_team; end if;
  -- sin team, o lo vende el propio jefe: todo para quien vendió
  if v_team is null or v_jefe is null or v_jefe = p_persona then
    rrpp := p_pozo; return;
  end if;
  rrpp := round(p_pozo * impl.reparto_pct(v_team, p_evento) / 100.0, 2);
  jefe := p_pozo - rrpp;
end;
$$;

create or replace function impl.comision_manilla(p_evento uuid, p_persona uuid,
  out rrpp numeric, out jefe numeric)
language plpgsql
stable
security definer
set search_path = public
as $$
declare e eventos; v record;
begin
  select * into e from eventos where id = p_evento;
  if not found then rrpp := 0; jefe := 0; return; end if;
  if not e.config_v2 then
    select * into v from impl.comision_manilla_v1(p_evento, p_persona);
    rrpp := v.rrpp; jefe := v.jefe; return;
  end if;
  select * into v from impl.repartir(p_evento, p_persona,
    case when coalesce(e.comision_manillas, true)
         then coalesce(e.precio_manilla, 0) * (100 - coalesce(e.pct_boliche, 0)) / 100.0 else 0 end);
  rrpp := v.rrpp; jefe := v.jefe;
end;
$$;

-- comisión de una mesa vendida (ya multiplicada por la cantidad de combos)
create or replace function impl.comision_mesa(p_mesa uuid, out rrpp numeric, out jefe numeric)
language plpgsql
stable
security definer
set search_path = public
as $$
declare m mesas; e eventos; co combos; v record; v_pozo numeric := 0;
begin
  rrpp := 0; jefe := 0;
  select * into m from mesas where id = p_mesa;
  if not found then return; end if;
  select * into e from eventos where id = m.evento_id;
  if not e.config_v2 then
    if m.combo_id is null then return; end if;
    select * into v from impl.comision_combo(m.combo_id, m.vendido_por, e.club_id);
    rrpp := v.rrpp * coalesce(m.combo_qty, 1); jefe := v.jefe * coalesce(m.combo_qty, 1); return;
  end if;
  if coalesce(e.comision_mesas, false) then
    v_pozo := v_pozo + coalesce(m.precio, 0) * coalesce(e.pct_comision_mesas, 0) / 100.0;
  end if;
  if coalesce(e.comision_combos, false) and m.combo_id is not null then
    select * into co from combos where id = m.combo_id;
    v_pozo := v_pozo + (coalesce(co.comision_rrpp, 0) + coalesce(co.comision_jefe, 0)) * coalesce(m.combo_qty, 1);
  end if;
  select * into v from impl.repartir(e.id, m.vendido_por, v_pozo);
  rrpp := v.rrpp; jefe := v.jefe;
end;
$$;

-- en los eventos nuevos manda la cuenta nueva
create or replace function impl.reparto_nuevo(p_evento uuid, p_persona uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select e.config_v2
      or not (coalesce(c.usa_relacionadores, true) and coalesce(c.usa_teams, true)
              and coalesce(c.comision_manillas, true) and coalesce(c.comision_combos, true))
      or exists (select 1 from teams t where t.id = impl.team_efectivo(p_persona, e.club_id)
                  and (t.rrpp_por_manilla is not null or t.rrpp_por_combo is not null))
    from eventos e left join clubs c on c.id = e.club_id
   where e.id = p_evento;
$$;

-- ── vistas y reportes: la comisión de mesa sale de comision_mesa ─────────
do $$
declare d text; n text;
begin
  -- v_stats_mesas
  d := pg_get_viewdef('public.v_stats_mesas'::regclass);
  n := replace(d, '(impl.comision_combo(mm.combo_id, p.id, e.club_id)).rrpp * (mm.combo_qty)::numeric', '(impl.comision_mesa(mm.id)).rrpp');
  n := replace(n, '(impl.comision_combo(mm.combo_id, p.id, e.club_id)).jefe * (mm.combo_qty)::numeric', '(impl.comision_mesa(mm.id)).jefe');
  n := replace(n, '(mm.combo_id IS NOT NULL) AND ', '');
  if n = d or n like '%comision_combo%' then raise exception 'v_stats_mesas: no se pudo reemplazar la comisión'; end if;
  execute 'create or replace view public.v_stats_mesas as ' || n;

  -- histórico (utilidad): comisión de mesas por mesa
  d := pg_get_functiondef('impl.historico_eventos(text)'::regprocedure);
  n := regexp_replace(d, '\(\(impl\.comision_combo\(m\.combo_id, m\.vendido_por, e\.club_id\)\)\.rrpp\s*\+\s*\(impl\.comision_combo\(m\.combo_id, m\.vendido_por, e\.club_id\)\)\.jefe\)\s*\*\s*coalesce\(m\.combo_qty, 1\)',
                         '((impl.comision_mesa(m.id)).rrpp + (impl.comision_mesa(m.id)).jefe)');
  if n = d or n like '%comision_combo%' then raise exception 'historico_eventos: no se pudo reemplazar la comisión'; end if;
  execute n;

  -- ranking: lo que cobra cada uno por sus mesas
  d := pg_get_functiondef('impl.ranking_rrpp(text, date)'::regprocedure);
  n := replace(d, '(impl.comision_combo(m.combo_id, b.id, p_club)).rrpp * coalesce(m.combo_qty, 1)', '(impl.comision_mesa(m.id)).rrpp');
  n := replace(n, ' and m.combo_id is not null), 0)', '), 0)');
  if n = d or n like '%comision_combo%' then raise exception 'ranking_rrpp: no se pudo reemplazar la comisión'; end if;
  execute n;
end $$;

-- liquidación: con la operación del evento (la vieja queda igual)
create or replace function impl.liquidacion_evento(p_evento uuid)
returns json
language sql
stable
security definer
set search_path = public
as $function$
  with ev as (
    select e.precio_manilla, e.pct_boliche, coalesce(e.manillas_externas, 0) as externas, e.club_id,
           case when e.config_v2
                then coalesce(e.modo_comision, 'jefes') <> 'ninguno' and coalesce(e.comision_manillas, true)
                else coalesce(c.usa_relacionadores, true) and coalesce(c.comision_manillas, true) end as con_comision
      from eventos e left join clubs c on c.id = e.club_id
     where e.id = p_evento
  ),
  man as (
    select count(*)::int as usadas
      from impl.entradas_vigentes
     where evento_id = p_evento and estado = 'usada' and mesa_id is null
  ),
  mes as (
    select coalesce(sum(m.precio), 0)::numeric as bruto,
           coalesce(sum((impl.comision_mesa(m.id)).rrpp + (impl.comision_mesa(m.id)).jefe), 0)::numeric as comision
      from mesas m
     where m.evento_id = p_evento and m.estado <> 'disponible'
  ),
  calc as (
    select ev.precio_manilla,
           ev.externas                                   as manillas_externas,
           man.usadas                                    as manillas_usadas,
           greatest(man.usadas - ev.externas, 0)         as manillas_netas,
           case when ev.con_comision then ev.precio_manilla * ev.pct_boliche / 100.0
                else ev.precio_manilla::numeric end      as por_manilla,
           mes.bruto                                     as bruto_mesas,
           mes.comision                                  as comision_mesas
      from ev, man, mes
  )
  select json_build_object(
    'precio_manilla',    precio_manilla,
    'manillas_externas', manillas_externas,
    'manillas_usadas',   manillas_usadas,
    'manillas_netas',    manillas_netas,
    'por_manilla',       por_manilla,
    'total_manillas',    manillas_netas * por_manilla,
    'bruto_mesas',       bruto_mesas,
    'comision_mesas',    comision_mesas,
    'total_mesas',       bruto_mesas - comision_mesas,
    'total_a_pagar',     (manillas_netas * por_manilla) + (bruto_mesas - comision_mesas)
  ) from calc;
$function$;

-- ── formularios dibujados por el servidor ────────────────────────────────
-- Devuelve los campos de la operación del boliche (p_evento null) o de un
-- evento. Cada campo: clave, etiqueta, tipo ('opcion' | 'si_no' |
-- 'porcentaje'), valor, opciones, ayuda y visible_si ({clave: [valores]}).
-- Las apps los dibujan tal cual: agregar una opción acá no pide actualizarlas.
create or replace function public.opciones_operacion(p_club text, p_evento uuid default null)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare c clubs; e eventos; v_modo text; v_pct numeric; v_man boolean; v_mes boolean; v_pmes numeric; v_comb boolean;
begin
  if rol_en_club(p_club) is distinct from 'admin' and not es_platform_admin() then
    raise exception 'Solo administradores.' using errcode = '42501';
  end if;
  select * into c from clubs where id = p_club;
  if not found then raise exception 'Boliche no encontrado.'; end if;
  if p_evento is not null then
    select * into e from eventos where id = p_evento and club_id = p_club;
    if not found then raise exception 'Evento no encontrado.'; end if;
    v_modo := e.modo_comision; v_pct := 100 - e.pct_boliche; v_man := e.comision_manillas;
    v_mes := e.comision_mesas; v_pmes := e.pct_comision_mesas; v_comb := e.comision_combos;
  else
    v_modo := case when not coalesce(c.usa_relacionadores, true) then 'ninguno'
                   when not coalesce(c.usa_teams, true) then 'relacionadores' else 'jefes' end;
    v_pct := 100 - c.pct_boliche_def; v_man := c.comision_manillas;
    v_mes := c.comision_mesas; v_pmes := c.pct_comision_mesas; v_comb := c.comision_combos;
  end if;
  return jsonb_build_object(
    'nivel', case when p_evento is null then 'boliche' else 'evento' end,
    'cuenta_vieja', p_evento is not null and not e.config_v2,
    'aviso', case when p_evento is not null and not e.config_v2
                  then 'Este evento usa la cuenta anterior. Al guardar pasa a esta configuración y se recalculan sus comisiones.' end,
    'campos', jsonb_build_array(
      jsonb_build_object('clave', 'modo_comision', 'tipo', 'opcion', 'etiqueta', 'Cómo se paga la comisión', 'valor', v_modo,
        'opciones', jsonb_build_array(
          jsonb_build_object('valor', 'jefes', 'etiqueta', 'Con jefes de team', 'ayuda', 'El boliche le da un % al team y el jefe decide cuánto va a sus relacionadores.'),
          jsonb_build_object('valor', 'relacionadores', 'etiqueta', 'Solo relacionadores', 'ayuda', 'Cada relacionador cobra el % entero de lo que vende.'),
          jsonb_build_object('valor', 'ninguno', 'etiqueta', 'Sin comisiones', 'ayuda', 'Nadie cobra comisión.'))),
      jsonb_build_object('clave', 'comision_manillas', 'tipo', 'si_no', 'etiqueta', 'Comisión por manillas', 'valor', v_man,
        'visible_si', jsonb_build_object('modo_comision', jsonb_build_array('jefes', 'relacionadores'))),
      jsonb_build_object('clave', 'pct_comision_manilla', 'tipo', 'porcentaje', 'etiqueta', 'Para el team, % de cada manilla', 'valor', v_pct,
        'ayuda', 'El resto queda para el boliche. El jefe reparte este % con su team.',
        'visible_si', jsonb_build_object('modo_comision', jsonb_build_array('jefes'), 'comision_manillas', jsonb_build_array(true))),
      jsonb_build_object('clave', 'pct_comision_manilla', 'tipo', 'porcentaje', 'etiqueta', 'Para el relacionador, % de cada manilla', 'valor', v_pct,
        'ayuda', 'El resto queda para el boliche.',
        'visible_si', jsonb_build_object('modo_comision', jsonb_build_array('relacionadores'), 'comision_manillas', jsonb_build_array(true))),
      jsonb_build_object('clave', 'comision_mesas', 'tipo', 'si_no', 'etiqueta', 'Comisión por mesas', 'valor', v_mes,
        'visible_si', jsonb_build_object('modo_comision', jsonb_build_array('jefes', 'relacionadores'))),
      jsonb_build_object('clave', 'pct_comision_mesas', 'tipo', 'porcentaje', 'etiqueta', '% del precio de la mesa', 'valor', v_pmes,
        'visible_si', jsonb_build_object('modo_comision', jsonb_build_array('jefes', 'relacionadores'), 'comision_mesas', jsonb_build_array(true))),
      jsonb_build_object('clave', 'comision_combos', 'tipo', 'si_no', 'etiqueta', 'Comisión por combos', 'valor', v_comb,
        'ayuda', 'Usa el monto de comisión cargado en cada combo.',
        'visible_si', jsonb_build_object('modo_comision', jsonb_build_array('jefes', 'relacionadores')))
    ));
end;
$$;

create or replace function public.guardar_opciones_operacion(p_club text, p_evento uuid, p_valores jsonb)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare v_modo text := p_valores ->> 'modo_comision';
        v_pct numeric := (p_valores ->> 'pct_comision_manilla')::numeric;
        v_pmes numeric := coalesce((p_valores ->> 'pct_comision_mesas')::numeric, 0);
        v_man boolean := coalesce((p_valores ->> 'comision_manillas')::boolean, true);
        v_mes boolean := coalesce((p_valores ->> 'comision_mesas')::boolean, false);
        v_comb boolean := coalesce((p_valores ->> 'comision_combos')::boolean, false);
begin
  if rol_en_club(p_club) is distinct from 'admin' and not es_platform_admin() then
    raise exception 'Solo administradores.' using errcode = '42501';
  end if;
  if v_modo not in ('jefes', 'relacionadores', 'ninguno') then raise exception 'Elegí cómo se paga la comisión.'; end if;
  if v_pct is null or v_pct < 0 or v_pct > 100 or v_pmes < 0 or v_pmes > 100 then
    raise exception 'Los porcentajes van de 0 a 100.';
  end if;
  if p_evento is not null then
    update eventos set modo_comision = v_modo, pct_boliche = round(100 - v_pct)::int, comision_manillas = v_man,
           comision_mesas = v_mes, pct_comision_mesas = v_pmes, comision_combos = v_comb, config_v2 = true
     where id = p_evento and club_id = p_club;
    if not found then raise exception 'Evento no encontrado.'; end if;
  else
    update clubs set usa_relacionadores = v_modo <> 'ninguno', usa_teams = v_modo = 'jefes',
           comision_manillas = v_man, pct_boliche_def = 100 - v_pct,
           comision_mesas = v_mes, pct_comision_mesas = v_pmes, comision_combos = v_comb
     where id = p_club;
    if not found then raise exception 'Boliche no encontrado.'; end if;
  end if;
  return public.opciones_operacion(p_club, p_evento);
end;
$$;

-- ── el jefe reparte su % ─────────────────────────────────────────────────
create or replace function public.reparto_jefe(p_evento uuid, p_team uuid default null)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare e eventos; v_rol text; v_team uuid; v_propio numeric; v_pct numeric; v_pozo numeric;
begin
  select * into e from eventos where id = p_evento;
  if not found then raise exception 'Evento no encontrado.'; end if;
  v_rol := rol_en_club(e.club_id);
  v_team := case when v_rol = 'admin' and p_team is not null then p_team else impl.team_en_club(auth.uid(), e.club_id) end;
  if v_rol not in ('admin', 'jefe') or v_team is null then raise exception 'Solo para jefes de team.' using errcode = '42501'; end if;
  select r.pct_rrpp into v_propio from team_reparto r where r.team_id = v_team and r.evento_id = p_evento;
  v_pct := impl.reparto_pct(v_team, p_evento);
  v_pozo := case when coalesce(e.comision_manillas, true) and e.modo_comision = 'jefes'
                 then coalesce(e.precio_manilla, 0) * (100 - e.pct_boliche) / 100.0 else 0 end;
  return jsonb_build_object(
    'team_id', v_team, 'modo', e.modo_comision, 'cuenta_vieja', not e.config_v2,
    'pct_rrpp', v_pct, 'definido', v_propio is not null,
    'pozo_manilla', v_pozo, 'rrpp_por_manilla', round(v_pozo * v_pct / 100.0, 2),
    'jefe_por_manilla', v_pozo - round(v_pozo * v_pct / 100.0, 2),
    'comision_mesas', e.comision_mesas, 'pct_comision_mesas', e.pct_comision_mesas,
    'comision_combos', e.comision_combos);
end;
$$;

create or replace function public.fijar_reparto_jefe(p_evento uuid, p_pct_rrpp numeric, p_team uuid default null)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare e eventos; v_rol text; v_team uuid;
begin
  select * into e from eventos where id = p_evento;
  if not found then raise exception 'Evento no encontrado.'; end if;
  if p_pct_rrpp is null or p_pct_rrpp < 0 or p_pct_rrpp > 100 then raise exception 'El reparto va de 0 a 100 %%.'; end if;
  v_rol := rol_en_club(e.club_id);
  v_team := case when v_rol = 'admin' and p_team is not null then p_team else impl.team_en_club(auth.uid(), e.club_id) end;
  if v_rol not in ('admin', 'jefe') or v_team is null then raise exception 'Solo para jefes de team.' using errcode = '42501'; end if;
  if v_rol = 'jefe' and not exists (select 1 from teams t where t.id = v_team and t.jefe_id = auth.uid()) then
    raise exception 'Solo el jefe de este team puede repartir.' using errcode = '42501';
  end if;
  insert into team_reparto (team_id, evento_id, pct_rrpp, definido_por)
  values (v_team, p_evento, p_pct_rrpp, auth.uid())
  on conflict (team_id, evento_id) do update set pct_rrpp = excluded.pct_rrpp, definido_por = excluded.definido_por, definido_at = now();
  return public.reparto_jefe(p_evento, v_team);
end;
$$;

revoke all on function public.opciones_operacion(text, uuid), public.guardar_opciones_operacion(text, uuid, jsonb),
  public.reparto_jefe(uuid, uuid), public.fijar_reparto_jefe(uuid, numeric, uuid) from public, anon;
grant execute on function public.opciones_operacion(text, uuid), public.guardar_opciones_operacion(text, uuid, jsonb),
  public.reparto_jefe(uuid, uuid), public.fijar_reparto_jefe(uuid, numeric, uuid) to authenticated;
-- las vistas de stats las llaman con los permisos de quien consulta (como
-- comision_combo hoy): authenticated sí, anon no
revoke all on function impl.repartir(uuid, uuid, numeric), impl.comision_mesa(uuid), impl.reparto_pct(uuid, uuid),
  impl.comision_manilla(uuid, uuid), impl.comision_manilla_v1(uuid, uuid) from public, anon;
grant execute on function impl.repartir(uuid, uuid, numeric), impl.comision_mesa(uuid), impl.reparto_pct(uuid, uuid),
  impl.comision_manilla(uuid, uuid), impl.comision_manilla_v1(uuid, uuid) to authenticated;
