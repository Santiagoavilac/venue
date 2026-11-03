import 'dart:math';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/networking/supabase.dart';

String bsCentavos(Object? n) {
  final v = n is num ? n.toInt() : int.tryParse('$n') ?? 0;
  return '${v < 0 ? '-' : ''}${v.abs() ~/ 100}.${(v.abs() % 100).toString().padLeft(2, '0')}';
}

int? leerCentavos(String s) {
  s = s.trim().replaceAll(',', '.');
  if (!RegExp(r'^\d{1,10}(\.\d{1,2})?$').hasMatch(s)) return null;
  final p = s.split('.');
  return int.parse(p[0]) * 100 +
      int.parse(p.length > 1 ? p[1].padRight(2, '0') : '0');
}

String claveAftr() {
  final r = Random.secure();
  final b = List.generate(16, (_) => r.nextInt(256));
  b[6] = (b[6] & 15) | 64;
  b[8] = (b[8] & 63) | 128;
  final s = b.map((x) => x.toRadixString(16).padLeft(2, '0')).join();
  return '${s.substring(0, 8)}-${s.substring(8, 12)}-${s.substring(12, 16)}-${s.substring(16, 20)}-${s.substring(20)}';
}

class OperacionAftrRepo {
  OperacionAftrRepo(this.sb);
  final SupabaseClient sb;
  Future<dynamic> rpc(String fn, [Map<String, dynamic> p = const {}]) =>
      sb.rpc(fn, params: p);
  Future<List<dynamic>> pedidos(String evento) async => List<dynamic>.from(
    await rpc('venue_pedidos_mesa', {'p_evento': evento}) as List,
  );
  Future<Map<String, dynamic>> catalogo(String club) async =>
      Map<String, dynamic>.from(
        await rpc('venue_catalogo_aftr', {'p_club': club}) as Map,
      );
}

final operacionAftrProvider = Provider(
  (ref) => OperacionAftrRepo(ref.watch(supabaseProvider)),
);
