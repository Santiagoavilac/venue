-- Cada boliche cobra a su propia cuenta.
--
-- Qué se rompía: hay una sola pasarela para toda la plataforma. Las
-- credenciales del banco viven en los secretos de la Edge Function
-- (BANECO_USER, BANECO_ACCOUNT, BANECO_AES_KEY, BANECO_PASSWORD), así que
-- todo lo que se cobra con QR cae en la misma cuenta, la del boliche que se
-- configuró primero. Con dos boliches más que traen su propia cuenta del Banco
-- Económico eso ya no da: la plata de uno terminaría en la cuenta del otro.
--
-- Cómo queda. La pasarela es un nombre corto -'sitroom', 'burtown'- y es lo
-- único que viaja por la base: las credenciales siguen en los secretos de la
-- función, con el nombre como prefijo:
--
--   BANECO_SITROOM_USER, BANECO_SITROOM_ACCOUNT,
--   BANECO_SITROOM_AES_KEY, BANECO_SITROOM_PASSWORD
--
-- y lo que no esté con prefijo se toma del BANECO_ de siempre, que pasa a ser
-- el de la plataforma. Así ningún número de cuenta ni ninguna llave entra en
-- la base, que es la razón por la que estaban en los secretos desde el
-- principio. Un boliche sin pasarela sigue cobrando como hoy.
--
-- El evento puede tener la suya, igual que `logistica`: una fiesta de terceros
-- en un boliche propio cobra aparte. Vacío = la del boliche.

-- ── dónde se elige ────────────────────────────────────────────────────
-- El nombre se valida acá porque termina armando el nombre de una variable de
-- entorno: cualquier cosa que no sea minúsculas, números y guion bajo no entra.
alter table public.clubs
  add column if not exists pasarela text
  check (pasarela is null or pasarela ~ '^[a-z0-9_]{1,24}$');
alter table public.eventos
  add column if not exists pasarela text
  check (pasarela is null or pasarela ~ '^[a-z0-9_]{1,24}$');

comment on column public.clubs.pasarela is
  'Nombre de la pasarela de cobro del boliche. Las credenciales viven en los secretos de la Edge Function con ese nombre como prefijo. Vacio: la de la plataforma.';
comment on column public.eventos.pasarela is
  'Pasarela propia del evento. Vacio: la del boliche.';

-- ── qué pasarela generó cada cobro ────────────────────────────────────
-- Igual que `ambiente`: el QR tiene que recordar con qué cuenta se generó,
-- porque el barrido lo consulta y lo anula después, cuando el boliche ya puede
-- haber cambiado de pasarela. Vacío = la de la plataforma.
alter table public.pago_qr
  add column if not exists pasarela text not null default ''
  check (pasarela = '' or pasarela ~ '^[a-z0-9_]{1,24}$');

-- ── quién cobra este pedido ───────────────────────────────────────────
-- Las recargas de PULSE son de la plataforma, no de un boliche: van siempre a
-- la pasarela de la plataforma. Las entradas y las mesas, al boliche del
-- evento; los pedidos de barra, al boliche de la mesa.
create or replace function public.baneco_pasarela_de(p_tipo text, p_id uuid)
returns text
language plpgsql stable security definer set search_path = public
as $$
declare v text;
begin
  if p_tipo = 'orden' then
    select coalesce(e.pasarela, c.pasarela) into v
      from aftr_ordenes o
      join eventos e on e.id = o.evento_id
      join clubs c on c.id = e.club_id
     where o.id = p_id;
  elsif p_tipo = 'pedido' then
    select coalesce(e.pasarela, c.pasarela) into v
      from aftr_bar_pedidos p
      join mesas m on m.id = p.mesa_id
      join eventos e on e.id = m.evento_id
      join clubs c on c.id = e.club_id
     where p.id = p_id;
  elsif p_tipo = 'recarga' then
    v := null;  -- PULSE es de la plataforma
  else
    raise exception 'Destino inválido';
  end if;
  return coalesce(v, '');
end $$;
revoke all on function public.baneco_pasarela_de(text, uuid) from public, anon, authenticated;

-- Las que están en uso, para que el barrido recorra todas y no sólo la de la
-- plataforma. Siempre incluye la vacía: es la que cobra lo que no tiene dueño.
create or replace function public.baneco_pasarelas()
returns text[]
language sql stable security definer set search_path = public
as $$
  select array(
    select distinct p from (
      select '' as p
      union select pasarela from clubs where pasarela is not null
      union select pasarela from eventos where pasarela is not null
      union select pasarela from pago_qr where pasarela <> ''
    ) t order by p)
$$;
revoke all on function public.baneco_pasarelas() from public, anon, authenticated;

