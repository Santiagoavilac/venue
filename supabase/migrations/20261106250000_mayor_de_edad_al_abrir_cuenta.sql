-- Los 18+ y los términos, también al abrir cuenta normal.
--
-- Qué se rompía: `aftr_datos_de_compra` (20261106240000) guarda `mayor_edad` y
-- `acepto_at` de quien compra sin cuenta, pero quien abre cuenta con Google o
-- Apple pasaba por `aftr_crear_perfil`, que no pide nada ni guarda nada. O sea:
-- la mitad de la gente quedaba sin constancia de haber aceptado ni de ser mayor
-- de edad, justo la mitad que además usa PULSE, mesas y reventa.
--
-- Acá `aftr_crear_perfil` recibe `p_acepta`. No es obligatorio, a propósito:
-- hay apps publicadas que llaman a esta función con dos argumentos y si se
-- exigiera, nadie con la app vieja podría abrir cuenta. Cuando llega en `true`
-- se guarda; cuando no llega, el perfil queda como queda hoy y la próxima vez
-- que la persona pase por una pantalla que lo pida se completa.
--
-- El parámetro nuevo lleva `default`, así que las llamadas de dos argumentos
-- siguen entrando. Y se borra la firma de dos para que no queden dos funciones:
-- con las dos vivas, una llamada por nombre es ambigua y PostgREST contesta 300
-- -el error que ya nos comimos tres veces esta semana-.
create or replace function public.aftr_crear_perfil(
  p_usuario text,
  p_nombre text,
  p_acepta boolean default false
) returns jsonb
language plpgsql security definer set search_path to 'public'
as $function$
declare v_usuario text := lower(trim(p_usuario)); c aftr_clientes;
begin
  perform impl.aftr_limite('crear_perfil', 5, interval '1 hour', 'Demasiados intentos. Esperá un rato.');

  if auth.uid() is null then
    raise exception 'Iniciá sesión.' using errcode = '28000';
  end if;
  if v_usuario !~ '^[a-z0-9_.]{3,24}$' then
    raise exception 'El usuario lleva de 3 a 24 letras, números, punto o guion bajo.';
  end if;
  if exists (select 1 from aftr_clientes where usuario = v_usuario and user_id <> auth.uid()) then
    raise exception 'Ese usuario ya está tomado.' using errcode = '23505';
  end if;
  insert into aftr_clientes (user_id, usuario, nombre, mayor_edad, acepto_at)
  values (auth.uid(), v_usuario, trim(p_nombre),
          coalesce(p_acepta, false),
          case when p_acepta then now() end)
  on conflict (user_id) do update set
    usuario = excluded.usuario,
    nombre = excluded.nombre,
    -- lo aceptado no se desacepta: una app vieja que manda `false` no borra
    -- la constancia de alguien que ya aceptó
    mayor_edad = aftr_clientes.mayor_edad or excluded.mayor_edad,
    acepto_at = coalesce(aftr_clientes.acepto_at, excluded.acepto_at)
  returning * into c;
  return to_jsonb(c);
end;
$function$;

drop function if exists public.aftr_crear_perfil(text, text);

revoke all on function public.aftr_crear_perfil(text, text, boolean) from public, anon;
grant execute on function public.aftr_crear_perfil(text, text, boolean) to authenticated;

notify pgrst,'reload schema';
