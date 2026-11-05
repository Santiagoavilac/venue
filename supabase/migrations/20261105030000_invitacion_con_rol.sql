-- Enlaces de invitación que ya traen el rol.
--
-- Hasta ahora sumar gente era: el admin creaba el usuario a mano con
-- contraseña, o la persona pedía unirse por un enlace y alguien tenía que
-- aprobar la solicitud. Con esto el admin genera un enlace que dice "sos
-- relacionador de Burtown" o "sos jefe", y quien lo abre entra directo.
--
-- Usuario y contraseña siguen funcionando para entrar; lo que cambia es el
-- alta, que deja de ser manual.
create table if not exists public.invitacion_rol (
  code        text primary key,
  club_id     text not null references public.clubs(id) on delete cascade,
  rol         text not null check (rol in ('rrpp', 'jefe')),
  team_id     uuid references public.teams(id),
  creada_por  uuid not null,
  created_at  timestamptz not null default now(),
  expira      timestamptz,
  usos_max    integer check (usos_max is null or usos_max > 0),
  usos        integer not null default 0,
  activo      boolean not null default true
);

create index if not exists invitacion_rol_club_idx
  on public.invitacion_rol (club_id, created_at desc);

alter table public.invitacion_rol enable row level security;
revoke all on public.invitacion_rol from anon, authenticated;

comment on table public.invitacion_rol is
  'Enlaces de alta que ya traen club y rol: quien los abre entra sin aprobación.';

-- ── crear el enlace ────────────────────────────────────────────────────────
-- Un admin invita relacionadores o jefes. Un jefe sólo puede invitar
-- relacionadores, y siempre a su propio team.
create or replace function public.crear_invitacion_rol(
  p_club text, p_rol text, p_team uuid default null,
  p_horas integer default 168, p_usos_max integer default null)
 returns json language plpgsql security definer set search_path to 'public'
as $function$
declare v_rol_mio text; v_code text; v_team uuid := p_team;
begin
  if auth.uid() is null then raise exception 'Iniciá sesión.' using errcode = '28000'; end if;
  if p_rol not in ('rrpp', 'jefe') then
    raise exception 'Rol no válido para un enlace.';
  end if;
  v_rol_mio := impl.exigir(p_club, '{admin,jefe}'::text[]);
  if v_rol_mio = 'jefe' then
    if p_rol <> 'rrpp' then
      raise exception 'Un jefe sólo puede invitar relacionadores.' using errcode = '42501';
    end if;
    v_team := impl.team_en_club(auth.uid(), p_club);
    if v_team is null then raise exception 'No tenés team en este boliche.'; end if;
  end if;
  if v_team is not null and not exists (
      select 1 from teams t where t.id = v_team and t.activo
        and (coalesce(array_length(t.clubs, 1), 0) = 0 or p_club = any(t.clubs))) then
    raise exception 'Ese team no trabaja en este boliche.';
  end if;

  loop
    v_code := lower(substr(replace(gen_random_uuid()::text, '-', ''), 1, 10));
    exit when not exists (select 1 from invitacion_rol where code = v_code);
  end loop;

  insert into invitacion_rol (code, club_id, rol, team_id, creada_por, expira, usos_max)
  values (v_code, p_club, p_rol, v_team, auth.uid(),
          case when p_horas is null then null else now() + make_interval(hours => p_horas) end,
          p_usos_max);

  return json_build_object('code', v_code, 'rol', p_rol, 'club', p_club,
                           'team_id', v_team,
                           'expira', case when p_horas is null then null
                                          else now() + make_interval(hours => p_horas) end);
end;
$function$;

-- ── mirar el enlace antes de entrar ────────────────────────────────────────
-- Se puede llamar sin sesión: es lo que deja mostrar "Te invitan a Burtown
-- como relacionador" antes de pedirle a la persona que cree su cuenta.
create or replace function public.ver_invitacion_rol(p_code text)
 returns json language plpgsql stable security definer set search_path to 'public'
