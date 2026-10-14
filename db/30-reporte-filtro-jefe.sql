-- "Rechazados en puerta" para el jefe, acotado a su team.
--
-- La web siempre le mostró este reporte al jefe, pero la guarda de
-- 19-rpc-guardas lo dejaba solo al admin (el jefe recibía "No autorizado").
-- El reporte original devolvía todos los teams; ahora el jefe ve únicamente
-- a los relacionadores de su team. El cambio quedó también en la matriz de
-- 19-rpc-guardas.sql, así que re-correr ese archivo da el mismo resultado.
-- Aplicado como migración 30_reporte_filtro_jefe_su_team.

update impl.rpc_permiso
   set roles = 'admin,jefe',
       guarda = impl.g('evento','p_evento','admin,jefe'),
       filtro = 'v_rol in (''admin'', ''servicio'') or t.usuario in (select pr.usuario from profiles pr where pr.team_id = mi_team_en_club(impl.club_de(''evento'', p_evento)) union select pr.usuario from club_membership cm join profiles pr on pr.id = cm.user_id where cm.club_id = impl.club_de(''evento'', p_evento) and cm.team_id = mi_team_en_club(impl.club_de(''evento'', p_evento)))',
       nota = 'el jefe ve solo los rechazados de su team'
 where fn = 'reporte_filtro';

drop function if exists public.reporte_filtro(uuid);
create function public.reporte_filtro(p_evento uuid)
returns table(rrpp text, team text, usuario text, cantidad bigint, personas text[])
language plpgsql stable security definer set search_path = public
as $guarda$
#variable_conflict use_column
declare v_rol text;
begin
  v_rol := impl.exigir(impl.club_de('evento', p_evento), '{admin,jefe}'::text[]);
  return query select * from impl.reporte_filtro(p_evento) t
   where v_rol in ('admin', 'servicio')
      or t.usuario in (select pr.usuario from profiles pr
                        where pr.team_id = mi_team_en_club(impl.club_de('evento', p_evento))
                       union
                       select pr.usuario from club_membership cm join profiles pr on pr.id = cm.user_id
                        where cm.club_id = impl.club_de('evento', p_evento)
                          and cm.team_id = mi_team_en_club(impl.club_de('evento', p_evento)));
end;
$guarda$;
comment on function public.reporte_filtro(uuid) is 'venue:guarda';
revoke all on function public.reporte_filtro(uuid) from public, anon;
grant execute on function public.reporte_filtro(uuid) to authenticated;
