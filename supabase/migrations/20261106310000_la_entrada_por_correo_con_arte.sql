-- Lo que lleva el correo de la entrada, en una función propia.
--
-- Qué se rompía: lo que va en el correo estaba escrito dentro del cuerpo de
-- `impl.aftr_emitir_orden`, inyectado. Cada vez que hace falta un dato más
-- -el apellido, el arte del evento- habría que volver a inyectar en una
-- función que además emite entradas, que es lo último que conviene tocar por
-- un cambio de diseño.
--
-- Acá el armado vive en `impl.correo_de_orden` y la emisión sólo la llama.
-- Sumar un dato al correo pasa a ser cambiar esta función y nada más.
create or replace function impl.correo_de_orden(p_orden uuid)
returns void language plpgsql security definer set search_path = public, pg_temp
as $$
declare o aftr_ordenes; c aftr_clientes; e eventos; v_club text;
begin
  select * into o from aftr_ordenes where id = p_orden;
  if not found then return; end if;
  select * into c from aftr_clientes where user_id = o.cliente_id;
  select * into e from eventos where id = o.evento_id;
  select cl.nombre into v_club from clubs cl where cl.id = e.club_id;

  perform impl.correo_encolar('entradas', impl.correo_de(o.cliente_id), jsonb_build_object(
    'nombre', c.nombre,
    'apellido', c.apellido,
    'orden', o.id,
    'evento', e.nombre,
    'club', v_club,
    'fecha', to_char(e.fecha, 'DD/MM/YYYY'),
    'hora', to_char(e.hora_inicio, 'HH24:MI'),
    'tipo', o.tipo,
    -- el arte del evento, que es el fondo de la entrada en el PDF
    'arte', e.flyer_url,
    -- los códigos recién emitidos de esta orden; el QR se arma al mandar
    'codigos', (select coalesce(jsonb_agg(x.code order by x.created_at), '[]'::jsonb)
                  from entradas x
                 where x.cliente_id = o.cliente_id and x.evento_id = o.evento_id
                   and x.estado = 'valida' and x.created_at >= now() - interval '5 seconds')));
end $$;

-- y la emisión pasa a llamarla, en vez de armar el correo adentro
do $migra$
declare v_def text; v_ini int; v_fin int;
begin
  select pg_get_functiondef(p.oid) into v_def
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'impl' and p.proname = 'aftr_emitir_orden';
  if v_def is null then raise exception 'No existe impl.aftr_emitir_orden'; end if;
  if position('correo_de_orden' in v_def) > 0 then return; end if;
  v_ini := position('  -- La copia que no depende del teléfono' in v_def);
  if v_ini = 0 then raise exception 'No encuentro el bloque del correo en aftr_emitir_orden'; end if;
  v_fin := position('  return v_n;' in v_def);
  if v_fin = 0 or v_fin < v_ini then raise exception 'No encuentro el final del bloque del correo'; end if;
  v_def := left(v_def, v_ini - 1)
    || '  -- La copia que no depende del teléfono: qué lleva lo decide' || chr(10)
    || '  -- impl.correo_de_orden, para no tocar la emisión por un cambio de correo.' || chr(10)
    || '  perform impl.correo_de_orden(o.id);' || chr(10) || chr(10)
    || substr(v_def, v_fin);
  execute v_def;
end $migra$;

notify pgrst,'reload schema';
