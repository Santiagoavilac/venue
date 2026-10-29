import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/networking/supabase.dart';
import '../../../core/routing/router.dart';
import '../../rrpp/data/rrpp.dart';
import '../data/sesion.dart';
import 'acceso_oscuro.dart';

enum _Modo { entrar, crear, recuperar }

/// Acceso de relacionadores: correo y contraseña (o el usuario de siempre),
/// crear cuenta, recuperar la contraseña, Google y Apple. Registrarse no da
/// acceso a ningún boliche: eso pasa cuando un boliche aprueba la solicitud.
class RelacionadoresScreen extends ConsumerStatefulWidget {
  const RelacionadoresScreen({super.key, this.codigo});

  /// Código de un enlace de invitación (venue://app/unirse?code=…).
  final String? codigo;

  @override
  ConsumerState<RelacionadoresScreen> createState() => _RelacionadoresState();
}

class _RelacionadoresState extends ConsumerState<RelacionadoresScreen> {
  _Modo _modo = _Modo.entrar;
  final _nombre = TextEditingController(), _correo = TextEditingController(), _clave = TextEditingController();
  bool _ocultar = true, _enviando = false;
  String? _error, _hecho;
  Invitacion? _inv;

  @override
  void initState() {
    super.initState();
    final c = widget.codigo;
    if (c != null && c.isNotEmpty) {
      Future.microtask(() => ref.read(unirsePendienteProvider.notifier).poner(c));
      ref.read(rrppRepositoryProvider).verInvitacion(c).then((i) {
        if (mounted) setState(() => _inv = i);
      }, onError: (_) {});
    }
    Future.microtask(() => ref.read(modoAccesoProvider.notifier).poner('rel'));
  }

  @override
  void dispose() {
    _nombre.dispose();
    _correo.dispose();
    _clave.dispose();
    super.dispose();
  }

  String _mensaje(Object e) {
    if (e is OtraPuerta) return e.mensaje;
    if (e is CuentaDesactivada) return 'Tu cuenta está desactivada. Hablá con el boliche.';
    if (esFallaDeRed(e)) return 'Sin conexión. Revisá la señal y probá de nuevo.';
    final m = (e is AuthException ? e.message : '$e').toLowerCase();
    if (m.contains('invalid login') || m.contains('invalid credentials')) {
      return 'El correo (o usuario) o la contraseña no coinciden.';
    }
    if (m.contains('not confirmed')) return 'Todavía no confirmaste tu correo. Buscá el enlace que te mandamos.';
    if (m.contains('already')) return 'Ya hay una cuenta con ese correo. Entrá con ella.';
    if (m.contains('rate') || m.contains('too many')) return 'Demasiados intentos. Esperá un momento.';
    if (m.contains('provider is not enabled')) return 'Ese método todavía no está habilitado. Usá tu correo.';
    return mensajeDeError(e);
  }

  Future<void> _enviar() async {
    if (_enviando) return;
    final auth = ref.read(authRepositoryProvider);
    final correo = _correo.text.trim(), clave = _clave.text, nombre = _nombre.text.trim();
    final valido = RegExp(r'^\S+@\S+\.\S+$').hasMatch(correo);
    String? err;
    if (_modo == _Modo.crear && nombre.length < 2) err = 'Poné tu nombre y apellido.';
    if (_modo != _Modo.entrar && !valido) err ??= 'Escribí un correo válido.';
    if (_modo == _Modo.crear && clave.length < 8) err ??= 'La contraseña tiene que tener al menos 8 caracteres.';
    if (_modo == _Modo.entrar && (correo.isEmpty || clave.isEmpty)) err = 'Completá tu correo (o usuario) y la contraseña.';
    if (err != null) return setState(() => _error = err);
    setState(() {
      _enviando = true;
      _error = null;
    });
    try {
      switch (_modo) {
        case _Modo.entrar:
          await auth.ingresarRelacionador(correo, clave);
        case _Modo.crear:
          final conSesion = await auth.crearCuenta(nombre: nombre, correo: correo, clave: clave);
          if (!conSesion) _hecho = 'Te mandamos un enlace a $correo. Abrilo desde este teléfono y tu cuenta queda lista.';
        case _Modo.recuperar:
          await auth.recuperar(correo);
          _hecho = 'Si $correo tiene una cuenta, te llegó un enlace para elegir una contraseña nueva.';
      }
    } catch (e) {
      _error = _mensaje(e);
    }
    if (mounted) setState(() => _enviando = false);
  }

