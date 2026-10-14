-- SEGURIDAD · la auditoría es de solo lectura para las personas.
--
-- Los grants por defecto de Supabase le daban a authenticated TRUNCATE,
-- REFERENCES y TRIGGER sobre audit_log. TRUNCATE no pasa por RLS: aunque
-- PostgREST no lo expone, nadie fuera del servicio debe poder vaciar el
-- registro. La lectura sigue gobernada por la política audit_log_leer
-- (plataforma, o admin del boliche de la fila). Re-ejecutable.

revoke truncate, references, trigger, insert, update, delete on audit_log from authenticated, anon;
