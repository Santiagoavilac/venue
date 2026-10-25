import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../data/modelos.dart';
import '../../features/accesos/accesos_screen.dart';
import '../../features/auth/bienvenida_screen.dart';
import '../../features/auth/login_screen.dart';
import '../../features/cuenta/cuenta_screen.dart';
import '../../features/descubrir/descubrir_screen.dart';
import '../../features/evento/evento_screen.dart';
import '../../features/lugar/lugar_screen.dart';
import '../../features/mapa/mapa_screen.dart';
import '../../features/shell/shell.dart';

/// Pantallas que suben desde abajo (ingreso y bienvenida), como hojas
/// completas.
CustomTransitionPage<T> _desdeAbajo<T>(GoRouterState st, Widget hijo) => CustomTransitionPage<T>(
      key: st.pageKey,
      fullscreenDialog: true,
      transitionDuration: const Duration(milliseconds: 420),
      reverseTransitionDuration: const Duration(milliseconds: 320),
      child: hijo,
      transitionsBuilder: (_, a, _, c) => SlideTransition(
        position: Tween(begin: const Offset(0, 1), end: Offset.zero).animate(CurvedAnimation(parent: a, curve: Curves.easeOutCubic)),
        child: c,
      ),
    );

/// Mirar no pide cuenta: no hay redirecciones. Lo que necesita perfil lo
/// pide en el momento (asegurarCuenta).
final routerProvider = Provider<GoRouter>((ref) {
  final raiz = GlobalKey<NavigatorState>();
  return GoRouter(
    navigatorKey: raiz,
    initialLocation: '/',
    routes: [
      StatefulShellRoute.indexedStack(
        builder: (_, _, nav) => Shell(nav: nav),
        branches: [
          StatefulShellBranch(routes: [GoRoute(path: '/', builder: (_, _) => const DescubrirScreen())]),
          StatefulShellBranch(routes: [GoRoute(path: '/mapa', builder: (_, _) => const MapaScreen())]),
          StatefulShellBranch(routes: [GoRoute(path: '/accesos', builder: (_, _) => const AccesosScreen())]),
          StatefulShellBranch(routes: [GoRoute(path: '/cuenta', builder: (_, _) => const CuentaScreen())]),
        ],
      ),
      GoRoute(
        parentNavigatorKey: raiz,
        path: '/evento/:id',
        builder: (_, st) => EventoScreen(id: st.pathParameters['id']!, previo: st.extra is Evento ? st.extra as Evento : null),
      ),
      GoRoute(
        parentNavigatorKey: raiz,
        path: '/lugar/:id',
        builder: (_, st) => LugarScreen(id: st.pathParameters['id']!, previo: st.extra is Lugar ? st.extra as Lugar : null),
      ),
      GoRoute(
        parentNavigatorKey: raiz,
        path: '/ingresar',
        pageBuilder: (_, st) => _desdeAbajo<bool>(st, const LoginScreen()),
      ),
      GoRoute(
        parentNavigatorKey: raiz,
        path: '/bienvenida',
        pageBuilder: (_, st) => _desdeAbajo<bool>(st, const BienvenidaScreen()),
      ),
    ],
  );
});
