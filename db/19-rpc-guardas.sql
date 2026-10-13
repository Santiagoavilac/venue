-- SEGURIDAD (2/…) · guardas de permiso para TODAS las RPC.
--
-- Problema: casi todas las RPC son SECURITY DEFINER (saltan RLS) y la
-- mayoría no comprobaba quién las llama: eliminar_evento, eliminar_usuario,
-- validar_entrada, etc. podían ejecutarse por REST con cualquier sesión —y,
-- sin REVOKE, también sin sesión, con la anon key.
--
-- Cómo se arregla SIN tocar la lógica de negocio:
--   1. La función original se muda, intacta, al esquema `impl` (no expuesto
--      por la API).
--   2. En `public` queda una guarda con la misma firma: comprueba sesión,
--      rol y boliche, y recién entonces delega en impl.
--   3. La matriz de quién puede qué vive en la tabla impl.rpc_permiso: es
--      a la vez la especificación (docs/RPC_MATRIZ.md sale de acá) y lo que
--      genera las guardas.
--   4. Se revoca EXECUTE a anon/public en todo el esquema.
--
-- Las funciones originales siguen llamándose entre sí por nombre sin
-- esquema (search_path = public): resuelven a la guarda, que vuelve a
-- comprobar con el mismo usuario. Correcto y barato.
--
-- Re-ejecutable. Si se vuelve a correr algún 02*/03*.sql original (pisa la
-- guarda con la versión sin protección), correr este archivo otra vez: lo
-- detecta por la marca del comentario y la vuelve a mudar.

create table if not exists impl.rpc_permiso (
  fn      text primary key,
  alcance text not null,      -- documentación: club / evento / mesa / … / sesión
  roles   text not null,      -- documentación: roles admitidos
  guarda  text not null,      -- PL/pgSQL que corre antes de delegar (deja v_rol)
  filtro  text,               -- solo set-returning: condición sobre la fila `t`
  nota    text
);
truncate impl.rpc_permiso;

/* guarda estándar: rol en el boliche de la entidad `tipo` que llega en `arg` */
create or replace function impl.g(p_tipo text, p_arg text, p_roles text)
returns text language sql immutable
as $$
  select case p_tipo
    when 'club'   then format('v_rol := impl.exigir(%s, %L::text[]);', p_arg, '{' || p_roles || '}')
    when 'sesion' then 'v_rol := impl.exigir_sesion();'
    else format('v_rol := impl.exigir(impl.club_de(%L, %s), %L::text[]);', p_tipo, p_arg, '{' || p_roles || '}')
  end;
$$;

-- Conjuntos de roles usados abajo:
--   admin                          catálogo y plata
--   admin,jefe                     gestión de team
--   admin,jefe,rrpp                los que venden / anotan
--   admin,jefe,rrpp,portero        operación de puerta (lectura)
--   admin,portero                  validar ingresos
--   admin,propietario[,barra|deposito]   módulo barra
insert into impl.rpc_permiso (fn, alcance, roles, guarda, filtro, nota) values
-- ── lectura de evento ────────────────────────────────────────────────
('liquidacion_evento',   'evento', 'admin',                    impl.g('evento','p_evento','admin'), null, 'plata del evento'),
('resumen_evento',       'evento', 'admin,jefe,rrpp,portero',  impl.g('evento','p_evento','admin,jefe,rrpp,portero'), null, null),
('reporte_fases',        'evento', 'admin',                    impl.g('evento','p_evento','admin'), null, null),
('reporte_filtro',       'evento', 'admin',                    impl.g('evento','p_evento','admin'), null, null),
('fases_evento',         'evento', 'admin,jefe,rrpp',          impl.g('evento','p_evento','admin,jefe,rrpp'), null, null),
('fase_vigente',         'evento', 'admin,jefe,rrpp',          impl.g('evento','p_evento','admin,jefe,rrpp'), null, null),
('cupos_fase',           'fase',   'admin',                    impl.g('fase','p_fase','admin'), null, null),
('mis_cupos',            'evento', 'admin,jefe,rrpp',          impl.g('evento','p_evento','admin,jefe,rrpp'), null, null),
('ventana_venta',        'evento', 'admin,jefe,rrpp',
   impl.g('evento','p_evento','admin,jefe,rrpp') ||
   ' if v_rol = ''rrpp'' and p_user is distinct from auth.uid() then raise exception ''No autorizado.'' using errcode = ''42501''; end if;',
   null, 'el rrpp solo consulta la suya'),
