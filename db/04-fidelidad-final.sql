-- FIDELIDAD FINAL · lo que la app necesita para operar contra el destino
-- y que no es una RPC: constraints que sus UPSERTs directos exigen, y el
-- Storage.  (Sigue siendo ETAPA 1: sin esto la app no funciona igual.)
--
-- EVIDENCIA:
-- · La app hace upsert directo sobre plano_fondos (club_id, planta),
--   caja_check (evento_id, user_id), club_membership (user_id, club_id) y
--   cupo_rrpp (lista_tipo_id, user_id): PostgREST exige un UNIQUE para que
--   el upsert actualice en vez de duplicar ⇒ el origen los tiene sí o sí.
--   Verificado contra los datos: CERO duplicados en las cuatro claves.
-- · Buckets: la app sube a 'disenos' (artes, fondos, QRs de cobro — solo
--   admin en la UI) y 'comprobantes' (fotos de transferencias), ambos con
--   getPublicUrl ⇒ públicos en el origen. El comentario del cliente
--   (app.js:6116) afirma la política real de comprobantes: "el bucket
--   exige que el archivo cuelgue de la carpeta del propio usuario".

-- Columnas que el ORIGEN agregó el 2026-08-20 (el tercero sigue
-- desarrollando): ambas boolean, sin nulls, default false observado
-- (solo_invitaciones=true únicamente en socio1). La paridad de lectura
-- se re-corrió tras agregarlas: 117/117 — hasta hoy son solo aditivas,
-- ninguna RPC de lectura cambió su salida por ellas.
alter table profiles add column if not exists solo_invitaciones boolean not null default false;
alter table registros add column if not exists oculto boolean not null default false;

alter table club_membership add primary key (user_id, club_id);
alter table cupo_rrpp add primary key (lista_tipo_id, user_id);
alter table plano_fondos add primary key (club_id, planta);
alter table caja_check add primary key (evento_id, user_id);
alter table cupo_permanente add primary key (club_id, user_id, lista_nombre);

-- Storage: buckets públicos como en el origen
insert into storage.buckets (id, name, public)
values ('disenos', 'disenos', true), ('comprobantes', 'comprobantes', true)
on conflict (id) do nothing;

-- comprobantes: cada quien sube SOLO bajo su carpeta {auth.uid()}/...
drop policy if exists comprobantes_subir on storage.objects;
create policy comprobantes_subir on storage.objects for insert to authenticated
  with check (bucket_id = 'comprobantes' and (storage.foldername(name))[1] = auth.uid()::text);
drop policy if exists comprobantes_pisar on storage.objects;
create policy comprobantes_pisar on storage.objects for update to authenticated
  using (bucket_id = 'comprobantes' and (storage.foldername(name))[1] = auth.uid()::text);

-- disenos: solo el admin escribe (artes de evento/fase, fondos de plano,
-- QRs de cobro — toda la UI que sube acá es de admin)
drop policy if exists disenos_subir on storage.objects;
create policy disenos_subir on storage.objects for insert to authenticated
  with check (bucket_id = 'disenos'
    and exists (select 1 from profiles p where p.id = auth.uid() and p.rol = 'admin'));
drop policy if exists disenos_pisar on storage.objects;
create policy disenos_pisar on storage.objects for update to authenticated
  using (bucket_id = 'disenos'
    and exists (select 1 from profiles p where p.id = auth.uid() and p.rol = 'admin'));
