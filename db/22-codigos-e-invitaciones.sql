-- SEGURIDAD (5/…) · códigos de entrada e invitaciones difíciles de adivinar.
--
-- Antes: 6 caracteres hexadecimales (16,7 millones de combinaciones) sacados
-- de md5(random()), que no es un generador criptográfico. Tanto para el QR
-- de las entradas como para el link de invitación de un team.
--
-- Ahora:
--   · entradas e invitados nuevos: 10 caracteres de un alfabeto de 30 sin
--     letras confundibles (≈ 5,9 × 10^14), generados con gen_random_bytes.
--     El formato del QR no cambia (EVT:<evento>:<código>): la web y la app
--     los leen igual, y se pueden seguir tipeando a mano.
--   · invitaciones de team: 32 hexadecimales (128 bits), con vencimiento
--     opcional (teams.invite_expira).
--   · la puerta corta a quien prueba códigos al azar (19-rpc-guardas.sql).
--
-- MIGRACIÓN: los códigos ya emitidos NO se tocan: siguen valiendo hasta que
-- termine su evento. Las invitaciones viejas sí se renuevan acá: son links
-- permanentes y adivinables, y regenerarlas solo obliga a compartir el link
-- nuevo.
-- Re-ejecutable.

create or replace function gen_code_evento(p_evento uuid)
returns text language plpgsql volatile
as $$
declare
  alfabeto constant text := 'ABCDEFGHJKMNPQRSTVWXYZ23456789';   -- sin I, L, O, U, 0, 1
  b bytea; c text;
begin
  loop
    b := extensions.gen_random_bytes(10);
    c := '';
    for i in 0..9 loop
      c := c || substr(alfabeto, 1 + get_byte(b, i) % 30, 1);
    end loop;
    exit when not exists (select 1 from entradas where evento_id = p_evento and code = c)
          and not exists (select 1 from registros r join lista_tipos lt on lt.id = r.lista_tipo_id
                           where lt.evento_id = p_evento and r.code = c);
  end loop;
  return c;
end;
$$;
revoke execute on function gen_code_evento(uuid) from public, anon, authenticated;

alter table teams add column if not exists invite_expira timestamptz;
alter table teams alter column invite_code
  set default encode(extensions.gen_random_bytes(16), 'hex');
update teams set invite_code = encode(extensions.gen_random_bytes(16), 'hex')
 where length(invite_code) < 32;

/* Límite de intentos para endpoints sin sesión (registro por invitación).
   Lo usa la Edge Function crear-usuario con la service key. */
create table if not exists rate_limit (
  id    bigint generated always as identity primary key,
  clave text not null,
  at    timestamptz not null default now()
);
create index if not exists rate_limit_clave_idx on rate_limit (clave, at desc);
alter table rate_limit enable row level security;   -- sin políticas: solo servicio
