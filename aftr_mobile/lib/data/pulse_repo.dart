import 'dart:async';
import 'dart:math';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../core/networking/supabase.dart';

typedef DatosPulse = Map<String, dynamic>;

/// Dinero de entrada en texto decimal. Nunca multiplicar un double por 100.
int? centavosDe(String texto) {
  final s = texto.trim().replaceAll(',', '.');
  if (!RegExp(r'^\d{1,10}(\.\d{1,2})?$').hasMatch(s)) return null;
  final p = s.split('.');
  return int.parse(p[0]) * 100 +
      int.parse(p.length == 1 ? '0' : p[1].padRight(2, '0'));
}

String importePulse(Object? valor) {
  final n = valor is num ? valor.toInt() : int.tryParse('$valor') ?? 0;
  return '${n < 0 ? '-' : ''}${n.abs() ~/ 100}.${(n.abs() % 100).toString().padLeft(2, '0')}';
}

String nuevaOperacion() {
  final r = Random.secure();
  final b = List.generate(16, (_) => r.nextInt(256));
  b[6] = (b[6] & 15) | 64;
  b[8] = (b[8] & 63) | 128;
  final s = b.map((x) => x.toRadixString(16).padLeft(2, '0')).join();
  return '${s.substring(0, 8)}-${s.substring(8, 12)}-${s.substring(12, 16)}-${s.substring(16, 20)}-${s.substring(20)}';
}

class PulseRepo {
  PulseRepo(this.sb);
  final SupabaseClient sb;
  Future<dynamic> rpc(String nombre, [DatosPulse p = const {}]) =>
      sb.rpc(nombre, params: p);
  Future<DatosPulse> saldo() async =>
      Map<String, dynamic>.from(await rpc('aftr_pulse') as Map);
  Future<DatosPulse> mesas() async =>
      Map<String, dynamic>.from(await rpc('aftr_mis_mesas') as Map);
  Future<DatosPulse> carta(String mesa) async => Map<String, dynamic>.from(
    await rpc('aftr_carta_mesa', {'p_mesa': mesa}) as Map,
  );
  Future<List<dynamic>> pedidos(String mesa) async => List<dynamic>.from(
    await rpc('aftr_mis_pedidos_mesa', {'p_mesa': mesa}) as List,
  );
  Future<DatosPulse> recargar(int centavos, String clave) async =>
      Map<String, dynamic>.from(
        await rpc('aftr_recargar_pulse', {
              'p_centavos': centavos,
              'p_client_key': clave,
            })
            as Map,
      );
  Future<void> pagarOrden(String orden) async {
    await rpc('aftr_pagar_pulse', {'p_orden': orden});
  }

  Future<DatosPulse> pedir(
    String mesa,
    List<DatosPulse> items,
    String metodo,
    String clave,
    String observaciones,
  ) async => Map<String, dynamic>.from(
    await rpc('aftr_pedir_mesa', {
          'p_mesa': mesa,
          'p_items': items,
          'p_metodo': metodo,
          'p_client_key': clave,
          'p_observaciones': observaciones,
        })
        as Map,
  );
}

final pulseRepoProvider = Provider(
  (ref) => PulseRepo(ref.watch(supabaseProvider)),
);

void _escuchar(Ref ref, List<String> tablas, String nombre) {
  final sb = ref.watch(supabaseProvider);
  final uid = ref.watch(usuarioIdProvider);
  if (uid == null) return;
  final canal = sb.channel('aftr-$nombre-$uid');
  Timer? espera;
  for (final t in tablas) {
    canal.onPostgresChanges(
      event: PostgresChangeEvent.all,
      schema: 'public',
      table: t,
      filter: PostgresChangeFilter(
        type: PostgresChangeFilterType.eq,
        column: 'cliente_id',
        value: uid,
      ),
      callback: (_) {
        espera?.cancel();
        espera = Timer(const Duration(milliseconds: 250), ref.invalidateSelf);
      },
    );
  }
  canal.subscribe();
  ref.onDispose(() {
    espera?.cancel();
    sb.removeChannel(canal);
  });
}

final pulseSaldoProvider = FutureProvider.autoDispose<DatosPulse>((ref) {
  _escuchar(ref, [
    'pulse_cuentas',
    'pulse_recargas',
    'pulse_movimientos',
  ], 'pulse');
  return ref.watch(pulseRepoProvider).saldo();
});
final misMesasProvider = FutureProvider.autoDispose<DatosPulse>((ref) {
  _escuchar(ref, ['aftr_mesa_miembros', 'aftr_avisos'], 'mesas');
  return ref.watch(pulseRepoProvider).mesas();
});
final cartaMesaProvider = FutureProvider.autoDispose.family<DatosPulse, String>(
  (ref, mesa) => ref.watch(pulseRepoProvider).carta(mesa),
);
final pedidosMesaProvider = FutureProvider.autoDispose
    .family<List<dynamic>, String>((ref, mesa) {
      _escuchar(ref, ['aftr_bar_pedidos'], 'pedidos-$mesa');
      return ref.watch(pulseRepoProvider).pedidos(mesa);
    });
