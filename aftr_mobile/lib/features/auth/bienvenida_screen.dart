import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/networking/supabase.dart';
import '../../core/theme/aftr_theme.dart';
import '../../core/widgets/movimiento.dart';
import '../../core/widgets/piezas.dart';
import '../../data/aftr_repo.dart';
import 'ingreso.dart';

/// Primera vez: nombre y @usuario, en dos pasos con barra de progreso (como
/// el onboarding de Pillowtalk). El @usuario es como te encuentran tus amigos
/// para pasarte una entrada.
class BienvenidaScreen extends ConsumerStatefulWidget {
  const BienvenidaScreen({super.key});

  @override
  ConsumerState<BienvenidaScreen> createState() => _BienvenidaScreenState();
}

class _BienvenidaScreenState extends ConsumerState<BienvenidaScreen> {
  late final _nombre = TextEditingController(text: ref.read(ingresoProvider).nombreSugerido() ?? '');
  late final _usuario = TextEditingController(text: usuarioDesde(_nombre.text));
  int _paso = 0;
  bool _guardando = false;
  String? _error;

  @override
  void dispose() {
    _nombre.dispose();
    _usuario.dispose();
    super.dispose();
  }

  bool get _valido =>
      _paso == 0 ? _nombre.text.trim().isNotEmpty : usuarioValido.hasMatch(_usuario.text.trim().toLowerCase());

  Future<void> _siguiente() async {
    if (_paso == 0) {
      if (_usuario.text.isEmpty) _usuario.text = usuarioDesde(_nombre.text);
      setState(() => _paso = 1);
      return;
    }
    setState(() {
      _guardando = true;
      _error = null;
    });
    try {
      await ref.read(repoProvider).crearPerfil(_usuario.text.trim().toLowerCase(), _nombre.text.trim());
      ref.invalidate(perfilProvider);
      if (mounted) context.pop(true);
    } catch (e) {
      setState(() => _error = mensajeDeError(e));
    } finally {
      if (mounted) setState(() => _guardando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final primerNombre = _nombre.text.trim().split(' ').first;
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              IconButton(
                onPressed: () => _paso == 0 ? ref.read(ingresoProvider).salir().then((_) {
                      if (context.mounted) context.pop(false);
                    }) : setState(() => _paso = 0),
                style: IconButton.styleFrom(backgroundColor: Aftr.superficie2),
                icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 16, color: Aftr.texto),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: TweenAnimationBuilder<double>(
                    tween: Tween(end: (_paso + 1) / 2),
                    duration: Aftr.lento,
                    curve: Aftr.curva,
                    builder: (_, v, _) => LinearProgressIndicator(
                      value: v,
                      minHeight: 4,
                      backgroundColor: Aftr.superficie3,
                      color: Aftr.acento,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 14),
              Text('${_paso + 1}/2', style: Aftr.cuerpo(13)),
            ]),
            const SizedBox(height: 36),
            Expanded(
              child: AnimatedSwitcher(
                duration: Aftr.medio,
                transitionBuilder: (c, a) => FadeTransition(
                  opacity: a,
                  child: SlideTransition(
                    position: Tween(begin: const Offset(0.08, 0), end: Offset.zero).animate(a),
                    child: c,
                  ),
                ),
                child: _paso == 0
                    ? _Paso(
                        key: const ValueKey(0),
                        titulo: 'Tu noche empieza acá.\n¿Cómo te llamamos?',
                        campo: TextField(
                          controller: _nombre,
                          autofocus: true,
                          textCapitalization: TextCapitalization.words,
                          style: Aftr.fuerte(24),
                          decoration: const InputDecoration(hintText: 'Tu nombre', filled: false, contentPadding: EdgeInsets.zero),
                          onChanged: (_) => setState(() {}),
                          onSubmitted: (_) => _valido ? _siguiente() : null,
                        ),
                      )
                    : _Paso(
                        key: const ValueKey(1),
                        titulo: 'Hola, $primerNombre.\nElegí tu usuario.',
                        ayuda: 'Con este nombre te encuentran tus amigos para mandarte entradas.',
                        campo: TextField(
                          controller: _usuario,
                          autofocus: true,
                          autocorrect: false,
                          style: Aftr.fuerte(24),
                          decoration: InputDecoration(
                            prefixText: '@',
                            prefixStyle: Aftr.fuerte(24, c: Aftr.texto3),
                            hintText: 'usuario',
                            filled: false,
                            contentPadding: EdgeInsets.zero,
                          ),
                          onChanged: (_) => setState(() => _error = null),
                          onSubmitted: (_) => _valido ? _siguiente() : null,
                        ),
                        error: _error,
                      ),
              ),
            ),
            BotonAftr(_paso == 0 ? 'Siguiente' : 'Empezar', cargando: _guardando, onTap: _valido ? _siguiente : null),
          ]),
        ),
      ),
    );
  }
}

class _Paso extends StatelessWidget {
  const _Paso({super.key, required this.titulo, required this.campo, this.ayuda, this.error});

  final String titulo;
  final Widget campo;
  final String? ayuda;
  final String? error;

  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Aparecer(child: Text(titulo, style: Aftr.titular(34))),
        const SizedBox(height: 40),
        campo,
        const Divider(color: Aftr.bordeFuerte, height: 24),
        if (error != null)
          Text(error!, style: Aftr.cuerpo(14, c: Aftr.alerta))
        else if (ayuda != null)
          Text(ayuda!, style: Aftr.cuerpo(14, c: Aftr.texto3)),
      ]);
}
