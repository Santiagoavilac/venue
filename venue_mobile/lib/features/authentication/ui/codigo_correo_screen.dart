import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/sesion.dart';

/// Entrar con un código al correo, para quien no se acuerda la contraseña.
///
/// No crea cuentas: en Venue las cuentas se crean por enlace con rol. El
/// código sólo le llega a un correo que ya tiene cuenta; a uno desconocido no
/// le llega nada, y la pantalla dice lo mismo en los dos casos para no contar
/// quién tiene cuenta y quién no.
class CodigoCorreoScreen extends ConsumerStatefulWidget {
  const CodigoCorreoScreen({super.key, this.relacionador = false});

  final bool relacionador;

  @override
  ConsumerState<CodigoCorreoScreen> createState() => _CodigoState();
}

class _CodigoState extends ConsumerState<CodigoCorreoScreen> {
  static const _suave = Color(0xFF9CA3AF);
  final _correo = TextEditingController();
  final _codigo = TextEditingController();
  bool _mandado = false;
  bool _enviando = false;
  String? _error;

  @override
  void dispose() {
    _correo.dispose();
    _codigo.dispose();
    super.dispose();
  }

  bool get _listo => _mandado
      ? _codigo.text.trim().length >= 6
      : RegExp(r'^[^@\s]+@[^@\s]+\.[a-zA-Z]{2,}$').hasMatch(_correo.text.trim());

  Future<void> _seguir() async {
    if (_enviando || !_listo) return;
    setState(() {
      _enviando = true;
      _error = null;
    });
    final auth = ref.read(authRepositoryProvider);
    try {
      if (!_mandado) {
        await auth.pedirCodigo(_correo.text);
        setState(() => _mandado = true);
      } else {
        await auth.entrarConCodigo(_correo.text, _codigo.text,
            relacionador: widget.relacionador);
        if (mounted) Navigator.of(context).pop(true);
        return;
      }
    } catch (e) {
      setState(() => _error = _mensaje(e));
    } finally {
      if (mounted) setState(() => _enviando = false);
    }
  }

  String _mensaje(Object e) {
    final t = e.toString().toLowerCase();
    if (t.contains('signups not allowed') || t.contains('not found')) {
      // no se dice si existe o no: eso contaría quién tiene cuenta
      return 'Si ese correo tiene cuenta, le va a llegar el código.';
    }
    if (t.contains('expired') || t.contains('invalid')) {
      return 'Ese código no sirve o ya venció. Pedí uno nuevo.';
    }
    return 'No pudimos mandarte el código. Probá de nuevo.';
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: Colors.black,
    appBar: AppBar(
      backgroundColor: Colors.black,
      foregroundColor: Colors.white,
      leading: IconButton(
        icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 18),
        onPressed: _enviando
            ? null
            : () => _mandado
                ? setState(() {
                    _mandado = false;
                    _error = null;
                    _codigo.clear();
                  })
                : Navigator.of(context).pop(false),
      ),
    ),
    body: ListView(
      padding: EdgeInsets.fromLTRB(22, 8, 22, 30 + MediaQuery.viewInsetsOf(context).bottom),
      children: [
        Text(
          _mandado ? 'Te mandamos un código' : 'Entrá con tu correo',
          style: const TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 10),
        Text(
          _mandado
              ? 'Fijate en ${_correo.text.trim()}. Vence en diez minutos.'
              : 'Te mandamos un código de seis dígitos al correo de tu cuenta.',
          style: const TextStyle(color: _suave, fontSize: 14, height: 1.4),
        ),
        const SizedBox(height: 26),
        if (!_mandado)
          TextField(
            controller: _correo,
            enabled: !_enviando,
            autofocus: true,
            style: const TextStyle(color: Colors.white),
            keyboardType: TextInputType.emailAddress,
            autofillHints: const [AutofillHints.email],
            autocorrect: false,
            decoration: const InputDecoration(labelText: 'Correo'),
            onChanged: (_) => setState(() {}),
            onSubmitted: (_) => _seguir(),
          )
        else
          TextField(
            controller: _codigo,
            enabled: !_enviando,
            autofocus: true,
            style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.w700),
            keyboardType: TextInputType.number,
            autofillHints: const [AutofillHints.oneTimeCode],
            maxLength: 6,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: const InputDecoration(labelText: 'Código', counterText: ''),
            onChanged: (_) => setState(() {}),
            onSubmitted: (_) => _seguir(),
          ),
        if (_error != null) ...[
          const SizedBox(height: 10),
          Text(_error!, style: const TextStyle(color: Color(0xFFF87171), fontSize: 14)),
        ],
        const SizedBox(height: 20),
        FilledButton(
          onPressed: _listo && !_enviando ? _seguir : null,
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
                  width: 22, height: 22,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black54))
              : Text(_mandado ? 'Entrar' : 'Mandarme el código'),
        ),
      ],
    ),
  );
}
