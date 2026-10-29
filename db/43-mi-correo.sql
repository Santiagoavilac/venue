-- 43 · Correo propio para entrar
--
-- Las cuentas creadas por el boliche tienen un correo interno
-- (usuario@plataforma.local). Cambiarlo por la vía normal de Supabase manda
-- una confirmación también a ese correo viejo, que nadie recibe. Esta RPC
-- fija el correo real de QUIEN LLAMA (nunca de otro), si ningún otro lo
-- usa. Después la persona entra con ese correo o con su usuario de siempre,
-- y la misma contraseña.
create or replace function public.fijar_mi_correo(p_correo text)
returns text
language plpgsql
security definer
set search_path = public, auth
as $$
declare
  v_uid uuid := auth.uid();
  v_correo text := lower(trim(p_correo));
begin
  if v_uid is null then raise exception 'Iniciá sesión.' using errcode = '28000'; end if;
  if not exists (select 1 from public.profiles where id = v_uid and activo and eliminado_at is null) then
    raise exception 'Tu cuenta no está activa.';
  end if;
  if v_correo !~ '^[^@\s]+@[^@\s]+\.[a-z]{2,}$' then raise exception 'Ese correo no parece válido.'; end if;
  if v_correo like '%@plataforma.local' then raise exception 'Usá tu correo personal.'; end if;
  if exists (select 1 from auth.users where lower(email) = v_correo and id <> v_uid) then
    raise exception 'Ese correo ya lo usa otra cuenta.';
  end if;
  update auth.users
     set email = v_correo, email_confirmed_at = coalesce(email_confirmed_at, now()), updated_at = now()
   where id = v_uid;
  update auth.identities
     set identity_data = identity_data || jsonb_build_object('email', v_correo), updated_at = now()
   where user_id = v_uid and provider = 'email';
  return v_correo;
end;
$$;

revoke all on function public.fijar_mi_correo(text) from public, anon;
grant execute on function public.fijar_mi_correo(text) to authenticated;