('excepciones_venta',    'evento', 'admin',                    impl.g('evento','p_evento','admin'), null, null),
('vendedores_posibles',  'evento', 'admin,jefe,rrpp',          impl.g('evento','p_evento','admin,jefe,rrpp'), null, null),
('mis_permisos_mesa',    'evento', 'admin,jefe,rrpp,portero',  impl.g('evento','p_evento','admin,jefe,rrpp,portero'), null, null),
('buscar_registros',     'evento', 'admin,jefe,rrpp,portero',  impl.g('evento','p_evento','admin,jefe,rrpp,portero'), null, null),
('contabilidad_evento',  'evento', 'admin,jefe',               impl.g('evento','p_evento','admin,jefe'), null, 'la función además exige contabilidad_total o ser jefe del team'),
-- ── lectura por boliche ──────────────────────────────────────────────
('teams_efectivos',      'club',   'admin,jefe,rrpp,portero,caja', impl.g('club','p_club','admin,jefe,rrpp,portero,caja'), null, null),
('roster_relacionadores','club',   'admin,caja,portero',       impl.g('club','p_club','admin,caja,portero'), null, null),
('roster_caja',          'club',   'admin,caja,portero',       impl.g('club','p_club','admin,caja,portero'), null, null),
('roster_cupos',         'club',   'admin',                    impl.g('club','p_club','admin'), null, null),
('roster_mi_team',       'club',   'admin,jefe,rrpp',          impl.g('club','p_club','admin,jefe,rrpp'), null, null),
('usuarios_sin_tope',    'club',   'admin,jefe,rrpp,portero',  impl.g('club','p_club','admin,jefe,rrpp,portero'), null, null),
('telefonos_equipo',     'club',   'admin,jefe',               impl.g('club','p_club','admin,jefe'),
   'v_rol in (''admin'', ''servicio'') or t.user_id in (select pr.id from profiles pr where pr.team_id = mi_team_en_club(p_club) union select cm.user_id from club_membership cm where cm.club_id = p_club and cm.team_id = mi_team_en_club(p_club))',
   'dato personal: el jefe solo ve los teléfonos de su team'),
('historico_eventos',    'club',   'admin',                    impl.g('club','p_club','admin'), null, null),
('ranking_rrpp',         'club',   'admin',                    impl.g('club','p_club','admin'), null, null),
('avisos_pendientes',    'club',   '*',                        impl.g('club','p_club','*'), null, null),
('avisos_admin',         'club',   'admin',                    impl.g('club','p_club','admin'), null, null),
('aviso_lectores',       'aviso',  'admin',                    impl.g('aviso','p_aviso','admin'), null, null),
('marcar_aviso_visto',   'aviso',  '*',                        impl.g('aviso','p_aviso','*'), null, null),
-- ── puerta ───────────────────────────────────────────────────────────
('validar_entrada',      'evento', 'admin,portero',            impl.g('evento','p_evento','admin,portero'), null, 'CONSUME la entrada'),
('validar_qr_lista',     'evento', 'admin,portero',            impl.g('evento','p_evento','admin,portero'), null, 'marca el ingreso'),
('descheckin_entrada',   'evento', 'admin,portero',            impl.g('evento','p_evento','admin,portero'), null, null),
('marcar_filtro_entrada','evento', 'admin,portero',            impl.g('evento','p_evento','admin,portero'), null, null),
('marcar_filtro_lista',  'evento', 'admin,portero',            impl.g('evento','p_evento','admin,portero'), null, null),
('marcar_filtro_registro','registro','admin,portero',          impl.g('registro','p_registro','admin,portero'), null, null),
('checkin_registro',     'registro','admin,portero,jefe,rrpp',
   impl.g('registro','p_registro','admin,portero,jefe,rrpp') ||
   ' if v_rol in (''jefe'',''rrpp'') and not coalesce((select pr.puede_tickear from profiles pr where pr.id = auth.uid()), false) then raise exception ''No autorizado.'' using errcode = ''42501''; end if;',
   null, 'jefe/rrpp solo con puede_tickear (regla que ya tenía la UI)'),
