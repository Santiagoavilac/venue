-- Comprar sin cuenta, y cuenta de verdad para todo lo demás.
--
-- Hasta ahora, para comprar una entrada había que entrar con Google o Apple.
-- Eso es pedirle a alguien que abra una cuenta antes de saber si le gusta la
-- fiesta: la mitad se va ahí. Ahora se compra llenando un formulario corto
-- -nombre, apellido, correo, CI, mayor de 18 y términos- y listo.
--
-- Por debajo igual hay una sesión: es anónima. Eso es lo que hace que la
-- entrada sea de alguien, que el QR aparezca en Accesos y que el cobro del
-- banco tenga dueño, sin pedirle una contraseña a nadie. Si después entra con
-- Google o Apple, su cuenta pasa a ser de verdad y conserva todo.
--
-- Lo que SÍ pide cuenta de verdad: PULSE, mesas, historias, reventa y rachas.
-- Son cosas que guardan plata o que se comparten con otra gente, y una sesión
-- anónima se pierde con el teléfono.

-- ── los datos del comprador ───────────────────────────────────────────
alter table public.aftr_clientes
  add column if not exists apellido text,
  add column if not exists email text,
  add column if not exists ci text,
  add column if not exists telefono text,
  add column if not exists acepto_at timestamptz,
  add column if not exists mayor_edad boolean not null default false;

comment on column public.aftr_clientes.acepto_at is
  'Cuando acepto terminos y declaro ser mayor de 18. Se guarda la fecha, no un si suelto.';

-- ── quién es de verdad y quién está de paso ───────────────────────────
create or replace function impl.es_anonimo() returns boolean
language sql stable set search_path = public as $$
  select coalesce((auth.jwt() ->> 'is_anonymous')::boolean, false)
$$;

/* Para lo que no se le puede dar a una sesión que se pierde con el teléfono.
   El mensaje es el que ve la persona: tiene que decirle qué hacer. */
create or replace function impl.aftr_cuenta_real() returns aftr_clientes
language plpgsql stable security definer set search_path = public as $$
declare c aftr_clientes := impl.aftr_yo();
begin
  if impl.es_anonimo() then
    raise exception 'Entrá con Google o Apple para esto. Tus entradas se guardan igual.'
      using errcode = '28000';
  end if;
  return c;
end $$;

-- ── el formulario de compra ───────────────────────────────────────────
-- Crea el perfil de quien compra sin cuenta. El usuario se arma solo a partir
-- del nombre: nunca se le pide elegir uno, que es justo la fricción que se
-- quería sacar.
create or replace function public.aftr_datos_de_compra(
  p_nombre text, p_apellido text, p_email text, p_ci text,
  p_telefono text default null, p_acepta boolean default false)
returns jsonb language plpgsql security definer set search_path = public as $$
declare u uuid := auth.uid(); v_nombre text := trim(coalesce(p_nombre, ''));
        v_apellido text := trim(coalesce(p_apellido, ''));
        v_email text := lower(trim(coalesce(p_email, '')));
        v_ci text := trim(coalesce(p_ci, '')); v_base text; v_usuario text; v_n int := 0;
        c aftr_clientes;
