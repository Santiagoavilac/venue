-- Que cada persona pueda borrar su propia cuenta de VENUE.
--
-- La App Store lo exige cuando la app permite crear cuentas (5.1.1(v)), y
-- VENUE permite tres altas distintas: correo con contraseña, Google/Apple y
-- enlace de invitación. Hasta ahora sólo se podía cerrar sesión, que no
-- alcanza.
--
-- Reusa impl.eliminar_usuario, que ya decide entre borrar o archivar según
-- haya actividad. La diferencia acá es que, aunque el perfil quede archivado
-- por contabilidad del boliche, los datos personales se van igual y el acceso
-- se corta de verdad: se borra el usuario de auth.
create or replace function public.venue_eliminar_mi_cuenta()
 returns jsonb
 language plpgsql
 security definer
 set search_path to 'public'
as $function$
declare v_uid uuid := auth.uid(); v_modo text;
begin
  if v_uid is null then
    raise exception 'Iniciá sesión.' using errcode = '28000';
  end if;

  -- el dueño de un boliche no puede desaparecer y dejarlo sin administrador
  if exists (select 1 from profiles where id = v_uid and admin_principal) then
    raise exception 'Sos el administrador principal de un boliche. Pasale la administración a otra persona antes de borrar tu cuenta.'
      using errcode = '42501';
  end if;

  if not exists (select 1 from profiles where id = v_uid) then
    delete from auth.users where id = v_uid;
    return jsonb_build_object('modo', 'eliminado');
  end if;

  v_modo := impl.eliminar_usuario(v_uid) ->> 'modo';

  -- archivado = el perfil queda para la contabilidad del evento, pero sin
  -- nada que identifique a la persona
  if v_modo = 'archivado' then
    update profiles set
      nombre = 'Cuenta eliminada',
      foto_url = null,
      ref_code = null,
      clubs = '{}',
      team_id = null,
      puede_tickear = false
    where id = v_uid;
    delete from club_membership where user_id = v_uid;
    delete from telefono_usuario where user_id = v_uid;
    delete from cupo_rrpp where user_id = v_uid;
    delete from cupo_permanente where user_id = v_uid;
    delete from aviso_visto where user_id = v_uid;
  end if;

  -- sin usuario de auth no se puede volver a entrar
  delete from auth.users where id = v_uid;
  return jsonb_build_object('modo', v_modo);
end;
$function$;

revoke all on function public.venue_eliminar_mi_cuenta() from public, anon;
grant execute on function public.venue_eliminar_mi_cuenta() to authenticated;

comment on function public.venue_eliminar_mi_cuenta() is
  'Borrado de la propia cuenta de VENUE. Exigido por App Store 5.1.1(v).';
