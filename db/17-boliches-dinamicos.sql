-- Boliches dinámicos: ampliar `clubs` para que un admin pueda crear
-- boliches nuevos desde la UI, con su propia identidad visual, en vez
-- de depender de los dos ids hardcodeados "bowie"/"burtown".

alter table clubs
  add column if not exists subtitulo        text,
  add column if not exists color_primario   text not null default '#7C3AED',
  add column if not exists color_secundario text not null default '#A855F7',
  add column if not exists color_accent     text not null default '#22D3EE',
  add column if not exists inicial          text,
  add column if not exists activo           boolean not null default true,
  add column if not exists created_at       timestamptz not null default now();

-- El id de `clubs` ya es el slug (lo que hoy sería "bowie"/"burtown").
-- Formato seguro para usarlo como clase CSS / segmento de URL.
alter table clubs drop constraint if exists clubs_id_formato;
alter table clubs
  add constraint clubs_id_formato check (id ~ '^[a-z0-9][a-z0-9-]{1,29}$');

-- RLS: sumar `clubs` al mismo patrón de escritura-admin que ya usan
-- las demás tablas de catálogo (ver 06-rls.sql). Hoy `clubs` quedaba
-- afuera de esa lista y nadie podía crear/editar boliches vía API.
drop policy if exists clubs_admin on clubs;
create policy clubs_admin on clubs for all to authenticated
  using (rol_actual() = 'admin') with check (rol_actual() = 'admin');
