import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/networking/supabase.dart';
import 'pulse_repo.dart';

typedef DatosSocial = Map<String, dynamic>;

DatosSocial mapaSocial(Object? v) =>
    v is Map ? Map<String, dynamic>.from(v) : <String, dynamic>{};
List<DatosSocial> listaSocial(Object? v) => v is List
    ? v.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList()
    : <DatosSocial>[];

/// Clock offsets are derived from each server response, never from a timer
/// created when a screen opens. Reopening an order cannot restart its deadline.
Duration desfaseSocial(DatosSocial datos, [DateTime? local]) =>
    (DateTime.tryParse('${datos['ahora']}') ?? local ?? DateTime.now())
        .difference(local ?? DateTime.tryParse('${datos['_recibido_at']}') ?? DateTime.now());
Duration tiempoRestante(Object? fecha, DateTime ahora) {
  final fin = DateTime.tryParse('$fecha');
  if (fin == null || !fin.isAfter(ahora)) return Duration.zero;
  return fin.difference(ahora);
}

String etiquetaReventa(Object? estado) => switch (estado) {
  'esperando_vendedor' => 'Esperando al vendedor',
  'pendiente_pago' || 'esperando_pago' || 'pendiente' => 'Esperando pago',
  'pago_informado' || 'pagada' || 'pagado' => 'Pago informado',
  'completada' || 'confirmada' => 'Completada',
  'cancelada' => 'Cancelada',
  'vencida' => 'Vencida',
  'en_disputa' || 'disputada' || 'disputa' => 'En disputa',
  'publicada' || 'activa' => 'Publicada',
  'reservada' => 'En operación',
  _ => '$estado'.replaceAll('_', ' '),
};

bool ordenTerminada(Object? estado) => const {
  'completada', 'confirmada', 'cancelada', 'vencida', 'resuelta',
}.contains(estado);
bool pagoInformado(Object? estado) => const {
  'pago_informado', 'pagada', 'pagado', 'confirmando',
}.contains(estado);

/// "En pago · vuelve en 7 min". La oferta reservada sigue a la vista porque
/// vuelve sola en minutos: lo que no se puede es soltarla mientras se paga,
/// porque invitaría a dos pagos reales por la misma entrada.
String enPagoVuelve(Object? vuelveAt, DateTime ahora) {
  final falta = tiempoRestante(vuelveAt, ahora);
  if (falta == Duration.zero) return 'En pago';
  final min = (falta.inSeconds / 60).ceil();
  return 'En pago\nvuelve en $min min';
}

/// El vendedor todavía no aceptó. Hasta que lo haga no se muestra ningún dato
/// de cobro: iniciar una orden no puede ser la forma de conseguirlos.
bool esperaAlVendedor(Object? estado) => estado == 'esperando_vendedor';

/// Validates bytes before upload. The media Edge Function performs independent
/// authoritative checks before the server allows a story to be published.
({String ext, String mime, bool video}) tipoMedio(Uint8List b) {
  if (b.length >= 3 && b[0] == 255 && b[1] == 216 && b[2] == 255) {
    return (ext: 'jpg', mime: 'image/jpeg', video: false);
  }
  if (b.length >= 8 && b.take(8).join(',') == '137,80,78,71,13,10,26,10') {
    return (ext: 'png', mime: 'image/png', video: false);
  }
  if (b.length >= 12 && String.fromCharCodes(b.take(4)) == 'RIFF' &&
      String.fromCharCodes(b.skip(8).take(4)) == 'WEBP') {
    return (ext: 'webp', mime: 'image/webp', video: false);
  }
  if (b.length >= 12 && String.fromCharCodes(b.skip(4).take(4)) == 'ftyp') {
    final marca = String.fromCharCodes(b.skip(8).take(4));
    if (const {'heic', 'heix', 'hevc', 'hevx', 'mif1', 'avif'}.contains(marca)) {
      throw const FormatException('Elegí una foto JPG, PNG o WebP.');
    }
    return (ext: 'mp4', mime: 'video/mp4', video: true);
  }
  throw const FormatException('Elegí JPG, PNG, WebP o video MP4.');
}

class SocialRepo {
  SocialRepo(this.sb);
  final SupabaseClient sb;

