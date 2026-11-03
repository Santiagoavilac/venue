-- Limpieza local independiente de la disponibilidad del banco.
-- Solo libera pedidos vencidos sin generación bancaria activa o incierta.
do $$ begin
 if to_regprocedure('cron.schedule(text,text,text)') is not null then
  perform cron.schedule('aftr-stock-liberar','* * * * *','select public.baneco_liberar_sin_qr();');
 end if;
end $$;
