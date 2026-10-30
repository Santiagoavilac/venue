-- 48 · El jefe ajusta los límites de lista (suyo y de su team)
--
-- El jefe fija, por lista del evento, cuántas personas puede anotar él y
-- cuántas cada relacionador de su team. Lo acepta explícitamente en la app
-- (aviso: "administración recibe aviso de cualquier cambio") y cada cambio
-- queda en cambios_cupo, que el admin ve hasta marcarlo como visto.
create table if not exists cambios_cupo (
  id            uuid primary key default gen_random_uuid(),
  club_id       text not null references clubs (id),
  evento_id     uuid not null references eventos (id) on delete cascade,
  lista_tipo_id uuid not null references lista_tipos (id) on delete cascade,
  jefe_id       uuid not null references profiles (id),
  team_id       uuid references teams (id),
  cupo_jefe     int,
  cupo_team     int,
  personas      int not null default 0,
  created_at    timestamptz not null default now(),
  visto_por     uuid references profiles (id),
  visto_at      timestamptz
);
create index if not exists cambios_cupo_pend_idx on cambios_cupo (club_id) where visto_at is null;
alter table cambios_cupo enable row level security;
drop policy if exists cambios_cupo_leer on cambios_cupo;
create policy cambios_cupo_leer on cambios_cupo for select to authenticated
  using (rol_en_club(club_id) = 'admin' or jefe_id = auth.uid());

-- límites actuales del jefe en el evento: el suyo y el de su team, por lista
create or replace function public.jefe_cupos(p_evento uuid)
returns table (lista_tipo_id uuid, lista text, cupo_mio int, cupo_team int, anotados_mios int, team_personas int)
language plpgsql
stable
security definer
set search_path = public
as $$
declare v_club text; v_team uuid;
begin
  select club_id into v_club from eventos where id = p_evento;
  if rol_en_club(v_club) is distinct from 'jefe' then raise exception 'Solo para jefes de team.'; end if;
  v_team := impl.team_en_club(auth.uid(), v_club);
  return query
  with gente as (
    select t.user_id from impl.teams_efectivos(v_club) t
     where t.team_id = v_team and t.rol = 'rrpp' and t.user_id <> auth.uid()
  )
  select lt.id, lt.nombre,
         (select mc.cupo from impl.mis_cupos(p_evento) mc where mc.lista_tipo_id = lt.id),
         coalesce((select mode() within group (order by cr.cupo) from cupo_rrpp cr
                    where cr.lista_tipo_id = lt.id and cr.user_id in (select user_id from gente)),
                  lt.cupo_por_rrpp),
         (select count(*)::int from registros r where r.lista_tipo_id = lt.id and r.rrpp_id = auth.uid()),
         (select count(*)::int from gente)
    from lista_tipos lt
   where lt.evento_id = p_evento
   order by lt.orden;
end;
$$;

-- fija los límites (null = sin límite). Pide aceptación en la app; acá se
-- registra el cambio para administración.
create or replace function public.jefe_fijar_cupos(p_lista uuid, p_mio int, p_team int)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare lt lista_tipos; v_club text; v_team uuid; v_n int := 0;
begin
  select * into lt from lista_tipos where id = p_lista;
  if not found then raise exception 'Lista no encontrada.'; end if;
  select club_id into v_club from eventos where id = lt.evento_id;
  if rol_en_club(v_club) is distinct from 'jefe' then raise exception 'Solo para jefes de team.'; end if;
  if (p_mio is not null and (p_mio < 0 or p_mio > 500)) or (p_team is not null and (p_team < 0 or p_team > 500)) then
    raise exception 'El límite tiene que estar entre 0 y 500.';
  end if;
  v_team := impl.team_en_club(auth.uid(), v_club);
  if v_team is null then raise exception 'No tenés team en este boliche.'; end if;

  -- el suyo
  if p_mio is null then
    delete from cupo_rrpp where lista_tipo_id = p_lista and user_id = auth.uid();
  else
    insert into cupo_rrpp (lista_tipo_id, user_id, cupo) values (p_lista, auth.uid(), p_mio)
    on conflict (lista_tipo_id, user_id) do update set cupo = excluded.cupo;
  end if;

  -- cada relacionador de su team en este boliche
  if p_team is null then
    delete from cupo_rrpp cr using impl.teams_efectivos(v_club) t
     where cr.lista_tipo_id = p_lista and cr.user_id = t.user_id
       and t.team_id = v_team and t.rol = 'rrpp' and t.user_id <> auth.uid();
    get diagnostics v_n = row_count;
  else
    insert into cupo_rrpp (lista_tipo_id, user_id, cupo)
    select p_lista, t.user_id, p_team from impl.teams_efectivos(v_club) t
     where t.team_id = v_team and t.rol = 'rrpp' and t.user_id <> auth.uid()
    on conflict (lista_tipo_id, user_id) do update set cupo = excluded.cupo;
    get diagnostics v_n = row_count;
  end if;

  insert into cambios_cupo (club_id, evento_id, lista_tipo_id, jefe_id, team_id, cupo_jefe, cupo_team, personas)
  values (v_club, lt.evento_id, p_lista, auth.uid(), v_team, p_mio, p_team, v_n);
  return jsonb_build_object('ok', true, 'personas', v_n);
end;
$$;

-- avisos para el admin: cambios sin ver del boliche
create or replace function public.cambios_cupo_pendientes(p_club text)
returns table (id uuid, jefe text, team text, evento text, lista text, cupo_jefe int, cupo_team int, personas int, created_at timestamptz)
language plpgsql
stable
security definer
set search_path = public
as $$
begin
  if rol_en_club(p_club) is distinct from 'admin' then return; end if;
  return query
  select c.id, p.nombre, t.nombre, e.nombre, lt.nombre, c.cupo_jefe, c.cupo_team, c.personas, c.created_at
    from cambios_cupo c
    join profiles p on p.id = c.jefe_id
    left join teams t on t.id = c.team_id
    join eventos e on e.id = c.evento_id
    join lista_tipos lt on lt.id = c.lista_tipo_id
   where c.club_id = p_club and c.visto_at is null
   order by c.created_at desc;
end;
$$;

create or replace function public.marcar_cambios_cupo_vistos(p_club text)
returns int
language plpgsql
security definer
set search_path = public
as $$
declare v_n int;
begin
  if rol_en_club(p_club) is distinct from 'admin' then raise exception 'Solo administradores.'; end if;
  update cambios_cupo set visto_por = auth.uid(), visto_at = now() where club_id = p_club and visto_at is null;
  get diagnostics v_n = row_count;
  return v_n;
end;
$$;

revoke all on function public.jefe_cupos(uuid), public.jefe_fijar_cupos(uuid, int, int),
  public.cambios_cupo_pendientes(text), public.marcar_cambios_cupo_vistos(text) from public, anon;
grant execute on function public.jefe_cupos(uuid), public.jefe_fijar_cupos(uuid, int, int),
  public.cambios_cupo_pendientes(text), public.marcar_cambios_cupo_vistos(text) to authenticated;
