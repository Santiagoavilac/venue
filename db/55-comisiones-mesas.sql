-- 55 · Comisión de cada mesa, calculada por el servidor
--
-- La web y la app sumaban la comisión fija del combo por su cuenta, sin mirar
-- la operación del evento. Ahora la piden acá (misma regla que v_stats_mesas
-- y la liquidación). Admin y seguridad ven todas; jefe, su team; relacionador,
-- las suyas.
create or replace function public.comisiones_mesas(p_evento uuid)
returns table (mesa_id uuid, precio numeric, vendido_por uuid, rrpp numeric, jefe numeric)
language plpgsql
stable
security definer
set search_path = public
as $$
#variable_conflict use_column
begin
  perform impl.exigir(impl.club_de('evento', p_evento), '{admin,jefe,rrpp,portero}'::text[]);
  return query
  select m.id, m.precio::numeric, m.vendido_por, c.rrpp, c.jefe
    from mesas m
    cross join lateral impl.comision_mesa(m.id) c
   where m.evento_id = p_evento and m.estado <> 'disponible'
     and (rol_en('evento', p_evento) in ('admin', 'portero') or impl.ve_registro(p_evento, m.vendido_por));
end;
$$;
revoke all on function public.comisiones_mesas(uuid) from public, anon;
grant execute on function public.comisiones_mesas(uuid) to authenticated;
