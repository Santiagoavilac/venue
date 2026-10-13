-- CUENTA PROTEGIDA · @aqueirolo sigue siendo rol=admin, pero la cuenta con
-- admin_principal=true es máxima autoridad: NINGÚN otro usuario (ni otro
-- admin) puede modificarla por ningún camino — tabla directa, RPC o
-- edge function. La fuente de verdad es admin_principal (verificado: solo
-- aqueirolo la tiene, en el origen y acá), nunca el nombre visible.
--
-- Enforcement por TRIGGER en profiles (no por RLS): la política de RLS
-- filtraría la fila en silencio (0 afectadas) y el pedido explícito es un
-- ERROR CLARO también ante requests directos por API. El trigger corre
-- para cualquier rol de base de datos, y distingue el contexto por
-- auth.uid():
--   · auth.uid() = otro usuario  -> rechazo (app, consola, RPC definer)
--   · auth.uid() = el dueño      -> permitido (se gestiona a sí mismo)
--   · auth.uid() IS NULL         -> permitido (postgres/service_role:
--     sincronización y administración de plataforma, que no son "otro
--     usuario")
-- El flag admin_principal en sí NO lo cambia ningún usuario autenticado
-- (ni el propio dueño, contra el auto-degradado accidental): solo el
-- contexto de servicio.

create or replace function cuenta_protegida_guard()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare v_uid uuid := auth.uid();
begin
  if v_uid is null then
    return coalesce(new, old);   -- contexto de servicio: sync / plataforma
  end if;
  if tg_op = 'DELETE' then
    if old.admin_principal then
      raise exception 'Esta cuenta administrativa está protegida.';
    end if;
    return old;
  end if;
  -- UPDATE
  if old.admin_principal and v_uid <> old.id then
    raise exception 'Esta cuenta administrativa está protegida.';
  end if;
  if new.admin_principal is distinct from old.admin_principal then
    raise exception 'Esta cuenta administrativa está protegida.';
  end if;
  return new;
end;
$$;

drop trigger if exists cuenta_protegida on profiles;
create trigger cuenta_protegida
  before update or delete on profiles
  for each row execute function cuenta_protegida_guard();

-- El teléfono también es dato de la cuenta: el admin común no toca el del
-- protegido (misma regla: el dueño sí puede el suyo).
create or replace function guardar_telefono_de(p_tel text, p_user uuid)
returns void
language plpgsql
volatile
security definer
set search_path = public
as $$
declare v text := telefono_normalizar(p_tel);
begin
  if (select rol from profiles where id = auth.uid()) is distinct from 'admin' then
    raise exception 'Solo el admin puede cargar el número de otra persona';  -- TEXTO SUPUESTO
  end if;
  if exists (select 1 from profiles pr where pr.id = p_user
               and pr.admin_principal and pr.id <> auth.uid()) then
    raise exception 'Esta cuenta administrativa está protegida.';
  end if;
  if v is null then
    delete from telefono_usuario where user_id = p_user;
    return;
  end if;
  insert into telefono_usuario (user_id, telefono, actualizado_at, cargado_por)
  values (p_user, v, now(), auth.uid())
  on conflict (user_id) do update set telefono = excluded.telefono,
    actualizado_at = now(), cargado_por = auth.uid();
end;
$$;

-- eliminar_usuario y todo camino que archive (UPDATE de usuario.borrado…)
-- o borre duro caen en el trigger: no necesitan cambios propios.
