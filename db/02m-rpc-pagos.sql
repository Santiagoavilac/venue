-- RPCs de PAGOS · crear_pago, estado_pago, adjuntar_comprobante.
--
-- ETAPA 1: paridad. Nada de mejoras acá.
--
-- REGLA DURA: ninguna se ejecutó contra el origen. Evidencia (2026-08-20,
-- 96 pagos reales): estados pendiente→pagado→verificado; verificado_por y
-- verificado_at están seteados SOLO en los verificados (el único
-- verificador real es el admin) y en cero pagos pendientes/pagados ⇒
-- verificar los setea y volver atrás los limpia; todos los pagos los
-- crearon rrpps y nacen 'pendiente' (la UI lo dice literal); montos
-- numeric (hay 2 con decimales); nro_operacion y comprobante opcionales.
--
-- SUPUESTOS: textos de error; que estado_pago es solo-admin (la UI solo
-- se lo muestra al admin y el único verificador real es admin) y que
-- adjuntar_comprobante exige dueño-o-admin y estado no verificado (regla
-- visible de la UI: puedeAdj).


/* crear_pago(p_evento, p_monto, p_concepto, p_nro, p_comprobante) -> void
 * Nace 'pendiente', a nombre de quien llama. */
create or replace function crear_pago(
  p_evento uuid, p_monto numeric, p_concepto text,
  p_nro text default null, p_comprobante text default null)
returns void
language plpgsql
volatile
security definer
set search_path = public
as $$
begin
  if not exists (select 1 from eventos where id = p_evento) then
    raise exception 'Evento no encontrado';                       -- TEXTO SUPUESTO
  end if;
  if p_monto is null or p_monto <= 0 then
    raise exception 'Monto inválido';                              -- TEXTO SUPUESTO
  end if;
  insert into pagos (id, evento_id, rrpp_id, monto, concepto, estado,
                     nro_operacion, comprobante_url, created_at)
  values (gen_random_uuid(), p_evento, auth.uid(), p_monto,
          coalesce(nullif(trim(p_concepto), ''), 'Pago'), 'pendiente',
          nullif(trim(coalesce(p_nro, '')), ''), p_comprobante, now());
end;
$$;


/* estado_pago(p_pago, p_estado) -> void
 * Solo el admin mueve estados. 'verificado' deja constancia de quién y
 * cuándo; volver a 'pagado'/'pendiente' la limpia (ningún pago real no
 * verificado tiene esos campos). */
create or replace function estado_pago(p_pago uuid, p_estado text)
returns void
language plpgsql
volatile
security definer
set search_path = public
as $$
declare v_rol text;
begin
  if p_estado not in ('pendiente', 'pagado', 'verificado') then
    raise exception 'Estado inválido';                             -- TEXTO SUPUESTO
  end if;
  if not exists (select 1 from pagos where id = p_pago) then
    raise exception 'Pago no encontrado';                          -- TEXTO SUPUESTO
  end if;
  select rol into v_rol from profiles where id = auth.uid();
  if v_rol is distinct from 'admin' then
    raise exception 'Solo el admin puede cambiar el estado de un pago';  -- TEXTO SUPUESTO
  end if;
  update pagos set
    estado = p_estado,
    verificado_por = case when p_estado = 'verificado' then auth.uid() end,
    verificado_at  = case when p_estado = 'verificado' then now() end
  where id = p_pago;
end;
$$;


/* adjuntar_comprobante(p_pago, p_url) -> void
 * Dueño del pago o admin, mientras no esté verificado (regla de la UI). */
create or replace function adjuntar_comprobante(p_pago uuid, p_url text)
returns void
language plpgsql
volatile
security definer
set search_path = public
as $$
declare
  pg pagos%rowtype;
  v_rol text;
begin
  select * into pg from pagos where id = p_pago;
  if not found then
    raise exception 'Pago no encontrado';                          -- TEXTO SUPUESTO
  end if;
  select rol into v_rol from profiles where id = auth.uid();
  if v_rol is distinct from 'admin' and pg.rrpp_id is distinct from auth.uid() then
    raise exception 'No podés adjuntar a este pago';               -- TEXTO SUPUESTO
  end if;
  if pg.estado = 'verificado' then
    raise exception 'El pago ya está verificado';                  -- TEXTO SUPUESTO
  end if;
  update pagos set comprobante_url = p_url where id = p_pago;
end;
$$;
