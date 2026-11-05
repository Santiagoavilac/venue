-- Un freno que las Edge Functions puedan usar.
--
-- `historias-media` descarga hasta 30 MB por llamada para validar un archivo, y
-- `firmar` resuelve hasta 60 claves. Las dos acciones no tienen sesión
-- obligatoria -firmar es justamente para el visitante sin cuenta-, así que sin
-- freno alguien puede tenerlas descargando todo el día.
--
-- El freno ya existe (impl.aftr_limite, de los límites de uso) pero sólo sabe
-- del actor de la sesión actual, y la Edge Function llama con la llave de
-- servicio: ahí dentro no hay sesión, hay una IP. Esta función recibe el actor
-- de afuera, y por eso es sólo para `service_role`: si la pudiera llamar
-- cualquiera, podría gastarle el cupo a otro.
create or replace function public.aftr_limite_externo(p_accion text, p_actor text,
                                                      p_max int, p_ventana_seg int)
returns void language plpgsql security definer set search_path = public as $$
declare v_n int; v_actor text := 'ip:' || left(coalesce(nullif(trim(p_actor), ''), 'sin-ip'), 60);
begin
  if p_accion is null or p_max is null or p_max < 1 or p_ventana_seg is null
     or p_ventana_seg < 1 or p_ventana_seg > 3600 then
    raise exception 'Límite mal pedido.';
  end if;
  select count(*) into v_n from aftr_intentos
   where accion = p_accion and actor = v_actor and at > now() - make_interval(secs => p_ventana_seg);
  if v_n >= p_max then
    raise exception 'Estás yendo muy rápido. Esperá un momento.' using errcode = '53400';
  end if;
  insert into aftr_intentos (actor, accion) values (v_actor, p_accion);
end $$;
revoke all on function public.aftr_limite_externo(text, text, int, int) from public, anon, authenticated;
grant execute on function public.aftr_limite_externo(text, text, int, int) to service_role;
notify pgrst,'reload schema';
