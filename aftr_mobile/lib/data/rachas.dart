import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'social_repo.dart';

/// Semanas seguidas saliendo.
///
/// Se cuenta en la puerta: una semana cuenta si la persona entró a un evento
/// -su entrada escaneada o su lugar en una lista marcado-, no por comprar ni
/// por abrir la app. Por semanas y no por noches porque la noche es de fin de
/// semana: una racha de días seguidos se cortaría todos los lunes.
class Racha {
  const Racha({
    required this.usuario,
    required this.nombre,
    required this.semanas,
    required this.viva,
    required this.mejor,
    required this.cerrada,
    this.foto,
    this.fotoKey,
    this.amigo = false,
  });

  final String usuario;
  final String nombre;

  /// Semanas seguidas hasta hoy. Cero si se cortó.
  final int semanas;

  /// Sigue viva: salió esta semana o la pasada. Un martes, la racha del sábado
  /// todavía cuenta.
  final bool viva;

  /// La mejor que tuvo, para que una racha cortada no desaparezca del todo.
  final int mejor;

  /// Ya salió esta semana. Si no, le queda hasta el domingo para no perderla.
  final bool cerrada;
  final String? foto;
  final String? fotoKey;

  /// Amigo aceptado. Si es false, está en la lista porque salieron juntos:
  /// compartieron una mesa o se pasaron una entrada.
  final bool amigo;

  factory Racha.desde(Map<String, dynamic> j) => Racha(
    usuario: j['usuario'] as String? ?? '',
    nombre: j['nombre'] as String? ?? '',
    semanas: (j['semanas'] as num?)?.toInt() ?? 0,
    viva: j['viva'] == true,
    mejor: (j['mejor'] as num?)?.toInt() ?? 0,
    cerrada: j['cerrada'] == true,
    foto: j['foto'] as String?,
    fotoKey: j['foto_key'] as String?,
    amigo: j['amigo'] == true,
  );
}

/// Alguien que apareció en el buscador.
class Encontrado {
  const Encontrado({
    required this.usuario,
    required this.nombre,
    required this.amistad,
    this.foto,
    this.fotoKey,
  });

  final String usuario;
  final String nombre;

  /// no · pedido (se lo mandaste) · te_pidio · amigos
  final String amistad;
  final String? foto;
  final String? fotoKey;

  factory Encontrado.desde(Map<String, dynamic> j) => Encontrado(
    usuario: j['usuario'] as String? ?? '',
    nombre: j['nombre'] as String? ?? '',
    amistad: j['amistad'] as String? ?? 'no',
    foto: j['foto'] as String?,
    fotoKey: j['foto_key'] as String?,
  );
}

class Rachas {
  const Rachas({
    required this.mia,
    required this.gente,
    this.pedidos = const [],
    this.ciudad = const [],
    this.noches = 0,
    this.lugar,
  });
  final Racha mia;

  /// Quienes te pidieron ser amigos y todavía no respondiste.
  final List<Racha> pedidos;

  /// El ranking de la ciudad: sólo nombre de usuario y foto, y sólo de dos
  /// semanas para arriba, para que nadie figure por haber salido una vez.
  final List<Racha> ciudad;

  /// Noches distintas de los últimos 30 días.
  final int noches;

  /// Donde más fue.
  final String? lugar;

  /// Con quién salió de verdad -se pasaron una entrada o compartieron mesa-,
  /// de la racha más larga a la más corta. No hay lista de amigos que armar.
  final List<Racha> gente;

  /// Cuántos de los suyos la tienen más larga que él.
  int get porDelante => gente.where((g) => g.semanas > mia.semanas).length;
}

final rachasProvider = FutureProvider.autoDispose<Rachas>((ref) async {
  final r = await ref.watch(socialRepoProvider).rachas();
  final t = mapaSocial(r['temporada']);
  return Rachas(
    mia: Racha.desde(mapaSocial(r['mia'])),
    gente: [for (final x in listaSocial(r['gente'])) Racha.desde(x)],
    pedidos: [for (final x in listaSocial(r['pedidos'])) Racha.desde(x)],
    ciudad: [for (final x in listaSocial(r['ciudad'])) Racha.desde(x)],
    noches: (t['noches'] as num?)?.toInt() ?? 0,
    lugar: t['lugar'] as String?,
  );
});
