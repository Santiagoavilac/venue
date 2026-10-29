import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/networking/supabase.dart';
import '../../../core/routing/router.dart';
import '../data/sesion.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _usuario = TextEditingController();
  final _clave = TextEditingController();
  final _foco = FocusNode();
  bool _ocultar = true;
  bool _enviando = false;
  String? _error;

  /// 0: usuario, 1: contraseña.
  int _paso = 0;

  @override
  void dispose() {
    _usuario.dispose();
    _clave.dispose();
    _foco.dispose();
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
    } on OtraPuerta catch (e) {
      _error = e.mensaje;
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

  /// Primero el usuario y después la contraseña, de a un dato por pantalla
  /// (como el ingreso de Resy).
  void _siguiente() {
    if (_usuario.text.trim().isEmpty) return;
    setState(() {
      _paso = 1;
      _error = null;
    });
    _foco.requestFocus();
  }

  /// Del primer paso se vuelve a la bienvenida (elegir Boliches o
  /// Relacionadores); del segundo, al usuario.
  void _atras() {
    if (_paso == 0) return context.go(Rutas.login);
    setState(() {
      _paso = 0;
      _error = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final clave = _paso == 1;
    // el ingreso es siempre oscuro, sin importar el modo de la app
    const fondo = Color(0xFF16181C), campo = Color(0xFF26292F), suave = Color(0xFF9AA0A9);
    final estiloCampo = InputDecoration(
      filled: true,
      fillColor: campo,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
      enabledBorder:
          OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
      focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Colors.white24)),
      hintStyle: const TextStyle(color: Colors.white38),
    );
    Widget rotulo(String t) => Padding(
          padding: const EdgeInsets.only(bottom: 8, left: 2),
          child: Text(t,
              style: const TextStyle(
                  color: suave, fontSize: 11.5, fontWeight: FontWeight.w600, letterSpacing: .6)),
        );

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (hecho, _) {
        if (!hecho) _atras();
      },
      child: Scaffold(
        backgroundColor: fondo,
        body: DecoratedBox(
          // un brillo cálido abajo, como el fondo de Resy
          decoration: const BoxDecoration(
            gradient: RadialGradient(
              center: Alignment(0, .55),
              radius: 1.1,
              colors: [Color(0xFF2A241B), fondo],
            ),
          ),
          child: SafeArea(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 460),
                child: AutofillGroup(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 4, 20, 16),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                      SizedBox(
                        height: 48,
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: IconButton(
                            tooltip: 'Volver',
                            onPressed: _atras,
                            padding: EdgeInsets.zero,
                            alignment: Alignment.centerLeft,
                            icon: const Icon(Icons.arrow_back_ios_new_rounded,
                                color: Colors.white, size: 20),
                          ),
                        ),
                      ),
                      Expanded(
                        child: SingleChildScrollView(
                          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                            const SizedBox(height: 6),
                            Text(clave ? 'Ingresá tu contraseña' : 'Ingresá tu usuario',
                                style: const TextStyle(
                                    color: Colors.white, fontSize: 24, fontWeight: FontWeight.w700)),
                            const SizedBox(height: 6),
                            Text(
                              clave
                                  ? 'Entrás como @${_usuario.text.trim()}'
                                  : 'Acceso para personal autorizado',
                              style: const TextStyle(color: suave, fontSize: 14.5),
                            ),
                            const SizedBox(height: 22),
                            // los dos campos quedan montados para que el
                            // llavero del teléfono los complete juntos
                            Offstage(
                              offstage: clave,
                              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                                rotulo('USUARIO'),
                                TextField(
                                  controller: _usuario,
                                  autofocus: true,
                                  autocorrect: false,
                                  enableSuggestions: false,
                                  textCapitalization: TextCapitalization.none,
                                  textInputAction: TextInputAction.next,
                                  autofillHints: const [AutofillHints.username],
                                  onChanged: (_) => setState(() {}),
                                  onSubmitted: (_) => _siguiente(),
                                  style: const TextStyle(color: Colors.white, fontSize: 16),
                                  cursorColor: Colors.white,
                                  decoration: estiloCampo.copyWith(hintText: 'tu.usuario'),
                                ),
                              ]),
                            ),
                            Offstage(
                              offstage: !clave,
                              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                                rotulo('CONTRASEÑA'),
                                TextField(
                                  controller: _clave,
                                  focusNode: _foco,
                                  obscureText: _ocultar,
                                  textInputAction: TextInputAction.go,
                                  autofillHints: const [AutofillHints.password],
                                  onChanged: (_) => setState(() {}),
                                  onSubmitted: (_) => _ingresar(),
                                  style: const TextStyle(color: Colors.white, fontSize: 16),
                                  cursorColor: Colors.white,
                                  decoration: estiloCampo.copyWith(
                                    suffixIcon: IconButton(
                                      tooltip: _ocultar ? 'Ver contraseña' : 'Ocultar contraseña',
                                      onPressed: () => setState(() => _ocultar = !_ocultar),
                                      icon: Icon(
                                          _ocultar
                                              ? Icons.visibility_outlined
                                              : Icons.visibility_off_outlined,
                                          color: suave),
                                    ),
                                  ),
                                ),
                              ]),
                            ),
                            if (_error != null) ...[
                              const SizedBox(height: 14),
                              Text(_error!,
                                  style: const TextStyle(color: Color(0xFFFF8A80), height: 1.35)),
                            ],
                            const SizedBox(height: 18),
                            if (clave)
                              const Text(
                                '¿Olvidaste tu contraseña? Pedile a tu jefe de team o al administrador que te la restablezca.',
                                style: TextStyle(color: suave, fontSize: 13, height: 1.4),
                              )
                            else
                              Align(
                                alignment: Alignment.centerLeft,
                                child: TextButton(
                                  onPressed: () => context.go(Rutas.relacionadores),
                                  style: TextButton.styleFrom(
                                      foregroundColor: Colors.white, padding: EdgeInsets.zero),
                                  child: const Text('¿Sos relacionador? Entrá por Relacionadores',
                                      style: TextStyle(decoration: TextDecoration.underline)),
                                ),
                              ),
                          ]),
                        ),
                      ),
                      // botón blanco abajo; sube con el teclado
                      FilledButton(
                        onPressed: _enviando ||
                                (clave ? _clave.text.isEmpty : _usuario.text.trim().isEmpty)
                            ? null
                            : (clave ? _ingresar : _siguiente),
                        style: FilledButton.styleFrom(
                          backgroundColor: Colors.white,
                          foregroundColor: Colors.black,
                          disabledBackgroundColor: Colors.white24,
                          disabledForegroundColor: Colors.white54,
                          minimumSize: const Size.fromHeight(54),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                        ),
                        child: _enviando
                            ? const SizedBox(
                                width: 22,
                                height: 22,
                                child: CircularProgressIndicator(strokeWidth: 2.4, color: Colors.black),
                              )
                            : Text(clave ? 'Ingresar' : 'Siguiente'),
                      ),
                    ]),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
