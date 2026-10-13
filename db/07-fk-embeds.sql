-- FIDELIDAD: los NOMBRES de los FK importan — la app los usa como hints de
-- embed de PostgREST (p. ej. `profiles!pagos_rrpp_id_fkey(nombre)` en
-- screenPagos). Sin el constraint con ESE nombre, PostgREST responde
-- "Could not find a relationship between 'pagos' and 'profiles'" y la
-- pantalla de Pagos muere. Detectado probando la app real contra el
-- destino (2026-08-21). Los otros 5 hints que usa la app ya existían con
-- el nombre exacto; faltaba solo este. Cero filas huérfanas verificado.
alter table pagos
  add constraint pagos_rrpp_id_fkey foreign key (rrpp_id) references profiles(id);
