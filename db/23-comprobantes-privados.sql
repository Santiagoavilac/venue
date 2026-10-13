-- SEGURIDAD (6/…) · comprobantes de pago en almacenamiento PRIVADO.
--
-- El bucket `comprobantes` era público: cualquiera con la URL veía la
-- captura de la transferencia (nombre, banco, monto), sin sesión.
--
-- Ahora es privado y la imagen se pide con una URL firmada de corta
-- duración (createSignedUrl), que solo consigue quien tiene permiso de
-- lectura sobre el objeto.
--
-- Quién lee un comprobante (los archivos viven en <uid del que subió>/…):
--   · quien lo subió;
--   · admin o caja que comparte boliche con esa persona;
--   · el jefe del team de esa persona.
--
-- MIGRACIÓN de lo existente: las columnas comprobante_url guardan la URL
-- pública vieja. No hace falta reescribirlas: el cliente extrae la ruta de
-- lo que viene después de "/comprobantes/" y pide la URL firmada. Los
-- archivos no se mueven.
-- Re-ejecutable.

update storage.buckets set public = false where id = 'comprobantes';

drop policy if exists comprobantes_leer on storage.objects;
create policy comprobantes_leer on storage.objects for select to authenticated
  using (bucket_id = 'comprobantes' and (
    (storage.foldername(name))[1] = auth.uid()::text
    or es_platform_admin()
    or (rol_actual() in ('admin', 'caja')
        and comparte_club(((storage.foldername(name))[1])::uuid))
    or (rol_actual() = 'jefe' and exists (
          select 1 from profiles p
           where p.id::text = (storage.foldername(name))[1]
             and p.team_id = mi_team_base()))));
