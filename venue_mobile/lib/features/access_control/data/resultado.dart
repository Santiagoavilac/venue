/// Veredicto de un escaneo. Es lo único que el portero necesita leer.
enum Veredicto {
  pasa('PASA'),
  yaIngreso('YA INGRESÓ'),
  noValido('NO VÁLIDO'),
  eventoIncorrecto('EVENTO INCORRECTO'),
  fueraDeHorario('FUERA DE HORARIO'),
  sinConexion('SIN CONEXIÓN'),
  sinPermiso('SIN PERMISO');

  const Veredicto(this.texto);
  final String texto;

  bool get dejaPasar => this == pasa;
}

class ResultadoEscaneo {
  const ResultadoEscaneo({
    required this.veredicto,
    required this.codigo,
    this.nombre,
    this.tipo,
    this.quien,
    this.detalle,
    this.hora,
  });

  final Veredicto veredicto;
  final String codigo;
  final String? nombre;

  /// Qué es: "Entrada prepagada", "Manilla de combo", nombre de la lista…
  final String? tipo;

  /// Quién lo trajo: relacionador y team.
  final String? quien;
  final String? detalle;

  /// Hora del ingreso (la de ahora si pasa; la anterior si ya había entrado).
  final DateTime? hora;

  /// Traduce la respuesta de `validar_entrada` / `validar_qr_lista`.
  ///
  /// Una respuesta que no se reconoce se trata como NO VÁLIDO: ante la duda,
  /// la puerta no se abre.
  factory ResultadoEscaneo.desdeServidor(
    Map<String, dynamic> r, {
    required String codigo,
    required bool esLista,
    required DateTime ahora,
  }) {
    final nombre = r['cliente'] as String?;
    final rrpp = r['rrpp'] as String?;
    final team = r['team'] as String?;
    final mesa = r['mesa'] as String?;
    final lista = r['lista_nombre'] as String?;
    final quien = [
      if (rrpp != null && rrpp.isNotEmpty) rrpp,
      if (team != null && team.isNotEmpty) 'Team $team',
    ].join(' · ');
    final cod = r['code'] as String? ?? codigo;

    String tipoBase() {
      if (esLista || lista != null) return lista ?? 'Lista';
      if (mesa != null) return 'Manilla de combo · Mesa $mesa';
      if (r['sin_tope'] == true) return 'Entrada de la casa';
      return 'Entrada prepagada';
    }

    switch (r['resultado']) {
      case 'valida':
        return ResultadoEscaneo(
          veredicto: Veredicto.pasa,
          codigo: cod,
          nombre: nombre,
          tipo: tipoBase(),
          quien: quien.isEmpty ? null : quien,
          detalle: r['sin_tope'] == true ? 'Sin tope de horario' : null,
          hora: ahora,
        );
      case 'usada':
        return ResultadoEscaneo(
          veredicto: Veredicto.yaIngreso,
          codigo: cod,
          nombre: nombre,
          tipo: tipoBase(),
          quien: quien.isEmpty ? null : quien,
          detalle: 'Ya fue usada. No vuelve a entrar.',
          hora: DateTime.tryParse(r['used_at'] as String? ?? '')?.toLocal(),
        );
      case 'anulada':
        return ResultadoEscaneo(
          veredicto: Veredicto.noValido,
          codigo: cod,
          nombre: nombre,
          tipo: 'Entrada anulada',
          detalle: 'El vendedor anuló esta entrada.',
        );
      case 'fuera_hora':
        return ResultadoEscaneo(
          veredicto: Veredicto.fueraDeHorario,
          codigo: cod,
          nombre: nombre,
          tipo: tipoBase(),
          detalle: 'El ingreso con QR ya cerró para este evento.',
        );
      case 'fuera_horario':
        final limite = r['limite'] as String?;
        return ResultadoEscaneo(
          veredicto: Veredicto.fueraDeHorario,
          codigo: cod,
          nombre: nombre,
          tipo: '${lista ?? 'Lista'} cerrada',
          detalle: limite == null ? null : 'Entraba hasta $limite',
        );
      default:
        return ResultadoEscaneo(
          veredicto: Veredicto.noValido,
          codigo: cod,
          detalle: '#$cod no existe para este evento.',
        );
    }
  }
}
