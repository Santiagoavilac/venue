-- PULSE, mesas, historias, guardados y la foto también piden cuenta de verdad.
--
-- Qué se rompía: ayer, al abrir la compra sin cuenta (20261106240000), puse la
-- línea de "cuenta real" en trece funciones y me faltaron éstas. Probado
-- contra el REST con una sesión anónima de verdad:
--
--   aftr_pulse     → 200 {"saldo_centavos": 0, ...}
--   aftr_mis_mesas → 200 {"mesas": [], "avisos": []}
--
-- No se filtraba nada —son las propias del invitado, y vacías—, pero la regla
-- es que PULSE y mesas son de quien tiene cuenta, y que el servidor es el que
-- la aplica: esconderlo en la app no lo protege, sale igual con la sesión
-- propia. Con esto el cliente puede mostrar una pantalla que diga qué hacer en
-- vez de una billetera en cero que nunca va a poder recargar.
--
-- Lo que NO entra acá, a propósito:
--
--   aftr_comprar, aftr_comprar_historia, aftr_datos_de_compra,
--   aftr_mis_accesos, aftr_mi_perfil, aftr_cancelar_mi_orden
--     son el camino de la compra sin cuenta. Si se cierran, no hay compra sin
--     cuenta.
--
--   aftr_eventos, aftr_evento, aftr_lugares, aftr_lugar, aftr_calor,
--   aftr_media_rutas, aftr_historia_visible, aftr_foto_de_perfil
--     se miran sin ninguna sesión: son la puerta de entrada y lo que firma las
--     fotos del feed. Cerrarlas es lo que ya rompí una vez ayer con el feed.
--
--   aftr_mis_guardados
--     es `language sql` y para el invitado devuelve vacío igual, porque
--     aftr_guardar -el que escribe- sí queda cerrado. Se deja como está en vez
--     de reescribirla a plpgsql sólo para esto.
--
-- Igual que ayer, la línea se inserta en el cuerpo vigente en vez de volver a
-- copiarlo acá: así no quedan dos versiones de cada función que se
-- desincronizan.
do $migra$
declare
  v_def text; v_pos int;
  fns text[] := array[
    'aftr_pulse',                                                     -- PULSE
    'aftr_mis_mesas', 'aftr_carta_mesa', 'aftr_mis_pedidos_mesa',
    'aftr_mesa_retirar',                                              -- mesas
    'aftr_reservar_historia',                                         -- historias
    'aftr_guardar', 'aftr_seguir',                                    -- guardar y seguir
    'aftr_cambiar_foto'                                               -- foto de perfil
  ];
  n text;
begin
  foreach n in array fns loop
    select pg_get_functiondef(p.oid) into v_def
      from pg_proc p join pg_namespace pn on pn.oid = p.pronamespace
     where pn.nspname = 'public' and p.proname = n
       and p.prolang = (select oid from pg_language where lanname = 'plpgsql');
    if v_def is null then raise exception 'No existe public.% en plpgsql', n; end if;
    if position('aftr_cuenta_real' in v_def) > 0 then continue; end if;
    v_pos := regexp_instr(v_def, '\mbegin\M', position('$function$' in v_def) + 10, 1, 1);
    if v_pos = 0 then raise exception 'No encuentro el begin de %', n; end if;
    v_def := left(v_def, v_pos - 1) || chr(10) ||
      '  perform impl.aftr_cuenta_real();' || chr(10) || substr(v_def, v_pos);
    execute v_def;
  end loop;
end $migra$;

notify pgrst,'reload schema';
