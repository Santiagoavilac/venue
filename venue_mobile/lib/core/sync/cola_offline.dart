import 'dart:convert';
import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../networking/supabase.dart';

/// Identificador único generado en el teléfono. Se usa como clave de
/// idempotencia: si una operación se reenvía, el servidor la reconoce.
String nuevoId() {
  final r = Random.secure();
  final b = List<int>.generate(16, (_) => r.nextInt(256));
  b[6] = (b[6] & 0x0f) | 0x40;
  b[8] = (b[8] & 0x3f) | 0x80;
  final h = b.map((x) => x.toRadixString(16).padLeft(2, '0')).join();
  return '${h.substring(0, 8)}-${h.substring(8, 12)}-${h.substring(12, 16)}-${h.substring(16, 20)}-${h.substring(20)}';
}

/// Una operación que no pudo enviarse por falta de señal.
class Pendiente {
  const Pendiente({
    required this.id,
    required this.rpc,
    required this.params,
    required this.etiqueta,
    required this.usuarioId,
    required this.at,
  });

  final String id;
  final String rpc;
  final Map<String, dynamic> params;

  /// Texto para mostrarle a la persona ("Ingreso de Ana Paz").
  final String etiqueta;

  /// Quién la generó: nunca se envía con la sesión de otra cuenta.
  final String usuarioId;
  final DateTime at;

  Map<String, dynamic> aJson() => {
        'id': id, 'rpc': rpc, 'params': params, 'etiqueta': etiqueta,
        'usuario': usuarioId, 'at': at.toIso8601String(),
      };

  factory Pendiente.desde(Map<String, dynamic> j) => Pendiente(
        id: j['id'] as String,
        rpc: j['rpc'] as String,
        params: Map<String, dynamic>.from(j['params'] as Map),
        etiqueta: j['etiqueta'] as String? ?? '',
        usuarioId: j['usuario'] as String? ?? '',
        at: DateTime.tryParse(j['at'] as String? ?? '') ?? DateTime.now(),
      );
}

/// Dónde se guarda la cola. Abstracto para poder probarla sin el teléfono.
abstract class AlmacenCola {
  Future<String?> leer();
  Future<void> guardar(String? json);
}

class AlmacenPreferencias implements AlmacenCola {
  static const _clave = 'venue.cola.v1';
  @override
  Future<String?> leer() async =>
      (await SharedPreferences.getInstance()).getString(_clave);
  @override
  Future<void> guardar(String? json) async {
    final p = await SharedPreferences.getInstance();
    json == null ? await p.remove(_clave) : await p.setString(_clave, json);
  }
}

class ResultadoDrenado {
  const ResultadoDrenado(this.enviadas, this.rechazadas, this.quedan);
  final int enviadas;

  /// El servidor las rechazó (regla de negocio o permiso): se descartan y se
  /// informan; reintentarlas para siempre no las va a arreglar.
  final List<({Pendiente op, String motivo})> rechazadas;
  final int quedan;
}

/// Cola de operaciones sin señal.
///
/// Solo admite operaciones que el servidor puede recibir dos veces sin
/// duplicar efectos (check-in de lista, venta de barra con `p_client_key`).
/// La validación de QR NO pasa por acá: exige respuesta del servidor.
class ColaOffline {
  ColaOffline(this._almacen);
  final AlmacenCola _almacen;

  Future<List<Pendiente>> leer() async {
    try {
      final t = await _almacen.leer();
      if (t == null || t.isEmpty) return [];
      return (jsonDecode(t) as List)
          .map((x) => Pendiente.desde(Map<String, dynamic>.from(x as Map)))
          .toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> _escribir(List<Pendiente> l) => _almacen
      .guardar(l.isEmpty ? null : jsonEncode(l.map((p) => p.aJson()).toList()));

  Future<void> encolar(Pendiente p) async => _escribir([...await leer(), p]);

  /// Borra lo pendiente (al cerrar sesión: la cola guarda nombres de clientes).
  Future<void> vaciar() => _almacen.guardar(null);

  /// Envía lo pendiente del usuario, en orden. Se detiene en la primera falla
  /// de red (no hay señal: no tiene sentido seguir) y conserva el resto.
  Future<ResultadoDrenado> drenar(
    String usuarioId,
    Future<void> Function(Pendiente) enviar,
  ) async {
    final todas = await leer();
    final quedan = <Pendiente>[];
    final rechazadas = <({Pendiente op, String motivo})>[];
    var enviadas = 0, sinRed = false;
    for (final p in todas) {
      if (sinRed || p.usuarioId != usuarioId) {
        quedan.add(p);
        continue;
      }
      try {
        await enviar(p);
        enviadas++;
      } catch (e) {
        if (esFallaDeRed(e)) {
          sinRed = true;
          quedan.add(p);
        } else {
          rechazadas.add((op: p, motivo: mensajeDeError(e)));
        }
      }
    }
    await _escribir(quedan);
    return ResultadoDrenado(
        enviadas, rechazadas, quedan.where((p) => p.usuarioId == usuarioId).length);
  }
}

final colaOfflineProvider =
    Provider<ColaOffline>((ref) => ColaOffline(AlmacenPreferencias()));

/// Cantidad de operaciones sin enviar, para el aviso fijo en pantalla.
class Pendientes extends Notifier<int> {
  @override
  int build() {
    refrescar();
    return 0;
  }

  Future<void> refrescar() async {
    final uid = ref.read(supabaseProvider).auth.currentUser?.id;
    final l = await ref.read(colaOfflineProvider).leer();
    state = l.where((p) => p.usuarioId == uid).length;
  }

  /// Ejecuta una RPC tolerando cortes: si no hay señal queda en la cola y
  /// devuelve `encolada = true`. Un rechazo del servidor se propaga.
  Future<({bool encolada, dynamic dato})> ejecutar(
    String rpc,
    Map<String, dynamic> params,
    String etiqueta,
  ) async {
    final sb = ref.read(supabaseProvider);
    try {
      final d = await sb.rpc(rpc, params: params).timeout(const Duration(seconds: 12));
      return (encolada: false, dato: d);
    } catch (e) {
      if (!esFallaDeRed(e)) rethrow;
      await ref.read(colaOfflineProvider).encolar(Pendiente(
            id: nuevoId(), rpc: rpc, params: params, etiqueta: etiqueta,
            usuarioId: sb.auth.currentUser?.id ?? '', at: DateTime.now(),
          ));
      await refrescar();
      return (encolada: true, dato: null);
    }
  }

  Future<ResultadoDrenado?> drenar() async {
    final SupabaseClient sb = ref.read(supabaseProvider);
    final uid = sb.auth.currentUser?.id;
    if (uid == null) return null;
    final r = await ref.read(colaOfflineProvider).drenar(
        uid, (p) => sb.rpc(p.rpc, params: p.params).timeout(const Duration(seconds: 12)));
    await refrescar();
    return r;
  }
}

final pendientesProvider = NotifierProvider<Pendientes, int>(Pendientes.new);
