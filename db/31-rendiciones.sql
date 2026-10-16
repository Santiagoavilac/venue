-- Rendiciones por relacionador: quién pagó lo que le toca rendir del evento.
--
-- El relacionador sube su comprobante (pagos, como siempre). El jefe ve a
-- los de su team que vendieron, con sus capturas y lo que deben, y les pone
-- un check de "pagó": se le confía. El admin ve todos los teams y puede
-- marcar o desmarcar a cualquiera, de a uno o el team entero.
--
-- La cuenta es sobre las manillas prepagadas que INGRESARON (entrada usada):
--   cobrado   = suma del precio de cada entrada usada (cada fase con su precio)
--   comisión  = comisión por manilla × usadas (cut_rel de la persona, si no
--               cut_rrpp del evento, si no la cuenta vieja por porcentajes:
--               misma regla que comisionPorManilla en la app y cutRrpp en la web)
--   a pagar   = cobrado − comisión (nunca negativo)
--
-- No toca la tabla pagos ni sus estados (pendiente → pagado → verificado),
-- que siguen siendo la verificación contra el extracto que usa la caja.
-- Solo agrega cosas: re-ejecutable.

create table if not exists rendicion_rrpp (
  evento_id   uuid not null references eventos(id) on delete cascade,
  rrpp_id     uuid not null references profiles(id) on delete cascade,
  pagado      boolean not null default false,
  marcado_por uuid references profiles(id) on delete set null,
  marcado_at  timestamptz,
  primary key (evento_id, rrpp_id)
);
alter table rendicion_rrpp enable row level security;   -- sin políticas: solo por las funciones

/* rendiciones_evento(p_evento) -> una fila por persona que vendió prepagadas.
   admin: todas · jefe: las de su team (y la propia) · rrpp: la propia. */
create or replace function rendiciones_evento(p_evento uuid)
returns table (
  rrpp_id uuid, nombre text, team_id uuid, team text,
  vendidas int, ingresaron int, cobrado numeric, comision_unit numeric,
  comision numeric, a_pagar numeric, pagado boolean, marcado_por text,
  marcado_at timestamptz, comprobantes text[], rendido numeric)
language plpgsql stable security definer set search_path = public
as $$
#variable_conflict use_column
declare
  v_club text := impl.club_de('evento', p_evento);
  v_rol  text;
  v_team uuid;
  e      record;
begin
  v_rol := impl.exigir(v_club, '{admin,jefe,rrpp}'::text[]);
  select ev.precio_manilla, ev.pct_boliche, ev.pct_rrpp, ev.cut_rrpp into e
    from eventos ev where ev.id = p_evento;
  select t.team_id into v_team from impl.teams_efectivos(v_club) t where t.user_id = auth.uid();

  return query
  with tm as (select * from impl.teams_efectivos(v_club)),
  ent as (
    select x.rrpp_id,
           count(*)::int                                         as vendidas,
           (count(*) filter (where x.estado = 'usada'))::int     as ingresaron,
           coalesce(sum(x.precio) filter (where x.estado = 'usada'), 0)::numeric as cobrado
      from entradas x
     where x.evento_id = p_evento and x.mesa_id is null and x.estado <> 'anulada'
       and x.rrpp_id is not null
     group by x.rrpp_id),
  pg as (
    select g.rrpp_id,
           array_agg(g.comprobante_url order by g.created_at desc)
             filter (where g.comprobante_url is not null)        as comps,
           sum(g.monto)::numeric                                  as rendido
      from pagos g where g.evento_id = p_evento group by g.rrpp_id)
  select ent.rrpp_id, coalesce(tm.nombre, pr.nombre), tm.team_id, coalesce(tm.team, 'Sin team'),
         ent.vendidas, ent.ingresaron, ent.cobrado,
         cu.c, cu.c * ent.ingresaron, greatest(ent.cobrado - cu.c * ent.ingresaron, 0),
         coalesce(r.pagado, false), mp.nombre, r.marcado_at,
         coalesce(pg.comps, '{}'::text[]), coalesce(pg.rendido, 0)
    from ent
    join profiles pr on pr.id = ent.rrpp_id
    left join tm on tm.user_id = ent.rrpp_id
    left join rendicion_rrpp r on r.evento_id = p_evento and r.rrpp_id = ent.rrpp_id
    left join profiles mp on mp.id = r.marcado_por
    left join pg on pg.rrpp_id = ent.rrpp_id
    cross join lateral (
      select round(coalesce(pr.cut_rel, e.cut_rrpp,
               coalesce(e.precio_manilla, 0) * (1 - coalesce(e.pct_boliche, 0) / 100.0)
                                             * (coalesce(e.pct_rrpp, 0) / 100.0))::numeric, 2) as c
    ) cu
   where v_rol in ('admin', 'servicio')
      or ent.rrpp_id = auth.uid()
      or (v_rol = 'jefe' and v_team is not null and tm.team_id = v_team)
   order by coalesce(tm.team, 'Sin team'), coalesce(tm.nombre, pr.nombre);
end;
$$;

/* marcar_rendicion(p_evento, p_rrpps, p_pagado) -> cantidad marcada
   Check (o lo saca) a uno o varios de una vez (el team entero).
   Jefe: solo a los de su team y no a sí mismo · admin: a cualquiera. */
create or replace function marcar_rendicion(p_evento uuid, p_rrpps uuid[], p_pagado boolean)
returns int
language plpgsql volatile security definer set search_path = public
as $$
declare
  v_club text := impl.club_de('evento', p_evento);
  v_rol  text;
  v_team uuid;
  v_n    int;
begin
  v_rol := impl.exigir(v_club, '{admin,jefe}'::text[]);
  if p_rrpps is null or cardinality(p_rrpps) = 0 then return 0; end if;
  if v_rol = 'jefe' then
    select t.team_id into v_team from impl.teams_efectivos(v_club) t where t.user_id = auth.uid();
    if v_team is null
       or auth.uid() = any(p_rrpps)
       or exists (select 1 from unnest(p_rrpps) u(id)
                   where not exists (select 1 from impl.teams_efectivos(v_club) t
                                      where t.user_id = u.id and t.team_id = v_team)) then
      raise exception 'Solo podés marcar a los relacionadores de tu team.' using errcode = '42501';
    end if;
  end if;
  insert into rendicion_rrpp as r (evento_id, rrpp_id, pagado, marcado_por, marcado_at)
  select p_evento, u.id, coalesce(p_pagado, false), auth.uid(), now()
    from unnest(p_rrpps) u(id)
  on conflict (evento_id, rrpp_id) do update
     set pagado = excluded.pagado, marcado_por = excluded.marcado_por, marcado_at = excluded.marcado_at;
  get diagnostics v_n = row_count;
  return v_n;
end;
$$;

comment on function rendiciones_evento(uuid) is 'venue:guarda';
comment on function marcar_rendicion(uuid, uuid[], boolean) is 'venue:guarda';
revoke execute on function rendiciones_evento(uuid) from public, anon;
revoke execute on function marcar_rendicion(uuid, uuid[], boolean) from public, anon;
grant  execute on function rendiciones_evento(uuid) to authenticated;
grant  execute on function marcar_rendicion(uuid, uuid[], boolean) to authenticated;
