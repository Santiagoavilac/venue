-- El enlace del relacionador lleva su nombre, no un código opaco: alguien
-- comparte "?ref=genjiro-sasamoto" mucho más fácil que "?ref=a3f91c2d".
-- El enlace identifica sólo a la persona; el jefe de team y el equipo nunca
-- aparecen en la URL ni se usan para resolverla.
create extension if not exists unaccent;

create or replace function impl.slug_persona(p_texto text)
 returns text language sql immutable as $$
  select nullif(trim(both '-' from
    regexp_replace(
      regexp_replace(lower(unaccent(coalesce(p_texto, ''))), '[^a-z0-9]+', '-', 'g'),
      '-{2,}', '-', 'g')), '')
$$;

create or replace function public.rrpp_mi_ref()
 returns text language plpgsql security definer set search_path to 'public'
as $function$
declare v text; v_base text; v_try text; i int := 1;
begin
  if auth.uid() is null then raise exception 'Iniciá sesión.' using errcode = '28000'; end if;
  select ref_code into v from profiles where id = auth.uid();
  if v is not null then return v; end if;
  select coalesce(impl.slug_persona(nombre), impl.slug_persona(usuario))
    into v_base from profiles where id = auth.uid();
  -- sin nombre utilizable se cae al código aleatorio de antes
  if v_base is null then
    loop
      v_base := lower(substr(replace(gen_random_uuid()::text, '-', ''), 1, 8));
      exit when not exists (select 1 from profiles where ref_code = v_base);
    end loop;
    update profiles set ref_code = v_base where id = auth.uid();
    return v_base;
  end if;
  v_try := v_base;
  while exists (select 1 from profiles where ref_code = v_try) loop
    i := i + 1; v_try := v_base || '-' || i;
  end loop;
  update profiles set ref_code = v_try where id = auth.uid();
  return v_try;
end;
$function$;

-- Los relacionadores y jefes que ya existen reciben su enlace ahora, para que
-- no dependa de que cada uno abra la pantalla por primera vez.
do $$
declare r record; v_base text; v_try text; i int;
begin
  for r in select id, nombre, usuario from profiles
            where rol in ('rrpp','jefe') and activo and ref_code is null
            order by created_at loop
    v_base := coalesce(impl.slug_persona(r.nombre), impl.slug_persona(r.usuario));
    if v_base is null then continue; end if;
    v_try := v_base; i := 1;
    while exists (select 1 from profiles where ref_code = v_try) loop
      i := i + 1; v_try := v_base || '-' || i;
    end loop;
    update profiles set ref_code = v_try where id = r.id;
  end loop;
end $$;
