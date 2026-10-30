-- 49 · Teams separados: nada cruza de un team a otro
--
-- * "A nombre de": el jefe solo puede cargar a nombre de la gente de SU
--   team (listas y mesas). El relacionador, solo a su nombre. El admin, de
--   cualquiera. Se controla acá, no en la pantalla.
-- * La lista de "a nombre de quién" que ve el jefe trae solo a su team.
-- * Entradas: la misma regla de lectura que las listas (47): admin y
--   seguridad todo, jefe lo suyo y su team, relacionador lo suyo.

create or replace function impl.exigir_mismo_team(p_club text, p_otro uuid)
returns void
language plpgsql
stable
security definer
set search_path = public
as $$
declare v_rol text := rol_en_club(p_club); v_mio uuid;
begin
  if p_otro is null or p_otro = auth.uid() or v_rol = 'admin' then return; end if;
  if v_rol = 'jefe' then
    v_mio := impl.team_en_club(auth.uid(), p_club);
    if v_mio is not null and v_mio = impl.team_en_club(p_otro, p_club) then return; end if;
    raise exception 'Solo podés cargar a nombre de la gente de tu team.';
  end if;
  raise exception 'No podés cargar a nombre de otra persona.';
end;
$$;

create or replace function public.vendedores_posibles(p_evento uuid)
returns table (id uuid, rol text, team text, nombre text)
language plpgsql
stable
security definer
set search_path = public
as $$
#variable_conflict use_column
declare v_rol text; v_club text; v_mio uuid;
begin
  v_club := impl.club_de('evento', p_evento);
  v_rol := impl.exigir(v_club, '{admin,jefe,rrpp}'::text[]);
  if v_rol = 'admin' then
    return query select * from impl.vendedores_posibles(p_evento) t;
  elsif v_rol = 'jefe' then
    v_mio := impl.team_en_club(auth.uid(), v_club);
    return query select * from impl.vendedores_posibles(p_evento) t
      where t.id = auth.uid() or (v_mio is not null and impl.team_en_club(t.id, v_club) = v_mio);
  else
    return query select * from impl.vendedores_posibles(p_evento) t where t.id = auth.uid();
  end if;
end;
$$;

create or replace function public.registrar_lista(p_lista uuid, p_nombres text[], p_a_nombre_de uuid default null)
returns json
language plpgsql
security definer
set search_path = public
as $function$
        #variable_conflict use_column
        declare v_rol text;
        begin
          v_rol := impl.exigir(impl.club_de('lista', p_lista), '{admin,jefe,rrpp}'::text[]);
          perform impl.exigir_mismo_team(impl.club_de('lista', p_lista), p_a_nombre_de);
          if v_rol in ('rrpp','jefe') then declare v_cupo int; v_tengo int; v_total int; v_hay int; v_n int := coalesce(array_length(p_nombres, 1), 0); begin select lt.cupo_total into v_total from lista_tipos lt where lt.id = p_lista; if v_total is not null then select count(*) into v_hay from registros rg where rg.lista_tipo_id = p_lista; if v_hay + v_n > v_total then raise exception 'La lista está llena: quedan % lugar(es).', greatest(v_total - v_hay, 0); end if; end if; if p_a_nombre_de is null then select mc.cupo into v_cupo from impl.mis_cupos((select lt.evento_id from lista_tipos lt where lt.id = p_lista)) mc where mc.lista_tipo_id = p_lista; if v_cupo is not null then select count(*) into v_tengo from registros rg where rg.lista_tipo_id = p_lista and rg.rrpp_id = auth.uid(); if v_tengo + v_n > v_cupo then raise exception 'Cupo agotado: te quedan % lugar(es) en esta lista.', greatest(v_cupo - v_tengo, 0); end if; end if; end if; end; end if;
          perform impl.exigir_permiso(impl.club_de('lista', p_lista), 'listas'); return impl.registrar_lista(p_lista, p_nombres, p_a_nombre_de);
        end;
        $function$;

create or replace function public.vender_mesa(p_mesa uuid, p_cliente text, p_combo uuid, p_botellas text[], p_manillas integer, p_estado text, p_cantidad integer default 1, p_comprobante text default null, p_efectivo boolean default false, p_a_nombre_de uuid default null, p_cortesia boolean default false)
returns json
language plpgsql
security definer
set search_path = public
as $function$
        #variable_conflict use_column
        declare v_rol text;
        begin
          v_rol := impl.exigir(impl.club_de('mesa', p_mesa), '{admin,jefe,rrpp}'::text[]); perform 1 from mesas ms where ms.id = p_mesa for update;
          perform impl.exigir_mismo_team(impl.club_de('mesa', p_mesa), p_a_nombre_de);
          perform impl.exigir_permiso(impl.club_de('mesa', p_mesa), 'mesas'); return impl.vender_mesa(p_mesa, p_cliente, p_combo, p_botellas, p_manillas, p_estado, p_cantidad, p_comprobante, p_efectivo, p_a_nombre_de, p_cortesia);
        end;
        $function$;

create or replace function public.vender_mesa_grupo(p_mesas uuid[], p_cliente text, p_combo uuid, p_botellas text[], p_manillas integer, p_estado text, p_cantidad integer default 1, p_comprobante text default null, p_efectivo boolean default false, p_a_nombre_de uuid default null, p_cortesia boolean default false)
returns json
language plpgsql
security definer
set search_path = public
as $function$
        #variable_conflict use_column
        declare v_rol text;
        begin
          v_rol := impl.exigir_mesas(p_mesas, '{admin,jefe,rrpp}'::text[]); perform 1 from mesas ms where ms.id = any(p_mesas) order by ms.id for update;
          perform impl.exigir_mismo_team(impl.club_de('mesa', p_mesas[1]), p_a_nombre_de);
          perform impl.exigir_permiso(impl.club_de('mesa', p_mesas[1]), 'mesas'); return impl.vender_mesa_grupo(p_mesas, p_cliente, p_combo, p_botellas, p_manillas, p_estado, p_cantidad, p_comprobante, p_efectivo, p_a_nombre_de, p_cortesia);
        end;
        $function$;

drop policy if exists entradas_leer on entradas;
create policy entradas_leer on entradas for select to authenticated
  using (impl.ve_registro(evento_id, rrpp_id));
