-- El QR de un invitado se puede inhabilitar, y la puerta lo respeta.
--
-- `registros.qr_anulado` existe desde db/13, replicada del origen con una nota
-- honesta: "el origen todavía no la usa, así que acá no se cambia ninguna RPC;
-- agregar el corte sería inventar una regla que decide quién entra". Pasó el
-- tiempo y el agujero quedó: **nadie escribe esa columna y la validación no la
-- mira**, así que hoy no hay ninguna forma de frenar a alguien que entra con el
-- QR de otro. Lo único que se puede hacer es no escanearlo, y en la puerta, con
-- cola, eso no pasa.
--
-- Decidido con Santiago: lo pueden inhabilitar el admin, el jefe y el portero
-- -los tres que están en la puerta o la manejan- y queda escrito quién y
-- cuándo. Se puede volver a habilitar, porque el error más probable es
-- inhabilitar al que no era.

alter table public.registros
  add column if not exists qr_anulado_por uuid references public.profiles(id),
  add column if not exists qr_anulado_at timestamptz,
  add column if not exists qr_anulado_motivo text;

comment on column public.registros.qr_anulado is
  'El QR no deja entrar. Lo pone un admin, un jefe o un portero desde el escaner.';

-- ── quién puede ───────────────────────────────────────────────────────
create or replace function public.anular_qr_lista(p_registro uuid, p_anular boolean default true,
                                                  p_motivo text default null)
returns jsonb language plpgsql security definer set search_path = public as $$
declare r registros; v_club text; v_rol text; v_motivo text := nullif(trim(coalesce(p_motivo, '')), '');
begin
  select * into r from registros where id = p_registro for update;
  if not found then raise exception 'Ese invitado no existe.'; end if;
  select club_id into v_club from eventos where id = r.evento_id;
  v_rol := rol_en_club(v_club);
  if not es_platform_admin() and coalesce(v_rol, '') not in ('admin', 'propietario', 'jefe', 'portero') then
    raise exception 'No autorizado.' using errcode = '42501';
  end if;
  -- el jefe, sólo con los que anotó su team: si no, un jefe podría borrarle
  -- la noche al team de al lado
  if v_rol = 'jefe' and not exists (
       select 1 from impl.teams_efectivos(v_club) t
        where t.user_id = r.rrpp_id and t.team_id = impl.team_en_club(auth.uid(), v_club)) then
    raise exception 'Ese invitado no es de tu team.' using errcode = '42501';
  end if;
  if p_anular and r.ingreso_at is not null then
    raise exception 'Esa persona ya entró. Inhabilitar el QR no la saca del lugar.';
  end if;
  update registros set
    qr_anulado = coalesce(p_anular, true),
    qr_anulado_por = case when coalesce(p_anular, true) then auth.uid() end,
    qr_anulado_at = case when coalesce(p_anular, true) then now() end,
    qr_anulado_motivo = case when coalesce(p_anular, true) then v_motivo end
   where id = r.id returning * into r;
  return jsonb_build_object('id', r.id, 'nombre', r.nombre, 'code', r.code,
    'qr_anulado', r.qr_anulado, 'motivo', r.qr_anulado_motivo, 'at', r.qr_anulado_at);
end $$;

revoke all on function public.anular_qr_lista(uuid, boolean, text) from public, anon;
grant execute on function public.anular_qr_lista(uuid, boolean, text) to authenticated, service_role;

-- ── la puerta lo respeta ──────────────────────────────────────────────
-- El corte va antes de consumir el ingreso, igual que el de entradas.estado =
-- 'anulada': si no, el QR inhabilitado se "usaría" y la persona quedaría
-- marcada como que entró.
create or replace function impl.validar_qr_lista(p_evento uuid, p_code text)
returns json language plpgsql security definer set search_path to 'public'
as $function$
declare
  r registros%rowtype;
  v_club text; v_lista text; v_rrpp text; v_team text;
  v_sin_tope boolean; v_limite timestamptz; v_hasta time;
begin
  select r2.* into r
    from registros r2
    join lista_tipos lt on lt.id = r2.lista_tipo_id
   where r2.evento_id = p_evento and r2.code = upper(p_code);
  if not found then
    return json_build_object('resultado', 'no_existe');
  end if;

  select e.club_id into v_club from eventos e where e.id = p_evento;
  select lt.nombre into v_lista from lista_tipos lt where lt.id = r.lista_tipo_id;
  v_hasta := lista_hora_ingreso(r.lista_tipo_id, r.rrpp_id);
  select p.nombre, t.nombre into v_rrpp, v_team
    from profiles p left join teams t on t.id = p.team_id
   where p.id = r.rrpp_id;
  v_sin_tope := exists (select 1 from ingreso_sin_tope st
                         where st.user_id = r.rrpp_id and st.club_id = v_club);

  if r.qr_anulado then
    return json_build_object('resultado', 'anulada', 'cliente', r.nombre, 'code', r.code,
                             'lista', true, 'lista_nombre', v_lista,
                             'motivo', r.qr_anulado_motivo,
                             'rrpp', v_rrpp, 'team', v_team);
  end if;

  if r.ingreso_at is not null then
    return json_build_object('resultado', 'usada', 'cliente', r.nombre, 'code', r.code,
                             'used_at', r.ingreso_at, 'lista_nombre', v_lista,
                             'rrpp', v_rrpp, 'team', v_team);
  end if;

  v_limite := lista_limite_ingreso(r.lista_tipo_id, r.rrpp_id);
  if v_limite is not null and now() > v_limite and not v_sin_tope then
    return json_build_object('resultado', 'fuera_horario', 'cliente', r.nombre, 'code', r.code,
                             'lista_nombre', v_lista, 'limite', to_char(v_hasta, 'HH24:MI'),
                             'rrpp', v_rrpp, 'team', v_team);
  end if;

  update registros set ingreso_at = now(), ingreso_por = auth.uid()
   where id = r.id and ingreso_at is null and not qr_anulado;
  if not found then
    select reg.* into r from registros reg where reg.id = r.id;
    return json_build_object('resultado', case when r.qr_anulado then 'anulada' else 'usada' end,
                             'cliente', r.nombre, 'code', r.code,
                             'used_at', r.ingreso_at, 'lista', true, 'lista_nombre', v_lista,
                             'motivo', r.qr_anulado_motivo,
                             'rrpp', v_rrpp, 'team', v_team);
  end if;
  return json_build_object('resultado', 'valida', 'cliente', r.nombre, 'code', r.code,
                           'lista', true, 'lista_nombre', v_lista,
                           'rrpp', v_rrpp, 'team', v_team, 'sin_tope', v_sin_tope);
