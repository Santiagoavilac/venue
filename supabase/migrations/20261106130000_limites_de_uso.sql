-- Un límite de uso, en una sola pieza, y el buscador deja de raspar.
--
-- En AFTR casi no hay límites: con un `while true; do curl` se puede pedir el
-- feed, buscar gente, crear órdenes o publicar historias todo lo que aguante la
-- base. Lo único que ya tenía freno era la puerta (`intento_validacion`, en
-- db/19), porque ahí el abuso es obvio: probar códigos al azar.
--
-- Acá va la misma idea para AFTR, en una pieza compartida. No hay nada nuevo
-- que entender: una tabla de intentos y una función que cuenta y corta.
--
-- Y de paso lo más urgente que no tenía freno: `aftr_buscar_usuario` no escapa
-- los comodines de `like`, así que `aftr_buscar_usuario('%%')` arma
-- `nombre like '%%%'` y devuelve diez cuentas cualesquiera del directorio. Con
-- dos caracteres mínimos y sin escape, eso es un volcado del padrón de a diez.

-- ── quién está pidiendo ───────────────────────────────────────────────
-- La sesión cuando hay, y si no la IP que informa el proxy. No es infalible
-- -una IP se cambia- pero sube el costo de raspar de "gratis" a "molesto", que
-- es lo que un límite puede hacer.
create or replace function impl.aftr_actor() returns text
language sql stable set search_path = public as $$
  select coalesce(
    auth.uid()::text,
    'ip:' || coalesce(nullif(split_part(
      coalesce(nullif(current_setting('request.headers', true), '')::json ->> 'x-forwarded-for', ''),
      ',', 1), ''), 'sin-ip'))
$$;

create table if not exists public.aftr_intentos (
  id     bigint generated always as identity primary key,
  actor  text not null,
  accion text not null,
  at     timestamptz not null default now()
);
create index if not exists aftr_intentos_busca on public.aftr_intentos (accion, actor, at desc);
alter table public.aftr_intentos enable row level security;  -- sin políticas: sólo las funciones
comment on table public.aftr_intentos is
  'Intentos por actor y accion, para los limites de uso. La limpia el cron.';

/* Cuenta los intentos de este actor en la ventana y corta si pasó el tope.
   Anota el intento ANTES de dejar pasar: si la operación falla igual cuenta,
   porque reintentar mil veces algo que falla es justo lo que se quiere frenar. */
create or replace function impl.aftr_limite(p_accion text, p_max int, p_ventana interval,
                                            p_mensaje text default null)
returns void language plpgsql security definer set search_path = public as $$
declare v_actor text := impl.aftr_actor(); v_n int;
begin
  select count(*) into v_n from aftr_intentos
   where accion = p_accion and actor = v_actor and at > now() - p_ventana;
  if v_n >= p_max then
    raise exception '%', coalesce(p_mensaje, 'Estás yendo muy rápido. Esperá un momento y volvé a intentar.')
      using errcode = '53400';
  end if;
  insert into aftr_intentos (actor, accion) values (v_actor, p_accion);
end $$;

/* La limpieza va con los vencimientos, que ya corren cada minuto. Un día de
   historia alcanza: la ventana más larga de un límite es de una hora. */
create or replace function impl.aftr_limpiar() returns void
language sql security definer set search_path = public as $$
  delete from aftr_intentos where at < now() - interval '1 day'
$$;

select cron.schedule('aftr-limpiar-intentos', '7 * * * *', $$select impl.aftr_limpiar();$$)
 where not exists (select 1 from cron.job where jobname = 'aftr-limpiar-intentos');

