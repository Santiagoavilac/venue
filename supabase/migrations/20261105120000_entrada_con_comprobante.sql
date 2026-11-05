-- La entrada que se vende a mano lleva el comprobante del pago.
--
-- No todos los boliches venden por AFTR. En los que no -BT, por ejemplo- el
-- cliente le paga al relacionador por fuera, le manda la foto del pago, y el
-- relacionador genera la entrada. Hasta hoy esa foto no se guardaba en ningun
-- lado: la entrada quedaba sin respaldo y, cuando el jefe rendia al boliche,
-- la unica prueba era la palabra de cada uno.
--
-- Ahora la entrada guarda la foto del pago y como pago. El archivo va al
-- bucket de comprobantes que ya usa Pagos, en la carpeta de quien vende, y la
-- funcion verifica que sea de ahi: si no, cualquiera podria colgarle a una
-- entrada la URL de otra cosa.
--
-- Los dos parametros son opcionales, asi que las apps ya publicadas siguen
-- llamando igual.
alter table public.entradas add column if not exists comprobante_url text;
alter table public.entradas add column if not exists metodo_pago text;

comment on column public.entradas.comprobante_url is
  'Foto del pago cuando la entrada se vendio por fuera de AFTR. Vive en el bucket comprobantes.';

drop function if exists public.generar_entrada(uuid, text, uuid);
drop function if exists impl.generar_entrada(uuid, text, uuid);

CREATE OR REPLACE FUNCTION impl.generar_entrada(p_evento uuid, p_cliente text, p_mesa uuid DEFAULT NULL::uuid,
  p_comprobante_url text DEFAULT NULL, p_metodo text DEFAULT NULL)
 RETURNS json
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  e eventos%rowtype;
  f evento_fase%rowtype;
  fila entradas%rowtype;
  v_precio numeric;
  v_fase uuid;
  v_team uuid;
  v_vendidas int;
  v_cupo_team int;
begin
  select * into e from eventos where id = p_evento;
  if not found then
    raise exception 'Evento no encontrado';
  end if;

  if p_mesa is not null then
    if not exists (select 1 from mesas m where m.id = p_mesa and m.evento_id = p_evento) then
      raise exception 'Mesa no encontrada';
    end if;
    v_precio := 0; v_fase := null;
  elsif e.venta_por_fases then
    -- fase vigente, con lock: el cupo se decide en serie
    select * into f
      from evento_fase
     where evento_id = p_evento
       and activo
       and (desde is null or now() >= desde)
       and (hasta is null or now() <= hasta)
       and (cupo is null or cupo > (select count(*) from impl.entradas_vigentes x where x.fase_id = evento_fase.id))
     order by orden
     limit 1
     for update;
    if not found then
      raise exception 'No hay ninguna fase de venta abierta';   -- TEXTO SUPUESTO
    end if;

    -- cupo por team dentro de la fase (todos los cupos reales observados
    -- son null: esta rama nunca corrió con datos reales — tabla deducida)
    select coalesce(cm.team_id,
             case when tb.id is not null
                       and (p.rol = 'admin' or tb.clubs is null
                            or coalesce(array_length(tb.clubs, 1), 0) = 0
                            or e.club_id = any(tb.clubs))
                  then p.team_id end)
      into v_team
      from profiles p
      left join club_membership cm on cm.user_id = p.id and cm.club_id = e.club_id
      left join teams tb on tb.id = p.team_id
     where p.id = auth.uid();
    select fc.cupo into v_cupo_team from fase_cupo_team fc
     where fc.fase_id = f.id and fc.team_id = v_team;
    if v_cupo_team is not null then
      select count(*) into v_vendidas
        from impl.entradas_vigentes x
        join profiles p2 on p2.id = x.rrpp_id
        left join club_membership cm2 on cm2.user_id = p2.id and cm2.club_id = e.club_id
        left join teams tb2 on tb2.id = p2.team_id
       where x.fase_id = f.id
         and coalesce(cm2.team_id,
               case when tb2.id is not null
                         and (p2.rol = 'admin' or tb2.clubs is null
                              or coalesce(array_length(tb2.clubs, 1), 0) = 0
                              or e.club_id = any(tb2.clubs))
                    then p2.team_id end) = v_team;
      if v_vendidas >= v_cupo_team then
        raise exception 'CUPO AGOTADO: tu team ya vendió sus % de esta fase', v_cupo_team;  -- TEXTO SUPUESTO
      end if;
    end if;

    v_precio := f.precio; v_fase := f.id;
  else
    v_precio := e.precio_manilla; v_fase := null;
  end if;

  -- El comprobante es la foto del pago que mandó el cliente. Tiene que ser
  -- un archivo del bucket de comprobantes y de la carpeta de quien vende: si
  -- no, cualquiera podría colgarle a una entrada la URL de otra cosa.
  if p_comprobante_url is not null then
    if p_comprobante_url !~ ('/storage/v1/object/(public|sign)/comprobantes/' || auth.uid()::text || '/') then
      raise exception 'El comprobante tiene que ser una imagen tuya.' using errcode = '42501';
    end if;
    if length(p_comprobante_url) > 500 then
      raise exception 'La referencia del comprobante es demasiado larga.';
    end if;
  end if;
  if p_metodo is not null and length(trim(p_metodo)) > 40 then
    raise exception 'El método de pago es demasiado largo.';
  end if;

  insert into entradas (id, evento_id, code, cliente, rrpp_id, precio, estado, created_at, mesa_id, fase_id,
                        comprobante_url, metodo_pago)
  values (gen_random_uuid(), p_evento, gen_code_evento(p_evento), trim(p_cliente), auth.uid(),
          v_precio, 'valida', now(), p_mesa, v_fase,
          p_comprobante_url, nullif(trim(coalesce(p_metodo, '')), ''))
  returning * into fila;
  return to_jsonb(fila);
end;
$function$;


-- La guarda de public, con la misma forma que genera db/19: exige rol en el
-- evento y delega. El comentario es el que busca el chequeo de cobertura.
create or replace function public.generar_entrada(p_evento uuid, p_cliente text, p_mesa uuid default null,
  p_comprobante_url text default null, p_metodo text default null)
returns json
language plpgsql
volatile
security definer
set search_path = public
as $guarda$
#variable_conflict use_column
declare v_rol text;
begin
  v_rol := impl.exigir(impl.club_de('evento', p_evento), '{admin,jefe,rrpp}'::text[]);
  return impl.generar_entrada(p_evento, p_cliente, p_mesa, p_comprobante_url, p_metodo);
end;
$guarda$;
comment on function public.generar_entrada(uuid, text, uuid, text, text) is 'venue:guarda';
revoke all on function public.generar_entrada(uuid, text, uuid, text, text) from public, anon;
grant execute on function public.generar_entrada(uuid, text, uuid, text, text) to authenticated, service_role;
notify pgrst,'reload schema';
