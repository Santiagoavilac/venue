import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/networking/supabase.dart';
import '../../core/theme/aftr_theme.dart';
import '../../core/widgets/listo.dart';
import '../../core/widgets/movimiento.dart';
import '../../core/widgets/piezas.dart';
import '../../data/aftr_repo.dart';
import '../../data/modelos.dart';

/// Pasarle una entrada a un amigo por su @usuario. No es un chat: es mandar la
/// entrada. Al pasarla, el QR cambia y el tuyo deja de servir.
Future<bool?> enviarEntrada(BuildContext context, Acceso a) => showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useRootNavigator: true,
      builder: (_) => _Enviar(a),
    );

class _Enviar extends ConsumerStatefulWidget {
  const _Enviar(this.a);
  final Acceso a;

  @override
  ConsumerState<_Enviar> createState() => _EnviarState();
}

class _EnviarState extends ConsumerState<_Enviar> with SingleTickerProviderStateMixin {
  final _q = TextEditingController();
  late final _vuelo = AnimationController(vsync: this, duration: const Duration(milliseconds: 650));
  Timer? _espera;
  List<Cliente> _resultados = const [];
  Cliente? _para;
  bool _buscando = false;
  bool _enviando = false;
  bool _listo = false;

  @override
  void dispose() {
    _espera?.cancel();
    _q.dispose();
    _vuelo.dispose();
    super.dispose();
  }

  void _buscar(String t) {
    _espera?.cancel();
    setState(() => _para = null);
    if (t.trim().replaceAll('@', '').length < 2) {
      setState(() => _resultados = const []);
      return;
    }
    _espera = Timer(const Duration(milliseconds: 280), () async {
      setState(() => _buscando = true);
      try {
        final r = await ref.read(repoProvider).buscarUsuario(t);
        if (mounted && _q.text == t) setState(() => _resultados = r);
      } catch (_) {
      } finally {
        if (mounted) setState(() => _buscando = false);
      }
    });
  }

  Future<void> _enviar() async {
    setState(() => _enviando = true);
    try {
      await ref.read(repoProvider).transferir(widget.a.id, _para!.usuario);
      await _vuelo.forward();
      ref.invalidate(accesosProvider);
      if (mounted) setState(() => _listo = true);
    } catch (e) {
      if (mounted) avisar(context, mensajeDeError(e));
    } finally {
      if (mounted) setState(() => _enviando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_listo) {
      return HojaListo(
        titulo: 'Entrada enviada',
        texto: 'Ya la tiene ${_para!.nombre} en su AFTR. Tu QR quedó sin efecto.',
        accion: 'Listo',
        onAccion: () => Navigator.of(context).pop(true),
      );
    }
    final teclado = MediaQuery.viewInsetsOf(context).bottom;
    final e = widget.a.evento;
    return Padding(
      padding: EdgeInsets.only(bottom: teclado),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.85),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Manija(),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 10, 20, 0),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Enviar a un amigo', style: Aftr.fuerte(22)),
              const SizedBox(height: 4),
              Text('${widget.a.titulo} · ${e.nombre}', style: Aftr.cuerpo(14)),
              const SizedBox(height: 18),
              // la entrada que se va: vuela hacia arriba al enviar
              AnimatedBuilder(
                animation: _vuelo,
                builder: (_, child) {
                  final t = Curves.easeInBack.transform(_vuelo.value);
                  return Transform.translate(
                    offset: Offset(0, -220 * t),
                    child: Transform.rotate(angle: -0.12 * t, child: Opacity(opacity: (1 - t).clamp(0, 1), child: child)),
                  );
                },
                child: Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(colors: [(e.club.color ?? Aftr.superficie3).withValues(alpha: 0.5), Aftr.superficie2]),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Row(children: [
                    const Icon(Icons.confirmation_number_outlined, color: Aftr.texto),
                    const SizedBox(width: 12),
                    Expanded(child: Text('${e.nombre} · ${fechaCorta(e.fecha)}', style: Aftr.fuerte(15))),
                    if (_para != null) Text('@${_para!.usuario}', style: Aftr.cuerpo(14, c: Aftr.acento, w: FontWeight.w600)),
                  ]),
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _q,
                autofocus: true,
                autocorrect: false,
                onChanged: _buscar,
                style: Aftr.cuerpo(16, c: Aftr.texto),
                decoration: InputDecoration(
                  hintText: '@usuario o nombre',
                  prefixIcon: const Icon(Icons.alternate_email_rounded, color: Aftr.texto2),
                  suffixIcon: _buscando
                      ? const Padding(
                          padding: EdgeInsets.all(14),
                          child: SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Aftr.texto2)),
                        )
                      : null,
                ),
              ),
            ]),
          ),
          Flexible(
            child: ListView(
              shrinkWrap: true,
              padding: const EdgeInsets.symmetric(vertical: 8),
              children: [
                for (final (i, c) in _resultados.indexed)
                  Aparecer(
                    orden: i,
                    child: ListTile(
                      onTap: () => setState(() => _para = c),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 20),
                      leading: CircleAvatar(
                        backgroundColor: Aftr.superficie3,
                        child: Text(c.nombre.isEmpty ? '?' : c.nombre.characters.first.toUpperCase(), style: Aftr.fuerte(15)),
                      ),
                      title: Text(c.nombre, style: Aftr.fuerte(15)),
                      subtitle: Text('@${c.usuario}', style: Aftr.cuerpo(13)),
                      trailing: AnimatedSwitcher(
                        duration: Aftr.rapido,
                        child: _para?.usuario == c.usuario
                            ? const Icon(Icons.check_circle_rounded, key: ValueKey(1), color: Aftr.acento)
                            : const Icon(Icons.circle_outlined, key: ValueKey(0), color: Aftr.texto3),
                      ),
                    ),
                  ),
                if (_q.text.trim().length >= 2 && !_buscando && _resultados.isEmpty)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('No encontramos a nadie con ese nombre.', style: Aftr.cuerpo(14)),
                      const SizedBox(height: 10),
                      Pildora(
                        'Invitalo a AFTR',
                        icono: Icons.ios_share_rounded,
                        onTap: () => SharePlus.instance.share(ShareParams(
                          text: 'Bajate AFTR para que te pase la entrada de ${e.nombre}: ahí vas a tener tu QR.',
                        )),
                      ),
                    ]),
                  ),
              ],
            ),
          ),
          Padding(
            padding: EdgeInsets.fromLTRB(20, 4, 20, 16 + (teclado > 0 ? 0 : MediaQuery.paddingOf(context).bottom)),
            child: Column(children: [
              if (_para != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Text('Tu QR deja de servir y ${_para!.nombre} recibe uno nuevo.',
                      textAlign: TextAlign.center, style: Aftr.cuerpo(13, c: Aftr.texto3)),
                ),
              BotonAftr(
                _para == null ? 'Elegí a quién' : 'Enviar a @${_para!.usuario}',
                cargando: _enviando,
                onTap: _para == null ? null : _enviar,
              ),
            ]),
          ),
        ]),
      ),
    );
  }
}
