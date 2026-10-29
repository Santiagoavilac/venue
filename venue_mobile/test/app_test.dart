import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:venue_mobile/core/networking/supabase.dart';
import 'package:venue_mobile/core/routing/router.dart';
import 'package:venue_mobile/core/theme/venue_theme.dart';
import 'package:venue_mobile/features/access_control/data/resultado.dart';
import 'package:venue_mobile/features/access_control/ui/veredicto_card.dart';
import 'package:venue_mobile/features/authentication/data/sesion.dart';
import 'package:venue_mobile/features/clubs/data/clubs.dart';
import 'package:venue_mobile/features/events/data/eventos.dart';

void main() {
  test('ruta según sesión y boliche', () {
    expect(destinoPara(conSesion: false, conClub: false), Rutas.login);
    expect(destinoPara(conSesion: false, conClub: true), Rutas.login);
    expect(destinoPara(conSesion: true, conClub: false), Rutas.clubs);
    expect(destinoPara(conSesion: true, conClub: true), Rutas.inicio);
  });

  test('ruta: relacionadores a su espacio, cuenta nueva a completar', () {
    expect(destinoPara(conSesion: true, conClub: false, sinPerfil: true), Rutas.completar);
    expect(destinoPara(conSesion: true, conClub: false, esRelacionador: true), Rutas.rel);
    expect(destinoPara(conSesion: true, conClub: true, esRelacionador: true), Rutas.rel);
    expect(destinoPara(conSesion: false, conClub: false, esRelacionador: true), Rutas.login);
  });

  test('quién es relacionador', () {
    expect(const Perfil(id: '1', usuario: 'a', nombre: 'A', activo: true, rol: 'rrpp').esRelacionador, isTrue);
    expect(const Perfil(id: '1', usuario: 'a', nombre: 'A', activo: true, rol: 'jefe').esRelacionador, isTrue);
    expect(const Perfil(id: '1', usuario: 'a', nombre: 'A', activo: true, rol: 'admin').esRelacionador, isFalse);
    expect(const Perfil(id: '1', usuario: 'a', nombre: 'A', activo: true, rol: 'jefe', adminPrincipal: true)
        .esRelacionador, isFalse);
  });

  test('email interno del usuario', () {
    expect(AuthRepository.emailDe('  Mateo.R '), 'mateo.r@plataforma.local');
  });

  test('roles: quién valida ingresos y quién ve eventos', () {
    expect(Rol.values.where((r) => r.validaIngresos), [Rol.admin, Rol.portero]);
    expect(Rol.barra.veEventos, isFalse);
    expect(Rol.caja.veEventos, isFalse);
    expect(Rol.desde('portero'), Rol.portero);
    expect(Rol.desde('inventado'), isNull);
    expect(Rol.desde(null), isNull);
  });

  test('color de marca desde hex; un dato inválido no rompe', () {
    expect(colorDesdeHex('#7C3AED'), const Color(0xFF7C3AED));
    expect(colorDesdeHex('22D3EE'), const Color(0xFF22D3EE));
    expect(colorDesdeHex('#abc'), isNull);
    expect(colorDesdeHex('zzzzzz'), isNull);
    expect(colorDesdeHex(null), isNull);
  });

  test('club desde la fila de la base', () {
    final c = Club.desde({
      'id': 'bowie', 'nombre': 'Bowie', 'inicial': null,
      'color_primario': '#7C3AED', 'color_secundario': 'malo',
    });
    expect(c.inicial, 'B');
    expect(c.primario, const Color(0xFF7C3AED));
    expect(c.secundario, isNull);
  });

  test('evento en curso cruza la medianoche', () {
    final e = Evento.desde({
      'id': 'e1', 'nombre': 'Viernes', 'fecha': '2026-10-16',
      'hora_inicio': '21:00:00', 'hora_fin': '06:00:00', 'estado': 'proximo',
    });
    expect(e.enCurso(DateTime(2026, 10, 16, 20, 59)), isFalse);
    expect(e.enCurso(DateTime(2026, 10, 16, 23, 0)), isTrue);
    expect(e.enCurso(DateTime(2026, 10, 17, 5, 30)), isTrue);
    expect(e.enCurso(DateTime(2026, 10, 17, 6, 1)), isFalse);
    expect(e.fechaCorta, 'vie 16 oct');
  });

  test('un evento cerrado nunca está en curso', () {
    final e = Evento.desde({
      'id': 'e1', 'nombre': 'x', 'fecha': '2026-10-16',
      'hora_inicio': '21:00', 'hora_fin': '06:00', 'estado': 'cerrado',
    });
    expect(e.enCurso(DateTime(2026, 10, 16, 23, 0)), isFalse);
  });

  test('falla de red vs. rechazo del servidor', () {
    expect(esFallaDeRed(const SocketException('sin red')), isTrue);
    expect(esFallaDeRed(const PostgrestException(message: 'No autorizado.', code: '42501')), isFalse);
    expect(mensajeDeError(const PostgrestException(message: 'No autorizado.')), 'No autorizado.');
  });

  testWidgets('la tarjeta muestra el veredicto y el nombre', (t) async {
    await t.pumpWidget(MaterialApp(
      theme: temaVenue(),
      home: const Scaffold(
        body: VeredictoCard(
          resultado: ResultadoEscaneo(
            veredicto: Veredicto.yaIngreso,
            codigo: 'ABC123',
            nombre: 'Carlos Roca',
            tipo: 'Entrada prepagada',
            detalle: 'Ya fue usada. No vuelve a entrar.',
          ),
        ),
      ),
    ));
    expect(find.text('YA INGRESÓ'), findsOneWidget);
    expect(find.text('Carlos Roca'), findsOneWidget);
    expect(colorDeVeredicto(Veredicto.yaIngreso), VenueColors.aviso);
    expect(colorDeVeredicto(Veredicto.pasa), VenueColors.ok);
    expect(colorDeVeredicto(Veredicto.sinConexion), VenueColors.neutro);
  });
}
