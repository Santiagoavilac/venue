-- Fotos privadas: cada cliente solo puede gestionar sus propios archivos.
alter table public.aftr_clientes add column if not exists foto_archivo text;

insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types)
values('aftr-perfiles','aftr-perfiles',false,2097152,array['image/jpeg','image/png','image/webp'])
on conflict(id) do update set public=false, file_size_limit=excluded.file_size_limit,
allowed_mime_types=excluded.allowed_mime_types;

drop policy if exists aftr_foto_leer on storage.objects;
create policy aftr_foto_leer on storage.objects for select to authenticated
using(bucket_id='aftr-perfiles' and (storage.foldername(name))[1]=(select auth.uid())::text);
drop policy if exists aftr_foto_crear on storage.objects;
create policy aftr_foto_crear on storage.objects for insert to authenticated
with check(bucket_id='aftr-perfiles' and (storage.foldername(name))[1]=(select auth.uid())::text
and exists(select 1 from public.aftr_clientes c where c.user_id=(select auth.uid())));
drop policy if exists aftr_foto_borrar on storage.objects;
create policy aftr_foto_borrar on storage.objects for delete to authenticated
using(bucket_id='aftr-perfiles' and (storage.foldername(name))[1]=(select auth.uid())::text);

create or replace function public.aftr_cambiar_foto(p_archivo text default null)
returns jsonb language plpgsql volatile security definer set search_path=public,pg_temp
as $$
declare v_uid uuid := auth.uid(); v_cliente public.aftr_clientes;
begin
  if v_uid is null then raise exception 'Iniciá sesión.' using errcode='28000'; end if;
  if not exists(select 1 from public.aftr_clientes where user_id=v_uid) then
    raise exception 'Completá tu perfil antes de cambiar la foto.';
  end if;
  if p_archivo is not null then
    if p_archivo !~ ('^'||v_uid::text||'/[a-z0-9-]{16,80}\.(jpg|png|webp)$') then
      raise exception 'La foto no pertenece a tu cuenta.' using errcode='42501';
    end if;
    if not exists(select 1 from storage.objects where bucket_id='aftr-perfiles' and name=p_archivo) then
      raise exception 'Primero subí la foto.';
    end if;
  end if;
  update public.aftr_clientes set foto_archivo=p_archivo, foto_url=null where user_id=v_uid
  returning * into v_cliente;
  return to_jsonb(v_cliente);
end;
$$;
revoke all on function public.aftr_cambiar_foto(text) from public,anon;
grant execute on function public.aftr_cambiar_foto(text) to authenticated;
notify pgrst,'reload schema';
