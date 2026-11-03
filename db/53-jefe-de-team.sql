-- 53 · El jefe de un team es quien tiene rol jefe en ese team (en ese boliche)
--
-- teams.jefe_id no se completa en la práctica (está vacío en todos los teams);
-- el jefe se reconoce por su rol, igual que en el resto del sistema. Sin jefe,
-- quien vende cobra el pozo entero.
create or replace function impl.jefe_de_team(p_team uuid, p_club text)
returns uuid
language sql
stable
security definer
set search_path = public
as $$
  select coalesce(
    (select t.jefe_id from teams t where t.id = p_team),
    (select x.user_id from impl.teams_efectivos(p_club) x
      where x.team_id = p_team and x.rol = 'jefe' order by x.nombre limit 1));
$$;
grant execute on function impl.jefe_de_team(uuid, text) to authenticated;
revoke all on function impl.jefe_de_team(uuid, text) from public, anon;

create or replace function impl.repartir(p_evento uuid, p_persona uuid, p_pozo numeric,
  out rrpp numeric, out jefe numeric)
language plpgsql
stable
security definer
set search_path = public
as $$
declare e eventos; p profiles; v_team uuid; v_jefe uuid;
begin
  rrpp := 0; jefe := 0;
  select * into e from eventos where id = p_evento;
  select * into p from profiles where id = p_persona;
  -- los admin no cobran comisión (regla de siempre); sin pozo no hay nada
  if not found or p.rol = 'admin' or coalesce(p_pozo, 0) <= 0 or e.modo_comision = 'ninguno' then return; end if;
  if e.modo_comision = 'relacionadores' then
    rrpp := p_pozo; return;
  end if;
  v_team := impl.team_efectivo(p_persona, e.club_id);
  if v_team is not null then v_jefe := impl.jefe_de_team(v_team, e.club_id); end if;
  -- sin team, team sin jefe, o lo vende el propio jefe: todo para quien vendió
  if v_team is null or v_jefe is null or v_jefe = p_persona then
    rrpp := p_pozo; return;
  end if;
  rrpp := round(p_pozo * impl.reparto_pct(v_team, p_evento) / 100.0, 2);
  jefe := p_pozo - rrpp;
end;
$$;

-- solo el jefe de ese team (o un admin) fija el reparto
do $$
declare d text; n text;
begin
  d := pg_get_functiondef('public.fijar_reparto_jefe(uuid, numeric, uuid)'::regprocedure);
  n := replace(d, 'not exists (select 1 from teams t where t.id = v_team and t.jefe_id = auth.uid())',
                  'impl.jefe_de_team(v_team, e.club_id) is distinct from auth.uid()');
  if n = d then raise exception 'fijar_reparto_jefe: no se pudo reemplazar'; end if;
  execute n;
end $$;
