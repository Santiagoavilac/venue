-- CAJA · filtrar la lista a los que vendieron prepagadas (2026-08-23)
--
-- Pedido del dueño: un interruptor —sólo en la cuenta @aqueirolo— que haga
-- que en el rol de CAJA aparezcan únicamente los relacionadores que
-- cargaron prepagadas en su registro (NO importa si esa gente entró: cuenta
-- haberlas vendido, no que se hayan escaneado). Más un listado de
-- EXCEPCIONES para sumar a mano a alguien que no vendió ninguna.
--
-- POR QUÉ POR EVENTO Y NO GLOBAL: "quién vendió prepagadas" cambia cada
-- noche. Un interruptor global mostraría a los vendedores de la noche
-- anterior. La preferencia y las excepciones se guardan por evento, igual
-- que caja_check y que venta_excepcion.
--
-- POR QUÉ NO SE FILTRA SÓLO EN EL CLIENTE: la lista de caja sale de
-- roster_relacionadores, que devuelve a TODOS. Esconderlos en el navegador
-- dejaría la lista completa viajando igual. El filtro se aplica en la RPC.

create table if not exists caja_filtro (
  evento_id  uuid primary key,
  activo     boolean not null default false,
  updated_at timestamptz not null default now(),
  updated_by uuid default auth.uid()
);

create table if not exists caja_filtro_excepcion (
  evento_id  uuid not null,
  user_id    uuid not null,
  creado_at  timestamptz not null default now(),
  creado_por uuid default auth.uid(),
  primary key (evento_id, user_id)
);

do $$ begin
  alter table caja_filtro add constraint caja_filtro_evento_fkey
    foreign key (evento_id) references eventos(id) on delete cascade;
exception when duplicate_object then null; end $$;
do $$ begin
  alter table caja_filtro_excepcion add constraint caja_filtro_exc_evento_fkey
    foreign key (evento_id) references eventos(id) on delete cascade;
exception when duplicate_object then null; end $$;
do $$ begin
  alter table caja_filtro_excepcion add constraint caja_filtro_exc_user_fkey
    foreign key (user_id) references profiles(id) on delete cascade;
exception when duplicate_object then null; end $$;

alter table caja_filtro            enable row level security;
alter table caja_filtro_excepcion  enable row level security;

/* Leer: cualquiera autenticado (la caja necesita saber si el filtro está
   puesto). Escribir: SÓLO la cuenta protegida — es su interruptor. */
drop policy if exists caja_filtro_leer on caja_filtro;
create policy caja_filtro_leer on caja_filtro for select to authenticated using (true);
drop policy if exists caja_filtro_escribir on caja_filtro;
create policy caja_filtro_escribir on caja_filtro for all to authenticated
  using     (exists (select 1 from profiles p where p.id = auth.uid() and p.admin_principal))
  with check(exists (select 1 from profiles p where p.id = auth.uid() and p.admin_principal));

drop policy if exists caja_filtro_exc_leer on caja_filtro_excepcion;
create policy caja_filtro_exc_leer on caja_filtro_excepcion for select to authenticated using (true);
drop policy if exists caja_filtro_exc_escribir on caja_filtro_excepcion;
create policy caja_filtro_exc_escribir on caja_filtro_excepcion for all to authenticated
  using     (exists (select 1 from profiles p where p.id = auth.uid() and p.admin_principal))
  with check(exists (select 1 from profiles p where p.id = auth.uid() and p.admin_principal));


/* roster_caja(p_club, p_evento) -> las filas que ve la CAJA
 *
 * Envuelve roster_relacionadores (que sigue intacto: la usan otras
 * pantallas) y le aplica el filtro del evento:
 *   · filtro apagado (o sin fila)  -> todos, exactamente como hoy.
 *   · filtro encendido             -> sólo quienes tienen al menos una
 *     entrada prepagada a su nombre en ese evento, MÁS las excepciones.
 *
 * "Vendió prepagadas" = existe una fila en `entradas` con rrpp_id = la
 * persona, en el evento, sin mesa (las de mesa van dentro del precio de la
 * mesa) y no anulada. NO se mira used_at ni estado 'usada': el pedido es
 * explícito —cuenta que estén en su registro, no que hayan entrado—.
 *
 * Devuelve una columna extra `motivo` para que la caja sepa por qué está
 * alguien en la lista: 'prepagadas' o 'excepcion' ('todos' con filtro off).
 */
create or replace function roster_caja(p_club text, p_evento uuid default null)
returns table (
  id uuid, nombre text, usuario text, rol text, team text,
  clubs text[], motivo text
)
language plpgsql
stable
security definer
set search_path = public
as $$
declare v_activo boolean := false;
begin
  if p_evento is not null then
    select cf.activo into v_activo from caja_filtro cf where cf.evento_id = p_evento;
  end if;
  v_activo := coalesce(v_activo, false);

  if not v_activo or p_evento is null then
    return query
      select r.id, r.nombre, r.usuario, r.rol, r.team, r.clubs, 'todos'::text
        from roster_relacionadores(p_club) r;
    return;
  end if;

  return query
    select r.id, r.nombre, r.usuario, r.rol, r.team, r.clubs,
           case when exists (select 1 from caja_filtro_excepcion x
                              where x.evento_id = p_evento and x.user_id = r.id)
                  and not exists (select 1 from entradas e
                                   where e.evento_id = p_evento and e.rrpp_id = r.id
                                     and e.mesa_id is null and e.estado <> 'anulada')
                then 'excepcion'::text else 'prepagadas'::text end
      from roster_relacionadores(p_club) r
     where exists (select 1 from entradas e
                    where e.evento_id = p_evento and e.rrpp_id = r.id
                      and e.mesa_id is null and e.estado <> 'anulada')
        or exists (select 1 from caja_filtro_excepcion x
                    where x.evento_id = p_evento and x.user_id = r.id);
end;
$$;

revoke all on function roster_caja(text, uuid) from public, anon;
grant execute on function roster_caja(text, uuid) to authenticated;

notify pgrst, 'reload schema';