end;
$function$;

-- ── y el buscador de la puerta lo muestra ─────────────────────────────
-- `buscar_registros` es lo que usa el guardia para encontrar a alguien por
-- nombre. Si no dice que el QR está inhabilitado, lo marca como ingresado a
-- mano y el corte no sirvió para nada.
create or replace function impl.buscar_registros(p_evento uuid, p_q text)
returns setof jsonb language sql stable security definer set search_path to 'public'
as $function$
  with q as (
    select unaccent(lower(p_q)) as needle
  ),
  de_lista as (
    select jsonb_build_object(
             'id', r.id,
             'rrpp', p.nombre,
             'tipo', 'lista',
             'lista', lt.nombre,
             'nombre', r.nombre,
             'sin_tope', false,
             'filtro_at', r.filtro_at,
             'ingreso_at', r.ingreso_at,
             'qr_anulado', r.qr_anulado,
             'qr_anulado_motivo', r.qr_anulado_motivo
           ) as fila,
           false as es_entrada,
           r.lista_tipo_id as grupo,
           null::uuid as grupo2,
           r.created_at as orden_at
    from registros r
    join lista_tipos lt on lt.id = r.lista_tipo_id
    join profiles p on p.id = r.rrpp_id
    cross join q
    where r.evento_id = p_evento
      and unaccent(lower(r.nombre)) ilike '%' || q.needle || '%'
  ),
  de_entrada as (
    select jsonb_build_object(
             'id', e.id,
             'code', e.code,
             'rrpp', p.nombre,
             'tipo', 'entrada',
             'lista', case when e.mesa_id is not null then 'Mesa ' || ms.etiqueta
                           else 'Prepagada' end,
             'estado', e.estado,
             'nombre', e.cliente,
             'sin_tope', exists (
               select 1 from ingreso_sin_tope st
                where st.user_id = e.rrpp_id and st.club_id = ev.club_id
             ),
             'filtro_at', e.filtro_at,
             'ingreso_at', e.used_at
           ) as fila,
           true as es_entrada,
           null::uuid as grupo,
           e.mesa_id as grupo2,
           e.created_at as orden_at
    from impl.entradas_vigentes e
    join eventos ev on ev.id = e.evento_id
    join profiles p on p.id = e.rrpp_id
    left join mesas ms on ms.id = e.mesa_id
    cross join q
    where e.evento_id = p_evento
      and unaccent(lower(e.cliente)) ilike '%' || q.needle || '%'
  )
  select fila
    from (
      select * from de_lista
      union all
      select * from de_entrada
    ) u
   order by es_entrada,          -- lista primero, entrada despues (contrato)
            grupo desc,          -- lista: agrupado por lista_tipo (observado desc)
            (grupo2 is null),    -- entrada: las de mesa primero
            orden_at asc;        -- created_at asc dentro de cada grupo
$function$;

notify pgrst,'reload schema';

-- ── y el ingreso a mano también ───────────────────────────────────────
-- Sin esto, el QR inhabilitado se frena al escanear pero el guardia lo marca
-- como ingresado desde el buscador y la persona entra igual.
create or replace function impl.checkin_registro(p_registro uuid)
returns json language plpgsql security definer set search_path to 'public'
as $function$
declare
  r registros%rowtype;
  v_club text; v_sin_tope boolean; v_limite timestamptz;
begin
  select * into r from registros where id = p_registro;
  if not found then
    return json_build_object('resultado', 'no_existe');
  end if;
  if r.qr_anulado then
    return json_build_object('resultado', 'anulada', 'nombre', r.nombre,
                             'motivo', r.qr_anulado_motivo);
  end if;
  if r.ingreso_at is not null then
    return json_build_object('resultado', 'ya', 'nombre', r.nombre, 'hora', r.ingreso_at);
  end if;

  select e.club_id into v_club from eventos e where e.id = r.evento_id;
  v_sin_tope := exists (select 1 from ingreso_sin_tope st
                         where st.user_id = r.rrpp_id and st.club_id = v_club);
  v_limite := lista_limite_ingreso(r.lista_tipo_id, r.rrpp_id);
  if v_limite is not null and now() > v_limite and not v_sin_tope then
    return json_build_object('resultado', 'fuera_horario', 'nombre', r.nombre);
  end if;

  update registros set ingreso_at = now(), ingreso_por = auth.uid()
   where id = p_registro and ingreso_at is null and not qr_anulado;
  if not found then
    select reg.* into r from registros reg where reg.id = p_registro;
    return json_build_object('resultado', case when r.qr_anulado then 'anulada' else 'ya' end,
                             'nombre', r.nombre, 'hora', r.ingreso_at,
                             'motivo', r.qr_anulado_motivo);
  end if;
  return json_build_object('resultado', 'ok', 'nombre', r.nombre, 'hora', now());
end;
$function$;
notify pgrst,'reload schema';