begin
  if u is null then raise exception 'Falta la sesión.' using errcode = '28000'; end if;
  perform impl.aftr_limite('datos_compra', 20, interval '1 hour',
    'Demasiados intentos. Esperá un rato.');
  if length(v_nombre) < 2 then raise exception 'Escribí tu nombre.'; end if;
  if length(v_apellido) < 2 then raise exception 'Escribí tu apellido.'; end if;
  if v_email !~ '^[^@[:space:]]+@[^@[:space:]]+\.[a-z]{2,}$' then
    raise exception 'Revisá tu correo.';
  end if;
  if length(v_ci) < 4 or length(v_ci) > 20 then raise exception 'Revisá tu carnet.'; end if;
  if not p_acepta then
    raise exception 'Para continuar tenés que ser mayor de 18 y aceptar los términos.';
  end if;

  -- un usuario que no choque: ana, ana2, ana3…
  v_base := left(regexp_replace(lower(translate(v_nombre || v_apellido,
    'áéíóúüñÁÉÍÓÚÜÑ', 'aeiouunAEIOUUN')), '[^a-z0-9]', '', 'g'), 20);
  if length(v_base) < 3 then v_base := 'aftr' || v_base; end if;
  v_usuario := v_base;
  while exists (select 1 from aftr_clientes where usuario = v_usuario and user_id <> u) loop
    v_n := v_n + 1;
    v_usuario := left(v_base, 20) || v_n;
  end loop;

  insert into aftr_clientes (user_id, usuario, nombre, apellido, email, ci, telefono,
                             acepto_at, mayor_edad)
  values (u, v_usuario, v_nombre, v_apellido, v_email, v_ci,
          nullif(trim(coalesce(p_telefono, '')), ''), now(), true)
  on conflict (user_id) do update set
    nombre = excluded.nombre, apellido = excluded.apellido, email = excluded.email,
    ci = excluded.ci, telefono = coalesce(excluded.telefono, aftr_clientes.telefono),
    acepto_at = coalesce(aftr_clientes.acepto_at, excluded.acepto_at),
    mayor_edad = true
  returning * into c;
  return to_jsonb(c);
end $$;
revoke all on function public.aftr_datos_de_compra(text, text, text, text, text, boolean) from public, anon;
grant execute on function public.aftr_datos_de_compra(text, text, text, text, text, boolean)
  to authenticated, service_role;

notify pgrst,'reload schema';
-- Lo que pide cuenta de verdad. Se inyecta la línea en el cuerpo vigente de
-- cada función, igual que los límites de uso: copiar quince cuerpos acá es lo
-- que se desincroniza con la próxima migración que los toque.
--
-- Comprar entradas NO está en la lista, a propósito: esa es la que se puede
-- hacer sin cuenta.
do $migra$
declare f record; v_def text; v_pos int;
  fns text[] := array[
    'aftr_recargar_pulse', 'aftr_pagar_pulse', 'aftr_pedir_mesa',     -- PULSE
    'aftr_reservar_mesa', 'aftr_mesa_invitar', 'aftr_mesa_responder', -- mesas
    'aftr_historias',                                                 -- historias
    'aftr_reventa',                                                   -- reventa
    'aftr_rachas', 'aftr_amistad', 'aftr_buscar_usuario',             -- rachas
    'aftr_transferir', 'aftr_anotarme_lista'                          -- pasar y listas
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
-- El feed de historias y el mercado de reventa son públicos: se miran sin
-- cuenta y esa es la puerta de entrada de la app. La línea de "cuenta real"
-- tiene que ir por acción, no arriba de todo, o se cierra lo único que estaba
-- abierto a propósito.
do $migra$
declare v_def text; n text;
begin
  foreach n in array array['aftr_historias', 'aftr_reventa'] loop
    select pg_get_functiondef(p.oid) into v_def
      from pg_proc p join pg_namespace pn on pn.oid = p.pronamespace
     where pn.nspname = 'public' and p.proname = n;
    -- se saca la línea de arriba
    v_def := replace(v_def, chr(10) || '  perform impl.aftr_cuenta_real();' || chr(10), chr(10));
    -- y se pone en el lugar donde ya se exigía sesión, que es por acción
    v_def := replace(v_def,
      ' if p_accion<>''feed'' and u is null then raise exception ''Iniciá sesión.'' using errcode=''28000''; end if;',
      ' if p_accion<>''feed'' then perform impl.aftr_cuenta_real(); end if;');
    v_def := replace(v_def,
      ' if p_accion<>''mercado'' and u is null then raise exception ''Iniciá sesión.'' using errcode=''28000''; end if;',
      ' if p_accion<>''mercado'' then perform impl.aftr_cuenta_real(); end if;');
    execute v_def;
  end loop;
end $migra$;
notify pgrst,'reload schema';
-- Las dos funciones puras que escribí sin search_path fijo. No leen tablas,
-- pero una función sin search_path se resuelve con el del que llama: es la
-- puerta por la que se cuela una función con el mismo nombre en otro esquema.
alter function impl.aftr_orden_misma(aftr_ordenes, integer, uuid) set search_path = public, pg_temp;
alter function impl.reventa_techo(entradas, integer) set search_path = public, pg_temp;
