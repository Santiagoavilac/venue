-- La comisión de jefe se decide boliche por boliche.
--
-- `rrpp_eventos` miraba `profiles.rol` global: quien es jefe en un boliche y
-- relacionador en otro cobraba comisión de jefe en los dos, sumando lo que
-- vendió todo un team ajeno. Plata de un boliche apareciendo en la rendición
-- de otro.
--
-- `rol_en_club` ya resuelve esto en todo el resto del sistema (db/18): mira
-- la membresía del boliche, y recién si no hay membresía cae al rol base.
-- Acá se usa el club del evento de cada fila, que es lo que corresponde.
--
-- Lo demás de la función queda igual que en db/41.
create or replace function public.rrpp_eventos(p_desde date default null, p_hasta date default null,
                                              p_club text default null)
returns table (
  evento_id uuid, club_id text, club text, logo_url text, evento text, fecha date, estado text,
  anotados bigint, ingresaron bigint, entradas_vendidas bigint, entradas_usadas bigint,
  mesas_confirmadas bigint, mesas_reservadas bigint, bruto_entradas numeric, bruto_mesas numeric,
  comision_entradas numeric, comision_mesas numeric, comision_jefe numeric, bono numeric,
  comision_total numeric, por_manilla numeric, estado_comision text, pagado_at timestamptz)
language plpgsql
stable
security definer
set search_path = public
as $$
#variable_conflict use_column
declare v_uid uuid := auth.uid();
begin
  if v_uid is null then raise exception 'Iniciá sesión.' using errcode = '28000'; end if;
  return query
  with evs as (
    select e.* from eventos e
     where (p_club is null or e.club_id = p_club)
       and (p_desde is null or e.fecha >= p_desde)
       and (p_hasta is null or e.fecha <= p_hasta)
       and (exists (select 1 from registros r where r.evento_id = e.id and r.rrpp_id = v_uid)
         or exists (select 1 from entradas x where x.evento_id = e.id and x.rrpp_id = v_uid)
         or exists (select 1 from mesas m where m.evento_id = e.id and m.vendido_por = v_uid)
         or exists (select 1 from bonos b where b.evento_id = e.id and b.user_id = v_uid))
  ),
  base as (
    select e.id, e.club_id, e.nombre, e.fecha, e.estado,
           s.anotados, s.ingresaron, s.entradas_vendidas, s.entradas_usadas,
           s.bruto_entradas::numeric as bruto_entradas, s.comision_rrpp::numeric as comision_rrpp,
           coalesce(m.comision_rrpp_mesas, 0)::numeric as comision_rrpp_mesas,
           s.team_id,
           (select count(*) from mesas mm where mm.evento_id = e.id and mm.vendido_por = v_uid
              and mm.estado not in ('disponible', 'reservada')) as mesas_conf,
           (select count(*) from mesas mm where mm.evento_id = e.id and mm.vendido_por = v_uid
              and mm.estado = 'reservada') as mesas_res,
           (select coalesce(sum(mm.precio), 0) from mesas mm where mm.evento_id = e.id
              and mm.vendido_por = v_uid and mm.estado not in ('disponible', 'reservada'))::numeric as bruto_mesas,
           coalesce((select sum(b.monto) from bonos b where b.evento_id = e.id and b.user_id = v_uid), 0)::numeric as bono,
           (impl.comision_manilla(e.id, v_uid)).rrpp::numeric as por_manilla
      from evs e
      join v_stats_rrpp s on s.evento_id = e.id and s.rrpp_id = v_uid
      left join v_stats_mesas m on m.evento_id = e.id and m.rrpp_id = v_uid
  ),
  -- comisión de jefe: la de todo su team en ese evento, solo si es jefe ahí
  jefe as (
    select b.id,
           case when rol_en_club(b.club_id) = 'jefe' and b.team_id is not null
                then coalesce((select sum(s2.comision_jefe) from v_stats_rrpp s2
                                where s2.evento_id = b.id and s2.team_id = b.team_id), 0)
                   + coalesce((select sum(m2.comision_jefe_mesas) from v_stats_mesas m2
                                where m2.evento_id = b.id and m2.team_id = b.team_id), 0)
                else 0 end::numeric as cj
      from base b
  )
  select b.id, b.club_id, c.nombre, c.logo_url, b.nombre, b.fecha, b.estado,
         b.anotados, b.ingresaron, b.entradas_vendidas, b.entradas_usadas,
         b.mesas_conf, b.mesas_res, b.bruto_entradas, b.bruto_mesas,
         b.comision_rrpp, b.comision_rrpp_mesas, j.cj, b.bono,
         b.comision_rrpp + b.comision_rrpp_mesas + j.cj + b.bono,
         b.por_manilla,
         case when rr.pagado then 'pagada'
              when b.estado = 'cerrado' then 'confirmada'
              else 'estimada' end,
         case when rr.pagado then rr.marcado_at end
    from base b
    join jefe j on j.id = b.id
    join clubs c on c.id = b.club_id
    left join rendicion_rrpp rr on rr.evento_id = b.id and rr.rrpp_id = v_uid
   order by b.fecha desc;
end;
$$;
notify pgrst,'reload schema';
