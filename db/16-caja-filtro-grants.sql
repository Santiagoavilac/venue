-- FIX (2026-08-23) · las tablas del filtro de caja no tenían GRANT para
-- `authenticated`, así que la app fallaba al guardar una excepción.
--
-- Causa: `create table` no otorga nada a los roles de PostgREST. Las tablas
-- viejas del proyecto (caja_check, venta_excepcion, …) sí los tienen porque
-- se crearon con los defaults del origen. RLS ya permitía la fila —el
-- permiso de TABLA la frenaba antes de llegar a la política—.
--
-- Por qué no lo cazó la suite: probaba con `set local role authenticated`
-- partiendo de `postgres`, que conserva privilegios heredados; el GRANT
-- faltante no se nota por ese camino. La prueba nueva lo verifica leyendo
-- information_schema, que es donde se ve de verdad.
--
-- Se otorga sólo a `authenticated`: `anon` (sin sesión) no tiene nada que
-- hacer acá, y quién puede escribir lo sigue decidiendo la RLS
-- (admin_principal manda) — el GRANT es la puerta, la política es el filtro.
grant select, insert, update, delete on caja_filtro           to authenticated;
grant select, insert, update, delete on caja_filtro_excepcion to authenticated;

notify pgrst, 'reload schema';
