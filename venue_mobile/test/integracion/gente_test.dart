import 'package:flutter_test/flutter_test.dart';
import 'package:supabase/supabase.dart';
import 'package:venue_mobile/core/config/env.dart';
import 'package:venue_mobile/features/authentication/data/sesion.dart';
import 'package:venue_mobile/features/teams/data/gente.dart';

import 'demo.dart';

final sufijo = DateTime.now().millisecondsSinceEpoch.toString().substring(6);

void main() {
  late SupabaseClient superadmin, admin, adminN, jefe, rrpp;

  setUpAll(() async {
    if (saltear != null) return;
    superadmin = await sesionDe('superadmin');
    admin = await sesionDe('admin.aurora');
    adminN = await sesionDe('admin.nebula');
    jefe = await sesionDe('jefe.aurora');
    rrpp = await sesionDe('rrpp.aurora');
  });

  test('el jefe suma un relacionador, lo pausa y le cambia la clave', () async {
    final r = GenteRepository(jefe);
    final u = await r.crear(
        usuario: 'T$sufijo.rr', nombre: 'Prueba Jefe App', clave: 'secreta1',
        rol: 'admin'); // aunque pida admin, el servidor lo crea rrpp de SU team
    expect(u, 't$sufijo.rr');
    final nuevo = (await r.miTeam('aurora')).firstWhere((x) => x.usuario == u);
    expect(nuevo.activo, isTrue);
    final fila = Usuario.desde(await jefe.from('profiles')
        .select('id, usuario, nombre, rol, activo, team_id, clubs, admin_principal, puede_tickear')
        .eq('id', nuevo.id).single());
    expect(fila.rol, 'rrpp');
    expect(fila.clubs, ['aurora']);

    await r.activar(nuevo.id, false);
    expect((await r.miTeam('aurora')).firstWhere((x) => x.id == nuevo.id).activo, isFalse);
    await r.activar(nuevo.id, true);

    await r.resetearClave(nuevo.id, 'otraclave9');
    final sb = SupabaseClient(Env.supabaseUrl, Env.supabaseAnonKey);
    await sb.auth.signInWithPassword(email: AuthRepository.emailDe(u), password: 'otraclave9');
    expect(await sb.rpc('rol_en_club', params: {'p_club': 'aurora'}), 'rrpp');

    // el jefe no le cambia el rol ni lo saca de su team
    await expectLater(jefe.from('profiles').update({'rol': 'jefe'}).eq('id', nuevo.id),
        throwsA(isA<PostgrestException>()));
    expect(await GenteRepository(admin).eliminar(nuevo.id), 'eliminado');
  }, skip: saltear);

  test('el admin crea, edita y elimina gente de SU boliche', () async {
    final r = GenteRepository(admin);
    final u = await r.crear(
        usuario: 't$sufijo.po', nombre: 'Prueba Portero App', clave: 'secreta1',
        rol: 'portero', clubs: ['aurora']);
    var x = (await r.usuarios('aurora')).firstWhere((p) => p.usuario == u);
    expect(x.rol, 'portero');
    expect(x.clubs, ['aurora']);
    expect(x.teamId, isNull);

    await r.editar(x.id, nombre: 'Prueba Caja App', rol: 'caja', clubs: ['aurora']);
    x = (await r.usuarios('aurora')).firstWhere((p) => p.id == x.id);
    expect((x.nombre, x.rol), ('Prueba Caja App', 'caja'));

    // no puede nombrarlo admin, ni mandarlo a un boliche que no administra
    await expectLater(r.editar(x.id, nombre: x.nombre, rol: 'admin', clubs: ['aurora']),
        throwsA(isA<PostgrestException>()));
    await expectLater(r.editar(x.id, nombre: x.nombre, rol: 'caja', clubs: ['aurora', 'nebula']),
        throwsA(isA<PostgrestException>()));
    // el admin de otro boliche no lo toca
    await expectLater(GenteRepository(adminN).resetearClave(x.id, 'pirata12'),
        throwsA(isA<RechazoDelServidor>()));
    await expectLater(GenteRepository(adminN).eliminar(x.id), throwsA(isA<PostgrestException>()));
    // ni lo ve: no comparten boliche
    expect((await GenteRepository(adminN).usuarios('aurora')).any((p) => p.id == x.id), isFalse);

    expect(await r.eliminar(x.id), 'eliminado');
    expect((await r.usuarios('aurora')).any((p) => p.id == x.id), isFalse);
  }, skip: saltear);

  test('crear administradores es de la plataforma', () async {
    await expectLater(
        GenteRepository(admin).crear(
            usuario: 't$sufijo.ad', nombre: 'Pirata', clave: 'secreta1', rol: 'admin'),
        throwsA(isA<RechazoDelServidor>()));
    await expectLater(
        GenteRepository(rrpp).crear(usuario: 't$sufijo.xx', nombre: 'Pirata', clave: 'secreta1'),
        throwsA(isA<RechazoDelServidor>()));
    expect(await GenteRepository(superadmin).soyDePlataforma(), isTrue);
    expect(await GenteRepository(admin).soyDePlataforma(), isFalse);
  }, skip: saltear);

  test('la cuenta principal no la modifica otro admin', () async {
    final principal = superadmin.auth.currentUser!.id;
    await expectLater(GenteRepository(admin).resetearClave(principal, 'pirata12'),
        throwsA(isA<RechazoDelServidor>()));
    await expectLater(GenteRepository(admin).eliminar(principal),
        throwsA(isA<PostgrestException>()));
  }, skip: saltear);

  test('rol distinto en cada boliche: membresías', () async {
    final r = GenteRepository(superadmin);
    final u = await r.crear(
        usuario: 't$sufijo.mb', nombre: 'Prueba Dos Boliches', clave: 'secreta1',
        rol: 'rrpp', clubs: ['aurora']);
    final x = (await r.usuarios('aurora')).firstWhere((p) => p.usuario == u);
    await r.editar(x.id, nombre: x.nombre, rol: 'rrpp', clubs: ['aurora', 'nebula'], porBoliche: [
      const Membresia(clubId: 'aurora', rol: 'rrpp'),
      const Membresia(clubId: 'nebula', rol: 'portero'),
    ]);
    expect((await r.membresias(x.id)).map((m) => '${m.clubId}:${m.rol}').toSet(),
        {'aurora:rrpp', 'nebula:portero'});
    final sb = SupabaseClient(Env.supabaseUrl, Env.supabaseAnonKey);
    await sb.auth.signInWithPassword(email: AuthRepository.emailDe(u), password: 'secreta1');
    expect(await sb.rpc('rol_en_club', params: {'p_club': 'aurora'}), 'rrpp');
    expect(await sb.rpc('rol_en_club', params: {'p_club': 'nebula'}), 'portero');
    // no se puede dar a sí mismo otro rol
    await sb.from('club_membership').update({'rol': 'admin'})
        .eq('user_id', x.id).eq('club_id', 'nebula'); // RLS: no toca ninguna fila
    expect(await sb.rpc('rol_en_club', params: {'p_club': 'nebula'}), 'portero');
    // volver a un solo boliche limpia las membresías
    await r.editar(x.id, nombre: x.nombre, rol: 'rrpp', clubs: ['aurora']);
    expect(await r.membresias(x.id), isEmpty);
    await r.eliminar(x.id);
  }, skip: saltear);

  test('teams: el admin los crea, edita y elimina moviendo a su gente', () async {
    final r = GenteRepository(admin);
    for (final t in (await r.teams('aurora')).where((t) => t.nombre.startsWith('ZZ'))) {
      await r.eliminarTeam(t.id);
    }
    await r.crearTeam('ZZ Team Prueba', 'aurora');
    var t = (await r.teams('aurora')).firstWhere((t) => t.nombre == 'ZZ Team Prueba');
    expect(t.invitacion.length, 32);
    await r.editarTeam(t.id, 'ZZ Team Editado', ['aurora']);
    t = (await r.teams('aurora')).firstWhere((x) => x.id == t.id);
    expect(t.nombre, 'ZZ Team Editado');
    await expectLater(GenteRepository(rrpp).crearTeam('pirata', 'aurora'),
        throwsA(isA<PostgrestException>()));
    await expectLater(GenteRepository(adminN).eliminarTeam(t.id),
        throwsA(isA<PostgrestException>()));
    expect(await r.eliminarTeam(t.id), 0);
    expect((await r.teams('aurora')).any((x) => x.id == t.id), isFalse);
  }, skip: saltear);

  test('boliches: los crea y edita solo la plataforma', () async {
    final r = GenteRepository(superadmin);
    final id = 'zz-$sufijo';
    await r.crearClub(id: id, nombre: 'ZZ Boliche Prueba', primario: '#112233',
        secundario: '#445566', acento: '#778899');
    await r.editarClub(id, nombre: 'ZZ Editado', subtitulo: 'Centro', primario: '#AA0000',
        secundario: '#445566', acento: '#778899');
    final fila = await superadmin.from('clubs').select().eq('id', id).single();
    expect((fila['nombre'], fila['color_primario'], fila['subtitulo']),
        ('ZZ Editado', '#AA0000', 'Centro'));
    // un admin de boliche no crea locales ni ve este
    await expectLater(
        GenteRepository(admin).crearClub(id: 'zz-pirata', nombre: 'x', primario: '#112233',
            secundario: '#112233', acento: '#112233'),
        throwsA(isA<PostgrestException>()));
    expect(await admin.from('clubs').select('id').eq('id', id), isEmpty);
    await r.desactivarClub(id);
    expect((await superadmin.from('clubs').select('activo').eq('id', id).single())['activo'], false);
    await superadmin.from('clubs').delete().eq('id', id);
  }, skip: saltear);
}
