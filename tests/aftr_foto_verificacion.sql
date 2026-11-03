-- Toda la prueba termina en ROLLBACK: no cambia fotos ni perfiles reales.
begin;
select set_config('request.jwt.claim.sub',(select user_id::text from public.aftr_clientes order by created_at desc limit 1),true);
do $$ begin
  if auth.uid() is null then raise exception 'Se necesita un perfil AFTR para esta verificación.'; end if;
end $$;
insert into storage.objects(bucket_id,name,metadata)
values ('aftr-perfiles',auth.uid()::text||'/prueba-perfil-00000001.png','{"mimetype":"image/png","size":68}'),
       ('aftr-perfiles','00000000-0000-4000-8000-000000000099/prueba-perfil-00000002.png','{"mimetype":"image/png","size":68}');
set local role authenticated;
do $$
declare ruta text:=auth.uid()::text||'/prueba-perfil-00000001.png';
begin
  perform public.aftr_cambiar_foto(ruta);
  assert (public.aftr_mi_perfil()->>'foto_archivo')=ruta, 'No se guardó la foto propia';
  assert exists(select 1 from storage.objects where bucket_id='aftr-perfiles' and name=ruta), 'No puede leer la foto propia';
  assert not exists(select 1 from storage.objects where bucket_id='aftr-perfiles' and name like '00000000-0000-4000-8000-000000000099/%'), 'RLS permite leer la foto ajena';
  begin
    perform public.aftr_cambiar_foto('00000000-0000-4000-8000-000000000099/prueba-perfil-00000002.png');
    raise exception 'Se aceptó una foto ajena';
  exception when insufficient_privilege then null; end;
  begin
    perform public.aftr_cambiar_foto(auth.uid()::text||'/../prueba-perfil-00000001.png');
    raise exception 'Se aceptó un directorio inválido';
  exception when insufficient_privilege then null; end;
  begin
    perform public.aftr_cambiar_foto(auth.uid()::text||'/archivo-inexistente-001.png');
    raise exception 'Se aceptó una foto inexistente';
  exception when raise_exception then
    if sqlerrm <> 'Primero subí la foto.' then raise; end if;
  end;
  assert (public.aftr_mi_perfil()->>'foto_archivo')=ruta, 'Una falla modificó la foto previa';
  perform public.aftr_cambiar_foto(null);
  assert (public.aftr_mi_perfil()->>'foto_archivo') is null, 'No se pudo quitar la foto';
end $$;
set local role anon;
do $$ begin
  begin
    perform public.aftr_cambiar_foto(null);
    raise exception 'Un anónimo pudo cambiar la foto';
  exception when insufficient_privilege then null; end;
end $$;
rollback;
