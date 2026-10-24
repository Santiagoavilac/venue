-- Logo de cada boliche. El admin lo sube desde la app (Cuenta → Boliche →
-- Logo) al bucket público `disenos`, en logos/<club>.jpg; acá queda la URL.
-- Escribir `clubs` ya es solo del admin (política clubs_admin, 17). Re-ejecutable.
alter table clubs add column if not exists logo_url text;

comment on column clubs.logo_url is
  'URL pública del logo (bucket disenos, logos/<id>.jpg). null = se muestra la inicial.';
