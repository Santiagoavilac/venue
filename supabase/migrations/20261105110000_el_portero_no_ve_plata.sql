-- El portero trabaja en la puerta, no con la plata.
--
-- `impl.ve_registro` decide quién ve el trabajo de quién, y le da todo al
-- admin y al portero. Para listas y entradas está bien: en la puerta hay que
-- poder marcar a cualquiera, sea de quien sea. Pero la misma función decide
-- también quién ve los bonos y los datos de cobro de una mesa, y ahí el
-- portero quedó viendo cuánto cobró de más un relacionador y por cuánto se
-- vendió cada mesa.
--
-- La app nunca se lo mostró —su hoja de mesa dice cliente, combo y estado, y
-- el resumen de mesas le esconde el total—, pero con su sesión salía igual
-- por el endpoint REST, que es exactamente lo que vinimos cerrando.
--
-- `impl.ve_plata` es lo mismo que `ve_registro` menos el portero. Se usa en
-- los bonos y en las columnas de cobro de la vista de mesas; lo operativo
-- —quién es el cliente, en qué estado está, quién la vendió— sigue como
-- estaba, porque de eso sí depende la puerta.
create or replace function impl.ve_plata(p_evento uuid, p_persona uuid)
returns boolean
language plpgsql
stable
security definer
set search_path = public
as $$
declare v_rol text := rol_en('evento', p_evento); v_club text; v_mio uuid;
begin
  if v_rol = 'admin' then return true; end if;
  if v_rol = 'portero' then return false; end if;
  if v_rol = 'rrpp' then return p_persona = auth.uid(); end if;
  if v_rol = 'jefe' then
    if p_persona = auth.uid() then return true; end if;
    select club_id into v_club from eventos where id = p_evento;
    v_mio := impl.team_en_club(auth.uid(), v_club);
    return v_mio is not null and v_mio = impl.team_en_club(p_persona, v_club);
  end if;
  return false;
end;
$$;
grant execute on function impl.ve_plata(uuid, uuid) to authenticated;

-- Los bonos son plata de alguien: su dueño, su jefe y el boliche.
drop policy if exists bonos_leer on public.bonos;
create policy bonos_leer on public.bonos for select to authenticated
  using (impl.ve_plata(evento_id, user_id));

-- En las mesas, lo de cobrar pasa a ve_plata; el plano y lo operativo quedan
-- igual que estaban.
create or replace view public.mesas_detalle
with (security_invoker = false) as
select
  m.id, m.evento_id, m.planta, m.etiqueta, m.categoria, m.x, m.y, m.w, m.h,
  m.team_id, m.estado, m.combo_id, m.combo_qty, m.botellas, m.manillas,
  m.grupo_id, m.capacidad, m.barra_id, m.canal, m.cortesia, m.updated_at,
  m.reservada_at, m.reserva_vence_at, m.pagada_at, m.verificado_at,
  m.pago_verificado,
  coalesce(impl.ve_registro(m.evento_id, m.vendido_por), false) as mia,
  case when coalesce(impl.ve_plata(m.evento_id, m.vendido_por), false) then m.precio end          as precio,
  case when coalesce(impl.ve_registro(m.evento_id, m.vendido_por), false) then m.vendido_por end  as vendido_por,
  case when coalesce(impl.ve_registro(m.evento_id, m.vendido_por), false) then m.cliente end      as cliente,
  case when coalesce(impl.ve_registro(m.evento_id, m.vendido_por), false) then m.cliente_id end   as cliente_id,
  case when coalesce(impl.ve_plata(m.evento_id, m.vendido_por), false) then m.metodo_pago end     as metodo_pago,
  case when coalesce(impl.ve_plata(m.evento_id, m.vendido_por), false) then m.comprobante_url end as comprobante_url,
  case when coalesce(impl.ve_plata(m.evento_id, m.vendido_por), false) then m.pagada_por end      as pagada_por,
  case when coalesce(impl.ve_registro(m.evento_id, m.vendido_por), false) then m.cargada_por end  as cargada_por,
  case when coalesce(impl.ve_registro(m.evento_id, m.vendido_por), false) then m.verificado_por end as verificado_por
from public.mesas m
where rol_en('evento', m.evento_id) is not null;

-- La vista se vuelve a crear, así que los permisos se vuelven a poner: sólo
-- lectura, como quedó en 20261105090000.
revoke all on public.mesas_detalle from authenticated, anon, public;
grant select on public.mesas_detalle to authenticated;

comment on view public.mesas_detalle is
  'Mesas con el plano completo para todos y los datos de venta solo para quien corresponde. La app lee de aca, no de mesas.';
