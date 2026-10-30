-- 50 · Resumen de Accesos: cada uno ve sus números (misma regla que 47/49)
create or replace function public.resumen_evento(p_evento uuid)
returns json
language plpgsql
stable
security definer
set search_path = public
as $function$
        #variable_conflict use_column
        declare v_rol text;
        begin
          v_rol := impl.exigir(impl.club_de('evento', p_evento), '{admin,jefe,rrpp,portero}'::text[]);
          if v_rol in ('admin', 'portero') then return impl.resumen_evento(p_evento); end if;
          -- relacionador: lo suyo; jefe: lo suyo y lo de su team
          return json_build_object(
            'anotados',   (select count(*)::int from registros r where r.evento_id = p_evento and impl.ve_registro(p_evento, r.rrpp_id)),
            'ingresaron', (select count(*)::int from registros r where r.evento_id = p_evento and r.ingreso_at is not null and impl.ve_registro(p_evento, r.rrpp_id)),
            'entradas',   (select count(*)::int from entradas e where e.evento_id = p_evento and e.estado <> 'anulada' and e.mesa_id is null and impl.ve_registro(p_evento, e.rrpp_id)),
            'qr_total',   (select count(*)::int from entradas e where e.evento_id = p_evento and impl.ve_registro(p_evento, e.rrpp_id)),
            'qr_usados',  (select count(*)::int from entradas e where e.evento_id = p_evento and e.estado = 'usada' and impl.ve_registro(p_evento, e.rrpp_id)),
            'mesas',      (select count(*)::int from mesas m where m.evento_id = p_evento and m.estado <> 'disponible' and impl.ve_registro(p_evento, m.vendido_por))
          );
        end;
        $function$;
