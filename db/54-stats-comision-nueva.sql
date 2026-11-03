-- 54 · v_stats_rrpp usa la comisión nueva
--
-- Al renombrar la cuenta vieja (52) la vista quedó apuntando a
-- comision_manilla_v1 (las vistas guardan la función, no su nombre). Se la
-- vuelve a apuntar a impl.comision_manilla, que decide sola cuenta vieja o nueva.
do $$
declare d text; n text;
begin
  d := pg_get_viewdef('public.v_stats_rrpp'::regclass);
  n := replace(d, 'impl.comision_manilla_v1(', 'impl.comision_manilla(');
  if n = d then raise exception 'v_stats_rrpp: no apuntaba a la cuenta vieja'; end if;
  execute 'create or replace view public.v_stats_rrpp as ' || n;
end $$;
