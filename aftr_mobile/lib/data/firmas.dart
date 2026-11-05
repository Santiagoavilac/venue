import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/networking/supabase.dart';

/// Lo que devuelve la función de firma: `{urls: {clave: url}, vence_en: 600}`.
typedef Pedir = Future<Map<String, dynamic>> Function(List<String> claves);

/// Cambia claves opacas de archivo por URL firmadas, todas juntas.
///
/// Antes cada archivo se firmaba por separado y contra storage: el visor pedía
/// una firma por historia y la fila de círculos una por foto de perfil, así que
/// abrir el feed eran veinte llamadas. Y la firma duraba 60 segundos y se
/// guardaba sin vencimiento, de modo que pasado el minuto la imagen se rompía
/// sin que nadie volviera a pedirla.
///
/// Acá: las claves que se piden en el mismo cuadro salen en una sola llamada,
/// y cada URL se guarda hasta el 80 % de su plazo, para volver a firmarla antes
/// de que se venza y no después.
class Firmas {
  Firmas(SupabaseClient sb, {Pedir? pedir})
    : _pedirlas = pedir ?? _porFuncion(sb);

  /// Se inyecta para poder probar el agrupado y el vencimiento sin red.
  final Pedir _pedirlas;

  static Pedir _porFuncion(SupabaseClient sb) => (claves) async {
    final r = await sb.functions.invoke(
      'historias-media',
      body: {'accion': 'firmar', 'claves': claves},
    );
    return Map<String, dynamic>.from(r.data as Map);
  };

  final _cache = <String, ({String url, DateTime hasta})>{};
  final _esperando = <String, List<Completer<String?>>>{};
  Timer? _junta;

  /// El límite de la función: más claves se parten en varias llamadas.
  static const _max = 60;

  String? enCache(String clave) {
    final c = _cache[clave];
    if (c == null) return null;
    if (c.hasta.isBefore(DateTime.now())) {
      _cache.remove(clave);
      return null;
    }
    return c.url;
  }

  Future<String?> url(String clave) {
    final listo = enCache(clave);
    if (listo != null) return Future.value(listo);
    final espera = Completer<String?>();
    (_esperando[clave] ??= []).add(espera);
    // 40 ms: lo que tarda en pintarse una fila de círculos. Lo que se pida en
    // ese rato viaja junto.
    _junta ??= Timer(const Duration(milliseconds: 40), _pedir);
    return espera.future;
  }

  Future<void> _pedir() async {
    _junta = null;
    final claves = _esperando.keys.take(_max).toList();
    if (claves.isEmpty) return;
    final esperan = {for (final c in claves) c: _esperando.remove(c)!};
    if (_esperando.isNotEmpty) _junta = Timer(Duration.zero, _pedir);
    try {
      final datos = await _pedirlas(claves);
      final urls = Map<String, dynamic>.from(datos['urls'] as Map? ?? {});
      final segundos = (datos['vence_en'] as num?)?.toInt() ?? 600;
      final hasta = DateTime.now().add(
        Duration(seconds: (segundos * 0.8).round()),
      );
      for (final clave in claves) {
        final url = urls[clave] as String?;
        // sólo se guardan los éxitos: una firma que falló no se cachea, si no
        // el error quedaría pegado hasta que la persona cierre la app
        if (url != null) _cache[clave] = (url: url, hasta: hasta);
        for (final e in esperan[clave]!) {
          e.complete(url);
        }
      }
    } catch (_) {
      for (final clave in claves) {
        for (final e in esperan[clave]!) {
          e.complete(null);
        }
      }
    }
  }
}

final firmasProvider = Provider<Firmas>(
  (ref) => Firmas(ref.watch(supabaseProvider)),
);

/// La URL de un archivo por su clave. Varias de estas en el mismo cuadro son
/// una sola llamada.
final mediaFirmadaProvider = FutureProvider.family<String?, String>(
  (ref, clave) => ref.watch(firmasProvider).url(clave),
);
