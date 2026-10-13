-- LECTURA POR ROL (aprobado 2026-08-21) · antes cualquier autenticado podía
-- leer las tablas operativas por REST. La matriz nueva conserva EXACTAMENTE
-- lo que cada pantalla usa hoy (nada cambia en la app) y cierra el resto:
--   · entradas / registros / mesas / lista_tipos → solo la operación de
--     puerta: admin, jefe, rrpp y portero (el portero las usa en el plano,
--     la lista de puerta y el contador realtime del escáner).
--   · pagos → admin, jefe y rrpp (el portero y la caja no ven plata de
--     rendiciones; la caja tiene su propia pantalla con roster + checks).
--   · caja y roles de barra (propietario/barra/deposito) no leen NADA de
--     la operación de puerta.
-- NOTA deliberada: el rrpp CONSERVA lectura completa de entradas/registros
-- porque Listas le muestra todos los invitados y el Reporte calcula
-- totales globales por diseño; restringirlo cambiaría lo que ve (decisión
-- de negocio, no endurecimiento). Su pantalla de Entradas ya consulta
-- solo lo suyo desde el fix anterior.

do $$
declare t text;
begin
  foreach t in array array['entradas', 'registros', 'mesas', 'lista_tipos']
  loop
    execute format('drop policy if exists %I on %I', t || '_leer', t);
    execute format(
      'create policy %I on %I for select to authenticated using (rol_actual() in (''admin'',''jefe'',''rrpp'',''portero''))',
      t || '_leer', t);
  end loop;
end $$;

drop policy if exists pagos_leer on pagos;
create policy pagos_leer on pagos for select to authenticated
  using (rol_actual() in ('admin', 'jefe', 'rrpp'));
