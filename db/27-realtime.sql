-- Tiempo real: el plano de mesas y el contador de la puerta se actualizan
-- solos. La web y la app se suscriben a los cambios de estas tablas por
-- evento; faltaba agregarlas a la publicación en una instalación limpia.
-- Realtime respeta RLS: cada quien recibe solo las filas que puede leer.
-- Re-ejecutable.
do $$
declare t text;
begin
  foreach t in array array['mesas', 'entradas', 'registros'] loop
    if not exists (select 1 from pg_publication_tables
                    where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = t) then
      execute format('alter publication supabase_realtime add table public.%I', t);
    end if;
  end loop;
end $$;
