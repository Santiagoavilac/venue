-- Privacidad entre relacionadores, parte 1: lo que no rompe nada.
--
-- Hoy cualquier relacionador del boliche puede hacer select * sobre mesas y
-- bonos y sacar precios, quién vendió y lo que ganaron otros. La app lo
-- esconde, pero con la propia sesión sale con un curl al endpoint REST.
--
-- No se arregla filtrando filas de mesas: el relacionador necesita el plano
-- completo para saber qué mesa está libre, y la tabla tiene realtime. Lo que
-- se quita son las COLUMNAS de dinero. Eso va en la parte 2, junto con el
-- cambio de la app, porque hoy la app pide select() de todas las columnas y
-- revocarlas ahora dejaría Mesas en blanco para todo el mundo.
--
-- Acá va lo que se puede aplicar sin romper: la vista que la app va a leer, y
-- las dos políticas que sí se pueden cerrar hoy.

-- La vista da el plano completo a todos y los datos de venta sólo a quien
-- corresponde. security_invoker = false para que la vista sí pueda leer las
-- columnas; cada fila pasa igual por ve_registro con la identidad de quien
-- consulta (admin y portero ven todo, el jefe su team, el rrpp lo suyo).
create or replace view public.mesas_detalle
with (security_invoker = false) as
select
  m.id, m.evento_id, m.planta, m.etiqueta, m.categoria, m.x, m.y, m.w, m.h,
  m.team_id, m.estado, m.combo_id, m.combo_qty, m.botellas, m.manillas,
  m.grupo_id, m.capacidad, m.barra_id, m.canal, m.cortesia, m.updated_at,
  m.reservada_at, m.reserva_vence_at, m.pagada_at, m.verificado_at,
  m.pago_verificado,
  coalesce(impl.ve_registro(m.evento_id, m.vendido_por), false) as mia,
  case when coalesce(impl.ve_registro(m.evento_id, m.vendido_por), false) then m.precio end          as precio,
  case when coalesce(impl.ve_registro(m.evento_id, m.vendido_por), false) then m.vendido_por end     as vendido_por,
  case when coalesce(impl.ve_registro(m.evento_id, m.vendido_por), false) then m.cliente end         as cliente,
  case when coalesce(impl.ve_registro(m.evento_id, m.vendido_por), false) then m.cliente_id end      as cliente_id,
  case when coalesce(impl.ve_registro(m.evento_id, m.vendido_por), false) then m.metodo_pago end     as metodo_pago,
  case when coalesce(impl.ve_registro(m.evento_id, m.vendido_por), false) then m.comprobante_url end as comprobante_url,
  case when coalesce(impl.ve_registro(m.evento_id, m.vendido_por), false) then m.pagada_por end      as pagada_por,
  case when coalesce(impl.ve_registro(m.evento_id, m.vendido_por), false) then m.cargada_por end     as cargada_por,
  case when coalesce(impl.ve_registro(m.evento_id, m.vendido_por), false) then m.verificado_por end  as verificado_por
from public.mesas m
where rol_en('evento', m.evento_id) is not null;

grant select on public.mesas_detalle to authenticated;

comment on view public.mesas_detalle is
  'Mesas con el plano completo para todos y los datos de venta solo para quien corresponde. La app lee de aca, no de mesas.';

-- Los bonos de otros: mismo criterio que listas y entradas (db/47, db/49).
drop policy if exists bonos_leer on public.bonos;
create policy bonos_leer on public.bonos for select to authenticated
  using (impl.ve_registro(evento_id, user_id));

-- El reparto de un team lo ven el boliche y ese team, no todos.
drop policy if exists team_reparto_leer on public.team_reparto;
create policy team_reparto_leer on public.team_reparto for select to authenticated
  using (exists (
    select 1 from eventos e
     where e.id = evento_id
       and (rol_en_club(e.club_id) = 'admin'
            or team_id = impl.team_en_club(auth.uid(), e.club_id))));
