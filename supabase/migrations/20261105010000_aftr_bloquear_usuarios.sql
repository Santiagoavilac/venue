-- Bloquear usuarios en AFTR.
--
-- La App Store exige, para apps con contenido de usuarios (Guideline 1.2),
-- poder bloquear a alguien abusivo: no alcanza con reportar. Hasta ahora sólo
-- existía "Reportar historia", así que la app se habría rechazado por esto.
--
-- Bloquear es personal y silencioso: el bloqueado no se entera y no cambia
-- nada para los demás. Sólo esconde sus historias de quien lo bloqueó.
create table if not exists public.aftr_bloqueos (
  bloqueador_id uuid not null references auth.users(id) on delete cascade,
  bloqueado_id  uuid not null references auth.users(id) on delete cascade,
  created_at    timestamptz not null default now(),
  primary key (bloqueador_id, bloqueado_id),
  constraint aftr_bloqueos_no_uno_mismo check (bloqueador_id <> bloqueado_id)
);

create index if not exists aftr_bloqueos_bloqueador_idx
  on public.aftr_bloqueos (bloqueador_id, created_at desc);

alter table public.aftr_bloqueos enable row level security;

-- Cada quien ve y maneja sólo su propia lista. Se escribe por RPC, pero la
-- policy de lectura permite que la app liste a quién tiene bloqueado.
drop policy if exists aftr_bloqueos_propios on public.aftr_bloqueos;
create policy aftr_bloqueos_propios on public.aftr_bloqueos
  for select using (bloqueador_id = auth.uid());

revoke all on public.aftr_bloqueos from anon, authenticated;
grant select on public.aftr_bloqueos to authenticated;

comment on table public.aftr_bloqueos is
  'Quién bloqueó a quién en AFTR. Exigido por App Store Guideline 1.2 para contenido de usuarios.';
