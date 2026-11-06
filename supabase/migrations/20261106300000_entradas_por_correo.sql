-- Las entradas también llegan por correo.
--
-- Hasta ahora la entrada vive sólo dentro de AFTR. Para quien compra con
-- cuenta eso alcanza: entra desde cualquier teléfono y ahí está. Para quien
-- compra **sin cuenta** no: su sesión es anónima y vive en ese navegador, así
-- que si cambia de teléfono, borra los datos del sitio o entra desde otro
-- lado, se queda sin la entrada que pagó. El correo es la copia que no depende
-- del dispositivo.
--
-- Por qué una cola y no mandar el correo ahí mismo: el correo se encola dentro
-- de la misma transacción que emite las entradas, pero se **manda después**,
-- desde un cron. Si se mandara en el momento habría que hacer una llamada HTTP
-- adentro de la transacción que emite: si Resend tarda o se cae, se cae la
-- emisión de una entrada que ya está pagada. Al revés es seguro: la entrada
-- existe siempre, y el correo se reintenta hasta que sale.
--
-- No se guarda nada del correo que no haga falta para mandarlo. El QR no se
-- guarda acá: se arma al mandar, a partir del código de cada entrada.

create table if not exists public.correos (
  id uuid primary key default gen_random_uuid(),
  tipo text not null check (tipo in ('entradas')),
  destino text not null,
  datos jsonb not null default '{}'::jsonb,
  estado text not null default 'pendiente' check (estado in ('pendiente', 'enviado', 'fallido')),
  intentos int not null default 0,
  error text,
  created_at timestamptz not null default now(),
  -- el reintento se espacia solo: si Resend está caído, no se lo machaca
  proximo_intento timestamptz not null default now(),
  enviado_at timestamptz
);

comment on table public.correos is
  'Cola de correos. Se encola en la misma transaccion que emite la entrada y se manda despues, desde el cron: si el correo fallara en el momento, se caeria la emision de una entrada ya pagada.';

-- Sin políticas: sólo la llave de servicio entra. Acá hay correos y nombres de
-- gente, y nadie de la app tiene por qué leer la cola de los demás.
alter table public.correos enable row level security;
revoke all on table public.correos from anon, authenticated;

create index if not exists correos_por_mandar on public.correos (proximo_intento)
  where estado = 'pendiente';

-- ── encolar ───────────────────────────────────────────────────────────
create or replace function impl.correo_encolar(p_tipo text, p_destino text, p_datos jsonb)
returns void language plpgsql security definer set search_path = public, pg_temp
as $$
begin
  -- sin correo no hay nada que mandar, y no es motivo para fallar nada:
  -- la entrada ya existe y está en Accesos
  if p_destino is null or p_destino !~ '^[^@[:space:]]+@[^@[:space:]]+\.[A-Za-z]{2,}$' then
    return;
  end if;
  insert into correos (tipo, destino, datos) values (p_tipo, lower(trim(p_destino)), p_datos);
end $$;

-- ── a dónde se le manda a cada quien ──────────────────────────────────
-- El de su perfil si lo dejó al comprar sin cuenta; si no, el de la cuenta con
-- la que entró (Google o Apple).
create or replace function impl.correo_de(p_cliente uuid)
returns text language sql stable security definer set search_path = public, pg_temp
as $$
  select coalesce(
    nullif(trim((select email from aftr_clientes where user_id = p_cliente)), ''),
    nullif(trim((select email from auth.users where id = p_cliente)), ''))
$$;

-- ── la entrada emitida encola su correo ───────────────────────────────
-- Se inyecta en el cuerpo vigente en vez de copiarlo acá: esta función se
-- toca seguido y copiarla es lo que se desincroniza.
do $migra$
declare v_def text;
begin
  select pg_get_functiondef(p.oid) into v_def
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'impl' and p.proname = 'aftr_emitir_orden';
  if v_def is null then raise exception 'No existe impl.aftr_emitir_orden'; end if;
  if position('correo_encolar' in v_def) > 0 then return; end if;
  v_def := replace(v_def,
    '  update aftr_ordenes set estado = ''confirmada'', confirmada_por = p_por, confirmada_at = now()
   where id = o.id;
  return v_n;',
    '  update aftr_ordenes set estado = ''confirmada'', confirmada_por = p_por, confirmada_at = now()
   where id = o.id;

  -- La copia que no depende del teléfono. Va con los códigos de esta orden:
  -- el QR se arma al mandar, no se guarda.
  perform impl.correo_encolar(''entradas'', impl.correo_de(o.cliente_id), jsonb_build_object(
    ''nombre'', c.nombre,
    ''orden'', o.id,
    ''evento'', (select e.nombre from eventos e where e.id = o.evento_id),
    ''club'', (select cl.nombre from eventos e join clubs cl on cl.id = e.club_id where e.id = o.evento_id),
    ''fecha'', (select to_char(e.fecha, ''DD/MM/YYYY'') from eventos e where e.id = o.evento_id),
    ''hora'', (select to_char(e.hora_inicio, ''HH24:MI'') from eventos e where e.id = o.evento_id),
    ''tipo'', o.tipo,
    ''codigos'', (select coalesce(jsonb_agg(x.code order by x.created_at), ''[]''::jsonb)
                    from entradas x where x.cliente_id = o.cliente_id and x.evento_id = o.evento_id
                     and x.estado = ''valida'' and x.created_at >= now() - interval ''5 seconds'')));

  return v_n;');
  if position('correo_encolar' in v_def) = 0 then
    raise exception 'El cuerpo de impl.aftr_emitir_orden cambió: revisar la inyección';
  end if;
  execute v_def;
end $migra$;

-- ── el cartero ────────────────────────────────────────────────────────
-- Toma lo que toca mandar y lo marca. El lease evita que dos corridas del cron
-- manden el mismo correo dos veces.
create or replace function public.correos_tomar(p_cuantos int default 20)
returns setof correos language plpgsql security definer set search_path = public, pg_temp
as $$
begin
  return query
  update correos set proximo_intento = now() + interval '2 minutes', intentos = intentos + 1
   where id in (
     select id from correos
      where estado = 'pendiente' and proximo_intento <= now()
      order by proximo_intento
      limit greatest(1, least(coalesce(p_cuantos, 20), 50))
      for update skip locked)
  returning *;
end $$;

create or replace function public.correos_resultado(p_id uuid, p_ok boolean, p_error text default null)
returns void language plpgsql security definer set search_path = public, pg_temp
as $$
begin
  update correos set
    -- a los cinco intentos se deja de insistir: la entrada está en Accesos
    estado = case when p_ok then 'enviado' when intentos >= 5 then 'fallido' else 'pendiente' end,
    enviado_at = case when p_ok then now() end,
    error = case when p_ok then null else left(coalesce(p_error, 'sin detalle'), 300) end,
    -- espera creciente: 2, 4, 8, 16 minutos
    proximo_intento = case when p_ok then proximo_intento
                           else now() + (interval '2 minutes' * power(2, least(intentos, 4))) end
   where id = p_id;
end $$;

revoke all on function public.correos_tomar(int) from public, anon, authenticated;
revoke all on function public.correos_resultado(uuid, boolean, text) from public, anon, authenticated;

notify pgrst,'reload schema';
