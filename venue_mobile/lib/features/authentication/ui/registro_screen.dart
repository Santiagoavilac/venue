import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/networking/supabase.dart';
import '../../../core/theme/venue_theme.dart';
import '../data/sesion.dart';

/// Registro de relacionador con el link de invitación de un team.
class RegistroScreen extends ConsumerStatefulWidget {
  const RegistroScreen({super.key, this.invitacion});

  /// Código que llegó en el link (`?invite=`), si la app se abrió desde uno.
  final String? invitacion;

  @override
  ConsumerState<RegistroScreen> createState() => _RegistroScreenState();
}

class _RegistroScreenState extends ConsumerState<RegistroScreen> {
  late final _invite = TextEditingController(text: widget.invitacion ?? '');
  final _nombre = TextEditingController();
  final _usuario = TextEditingController();
  final _clave = TextEditingController();
  bool _enviando = false;
  String? _error;

  @override
  void dispose() {
    for (final c in [_invite, _nombre, _usuario, _clave]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _registrar() async {
    if (_enviando) return;
    if (_invite.text.trim().isEmpty ||
        _nombre.text.trim().isEmpty ||
        _usuario.text.trim().length < 3 ||
        _clave.text.length < 6) {
      setState(() => _error =
          'Completá todo: usuario de 3 letras o más y contraseña de 6 o más.');
      return;
    }
    setState(() {
      _enviando = true;
      _error = null;
    });
    try {
      final team = await ref.read(authRepositoryProvider).registrarse(
            invitacion: _invite.text,
            nombre: _nombre.text,
            usuario: _usuario.text,
            clave: _clave.text,
          );
      if (mounted && team.isNotEmpty) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Bienvenido al $team')));
      }
      // Con la sesión abierta, el router lleva solo a la app.
    } on RegistroRechazado catch (e) {
      _error = e.motivo;
    } catch (e) {
      _error = mensajeDeError(e);
    }
    if (mounted) setState(() => _enviando = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => context.go('/login'),
        ),
        title: const Text('Registro de relacionador'),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            const Text(
              'Al registrarte quedás en el team de quien te pasó el link.',
              style: TextStyle(color: VenueColors.textoSuave, height: 1.4),
            ),
            const SizedBox(height: 18),
            TextField(
              controller: _invite,
              autocorrect: false,
              decoration: const InputDecoration(
                labelText: 'Link o código de invitación',
              ),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _nombre,
              textCapitalization: TextCapitalization.words,
              autofillHints: const [AutofillHints.name],
              decoration:
                  const InputDecoration(labelText: 'Tu nombre y apellido'),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _usuario,
              autocorrect: false,
              enableSuggestions: false,
              decoration: const InputDecoration(
                  labelText: 'Usuario (corto, sin espacios)'),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _clave,
              obscureText: true,
              autofillHints: const [AutofillHints.newPassword],
              onSubmitted: (_) => _registrar(),
              decoration:
                  const InputDecoration(labelText: 'Contraseña (mínimo 6)'),
            ),
            if (_error != null) ...[
              const SizedBox(height: 14),
              Text(_error!,
                  style: const TextStyle(color: VenueColors.mal, height: 1.35)),
            ],
            const SizedBox(height: 22),
            FilledButton(
              onPressed: _enviando ? null : _registrar,
              child: _enviando
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(strokeWidth: 2.4))
                  : const Text('Registrarme'),
            ),
          ],
        ),
      ),
    );
  }
}
