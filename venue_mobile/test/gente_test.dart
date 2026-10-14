import 'package:flutter_test/flutter_test.dart';
import 'package:venue_mobile/features/teams/data/gente.dart';

void main() {
  test('identificador de boliche y colores válidos', () {
    expect(slugValido('aurora-club'), isTrue);
    expect(slugValido('a'), isFalse);              // muy corto
    expect(slugValido('Aurora'), isFalse);         // mayúsculas
    expect(slugValido('-aurora'), isFalse);
    expect(slugValido('aurora club'), isFalse);
    expect(colorValido('#7C3AED'), isTrue);
    expect(colorValido('7C3AED'), isFalse);
    expect(colorValido('#7C3'), isFalse);
  });

  test('invitación de team: link que abre la app y código de respaldo', () {
    final t = TeamInfo.desde({
      'id': 't', 'nombre': 'Team Norte', 'clubs': ['aurora'],
      'invite_code': 'ab12cd34ab12cd34ab12cd34ab12cd34',
    });
    expect(t.link, 'venue://app/registro?invite=ab12cd34ab12cd34ab12cd34ab12cd34');
    final m = mensajeDeInvitacion(t, 'Aurora Club');
    expect(m, contains(t.link));
    expect(m, contains('Team Norte'));
    expect(m, contains(t.invitacion));
  });

  test('usuario desde la base', () {
    final u = Usuario.desde({
      'id': '1', 'usuario': 'pablo', 'nombre': 'Pablo', 'rol': 'portero',
      'activo': true, 'clubs': ['aurora'], 'admin_principal': false,
    });
    expect((u.rolEtiqueta, u.activo), ('Seguridad', true));
    expect(u.clubs, ['aurora']);
  });
}
