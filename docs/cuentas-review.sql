-- Cuentas para App Review de VENUE, en el boliche Burtown. YA APLICADO.
--
-- Los usuarios de acceso se crearon con la API de administración de Supabase
-- Auth y este script les dio el perfil y el rol. Queda como registro de cómo
-- se armaron, por si hay que rehacerlas.
--
-- Las contraseñas NO van acá: están en App Store Connect, en App Review
-- Information. Si hay que rotarlas, se cambian desde Authentication → Users
-- en el panel de Supabase y se actualizan ahí.
--
-- Entran por la puerta "Boliches", con usuario y contraseña:
--   applereview  → admin de Burtown
--   reviewrrpp   → relacionador de Burtown

insert into profiles (id, usuario, nombre, rol, clubs, activo, puede_tickear)
values
  ('1366242a-d898-4db0-86e3-fb093542a8cb', 'applereview', 'App Review',
   'admin', array['burtown'], true, true),
  ('c1528e78-5a5d-4f8f-a8bc-c9c37231506a', 'reviewrrpp', 'App Review RRPP',
   'rrpp', array['burtown'], true, true)
on conflict (id) do update set
  usuario = excluded.usuario,
  nombre = excluded.nombre,
  rol = excluded.rol,
  clubs = excluded.clubs,
  activo = true;

-- Comprobar que quedaron bien:
select usuario, nombre, rol, clubs, activo from profiles
 where usuario in ('applereview', 'reviewrrpp');
