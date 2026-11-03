import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/networking/supabase.dart';
import '../../../core/sync/cola_offline.dart';
import '../../authentication/data/sesion.dart';
import '../../clubs/data/clubs.dart';

typedef DatosSocial = Map<String, dynamic>;

DatosSocial mapaSocial(dynamic dato) =>
    dato is Map ? Map<String, dynamic>.from(dato) : <String, dynamic>{};
List<DatosSocial> filasSocial(dynamic dato) => dato is List
    ? dato.whereType<Map>().map((x) => Map<String, dynamic>.from(x)).toList()
    : <DatosSocial>[];
String textoSocial(dynamic dato) {
  if (dato is Map) return '${dato['nombre'] ?? dato['usuario'] ?? ''}';
  return dato?.toString() ?? '';
}

String dineroSocial(dynamic centavos) =>
    'Bs ${((centavos is num ? centavos : 0) / 100).toStringAsFixed(2)}';

class SocialAftr {
  SocialAftr(this.sb);
  final SupabaseClient sb;
  final Map<String, String> _artes = {};

  Future<DatosSocial> historias(
    String accion, [
    DatosSocial datos = const {},
  ]) => _rpc('aftr_historias', accion, datos);
  Future<DatosSocial> reventa(String accion, [DatosSocial datos = const {}]) =>
      _rpc('aftr_reventa', accion, datos);

  Future<DatosSocial> _rpc(
    String nombre,
    String accion,
    DatosSocial datos,
  ) async {
    final valor = await sb
        .rpc(nombre, params: {'p_accion': accion, 'p_datos': datos})
        .timeout(const Duration(seconds: 20));
    return mapaSocial(valor);
  }

  Future<String> medio(String bucket, String path) =>
      sb.storage.from(bucket).createSignedUrl(path, 300);

  Future<String> subir(Uint8List bytes, String tipo) async {
    if (bytes.isEmpty || bytes.length > 30 * 1024 * 1024) {
      throw Exception('El archivo debe pesar como máximo 30 MB.');
    }
    final uid = sb.auth.currentUser?.id;
    if (uid == null) throw Exception('Iniciá sesión para publicar.');
    final extension = switch (tipo) {
      'video/mp4' => 'mp4',
      'video/quicktime' => 'mov',
      'image/png' => 'png',
      'image/webp' => 'webp',
      _ => 'jpg',
    };
    final path = '$uid/${nuevoId()}.$extension';
    await sb.storage
        .from('aftr-historias')
        .uploadBinary(
          path,
          bytes,
          fileOptions: FileOptions(contentType: tipo, upsert: false),
        );
    try {
      final r = await sb.functions.invoke(
        'historias-media',
        body: {'path': path},
      );
      final datos = mapaSocial(r.data);
      if (datos['error'] != null) throw Exception(datos['error']);
      if (datos['valido'] == false)
        throw Exception('No se pudo validar el archivo.');
      return path;
    } catch (_) {
      // Sólo se borra el archivo recién subido, todavía sin historia.
      try {
        await sb.storage.from('aftr-historias').remove([path]);
      } catch (_) {}
      rethrow;
    }
  }

  Future<String> subirArte(String url) async {
    final clave = '${sb.auth.currentUser?.id}:$url';
    if (_artes[clave] case final String path) return path;
    final uri = Uri.tryParse(url);
    if (uri == null || uri.scheme != 'https') {
      throw Exception('El arte del evento no tiene una dirección válida.');
    }
    final data = await NetworkAssetBundle(uri).load(url);
    final bytes = data.buffer.asUint8List(
      data.offsetInBytes,
      data.lengthInBytes,
    );
    final tipo = bytes.length > 3 && bytes[0] == 137 && bytes[1] == 80
        ? 'image/png'
        : 'image/jpeg';
    final path = await subir(bytes, tipo);
    _artes[clave] = path;
    return path;
  }
}

final socialAftrProvider = Provider<SocialAftr>(
  (ref) => SocialAftr(ref.watch(supabaseProvider)),
);

final historiasGestionProvider = FutureProvider.autoDispose<DatosSocial>((ref) {
  ref.watch(usuarioIdProvider);
  final club = ref.watch(clubActivoIdProvider);
  _escuchar(ref, ['aftr_historias'], club);
  return ref.watch(socialAftrProvider).historias('gestion', {'club_id': ?club});
});

final reventaGestionProvider = FutureProvider.autoDispose
    .family<DatosSocial, bool>((ref, global) {
      ref.watch(usuarioIdProvider);
      final club = ref.watch(clubActivoIdProvider);
      _escuchar(ref, [
        'aftr_reventa_ofertas',
        'aftr_reventa_ordenes',
      ], global ? null : club);
      return ref.watch(socialAftrProvider).reventa('gestion', {
        if (!global && club != null) 'club_id': club,
      });
    });

void _escuchar(Ref ref, List<String> tablas, String? club) {
  final sb = ref.watch(supabaseProvider);
  Timer? debounce;
  final canal = sb.channel('venue-social-${tablas.first}-${club ?? 'global'}');
  for (final tabla in tablas) {
    canal.onPostgresChanges(
      event: PostgresChangeEvent.all,
      schema: 'public',
      table: tabla,
      callback: (_) {
        debounce?.cancel();
        debounce = Timer(const Duration(milliseconds: 250), ref.invalidateSelf);
      },
    );
  }
  canal.subscribe();
  // También reconcilia vencimientos y reconexiones sin depender de un mensaje RT.
  final reloj = Timer.periodic(
    const Duration(seconds: 20),
    (_) => ref.invalidateSelf(),
  );
  ref.onDispose(() {
    debounce?.cancel();
    reloj.cancel();
    sb.removeChannel(canal);
  });
}
