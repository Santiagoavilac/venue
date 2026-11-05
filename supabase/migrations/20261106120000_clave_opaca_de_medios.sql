-- El uid deja de viajar, y las firmas se piden todas juntas.
--
-- El feed de historias es anónimo a propósito (un visitante tiene que poder
-- mirar antes de hacerse cuenta) y devolvía, para cada historia:
--
--   autor_id      9a4297bc-2c08-456b-8d51-7429830417f7
--   storage_path  9a4297bc-2c08-456b-8d51-7429830417f7/3094a4….png
--   foto_archivo  9a4297bc-2c08-456b-8d51-7429830417f7/65f2cd….png
--
-- Es decir: un `curl` sin sesión contra aftr_historias enumera los uid de
-- quienes publicaron, tres veces cada uno. Con el uid se puede probar suerte
-- contra cualquier otro endpoint que acepte un id de usuario.
--
-- Acá el cliente deja de ver rutas y uid: ve una clave opaca por archivo
-- (`media_key`, `foto_key`) y se la cambia al servidor por una URL firmada. La
-- ruta real -que sigue teniendo el uid adentro, porque la política de subida de
-- storage se apoya en eso para saber de quién es cada archivo- no sale nunca
-- más de la base.
--
-- De paso se arreglan tres cosas que venían con la ruta:
--
-- * Firmar era de a una (`createSignedUrl` por archivo) y en el visor pasaba
--   en cada historia: un N+1 contra storage en el peor momento. La nueva
--   función recibe UNA lista.
-- * `aftr_social_archivo` -la política de lectura de storage- llama a
--   `es_platform_admin()`, que `anon` no puede ejecutar: el visitante sin sesión
--   recibía "permission denied" al firmar. O sea que las historias no se veían
--   sin cuenta, aunque el feed llegara. Ahora firma el servidor.
-- * `aftr_foto_leer` es sólo para `authenticated`, así que la foto de perfil
--   nunca aparecía en la web para un visitante. Mismo camino, mismo arreglo.
--
-- Las políticas de storage quedan como están: sin la ruta no se pueden usar, y
-- hay apps publicadas que todavía firman por su cuenta. Se cierran cuando esas
-- versiones caigan.

-- ── 1 · una clave por archivo ─────────────────────────────────────────
alter table public.aftr_historias
  add column if not exists media_key uuid not null default gen_random_uuid();
create unique index if not exists aftr_historias_media_key on public.aftr_historias (media_key);
comment on column public.aftr_historias.media_key is
  'Lo que ve el cliente en vez de storage_path: no dice de quien es el archivo.';

alter table public.aftr_clientes add column if not exists foto_key uuid;
create unique index if not exists aftr_clientes_foto_key on public.aftr_clientes (foto_key);
comment on column public.aftr_clientes.foto_key is
  'Clave opaca de foto_archivo. La renueva un trigger cada vez que cambia la foto.';

/* La clave se renueva con la foto, y se va con ella. Es un trigger y no una
   línea en cada RPC que toca el perfil porque hay varias y una que se olvide
   dejaría una clave apuntando a un archivo que ya no existe. */
create or replace function impl.aftr_foto_key() returns trigger
language plpgsql set search_path = public as $$
begin
  if tg_op = 'INSERT' or new.foto_archivo is distinct from old.foto_archivo then
    new.foto_key := case when new.foto_archivo is null then null else gen_random_uuid() end;
  end if;
  return new;
end $$;

drop trigger if exists aftr_clientes_foto_key on public.aftr_clientes;
create trigger aftr_clientes_foto_key before insert or update on public.aftr_clientes
  for each row execute function impl.aftr_foto_key();

update public.aftr_clientes set foto_key = gen_random_uuid()
 where foto_archivo is not null and foto_key is null;

-- ── 2 · cambiar claves por rutas, con el permiso de quien pregunta ────
-- Security definer para poder leer las rutas, pero la visibilidad se decide con
-- auth.uid(): la Edge Function tiene que llamarla con el token de la persona,
-- no con la llave de servicio. Si no hay sesión, se ve lo público y nada más.
create or replace function public.aftr_media_rutas(p_claves uuid[])
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare v_n int := coalesce(array_length(p_claves, 1), 0);
begin
  if v_n = 0 then return '[]'::jsonb; end if;
  if v_n > 60 then raise exception 'Demasiados archivos de una vez.'; end if;
  return coalesce((
    -- historias: mismo criterio que la política de storage
    select jsonb_agg(x) from (
      select jsonb_build_object('clave', h.media_key, 'bucket', 'aftr-historias', 'ruta', h.storage_path) as x
        from aftr_historias h
       where h.media_key = any (p_claves)
         and (aftr_historia_visible(h.id) or h.autor_id = auth.uid()
              or (h.identidad = 'club' and rol_en_club(h.club_id) in ('admin', 'propietario')))
      union all
      -- fotos de perfil: ya se muestran en el feed, no hay nada que esconder
      select jsonb_build_object('clave', c.foto_key, 'bucket', 'aftr-perfiles', 'ruta', c.foto_archivo)
        from aftr_clientes c
       where c.foto_key = any (p_claves) and c.foto_archivo is not null
    ) y), '[]'::jsonb);
