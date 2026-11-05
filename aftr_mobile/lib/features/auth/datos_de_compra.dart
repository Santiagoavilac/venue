import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/networking/supabase.dart';
import '../../core/theme/aftr_theme.dart';
import '../../core/widgets/piezas.dart';
import '../../data/aftr_repo.dart';
import '../cuenta/cuenta_screen.dart' show aftrTerminos;

/// Comprar sin cuenta.
///
/// Pedirle a alguien que abra una cuenta antes de saber si le gusta la fiesta
/// es perder a la mitad ahí mismo. Acá se llena esto una vez -nombre,
/// apellido, correo, carnet- y se compra. Por debajo hay una sesión anónima:
/// es lo que hace que la entrada tenga dueño y que el QR aparezca en Accesos,
/// sin pedirle una contraseña a nadie.
class DatosDeCompraScreen extends ConsumerStatefulWidget {
  const DatosDeCompraScreen({super.key});

  @override
  ConsumerState<DatosDeCompraScreen> createState() => _DatosState();
}

class _DatosState extends ConsumerState<DatosDeCompraScreen> {
  final _form = GlobalKey<FormState>();
  final _nombre = TextEditingController();
  final _apellido = TextEditingController();
  final _email = TextEditingController();
  final _ci = TextEditingController();
  final _telefono = TextEditingController();
  bool _acepta = false;
  bool _ocupado = false;
  String? _error;

  @override
  void dispose() {
    for (final c in [_nombre, _apellido, _email, _ci, _telefono]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _seguir() async {
    if (_ocupado || !(_form.currentState?.validate() ?? false)) return;
    if (!_acepta) {
      setState(() => _error = 'Para continuar tenés que ser mayor de 18 y aceptar los términos.');
      return;
    }
    setState(() {
      _ocupado = true;
      _error = null;
    });
    try {
      final sb = ref.read(supabaseProvider);
      // La sesión anónima se crea recién acá: sólo para quien va a comprar.
      if (sb.auth.currentSession == null) await sb.auth.signInAnonymously();
      await ref.read(repoProvider).datosDeCompra(
        nombre: _nombre.text,
        apellido: _apellido.text,
        email: _email.text,
        ci: _ci.text,
        telefono: _telefono.text,
      );
      ref.invalidate(perfilProvider);
      await ref.read(perfilProvider.future);
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      // Una sesión anónima sin perfil rompe Accesos y no sirve para nada: si
      // el formulario no llegó a guardar, se cierra.
      final sb = ref.read(supabaseProvider);
      if (sb.auth.currentUser?.isAnonymous == true) {
        try {
          if (await ref.read(perfilProvider.future) == null) await sb.auth.signOut();
        } catch (_) {}
      }
      if (mounted) setState(() => _error = mensajeDeError(e));
    } finally {
      if (mounted) setState(() => _ocupado = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Tus datos')),
    body: Form(
      key: _form,
      child: ListView(
        padding: EdgeInsets.fromLTRB(22, 10, 22, 30 + MediaQuery.viewInsetsOf(context).bottom),
        children: [
          Text('Para tu entrada', style: Aftr.titular(32)),
          const SizedBox(height: 8),
          Text(
            'Sin crear cuenta ni contraseña. Tu QR te queda guardado en Accesos, '
            'en este teléfono.',
            style: Aftr.cuerpo(14),
          ),
          const SizedBox(height: 24),
          _campo(_nombre, 'Nombre', autofill: AutofillHints.givenName),
          _campo(_apellido, 'Apellido', autofill: AutofillHints.familyName),
          _campo(
            _email,
            'Correo',
            teclado: TextInputType.emailAddress,
            autofill: AutofillHints.email,
            valida: (t) => RegExp(r'^[^@\s]+@[^@\s]+\.[a-zA-Z]{2,}$').hasMatch(t)
                ? null
                : 'Revisá tu correo',
          ),
          _campo(
            _ci,
            'Carnet de identidad',
            teclado: TextInputType.number,
            formato: [FilteringTextInputFormatter.allow(RegExp(r'[0-9A-Za-z-]'))],
            valida: (t) => t.length >= 4 ? null : 'Revisá tu carnet',
          ),
          _campo(
            _telefono,
            'Celular (opcional)',
            teclado: TextInputType.phone,
            autofill: AutofillHints.telephoneNumber,
            opcional: true,
          ),
          const SizedBox(height: 6),
          // Una sola casilla para las dos cosas: son las dos obligatorias y
          // separarlas es pedir dos toques para lo mismo.
          InkWell(
            onTap: _ocupado ? null : () => setState(() => _acepta = !_acepta),
            borderRadius: BorderRadius.circular(12),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Checkbox(
                  value: _acepta,
                  onChanged: _ocupado ? null : (v) => setState(() => _acepta = v ?? false),
                  side: const BorderSide(color: Aftr.bordeFuerte, width: 1.6),
                  activeColor: Aftr.acento,
                  checkColor: Aftr.fondo,
                ),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Text.rich(
                      TextSpan(children: [
                        TextSpan(
                          text: 'Soy mayor de 18 años y acepto los ',
                          style: Aftr.cuerpo(13, c: Aftr.texto),
                        ),
                        TextSpan(
                          text: 'términos y condiciones',
                          style: Aftr.cuerpo(13, c: Aftr.acento, w: FontWeight.w600),
                        ),
                        TextSpan(text: ' de AFTR.', style: Aftr.cuerpo(13, c: Aftr.texto)),
                      ]),
                    ),
                  ),
                ),
                IconButton(
                  tooltip: 'Leer los términos',
                  onPressed: () => launchUrl(
                    Uri.parse(aftrTerminos),
                    mode: LaunchMode.externalApplication,
                  ),
                  icon: const Icon(Icons.open_in_new_rounded, size: 18, color: Aftr.texto3),
                ),
              ]),
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: 10),
            Text(_error!, style: Aftr.cuerpo(14, c: Aftr.alerta)),
          ],
          const SizedBox(height: 18),
          BotonAftr('Continuar', cargando: _ocupado, onTap: _seguir),
          const SizedBox(height: 14),
          Center(
            child: TextButton(
              onPressed: _ocupado ? null : () => Navigator.of(context).pop(false),
              child: const Text('Mejor entro con mi cuenta'),
            ),
          ),
        ],
      ),
    ),
  );

  Widget _campo(
    TextEditingController c,
    String etiqueta, {
    TextInputType? teclado,
    String? autofill,
    List<TextInputFormatter>? formato,
    String? Function(String)? valida,
    bool opcional = false,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: 14),
    child: TextFormField(
      controller: c,
      enabled: !_ocupado,
      keyboardType: teclado,
      inputFormatters: formato,
      autofillHints: autofill == null ? null : [autofill],
      textCapitalization: teclado == null
          ? TextCapitalization.words
          : TextCapitalization.none,
      decoration: InputDecoration(labelText: etiqueta),
      validator: (t) {
        final v = (t ?? '').trim();
        if (opcional && v.isEmpty) return null;
        if (v.length < 2) return 'Completá este dato';
        return valida?.call(v);
      },
    ),
  );
}
