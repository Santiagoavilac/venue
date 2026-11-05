-- Amigos de verdad, y rankings.
--
-- La racha salió comparándose contra "tu gente", que se deducía de con quién
-- compartiste mesa o te pasaste una entrada. Eso sigue -es gratis y no exige
-- que nadie agregue a nadie- pero no alcanza: para competir hay que poder
-- buscar a alguien y agregarlo.
--
-- Se pide y se acepta, no se sigue de una: la racha dice qué noches sale una
-- persona, y eso no se le muestra a cualquiera que la busque por el nombre.
-- Mientras el pedido está pendiente no se ve ninguna racha.

create table if not exists public.aftr_amistades (
  de         uuid not null references auth.users(id) on delete cascade,
  para       uuid not null references auth.users(id) on delete cascade,
  estado     text not null default 'pendiente' check (estado in ('pendiente', 'aceptada')),
  created_at timestamptz not null default now(),
  decidida_at timestamptz,
  primary key (de, para),
  check (de <> para)
);
create index if not exists aftr_amistades_para on public.aftr_amistades (para, estado);
alter table public.aftr_amistades enable row level security;  -- se opera por RPC
comment on table public.aftr_amistades is
  'Pedidos de amistad. Se pide y se acepta: la racha dice que noches sale alguien.';

/* Amigos aceptados, en cualquier dirección. */
create or replace function impl.amigos(p_cliente uuid)
returns setof uuid language sql stable security definer set search_path = public as $$
  select case when a.de = p_cliente then a.para else a.de end
    from aftr_amistades a
   where a.estado = 'aceptada' and p_cliente in (a.de, a.para)
$$;

-- ── la gente con la que uno se compara ────────────────────────────────
-- Amigos aceptados MÁS los que se ganaron solos: con quien compartiste una
-- mesa o te pasaste una entrada. Así la lista no arranca vacía.
create or replace function impl.mi_gente(p_cliente uuid)
returns setof uuid language sql stable security definer set search_path = public as $$
  select otro from (
    select * from impl.amigos(p_cliente) as a(otro)
    union
    select t.para from aftr_transferencias t where t.de = p_cliente
    union
    select t.de from aftr_transferencias t where t.para = p_cliente
    union
    select m2.cliente_id from aftr_mesa_miembros m1
      join aftr_mesa_miembros m2 on m2.mesa_id = m1.mesa_id and m2.cliente_id <> m1.cliente_id
     where m1.cliente_id = p_cliente and m1.estado = 'aceptado' and m2.estado = 'aceptado'
    union
    select m.cliente_id from aftr_mesa_miembros mm join mesas m on m.id = mm.mesa_id
     where mm.cliente_id = p_cliente and mm.estado = 'aceptado' and m.cliente_id is not null
    union
    select mm.cliente_id from mesas m join aftr_mesa_miembros mm on mm.mesa_id = m.id
     where m.cliente_id = p_cliente and mm.estado = 'aceptado'
  ) g
  where otro is not null and otro <> p_cliente
    and not exists (select 1 from aftr_bloqueos b
                     where (b.bloqueador_id = p_cliente and b.bloqueado_id = otro)
                        or (b.bloqueador_id = otro and b.bloqueado_id = p_cliente))
  group by otro
$$;

