-- La foto del autor en las historias.
--
-- El círculo de cada historia mostraba solo la inicial del nombre: la foto de
-- perfil existía pero nunca llegaba al feed, y el bucket aftr-perfiles solo se
-- podía leer a sí mismo, así que ni con la ruta se podía firmar la imagen de
-- otra persona.
--
-- Acá el JSON de cada historia agrega la foto del autor (el logo del boliche
-- cuando publica un club) y la lectura del bucket se abre a los usuarios con
-- sesión, pero solo para los archivos que hoy son la foto de perfil de alguien:
-- los restos de fotos cambiadas o borradas siguen siendo privados, y la ruta
-- solo se conoce donde el servidor decide mandarla.
-- aftr_clientes solo se lee a sí mismo, así que la pregunta "¿este archivo es
-- la foto de alguien?" va en una función que la responde sin abrir la tabla.
create or replace function public.aftr_foto_de_perfil(p_archivo text) returns boolean
language sql stable security definer set search_path=public,pg_temp as $$
 select p_archivo is not null and exists(
  select 1 from public.aftr_clientes c where c.foto_archivo=p_archivo)
$$;
revoke all on function public.aftr_foto_de_perfil(text) from public,anon;
grant execute on function public.aftr_foto_de_perfil(text) to authenticated;

drop policy if exists aftr_foto_leer on storage.objects;
create policy aftr_foto_leer on storage.objects for select to authenticated
using(bucket_id='aftr-perfiles' and ((storage.foldername(name))[1]=(select auth.uid())::text
  or public.aftr_foto_de_perfil(name)));

create or replace function impl.social_historia_json(h public.aftr_historias) returns jsonb
language sql stable security definer set search_path=public,pg_temp as $$
 select jsonb_build_object('id',h.id,'autor_id',h.autor_id,'autor',coalesce(c.nombre,p.nombre,'AFTR'),
 'nombre',case when h.identidad='club' then cl.nombre else coalesce(c.nombre,p.nombre,'AFTR') end,
 'foto',case when h.identidad='club' then cl.logo_url else c.foto_url end,
 'foto_archivo',case when h.identidad='club' then null else c.foto_archivo end,
 'identidad',h.identidad,'club_id',h.club_id,'evento_id',h.evento_id,'evento',e.nombre,
 'cta',h.cta,'storage_path',h.storage_path,'tipo',h.tipo,'duracion_ms',h.duracion_ms,
 'created_at',h.created_at,'vence_at',h.vence_at,'retirada_at',h.retirada_at,
 'can_retirar',h.autor_id=auth.uid() or es_platform_admin() or (h.identidad='club' and rol_en_club(h.club_id) in ('admin','propietario')))
 from (select 1) b left join aftr_clientes c on c.user_id=h.autor_id left join profiles p on p.id=h.autor_id
 left join clubs cl on cl.id=h.club_id left join eventos e on e.id=h.evento_id
$$;
notify pgrst,'reload schema';
