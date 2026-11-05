-- El cron de limpieza de historias usa su propia llave.
--
-- `historias-media` validaba el token del cron contra BANECO_CRON_TOKEN, el del
-- banco, y el cron le mandaba ese mismo secreto desde el Vault. Dos puertas con
-- la misma llave es una llave que no se puede rotar sin cerrar las dos: rotar
-- la del banco cortaba la limpieza, y al revés.
--
-- El secreto nuevo se crea una sola vez y no vive acá (un secreto no va a un
-- archivo del repo). Si hace falta recrearlo:
--
--   select vault.create_secret('<token de 64 hex>', 'social_cron_token',
--     'Token del cron de limpieza de historias (historias-media)');
--   supabase secrets set SOCIAL_CRON_TOKEN='<el mismo token>'
--
-- Los dos valores tienen que ser el mismo. La función acepta el del banco sólo
-- como respaldo, para que la limpieza no se corte entre el cambio y el deploy.
do $cron$
begin
  if not exists (select 1 from vault.decrypted_secrets where name = 'social_cron_token') then
    raise notice 'Falta el secreto social_cron_token: la limpieza sigue con el token del banco.';
    return;
  end if;
  perform cron.unschedule('aftr-historias-limpiar')
   where exists (select 1 from cron.job where jobname = 'aftr-historias-limpiar');
  perform cron.schedule('aftr-historias-limpiar', '*/15 * * * *', $trabajo$
   select net.http_post(url:='https://cxksjarupexptfksnptg.supabase.co/functions/v1/historias-media',
    headers:=jsonb_build_object('Content-Type','application/json','x-social-cron',
      (select decrypted_secret from vault.decrypted_secrets where name='social_cron_token' limit 1)),
    body:='{"accion":"limpiar"}'::jsonb,timeout_milliseconds:=30000)
   where exists(select 1 from vault.decrypted_secrets where name='social_cron_token')
  $trabajo$);
end $cron$;