-- ── buscar, con la foto ───────────────────────────────────────────────
-- Devuelve además foto_key -la clave opaca que firma el servidor- y en qué
-- está la amistad, para que el botón diga Agregar, Pendiente o Amigos.
create or replace function public.aftr_buscar_usuario(p_q text) returns jsonb
language plpgsql security definer set search_path to 'public'
as $function$
declare v_q text := lower(trim(both '@ ' from coalesce(p_q, ''))); v_like text; u uuid;
begin
  perform impl.aftr_yo();
  u := auth.uid();
  if length(v_q) < 3 then return '[]'::jsonb; end if;
  perform impl.aftr_limite('buscar_usuario', 30, interval '1 minute',
    'Demasiadas búsquedas. Esperá un minuto.');
  v_like := replace(replace(replace(v_q, '\', '\\'), '%', '\%'), '_', '\_');
  return coalesce((select jsonb_agg(jsonb_build_object(
      'usuario', c.usuario, 'nombre', c.nombre, 'foto', c.foto_url, 'foto_key', c.foto_key,
      'amistad', case
        when exists (select 1 from impl.amigos(u) as a(o) where a.o = c.user_id) then 'amigos'
        when exists (select 1 from aftr_amistades x
                      where x.estado = 'pendiente' and x.de = u and x.para = c.user_id) then 'pedido'
        when exists (select 1 from aftr_amistades x
                      where x.estado = 'pendiente' and x.de = c.user_id and x.para = u) then 'te_pidio'
        else 'no' end))
    from (select * from aftr_clientes
           where user_id <> u
             and (usuario like v_like || '%' or lower(nombre) like '%' || v_like || '%')
             and not exists (select 1 from aftr_bloqueos b
                              where (b.bloqueador_id = u and b.bloqueado_id = user_id)
                                 or (b.bloqueador_id = user_id and b.bloqueado_id = u))
           order by usuario = v_q desc, usuario limit 12) c), '[]'::jsonb);
end;
$function$;
revoke all on function public.aftr_buscar_usuario(text) from public, anon;
grant execute on function public.aftr_buscar_usuario(text) to authenticated, service_role;

-- ── pedir, aceptar, borrar ────────────────────────────────────────────
create or replace function public.aftr_amistad(p_accion text, p_usuario text)
returns jsonb language plpgsql security definer set search_path = public as $function$
declare c aftr_clientes := impl.aftr_yo(); v_otro uuid; v_estado text;
begin
  if p_accion not in ('pedir', 'aceptar', 'borrar') then raise exception 'Acción no válida.'; end if;
  select user_id into v_otro from aftr_clientes
   where usuario = lower(trim(both '@ ' from coalesce(p_usuario, '')));
  if v_otro is null then raise exception 'No encontramos esa cuenta.'; end if;
  if v_otro = c.user_id then raise exception 'No podés agregarte a vos mismo.'; end if;
  if exists (select 1 from aftr_bloqueos b
              where (b.bloqueador_id = c.user_id and b.bloqueado_id = v_otro)
                 or (b.bloqueador_id = v_otro and b.bloqueado_id = c.user_id)) then
    raise exception 'No se puede.' using errcode = '42501';
  end if;

  if p_accion = 'pedir' then
    perform impl.aftr_limite('pedir_amistad', 40, interval '1 hour',
      'Mandaste muchos pedidos. Esperá un rato.');
    -- si el otro ya te pidió, pedir es aceptar: nadie queda esperando de gusto
    update aftr_amistades set estado = 'aceptada', decidida_at = now()
     where de = v_otro and para = c.user_id and estado = 'pendiente';
    if not found then
      insert into aftr_amistades (de, para) values (c.user_id, v_otro)
        on conflict (de, para) do nothing;
    end if;
  elsif p_accion = 'aceptar' then
    update aftr_amistades set estado = 'aceptada', decidida_at = now()
     where de = v_otro and para = c.user_id and estado = 'pendiente';
    if not found then raise exception 'Ese pedido ya no está.'; end if;
  else
    delete from aftr_amistades
     where (de = c.user_id and para = v_otro) or (de = v_otro and para = c.user_id);
  end if;

  select case
    when exists (select 1 from impl.amigos(c.user_id) as a(o) where a.o = v_otro) then 'amigos'
    when exists (select 1 from aftr_amistades x where x.estado='pendiente' and x.de=c.user_id and x.para=v_otro) then 'pedido'
    when exists (select 1 from aftr_amistades x where x.estado='pendiente' and x.de=v_otro and x.para=c.user_id) then 'te_pidio'
    else 'no' end into v_estado;
  return jsonb_build_object('ok', true, 'amistad', v_estado);
end $function$;
revoke all on function public.aftr_amistad(text, text) from public, anon;
grant execute on function public.aftr_amistad(text, text) to authenticated, service_role;

-- ── lo que pide la pantalla de rachas ─────────────────────────────────
-- La propia, los pedidos por responder, el ranking de su gente, el de la
-- ciudad y dos números de la temporada. Todo en una llamada: la pantalla no
-- tiene que pedir cinco cosas para dibujarse.
create or replace function public.aftr_rachas()
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare c aftr_clientes := impl.aftr_yo(); v_desde date := (now() at time zone 'America/La_Paz')::date - 30;
begin
  return jsonb_build_object(
    'mia', impl.racha(c.user_id) || jsonb_build_object(
      'usuario', c.usuario, 'nombre', c.nombre, 'foto', c.foto_url, 'foto_key', c.foto_key),
    'pedidos', coalesce((select jsonb_agg(jsonb_build_object(
        'usuario', cl.usuario, 'nombre', cl.nombre, 'foto', cl.foto_url, 'foto_key', cl.foto_key)
        order by a.created_at desc)
      from aftr_amistades a join aftr_clientes cl on cl.user_id = a.de
     where a.para = c.user_id and a.estado = 'pendiente'), '[]'::jsonb),
    'gente', coalesce((select jsonb_agg(x order by (x->>'semanas')::int desc, x->>'nombre')
      from (
        select impl.racha(g.otro) || jsonb_build_object(
                 'usuario', cl.usuario, 'nombre', cl.nombre,
                 'foto', cl.foto_url, 'foto_key', cl.foto_key,
                 'amigo', exists (select 1 from impl.amigos(c.user_id) as a(o) where a.o = g.otro)) as x
          from impl.mi_gente(c.user_id) as g(otro)
          join aftr_clientes cl on cl.user_id = g.otro
         limit 40
      ) y), '[]'::jsonb),
    -- El ranking de la ciudad: sólo el nombre de usuario y la foto, que ya son
    -- públicos en el buscador, y sólo de dos semanas para arriba, para que
    -- nadie figure por haber salido una vez.
    'ciudad', coalesce((select jsonb_agg(x order by (x->>'semanas')::int desc, x->>'usuario')
      from (
        select impl.racha(t.cliente_id) || jsonb_build_object(
                 'usuario', cl.usuario, 'foto', cl.foto_url, 'foto_key', cl.foto_key,
                 'yo', t.cliente_id = c.user_id) as x
          from (
            -- candidatos: los que entraron en las últimas cinco semanas
            select x.cliente_id, count(distinct impl.semana_de(x.used_at)) as semanas
              from entradas x
             where x.used_at > now() - interval '6 weeks' and x.cliente_id is not null
             group by x.cliente_id
            having count(distinct impl.semana_de(x.used_at)) >= 2
             order by semanas desc limit 60
          ) t
          join aftr_clientes cl on cl.user_id = t.cliente_id
         where not exists (select 1 from aftr_bloqueos b
                            where (b.bloqueador_id = c.user_id and b.bloqueado_id = t.cliente_id)
                               or (b.bloqueador_id = t.cliente_id and b.bloqueado_id = c.user_id))
         limit 20
      ) y where (x->>'semanas')::int >= 2), '[]'::jsonb),
    'temporada', jsonb_build_object(
      'noches', (select count(distinct (x.used_at at time zone 'America/La_Paz')::date)
                   from entradas x
                  where x.cliente_id = c.user_id and x.used_at is not null
                    and (x.used_at at time zone 'America/La_Paz')::date >= v_desde),
      'lugar', (select cb.nombre from entradas x
                  join eventos e on e.id = x.evento_id join clubs cb on cb.id = e.club_id
                 where x.cliente_id = c.user_id and x.used_at is not null
                 group by cb.nombre order by count(*) desc limit 1)),
    'ahora', now());
end $$;
revoke all on function public.aftr_rachas() from public, anon;
grant execute on function public.aftr_rachas() to authenticated, service_role;

notify pgrst,'reload schema';
