-- Cómo trabaja un boliche, en una sola decisión.
--
-- Hasta ahora "cómo trabaja" estaba repartido en cinco banderas sueltas
-- (usa_relacionadores, usa_teams, comision_manillas, modo_comision,
-- exige_comprobante) que había que entender una por una y que se podían dejar
-- en combinaciones que no existen en la realidad. En la práctica hay tres
-- formas de trabajar, y cada una decide esas banderas sola:
--
--   bt          Todo a mano, sin AFTR. El relacionador vende la entrada, sube
--               el comprobante del pago, le rinde al jefe y el jefe al
--               boliche. Es como trabajan Burtown y SitRoom.
--
--   aftr_jefes  Se vende por el enlace de AFTR. El relacionador sólo comparte
--               su enlace: no genera entradas ni sube comprobantes. Hay jefes
--               y la comisión se reparte como en bt.
--
--   premium     Se vende por AFTR y cada relacionador cobra un monto fijo por
--               manilla. Sin jefes y sin ajustes: rinde directo al boliche.
--
-- Las mesas no entran en esto: siempre se venden a mano, en las tres. Lo que
-- sí se elige en cada una es si pagan comisión, que queda como estaba.
--
-- La logística no reemplaza a las banderas: las fija. Todo lo que ya lee
-- usa_teams o modo_comision sigue leyendo lo mismo, así que nada se rompe.
alter table public.clubs
  add column if not exists logistica text not null default 'bt'
  check (logistica in ('bt', 'aftr_jefes', 'premium'));

-- Un evento puede trabajarse distinto del boliche (una fiesta que sí va por
-- AFTR en un boliche que vende a mano). Vacío = la del boliche.
alter table public.eventos
  add column if not exists logistica text
  check (logistica is null or logistica in ('bt', 'aftr_jefes', 'premium'));

comment on column public.clubs.logistica is
  'Como trabaja el boliche: bt (manual con jefes), aftr_jefes (enlace de AFTR con jefes) o premium (AFTR, monto fijo por manilla, sin jefes).';
comment on column public.eventos.logistica is
  'Logistica propia del evento. Vacio: la del boliche.';

-- ── lo que decide cada una ────────────────────────────────────────────
-- Sin security definer a propósito: no hay nada que esconder acá y así la
-- consulta pasa por las políticas de quien pregunta, sin guarda que mantener.
create or replace function public.logistica_de(p_evento uuid) returns text
language sql stable set search_path = public as $$
  select coalesce(e.logistica, c.logistica, 'bt')
    from eventos e join clubs c on c.id = e.club_id where e.id = p_evento
$$;
revoke all on function public.logistica_de(uuid) from public, anon;
grant execute on function public.logistica_de(uuid) to authenticated;

/* Deja las banderas del boliche como las pide su logística. No toca las de
   mesas ni las de combos: esas se eligen aparte en las tres. */
create or replace function impl.aplicar_logistica(p_club text, p_logistica text)
returns void language plpgsql security definer set search_path = public as $$
begin
  update clubs set
    logistica = p_logistica,
    -- con jefes en bt y aftr_jefes; en premium cada uno cobra lo suyo
    usa_teams = p_logistica in ('bt', 'aftr_jefes'),
    usa_relacionadores = true,
    -- el comprobante sólo tiene sentido donde la venta es a mano
    exige_comprobante = (p_logistica = 'bt')
  where id = p_club;
end $$;

