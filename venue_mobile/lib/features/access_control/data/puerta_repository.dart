import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/networking/supabase.dart';
import 'persona_puerta.dart';
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
      if (qr.esCredencial) {
        final r = await _sb.rpc('ver_credencial',
            params: {'p_evento': eventoId, 'p_code': qr.codigo}).timeout(const Duration(seconds: 12));
        return ResultadoEscaneo.desdeCredencial(Map<String, dynamic>.from(r as Map), codigo: qr.codigo);
      }
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
      if (qr.esCredencial && e is PostgrestException && e.code == 'PGRST202') {
        return ResultadoEscaneo(
          veredicto: Veredicto.noValido,
          codigo: qr.codigo,
          detalle: 'Falta preparar la base para las credenciales (db/34-excepciones-credencial.sql).',
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

  /// Marca (o desmarca) "no pasó el filtro" sobre un QR, sin consumirlo.
  /// Devuelve `protegida` para las entradas de la casa, que no se filtran.
  Future<Map<String, dynamic>> marcarFiltroQr({
    required String eventoId,
    required QrLeido qr,
  }) async {
    final r = await _sb.rpc(
      qr.esLista ? 'marcar_filtro_lista' : 'marcar_filtro_entrada',
      params: {'p_evento': eventoId, 'p_code': qr.codigo},
    );
    return Map<String, dynamic>.from(r as Map? ?? const {});
  }

  /// Búsqueda por nombre para la lista en puerta.
  Future<List<PersonaPuerta>> buscar(String eventoId, String q) async {
    final r = await _sb.rpc('buscar_registros',
        params: {'p_evento': eventoId, 'p_q': q});
    return (r as List? ?? const [])
        .map((x) => PersonaPuerta.desde(Map<String, dynamic>.from(x as Map)))
        .toList();
  }

  /// Ingreso manual de un invitado de lista. Devuelve true si entró ahora,
  /// false si ya había ingresado.
  Future<bool> ingresoDeLista(String registroId) async {
    final r = Map<String, dynamic>.from(
        await _sb.rpc('checkin_registro', params: {'p_registro': registroId})
            as Map);
    return r['resultado'] == 'ok';
  }

  Future<void> desmarcarLista(String registroId) =>
      _sb.rpc('descheckin_registro', params: {'p_registro': registroId});

  Future<void> desmarcarEntrada(String eventoId, String codigo) => _sb.rpc(
      'descheckin_entrada',
      params: {'p_evento': eventoId, 'p_code': codigo});

  /// Alterna la marca de filtro de una persona de la lista en puerta.
  /// Devuelve el texto para avisar y si quedó marcada.
  Future<({bool marcado, String nombre, String rrpp})> alternarFiltro(
      String eventoId, PersonaPuerta p) async {
    final r = Map<String, dynamic>.from(await (p.esEntrada
        ? _sb.rpc('marcar_filtro_entrada',
            params: {'p_evento': eventoId, 'p_code': p.codigo})
        : _sb.rpc('marcar_filtro_registro',
            params: {'p_registro': p.id})) as Map);
    return (
      marcado: r['marcado'] == true,
      nombre: r['nombre'] as String? ?? p.nombre,
      rrpp: r['rrpp'] as String? ?? '',
    );
  }

  /// Relacionadores del boliche, para que el guardia consulte de qué team
  /// es quien llega. Es la misma lista que usa la caja; no trae plata.
  Future<List<Relacionador>> relacionadores(String clubId, String? eventoId) async {
    final r = await _sb.rpc('roster_caja',
        params: {'p_club': clubId, 'p_evento': eventoId});
    return (r as List? ?? const [])
        .map((x) => Relacionador.desde(Map<String, dynamic>.from(x as Map)))
        .toList();
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
