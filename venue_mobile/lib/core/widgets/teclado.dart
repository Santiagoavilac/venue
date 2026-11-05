import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Cierra el teclado de verdad: suelta el foco y además le pide al sistema que
/// lo esconda. Soltar el foco solo no siempre alcanza.
void esconderTeclado() {
  FocusManager.instance.primaryFocus?.unfocus();
  SystemChannels.textInput.invokeMethod<void>('TextInput.hide');
}

/// ¿Hay un campo de texto enfocado ahora mismo?
bool hayCampoEnfocado() {
  final nodo = FocusManager.instance.primaryFocus;
  final contexto = nodo?.context;
  if (nodo == null || contexto == null || !nodo.hasFocus) return false;
  return contexto.findAncestorWidgetOfExactType<EditableText>() != null;
}

/// El teclado a veces quedaba abierto sin ningún campo enfocado: al cerrar una
/// hoja o un diálogo con texto, o al volver atrás mientras se escribía, el
/// campo se destruye y nadie cierra la conexión de texto, así que el teclado se
/// queda tapando media pantalla y no hay dónde tocar para bajarlo.
///
/// Este vigilante mira el foco y el alto del teclado: si el teclado está
/// levantado y no hay campo escribiendo, lo baja. El retardo evita pelear con
/// el salto de un campo al siguiente, que pasa por un instante sin foco.
class VigilanteDelTeclado extends StatefulWidget {
  const VigilanteDelTeclado({super.key, required this.child});
  final Widget child;

  @override
  State<VigilanteDelTeclado> createState() => _VigilanteDelTecladoState();
}

class _VigilanteDelTecladoState extends State<VigilanteDelTeclado>
    with WidgetsBindingObserver {
  Timer? _espera;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    FocusManager.instance.addListener(_revisar);
  }

  @override
  void dispose() {
    _espera?.cancel();
    FocusManager.instance.removeListener(_revisar);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeMetrics() => _revisar();

  void _revisar() {
    _espera?.cancel();
    _espera = Timer(const Duration(milliseconds: 250), () {
      if (!mounted || hayCampoEnfocado()) return;
      if (MediaQuery.viewInsetsOf(context).bottom <= 0) return;
      SystemChannels.textInput.invokeMethod<void>('TextInput.hide');
    });
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
