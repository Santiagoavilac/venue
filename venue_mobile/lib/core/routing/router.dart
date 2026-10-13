import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/authentication/data/sesion.dart';
import '../../features/authentication/ui/login_screen.dart';
import '../../features/clubs/data/clubs.dart';
import '../../features/clubs/ui/selector_club_screen.dart';
import '../../features/dashboard/ui/inicio_shell.dart';

abstract final class Rutas {
  static const login = '/login';
  static const clubs = '/boliches';
  static const inicio = '/';
}

/// A dónde tiene que estar la persona según su sesión y su boliche.
/// Función pura para poder probarla sin widgets.
String destinoPara({required bool conSesion, required bool conClub}) {
  if (!conSesion) return Rutas.login;
  if (!conClub) return Rutas.clubs;
  return Rutas.inicio;
}

final routerProvider = Provider<GoRouter>((ref) {
  final cambio = ValueNotifier(0);
  ref.onDispose(cambio.dispose);
  ref.listen(usuarioIdProvider, (_, _) => cambio.value++);
  ref.listen(clubActivoIdProvider, (_, _) => cambio.value++);

  // Con un solo boliche no hay nada que elegir: se entra directo.
  ref.listen(clubsProvider, (_, lista) {
    final l = lista.value;
    if (l != null && l.length == 1 && ref.read(clubActivoIdProvider) == null) {
      ref.read(clubActivoIdProvider.notifier).elegir(l.first.id);
    }
  });

  return GoRouter(
    initialLocation: Rutas.inicio,
    refreshListenable: cambio,
    redirect: (context, state) {
      final destino = destinoPara(
        conSesion: ref.read(usuarioIdProvider) != null,
        conClub: ref.read(clubActivoIdProvider) != null,
      );
      return state.matchedLocation == destino ? null : destino;
    },
    routes: [
      GoRoute(path: Rutas.login, builder: (_, _) => const LoginScreen()),
      GoRoute(path: Rutas.clubs, builder: (_, _) => const SelectorClubScreen()),
      GoRoute(path: Rutas.inicio, builder: (_, _) => const InicioShell()),
    ],
  );
});