('descheckin_registro',  'registro','admin,portero,jefe,rrpp',
   impl.g('registro','p_registro','admin,portero,jefe,rrpp') ||
   ' if v_rol in (''jefe'',''rrpp'') and not coalesce((select pr.puede_tickear from profiles pr where pr.id = auth.uid()), false) then raise exception ''No autorizado.'' using errcode = ''42501''; end if;',
   null, null),
-- ── listas y entradas ────────────────────────────────────────────────
('registrar_lista',      'lista',  'admin,jefe,rrpp',          impl.g('lista','p_lista','admin,jefe,rrpp'), null, null),
('eliminar_registro',    'registro','admin,jefe,rrpp',         impl.g('registro','p_registro','admin,jefe,rrpp'), null, 'la función exige además ser quien lo anotó o admin'),
('heredar_cupos_lista',  'lista',  'admin',                    impl.g('lista','p_lista','admin'), null, null),
('generar_qr_lista',     'registro','admin,jefe,rrpp',
   impl.g('registro','p_registro','admin,jefe,rrpp') ||
   ' if v_rol = ''rrpp'' and not exists (select 1 from registros rg where rg.id = p_registro and auth.uid() in (rg.rrpp_id, rg.cargado_por)) then raise exception ''No autorizado.'' using errcode = ''42501''; end if;',
   null, 'el rrpp solo genera QR de sus invitados'),
('generar_qr_lista_masivo','sesión','(interno)',               impl.g('sesion','',''), null, 'la función ya filtra por rol/team registro por registro'),
('generar_entrada',      'evento', 'admin,jefe,rrpp',          impl.g('evento','p_evento','admin,jefe,rrpp'), null, null),
('anular_entrada',       'entrada','admin,jefe,rrpp',          impl.g('entrada','p_entrada','admin,jefe,rrpp'), null, 'la función exige vendedor o admin'),
('eliminar_entrada',     'entrada','admin,jefe,rrpp',          impl.g('entrada','p_entrada','admin,jefe,rrpp'), null, null),
-- ── mesas ────────────────────────────────────────────────────────────
-- BLOQUEO DE FILA: vender_mesa leía la mesa, veía "disponible" y la marcaba
-- vendida sin bloquearla; dos ventas simultáneas pasaban las dos (probado:
-- tests/test_seguridad.py). La guarda toma la fila FOR UPDATE antes de
-- delegar: la segunda espera, y al seguir ya la ve vendida.
('vender_mesa',          'mesa',   'admin,jefe,rrpp',          impl.g('mesa','p_mesa','admin,jefe,rrpp') || ' perform 1 from mesas ms where ms.id = p_mesa for update;', null, 'bloquea la mesa: sin doble venta'),
('vender_mesa_grupo',    'mesas',  'admin,jefe,rrpp',          'v_rol := impl.exigir_mesas(p_mesas, ''{admin,jefe,rrpp}''::text[]); perform 1 from mesas ms where ms.id = any(p_mesas) order by ms.id for update;', null, 'bloquea las mesas en orden: sin doble venta ni deadlock'),
('editar_mesa',          'mesa',   'admin,jefe',               impl.g('mesa','p_mesa','admin,jefe') || ' perform 1 from mesas ms where ms.id = p_mesa for update;', null, null),
('pagar_mesa',           'mesa',   'admin,jefe,rrpp',
   impl.g('mesa','p_mesa','admin,jefe,rrpp') ||
   ' if v_rol = ''rrpp'' and not exists (select 1 from mesas ms where ms.id = p_mesa and auth.uid() in (ms.vendido_por, ms.cargada_por)) then raise exception ''No autorizado.'' using errcode = ''42501''; end if;',
   null, 'el rrpp solo paga las mesas que vendió'),
