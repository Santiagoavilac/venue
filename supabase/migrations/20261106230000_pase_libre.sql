-- Pase libre: el QR que siempre entra.
--
-- Hoy existe "de la casa" (ingreso_sin_tope), pero es por PERSONA y por
-- boliche: marca a un relacionador y entonces TODAS sus entradas quedan sin
-- hora tope. No sirve para lo que hace falta, que es el QR del dueño o del
-- administrador: uno solo, que entra siempre, que entra y sale, y que el
-- portero no puede frenar por error.
--
-- Pase libre es por entrada y lo pone el administrador del boliche al
-- generarla. Hace tres cosas, que son las tres que se pidieron:
--
--   1. no le corre la hora tope del evento;
--   2. no se consume: se puede escanear de nuevo y vuelve a decir que pasa,
--      porque el dueño entra y sale toda la noche;
--   3. el botón de "no pasó el control" no la toca: contesta `protegida`.
--
-- Anularla sigue siendo posible: si no, una entrada mal dada no se podría
-- sacar nunca. Lo que no se puede es frenarla en la puerta por accidente.

alter table public.entradas
  add column if not exists pase_libre boolean not null default false;
comment on column public.entradas.pase_libre is
  'Entra siempre, entra y sale, y la puerta no la puede frenar. La pone el admin del boliche.';

-- ── al generarla ──────────────────────────────────────────────────────
-- El parámetro va al final con default false: las apps publicadas siguen
-- llamando con cinco argumentos y generan entradas normales.
do $migra$
declare v_def text;
begin
  select pg_get_functiondef(p.oid) into v_def
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'impl' and p.proname = 'generar_entrada';
  if v_def is null then raise exception 'impl.generar_entrada no existe'; end if;
  if position('p_pase_libre' in v_def) > 0 then return; end if;

  -- un parámetro más, y la columna en el insert
  v_def := replace(v_def,
    'p_metodo text DEFAULT NULL::text)',
    'p_metodo text DEFAULT NULL::text, p_pase_libre boolean DEFAULT false)');
  v_def := replace(v_def,
    '  insert into entradas (id, evento_id, code, cliente, rrpp_id, precio, estado, created_at, mesa_id, fase_id,',
    '  -- sólo el administrador del boliche: un relacionador no se regala' || chr(10) ||
    '  -- entradas que la puerta no puede frenar' || chr(10) ||
    '  if p_pase_libre and rol_en_club(e.club_id) is distinct from ''admin'' and not es_platform_admin() then' || chr(10) ||
    '    raise exception ''El pase libre lo da el administrador del boliche.'' using errcode = ''42501'';' || chr(10) ||
    '  end if;' || chr(10) || chr(10) ||
    '  insert into entradas (id, evento_id, code, cliente, rrpp_id, precio, estado, created_at, mesa_id, fase_id,');
  -- y la columna en el insert
  v_def := replace(v_def,
    '                        comprobante_url, metodo_pago)',
    '                        comprobante_url, metodo_pago, pase_libre)');
  v_def := replace(v_def,
    '          p_comprobante_url, nullif(trim(coalesce(p_metodo, '''''''')), ''''''''))',
    '          p_comprobante_url, nullif(trim(coalesce(p_metodo, '''''''')), ''''''''), coalesce(p_pase_libre, false))');
  execute v_def;
end $migra$;

-- `create or replace` con un parámetro nuevo no reemplaza: crea OTRA función,
-- y con las dos una llamada de cinco argumentos queda ambigua y las apps
-- publicadas dejan de generar entradas. Se borra la vieja: la nueva responde
-- igual por el default.
drop function if exists public.generar_entrada(uuid, text, uuid, text, text);
drop function if exists impl.generar_entrada(uuid, text, uuid, text, text);