  Future<void> _proveedor(OAuthProvider p) async {
    setState(() => _error = null);
    try {
      await ref.read(authRepositoryProvider).conProveedor(p);
    } catch (e) {
      if (mounted) setState(() => _error = _mensaje(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    final crear = _modo == _Modo.crear, recup = _modo == _Modo.recuperar;
    void volver() => recup || _hecho != null
        ? setState(() {
            _modo = _Modo.entrar;
            _hecho = null;
          })
        : context.go(Rutas.login);

    if (_hecho != null) {
      return FondoAcceso(
        alVolver: volver,
        child: ListView(children: [
          Acceso.titulo(recup ? 'Revisá tu correo' : 'Confirmá tu correo', _hecho!),
          const SizedBox(height: 10),
          Acceso.botonBlanco('Ya lo confirmé, entrar', volver),
        ]),
      );
    }

    Widget seg(String t, _Modo m) => Expanded(
          child: GestureDetector(
            onTap: () => setState(() {
              _modo = m;
              _error = null;
            }),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 160),
              height: 40,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                  color: _modo == m ? const Color(0xFF2E333A) : Colors.transparent,
                  borderRadius: BorderRadius.circular(9)),
              child: Text(t,
                  style: TextStyle(
                      color: _modo == m ? Colors.white : Acceso.suave, fontWeight: FontWeight.w600, fontSize: 14.5)),
            ),
          ),
        );
    const estilo = TextStyle(color: Colors.white, fontSize: 16);

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (hecho, _) {
        if (!hecho) volver();
      },
      child: FondoAcceso(
        alVolver: volver,
        child: AutofillGroup(
          child: ListView(children: [
            if (_inv != null)
              Container(
                margin: const EdgeInsets.only(bottom: 14),
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(color: Acceso.tarjeta, borderRadius: BorderRadius.circular(12)),
                child: Text(
                  'Te invitan a sumarte a ${_inv!.team ?? _inv!.clubs.map((c) => c.nombre).join(', ')}. '
                  'Entrá o creá tu cuenta para mandar la solicitud.',
                  style: const TextStyle(color: Color(0xFFC9CDD3), height: 1.4),
                ),
              ),
            Acceso.titulo(recup ? 'Recuperar contraseña' : 'Relacionadores',
                recup ? 'Te mandamos un enlace a tu correo.' : 'Una sola cuenta para todos los boliches con los que trabajes.'),
            if (!recup)
              Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(color: Acceso.tarjeta, borderRadius: BorderRadius.circular(12)),
                child: Row(children: [seg('Entrar', _Modo.entrar), seg('Crear cuenta', _Modo.crear)]),
              ),
            if (crear) ...[
              Acceso.rotulo('NOMBRE Y APELLIDO'),
              TextField(
                controller: _nombre,
                textCapitalization: TextCapitalization.words,
                autofillHints: const [AutofillHints.name],
                textInputAction: TextInputAction.next,
                style: estilo,
                cursorColor: Colors.white,
                decoration: Acceso.campoDeco(),
              ),
            ],
            Acceso.rotulo(crear || recup ? 'CORREO' : 'CORREO O USUARIO'),
            TextField(
              controller: _correo,
              keyboardType: TextInputType.emailAddress,
              autocorrect: false,
              enableSuggestions: false,
              textCapitalization: TextCapitalization.none,
              autofillHints: [crear ? AutofillHints.email : AutofillHints.username],
              textInputAction: recup ? TextInputAction.go : TextInputAction.next,
              onSubmitted: recup ? (_) => _enviar() : null,
              style: estilo,
              cursorColor: Colors.white,
              decoration: Acceso.campoDeco(),
            ),
            if (!recup) ...[
              Acceso.rotulo('CONTRASEÑA'),
              TextField(
                controller: _clave,
                obscureText: _ocultar,
                autofillHints: [crear ? AutofillHints.newPassword : AutofillHints.password],
                textInputAction: TextInputAction.go,
                onSubmitted: (_) => _enviar(),
                style: estilo,
                cursorColor: Colors.white,
                decoration: Acceso.campoDeco(
                  pista: crear ? 'Mínimo 8 caracteres' : null,
                  sufijo: IconButton(
                    tooltip: _ocultar ? 'Ver contraseña' : 'Ocultar contraseña',
                    onPressed: () => setState(() => _ocultar = !_ocultar),
                    icon: Icon(_ocultar ? Icons.visibility_outlined : Icons.visibility_off_outlined,
                        color: Acceso.suave),
                  ),
                ),
              ),
            ],
            Acceso.errorTexto(_error),
            const SizedBox(height: 18),
            Acceso.botonBlanco(recup ? 'Mandar enlace' : crear ? 'Crear cuenta' : 'Entrar', _enviar, cargando: _enviando),
            if (_modo == _Modo.entrar)
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton(
                  onPressed: () => setState(() {
                    _modo = _Modo.recuperar;
                    _error = null;
                  }),
                  style: TextButton.styleFrom(foregroundColor: Colors.white, padding: const EdgeInsets.only(top: 8)),
                  child: const Text('Olvidé mi contraseña', style: TextStyle(decoration: TextDecoration.underline)),
                ),
              ),
            if (!recup) ...[
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 16),
                child: Row(children: [
                  Expanded(child: Divider(color: Colors.white12)),
                  Padding(padding: EdgeInsets.symmetric(horizontal: 12), child: Text('o', style: TextStyle(color: Acceso.suave))),
                  Expanded(child: Divider(color: Colors.white12)),
                ]),
              ),
              Acceso.botonBorde(const LogoGoogle(), 'Continuar con Google', () => _proveedor(OAuthProvider.google)),
              Acceso.botonBorde(const Icon(Icons.apple, color: Colors.white, size: 24), 'Continuar con Apple',
                  () => _proveedor(OAuthProvider.apple)),
              const SizedBox(height: 6),
              const Text('Si ya trabajás con un boliche en VENUE, entrá con tu mismo usuario y contraseña.',
                  style: TextStyle(color: Acceso.suave, fontSize: 13, height: 1.4)),
            ],
          ]),
        ),
      ),
    );
  }
}

