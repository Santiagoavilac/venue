-- Subir con "reemplazar si existe" (upsert) necesita poder LEER el objeto
-- existente. El bucket `disenos` es público (artes, fondos de plano, QRs de
-- cobro), pero faltaba la política de lectura por la API autenticada: sin
-- ella, volver a subir el fondo de un plano o el arte de un evento fallaba.
-- Re-ejecutable.
drop policy if exists disenos_leer on storage.objects;
create policy disenos_leer on storage.objects for select to authenticated
  using (bucket_id = 'disenos');
drop policy if exists disenos_borrar on storage.objects;
create policy disenos_borrar on storage.objects for delete to authenticated
  using (bucket_id = 'disenos'
    and exists (select 1 from profiles p where p.id = auth.uid() and p.rol = 'admin'));
drop policy if exists comprobantes_borrar on storage.objects;
create policy comprobantes_borrar on storage.objects for delete to authenticated
  using (bucket_id = 'comprobantes' and (storage.foldername(name))[1] = auth.uid()::text);