-- ── el cobro guarda su pasarela ───────────────────────────────────────
-- Se inyecta en la función vigente en vez de copiar su cuerpo acá: ya se
-- reescribió dos veces esta semana y copiarlo es lo que se desincroniza.
do $migra$
declare v_def text;
begin
  select pg_get_functiondef(p.oid) into v_def
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.proname = 'baneco_reservar_destino';
  if v_def is null then raise exception 'No existe public.baneco_reservar_destino'; end if;
  if position('baneco_pasarela_de' in v_def) > 0 then return; end if;
  -- en la fila nueva
  v_def := replace(v_def,
    'insert into pago_qr(orden_id,recarga_id,pedido_id,ambiente,transaction_id,monto,moneda,vence,limite_at,estado,generacion_id,generacion_iniciada_at)',
    'insert into pago_qr(orden_id,recarga_id,pedido_id,ambiente,transaction_id,monto,moneda,vence,limite_at,estado,generacion_id,generacion_iniciada_at,pasarela)');
  v_def := replace(v_def,
    '           ''generando'',gen_random_uuid(),now())',
    '           ''generando'',gen_random_uuid(),now(),baneco_pasarela_de(p_tipo,p_id))');
  -- y en la que se reusa, porque el boliche pudo cambiar de cuenta en el medio
  v_def := replace(v_def,
    '    update pago_qr set estado=''generando'', generacion_id=gen_random_uuid(),',
    '    update pago_qr set estado=''generando'', generacion_id=gen_random_uuid(), pasarela=baneco_pasarela_de(p_tipo,p_id),');
  if position('baneco_pasarela_de' in v_def) = 0 then
    raise exception 'El cuerpo de baneco_reservar_destino cambió: revisar la inyección';
  end if;
  execute v_def;
end $migra$;

-- ── el barrido, uno por pasarela ──────────────────────────────────────
-- El cursor de conciliación era por ambiente. Cada cuenta tiene su propia
-- lista de pagados en el banco, así que ahora es por ambiente y pasarela.
alter table public.baneco_conciliacion
  add column if not exists pasarela text not null default '';

alter table public.baneco_conciliacion drop constraint if exists baneco_conciliacion_pkey;
alter table public.baneco_conciliacion add primary key (ambiente, pasarela);

create or replace function public.baneco_tomar_barrido(p_ambiente text, p_pasarela text default '')
returns jsonb
language plpgsql security definer set search_path = 'public'
as $function$
declare s baneco_conciliacion; v_dia date; v_token uuid := gen_random_uuid();
begin
  if p_ambiente not in ('certificacion', 'produccion') or p_ambiente is null then raise exception 'Ambiente inválido'; end if;
  if p_pasarela is null or (p_pasarela <> '' and p_pasarela !~ '^[a-z0-9_]{1,24}$') then raise exception 'Pasarela inválida'; end if;
  select coalesce(min((created_at at time zone 'America/La_Paz')::date), (now() at time zone 'America/La_Paz')::date)
    into v_dia from pago_qr where ambiente = p_ambiente and pasarela = p_pasarela;
  insert into baneco_conciliacion(ambiente, pasarela, dia) values(p_ambiente, p_pasarela, v_dia) on conflict do nothing;
  select * into s from baneco_conciliacion where ambiente = p_ambiente and pasarela = p_pasarela for update;
  if s.lease_hasta > now() then return null; end if;
  -- Una ejecución que murió generando un QR no habilita otra generación a ciegas.
  update pago_qr set estado = 'revisar', nota = 'GENERACION_INCIERTA'
    where ambiente = p_ambiente and pasarela = p_pasarela and estado = 'generando'
      and coalesce(generacion_iniciada_at, created_at) < now() - interval '2 minutes';
  update baneco_conciliacion set lease = v_token, lease_hasta = now() + interval '90 seconds', ultimo_intento = now()
    where ambiente = p_ambiente and pasarela = p_pasarela;
  return jsonb_build_object('dia', s.dia, 'token', v_token);
end;
$function$;

create or replace function public.baneco_finalizar_barrido(
  p_ambiente text, p_token uuid, p_dia_ok date, p_errores integer, p_pasarela text default ''
) returns void
language plpgsql security definer set search_path = 'public'
as $function$
begin
  update baneco_conciliacion set
    dia = case when p_dia_ok = dia
      then least(dia + 1, (now() at time zone 'America/La_Paz')::date) else dia end,
    ultimo_exito = case when p_dia_ok = dia then now() else ultimo_exito end,
    errores = greatest(0, p_errores), lease = null, lease_hasta = null
    where ambiente = p_ambiente and pasarela = p_pasarela and lease = p_token;
end;
$function$;

-- Las firmas viejas se borran: con las dos vivas, una llamada por nombre con
-- los argumentos de siempre es ambigua y PostgREST contesta 300.
drop function if exists public.baneco_tomar_barrido(text);
drop function if exists public.baneco_finalizar_barrido(text, uuid, date, integer);

revoke all on function public.baneco_tomar_barrido(text, text) from public, anon, authenticated;
revoke all on function public.baneco_finalizar_barrido(text, uuid, date, integer, text) from public, anon, authenticated;

notify pgrst,'reload schema';
