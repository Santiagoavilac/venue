-- ETAPA 2 · MEJORAS (2/2): RLS completo.
--
-- Cierra el hallazgo M1 de la auditoría: la app hace ~30 accesos directos
-- a tablas (la matriz exacta se extrajo de app.js con un parser de
-- sb.from(...)), y sin RLS cualquier usuario autenticado podía escribir
-- CUALQUIER tabla desde la consola del navegador. Las políticas replican
-- el gateo REAL de la UI (quién ve qué pantalla), ni más ni menos:
--   admin        → catálogo completo (eventos, listas, mesas, teams, etc.)
--   jefe         → activar/desactivar gente de SU team (profiles.activo)
--   caja         → caja_check
--   propietario  → configuración de barra
--   resto        → solo lectura de lo que la app lee directo
-- Las RPCs son SECURITY DEFINER: no las afecta. Los permisos internos de
-- cada RPC ya están reconstruidos función por función.
--
-- Lo que NO se abre (la app no lo toca directo, solo vía RPC):
--   escrituras de registros/entradas/pagos/lotes/stock_mov/bar_ventas/
--   bar_venta_items/bar_conteos/evento_fase/fase_cupo_team/telefono_usuario/
--   ingreso_sin_tope/aviso_visto/clubs — y la lectura directa de
--   telefono_usuario/ingreso_sin_tope/aviso_visto/fase_cupo_team queda
--   solo para admin (datos personales / internos).

-- helpers (definer: evitan la recursión de RLS sobre profiles)
create or replace function rol_actual()
returns text language sql stable security definer set search_path = public
as $$ select rol from profiles where id = auth.uid() $$;

create or replace function mi_team_base()
returns uuid language sql stable security definer set search_path = public
as $$ select team_id from profiles where id = auth.uid() $$;

grant execute on function rol_actual(), mi_team_base() to authenticated;

-- ==== activar RLS en todo public ====
do $$
declare t text;
begin
  foreach t in array array[
    'profiles','clubs','teams','eventos','lista_tipos','registros','entradas',
    'mesas','pagos','combos','qr_cobro','plano_fondos','cupo_rrpp',
    'cupo_permanente','club_membership','venta_excepcion','caja_check',
    'avisos','bonos','telefono_usuario','ingreso_sin_tope','evento_fase',
    'fase_cupo_team','aviso_visto','bar_categorias','bebidas','barras',
    'tragos','receta_items','lotes','stock_mov','bar_ventas',
    'bar_venta_items','bar_staff','bar_cortesia_config','bar_cortesia_cupo',
    'bar_conteos']
  loop
    execute format('alter table %I enable row level security', t);
  end loop;
end $$;

-- ==== lectura abierta a autenticados (todo lo que la app lee directo) ====
do $$
declare t text;
begin
  foreach t in array array[
    'profiles','clubs','teams','eventos','lista_tipos','registros','entradas',
    'mesas','pagos','combos','qr_cobro','plano_fondos','cupo_rrpp',
    'cupo_permanente','club_membership','venta_excepcion','caja_check',
    'avisos','bonos','evento_fase']
  loop
    execute format('drop policy if exists %I on %I', t || '_leer', t);
    execute format('create policy %I on %I for select to authenticated using (true)', t || '_leer', t);
  end loop;
end $$;

-- ==== lectura restringida a admin (datos personales / internos) ====
do $$
declare t text;
begin
  foreach t in array array['telefono_usuario','ingreso_sin_tope','aviso_visto','fase_cupo_team']
  loop
    execute format('drop policy if exists %I on %I', t || '_leer', t);
    execute format('create policy %I on %I for select to authenticated using (rol_actual() = ''admin'')', t || '_leer', t);
  end loop;
end $$;

-- ==== barra: lectura para los roles del módulo ====
do $$
declare t text;
begin
  foreach t in array array[
    'bar_categorias','bebidas','barras','tragos','receta_items','lotes',
    'stock_mov','bar_ventas','bar_venta_items','bar_staff',
    'bar_cortesia_config','bar_cortesia_cupo','bar_conteos']
  loop
    execute format('drop policy if exists %I on %I', t || '_leer', t);
    execute format('create policy %I on %I for select to authenticated using (rol_actual() in (''admin'',''propietario'',''barra'',''deposito''))', t || '_leer', t);
  end loop;
end $$;

-- las vistas de plata de barra pasan a security_invoker: así la lectura
-- respeta las políticas de las tablas base (solo roles de barra + admin)
do $$
declare v text;
begin
  foreach v in array array[
    'v_bar_stock','v_bar_movimientos','v_bar_cierre','v_bar_evento',
    'v_bar_por_barra','v_bar_costos_evento','v_bar_merma','v_bar_margen',
    'v_bar_top_trago']
  loop
    execute format('alter view %I set (security_invoker = true)', v);
  end loop;
end $$;

-- ==== escritura: catálogo del admin ====
do $$
declare t text;
begin
  foreach t in array array[
    'eventos','lista_tipos','mesas','teams','club_membership','combos',
    'qr_cobro','plano_fondos','avisos','venta_excepcion','bonos',
    'cupo_rrpp','cupo_permanente']
  loop
    execute format('drop policy if exists %I on %I', t || '_admin', t);
    execute format('create policy %I on %I for all to authenticated using (rol_actual() = ''admin'') with check (rol_actual() = ''admin'')', t || '_admin', t);
  end loop;
end $$;

-- ==== profiles: admin todo; jefe solo filas de SU team (toggle activo) ====
drop policy if exists profiles_escribir on profiles;
create policy profiles_escribir on profiles for update to authenticated
  using (rol_actual() = 'admin'
         or (rol_actual() = 'jefe' and team_id is not distinct from mi_team_base()))
  with check (rol_actual() = 'admin'
         or (rol_actual() = 'jefe' and team_id is not distinct from mi_team_base()));

-- ==== caja_check: caja y admin ====
drop policy if exists caja_check_escribir on caja_check;
create policy caja_check_escribir on caja_check for all to authenticated
  using (rol_actual() in ('admin', 'caja'))
  with check (rol_actual() in ('admin', 'caja'));

-- ==== configuración de barra: propietario y admin ====
do $$
declare t text;
begin
  foreach t in array array[
    'bar_categorias','bebidas','barras','tragos','receta_items','bar_staff',
    'bar_cortesia_config']
  loop
    execute format('drop policy if exists %I on %I', t || '_escribir', t);
    execute format('create policy %I on %I for all to authenticated using (rol_actual() in (''admin'',''propietario'')) with check (rol_actual() in (''admin'',''propietario''))', t || '_escribir', t);
  end loop;
end $$;
