-- SEGURIDAD (4/…) · RLS POR BOLICHE.
--
-- Las políticas de 06 y 10 decidían con rol_actual(), el rol BASE: cualquier
-- persona con rol en un boliche leía por REST las entradas, invitados,
-- mesas, pagos y stock de TODOS los boliches, y un admin escribía en todos.
-- Acá cada política pregunta por el rol EFECTIVO en el boliche dueño de la
-- fila (rol_en_club, 18-helpers-permiso.sql).
--
-- Dentro de un boliche se conserva la matriz de 10-lectura-por-rol.sql (qué
-- rol lee qué), con dos ajustes sobre datos sensibles:
--   · pagos: el rrpp ve los suyos; el jefe, los de su team; el admin, todos.
--   · telefono_usuario: solo el propio (los admins usan telefonos_equipo).
-- Pendiente de decisión de negocio (no se cambia acá): el rrpp sigue leyendo
-- todos los invitados y entradas de SU boliche, porque Listas y Reporte de la
-- web calculan totales con eso.
--
-- Las escrituras que no figuran acá siguen yendo solo por RPC.
-- Re-ejecutable: borra TODAS las políticas de cada tabla y las vuelve a crear.

/* rol efectivo en el boliche dueño de una entidad (para usar en políticas) */
create or replace function rol_en(p_tipo text, p_id uuid)
returns text language sql stable security definer set search_path = public
as $$
  select rol_en_club(case p_tipo
    when 'trago' then (select t.club_id from tragos t where t.id = p_id)
    else impl.club_de(p_tipo, p_id) end);
$$;

/* ¿administra TODOS estos boliches? (teams y personas que cruzan locales) */
create or replace function admin_de_clubs(p_clubs text[])
returns boolean language sql stable security definer set search_path = public
as $$
  select es_platform_admin()
      or (coalesce(array_length(p_clubs, 1), 0) > 0
          and not exists (select 1 from unnest(p_clubs) c
                           where rol_en_club(c) is distinct from 'admin'));
$$;

/* ¿la persona comparte algún boliche conmigo? */
create or replace function comparte_club(p_user uuid)
returns boolean language sql stable security definer set search_path = public
as $$
  select exists (
    select 1 from profiles p
     where p.id = p_user
       and (exists (select 1 from unnest(p.clubs) c where rol_en_club(c) is not null)
            or exists (select 1 from club_membership cm
                        where cm.user_id = p.id and rol_en_club(cm.club_id) is not null)));
$$;

grant execute on function rol_en(text, uuid), admin_de_clubs(text[]), comparte_club(uuid) to authenticated;

do $rls$
declare
  r record; p record;
  v_rol text; v_leer text; v_escribir text;
  puerta   constant text := '{admin,jefe,rrpp,portero}';
  venta    constant text := '{admin,jefe,rrpp}';
  barra    constant text := '{admin,propietario,barra,deposito}';
  barra_w  constant text := '{admin,propietario}';
begin
  for r in
    select * from (values
      -- tabla, expresión del rol de quien consulta, roles que leen ('*' = cualquiera del boliche), roles que escriben (null = solo RPC)
      ('eventos',               'rol_en_club(club_id)',               '*',      '{admin}'),
      ('combos',                'rol_en_club(club_id)',               '*',      '{admin}'),
      ('plano_fondos',          'rol_en_club(club_id)',               '*',      '{admin}'),
      ('qr_cobro',              'rol_en_club(club_id)',               venta,    '{admin}'),
      ('avisos',                'rol_en_club(club_id)',               '{admin}','{admin}'),
      ('cupo_permanente',       'rol_en_club(club_id)',               venta,    '{admin}'),
      ('ingreso_sin_tope',      'rol_en_club(club_id)',               '{admin}','{admin}'),
      ('lista_tipos',           'rol_en(''evento'', evento_id)',      puerta,   '{admin}'),
      ('mesas',                 'rol_en(''evento'', evento_id)',      puerta,   '{admin}'),
      ('registros',             'rol_en(''evento'', evento_id)',      puerta,   null),
      ('entradas',              'rol_en(''evento'', evento_id)',      puerta,   null),
      ('evento_fase',           'rol_en(''evento'', evento_id)',      venta,    null),
      ('venta_excepcion',       'rol_en(''evento'', evento_id)',      venta,    '{admin}'),
      ('bonos',                 'rol_en(''evento'', evento_id)',      venta,    '{admin}'),
      ('caja_check',            'rol_en(''evento'', evento_id)',      '{admin,caja,portero}', '{admin,caja}'),
      ('cupo_rrpp',             'rol_en(''lista'', lista_tipo_id)',   venta,    '{admin}'),
      ('fase_cupo_team',        'rol_en(''fase'', fase_id)',          '{admin}', null),
      -- barra
      ('bebidas',               'rol_en_club(club_id)',               barra,    barra_w),
      ('barras',                'rol_en_club(club_id)',               barra,    barra_w),
      ('tragos',                'rol_en_club(club_id)',               barra,    barra_w),
      ('bar_cortesia_config',   'rol_en_club(club_id)',               barra,    barra_w),
      ('bar_cortesia_cupo',     'rol_en_club(club_id)',               barra,    null),
      ('receta_items',          'rol_en(''trago'', trago_id)',        barra,    barra_w),
      ('bar_staff',             'rol_en(''evento'', evento_id)',      barra,    barra_w),
      ('bar_conteos',           'rol_en(''evento'', evento_id)',      barra,    null),
      ('bar_ventas',            'rol_en(''evento'', evento_id)',      barra,    null),
      ('bar_venta_items',       'rol_en(''venta'', venta_id)',        barra,    null),
      ('lotes',                 'rol_en(''bebida'', bebida_id)',      barra,    null),
      ('stock_mov',             'rol_en(''bebida'', bebida_id)',      barra,    null)
    ) as m(tabla, rol, leen, escriben)
  loop
    for p in select polname from pg_policy where polrelid = ('public.' || r.tabla)::regclass loop
      execute format('drop policy %I on %I', p.polname, r.tabla);
    end loop;
    execute format('alter table %I enable row level security', r.tabla);
    v_leer := case when r.leen = '*' then format('%s is not null', r.rol)
                   else format('%s = any(%L::text[])', r.rol, r.leen) end;
    execute format('create policy %I on %I for select to authenticated using (%s)',
                   r.tabla || '_leer', r.tabla, v_leer);
    if r.escriben is not null then
      v_escribir := format('%s = any(%L::text[])', r.rol, r.escriben);
      execute format('create policy %I on %I for all to authenticated using (%s) with check (%s)',
                     r.tabla || '_escribir', r.tabla, v_escribir, v_escribir);
    end if;
  end loop;
