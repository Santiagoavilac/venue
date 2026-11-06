-- El QR del correo se sirve desde una URL firmada.
--
-- Qué se rompía: el QR iba incrustado en el correo como adjunto en línea
-- (`cid:`). En el teléfono se ve bien, pero **Gmail en la web no lo dibuja**:
-- sale el cuadrito roto donde tendría que estar el código. Y Gmail en la web
-- es donde más gente abre el correo.
--
-- Acá el QR se sube a este bucket y el correo lo trae por una URL firmada, que
-- es lo que Gmail sí muestra. El bucket es privado: sin la firma no se llega
-- al archivo, y el nombre es un uuid al azar, así que tampoco se puede ir
-- probando nombres. La firma dura 60 días, que es mucho más que cualquier
-- fiesta y suficiente para que el correo viejo siga abriendo.
--
-- El PDF adjunto sigue siendo la entrada de verdad: funciona aunque el correo
-- tenga las imágenes bloqueadas, que es lo que pasa en algunas casillas.
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('aftr-qr', 'aftr-qr', false, 262144, array['image/png'])
on conflict (id) do update set
  public = false,
  file_size_limit = 262144,
  allowed_mime_types = array['image/png'];

-- Sin políticas: sólo la llave de servicio sube y firma. Nadie de la app tiene
-- por qué leer el QR de otro, y por eso no hay ninguna política de lectura.
-- (RLS en storage.objects ya está activo desde db/.)

-- ── limpieza ──────────────────────────────────────────────────────────
-- Los QR de fiestas que ya pasaron no tienen por qué seguir ahí. A los 90 días
-- se borran: para entonces la firma ya venció y la entrada hace rato que se
-- usó o se perdió.
create or replace function impl.aftr_qr_limpieza()
returns integer language plpgsql security definer set search_path = public, pg_temp
as $$
declare v_n int;
begin
  with viejos as (
    delete from storage.objects
     where bucket_id = 'aftr-qr' and created_at < now() - interval '90 days'
    returning 1)
  select count(*) into v_n from viejos;
  return coalesce(v_n, 0);
end $$;
revoke all on function impl.aftr_qr_limpieza() from public, anon, authenticated;

select cron.schedule('aftr-qr-limpiar', '17 5 * * *', $$select impl.aftr_qr_limpieza();$$)
 where not exists (select 1 from cron.job where jobname = 'aftr-qr-limpiar');

notify pgrst,'reload schema';
