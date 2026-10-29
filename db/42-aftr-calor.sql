-- 42 · Calor del mapa de AFTR: dónde se están vendiendo entradas.
--
-- Una fila por boliche visible en AFTR con su próximo evento público y una
-- intensidad de 0 a 1 (sus entradas vendidas sobre las del boliche que más
-- vendió). Nunca devuelve el número de entradas: el mapa es público y no
-- muestra las ventas de cada boliche.
create or replace function public.aftr_calor()
returns table (club_id text, intensidad numeric)
language sql
stable
security definer
set search_path = public
as $$
  with prox as (
    select distinct on (e.club_id) e.club_id, e.id
      from eventos e
      join clubs c on c.id = e.club_id
     where c.activo and c.aftr_visible and c.lat is not null and c.lng is not null
       and e.aftr_publico and e.estado <> 'cerrado' and e.fecha >= current_date
     order by e.club_id, e.fecha, e.hora_inicio nulls last
  ),
  ventas as (
    select p.club_id,
           (select count(*) from entradas x
             where x.evento_id = p.id and x.estado <> 'anulada' and x.mesa_id is null) as n
      from prox p
  )
  select v.club_id, round(v.n::numeric / nullif(max(v.n) over (), 0), 3)
    from ventas v
   where v.n > 0;
$$;

revoke all on function public.aftr_calor() from public;
grant execute on function public.aftr_calor() to anon, authenticated;
