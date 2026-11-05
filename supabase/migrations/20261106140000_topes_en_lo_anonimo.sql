-- Topes en las tres RPC por las que se tira abajo la base con un curl.
--
-- `aftr_eventos`, `aftr_historias` y `aftr_calor` se pueden llamar sin sesión:
-- son las que ve alguien que entra a mirar. Ninguna tenía techo.
--
-- * `aftr_eventos` acepta cualquier rango. Con `p_desde=1900-01-01` recorre la
--   tabla entera y serializa una tarjeta por evento, cada una con su boliche,
--   sus fases y su cupo. Un pedido, mucho trabajo.
-- * el feed de historias serializa hasta 300 historias de una, cada una con su
--   tarjeta de evento. Y `publicar` no valida el tamaño de `p_datos`, aunque su
--   hermana `aftr_reventa` sí lo hace: se puede mandar un jsonb gigante.
-- * `aftr_calor` cuenta, en cada llamada, las entradas vigentes del próximo
--   evento de CADA boliche. Es el mapa: se pide al abrir la app y en cada
--   movimiento de cámara. El dato cambia cada varios minutos, así que
--   recalcularlo por pedido es trabajo tirado.
--
-- Nada de esto cambia lo que ve la gente: 120 historias son más de las que
-- nadie mira, el rango de 90 días cubre lo que la app muestra, y el calor se
-- refresca cada dos minutos.

-- ── 1 · eventos: rango acotado y techo ────────────────────────────────
create or replace function public.aftr_eventos(p_desde date default null, p_hasta date default null,
                                               p_ciudad text default null)
returns jsonb language sql stable security definer set search_path to 'public'
as $function$
  with v as (
    select greatest(coalesce(p_desde, (now() at time zone 'America/La_Paz')::date - 1),
                    (now() at time zone 'America/La_Paz')::date - 31) as desde
  ), r as (
    -- 90 días desde el inicio, nunca más: es lo que la app muestra
    select v.desde, least(coalesce(p_hasta, v.desde + 60), v.desde + 90) as hasta from v
  )
  select coalesce(jsonb_agg(t.tarjeta order by t.fecha, t.hora_inicio), '[]'::jsonb)
    from (select impl.aftr_tarjeta(e.id) as tarjeta, e.fecha, e.hora_inicio
            from eventos e join clubs c on c.id = e.club_id, r
           where impl.aftr_visible(e.id)
             and e.fecha >= r.desde and e.fecha <= r.hasta
             and (p_ciudad is null or c.ciudad ilike p_ciudad)
           order by e.fecha, e.hora_inicio
           limit 300) t
$function$;

-- ── 2 · el calor del mapa sale de una caché ───────────────────────────
create table if not exists public.aftr_calor_cache (
  club_id     text primary key references public.clubs(id) on delete cascade,
  intensidad  numeric not null,
  at          timestamptz not null default now()
);
alter table public.aftr_calor_cache enable row level security;  -- se lee por la RPC
comment on table public.aftr_calor_cache is
  'Lo que devuelve aftr_calor. La refresca el cron: contarlo por pedido era trabajo tirado.';

create or replace function impl.aftr_calor_refrescar() returns void
language plpgsql security definer set search_path = public as $$
begin
  with prox as (
    select distinct on (e.club_id) e.club_id, e.id
      from eventos e join clubs c on c.id = e.club_id
     where c.activo and c.aftr_visible and c.lat is not null and c.lng is not null
       and e.aftr_publico and e.estado <> 'cerrado' and e.fecha >= current_date
     order by e.club_id, e.fecha, e.hora_inicio nulls last
  ), ventas as (
    select p.club_id,
           (select count(*) from impl.entradas_vigentes x
             where x.evento_id = p.id and x.estado <> 'anulada' and x.mesa_id is null) as n
      from prox p
  ), calculado as (
    select v.club_id, round(v.n::numeric / nullif(max(v.n) over (), 0), 3) as intensidad
      from ventas v where v.n > 0
  )
  merge into aftr_calor_cache d
  using calculado c on d.club_id = c.club_id
  when matched then update set intensidad = c.intensidad, at = now()
  when not matched then insert (club_id, intensidad) values (c.club_id, c.intensidad);
  -- el boliche que dejó de vender sale del mapa
  delete from aftr_calor_cache where at < now() - interval '10 minutes';
end $$;

create or replace function public.aftr_calor()
returns table(club_id text, intensidad numeric)
language sql stable security definer set search_path to 'public'
as $function$
  select k.club_id, k.intensidad from aftr_calor_cache k
    join clubs c on c.id = k.club_id
   where c.activo and c.aftr_visible
$function$;

select cron.schedule('aftr-calor', '*/2 * * * *', $$select impl.aftr_calor_refrescar();$$)
 where not exists (select 1 from cron.job where jobname = 'aftr-calor');
-- para que el mapa no quede vacío hasta el primer minuto par
select impl.aftr_calor_refrescar();

-- ── 3 · historias: tamaño de la entrada y techo del feed ──────────────
-- El feed baja a 120 y acepta un cursor: `antes` es el created_at de la última
-- que ya se mostró. Las apps publicadas no lo mandan y reciben las 120 más
-- nuevas, que es más de lo que nadie mira.
create or replace function public.aftr_historias(p_accion text, p_datos jsonb default '{}'::jsonb)
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp'
as $function$
declare u uuid:=auth.uid(); h aftr_historias; m aftr_media_validada; v_identidad text; v_club text;
 v_evento uuid; v_id uuid; v_cta text; r jsonb; v_rol text; v_otro uuid; v_antes timestamptz;
begin
 -- mismo guard que aftr_reventa: un jsonb gigante no llega a la lógica
 if p_datos is null or jsonb_typeof(p_datos)<>'object' or octet_length(p_datos::text)>16000 then
  raise exception 'Datos no válidos.';
 end if;
 if p_accion='feed' then
  v_antes:=nullif(p_datos->>'antes','')::timestamptz;
  return jsonb_build_object('historias',coalesce((select jsonb_agg(impl.social_historia_json(x) order by x.created_at)
   from (select * from aftr_historias hi where aftr_historia_visible(hi.id)
          and (v_antes is null or hi.created_at < v_antes)
          and not exists (select 1 from aftr_bloqueos b
                           where b.bloqueador_id=u and b.bloqueado_id=hi.autor_id)
         order by hi.created_at desc limit 120) x),'[]'::jsonb),'ahora',now());
 end if;
 if u is null then raise exception 'Iniciá sesión.' using errcode='28000'; end if;
 if p_accion in ('mias','gestion') then
  return jsonb_build_object('historias',coalesce((select jsonb_agg(impl.social_historia_json(x) order by x.created_at desc)
   from (select * from aftr_historias where (p_datos->>'club_id' is null or club_id=p_datos->>'club_id') and
   (autor_id=u or (p_accion='gestion' and (es_platform_admin() or (identidad='club' and rol_en_club(club_id) in ('admin','propietario')))))
   and created_at>now()-interval '30 days' order by created_at desc limit 120) x),'[]'::jsonb),
   'reportes',case when es_platform_admin() then coalesce((select jsonb_agg(to_jsonb(x)) from
   (select * from aftr_historia_reportes order by created_at desc limit 200) x),'[]'::jsonb) else '[]'::jsonb end,'ahora',now());
 elsif p_accion='publicar' then
  perform impl.aftr_limite('publicar_historia', 10, interval '10 minutes',
    'Publicaste muchas historias seguidas. Esperá unos minutos.');
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
   perform impl.aftr_limite('reportar', 20, interval '1 hour', 'Muchos reportes seguidos. Esperá un rato.');
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
