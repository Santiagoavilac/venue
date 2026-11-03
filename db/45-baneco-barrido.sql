-- Ejecutar sólo después de aplicar la migración, publicar baneco y configurar
-- secretos vigentes. La URL y el token se leen de Vault, nunca del frontend.
begin;
create extension if not exists pg_net;
create extension if not exists pg_cron;
do $$
declare v_url text; v_token text;
begin
  select decrypted_secret into v_url from vault.decrypted_secrets where name = 'baneco_project_url';
  select decrypted_secret into v_token from vault.decrypted_secrets where name = 'baneco_cron_token';
  if v_url is null or v_url !~ '^https://[a-z0-9]+\.supabase\.co$' then raise exception 'Falta la URL válida del proyecto en Vault'; end if;
  if v_token is null or length(v_token) < 32 then raise exception 'Falta un token de cron seguro en Vault'; end if;
  perform cron.unschedule(jobid) from cron.job where jobname = 'baneco-barrido';
  perform cron.schedule('baneco-barrido', '* * * * *', $job$
    select net.http_post(
      url := (select decrypted_secret from vault.decrypted_secrets where name = 'baneco_project_url') || '/functions/v1/baneco',
      headers := jsonb_build_object('Content-Type', 'application/json',
        'x-cron', (select decrypted_secret from vault.decrypted_secrets where name = 'baneco_cron_token')),
      body := '{"accion":"barrido"}'::jsonb,
      timeout_milliseconds := 55000)
    where exists (select 1 from public.pago_qr);
  $job$);
end;
$$;
commit;