end
$rls$;

-- ── tablas con reglas propias ───────────────────────────────────────

-- clubs: cada quien ve los suyos; crear/borrar boliches es de la plataforma
do $$ declare p record; begin
  for p in select polname, polrelid::regclass as t from pg_policy
            where polrelid in ('clubs'::regclass, 'teams'::regclass, 'profiles'::regclass,
                               'club_membership'::regclass, 'pagos'::regclass,
                               'telefono_usuario'::regclass, 'aviso_visto'::regclass,
                               'caja_filtro'::regclass, 'caja_filtro_excepcion'::regclass)
  loop execute format('drop policy %I on %s', p.polname, p.t); end loop;
end $$;

create policy clubs_leer on clubs for select to authenticated
  using (rol_en_club(id) is not null);
create policy clubs_editar on clubs for update to authenticated
  using (rol_en_club(id) = 'admin') with check (rol_en_club(id) = 'admin');
create policy clubs_crear on clubs for insert to authenticated
  with check (es_platform_admin());
create policy clubs_borrar on clubs for delete to authenticated
  using (es_platform_admin());

-- teams: visibles si operan en alguno de mis boliches
create policy teams_leer on teams for select to authenticated
  using (es_platform_admin()
         or exists (select 1 from unnest(clubs) c where rol_en_club(c) is not null));
create policy teams_escribir on teams for all to authenticated
  using (admin_de_clubs(clubs)) with check (admin_de_clubs(clubs));

-- profiles: yo, y la gente con la que comparto boliche
create policy profiles_leer on profiles for select to authenticated
  using (id = auth.uid() or es_platform_admin() or comparte_club(id));
-- el detalle fino (qué columnas, a quién) lo hace el trigger perfil_update
create policy profiles_escribir on profiles for update to authenticated
  using (id = auth.uid() or es_platform_admin()
         or (comparte_club(id) and (rol_actual() = 'admin'
              or (rol_actual() = 'jefe' and team_id is not distinct from mi_team_base()))))
  with check (id = auth.uid() or es_platform_admin()
         or (rol_actual() = 'admin'
              or (rol_actual() = 'jefe' and team_id is not distinct from mi_team_base())));

create policy club_membership_leer on club_membership for select to authenticated
  using (user_id = auth.uid() or rol_en_club(club_id) is not null);
create policy club_membership_escribir on club_membership for all to authenticated
  using (rol_en_club(club_id) = 'admin') with check (rol_en_club(club_id) = 'admin');

-- pagos (plata): admin del boliche todo; jefe su team; cada uno lo suyo
create policy pagos_leer on pagos for select to authenticated
  using (rrpp_id = auth.uid()
         or rol_en('evento', evento_id) = 'admin'
         or (rol_en('evento', evento_id) = 'jefe'
             and exists (select 1 from profiles pr
                          where pr.id = pagos.rrpp_id
                            and pr.team_id = mi_team_en_club((select e.club_id from eventos e where e.id = pagos.evento_id)))));

create policy telefono_usuario_leer on telefono_usuario for select to authenticated
  using (user_id = auth.uid() or es_platform_admin());

create policy aviso_visto_leer on aviso_visto for select to authenticated
  using (user_id = auth.uid() or rol_en('aviso', aviso_id) = 'admin');

-- filtro de caja: lo escribe solo la cuenta principal (regla de 15), y ahora
-- además se lee solo dentro del boliche
create policy caja_filtro_leer on caja_filtro for select to authenticated
  using (rol_en('evento', evento_id) = any('{admin,caja,portero}'::text[]));
create policy caja_filtro_escribir on caja_filtro for all to authenticated
  using (es_platform_admin()) with check (es_platform_admin());
create policy caja_filtro_exc_leer on caja_filtro_excepcion for select to authenticated
  using (rol_en('evento', evento_id) = any('{admin,caja,portero}'::text[]));
create policy caja_filtro_exc_escribir on caja_filtro_excepcion for all to authenticated
  using (es_platform_admin()) with check (es_platform_admin());

-- Las políticas no usan nada de `impl`: corren como quien consulta y ese
-- esquema está cerrado para `authenticated`.
revoke usage on schema impl from authenticated;

-- ── vistas de estadísticas: que respeten RLS ────────────────────────
-- v_stats_rrpp y v_stats_mesas corrían con los permisos del dueño y
-- devolvían las filas de todos los boliches a cualquier sesión.
alter view v_stats_rrpp  set (security_invoker = true);
alter view v_stats_mesas set (security_invoker = true);

-- ── anónimos: nada ──────────────────────────────────────────────────
revoke all on all tables in schema public from anon;
alter default privileges in schema public revoke all on tables from anon;
