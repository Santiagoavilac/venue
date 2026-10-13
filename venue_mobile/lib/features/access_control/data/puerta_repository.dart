import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/networking/supabase.dart';
import 'qr.dart';
import 'resultado.dart';

final puertaRepositoryProvider = Provider<PuertaRepository>(
  (ref) => PuertaRepository(ref.watch(supabaseProvider)),
);

class Aforo {
  const Aforo({required this.ingresaron, required this.total});
  final int ingresaron;
  final int total;
  int get pendientes => total > ingresaron ? total - ingresaron : 0;
}

class PuertaRepository {
  PuertaRepository(this._sb);
  final SupabaseClient _sb;

  /// Valida un QR contra el servidor. Nunca lanza: todo desenlace —incluida
  /// la falta de señal— es un [ResultadoEscaneo] que la pantalla sabe pintar.
  ///
  /// La validación es SIEMPRE en línea: el servidor consume la entrada en
  /// una sola operación atómica, que es lo que impide que dos porteros
  /// dejen pasar el mismo QR. Sin señal no se deja pasar a nadie por QR.
  Future<ResultadoEscaneo> validar({
    required String eventoId,
    required String crudo,
    DateTime Function() reloj = DateTime.now,
  }) async {
    final qr = QrLeido.interpretar(crudo);
    if (qr == null) {
      return const ResultadoEscaneo(
        veredicto: Veredicto.noValido,
        codigo: '',
        detalle: 'El código está vacío.',
      );
    }
    if (qr.esDeOtroEvento(eventoId)) {
      return ResultadoEscaneo(
        veredicto: Veredicto.eventoIncorrecto,
        codigo: qr.codigo,
        detalle: 'Este QR es de otro evento o de otro boliche.',
      );
    }
    try {
      final r = await _sb
          .rpc(
            qr.esLista ? 'validar_qr_lista' : 'validar_entrada',
            params: {'p_evento': eventoId, 'p_code': qr.codigo},
          )
          .timeout(const Duration(seconds: 12));
      return ResultadoEscaneo.desdeServidor(
        Map<String, dynamic>.from(r as Map),
        codigo: qr.codigo,
        esLista: qr.esLista,
        ahora: reloj(),
      );
    } catch (e) {
      if (esFallaDeRed(e)) {
        return ResultadoEscaneo(
          veredicto: Veredicto.sinConexion,
          codigo: qr.codigo,
          detalle:
              'No se pudo verificar el QR. No dejes pasar por QR hasta que vuelva la señal.',
        );
      }
      if (e is PostgrestException && (e.code == '42501' || e.code == '28000')) {
        return ResultadoEscaneo(
          veredicto: Veredicto.sinPermiso,
          codigo: qr.codigo,
          detalle: 'Tu cuenta no puede validar ingresos en este evento.',
        );
      }
      return ResultadoEscaneo(
        veredicto: Veredicto.noValido,
        codigo: qr.codigo,
        detalle: mensajeDeError(e),
      );
    }
  }

  Future<Aforo> aforo(String eventoId) async {
    final r = Map<String, dynamic>.from(
      await _sb.rpc('resumen_evento', params: {'p_evento': eventoId}) as Map,
    );
    int n(String k) => (r[k] as num?)?.toInt() ?? 0;
    return Aforo(ingresaron: n('qr_usados'), total: n('qr_total'));
  }
}

final aforoProvider = FutureProvider.family<Aforo, String>(
  (ref, eventoId) => ref.watch(puertaRepositoryProvider).aforo(eventoId),
);
