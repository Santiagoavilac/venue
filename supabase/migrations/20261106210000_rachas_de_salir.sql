-- La racha: cuántas semanas seguidas salió cada uno.
--
-- AFTR no tenía nada que premie volver. Una racha es lo más simple que
-- funciona y no se puede falsear: semanas seguidas en las que la persona
-- ENTRÓ a un evento, medido en la puerta -su entrada escaneada o su lugar en
-- una lista marcado-, no por comprar ni por abrir la app.
--
-- Por semanas y no por noches: la noche es de fin de semana, y una racha de
-- días seguidos se corta siempre el lunes. La semana va de lunes a domingo en
-- hora de Bolivia, que es cuando termina la noche del domingo.
--
-- La racha sigue viva si hay ingreso en la semana en curso o en la anterior:
-- si no, un martes todo el mundo vería su racha en cero hasta el sábado.
--
-- "Los amigos" no son una lista que alguien arma: son las personas con las que
-- de verdad salió. Se saca de lo que ya existe -las entradas que se pasaron
-- entre ellos y las mesas que compartieron-, así que no hay que pedirle a
-- nadie que agregue a nadie, ni hay una pantalla nueva que mantener.

-- ── la semana de una fecha, en Bolivia ────────────────────────────────
create or replace function impl.semana_de(p_at timestamptz) returns date
language sql immutable set search_path = public as $$
  select date_trunc('week', p_at at time zone 'America/La_Paz')::date
$$;

/* Las semanas en las que esta persona entró a algún evento. Una fila por
   semana, de la más nueva a la más vieja. */
create or replace function impl.semanas_saliendo(p_cliente uuid)
returns setof date language sql stable security definer set search_path = public as $$
  select semana from (
    select impl.semana_de(x.used_at) as semana
      from entradas x
     where x.cliente_id = p_cliente and x.used_at is not null
    union
    select impl.semana_de(r.ingreso_at)
      from registros r
     where r.cliente_id = p_cliente and r.ingreso_at is not null
  ) s
  group by semana
  order by semana desc
$$;

/* La racha: semanas seguidas hacia atrás desde la última en la que salió, y
   sólo si esa última es la de ahora o la pasada. */
create or replace function impl.racha(p_cliente uuid)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare v_ahora date := impl.semana_de(now()); s date; v_esperada date; v_n int := 0;
        v_ultima date; v_mejor int := 0; v_corrida int := 0; v_previa date;
begin
  for s in select * from impl.semanas_saliendo(p_cliente) loop
    if v_ultima is null then
      v_ultima := s;
      -- viva sólo si salió esta semana o la pasada
      if s >= v_ahora - 7 then v_n := 1; v_esperada := s - 7; end if;
    elsif v_esperada is not null and s = v_esperada then
      v_n := v_n + 1; v_esperada := s - 7;
    elsif v_esperada is not null then
      v_esperada := null;  -- la racha viva se cortó; se sigue para la mejor
    end if;
    -- la mejor racha histórica, de paso
    if v_previa is null or v_previa - 7 = s then v_corrida := v_corrida + 1;
    else v_corrida := 1; end if;
    if v_corrida > v_mejor then v_mejor := v_corrida; end if;
    v_previa := s;
  end loop;
  return jsonb_build_object(
    'semanas', v_n,
    'viva', v_n > 0,
    'mejor', v_mejor,
    'ultima', v_ultima,
    -- si salió esta semana ya está sumada; si no, le queda hasta el domingo
    'cerrada', v_ultima is not null and v_ultima >= v_ahora);
end $$;

/* Con quién salió de verdad: se pasaron una entrada o compartieron una mesa.
   No hay lista de amigos que alguien tenga que armar. */
create or replace function impl.mi_gente(p_cliente uuid)
returns setof uuid language sql stable security definer set search_path = public as $$
  select otro from (
    select t.para as otro from aftr_transferencias t
      join entradas e on e.id = t.entrada_id
     where t.de = p_cliente
    union
    select t.de from aftr_transferencias t
      join entradas e on e.id = t.entrada_id
     where t.para = p_cliente
    union
    select m2.cliente_id from aftr_mesa_miembros m1
      join aftr_mesa_miembros m2 on m2.mesa_id = m1.mesa_id and m2.cliente_id <> m1.cliente_id
     where m1.cliente_id = p_cliente and m1.estado = 'aceptado' and m2.estado = 'aceptado'
    union
    -- el dueño de la mesa que lo invitó, y los invitados de la suya
    select m.cliente_id from aftr_mesa_miembros mm join mesas m on m.id = mm.mesa_id
     where mm.cliente_id = p_cliente and mm.estado = 'aceptado' and m.cliente_id is not null
    union
    select mm.cliente_id from mesas m join aftr_mesa_miembros mm on mm.mesa_id = m.id
     where m.cliente_id = p_cliente and mm.estado = 'aceptado'
  ) g
  where otro is not null and otro <> p_cliente
    -- a quien bloqueaste no se te muestra, ni vos a quien te bloqueó
    and not exists (select 1 from aftr_bloqueos b
                     where (b.bloqueador_id = p_cliente and b.bloqueado_id = otro)
                        or (b.bloqueador_id = otro and b.bloqueado_id = p_cliente))
  group by otro
$$;

-- ── lo que pide la app ────────────────────────────────────────────────
create or replace function public.aftr_rachas()
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare c aftr_clientes := impl.aftr_yo();
begin
  return jsonb_build_object(
    'mia', impl.racha(c.user_id) || jsonb_build_object(
      'usuario', c.usuario, 'nombre', c.nombre, 'foto', c.foto_url, 'foto_key', c.foto_key),
    'gente', coalesce((select jsonb_agg(x order by (x->>'semanas')::int desc, x->>'nombre')
      from (
        select impl.racha(g.otro) || jsonb_build_object(
                 'usuario', cl.usuario, 'nombre', cl.nombre,
                 'foto', cl.foto_url, 'foto_key', cl.foto_key) as x
          from impl.mi_gente(c.user_id) as g(otro)
          join aftr_clientes cl on cl.user_id = g.otro
         limit 30
      ) y), '[]'::jsonb),
    'ahora', now());
end $$;
revoke all on function public.aftr_rachas() from public, anon;
grant execute on function public.aftr_rachas() to authenticated, service_role;

notify pgrst,'reload schema';