-- ── la logística, arriba de todo en el formulario de operación ────────
-- El formulario se dibuja solo a partir de esto, así que la pantalla de
-- ajustes no se toca: aparece la decisión nueva y desaparecen las que la
-- logística ya resolvió.
create or replace function public.opciones_operacion(p_club text, p_evento uuid default null)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare c clubs; e eventos; v_modo text; v_pct numeric; v_man boolean; v_mes boolean; v_pmes numeric; v_comb boolean;
        v_log text;
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
    v_log := coalesce(e.logistica, c.logistica, 'bt');
  else
    v_modo := case when not coalesce(c.usa_relacionadores, true) then 'ninguno'
                   when not coalesce(c.usa_teams, true) then 'relacionadores' else 'jefes' end;
    v_pct := 100 - c.pct_boliche_def; v_man := c.comision_manillas;
    v_mes := c.comision_mesas; v_pmes := c.pct_comision_mesas; v_comb := c.comision_combos;
    v_log := coalesce(c.logistica, 'bt');
  end if;
  return jsonb_build_object(
    'nivel', case when p_evento is null then 'boliche' else 'evento' end,
    'logistica', v_log,
    'cuenta_vieja', p_evento is not null and not e.config_v2,
    'aviso', case when p_evento is not null and not e.config_v2
                  then 'Este evento usa la cuenta anterior. Al guardar pasa a esta configuración y se recalculan sus comisiones.' end,
    'campos', jsonb_build_array(
      jsonb_build_object('clave', 'logistica', 'tipo', 'opcion', 'etiqueta', 'Cómo se trabaja', 'valor', v_log,
        'opciones', jsonb_build_array(
          jsonb_build_object('valor', 'bt', 'etiqueta', 'A mano, con jefes',
            'ayuda', 'El relacionador vende la entrada, sube el comprobante del pago y le rinde a su jefe; el jefe le rinde al boliche. Sin venta por AFTR.'),
          jsonb_build_object('valor', 'aftr_jefes', 'etiqueta', 'Con AFTR y jefes',
            'ayuda', 'Se vende por el enlace de AFTR. El relacionador sólo comparte su enlace: no genera entradas ni sube comprobantes. La comisión se reparte por team.'),
          jsonb_build_object('valor', 'premium', 'etiqueta', 'Con AFTR, monto fijo',
            'ayuda', 'Se vende por AFTR y cada relacionador cobra un monto fijo por manilla. Sin jefes: rinde directo al boliche.'))),
      -- el reparto sólo se elige donde hay algo que repartir
      jsonb_build_object('clave', 'pct_comision_manilla', 'tipo', 'porcentaje',
        'etiqueta', case when v_log = 'premium' then 'Bs por manilla al relacionador' else 'Para el team, % de cada manilla' end,
        'valor', v_pct,
        'ayuda', case when v_log = 'premium' then 'Lo que cobra el relacionador por cada manilla que entra.'
                      else 'El resto queda para el boliche. El jefe reparte este % con su team.' end,
        'visible_si', jsonb_build_object('comision_manillas', jsonb_build_array(true))),
      jsonb_build_object('clave', 'comision_manillas', 'tipo', 'si_no', 'etiqueta', 'Pagar comisión por manillas', 'valor', v_man),
      jsonb_build_object('clave', 'comision_mesas', 'tipo', 'si_no', 'etiqueta', 'Pagar comisión por mesas', 'valor', v_mes,
        'ayuda', 'Las mesas se venden a mano en las tres formas de trabajar: el relacionador sube el comprobante y rinde. Esto decide si además cobra por venderlas.'),
      jsonb_build_object('clave', 'pct_comision_mesas', 'tipo', 'porcentaje', 'etiqueta', '% del precio de la mesa', 'valor', v_pmes,
        'visible_si', jsonb_build_object('comision_mesas', jsonb_build_array(true))),
      jsonb_build_object('clave', 'comision_combos', 'tipo', 'si_no', 'etiqueta', 'Pagar comisión por combos', 'valor', v_comb,
        'ayuda', 'Usa el monto de comisión cargado en cada combo.')
    ));
end;
$$;

create or replace function public.guardar_opciones_operacion(p_club text, p_evento uuid, p_valores jsonb)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare v_log text := p_valores ->> 'logistica';
        v_pct numeric := (p_valores ->> 'pct_comision_manilla')::numeric;
        v_pmes numeric := coalesce((p_valores ->> 'pct_comision_mesas')::numeric, 0);
        v_man boolean := coalesce((p_valores ->> 'comision_manillas')::boolean, true);
        v_mes boolean := coalesce((p_valores ->> 'comision_mesas')::boolean, false);
        v_comb boolean := coalesce((p_valores ->> 'comision_combos')::boolean, false);
        v_modo text;
begin
  if rol_en_club(p_club) is distinct from 'admin' and not es_platform_admin() then
    raise exception 'Solo administradores.' using errcode = '42501';
  end if;
  if v_log is null or v_log not in ('bt', 'aftr_jefes', 'premium') then
    raise exception 'Elegí cómo se trabaja en este boliche.';
  end if;
  if v_pct is null or v_pct < 0 or v_pct > 100 or v_pmes < 0 or v_pmes > 100 then
    raise exception 'Los porcentajes van de 0 a 100.';
  end if;
  -- la logística decide el modo: con jefes salvo en premium
  v_modo := case when not v_man and not v_mes and not v_comb then 'ninguno'
                 when v_log = 'premium' then 'relacionadores' else 'jefes' end;
  if p_evento is not null then
    update eventos set logistica = v_log, modo_comision = v_modo, pct_boliche = round(100 - v_pct)::int,
           comision_manillas = v_man, comision_mesas = v_mes, pct_comision_mesas = v_pmes,
           comision_combos = v_comb, config_v2 = true,
           -- en las logísticas de AFTR el evento nace a la venta; en bt, no
           aftr_publico = (v_log <> 'bt')
     where id = p_evento and club_id = p_club;
    if not found then raise exception 'Evento no encontrado.'; end if;
  else
    perform impl.aplicar_logistica(p_club, v_log);
    update clubs set comision_manillas = v_man, pct_boliche_def = 100 - v_pct,
           comision_mesas = v_mes, pct_comision_mesas = v_pmes, comision_combos = v_comb
     where id = p_club;
    if not found then raise exception 'Boliche no encontrado.'; end if;
  end if;
  return public.opciones_operacion(p_club, p_evento);
end;
$$;

-- Los boliches que ya existen trabajan a mano: es lo que vienen haciendo.
update clubs set logistica = 'bt' where logistica is null;
select impl.aplicar_logistica(id, 'bt') from clubs where logistica = 'bt';
notify pgrst,'reload schema';
