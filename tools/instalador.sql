-- Instalador temporal que usa tools/aplicar.py. Ejecuta SQL arbitrario:
-- crearlo SOLO mientras se instala (SQL Editor de Supabase) y borrarlo al
-- terminar con:   drop function if exists public._venue_exec(text);
create or replace function public._venue_exec(q text)
returns void language plpgsql security definer set search_path = public
as $$ begin execute q; end $$;
revoke all on function public._venue_exec(text) from public, anon, authenticated;
grant execute on function public._venue_exec(text) to service_role;
notify pgrst, 'reload schema';