end $$;
revoke all on function public.aftr_media_rutas(uuid[]) from public;
grant execute on function public.aftr_media_rutas(uuid[]) to anon, authenticated, service_role;

-- ── 3 · el feed deja de mandar rutas ni uid al visitante ────────────
-- Las apps publicadas firman el archivo por su cuenta con la ruta que trae el
-- feed. Si se la saca de golpe, dejan de mostrar historias. La ruta sigue
-- viajando para quien tiene sesión -que es el único caso en que esas versiones
-- pueden firmar- y desaparece para el visitante anónimo, que es por donde se
-- enumeraban los uid. Se saca del todo cuando esas versiones caigan.
create or replace function impl.social_historia_json(h aftr_historias)
returns jsonb language sql stable security definer set search_path to 'public', 'pg_temp'
as $function$
 select jsonb_build_object(
 'id',h.id,
 'autor_id',case when auth.uid() is not null then h.autor_id end,
 'grupo',case when h.identidad='club' then 'club:'||h.club_id else 'autor:'||md5(h.autor_id::text) end,
 'autor',coalesce(c.nombre,p.nombre,'AFTR'),
 'nombre',case when h.identidad='club' then cl.nombre else coalesce(c.nombre,p.nombre,'AFTR') end,
 'foto',case when h.identidad='club' then cl.logo_url else c.foto_url end,
 'foto_key',case when h.identidad='club' then null else c.foto_key end,
 'foto_archivo',case when auth.uid() is null or h.identidad='club' then null else c.foto_archivo end,
 'identidad',h.identidad,'club_id',h.club_id,'evento_id',h.evento_id,'evento',e.nombre,
 'cta',h.cta,'media_key',h.media_key,
 'storage_path',case when auth.uid() is not null then h.storage_path end,
 'tipo',h.tipo,'duracion_ms',h.duracion_ms,
 'created_at',h.created_at,'vence_at',h.vence_at,'retirada_at',h.retirada_at,
 'can_retirar',h.autor_id=auth.uid() or es_platform_admin() or (h.identidad='club' and rol_en_club(h.club_id) in ('admin','propietario')))
 from (select 1) b left join aftr_clientes c on c.user_id=h.autor_id left join profiles p on p.id=h.autor_id
 left join clubs cl on cl.id=h.club_id left join eventos e on e.id=h.evento_id
$function$;


-- aftr_historias.storage_path tiene una clave foránea a
-- aftr_media_validada.storage_path: la historia no puede apuntar a un archivo
-- que no se validó. Así que la ruta buena es esa columna y no una nueva al
-- lado. Al mover el archivo se actualiza storage_path, y queda anotado en
-- ruta_subida de dónde vino, para que el cliente -que sólo conoce la ruta que
-- subió- pueda seguir publicando con ella.
alter table public.aftr_media_validada drop column if exists ruta_final;
alter table public.aftr_media_validada add column if not exists ruta_subida text;
comment on column public.aftr_media_validada.ruta_subida is
  'Donde lo subio el cliente, antes de sacarlo de su carpeta. storage_path es donde esta ahora.';
create index if not exists aftr_media_validada_ruta_subida
  on public.aftr_media_validada (ruta_subida) where ruta_subida is not null;

-- Una ruta ya usada no se reusa, ni la actual ni la de la subida original.
create or replace function public.aftr_social_ruta_nueva(p_path text) returns boolean
language sql stable security definer set search_path to 'public', 'pg_temp' as $function$
 select split_part(p_path,'/',1)=auth.uid()::text
   and not exists(select 1 from aftr_media_validada
                   where storage_path=p_path or ruta_subida=p_path)
$function$;

create or replace function public.aftr_historias(p_accion text, p_datos jsonb default '{}'::jsonb)
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp'
as $function$
declare u uuid:=auth.uid(); h aftr_historias; m aftr_media_validada; v_identidad text; v_club text;
 v_evento uuid; v_id uuid; v_cta text; r jsonb; v_rol text; v_otro uuid;
