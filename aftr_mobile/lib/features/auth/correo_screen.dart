import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/networking/supabase.dart';
import '../../core/theme/aftr_theme.dart';
import '../../core/widgets/piezas.dart';
import '../../data/aftr_repo.dart';
import 'ingreso.dart';

/// Entrar con un código al correo.
///
/// Un código de seis dígitos y no un enlace: el enlace se abre en el navegador
/// del correo y deja la sesión ahí, no en la app donde la persona la pidió.
/// El código se copia y entra donde estaba.
class CorreoScreen extends ConsumerStatefulWidget {
  const CorreoScreen({super.key});

  @override
  ConsumerState<CorreoScreen> createState() => _CorreoState();
}

class _CorreoState extends ConsumerState<CorreoScreen> {
  final _correo = TextEditingController();
  final _codigo = TextEditingController();
  bool _mandado = false;
  bool _ocupado = false;
  String? _error;

  @override
  void dispose() {
    _correo.dispose();
    _codigo.dispose();
    super.dispose();
  }

  bool get _valido => _mandado
      ? _codigo.text.trim().length >= 6
      : RegExp(r'^[^@\s]+@[^@\s]+\.[a-zA-Z]{2,}$').hasMatch(_correo.text.trim());

  Future<void> _seguir() async {
    if (_ocupado || !_valido) return;
    setState(() {
      _ocupado = true;
      _error = null;
    });
    final ingreso = ref.read(ingresoProvider);
    try {
      if (!_mandado) {
        await ingreso.pedirCodigo(_correo.text);
        setState(() => _mandado = true);
      } else {
        await ingreso.entrarConCodigo(_correo.text, _codigo.text);
        ref.invalidate(perfilProvider);
        if (mounted) Navigator.of(context).pop(true);
        return;
      }
    } catch (e) {
      setState(() => _error = mensajeDeError(e));
    } finally {
      if (mounted) setState(() => _ocupado = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      leading: IconButton(
        icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 18),
        onPressed: _ocupado
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
          _mandado ? 'Te mandamos un código.' : 'Entrá con tu correo.',
          style: Aftr.titular(32),
        ),
        const SizedBox(height: 10),
        Text(
          _mandado
              ? 'Fijate en ${_correo.text.trim()}. Vence en diez minutos.'
              : 'Te mandamos un código de seis dígitos.',
          style: Aftr.cuerpo(15),
        ),
        const SizedBox(height: 28),
        if (!_mandado)
          TextField(
            controller: _correo,
            enabled: !_ocupado,
            autofocus: true,
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
            enabled: !_ocupado,
            autofocus: true,
            keyboardType: TextInputType.number,
            autofillHints: const [AutofillHints.oneTimeCode],
            maxLength: 6,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            style: Aftr.fuerte(26),
            decoration: const InputDecoration(labelText: 'Código', counterText: ''),
            onChanged: (_) => setState(() {}),
            onSubmitted: (_) => _seguir(),
          ),
        if (_error != null) ...[
          const SizedBox(height: 8),
          Text(_error!, style: Aftr.cuerpo(14, c: Aftr.alerta)),
        ],
        const SizedBox(height: 18),
        BotonAftr(
          _mandado ? 'Entrar' : 'Mandarme el código',
          cargando: _ocupado,
          onTap: _valido ? _seguir : null,
        ),
        if (_mandado) ...[
          const SizedBox(height: 10),
          Center(
            child: TextButton(
              onPressed: _ocupado ? null : () => setState(() => _mandado = false),
              child: const Text('Cambiar el correo'),
            ),
          ),
        ],
      ],
    ),
  );
}
