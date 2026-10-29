import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/routing/router.dart';
import '../../rrpp/data/rrpp.dart';
import 'acceso_oscuro.dart';

/// Primera pantalla: dos entradas bien separadas. Boliches (personal del
/// local, usuario y contraseña) y Relacionadores (cuenta propia).
class BienvenidaScreen extends ConsumerWidget {
  const BienvenidaScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    Widget opcion(IconData ic, String t, String d, String modo, String ruta) => Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Material(
            color: Acceso.tarjeta,
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16), side: const BorderSide(color: Color(0x14FFFFFF))),
            child: InkWell(
              borderRadius: BorderRadius.circular(16),
              onTap: () {
                ref.read(modoAccesoProvider.notifier).poner(modo);
                context.go(ruta);
              },
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
                child: Row(children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(color: const Color(0xFF2A2E35), borderRadius: BorderRadius.circular(12)),
                    child: Icon(ic, color: Colors.white, size: 22),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(t, style: const TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w600)),
                      const SizedBox(height: 3),
                      Text(d, style: const TextStyle(color: Acceso.suave, fontSize: 13.5)),
                    ]),
                  ),
                  const Icon(Icons.chevron_right_rounded, color: Acceso.suave),
                ]),
              ),
            ),
          ),
        );

    return FondoAcceso(
      marca: true,
      child: ListView(children: [
        Acceso.titulo('Bienvenido', '¿Cómo vas a entrar?'),
        const SizedBox(height: 6),
        opcion(Icons.storefront_outlined, 'Boliches', 'Administración y personal del local', 'boliche',
            Rutas.loginBoliche),
        opcion(Icons.person_outline_rounded, 'Relacionadores', 'Tu cuenta, tus boliches y tus ganancias', 'rel',
            Rutas.relacionadores),
      ]),
    );
  }
}
