-- La entrada en Apple Wallet y en Google Wallet.
--
-- El pase se arma desde el correo, que se abre fuera de la app y sin sesión.
-- Por eso el enlace lleva el código de la entrada y una firma: la Edge
-- Function comprueba la firma antes de mirar nada. Sin firma, el código solo
-- no abre nada.
--
-- Esta función es la única parte que vive en la base: junta lo que el pase
-- necesita y nada más. No devuelve el id del cliente ni su correo: el pase
-- lleva el nombre, y con eso alcanza para la puerta.
create or replace function public.wallet_entrada(p_code text)
returns jsonb
language plpgsql stable security definer set search_path = public, pg_temp
as $$
declare x entradas; e eventos; c clubs; v_cliente aftr_clientes;
begin
  select * into x from entradas where code = p_code;
  if not found then return null; end if;
  -- una entrada anulada, usada o reemplazada no se lleva a la billetera
  if x.estado <> 'valida' then return null; end if;

  select * into e from eventos where id = x.evento_id;
  if not found then return null; end if;
  select * into c from clubs where id = e.club_id;
  select * into v_cliente from aftr_clientes where user_id = x.cliente_id;

  return jsonb_build_object(
    'codigo', x.code,
    'serie', x.id,
    'evento', e.nombre,
    'club', c.nombre,
    'fecha', to_char(e.fecha, 'DD/MM/YYYY'),
    'hora', to_char(e.hora_inicio, 'HH24:MI'),
    -- el momento exacto, que es lo que hace que el pase aparezca solo en la
    -- pantalla bloqueada un rato antes
    'inicio', to_char(impl.aftr_inicio(e.fecha, e.hora_inicio) at time zone 'UTC',
                      'YYYY-MM-DD"T"HH24:MI:SS"Z"'),
    'persona', nullif(trim(coalesce(v_cliente.nombre, x.cliente) || ' '
                           || coalesce(v_cliente.apellido, '')), ''),
    'arte', e.flyer_url,
    -- y dónde queda, para que aparezca al llegar
    'lat', c.lat, 'lng', c.lng);
end $$;
revoke all on function public.wallet_entrada(text) from public, anon, authenticated;

notify pgrst,'reload schema';