('verificar_mesa',       'mesa',   'admin',                    impl.g('mesa','p_mesa','admin') || ' perform 1 from mesas ms where ms.id = p_mesa for update;', null, 'verificación de pago'),
('estado_mesa',          'mesa',   'admin,jefe,rrpp',
   impl.g('mesa','p_mesa','admin,jefe,rrpp') ||
   ' if v_rol = ''rrpp'' and not exists (select 1 from mesas ms where ms.id = p_mesa and auth.uid() in (ms.vendido_por, ms.cargada_por)) then raise exception ''No autorizado.'' using errcode = ''42501''; end if;'
   ' if v_rol = ''jefe'' and not exists (select 1 from mesas ms join profiles pv on pv.id = ms.vendido_por where ms.id = p_mesa and (ms.vendido_por = auth.uid() or pv.team_id = mi_team_en_club(impl.club_de(''mesa'', p_mesa)))) then raise exception ''No autorizado.'' using errcode = ''42501''; end if;',
   null, 'liberar/ocupar: admin, quien la vendió o el jefe de su team'),
('liberar_reservas_vencidas','evento','admin,jefe,rrpp,portero', impl.g('evento','p_evento','admin,jefe,rrpp,portero'), null, 'barrido automático al abrir Mesas'),
('heredar_mesas',        'evento', 'admin',                    impl.g('evento','p_hacia','admin'), null, null),
('copiar_mesas',         'evento×2','admin',
   impl.g('evento','p_desde','admin') || ' ' || impl.g('evento','p_hacia','admin'), null, 'admin en el boliche de AMBOS eventos'),
-- ── pagos ────────────────────────────────────────────────────────────
('crear_pago',           'evento', 'admin,jefe,rrpp',          impl.g('evento','p_evento','admin,jefe,rrpp'), null, null),
('estado_pago',          'pago',   'admin',                    impl.g('pago','p_pago','admin'), null, 'verificación de pago'),
('adjuntar_comprobante', 'pago',   'admin,jefe,rrpp',          impl.g('pago','p_pago','admin,jefe,rrpp'), null, 'la función exige dueño del pago o admin'),
-- ── eventos y catálogo ───────────────────────────────────────────────
('publicar_evento',      'evento', 'admin',                    impl.g('evento','p_evento','admin'), null, null),
('eliminar_evento',      'evento', 'admin',                    impl.g('evento','p_evento','admin'), null, 'DESTRUCTIVA'),
('guardar_fase',         'evento', 'admin',                    impl.g('evento','p_evento','admin'), null, null),
('borrar_fase',          'fase',   'admin',                    impl.g('fase','p_fase','admin'), null, null),
('fase_arte',            'fase',   'admin',                    impl.g('fase','p_fase','admin'), null, null),
('guardar_cupo_team',    'fase',   'admin',                    impl.g('fase','p_fase','admin'), null, null),
('set_venta_por_fases',  'evento', 'admin',                    impl.g('evento','p_evento','admin'), null, null),
('set_manillas_externas','evento', 'admin',                    impl.g('evento','p_evento','admin'), null, null),
-- ── equipo ───────────────────────────────────────────────────────────
('eliminar_usuario',     'usuario','admin de todos sus boliches',
   'v_rol := impl.exigir_sesion(); if not impl.puede_admin_usuario(p_user) then raise exception ''No autorizado.'' using errcode = ''42501''; end if;',
   null, 'DESTRUCTIVA'),