-- la guarda de public.generar_entrada se regenera para la firma nueva
do $gen$
declare r record; f record; v_cuerpo text;
begin
  for f in
    select p.oid, pg_get_function_arguments(p.oid) as args,
           pg_get_function_identity_arguments(p.oid) as ident,
           pg_get_function_result(p.oid) as res,
           coalesce((select string_agg(quote_ident(nm), ', ' order by ord)
                       from unnest(p.proargnames[1:p.pronargs]) with ordinality as a(nm, ord)), '') as llamada
      from pg_proc p join pg_namespace n on n.oid = p.pronamespace
     where n.nspname = 'impl' and p.proname = 'generar_entrada'
  loop
    select guarda into r from impl.rpc_permiso where fn = 'generar_entrada';
    execute format('drop function if exists public.generar_entrada(%s)', f.ident);
    execute format($f$
      create or replace function public.generar_entrada(%s) returns %s
      language plpgsql security definer set search_path = public as $cuerpo$
      declare v_rol text; begin
        %s
        return impl.generar_entrada(%s);
      end $cuerpo$
    $f$, f.args, f.res, r.guarda, f.llamada);
    execute format('comment on function public.generar_entrada(%s) is %L', f.ident, 'venue:guarda');
    execute format('revoke all on function public.generar_entrada(%s) from public, anon', f.ident);
    execute format('grant execute on function public.generar_entrada(%s) to authenticated, service_role', f.ident);
  end loop;
end $gen$;

-- ── en la puerta ──────────────────────────────────────────────────────
-- El pase libre no se consume, así que no se marca como usada: la tabla exige
-- que `estado='usada'` y `used_at` vayan juntos, y acá no corresponde ninguno
-- de los dos. Cuándo entró queda en el registro de escaneos de la puerta.
create or replace function impl.validar_entrada(p_evento uuid, p_code text)
returns json language plpgsql security definer set search_path to 'public', 'pg_temp'
as $function$
declare x entradas; v_club text; v_tope timestamptz; v_rrpp text; v_team text; v_mesa text; v_sin_tope boolean;
begin
 select * into x from entradas where evento_id=p_evento and code=upper(p_code) for update;
 if not found then return json_build_object('resultado','no_existe'); end if;
 if x.reventa_sucesora_id is not null then return json_build_object('resultado','reemplazada','cliente',x.cliente,'code',x.code); end if;
 if x.reventa_oferta_id is not null then return json_build_object('resultado','bloqueada','cliente',x.cliente,'code',x.code); end if;
 select club_id,entrada_hasta into v_club,v_tope from eventos where id=p_evento;
 select p.nombre,t.nombre into v_rrpp,v_team from profiles p left join teams t on t.id=p.team_id where p.id=x.rrpp_id;
 select etiqueta into v_mesa from mesas where id=x.mesa_id;
 v_sin_tope:=x.pase_libre or exists(select 1 from ingreso_sin_tope where user_id=x.rrpp_id and club_id=v_club);
 if x.estado='anulada' then return json_build_object('resultado','anulada','cliente',x.cliente,'code',x.code); end if;
 -- El pase libre entra y sale toda la noche: no se consume, así que un
 -- segundo escaneo vuelve a decir que pasa en vez de "ya usada".
 if x.pase_libre then
  return json_build_object('resultado','valida','cliente',x.cliente,'code',x.code,'rrpp',v_rrpp,
    'team',v_team,'mesa',v_mesa,'sin_tope',true,'pase_libre',true);
 end if;
 if x.estado='usada' then return json_build_object('resultado','usada','cliente',x.cliente,'code',x.code,'used_at',x.used_at,'rrpp',v_rrpp,'team',v_team,'mesa',v_mesa); end if;
 if v_tope is not null and now()>v_tope and not v_sin_tope then return json_build_object('resultado','fuera_hora','cliente',x.cliente,'code',x.code); end if;
 update entradas set estado='usada',used_at=now(),portero_id=auth.uid() where id=x.id and code=upper(p_code) and estado='valida'
 and reventa_oferta_id is null and reventa_sucesora_id is null;
 if not found then return json_build_object('resultado','no_existe'); end if;
 return json_build_object('resultado','valida','cliente',x.cliente,'code',x.code,'rrpp',v_rrpp,'team',v_team,'mesa',v_mesa,'sin_tope',v_sin_tope);
