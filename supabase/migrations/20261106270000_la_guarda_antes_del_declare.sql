-- La guarda tiene que correr antes que el declare, no después.
--
-- Qué se rompía: en `aftr_reservar_historia` la guarda de cuenta quedó dentro
-- del cuerpo, pero el `declare` llamaba a `impl.historia_atribucion(...)`, y
-- el declare se ejecuta ANTES del primer `begin`. Resultado, probado con una
-- sesión anónima contra el REST:
--
--   aftr_reservar_historia → 400 'La historia ya no está disponible.'
--
-- en vez de pedirle cuenta. No es grave -lo único que se aprende es si un id
-- de historia existe-, pero es la guarda que no se ejecuta: hoy filtra eso y
-- mañana, cuando alguien agregue otra llamada al declare, filtra lo que esa
-- llamada diga.
--
-- Pasa sólo acá. Revisadas las 22 funciones que tienen la guarda, el resto
-- declara `impl.aftr_yo()`, `auth.uid()` o un `lower(trim(...))`: nada que
-- hable ni que decida. Ésta era la única con una llamada que levanta su propio
-- error.
--
-- La forma de arreglarlo es dejar el declare sin nada que se ejecute y mover
-- la llamada al cuerpo, después de la guarda.
create or replace function public.aftr_reservar_historia(
  p_historia uuid, p_evento uuid, p_mesa uuid,
  p_combo uuid default null, p_client_key uuid default null
) returns jsonb
language plpgsql security definer set search_path to 'public', 'pg_temp'
as $function$
declare h aftr_historias; r jsonb;
begin
  perform impl.aftr_cuenta_real();

  h := impl.historia_atribucion(p_historia, 'mesa');
  if h.evento_id is distinct from p_evento then raise exception 'La historia no pertenece a este evento.'; end if;
  r := aftr_reservar_mesa(h.evento_id, p_mesa, p_combo, p_client_key);
  update aftr_ordenes set historia_id = h.id,
         referido_rrpp_id = case when h.identidad = 'rrpp' then h.autor_id end
   where id = (r ->> 'id')::uuid;
  update mesas set vendido_por = case when h.identidad = 'rrpp' then h.autor_id end where id = p_mesa;
  return r;
end $function$;

notify pgrst,'reload schema';
