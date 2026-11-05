-- Acciones de bloqueo en aftr_historias y feed que respeta la lista.
--
-- 'bloquear' con {usuario, on} agrega o saca a alguien de la lista personal;
-- 'bloqueados' la devuelve para la pantalla de Ajustes. El feed deja de
-- mostrar historias de los autores bloqueados. Nada de esto es visible para
-- el bloqueado ni cambia lo que ven los demás.
CREATE OR REPLACE FUNCTION public.aftr_historias(p_accion text, p_datos jsonb DEFAULT '{}'::jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
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
  select * into m from aftr_media_validada where storage_path=p_datos->>'storage_path' and autor_id=u;
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
  -- bloquear es personal y silencioso: el otro no se entera
  v_otro:=(p_datos->>'usuario')::uuid;
  if v_otro is null then raise exception 'Falta el usuario a bloquear.'; end if;
  if v_otro=u then raise exception 'No podés bloquearte a vos mismo.'; end if;
  if coalesce((p_datos->>'on')::boolean,true) then
   insert into aftr_bloqueos(bloqueador_id,bloqueado_id) values(u,v_otro)
    on conflict do nothing;
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
end $function$
;