end $function$;
notify pgrst,'reload schema';
-- `impl.entradas_vigentes` es una vista con menos columnas que la tabla, y
-- `select * into e` (de tipo entradas) rellena por posición: pase_libre, que es
-- la última columna de la tabla, llegaba siempre en false. Se lee de la tabla.
create or replace function impl.marcar_filtro_entrada(p_evento uuid, p_code text)
returns json language plpgsql security definer set search_path to 'public'
as $function$
declare e entradas%rowtype; v_club text; v_rrpp text; v_marcar boolean; v_libre boolean;
begin
  select * into e from impl.entradas_vigentes where evento_id = p_evento and code = upper(p_code);
  if not found then return json_build_object('resultado', 'no_existe'); end if;
  select club_id into v_club from eventos where id = p_evento;
  select coalesce(x.pase_libre, false) into v_libre
    from entradas x where x.evento_id = p_evento and x.code = upper(p_code);
  if v_libre
     or exists (select 1 from ingreso_sin_tope st where st.user_id = e.rrpp_id and st.club_id = v_club) then
    return json_build_object('resultado', 'protegida');
  end if;
  select p.nombre into v_rrpp from profiles p where p.id = e.rrpp_id;
  v_marcar := e.filtro_at is null;
  update entradas
     set filtro_at  = case when v_marcar then now() end,
         filtro_por = case when v_marcar then auth.uid() end
   where id = e.id;
  return json_build_object('resultado', 'ok', 'marcado', v_marcar, 'nombre', e.cliente, 'rrpp', v_rrpp);
end;
$function$;
notify pgrst,'reload schema';
-- El buscador de la puerta marca "de la casa" para no dejar frenar esas
-- entradas; el pase libre entra en la misma bolsa, que es lo que el guardia
-- necesita ver.
create or replace function impl.buscar_registros(p_evento uuid, p_q text)
returns setof jsonb language sql stable security definer set search_path to 'public'
as $function$
  with q as (select unaccent(lower(p_q)) as needle),
  de_lista as (
    select jsonb_build_object('id', r.id, 'rrpp', p.nombre, 'tipo', 'lista', 'lista', lt.nombre,
             'nombre', r.nombre, 'sin_tope', false, 'filtro_at', r.filtro_at,
             'ingreso_at', r.ingreso_at, 'qr_anulado', r.qr_anulado,
             'qr_anulado_motivo', r.qr_anulado_motivo) as fila,
           false as es_entrada, r.lista_tipo_id as grupo, null::uuid as grupo2, r.created_at as orden_at
    from registros r join lista_tipos lt on lt.id = r.lista_tipo_id
    join profiles p on p.id = r.rrpp_id cross join q
    where r.evento_id = p_evento and unaccent(lower(r.nombre)) ilike '%' || q.needle || '%'
  ),
  de_entrada as (
    select jsonb_build_object('id', e.id, 'code', e.code, 'rrpp', p.nombre, 'tipo', 'entrada',
             'lista', case when e.mesa_id is not null then 'Mesa ' || ms.etiqueta else 'Prepagada' end,
             'estado', e.estado, 'nombre', e.cliente,
             'sin_tope', coalesce(t.pase_libre, false) or exists (
               select 1 from ingreso_sin_tope st where st.user_id = e.rrpp_id and st.club_id = ev.club_id),
             'pase_libre', coalesce(t.pase_libre, false),
             'filtro_at', e.filtro_at, 'ingreso_at', e.used_at) as fila,
           true as es_entrada, null::uuid as grupo, e.mesa_id as grupo2, e.created_at as orden_at
    from impl.entradas_vigentes e
    join entradas t on t.id = e.id
    join eventos ev on ev.id = e.evento_id
    join profiles p on p.id = e.rrpp_id
    left join mesas ms on ms.id = e.mesa_id cross join q
    where e.evento_id = p_evento and unaccent(lower(e.cliente)) ilike '%' || q.needle || '%'
  )
  select fila from (select * from de_lista union all select * from de_entrada) u
   order by es_entrada, grupo desc, (grupo2 is null), orden_at asc;
$function$;
notify pgrst,'reload schema';
