-- Las notificaciones push: a quién, y qué se le manda.
--
-- Un teléfono puede tener las dos apps, y la misma persona puede entrar desde
-- varios teléfonos. Por eso lo que se guarda es **el aparato**, no la persona:
-- una fila por token, con de qué app es. Si el mismo token aparece de nuevo
-- -pasa cuando la app se reinstala o Google rota el token- se actualiza el
-- dueño en vez de duplicar.
create table if not exists public.dispositivos (
  token text primary key,
  user_id uuid not null references auth.users(id) on delete cascade,
  app text not null check (app in ('aftr', 'venue')),
  plataforma text not null check (plataforma in ('ios', 'android')),
  created_at timestamptz not null default now(),
  visto_at timestamptz not null default now()
);

comment on table public.dispositivos is
  'Un aparato por token. La misma persona puede tener varios y el mismo aparato las dos apps.';

create index if not exists dispositivos_de_cada_uno on public.dispositivos (user_id, app);

alter table public.dispositivos enable row level security;
revoke all on table public.dispositivos from anon, authenticated;

-- Cada quien ve y borra los suyos, y nada más. Se escribe por la RPC de abajo.
drop policy if exists "mis aparatos" on public.dispositivos;
create policy "mis aparatos" on public.dispositivos
  for select to authenticated using (user_id = auth.uid());
drop policy if exists "borrar los mios" on public.dispositivos;
create policy "borrar los mios" on public.dispositivos
  for delete to authenticated using (user_id = auth.uid());
grant select, delete on public.dispositivos to authenticated;

-- ── registrar el aparato ──────────────────────────────────────────────
create or replace function public.registrar_dispositivo(
  p_token text, p_app text, p_plataforma text
) returns void
language plpgsql security definer set search_path = public, pg_temp
as $$
begin
  if auth.uid() is null then
    raise exception 'Iniciá sesión.' using errcode = '28000';
  end if;
  if p_token is null or length(trim(p_token)) < 20 or length(p_token) > 400 then
    raise exception 'Token de notificaciones inválido.';
  end if;
  if p_app not in ('aftr', 'venue') or p_plataforma not in ('ios', 'android') then
    raise exception 'Aparato inválido.';
  end if;
  -- el token puede mudarse de dueño: el mismo teléfono prestado, o alguien que
  -- cierra sesión y entra con otra cuenta. Gana el último que lo registró.
  insert into dispositivos (token, user_id, app, plataforma)
  values (trim(p_token), auth.uid(), p_app, p_plataforma)
  on conflict (token) do update set
    user_id = excluded.user_id, app = excluded.app,
    plataforma = excluded.plataforma, visto_at = now();
end $$;
revoke all on function public.registrar_dispositivo(text, text, text) from public, anon;
grant execute on function public.registrar_dispositivo(text, text, text) to authenticated;

-- ── la cola de avisos ─────────────────────────────────────────────────
-- Mismo trato que los correos y por la misma razón: se encola dentro de la
-- transacción que lo provoca y se manda después. Una notificación que falla
-- no puede voltear la operación que la generó.
create table if not exists public.avisos_push (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  app text not null check (app in ('aftr', 'venue')),
  titulo text not null,
  cuerpo text not null,
  datos jsonb not null default '{}'::jsonb,
  estado text not null default 'pendiente' check (estado in ('pendiente', 'enviado', 'fallido')),
  intentos int not null default 0,
  error text,
  created_at timestamptz not null default now(),
  proximo_intento timestamptz not null default now(),
  enviado_at timestamptz
);

alter table public.avisos_push enable row level security;
revoke all on table public.avisos_push from anon, authenticated;
create index if not exists avisos_por_mandar on public.avisos_push (proximo_intento)
  where estado = 'pendiente';

create or replace function impl.avisar(
  p_user uuid, p_app text, p_titulo text, p_cuerpo text, p_datos jsonb default '{}'::jsonb
) returns void
language plpgsql security definer set search_path = public, pg_temp
as $$
begin
  if p_user is null then return; end if;
  -- sin aparato registrado no hay nada que mandar, y no es motivo para fallar
  if not exists (select 1 from dispositivos where user_id = p_user and app = p_app) then
    return;
  end if;
  insert into avisos_push (user_id, app, titulo, cuerpo, datos)
  values (p_user, p_app, left(p_titulo, 120), left(p_cuerpo, 300), coalesce(p_datos, '{}'::jsonb));
end $$;

create or replace function public.push_tomar(p_cuantos int default 20)
returns table (id uuid, app text, titulo text, cuerpo text, datos jsonb, tokens text[])
language plpgsql security definer set search_path = public, pg_temp
as $$
begin
  return query
  with tomados as (
    update avisos_push set proximo_intento = now() + interval '2 minutes', intentos = intentos + 1
     where avisos_push.id in (
       select a.id from avisos_push a
        where a.estado = 'pendiente' and a.proximo_intento <= now()
        order by a.proximo_intento
        limit greatest(1, least(coalesce(p_cuantos, 20), 50))
        for update skip locked)
    returning *)
  select t.id, t.app, t.titulo, t.cuerpo, t.datos,
         array(select d.token from dispositivos d
                where d.user_id = t.user_id and d.app = t.app)
    from tomados t;
end $$;

create or replace function public.push_resultado(
  p_id uuid, p_ok boolean, p_error text default null, p_muertos text[] default null
) returns void
language plpgsql security definer set search_path = public, pg_temp
as $$
begin
  -- los tokens que el servicio dio por muertos se borran: un aparato que
  -- desinstaló la app no tiene por qué seguir ocupando lugar ni reintentos
  if p_muertos is not null and array_length(p_muertos, 1) > 0 then
    delete from dispositivos where token = any(p_muertos);
  end if;
  update avisos_push set
    estado = case when p_ok then 'enviado' when intentos >= 4 then 'fallido' else 'pendiente' end,
    enviado_at = case when p_ok then now() end,
    error = case when p_ok then null else left(coalesce(p_error, 'sin detalle'), 300) end,
    proximo_intento = case when p_ok then proximo_intento
                           else now() + (interval '2 minutes' * power(2, least(intentos, 3))) end
   where id = p_id;
end $$;

revoke all on function public.push_tomar(int) from public, anon, authenticated;
revoke all on function public.push_resultado(uuid, boolean, text, text[]) from public, anon, authenticated;

notify pgrst,'reload schema';
