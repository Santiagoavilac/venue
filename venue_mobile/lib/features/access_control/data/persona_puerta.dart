/// Una fila de la búsqueda de puerta (`buscar_registros`): un invitado de
/// lista o una entrada/manilla, con su estado de ingreso.
class PersonaPuerta {
  const PersonaPuerta({
    required this.esEntrada,
    required this.nombre,
    this.id,
    this.codigo,
    this.lista,
    this.rrpp,
    this.estado,
    this.sinTope = false,
    this.ingresoAt,
    this.filtroAt,
  });

  /// true = entrada o manilla con QR; false = invitado de lista.
  final bool esEntrada;
  final String nombre;

  /// Id del registro (invitados de lista).
  final String? id;

  /// Código de la entrada (entradas y manillas).
  final String? codigo;
  final String? lista;
  final String? rrpp;
  final String? estado;

  /// Entrada "de la casa": sin tope de horario y no se puede filtrar.
  final bool sinTope;
  final DateTime? ingresoAt;
  final DateTime? filtroAt;

  bool get ingreso => ingresoAt != null;
  bool get filtrada => filtroAt != null;
  bool get anulada => estado == 'anulada';

  factory PersonaPuerta.desde(Map<String, dynamic> j) {
    DateTime? f(String k) => DateTime.tryParse(j[k] as String? ?? '')?.toLocal();
    return PersonaPuerta(
      esEntrada: j['tipo'] == 'entrada',
      nombre: j['nombre'] as String? ?? '',
      id: j['id'] as String?,
      codigo: j['code'] as String?,
      lista: j['lista'] as String?,
      rrpp: j['rrpp'] as String?,
      estado: j['estado'] as String?,
      sinTope: j['sin_tope'] == true,
      ingresoAt: f('ingreso_at'),
      filtroAt: f('filtro_at'),
    );
  }

  /// Orden de la lista en puerta (el mismo de la web): arriba los que ya
  /// ingresaron (el más reciente primero), en el medio los pendientes por
  /// nombre, y al fondo los que no pasaron el filtro.
  static int comparar(PersonaPuerta a, PersonaPuerta b) {
    if (a.filtrada != b.filtrada) return a.filtrada ? 1 : -1;
    if (a.ingreso != b.ingreso) return a.ingreso ? -1 : 1;
    if (a.ingreso && b.ingreso) return b.ingresoAt!.compareTo(a.ingresoAt!);
    return a.nombre.toLowerCase().compareTo(b.nombre.toLowerCase());
  }

  /// Aplica el "filtro discreto" de la puerta: si la búsqueda empieza con un
  /// espacio, solo se muestran los de la casa (el resto queda oculto a la
  /// vista de quien mira la pantalla).
  static List<PersonaPuerta> ordenar(List<PersonaPuerta> filas,
      {bool discreto = false}) {
    final l = filas.where((r) => !discreto || r.sinTope).toList()
      ..sort(comparar);
    return l;
  }
}

class Relacionador {
  const Relacionador({
    required this.nombre,
    required this.usuario,
    required this.team,
    required this.esJefe,
  });
  final String nombre;
  final String usuario;
  final String team;
  final bool esJefe;

  factory Relacionador.desde(Map<String, dynamic> j) => Relacionador(
        nombre: j['nombre'] as String? ?? '',
        usuario: j['usuario'] as String? ?? '',
        team: j['team'] as String? ?? 'Sin team',
        esJefe: j['rol'] == 'jefe',
      );
}