begin
 if p_accion='feed' then
  return jsonb_build_object('historias',coalesce((select jsonb_agg(impl.social_historia_json(x) order by x.created_at)
   from (select * from aftr_historias hi where aftr_historia_visible(hi.id)
          and not exists (select 1 from aftr_bloqueos b
                           where b.bloqueador_id=u and b.bloqueado_id=hi.autor_id)
         order by hi.created_at desc limit 300) x),'[]'::jsonb),'ahora',now());
 end if;
 if u is null then raise exception 'Iniciá sesión.' using errcode='28000'; end if;
 if p_accion in ('mias','gestion') then
  return jsonb_build_object('historias',coalesce((select jsonb_agg(impl.social_historia_json(x) order by x.created_at desc)
   from (select * from aftr_historias where (p_datos->>'club_id' is null or club_id=p_datos->>'club_id') and
   (autor_id=u or (p_accion='gestion' and (es_platform_admin() or (identidad='club' and rol_en_club(club_id) in ('admin','propietario')))))
   and created_at>now()-interval '30 days' order by created_at desc limit 300) x),'[]'::jsonb),
   'reportes',case when es_platform_admin() then coalesce((select jsonb_agg(to_jsonb(x)) from
   (select * from aftr_historia_reportes order by created_at desc limit 200) x),'[]'::jsonb) else '[]'::jsonb end,'ahora',now());
 elsif p_accion='publicar' then
  v_identidad:=coalesce(p_datos->>'identidad','usuario'); v_club:=nullif(p_datos->>'club_id','');
  v_evento:=nullif(p_datos->>'evento_id','')::uuid; v_cta:=nullif(p_datos->>'cta','');
  if v_identidad='usuario' then
   perform impl.aftr_yo(); v_club:=null;
  elsif v_identidad in ('club','rrpp') then
   v_rol:=rol_en_club(v_club);
   if (v_identidad='club' and coalesce(v_rol,'') not in ('admin','propietario')) or
      (v_identidad='rrpp' and coalesce(v_rol,'') not in ('rrpp','jefe','admin')) then
    raise exception 'No podés publicar con esa identidad.' using errcode='42501';
   end if;
  else raise exception 'Identidad no válida.'; end if;
  if v_evento is not null and (not impl.aftr_visible(v_evento) or
   (v_club is not null and not exists(select 1 from eventos where id=v_evento and club_id=v_club))) then
   raise exception 'Este evento no está disponible para esta historia.';
  end if;
  if (select count(*) from aftr_historias where autor_id=u and created_at>now()-interval '24 hours')>=30 then
   raise exception 'Podés publicar hasta 30 historias por día.';
  end if;
  -- el cliente manda la ruta que subió; el archivo ya puede estar movido
  select * into m from aftr_media_validada
   where (storage_path=p_datos->>'storage_path' or ruta_subida=p_datos->>'storage_path') and autor_id=u;
  if not found or not exists(select 1 from storage.objects where bucket_id='aftr-historias' and name=m.storage_path) then
   raise exception 'Primero subí y validá el archivo de la historia.';
  end if;
  insert into aftr_historias(autor_id,identidad,club_id,evento_id,cta,storage_path,tipo,duracion_ms)
  values(u,v_identidad,v_club,v_evento,v_cta,m.storage_path,m.tipo,m.duracion_ms) returning * into h;
  return impl.social_historia_json(h);
 elsif p_accion in ('retirar','reportar') then
  v_id:=(p_datos->>'id')::uuid; select * into h from aftr_historias where id=v_id for update;
  if not found then raise exception 'Historia no encontrada.'; end if;
  if p_accion='retirar' then
   if not coalesce(h.autor_id=u or es_platform_admin() or (h.identidad='club' and rol_en_club(h.club_id) in ('admin','propietario')),false) then
    raise exception 'No autorizado.' using errcode='42501'; end if;
   update aftr_historias set retirada_at=coalesce(retirada_at,now()),retirada_por=u where id=h.id;
  else
   if not aftr_historia_visible(h.id) then raise exception 'Esta historia ya no está disponible.'; end if;
   insert into aftr_historia_reportes(historia_id,autor_id,motivo) values(h.id,u,trim(p_datos->>'motivo'))
    on conflict(historia_id,autor_id) do nothing;
  end if;
  return jsonb_build_object('ok',true);
 elsif p_accion='bloquear' then
  v_otro:=(p_datos->>'usuario')::uuid;
  if v_otro is null then raise exception 'Falta el usuario a bloquear.'; end if;
  if v_otro=u then raise exception 'No podés bloquearte a vos mismo.'; end if;
  if coalesce((p_datos->>'on')::boolean,true) then
   insert into aftr_bloqueos(bloqueador_id,bloqueado_id) values(u,v_otro) on conflict do nothing;
  else
   delete from aftr_bloqueos where bloqueador_id=u and bloqueado_id=v_otro;
  end if;
  return jsonb_build_object('ok',true);
 elsif p_accion='bloqueados' then
  return jsonb_build_object('bloqueados',coalesce((select jsonb_agg(jsonb_build_object(
    'id',b.bloqueado_id,'nombre',c.nombre,'foto',c.foto_url,'desde',b.created_at) order by b.created_at desc)
   from aftr_bloqueos b left join aftr_clientes c on c.user_id=b.bloqueado_id
   where b.bloqueador_id=u),'[]'::jsonb));
 end if;
 raise exception 'Acción de historias no válida.';
end $function$;
notify pgrst,'reload schema';
