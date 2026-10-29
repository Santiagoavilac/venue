import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/authentication/data/sesion.dart';
import '../../features/authentication/ui/bienvenida_screen.dart';
import '../../features/authentication/ui/login_screen.dart';
import '../../features/authentication/ui/relacionadores_screen.dart';
import '../../features/clubs/data/clubs.dart';
import '../../features/clubs/ui/selector_club_screen.dart';
import '../../features/dashboard/ui/inicio_shell.dart';
import '../../features/rrpp/data/rrpp.dart';
import '../../features/rrpp/ui/rrpp_shell.dart';

abstract final class Rutas {
  /// Bienvenida: elegir Boliches o Relacionadores.
  static const login = '/login';
  static const loginBoliche = '/login/boliche';
  static const relacionadores = '/relacionadores';
  static const completar = '/completar';

  /// Espacio personal del relacionador (todos sus boliches).
  static const rel = '/rel';

  /// Enlaces de invitación: el nuevo (unirse?code=) y el viejo de los teams
  /// (registro?invite=). Ninguno crea cuentas: llevan a pedir sumarse.
  static const unirse = '/unirse';
  static const registro = '/registro';
  static const clubs = '/boliches';
  static const inicio = '/';
}

const _sinSesion = {Rutas.login, Rutas.loginBoliche, Rutas.relacionadores};

/// A dónde tiene que estar la persona según su sesión, su perfil y su
/// boliche. Función pura para poder probarla sin widgets.
String destinoPara({
  required bool conSesion,
  required bool conClub,
  bool sinPerfil = false,
  bool esRelacionador = false,
}) {
  if (!conSesion) return Rutas.login;
  if (sinPerfil) return Rutas.completar;
  if (esRelacionador) return Rutas.rel;
  if (!conClub) return Rutas.clubs;
  return Rutas.inicio;
}

final routerProvider = Provider<GoRouter>((ref) {
  final cambio = ValueNotifier(0);
  ref.onDispose(cambio.dispose);
  ref.listen(usuarioIdProvider, (_, _) => cambio.value++);
  ref.listen(clubActivoIdProvider, (_, _) => cambio.value++);
  ref.listen(perfilProvider, (_, _) => cambio.value++);

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
      final conSesion = ref.read(usuarioIdProvider) != null;
      final loc = state.matchedLocation;
      // un enlace de invitación guarda el código; sin sesión, primero entrar
      if (loc == Rutas.unirse || loc == Rutas.registro) {
        final q = state.uri.queryParameters;
        final code = q['code'] ?? q['invite'];
        if (code != null && code.isNotEmpty) {
          ref.read(unirsePendienteProvider.notifier).poner(codigoDeUnion(code));
        }
        if (!conSesion) {
          return code == null ? Rutas.relacionadores : '${Rutas.relacionadores}?code=${codigoDeUnion(code)}';
        }
      }
      if (!conSesion) return _sinSesion.contains(loc) ? null : Rutas.login;
      final perfil = ref.read(perfilProvider);
      if (perfil.isLoading && !perfil.hasValue) return null; // se decide cuando llegue
      final p = perfil.value;
      final destino = destinoPara(
        conSesion: true,
        conClub: ref.read(clubActivoIdProvider) != null,
        sinPerfil: p == null,
        esRelacionador: p?.esRelacionador ?? false,
      );
      return loc == destino ? null : destino;
    },
    routes: [
      GoRoute(path: Rutas.login, builder: (_, _) => const BienvenidaScreen()),
      GoRoute(path: Rutas.loginBoliche, builder: (_, _) => const LoginScreen()),
      GoRoute(
        path: Rutas.relacionadores,
        builder: (_, st) => RelacionadoresScreen(codigo: st.uri.queryParameters['code']),
      ),
      GoRoute(path: Rutas.completar, builder: (_, _) => const CompletarCuentaScreen()),
      GoRoute(path: Rutas.rel, builder: (_, _) => const RrppShell()),
      GoRoute(path: Rutas.unirse, builder: (_, _) => const RrppShell()),
      GoRoute(path: Rutas.registro, builder: (_, _) => const RrppShell()),
      GoRoute(path: Rutas.clubs, builder: (_, _) => const SelectorClubScreen()),
      GoRoute(path: Rutas.inicio, builder: (_, _) => const InicioShell()),
    ],
  );
});
