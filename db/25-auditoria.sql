-- SEGURIDAD (7/…) · registro de auditoría de operaciones sensibles.
--
-- Hasta ahora no quedaba rastro de quién anuló una entrada, liberó una mesa,
-- verificó un pago, cambió un rol o borró un evento. audit_log lo guarda:
-- quién, cuándo, sobre qué fila, y el antes y el después.
--
-- Lo escriben solo los triggers (nadie por la API). Lo lee el admin del
-- boliche al que pertenece la fila, y el platform admin todo.
-- Re-ejecutable.

create table if not exists audit_log (
  id       bigint generated always as identity primary key,
  at       timestamptz not null default now(),
  actor    uuid,                 -- auth.uid(); null = contexto de servicio
  club_id  text,
  tabla    text not null,
  op       text not null,        -- INSERT | UPDATE | DELETE
  fila_id  text,
  antes    jsonb,
  despues  jsonb
);
create index if not exists audit_log_club_idx  on audit_log (club_id, at desc);
create index if not exists audit_log_tabla_idx on audit_log (tabla, fila_id);
alter table audit_log enable row level security;

drop policy if exists audit_log_leer on audit_log;
create policy audit_log_leer on audit_log for select to authenticated
  using (es_platform_admin() or (club_id is not null and rol_en_club(club_id) = 'admin'));
revoke insert, update, delete on audit_log from authenticated, anon;

create or replace function auditar()
returns trigger language plpgsql security definer set search_path = public
as $$
declare
  v_antes jsonb := case when tg_op <> 'INSERT' then to_jsonb(old) end;
  v_desp  jsonb := case when tg_op <> 'DELETE' then to_jsonb(new) end;
  v jsonb := coalesce(v_desp, v_antes);
  v_club text;
begin
  v_club := coalesce(
    v ->> 'club_id',
    (select e.club_id from eventos e where e.id = nullif(v ->> 'evento_id', '')::uuid));
  insert into audit_log (actor, club_id, tabla, op, fila_id, antes, despues)
  values (auth.uid(), v_club, tg_table_name, tg_op,
          coalesce(v ->> 'id', v ->> 'user_id'), v_antes, v_desp);
  return coalesce(new, old);
end;
$$;
revoke execute on function auditar() from public, anon, authenticated;

do $$
declare r record;
begin
  for r in select * from (values
    -- tabla, eventos, condición (solo para UPDATE; null = siempre)
    ('pagos',           'insert or update or delete', null),
    ('eventos',         'update or delete',           null),
    ('profiles',        'update or delete',           null),
    ('club_membership', 'insert or update or delete', null),
    ('platform_admins', 'insert or delete',           null),
    ('teams',           'update or delete',           null),
    ('clubs',           'insert or update or delete', null),
    ('bar_ventas',      'update or delete',           null),
    ('entradas',        'update or delete',           null),
    ('registros',       'update or delete',           null)
  ) as t(tabla, cuando, cond)
  loop
    execute format('drop trigger if exists auditoria on %I', r.tabla);
    execute format('create trigger auditoria after %s on %I for each row execute function auditar()',
                   r.cuando, r.tabla);
  end loop;
end $$;

-- mesas: solo lo que es plata o estado (mover una mesa en el plano no se audita)
drop trigger if exists auditoria on mesas;
create trigger auditoria after update on mesas for each row
  when (old.estado is distinct from new.estado
     or old.precio is distinct from new.precio
     or old.pago_verificado is distinct from new.pago_verificado
     or old.cortesia is distinct from new.cortesia
     or old.vendido_por is distinct from new.vendido_por
     or old.cliente is distinct from new.cliente)
  execute function auditar();
drop trigger if exists auditoria_borrado on mesas;
create trigger auditoria_borrado after delete on mesas for each row execute function auditar();

-- bar_ventas no guardaba quién vendió: sin eso no se puede auditar ni
-- limitar la anulación al bartender que hizo la venta.
alter table bar_ventas add column if not exists vendido_por uuid default auth.uid();
