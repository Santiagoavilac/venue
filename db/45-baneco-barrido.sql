-- 45 · Revisión automática de pagos QR (cada minuto)
--
-- Confirma los pagos aunque el comprador cierre la app: llama a la Edge
-- Function `baneco` con { accion: "barrido" }. El token va cifrado en la
-- bóveda (vault) y es el mismo que el secreto BANECO_CRON_TOKEN de la
-- función. Acá NO va el valor: se crea a mano con
--   select vault.create_secret('<token>', 'baneco_cron_token', '...');
create extension if not exists pg_net;
create extension if not exists pg_cron;

-- cada minuto, solo si hay QR activos (no molesta al banco si no hay nada pendiente)
select cron.unschedule('baneco-barrido') where exists (select 1 from cron.job where jobname = 'baneco-barrido');
select cron.schedule('baneco-barrido', '* * * * *', $job$
  select net.http_post(
    url := 'https://cxksjarupexptfksnptg.supabase.co/functions/v1/baneco',
    headers := jsonb_build_object('Content-Type', 'application/json',
      'x-cron', (select decrypted_secret from vault.decrypted_secrets where name = 'baneco_cron_token')),
    body := '{"accion":"barrido"}'::jsonb,
    timeout_milliseconds := 55000)
  where exists (select 1 from public.pago_qr where estado = 'activo');
$job$);