as $function$
declare i invitacion_rol; c clubs; t teams;
begin
  select * into i from invitacion_rol where code = lower(trim(p_code));
  if not found or not i.activo
     or (i.expira is not null and i.expira <= now())
     or (i.usos_max is not null and i.usos >= i.usos_max) then
    return json_build_object('valido', false);
  end if;
  select * into c from clubs where id = i.club_id and activo;
  if not found then return json_build_object('valido', false); end if;
  select * into t from teams where id = i.team_id;
  return json_build_object('valido', true, 'rol', i.rol,
    'club', json_build_object('id', c.id, 'nombre', c.nombre, 'logo_url', c.logo_url,
                              'ciudad', c.ciudad, 'color', c.color_primario),
    'team', case when t.id is null then null
                 else json_build_object('id', t.id, 'nombre', t.nombre) end);
end;
$function$;

-- ── entrar con el enlace ───────────────────────────────────────────────────
create or replace function public.aceptar_invitacion_rol(p_code text)
 returns json language plpgsql security definer set search_path to 'public'
as $function$
declare v_uid uuid := auth.uid(); i invitacion_rol; c clubs; v_team uuid; v_nombre text;
begin
  if v_uid is null then raise exception 'Iniciá sesión.' using errcode = '28000'; end if;
  select nombre into v_nombre from profiles where id = v_uid and activo and eliminado_at is null;
  if v_nombre is null then raise exception 'Completá tu cuenta primero.'; end if;

  select * into i from invitacion_rol where code = lower(trim(p_code)) for update;
  if not found or not i.activo then raise exception 'El enlace no es válido o fue desactivado.'; end if;
  if i.expira is not null and i.expira <= now() then raise exception 'Ese enlace venció.'; end if;
  if i.usos_max is not null and i.usos >= i.usos_max then raise exception 'Ese enlace ya se usó.'; end if;

  select * into c from clubs where id = i.club_id and activo;
  if not found then raise exception 'Ese boliche no está disponible.'; end if;
  if rol_en_club(c.id) is not null then raise exception 'Ya trabajás con %.', c.nombre; end if;

  -- el tope del boliche vale para las dos puertas de alta
  if exists (select 1 from clubs x where x.id = c.id and x.max_relacionadores is not null
               and impl.relacionadores_activos(c.id) >= x.max_relacionadores) then
    raise exception 'Este boliche llegó a su tope de relacionadores. Pedile al boliche que libere un lugar.';
  end if;

  v_team := i.team_id;
  -- un jefe sin team armado estrena el suyo, con su nombre
  if i.rol = 'jefe' and v_team is null then
    insert into teams (nombre, jefe_id, activo, clubs)
    values (v_nombre, v_uid, true, array[c.id]) returning id into v_team;
  end if;

  perform set_config('venue.perfil_aprobado', '1', true);
  insert into club_membership (user_id, club_id, rol, team_id, activo, origen, aprobado_por, aprobado_at, revocado_at)
  values (v_uid, c.id, i.rol, v_team, true, 'enlace_rol', i.creada_por, now(), null)
  on conflict (user_id, club_id) do update
     set rol = excluded.rol, team_id = excluded.team_id, activo = true,
         origen = excluded.origen, aprobado_por = excluded.aprobado_por,
         aprobado_at = excluded.aprobado_at, revocado_at = null;

  update profiles set team_id = coalesce(v_team, team_id) where id = v_uid;
  update invitacion_rol set usos = usos + 1 where code = i.code;

  return json_build_object('club', c.id, 'nombre', c.nombre, 'rol', i.rol, 'team_id', v_team);
end;
$function$;

revoke all on function public.crear_invitacion_rol(text, text, uuid, integer, integer) from public, anon;
grant execute on function public.crear_invitacion_rol(text, text, uuid, integer, integer) to authenticated;
grant execute on function public.ver_invitacion_rol(text) to anon, authenticated;
revoke all on function public.aceptar_invitacion_rol(text) from public, anon;
grant execute on function public.aceptar_invitacion_rol(text) to authenticated;
