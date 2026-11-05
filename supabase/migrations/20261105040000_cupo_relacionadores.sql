-- Tope de relacionadores por boliche.
--
-- El admin del boliche necesita saber cuántos relacionadores puede tener y
-- cuántos le quedan, sobre todo ahora que el alta es por enlace y ya no la
-- controla uno por uno. El tope lo fija la plataforma; el boliche lo consulta.
--
-- max_relacionadores nulo = sin tope, que es como quedan todos los boliches
-- existentes: esto no le quita cupo a nadie.
alter table public.clubs
  add column if not exists max_relacionadores integer
    check (max_relacionadores is null or max_relacionadores > 0);

comment on column public.clubs.max_relacionadores is
  'Cuántos relacionadores activos admite el boliche. Nulo = sin tope.';

-- Cuántos ocupan cupo hoy: relacionadores y jefes activos del boliche.
create or replace function impl.relacionadores_activos(p_club text)
 returns integer language sql stable security definer set search_path to 'public'
as $function$
  select count(*)::int
    from club_membership m
    join profiles p on p.id = m.user_id
   where m.club_id = p_club and m.activo and m.revocado_at is null
     and m.rol in ('rrpp', 'jefe')
     and p.activo and p.eliminado_at is null;
$function$;

-- Lo que ve el admin.
create or replace function public.cupo_relacionadores(p_club text)
 returns json language plpgsql stable security definer set search_path to 'public'
as $function$
declare v_max integer; v_usados integer;
begin
  perform impl.exigir(p_club, '{admin,jefe}'::text[]);
  select max_relacionadores into v_max from clubs where id = p_club;
  v_usados := impl.relacionadores_activos(p_club);
  return json_build_object(
    'usados', v_usados,
    'maximo', v_max,
    'disponibles', case when v_max is null then null else greatest(v_max - v_usados, 0) end,
    'lleno', v_max is not null and v_usados >= v_max);
end;
$function$;

-- Sólo la plataforma mueve el tope.
create or replace function public.fijar_cupo_relacionadores(p_club text, p_max integer)
 returns json language plpgsql security definer set search_path to 'public'
as $function$
begin
  if not es_platform_admin() then
    raise exception 'No autorizado.' using errcode = '42501';
  end if;
  if p_max is not null and p_max < 1 then
    raise exception 'El tope tiene que ser al menos 1, o vacío para sin tope.';
  end if;
  update clubs set max_relacionadores = p_max where id = p_club;
  return json_build_object('club', p_club, 'maximo', p_max,
                           'usados', impl.relacionadores_activos(p_club));
end;
$function$;

grant execute on function public.cupo_relacionadores(text) to authenticated;
revoke all on function public.fijar_cupo_relacionadores(text, integer) from public, anon;
grant execute on function public.fijar_cupo_relacionadores(text, integer) to authenticated;
