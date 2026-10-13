-- RPCs de CHECK-IN · el módulo de puerta: validar QR, marcar/desmarcar
-- ingresos, filtro de puerta y generación de QR de lista.
--
-- ETAPA 1: paridad. Nada de mejoras acá.
--
-- REGLA DURA: ninguna de estas funciones se ejecutó jamás contra el origen
-- (son de escritura). La reconstrucción sale de TRES fuentes de evidencia:
--
-- 1. INVARIANTES de los datos reales (verificados el 2026-08-20 sobre las
--    3.285 entradas y 5.049 registros del origen, cero excepciones):
--      estado='usada'  <=> used_at y portero_id seteados
--      estado='valida' <=> used_at y portero_id en NULL
--        (o sea: descheckin_entrada LIMPIA used_at y portero_id)
--      ingreso_at <=> ingreso_por   (descheckin_registro limpia ambos)
--      filtro_at  <=> filtro_por    (des-marcar filtro limpia ambos)
--      codes: SIEMPRE 6 caracteres [0-9A-F], únicos por evento (2 duplicados
--      entre eventos distintos en 3.285 = colisiones esperables de un
--      generador aleatorio; dentro de un evento, cero).
--
-- 2. TOPE HORARIO, verificado contra los ingresos reales:
--      - eventos.entrada_hasta (QR de manillas): 0 ingresos posteriores en
--        los 3 eventos que lo configuraron.
--      - lista_tipos.ingreso_hasta: 0 ingresos posteriores en los 6 eventos
--        desde el 23/07 (los tardíos de Freaky/Like a Diamond son de antes
--        de que el tope existiera/aplicara), CON UNA EXCEPCIÓN EXACTA: los
--        3 tardíos de HOLIDAY son invitados de jmenacho (ingreso_sin_tope),
--        escaneados por un portero => el bypass es POR EL RRPP del registro,
--        y el que aplica el tope es el camino del scanner.
--      - la regla del día siguiente sale del hint de la app ("una hora
--        anterior al inicio se toma como la madrugada siguiente") y calza
--        con los datos: limite = fecha + ingreso_hasta (+1 día si la hora
--        es <= hora_inicio), en hora de Bolivia (America/La_Paz).
--
-- 3. Los SITIOS DE LLAMADA en app.js (campos que el cliente lee de cada
--    respuesta y qué actualiza localmente tras cada llamada).
--
-- SUPUESTOS no verificables (documentados en cada función): el valor exacto
-- de `resultado` cuando un código no existe (el cliente solo distingue
-- que NO sea valida/usada/anulada/fuera_hora), si checkin_registro aplica
-- el tope igual que el scanner (el hint de la app dice que sí: "el QR y el
-- check-in de esta lista se rechazan en puerta"), el texto de `limite`, y
-- si `team` en las respuestas es el base o el efectivo (se usa el base,
-- igual que reporte_filtro, único caso medido).


/* ---------- generador de código: 6 hex mayúsculas, único por evento ----- */
create or replace function gen_code_evento(p_evento uuid)
returns text
language plpgsql
volatile
as $$
declare c text;
begin
  loop
    c := upper(substr(md5(random()::text || clock_timestamp()::text), 1, 6));
    exit when not exists (select 1 from entradas  where evento_id = p_evento and code = c)
          and not exists (select 1 from registros r join lista_tipos lt on lt.id = r.lista_tipo_id
                           where lt.evento_id = p_evento and r.code = c);
  end loop;
  return c;
end;
$$;

/* ---------- límite de ingreso de una lista (timestamptz) ----------------
 * fecha del evento + ingreso_hasta, +1 día si la hora es <= hora_inicio,
 * interpretado en hora de Bolivia. NULL si la lista no tiene tope. */
create or replace function lista_limite_ingreso(p_lista uuid)
returns timestamptz
language sql
stable
as $$
  select case when lt.ingreso_hasta is null then null
              else ((e.fecha + lt.ingreso_hasta)
                    + case when lt.ingreso_hasta <= e.hora_inicio then interval '1 day' else interval '0' end)
                   at time zone 'America/La_Paz'
         end
    from lista_tipos lt join eventos e on e.id = lt.evento_id
   where lt.id = p_lista;
$$;


/* validar_entrada(p_evento, p_code) -> json
 *
 * El scanner de manillas. Consume la entrada (estado='usada', used_at=now(),
 * portero_id=auth.uid() — los tres, por el invariante 1).
 *
 * Respuestas (campos = exactamente los que lee validar()/data-tk-e en app.js):
 *   valida:     {resultado, cliente, code, rrpp, team, mesa, sin_tope}
 *               mesa = etiqueta de la mesa si es manilla de mesa, si no null
 *   usada:      {resultado, cliente, code, used_at, rrpp, team, mesa}
 *               used_at = el ingreso ANTERIOR (el dato que corta la discusión)
 *   anulada:    {resultado, cliente, code}
 *   fuera_hora: {resultado, cliente, code}   (entrada_hasta vencido; los
 *               vendedores de ingreso_sin_tope del club NO tienen tope)
 *   no existe (o es de otro evento): {resultado: 'no_existe'} — SUPUESTO:
 *               el cliente solo exige que no sea ninguno de los otros y que
 *               el objeto no sea null (r.resultado se lee sin optional
 *               chaining en app.js:2886).
 * Orden de precedencia: no existe > anulada > usada > fuera_hora > valida.
 */
create or replace function validar_entrada(p_evento uuid, p_code text)
returns json
language plpgsql
volatile
security definer
set search_path = public
as $$
declare
  e entradas%rowtype;
  v_club text;
  v_rrpp text; v_team text; v_mesa text;
  v_sin_tope boolean;
  v_tope timestamptz;
begin
  select * into e from entradas
   where evento_id = p_evento and code = upper(p_code);
  if not found then
    return json_build_object('resultado', 'no_existe');
  end if;

  select club_id, entrada_hasta into v_club, v_tope from eventos where id = p_evento;
  select p.nombre, t.nombre into v_rrpp, v_team
    from profiles p left join teams t on t.id = p.team_id
   where p.id = e.rrpp_id;
  select m.etiqueta into v_mesa from mesas m where m.id = e.mesa_id;
  v_sin_tope := exists (select 1 from ingreso_sin_tope st
                         where st.user_id = e.rrpp_id and st.club_id = v_club);

  if e.estado = 'anulada' then
    return json_build_object('resultado', 'anulada', 'cliente', e.cliente, 'code', e.code);
  end if;
  if e.estado = 'usada' then
    return json_build_object('resultado', 'usada', 'cliente', e.cliente, 'code', e.code,
                             'used_at', e.used_at, 'rrpp', v_rrpp, 'team', v_team, 'mesa', v_mesa);
  end if;
  if v_tope is not null and now() > v_tope and not v_sin_tope then
    return json_build_object('resultado', 'fuera_hora', 'cliente', e.cliente, 'code', e.code);
  end if;

  -- consumo CONDICIONAL: si dos porteros escanean el mismo code a la vez,
  -- solo uno gana; el otro recibe 'usada' con los datos frescos (una
  -- entrada entra UNA vez — endurecimiento, no cambia la regla)
  update entradas set estado = 'usada', used_at = now(), portero_id = auth.uid()
   where id = e.id and estado = 'valida';
  if not found then
    select ent.* into e from entradas ent where ent.id = e.id;
    return json_build_object('resultado', 'usada', 'cliente', e.cliente, 'code', e.code,
                             'used_at', e.used_at, 'rrpp', v_rrpp, 'team', v_team, 'mesa', v_mesa);
  end if;
  return json_build_object('resultado', 'valida', 'cliente', e.cliente, 'code', e.code,
                           'rrpp', v_rrpp, 'team', v_team, 'mesa', v_mesa,
                           'sin_tope', v_sin_tope);
end;
$$;


/* validar_qr_lista(p_evento, p_code) -> json
 *
 * El scanner de QRs de lista (payload LST:). Marca el ingreso del registro
 * (ingreso_at=now(), ingreso_por=auth.uid() — invariante 1).
 *
 * Respuestas (campos que lee validar() en app.js, rama esLista):
 *   valida:  {resultado, cliente, code, lista: true, lista_nombre, rrpp,
 *             team, sin_tope}
 *   usada:   {resultado, cliente, code, used_at (=ingreso anterior),
 *             lista_nombre, rrpp, team}
 *   fuera_horario: {resultado, cliente, code, lista_nombre, limite}
 *             limite = la hora tope como texto HH24:MI (la UI lo muestra
 *             como "Entraba hasta {limite}") — FORMATO SUPUESTO.
 *   no existe / otro evento: {resultado: 'no_existe'} (mismo supuesto).
 * Tope: lista_limite_ingreso, con bypass si el rrpp que anotó está en
 * ingreso_sin_tope del club (verificado con los 3 tardíos de HOLIDAY).
 */
create or replace function validar_qr_lista(p_evento uuid, p_code text)
returns json
language plpgsql
volatile
security definer
set search_path = public
as $$
declare
  r registros%rowtype;
  v_club text; v_lista text; v_rrpp text; v_team text;
  v_sin_tope boolean; v_limite timestamptz; v_hasta time;
begin
  select r2.* into r
    from registros r2
    join lista_tipos lt on lt.id = r2.lista_tipo_id
   where r2.evento_id = p_evento and r2.code = upper(p_code);
  if not found then
    return json_build_object('resultado', 'no_existe');
  end if;

  select e.club_id into v_club from eventos e where e.id = p_evento;
  select lt.nombre, lt.ingreso_hasta into v_lista, v_hasta from lista_tipos lt where lt.id = r.lista_tipo_id;
  select p.nombre, t.nombre into v_rrpp, v_team
    from profiles p left join teams t on t.id = p.team_id
   where p.id = r.rrpp_id;
  v_sin_tope := exists (select 1 from ingreso_sin_tope st
                         where st.user_id = r.rrpp_id and st.club_id = v_club);

  if r.ingreso_at is not null then
    return json_build_object('resultado', 'usada', 'cliente', r.nombre, 'code', r.code,
                             'used_at', r.ingreso_at, 'lista_nombre', v_lista,
                             'rrpp', v_rrpp, 'team', v_team);
  end if;

  v_limite := lista_limite_ingreso(r.lista_tipo_id);
  if v_limite is not null and now() > v_limite and not v_sin_tope then
    return json_build_object('resultado', 'fuera_horario', 'cliente', r.nombre, 'code', r.code,
                             'lista_nombre', v_lista, 'limite', to_char(v_hasta, 'HH24:MI'));
  end if;

  -- consumo condicional (carrera de dos escáneres: ver validar_entrada)
  update registros set ingreso_at = now(), ingreso_por = auth.uid()
   where id = r.id and ingreso_at is null;
  if not found then
    select reg.* into r from registros reg where reg.id = r.id;
    return json_build_object('resultado', 'usada', 'cliente', r.nombre, 'code', r.code,
                             'used_at', r.ingreso_at, 'lista_nombre', v_lista,
                             'rrpp', v_rrpp, 'team', v_team);
  end if;
  return json_build_object('resultado', 'valida', 'cliente', r.nombre, 'code', r.code,
                           'lista', true, 'lista_nombre', v_lista,
                           'rrpp', v_rrpp, 'team', v_team, 'sin_tope', v_sin_tope);
end;
$$;


/* checkin_registro(p_registro) -> json
 *
 * El tick manual (cebox del admin en Listas, y la fila de "Lista en puerta").
 * Respuesta que lee el cliente: {resultado, nombre, hora}; con resultado
 * distinto de 'ok' muestra "Ya había ingresado" y usa `hora` para pintar.
 *
 * Aplica el MISMO tope de lista que el scanner, con el mismo bypass — el
 * hint de la app lo promete para los dos caminos ("el QR y el check-in de
 * esta lista se rechazan en puerta"); no hay ingreso manual tardío en los
 * datos que lo contradiga. SUPUESTO PARCIAL: si el original no lo aplicara,
 * el cliente mostraría "Ya había ingresado" para un rechazo por hora — no
 * distinguible sin ejecutar el original.
 */
create or replace function checkin_registro(p_registro uuid)
returns json
language plpgsql
volatile
security definer
set search_path = public
as $$
declare
  r registros%rowtype;
  v_club text; v_sin_tope boolean; v_limite timestamptz;
begin
  select * into r from registros where id = p_registro;
  if not found then
    return json_build_object('resultado', 'no_existe');
  end if;
  if r.ingreso_at is not null then
    return json_build_object('resultado', 'ya', 'nombre', r.nombre, 'hora', r.ingreso_at);
  end if;

  select e.club_id into v_club from eventos e where e.id = r.evento_id;
  v_sin_tope := exists (select 1 from ingreso_sin_tope st
                         where st.user_id = r.rrpp_id and st.club_id = v_club);
  v_limite := lista_limite_ingreso(r.lista_tipo_id);
  if v_limite is not null and now() > v_limite and not v_sin_tope then
    return json_build_object('resultado', 'fuera_horario', 'nombre', r.nombre);
  end if;

  -- doble toque simultáneo: el segundo cae en 'ya', igual que el chequeo de arriba
  update registros set ingreso_at = now(), ingreso_por = auth.uid()
   where id = p_registro and ingreso_at is null;
  if not found then
    select reg.* into r from registros reg where reg.id = p_registro;
    return json_build_object('resultado', 'ya', 'nombre', r.nombre, 'hora', r.ingreso_at);
  end if;
  return json_build_object('resultado', 'ok', 'nombre', r.nombre, 'hora', now());
end;
$$;


/* descheckin_registro(p_registro) -> void
 * Desmarca un ingreso de lista. Limpia ingreso_at E ingreso_por (invariante:
 * no existe ninguna fila con uno solo de los dos). El cliente ignora la
 * respuesta. */
create or replace function descheckin_registro(p_registro uuid)
returns void
language sql
volatile
security definer
set search_path = public
as $$
  update registros set ingreso_at = null, ingreso_por = null where id = p_registro;
$$;


/* descheckin_entrada(p_evento, p_code) -> json {cliente}
 * Desmarca el ingreso de una manilla: estado vuelve a 'valida' y se limpian
 * used_at y portero_id (invariante: ninguna 'valida' los tiene). El cliente
 * lee data?.cliente para el toast. */
create or replace function descheckin_entrada(p_evento uuid, p_code text)
returns json
language plpgsql
volatile
security definer
set search_path = public
as $$
declare e entradas%rowtype;
begin
  select * into e from entradas where evento_id = p_evento and code = upper(p_code);
  if not found then return null; end if;
  update entradas set estado = 'valida', used_at = null, portero_id = null where id = e.id;
  return json_build_object('cliente', e.cliente);
end;
$$;


/* marcar_filtro_entrada(p_evento, p_code) -> json
 *
 * Toggle de la marca "no pasó el control" sobre una manilla. Protegida si
 * el VENDEDOR está en ingreso_sin_tope del club (el scanner en modo filtro
 * la deja pasar derecho cuando recibe 'protegida' — app.js:2857-2869).
 *   ok:        {resultado:'ok', marcado, nombre, rrpp}
 *   protegida: {resultado:'protegida'}
 *   no existe: {resultado:'no_existe'} (el cliente solo chequea != 'ok')
 * marcado=true setea filtro_at=now() y filtro_por; false limpia ambos
 * (invariante: filtro_at <=> filtro_por). */
create or replace function marcar_filtro_entrada(p_evento uuid, p_code text)
returns json
language plpgsql
volatile
security definer
set search_path = public
as $$
declare
  e entradas%rowtype; v_club text; v_rrpp text; v_marcar boolean;
begin
  select * into e from entradas where evento_id = p_evento and code = upper(p_code);
  if not found then return json_build_object('resultado', 'no_existe'); end if;
  select club_id into v_club from eventos where id = p_evento;
  if exists (select 1 from ingreso_sin_tope st where st.user_id = e.rrpp_id and st.club_id = v_club) then
    return json_build_object('resultado', 'protegida');
  end if;
  select p.nombre into v_rrpp from profiles p where p.id = e.rrpp_id;
  v_marcar := e.filtro_at is null;
  update entradas
     set filtro_at  = case when v_marcar then now() end,
         filtro_por = case when v_marcar then auth.uid() end
   where id = e.id;
  return json_build_object('resultado', 'ok', 'marcado', v_marcar, 'nombre', e.cliente, 'rrpp', v_rrpp);
end;
$$;


/* marcar_filtro_registro(p_registro) -> json {marcado, nombre, rrpp}
 * Igual que el de entradas pero por id de registro (fila de Lista en
 * puerta). La UI ni siquiera muestra el botón para los protegidos, pero la
 * protección se replica en el server por consistencia con el resto del
 * módulo — SUPUESTO (inalcanzable desde la UI). */
create or replace function marcar_filtro_registro(p_registro uuid)
returns json
language plpgsql
volatile
security definer
set search_path = public
as $$
declare
  r registros%rowtype; v_club text; v_rrpp text; v_marcar boolean;
begin
  select * into r from registros where id = p_registro;
  if not found then return json_build_object('resultado', 'no_existe'); end if;
  select e.club_id into v_club from eventos e where e.id = r.evento_id;
  if exists (select 1 from ingreso_sin_tope st where st.user_id = r.rrpp_id and st.club_id = v_club) then
    return json_build_object('resultado', 'protegida');
  end if;
  select p.nombre into v_rrpp from profiles p where p.id = r.rrpp_id;
  v_marcar := r.filtro_at is null;
  update registros
     set filtro_at  = case when v_marcar then now() end,
         filtro_por = case when v_marcar then auth.uid() end
   where id = r.id;
  return json_build_object('resultado', 'ok', 'marcado', v_marcar, 'nombre', r.nombre, 'rrpp', v_rrpp);
end;
$$;


/* marcar_filtro_lista(p_evento, p_code) -> json
 * El camino del scanner en modo filtro para QRs de lista: busca el registro
 * por code. 'protegida' es lo único que el cliente chequea (los invitados
 * de la casa siguen derecho a validarse). */
create or replace function marcar_filtro_lista(p_evento uuid, p_code text)
returns json
language plpgsql
volatile
security definer
set search_path = public
as $$
declare
  r registros%rowtype; v_club text; v_rrpp text; v_marcar boolean;
begin
  select r2.* into r from registros r2
   where r2.evento_id = p_evento and r2.code = upper(p_code);
  if not found then return json_build_object('resultado', 'no_existe'); end if;
  select e.club_id into v_club from eventos e where e.id = r.evento_id;
  if exists (select 1 from ingreso_sin_tope st where st.user_id = r.rrpp_id and st.club_id = v_club) then
    return json_build_object('resultado', 'protegida');
  end if;
  select p.nombre into v_rrpp from profiles p where p.id = r.rrpp_id;
  v_marcar := r.filtro_at is null;
  update registros
     set filtro_at  = case when v_marcar then now() end,
         filtro_por = case when v_marcar then auth.uid() end
   where id = r.id;
  return json_build_object('resultado', 'ok', 'marcado', v_marcar, 'nombre', r.nombre, 'rrpp', v_rrpp);
end;
$$;


/* generar_qr_lista(p_registro) -> json {code, nombre}
 * Crea el code del registro si no lo tiene (6 hex, único por evento); si ya
 * existe devuelve el mismo ("la base devuelve el mismo código", app.js). */
create or replace function generar_qr_lista(p_registro uuid)
returns json
language plpgsql
volatile
security definer
set search_path = public
as $$
declare r registros%rowtype;
begin
  select * into r from registros where id = p_registro;
  if not found then return null; end if;
  if r.code is null then
    update registros set code = gen_code_evento(r.evento_id) where id = r.id
      returning * into r;
  end if;
  return json_build_object('code', r.code, 'nombre', r.nombre);
end;
$$;


/* generar_qr_lista_masivo(p_registros uuid[]) -> filas {code, nombre, rrpp_id}
 *
 * Lo mismo en tanda, PERO devuelve solo los registros que el que llama
 * puede mandar: los suyos, los de su team (si es jefe) o todos (admin).
 * Esa regla está afirmada por la app ("La base la vuelve a aplicar igual",
 * app.js:1936) y por el mensaje "${n} no son tuyos y quedaron afuera".
 * Rol y team del que llama: EFECTIVOS del club del evento (la regla de la
 * familia de rosters). Crea el code de los que no lo tengan.
 */
create or replace function generar_qr_lista_masivo(p_registros uuid[])
returns table (code text, nombre text, rrpp_id uuid)
language plpgsql
volatile
security definer
set search_path = public
as $$
declare r record; v_rol text; v_team uuid; v_club text;
begin
  for r in
    select r2.*, e.club_id
      from registros r2 join eventos e on e.id = r2.evento_id
     where r2.id = any(p_registros)
  loop
    select coalesce(cm.rol, p.rol),
           coalesce(cm.team_id,
             case when tb.id is not null
                       and (p.rol = 'admin' or tb.clubs is null
                            or coalesce(array_length(tb.clubs, 1), 0) = 0
                            or r.club_id = any(tb.clubs))
                  then p.team_id end)
      into v_rol, v_team
      from profiles p
      left join club_membership cm on cm.user_id = p.id and cm.club_id = r.club_id
      left join teams tb on tb.id = p.team_id
     where p.id = auth.uid();

    if v_rol = 'admin'
       or r.rrpp_id = auth.uid()
       or (v_rol = 'jefe' and v_team is not null and v_team = (
             select coalesce(cm2.team_id,
               case when tb2.id is not null
                         and (p2.rol = 'admin' or tb2.clubs is null
                              or coalesce(array_length(tb2.clubs, 1), 0) = 0
                              or r.club_id = any(tb2.clubs))
                    then p2.team_id end)
               from profiles p2
               left join club_membership cm2 on cm2.user_id = p2.id and cm2.club_id = r.club_id
               left join teams tb2 on tb2.id = p2.team_id
              where p2.id = r.rrpp_id))
    then
      if r.code is null then
        update registros set code = gen_code_evento(r.evento_id)
         where id = r.id returning registros.code into r.code;
      end if;
      code := r.code; nombre := r.nombre; rrpp_id := r.rrpp_id;
      return next;
    end if;
  end loop;
end;
$$;
