/// Lo que trae un QR de Venue, ya interpretado.
///
/// Formatos (los mismos que genera y lee la web, ver `validar` en app.js):
///   `EVT:<evento>:<código>`  entrada prepagada o manilla de mesa
///   `LST:<evento>:<código>`  invitado de lista
///   `CRD|<boliche>|<código>` credencial de un relacionador (no es entrada)
///   `<código>`               código suelto, tipeado a mano
/// El separador puede ser `:` o `|`.
class QrLeido {
  const QrLeido({
    required this.codigo,
    required this.esLista,
    this.eventoId,
    this.esCredencial = false,
  });

  final String codigo;
  final bool esLista;

  /// La credencial de una persona del equipo: se muestra su ficha, no se
  /// marca ningún ingreso.
  final bool esCredencial;

  /// Evento al que pertenece según el QR; null si era un código suelto.
  final String? eventoId;

  bool esDeOtroEvento(String eventoActual) =>
      !esCredencial && eventoId != null && eventoId != eventoActual;

  static final _lista = RegExp(r'LST[:|]([\w-]+)[:|](\w+)', caseSensitive: false);
  static final _entrada = RegExp(r'EVT[:|]([\w-]+)[:|](\w+)', caseSensitive: false);
  static final _credencial = RegExp(r'^CRD[:|]([\w-]+)[:|](\w+)$', caseSensitive: false);

  /// Devuelve null si no hay nada que validar.
  static QrLeido? interpretar(String? crudo) {
    final texto = (crudo ?? '').trim();
    if (texto.isEmpty) return null;

    final c = _credencial.firstMatch(texto);
    if (c != null) {
      return QrLeido(codigo: c.group(2)!.toUpperCase(), esLista: false, esCredencial: true);
    }
    final l = _lista.firstMatch(texto);
    final e = l == null ? _entrada.firstMatch(texto) : null;
    final m = l ?? e;
    final codigo = (m?.group(2) ?? texto).replaceFirst(RegExp(r'^#'), '').toUpperCase();
    if (codigo.isEmpty) return null;
    return QrLeido(
      codigo: codigo,
      esLista: l != null,
      eventoId: m?.group(1)?.toLowerCase(),
    );
  }
}