/// Cuenta nueva sin perfil (correo, Google o Apple): falta el nombre.
class CompletarCuentaScreen extends ConsumerStatefulWidget {
  const CompletarCuentaScreen({super.key});
  @override
  ConsumerState<CompletarCuentaScreen> createState() => _CompletarState();
}

class _CompletarState extends ConsumerState<CompletarCuentaScreen> {
  late final _nombre = TextEditingController(text: () {
    final m = ref.read(supabaseProvider).auth.currentUser?.userMetadata ?? const {};
    return (m['nombre'] ?? m['full_name'] ?? m['name'] ?? '').toString();
  }());
  bool _enviando = false;
  String? _error;

  @override
  void dispose() {
    _nombre.dispose();
    super.dispose();
  }

  Future<void> _seguir() async {
    if (_nombre.text.trim().length < 2) return setState(() => _error = 'Poné tu nombre y apellido.');
    setState(() {
      _enviando = true;
      _error = null;
    });
    try {
      await ref.read(authRepositoryProvider).completarCuenta(_nombre.text);
      ref.invalidate(perfilProvider);
    } catch (e) {
      _error = mensajeDeError(e);
    }
    if (mounted) setState(() => _enviando = false);
  }

  @override
  Widget build(BuildContext context) => FondoAcceso(
        marca: true,
        child: ListView(children: [
          Acceso.titulo('Un último paso', '¿Cómo te llamás? Así te ven los boliches cuando pidas sumarte.'),
          Acceso.rotulo('NOMBRE Y APELLIDO'),
          TextField(
            controller: _nombre,
            autofocus: true,
            textCapitalization: TextCapitalization.words,
            onSubmitted: (_) => _seguir(),
            style: const TextStyle(color: Colors.white, fontSize: 16),
            cursorColor: Colors.white,
            decoration: Acceso.campoDeco(),
          ),
          Acceso.errorTexto(_error),
          const SizedBox(height: 18),
          Acceso.botonBlanco('Continuar', _seguir, cargando: _enviando),
          TextButton(
            onPressed: () => ref.read(authRepositoryProvider).salir(),
            style: TextButton.styleFrom(foregroundColor: Colors.white),
            child: const Text('Usar otra cuenta'),
          ),
        ]),
      );
}
