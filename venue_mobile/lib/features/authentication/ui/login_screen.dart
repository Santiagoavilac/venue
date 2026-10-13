import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/networking/supabase.dart';
import '../../../core/theme/venue_theme.dart';
import '../data/sesion.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _usuario = TextEditingController();
  final _clave = TextEditingController();
  bool _ocultar = true;
  bool _enviando = false;
  String? _error;

  @override
  void dispose() {
    _usuario.dispose();
    _clave.dispose();
    super.dispose();
  }

  Future<void> _ingresar() async {
    final u = _usuario.text.trim(), c = _clave.text;
    if (u.isEmpty || c.isEmpty || _enviando) return;
    setState(() {
      _enviando = true;
      _error = null;
    });
    try {
      await ref.read(authRepositoryProvider).ingresar(u, c);
    } on CuentaDesactivada {
      _error = 'Tu usuario está desactivado. Hablá con tu jefe de team o con el administrador.';
    } on AuthException catch (e) {
      _error = esFallaDeRed(e)
          ? 'Sin conexión. Revisá la señal y probá de nuevo.'
          : 'Usuario o contraseña incorrectos.';
    } catch (e) {
      _error = mensajeDeError(e);
    }
    if (mounted) setState(() => _enviando = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: AutofillGroup(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Text(
                      'VENUE',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 40,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 8,
                      ),
                    ),
                    const SizedBox(height: 6),
                    const Text(
                      'Acceso para personal autorizado',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: VenueColors.textoSuave),
                    ),
                    const SizedBox(height: 36),
                    TextField(
                      controller: _usuario,
                      autocorrect: false,
                      enableSuggestions: false,
                      textCapitalization: TextCapitalization.none,
                      textInputAction: TextInputAction.next,
                      autofillHints: const [AutofillHints.username],
                      decoration: const InputDecoration(labelText: 'Usuario'),
                    ),
                    const SizedBox(height: 14),
                    TextField(
                      controller: _clave,
                      obscureText: _ocultar,
                      textInputAction: TextInputAction.go,
                      autofillHints: const [AutofillHints.password],
                      onSubmitted: (_) => _ingresar(),
                      decoration: InputDecoration(
                        labelText: 'Contraseña',
                        suffixIcon: IconButton(
                          tooltip: _ocultar ? 'Ver contraseña' : 'Ocultar contraseña',
                          onPressed: () => setState(() => _ocultar = !_ocultar),
                          icon: Icon(_ocultar
                              ? Icons.visibility_outlined
                              : Icons.visibility_off_outlined),
                        ),
                      ),
                    ),
                    if (_error != null) ...[
                      const SizedBox(height: 14),
                      Text(
                        _error!,
                        style: const TextStyle(color: VenueColors.mal, height: 1.35),
                      ),
                    ],
                    const SizedBox(height: 22),
                    FilledButton(
                      onPressed: _enviando ? null : _ingresar,
                      child: _enviando
                          ? const SizedBox(
                              width: 22,
                              height: 22,
                              child: CircularProgressIndicator(strokeWidth: 2.4),
                            )
                          : const Text('Ingresar'),
                    ),
                    const SizedBox(height: 18),
                    const Text(
                      '¿Olvidaste tu contraseña? Pedile a tu jefe de team o al administrador que te la restablezca.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: VenueColors.textoSuave,
                        fontSize: 13,
                        height: 1.4,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
