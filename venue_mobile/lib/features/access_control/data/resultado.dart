/// Veredicto de un escaneo. Es lo único que el portero necesita leer.
enum Veredicto {
  pasa('PASA'),
  yaIngreso('YA INGRESÓ'),
  noValido('NO VÁLIDO'),
  eventoIncorrecto('EVENTO INCORRECTO'),
  fueraDeHorario('FUERA DE HORARIO'),
  sinConexion('SIN CONEXIÓN'),
  sinPermiso('SIN PERMISO'),
  credencial('CREDENCIAL');

  const Veredicto(this.texto);
  final String texto;

  bool get dejaPasar => this == pasa;
}

/// Una lista vista desde la credencial: cuánto tiene la persona esta noche.
class ListaCredencial {
  const ListaCredencial({
    required this.nombre,
    required this.anotados,
    required this.ingresaron,
    this.cupo,
    this.entraHasta,
    this.especial = false,
  });

  final String nombre;
  final int? cupo;
  final int anotados;
  final int ingresaron;
  final String? entraHasta;
  final bool especial;

  factory ListaCredencial.desde(Map<String, dynamic> j) => ListaCredencial(
        nombre: j['nombre'] as String? ?? 'Lista',
        cupo: (j['cupo'] as num?)?.toInt(),
        anotados: (j['anotados'] as num?)?.toInt() ?? 0,
        ingresaron: (j['ingresaron'] as num?)?.toInt() ?? 0,
        entraHasta: j['entra_hasta'] as String?,
        especial: j['especial'] == true,
      );
}

/// La ficha que ve el portero al escanear la credencial de alguien del equipo.
class Credencial {
  const Credencial({
    required this.nombre,
    required this.usuario,
    this.rol,
    this.team,
    this.fotoUrl,
    this.activo = true,
    this.delBoliche = true,
    this.sinTope = false,
    this.listas = const [],
  });

  final String nombre;
  final String usuario;
  final String? rol;
  final String? team;
  final String? fotoUrl;
  final bool activo;
  final bool delBoliche;
  final bool sinTope;
  final List<ListaCredencial> listas;

  bool get valida => activo && delBoliche;

  factory Credencial.desde(Map<String, dynamic> j) => Credencial(
        nombre: j['nombre'] as String? ?? '',
        usuario: j['usuario'] as String? ?? '',
        rol: j['rol'] as String?,
        team: j['team'] as String?,
        fotoUrl: j['foto_url'] as String?,
        activo: j['activo'] != false,
        delBoliche: j['del_boliche'] != false,
        sinTope: j['sin_tope'] == true,
        listas: (j['listas'] as List? ?? const [])
            .map((x) => ListaCredencial.desde(Map<String, dynamic>.from(x as Map)))
            .toList(),
      );
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
    this.credencial,
  });

  final Veredicto veredicto;

  /// Solo cuando se escaneó una credencial.
  final Credencial? credencial;
  final String codigo;
  final String? nombre;

  /// Qué es: "Entrada prepagada", "Manilla de combo", nombre de la lista…
  final String? tipo;

  /// Quién lo trajo: relacionador y team.
  final String? quien;
  final String? detalle;

  /// Hora del ingreso (la de ahora si pasa; la anterior si ya había entrado).
  final DateTime? hora;

  /// Traduce la respuesta de `ver_credencial`.
  factory ResultadoEscaneo.desdeCredencial(Map<String, dynamic> r, {required String codigo}) {
    if (r['resultado'] != 'credencial') {
      return ResultadoEscaneo(
        veredicto: Veredicto.noValido,
        codigo: codigo,
        tipo: 'Credencial no válida',
        detalle: 'Este QR ya no sirve: puede ser uno viejo. Pedile que lo genere de nuevo.',
      );
    }
    final c = Credencial.desde(r);
    return ResultadoEscaneo(
      veredicto: c.valida ? Veredicto.credencial : Veredicto.noValido,
      codigo: codigo,
      nombre: c.nombre,
      tipo: !c.activo
          ? 'Cuenta pausada'
          : !c.delBoliche
              ? 'No es de este boliche'
              : null,
      credencial: c,
    );
  }

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
