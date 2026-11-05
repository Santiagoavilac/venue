import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/aftr_theme.dart';
import '../../core/networking/supabase.dart';
import '../../core/widgets/avatar.dart';
import '../../core/widgets/movimiento.dart';
import '../../core/widgets/piezas.dart';
import '../../data/rachas.dart';
import '../../data/social_repo.dart';

/// Buscar gente por nombre, apellido o usuario, y agregarla.
///
/// Se pide y se acepta: la racha dice qué noches sale una persona, y eso no se
/// le muestra a cualquiera que la encuentre por el nombre.
Future<void> hojaAgregarAmigos(BuildContext context) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  backgroundColor: Aftr.superficie,
  showDragHandle: true,
  builder: (_) => const Padding(
    padding: EdgeInsets.only(top: 2),
    child: FractionallySizedBox(heightFactor: .92, child: BuscarAmigos()),
  ),
);

class BuscarAmigos extends ConsumerStatefulWidget {
  const BuscarAmigos({super.key});

  @override
  ConsumerState<BuscarAmigos> createState() => _BuscarAmigosState();
}

class _BuscarAmigosState extends ConsumerState<BuscarAmigos> {
  final _q = TextEditingController();
  Timer? _espera;
  List<Encontrado>? _gente;
  String? _error;
  bool _buscando = false;
  int _pedido = 0;

  /// En qué quedó cada uno después de tocar el botón, sin volver a buscar.
  final _cambios = <String, String>{};

  @override
  void dispose() {
    _espera?.cancel();
    _q.dispose();
    super.dispose();
  }

  void _alEscribir(String _) {
    _espera?.cancel();
    // 300 ms: lo que tarda en dejar de tipear. El servidor cuenta las
    // búsquedas y no hay por qué gastarle una por letra.
    _espera = Timer(const Duration(milliseconds: 300), _buscar);
  }

  Future<void> _buscar() async {
    final texto = _q.text.trim();
    if (texto.length < 3) {
      setState(() {
        _gente = null;
        _error = null;
      });
      return;
    }
    final n = ++_pedido;
    setState(() => _buscando = true);
    try {
      final r = await ref.read(socialRepoProvider).buscarUsuario(texto);
      if (!mounted || n != _pedido) return; // llegó tarde: ya hay otra búsqueda
      setState(() {
        _gente = [for (final x in r) Encontrado.desde(x)];
        _error = null;
        _buscando = false;
      });
    } catch (e) {
      if (!mounted || n != _pedido) return;
      setState(() {
        _error = mensajeDeError(e);
        _buscando = false;
      });
    }
  }

  Future<void> _tocar(Encontrado e, String estado) async {
    final accion = switch (estado) {
      'no' => 'pedir',
      'te_pidio' => 'aceptar',
      _ => 'borrar',
    };
    setState(() => _cambios[e.usuario] = '…');
    try {
      final nuevo = await ref.read(socialRepoProvider).amistad(accion, e.usuario);
      ref.invalidate(rachasProvider);
      if (mounted) setState(() => _cambios[e.usuario] = nuevo);
    } catch (err) {
      if (mounted) {
        setState(() => _cambios.remove(e.usuario));
        avisar(context, mensajeDeError(err));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final gente = _gente;
    return Padding(
      padding: EdgeInsets.fromLTRB(
        22,
        4,
        22,
        16 + MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Agregar amigos', style: Aftr.titular(30)),
        const SizedBox(height: 14),
        TextField(
          controller: _q,
          autofocus: true,
          onChanged: _alEscribir,
          onSubmitted: (_) => _buscar(),
          textInputAction: TextInputAction.search,
          style: Aftr.cuerpo(16, c: Aftr.texto),
          decoration: InputDecoration(
            hintText: 'Nombre, apellido o @usuario',
            prefixIcon: const Icon(Icons.search_rounded, color: Aftr.texto2),
            suffixIcon: _buscando
                ? const Padding(
                    padding: EdgeInsets.all(14),
                    child: SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Aftr.acento),
                    ),
                  )
                : _q.text.isEmpty
                ? null
                : IconButton(
                    onPressed: () {
                      _q.clear();
                      _buscar();
                    },
                    icon: const Icon(Icons.close_rounded, color: Aftr.texto2, size: 20),
                  ),
          ),
        ),
        const SizedBox(height: 16),
        Expanded(
          child: _error != null
              ? Text(_error!, style: Aftr.cuerpo(14, c: Aftr.alerta))
              : _q.text.trim().length < 3
              ? Text(
                  'Escribí al menos tres letras del nombre, el apellido o el '
                  '@usuario de la persona.',
                  style: Aftr.cuerpo(13),
                )
              : gente == null
              ? const SizedBox.shrink()
              : gente.isEmpty
              ? Text('No encontramos a nadie así.', style: Aftr.cuerpo(14))
              : ListView.separated(
                  padding: EdgeInsets.zero,
                  itemCount: gente.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 4),
                  itemBuilder: (_, i) => _FilaPersona(
                    gente[i],
                    estado: _cambios[gente[i].usuario] ?? gente[i].amistad,
                    onTocar: _tocar,
                  ),
                ),
        ),
      ]),
    );
  }
}

class _FilaPersona extends StatelessWidget {
  const _FilaPersona(this.e, {required this.estado, required this.onTocar});
  final Encontrado e;
  final String estado;
  final Future<void> Function(Encontrado, String) onTocar;

  @override
  Widget build(BuildContext context) {
    final (texto, activo) = switch (estado) {
      'amigos' => ('Amigos', false),
      'pedido' => ('Pendiente', false),
      'te_pidio' => ('Aceptar', true),
      '…' => ('…', false),
      _ => ('Agregar', true),
    };
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(children: [
        AvatarRemoto(nombre: e.nombre, foto: e.foto, clave: e.fotoKey, radio: 22),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(e.nombre, maxLines: 1, overflow: TextOverflow.ellipsis, style: Aftr.fuerte(16)),
            const SizedBox(height: 1),
            // el usuario abajo, más chico y más apagado que el nombre
            Text(
              '@${e.usuario}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Aftr.cuerpo(13, c: Aftr.texto3),
            ),
          ]),
        ),
        const SizedBox(width: 10),
        // blanco cuando hay algo que hacer; apagado cuando ya está hecho
        Presionable(
          onTap: activo ? () => onTocar(e, estado) : null,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
            decoration: BoxDecoration(
              color: activo ? Aftr.texto : Aftr.superficie2,
              borderRadius: BorderRadius.circular(999),
              border: activo ? null : Border.all(color: Aftr.borde),
            ),
            child: Text(
              texto,
              style: Aftr.cuerpo(13,
                  c: activo ? Aftr.fondo : Aftr.texto3, w: FontWeight.w700),
            ),
          ),
        ),
      ]),
    );
  }
}