('eliminar_team',        'team',   'admin de todos sus boliches',
   'v_rol := impl.exigir_sesion(); if not impl.puede_admin_team(p_team) or (p_destino is not null and not impl.puede_admin_team(p_destino)) then raise exception ''No autorizado.'' using errcode = ''42501''; end if;',
   null, 'DESTRUCTIVA'),
('set_team_qr',          'team',   'jefe (su team) · admin del team',
   'v_rol := impl.exigir_sesion(); if p_team is not null and not impl.puede_admin_team(p_team) then raise exception ''No autorizado.'' using errcode = ''42501''; end if; if p_team is null and not exists (select 1 from teams tm where tm.jefe_id = auth.uid() or (tm.id = (select pr.team_id from profiles pr where pr.id = auth.uid()) and v_rol in (''jefe'',''admin''))) then raise exception ''No autorizado.'' using errcode = ''42501''; end if;',
   null, 'el QR de cobro del team recibe plata: no lo cambia un rrpp'),
('guardar_telefono_de',  'usuario','admin de todos sus boliches',
   'v_rol := impl.exigir_sesion(); if not impl.puede_admin_usuario(p_user) and p_user is distinct from auth.uid() then raise exception ''No autorizado.'' using errcode = ''42501''; end if;',
   null, null),
('guardar_telefono',     'sesión', '*',                        impl.g('sesion','',''), null, 'el propio'),
('mi_telefono',          'sesión', '*',                        impl.g('sesion','',''), null, 'el propio'),
-- ── barra ────────────────────────────────────────────────────────────
('bar_disponibilidad',   'club',   'admin,propietario,barra',  impl.g('club','p_club','admin,propietario,barra'), null, null),
('bar_proyeccion_compra','club',   'admin,propietario',        impl.g('club','p_club','admin,propietario'), null, null),
('bar_cortesias_evento', 'evento', 'admin,propietario,barra',  impl.g('evento','p_evento','admin,propietario,barra'), null, null),
('bar_conteo_pendiente', 'evento', 'admin,propietario',        impl.g('evento','p_evento','admin,propietario'), null, null),
('bar_conteo_masivo',    'evento', 'admin,propietario',        impl.g('evento','p_evento','admin,propietario'), null, null),
('bar_recibir_lote',     'bebida', 'admin,propietario,deposito', impl.g('bebida','p_bebida','admin,propietario,deposito'), null, null),
('bar_vender',           'evento', 'admin,propietario,barra',
   impl.g('evento','p_evento','admin,propietario,barra') ||
   ' if impl.club_de(''barra'', p_barra) is distinct from impl.club_de(''evento'', p_evento) then raise exception ''No autorizado.'' using errcode = ''42501''; end if;',
   null, 'la barra tiene que ser del mismo boliche que el evento'),
('bar_anular_venta',     'venta',  'admin,propietario,barra',  impl.g('venta','p_venta','admin,propietario,barra'), null,
   'bar_ventas no guarda quién vendió: no se puede limitar al bartender a las suyas hasta 25-auditoria.sql'),
('bar_ajuste_conteo',    'lote',   'admin,propietario',        impl.g('lote','p_lote','admin,propietario'), null, null),
('bar_baja',             'lote',   'admin,propietario',        impl.g('lote','p_lote','admin,propietario'), null, null);

/* ── generador ─────────────────────────────────────────────────────── */
do $gen$
declare
  r record; f record;
  v_args text; v_call text; v_res text; v_vol text; v_cuerpo text;