  Future<DatosSocial> historias(String accion, [DatosSocial datos = const {}]) async {
    final resultado = mapaSocial(await sb.rpc('aftr_historias', params: {
        'p_accion': accion, 'p_datos': datos,
      }));
    resultado['_recibido_at'] = DateTime.now().toUtc().toIso8601String();
    return resultado;
  }
  Future<DatosSocial> reventa(String accion, [DatosSocial datos = const {}]) async {
    final resultado = mapaSocial(await sb.rpc('aftr_reventa', params: {
        'p_accion': accion, 'p_datos': datos,
      }));
    resultado['_recibido_at'] = DateTime.now().toUtc().toIso8601String();
    return resultado;
  }

  Future<String> firmar(String bucket, String path) =>
      sb.storage.from(bucket).createSignedUrl(path, 60);

  Future<String> subir(Uint8List bytes, {required bool historia}) async {
    if (bytes.length > (historia ? 30 : 8) * 1024 * 1024) {
      throw FormatException('El archivo supera ${historia ? 30 : 8} MB.');
    }
    final tipo = tipoMedio(bytes);
    if (!historia && tipo.video) {
      throw const FormatException('El comprobante debe ser una imagen.');
    }
    final uid = sb.auth.currentUser?.id;
    if (uid == null) throw const AuthException('Iniciá sesión para continuar.');
    final bucket = historia ? 'aftr-historias' : 'aftr-p2p';
    final path = '$uid/${nuevaOperacion()}.${tipo.ext}';
    await sb.storage.from(bucket).uploadBinary(path, bytes,
        fileOptions: FileOptions(contentType: tipo.mime, cacheControl: '0'));
    if (historia) {
      try {
        final r = await sb.functions.invoke('historias-media', body: {'path': path});
        if (r.status < 200 || r.status >= 300) {
          throw const FormatException('No se pudo verificar el archivo.');
        }
      } catch (_) {
        await borrar(bucket, path);
        rethrow;
      }
    }
    return path;
  }

  Future<void> borrar(String bucket, String path) async {
    try { await sb.storage.from(bucket).remove([path]); } catch (_) {}
  }
}

final socialRepoProvider = Provider((ref) => SocialRepo(ref.watch(supabaseProvider)));

void escucharSocial(Ref ref, List<String> tablas, String nombre,
    {Duration cada = const Duration(seconds: 30)}) {
  final sb = ref.watch(supabaseProvider);
  ref.watch(usuarioIdProvider);
  Timer? rafaga;
  final canal = sb.channel('social-$nombre-${nuevaOperacion()}');
  for (final tabla in tablas) {
    canal.onPostgresChanges(event: PostgresChangeEvent.all, schema: 'public',
      table: tabla, callback: (_) {
        rafaga?.cancel();
        rafaga = Timer(const Duration(milliseconds: 180), ref.invalidateSelf);
      });
  }
  canal.subscribe();
  final reloj = Timer.periodic(cada, (_) => ref.invalidateSelf());
  ref.onDispose(() {
    rafaga?.cancel(); reloj.cancel(); sb.removeChannel(canal);
  });
}

final historiasProvider = FutureProvider.autoDispose<DatosSocial>((ref) {
  escucharSocial(ref, ['aftr_historias'], 'historias', cada: const Duration(seconds: 60));
  return ref.watch(socialRepoProvider).historias('feed');
});
final mercadoProvider = FutureProvider.autoDispose<DatosSocial>((ref) {
  escucharSocial(ref, ['aftr_reventa_ofertas'], 'mercado');
  return ref.watch(socialRepoProvider).reventa('mercado');
});
final misReventasProvider = FutureProvider.autoDispose<DatosSocial>((ref) {
  escucharSocial(ref, ['aftr_reventa_ofertas', 'aftr_reventa_ordenes', 'entradas'], 'mias');
  return ref.watch(socialRepoProvider).reventa('mias');
});
final ordenReventaProvider = FutureProvider.autoDispose.family<DatosSocial, String>((ref, id) {
  escucharSocial(ref, ['aftr_reventa_ordenes', 'aftr_reventa_historial'], 'orden-$id',
      cada: const Duration(seconds: 15));
  return ref.watch(socialRepoProvider).reventa('orden', {'id': id});
});
