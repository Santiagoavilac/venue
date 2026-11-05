-- mesas_detalle se lee, no se escribe.
--
-- La vista se creó para mostrar el plano a todos y la plata sólo a quien
-- corresponde, y por eso va con security_invoker = false: tiene que poder
-- leer las columnas aunque quien pregunta no pueda. El efecto de lado es que
-- todo lo que pase por la vista corre con los permisos de su dueño, que es
-- postgres, y postgres no pasa por RLS.
--
-- Postgres hace esta vista actualizable sola (una sola tabla, columnas
-- simples), y Supabase concede por defecto todo lo que se cree en public a
-- authenticated. Las dos cosas juntas dejaban que cualquiera con sesión
-- escribiera en `mesas` a través de la vista sin pasar por ninguna política:
-- liberar la mesa de otro, cambiarle el precio, marcarla pagada o borrar las
-- mesas de un evento entero.
--
-- Acá queda sólo SELECT. Escribir mesas sigue siendo lo de siempre: la tabla,
-- con sus políticas y sus guardas.
revoke all on public.mesas_detalle from authenticated, anon, public;
grant select on public.mesas_detalle to authenticated;

-- No se tocan los permisos por defecto del esquema: las TABLAS de este
-- sistema se protegen con RLS, no quitando el grant, y sacárselo haría fallar
-- la próxima tabla que se cree esperando lo de siempre. El problema es de las
-- VISTAS con security_invoker = false, que no pasan por RLS: cada una que se
-- agregue tiene que quedar en sólo lectura como ésta.
