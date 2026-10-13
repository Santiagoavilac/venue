import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../networking/supabase.dart';

/// Cambios en vivo de un evento. Emite el nombre de la tabla que cambió
/// (`mesas`, `entradas`, `registros`), agrupando ráfagas: en la puerta varios
/// porteros escanean a la vez y cada validación llega como un evento.
///
/// Realtime respeta RLS: solo llegan cambios de filas que la persona puede
/// leer.
final cambiosEventoProvider =
    StreamProvider.autoDispose.family<Set<String>, String>((ref, eventoId) {
  final sb = ref.watch(supabaseProvider);
  final salida = StreamController<Set<String>>();
  final acumulado = <String>{};
  Timer? espera;

  void anotar(String tabla) {
    acumulado.add(tabla);
    espera?.cancel();
    espera = Timer(const Duration(milliseconds: 900), () {
      if (!salida.isClosed) salida.add({...acumulado});
      acumulado.clear();
    });
  }

  var canal = sb.channel('rt-$eventoId');
  for (final tabla in const ['mesas', 'entradas', 'registros']) {
    canal = canal.onPostgresChanges(
      event: PostgresChangeEvent.all,
      schema: 'public',
      table: tabla,
      filter: PostgresChangeFilter(
          type: PostgresChangeFilterType.eq, column: 'evento_id', value: eventoId),
      callback: (_) => anotar(tabla),
    );
  }
  canal.subscribe();

  ref.onDispose(() {
    espera?.cancel();
    sb.removeChannel(canal);
    salida.close();
  });
  return salida.stream;
});
