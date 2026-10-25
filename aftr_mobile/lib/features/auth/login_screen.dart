import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/networking/supabase.dart';
import '../../core/theme/aftr_theme.dart';
import '../../core/widgets/logo.dart';
import '../../core/widgets/movimiento.dart';
import '../../core/widgets/piezas.dart';
import '../../data/aftr_repo.dart' show perfilProvider;
import '../splash/splash.dart';
import 'ingreso.dart';

/// Ingreso: las fotos de noche siguen pasando detrás (más lento que en el
/// arranque, con un zoom suave) y abajo Apple y Google.
class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> with SingleTickerProviderStateMixin {
  late final _zoom = AnimationController(vsync: this, duration: const Duration(milliseconds: 2400));
  Timer? _reloj;
  int _foto = 0;
  String? _cargando;

  @override
  void initState() {
    super.initState();
    _zoom.forward();
    _reloj = Timer.periodic(const Duration(milliseconds: 2400), (_) {
      setState(() => _foto++);
      _zoom.forward(from: 0);
    });
  }

  @override
  void dispose() {
    _reloj?.cancel();
    _zoom.dispose();
    super.dispose();
  }

  Future<void> _entrar(String con) async {
    setState(() => _cargando = con);
    final ingreso = ref.read(ingresoProvider);
    try {
      con == 'apple' ? await ingreso.conApple() : await ingreso.conGoogle();
      ref.invalidate(perfilProvider);
      // si falta el perfil, lo pide asegurarCuenta con la bienvenida
      if (mounted) context.pop(true);
    } on IngresoCancelado {
      // nada: volvió atrás
    } catch (e) {
      if (mounted) avisar(context, mensajeDeError(e));
    } finally {
      if (mounted) setState(() => _cargando = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final abajo = MediaQuery.paddingOf(context).bottom;
    return Scaffold(
      body: Stack(fit: StackFit.expand, children: [
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 700),
          child: AnimatedBuilder(
            key: ValueKey(_foto),
            animation: _zoom,
            builder: (_, child) => Transform.scale(scale: 1.04 + 0.06 * _zoom.value, child: child),
            child: Image.asset(fotosNoche[_foto % fotosNoche.length], fit: BoxFit.cover),
          ),
        ),
        const DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              stops: [0, 0.35, 0.72, 1],
              colors: [Color(0x99000000), Color(0x33000000), Color(0xE6000000), Aftr.fondo],
            ),
          ),
        ),
        SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const SizedBox(height: 8),
              Row(children: [
                const PalabraAftr(alto: 22),
                const Spacer(),
                if (context.canPop())
                  IconButton(
                    onPressed: () => context.pop(false),
                    icon: const Icon(Icons.close_rounded, color: Aftr.texto),
                  ),
              ]),
              const Spacer(),
              Aparecer(child: Text('Your night\nstarts here.', style: Aftr.titular(46))),
              const SizedBox(height: 12),
              Aparecer(
                orden: 2,
                child: Text('Descubrí, reservá y entrá. Todo desde una sola app.', style: Aftr.cuerpo(16)),
              ),
              const SizedBox(height: 32),
              Aparecer(
                orden: 4,
                child: BotonAftr(
                  'Continuar con Apple',
                  icono: const Icon(Icons.apple, color: Aftr.fondo, size: 22),
                  cargando: _cargando == 'apple',
                  onTap: _cargando == null ? () => _entrar('apple') : null,
                ),
              ),
              const SizedBox(height: 12),
              Aparecer(
                orden: 5,
                child: BotonAftr(
                  'Continuar con Google',
                  secundario: true,
                  icono: Text('G', style: Aftr.fuerte(18)),
                  cargando: _cargando == 'google',
                  onTap: _cargando == null ? () => _entrar('google') : null,
                ),
              ),
              const SizedBox(height: 18),
              Center(
                child: Text(
                  'Al continuar aceptás los términos y la política de privacidad de AFTR.',
                  textAlign: TextAlign.center,
                  style: Aftr.cuerpo(12, c: Aftr.texto3),
                ),
              ),
              SizedBox(height: abajo > 0 ? 8 : 20),
            ]),
          ),
        ),
      ]),
    );
  }
}