-- ── el buscador, con escape y con freno ───────────────────────────────
-- Volátil y no estable: ahora anota el intento, y una función estable no puede
-- escribir. Se llama por POST, así que no cambia nada para el cliente.
create or replace function public.aftr_buscar_usuario(p_q text) returns jsonb
language plpgsql security definer set search_path to 'public'
as $function$
declare v_q text := lower(trim(both '@ ' from coalesce(p_q, ''))); v_like text;
begin
  perform impl.aftr_yo();
  -- tres caracteres: con dos, 'ma' ya devuelve medio directorio
  if length(v_q) < 3 then return '[]'::jsonb; end if;
  perform impl.aftr_limite('buscar_usuario', 30, interval '1 minute',
    'Demasiadas búsquedas. Esperá un minuto.');
  -- los comodines del cliente son texto, no patrón: '%%' buscaba '%%%'
  v_like := replace(replace(replace(v_q, '\', '\\'), '%', '\%'), '_', '\_');
  return coalesce((select jsonb_agg(jsonb_build_object('usuario', c.usuario, 'nombre', c.nombre, 'foto', c.foto_url))
                     from (select * from aftr_clientes
                            where user_id <> auth.uid()
                              and (usuario like v_like || '%' or lower(nombre) like '%' || v_like || '%')
                            order by usuario = v_q desc, usuario limit 10) c), '[]'::jsonb);
end;
$function$;
revoke all on function public.aftr_buscar_usuario(text) from public, anon;
grant execute on function public.aftr_buscar_usuario(text) to authenticated, service_role;

notify pgrst,'reload schema';

-- ── los frenos, uno por acción ────────────────────────────────────────
-- Se inyecta la línea en el cuerpo vigente de cada función en vez de volver a
-- copiar ocho cuerpos acá: copiados se desincronizan con la próxima migración
-- que los toque, y el bug que eso deja es de los que no se ven hasta que pasa.
--
-- Los números no son de seguridad, son de realidad: nadie compra veinte veces
-- por hora ni publica diez historias en diez minutos. Al que lo intenta le
-- sale un mensaje claro, no un error crudo.
do $migra$
declare
  f record;
  v_def text;
  v_linea text;
  v_pos int;
  frenos jsonb := jsonb_build_array(
    jsonb_build_object('n','aftr_comprar','a','comprar','max',20,'v','1 hour',
      'm','Muchos pedidos en poco tiempo. Pagá o cancelá los que tenés y volvé a intentar.'),
    jsonb_build_object('n','aftr_reservar_mesa','a','reservar_mesa','max',10,'v','1 hour',
      'm','Muchas reservas de mesa en poco tiempo. Esperá un rato.'),
    jsonb_build_object('n','aftr_recargar_pulse','a','recargar','max',10,'v','1 hour',
      'm','Muchas recargas en poco tiempo. Esperá un rato.'),
    jsonb_build_object('n','aftr_transferir','a','transferir','max',20,'v','1 hour',
      'm','Muchas transferencias en poco tiempo. Esperá un rato.'),
    jsonb_build_object('n','aftr_anotarme_lista','a','anotarme',  'max',15,'v','1 hour',
      'm','Te anotaste en muchas listas en poco tiempo. Esperá un rato.'),
    jsonb_build_object('n','aftr_mesa_invitar','a','invitar_mesa','max',40,'v','1 hour',
      'm','Muchas invitaciones en poco tiempo. Esperá un rato.'),
    jsonb_build_object('n','aftr_crear_perfil','a','crear_perfil','max',5,'v','1 hour',
      'm','Demasiados intentos. Esperá un rato.'),
    jsonb_build_object('n','aftr_cambiar_foto','a','cambiar_foto','max',10,'v','1 hour',
      'm','Cambiaste la foto muchas veces. Esperá un rato.')
  );
begin
  for f in select e.valor from jsonb_array_elements(frenos) as e(valor) loop
    select pg_get_functiondef(p.oid) into v_def
      from pg_proc p join pg_namespace n on n.oid = p.pronamespace
     where n.nspname = 'public' and p.proname = f.valor ->> 'n'
       and p.prolang = (select oid from pg_language where lanname = 'plpgsql');
    if v_def is null then raise exception 'No existe public.% en plpgsql', f.valor ->> 'n'; end if;
    if position('impl.aftr_limite' in v_def) > 0 then continue; end if;
    v_linea := format('  perform impl.aftr_limite(%L, %s, interval %L, %L);',
      f.valor ->> 'a', f.valor ->> 'max', f.valor ->> 'v', f.valor ->> 'm') || chr(10);
    -- después del `begin` del bloque exterior: la primera palabra `begin`
    -- suelta que aparece dentro del cuerpo. Se busca como palabra entera y no
    -- como línea, porque varias funciones de acá están escritas apretadas y
    -- tienen el `declare` y el `begin` en el mismo renglón.
    v_pos := regexp_instr(v_def, '\mbegin\M', position('$function$' in v_def) + 10, 1, 1);
    if v_pos = 0 then raise exception 'No encuentro el begin de %', f.valor ->> 'n'; end if;
    v_def := left(v_def, v_pos - 1) || chr(10) || v_linea || substr(v_def, v_pos);
    execute v_def;
  end loop;
end $migra$;
notify pgrst,'reload schema';
