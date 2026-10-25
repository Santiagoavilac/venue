import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/aftr_theme.dart';
import '../../data/aftr_repo.dart';
import '../../data/modelos.dart';

/// Las cuatro pestañas en una barra de vidrio oscuro, como la de Resy. La
/// activa se ilumina con un punto debajo; Accesos muestra cuántos QR válidos
/// hay para esta noche.
class Shell extends ConsumerWidget {
  const Shell({super.key, required this.nav});

  final StatefulNavigationShell nav;

  static const _items = [
    (Icons.auto_awesome_outlined, Icons.auto_awesome, 'Descubrir'),
    (Icons.map_outlined, Icons.map_rounded, 'Mapa'),
    (Icons.confirmation_number_outlined, Icons.confirmation_number, 'Accesos'),
    (Icons.person_outline_rounded, Icons.person_rounded, 'Cuenta'),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final abajo = MediaQuery.paddingOf(context).bottom;
    final validos = (ref.watch(accesosProvider).value?.proximos(DateTime.now()) ?? const <Acceso>[])
        .where((a) => a.tieneQr)
        .length;
    return Scaffold(
      extendBody: true,
      body: nav,
      bottomNavigationBar: ClipRect(
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 22, sigmaY: 22),
          child: Container(
            padding: EdgeInsets.fromLTRB(8, 8, 8, abajo > 0 ? abajo - 6 : 10),
            decoration: BoxDecoration(
              color: Aftr.fondo.withValues(alpha: 0.72),
              border: const Border(top: BorderSide(color: Aftr.borde)),
            ),
            child: Row(children: [
              for (var i = 0; i < _items.length; i++)
                Expanded(
                  child: _Item(
                    icono: _items[i].$1,
                    activo: _items[i].$2,
                    texto: _items[i].$3,
                    elegido: nav.currentIndex == i,
                    globo: i == 2 && validos > 0 ? validos : null,
                    onTap: () {
                      HapticFeedback.selectionClick();
                      nav.goBranch(i, initialLocation: i == nav.currentIndex);
                    },
                  ),
                ),
            ]),
          ),
        ),
      ),
    );
  }
}

class _Item extends StatelessWidget {
  const _Item({required this.icono, required this.activo, required this.texto, required this.elegido, required this.onTap, this.globo});

  final IconData icono;
  final IconData activo;
  final String texto;
  final bool elegido;
  final VoidCallback onTap;
  final int? globo;

  @override
  Widget build(BuildContext context) => GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Stack(clipBehavior: Clip.none, children: [
            AnimatedScale(
              duration: Aftr.medio,
              curve: Curves.easeOutBack,
              scale: elegido ? 1.12 : 1,
              child: Icon(elegido ? activo : icono, size: 24, color: elegido ? Aftr.texto : Aftr.texto3),
            ),
            if (globo != null)
              Positioned(
                right: -9,
                top: -5,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                  decoration: BoxDecoration(color: Aftr.acento, borderRadius: BorderRadius.circular(8)),
                  child: Text('$globo', style: Aftr.cuerpo(11, c: Aftr.fondo, w: FontWeight.w800)),
                ),
              ),
          ]),
          const SizedBox(height: 4),
          AnimatedDefaultTextStyle(
            duration: Aftr.medio,
            style: Aftr.cuerpo(11, c: elegido ? Aftr.texto : Aftr.texto3, w: elegido ? FontWeight.w700 : FontWeight.w500),
            child: Text(texto),
          ),
          const SizedBox(height: 4),
          AnimatedContainer(
            duration: Aftr.medio,
            curve: Aftr.curva,
            width: elegido ? 4 : 0,
            height: 4,
            decoration: const BoxDecoration(color: Aftr.acento, shape: BoxShape.circle),
          ),
        ]),
      );
}