begin
  for r in select * from impl.rpc_permiso order by fn loop
    -- 1) mudar a impl toda versión de public que no sea ya una guarda
    for f in
      select p.oid, pg_get_function_identity_arguments(p.oid) as ident
        from pg_proc p join pg_namespace n on n.oid = p.pronamespace
       where n.nspname = 'public' and p.proname = r.fn
         and coalesce(obj_description(p.oid, 'pg_proc'), '') <> 'venue:guarda'
    loop
      execute format('drop function if exists impl.%I(%s)', r.fn, f.ident);
      execute format('alter function public.%I(%s) set schema impl', r.fn, f.ident);
    end loop;

    if not exists (select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
                    where n.nspname = 'impl' and p.proname = r.fn) then
      raise exception 'rpc_permiso: la función % no existe (¿falta correr algún archivo previo?)', r.fn;
    end if;

    -- 2) una guarda por cada firma que haya en impl
    for f in
      select p.oid, p.proretset, p.prorettype, p.provolatile,
             pg_get_function_arguments(p.oid)          as args,
             pg_get_function_identity_arguments(p.oid) as ident,
             pg_get_function_result(p.oid)             as res,
             coalesce((select string_agg(quote_ident(nm), ', ' order by ord)
                         from unnest(p.proargnames[1:p.pronargs]) with ordinality as a(nm, ord)), '') as llamada
        from pg_proc p join pg_namespace n on n.oid = p.pronamespace
       where n.nspname = 'impl' and p.proname = r.fn
    loop
      v_vol := case f.provolatile when 'i' then 'stable' when 's' then 'stable' else 'volatile' end;
      v_call := format('impl.%I(%s)', r.fn, f.llamada);
      v_cuerpo := case
        when f.proretset then
          format('return query select * from %s t%s;', v_call,
                 case when r.filtro is not null then ' where ' || r.filtro else '' end)
        when f.prorettype = 'void'::regtype then format('perform %s;', v_call)
        else format('return %s;', v_call)
      end;
      execute format('drop function if exists public.%I(%s)', r.fn, f.ident);
      execute format($f$
        create function public.%I(%s) returns %s
        language plpgsql %s security definer set search_path = public
        as $guarda$
        #variable_conflict use_column
        declare v_rol text;
        begin
          %s
          %s
        end;
        $guarda$
      $f$, r.fn, f.args, f.res, v_vol, r.guarda, v_cuerpo);
      execute format('comment on function public.%I(%s) is %L', r.fn, f.ident, 'venue:guarda');
    end loop;
  end loop;
end
$gen$;

/* ── toda RPC de public que NO esté en la matriz es un error de cobertura ─ */
do $chk$
declare v text;
begin
  select string_agg(p.proname, ', ' order by p.proname) into v
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.prosecdef
     and p.prorettype <> 'trigger'::regtype
     and coalesce(obj_description(p.oid, 'pg_proc'), '') <> 'venue:guarda'
     and p.proname <> '_venue_exec'   -- instalador temporal (tools/aplicar.py), solo service_role
     and p.proname not in ('rol_actual', 'mi_team_base', 'es_platform_admin',
                           'rol_en_club', 'mi_team_en_club', 'mis_clubs',
                           -- helpers de políticas (21-rls-por-boliche.sql): solo informan el rol propio
                           'rol_en', 'admin_de_clubs', 'comparte_club');
  if v is not null then
    raise exception 'Funciones SECURITY DEFINER sin guarda en public: %', v;
  end if;
end
$chk$;

/* ── permisos de ejecución ─────────────────────────────────────────── */
revoke execute on all functions in schema public from public, anon;
grant  execute on all functions in schema public to authenticated, service_role;
revoke execute on all functions in schema impl   from public, anon, authenticated;

-- internas: se usan solo desde otras funciones (que corren como dueño)
revoke execute on function gen_code_evento(uuid), mesa_limpiar(uuid) from authenticated;
revoke execute on function cuenta_protegida_guard(), perfil_update_guard(),
  membresia_protegida_guard() from authenticated;

-- lo que se cree de acá en adelante nace cerrado para anónimos
alter default privileges revoke execute on functions from public;
alter default privileges in schema public revoke execute on functions from anon;
