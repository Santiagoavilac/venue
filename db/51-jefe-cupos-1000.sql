-- 51 · Límites del jefe hasta 1000 (antes 500: un jefe con 1000 asignado por
-- el admin no podía guardar sin que se le bajara su propio límite)
do $$
declare d text;
begin
  select pg_get_functiondef('public.jefe_fijar_cupos(uuid,int,int)'::regprocedure) into d;
  d := replace(d, 'p_mio > 500', 'p_mio > 1000');
  d := replace(d, 'p_team > 500', 'p_team > 1000');
  d := replace(d, 'entre 0 y 500', 'entre 0 y 1000');
  execute d;
end $$;
