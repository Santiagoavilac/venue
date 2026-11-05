-- El boliche puede exigir el comprobante de cada entrada vendida.
--
-- En los boliches que no venden por AFTR la plata se mueve por fuera: el
-- cliente le paga al relacionador, el relacionador le rinde al jefe y el jefe
-- al boliche. Para que esa cadena cierre, el administrador tiene que poder
-- ver el comprobante de cada persona, no un total que le pasan de palabra.
--
-- Queda como opción del boliche y no como regla fija por una razón práctica:
-- hay apps ya publicadas que generan entradas sin mandar el comprobante, y si
-- el servidor lo exigiera de un día para el otro, el equipo que todavía no
-- actualizó no podría vender. El administrador lo prende cuando su gente tiene
-- la app nueva.
--
-- Las entradas sin precio quedan afuera: una cortesía no tiene pago que
-- mostrar.
alter table public.clubs
  add column if not exists exige_comprobante boolean not null default false;

comment on column public.clubs.exige_comprobante is
  'Si cada entrada con precio necesita la foto del pago para generarse.';

-- ── la opción, en el mismo formulario que ya se dibuja solo ───────────
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
    )
    -- sólo a nivel boliche: es cómo cobra el boliche, no cómo paga un evento
    || case when p_evento is null then jsonb_build_array(
         jsonb_build_object('clave', 'exige_comprobante', 'tipo', 'si_no',
           'etiqueta', 'Pedir el comprobante de cada entrada',
           'valor', coalesce(c.exige_comprobante, false),
           'ayuda', 'Para vender hay que adjuntar la foto del pago. Sirve cuando la plata se mueve por fuera: el relacionador le rinde al jefe y el jefe al boliche, y vos ves el comprobante de cada persona.'))
       else '[]'::jsonb end);
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
        v_comp boolean := (p_valores ->> 'exige_comprobante')::boolean;
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
           comision_mesas = v_mes, pct_comision_mesas = v_pmes, comision_combos = v_comb,
           exige_comprobante = coalesce(v_comp, exige_comprobante)
     where id = p_club;
    if not found then raise exception 'Boliche no encontrado.'; end if;
  end if;
  return public.opciones_operacion(p_club, p_evento);
end;
$$;
notify pgrst,'reload schema';

-- ── y la regla al vender ──────────────────────────────────────────────
-- Con la opción prendida, una entrada con precio no se genera sin la foto
-- del pago. La gratis sí: no hay pago que mostrar.
create or replace function impl.exige_comprobante(p_club text) returns boolean
language sql stable security definer set search_path = public as $$
  select coalesce(exige_comprobante, false) from clubs where id = p_club
$$;

do $migra$
declare v_def text;
begin
  -- se reescribe la función vigente agregándole el chequeo, sin volver a
  -- copiar su cuerpo acá: así no quedan dos versiones que se desincronizan
  select pg_get_functiondef(p.oid) into v_def
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'impl' and p.proname = 'generar_entrada';
  if v_def is null then raise exception 'impl.generar_entrada no existe'; end if;
  if position('impl.exige_comprobante' in v_def) > 0 then return; end if;
  v_def := replace(v_def,
    '  insert into entradas (id, evento_id, code, cliente, rrpp_id, precio, estado, created_at, mesa_id, fase_id,',
    '  if v_precio > 0 and p_comprobante_url is null and impl.exige_comprobante(e.club_id) then' || chr(10) ||
    '    raise exception ''Adjuntá el comprobante del pago para generar esta entrada.'';' || chr(10) ||
    '  end if;' || chr(10) || chr(10) ||
    '  insert into entradas (id, evento_id, code, cliente, rrpp_id, precio, estado, created_at, mesa_id, fase_id,');
  execute v_def;
end $migra$;
notify pgrst,'reload schema';
