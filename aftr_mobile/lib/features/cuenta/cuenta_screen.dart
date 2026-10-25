import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/networking/supabase.dart';
import '../../core/theme/aftr_theme.dart';
import '../../core/widgets/listo.dart';
import '../../core/widgets/logo.dart';
import '../../core/widgets/movimiento.dart';
import '../../core/widgets/piezas.dart';
import '../../core/widgets/tarjetas.dart';
import '../../data/aftr_repo.dart';
import '../auth/asegurar_cuenta.dart';
import '../auth/ingreso.dart';

class CuentaScreen extends ConsumerWidget {
  const CuentaScreen({super.key});

  Future<void> _eliminar(BuildContext context, WidgetRef ref) async {
    final ok = await showModalBottomSheet<bool>(
      context: context,
      useRootNavigator: true,
      builder: (ctx) => Padding(
        padding: EdgeInsets.fromLTRB(24, 0, 24, 20 + MediaQuery.paddingOf(ctx).bottom),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Manija(),
          const SizedBox(height: 14),
          Text('¿Eliminar tu cuenta?', style: Aftr.fuerte(22)),
          const SizedBox(height: 8),
          Text('Se borran tu perfil, tus guardados y los lugares que seguís. Las entradas que tengas dejan de estar a tu nombre en AFTR. No se puede deshacer.',
              style: Aftr.cuerpo(15)),
          const SizedBox(height: 22),
          BotonAftr('Eliminar cuenta', onTap: () => Navigator.of(ctx).pop(true)),
          const SizedBox(height: 10),
          BotonAftr('Cancelar', secundario: true, onTap: () => Navigator.of(ctx).pop(false)),
        ]),
      ),
    );
    if (ok != true) return;
    try {
      await ref.read(repoProvider).eliminarCuenta();
      await ref.read(ingresoProvider).salir();
      if (context.mounted) avisar(context, 'Tu cuenta se eliminó.');
    } catch (e) {
      if (context.mounted) avisar(context, mensajeDeError(e));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final logueado = ref.watch(usuarioIdProvider) != null;
    final perfil = ref.watch(perfilProvider).value;
    final guardados = ref.watch(guardadosProvider).value;
    final arriba = MediaQuery.paddingOf(context).top;

    if (!logueado) {
      return Scaffold(
        body: Padding(
          padding: EdgeInsets.fromLTRB(24, arriba + 12, 24, 130),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Cuenta', style: Aftr.titular(40)),
            const Spacer(),
            const PalabraAftr(alto: 30),
            const SizedBox(height: 18),
            Text('Guardá eventos, seguí lugares y tené tus QR siempre a mano.', style: Aftr.cuerpo(16, c: Aftr.texto)),
            const SizedBox(height: 22),
            BotonAftr('Entrar', onTap: () => asegurarCuenta(context, ref)),
          ]),
        ),
      );
    }

    return Scaffold(
      body: ListView(
        physics: const BouncingScrollPhysics(),
        padding: EdgeInsets.fromLTRB(0, arriba + 12, 0, 130 + MediaQuery.paddingOf(context).bottom),
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Aparecer(
              child: Row(children: [
                CircleAvatar(
                  radius: 34,
                  backgroundColor: Aftr.superficie2,
                  child: Text(
                    (perfil?.nombre.isNotEmpty ?? false) ? perfil!.nombre.characters.first.toUpperCase() : '?',
                    style: Aftr.titular(30),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(perfil?.nombre ?? '', style: Aftr.fuerte(24)),
                    if (perfil != null) Text('@${perfil.usuario}', style: Aftr.cuerpo(15)),
                  ]),
                ),
              ]),
            ),
          ),
          if (perfil == null)
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
              child: BotonAftr('Completar perfil', onTap: () => context.push('/bienvenida')),
            ),
          if (guardados != null && guardados.eventos.isNotEmpty) ...[
            const TituloSeccion('Guardados'),
            SizedBox(
              height: 318,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 20),
                itemCount: guardados.eventos.length,
                separatorBuilder: (_, _) => const SizedBox(width: 14),
                itemBuilder: (_, i) => TarjetaEvento(guardados.eventos[i]),
              ),
            ),
          ],
          if (guardados != null && guardados.lugares.isNotEmpty) ...[
            const TituloSeccion('Siguiendo'),
            for (final l in guardados.lugares) FilaLugar(l),
          ],
          const TituloSeccion('Ajustes'),
          _Opcion(Icons.confirmation_number_outlined, 'Mis accesos', () => context.go('/accesos')),
          _Opcion(Icons.logout_rounded, 'Cerrar sesión', () => ref.read(ingresoProvider).salir()),
          _Opcion(Icons.delete_outline_rounded, 'Eliminar cuenta', () => _eliminar(context, ref), peligro: true),
          const SizedBox(height: 30),
          const Center(child: MarcaAftr(alto: 26, color: Aftr.texto3)),
          const SizedBox(height: 8),
          Center(child: Text('AFTR · Nightlife & Events', style: Aftr.cuerpo(12, c: Aftr.texto3))),
        ],
      ),
    );
  }
}

class _Opcion extends StatelessWidget {
  const _Opcion(this.icono, this.texto, this.onTap, {this.peligro = false});
  final IconData icono;
  final String texto;
  final VoidCallback onTap;
  final bool peligro;

  @override
  Widget build(BuildContext context) => Presionable(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          child: Row(children: [
            Icon(icono, color: peligro ? Aftr.alerta : Aftr.texto, size: 22),
            const SizedBox(width: 14),
            Expanded(child: Text(texto, style: Aftr.cuerpo(16, c: peligro ? Aftr.alerta : Aftr.texto, w: FontWeight.w500))),
            const Icon(Icons.chevron_right_rounded, color: Aftr.texto3),
          ]),
        ),
      );
}
