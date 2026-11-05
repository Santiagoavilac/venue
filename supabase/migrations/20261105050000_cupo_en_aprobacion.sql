-- El tope de relacionadores también se aplica al aprobar una solicitud.
-- Sin esto, el enlace con rol respeta el cupo pero la aprobación manual no,
-- y el tope deja de significar algo.
CREATE OR REPLACE FUNCTION public.resolver_solicitud(p_id uuid, p_aprobar boolean, p_team uuid DEFAULT NULL::uuid)
 RETURNS json
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  s solicitud_union;
  v_rol text;
  v_team uuid;
begin
  select * into s from solicitud_union where id = p_id for update;
  if not found or s.estado <> 'pendiente' then raise exception 'Esa solicitud ya fue resuelta.'; end if;
  if s.user_id = auth.uid() then raise exception 'No podés resolver tu propia solicitud.' using errcode = '42501'; end if;
  v_rol := impl.exigir(s.club_id, '{admin,jefe}'::text[]);
  if v_rol = 'jefe' then
    v_team := impl.team_en_club(auth.uid(), s.club_id);
    if v_team is null or (s.team_id is not null and s.team_id <> v_team) then
      raise exception 'Esa solicitud es de otro team.' using errcode = '42501';
    end if;
  else
    v_team := coalesce(p_team, s.team_id);
    if v_team is not null and not exists (select 1 from teams t where t.id = v_team and t.activo
              and (coalesce(array_length(t.clubs, 1), 0) = 0 or s.club_id = any(t.clubs))) then
      raise exception 'Ese team no trabaja en este boliche.';
    end if;
  end if;

  update solicitud_union
     set estado = case when p_aprobar then 'aprobada' else 'rechazada' end,
         team_id = case when p_aprobar then v_team else team_id end,
         resuelto_por = auth.uid(), resuelto_at = now()
   where id = s.id;

  if p_aprobar then
    -- el tope de relacionadores del boliche también frena una aprobación:
    -- si no, el enlace respeta el cupo y esta puerta lo evade
    if exists (select 1 from clubs x where x.id = s.club_id and x.max_relacionadores is not null
                 and impl.relacionadores_activos(s.club_id) >= x.max_relacionadores) then
      raise exception 'Este boliche llegó a su tope de relacionadores. Liberá un lugar antes de aprobar.';
    end if;
    perform set_config('venue.perfil_aprobado', '1', true);
    insert into club_membership (user_id, club_id, rol, team_id, activo, origen, aprobado_por, aprobado_at, revocado_at)
    values (s.user_id, s.club_id, 'rrpp', v_team, true, s.origen, auth.uid(), now(), null)
    on conflict (user_id, club_id) do update
       set rol = 'rrpp', team_id = excluded.team_id, activo = true, origen = excluded.origen,
           aprobado_por = excluded.aprobado_por, aprobado_at = excluded.aprobado_at, revocado_at = null;
  end if;
  return json_build_object('estado', case when p_aprobar then 'aprobada' else 'rechazada' end, 'team_id', v_team);
end;
$function$
;
