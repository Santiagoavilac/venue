import 'dart:math';
import 'dart:typed_data';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../core/networking/supabase.dart';

const bucketPerfil = 'aftr-perfiles';

String extensionFoto(Uint8List bytes) {
  if (bytes.length >= 3 &&
      bytes[0] == 0xff &&
      bytes[1] == 0xd8 &&
      bytes[2] == 0xff) {
    return 'jpg';
  }
  if (bytes.length >= 8 &&
      bytes.take(8).join(',') == '137,80,78,71,13,10,26,10') {
    return 'png';
  }
  if (bytes.length >= 12 &&
      String.fromCharCodes(bytes.take(4)) == 'RIFF' &&
      String.fromCharCodes(bytes.skip(8).take(4)) == 'WEBP') {
    return 'webp';
  }
  throw const FormatException('Elegí una foto JPG, PNG o WebP.');
}

/// Firma la foto de perfil de cualquiera para poder mostrarla (el bucket es
/// privado: la URL dura una hora). Queda en caché por ruta, así el feed de
/// historias no vuelve a pedirla al desplazarse.
final fotoFirmadaProvider = FutureProvider.family<String?, String>((
  ref,
  ruta,
) async {
  try {
    return await ref
        .watch(supabaseProvider)
        .storage
        .from(bucketPerfil)
        .createSignedUrl(ruta, 3600);
  } catch (_) {
    return null;
  }
});

class FotoPerfilRepo {
  FotoPerfilRepo(this.sb);
  final SupabaseClient sb;

  Future<void> guardar(Uint8List bytes, String? anterior) async {
    if (bytes.length > 2 * 1024 * 1024) {
      throw const FormatException(
        'La foto debe pesar menos de 2 MB. Elegí otra imagen.',
      );
    }
    final uid = sb.auth.currentUser?.id;
    if (uid == null) {
      throw const AuthException('Iniciá sesión para cambiar tu foto.');
    }
    final ext = extensionFoto(bytes);
    final nombre =
        '${DateTime.now().microsecondsSinceEpoch.toRadixString(16)}-${List.generate(8, (_) => Random.secure().nextInt(256).toRadixString(16).padLeft(2, '0')).join()}';
    final ruta = '$uid/$nombre.$ext';
    await sb.storage
        .from(bucketPerfil)
        .uploadBinary(
          ruta,
          bytes,
          fileOptions: FileOptions(
            contentType: 'image/${ext == 'jpg' ? 'jpeg' : ext}',
            cacheControl: '3600',
          ),
        );
    try {
      // Antes de dejarla en el perfil, el servidor mira los bytes: la foto se
      // le muestra ahora a cualquier visitante sin cuenta, y storage acepta
      // cualquier contenido con que el cliente declare image/jpeg.
      final r = await sb.functions.invoke('historias-media',
          body: {'accion': 'revisar', 'bucket': bucketPerfil, 'path': ruta});
      if (r.status < 200 || r.status >= 300) {
        throw const FormatException('Elegí una foto JPG, PNG o WebP.');
      }
      await sb.rpc('aftr_cambiar_foto', params: {'p_archivo': ruta});
    } catch (_) {
      try {
        await sb.storage.from(bucketPerfil).remove([ruta]);
      } catch (_) {}
      rethrow;
    }
    // La foto previa se borra después de confirmar el cambio de perfil.
    if (anterior?.startsWith('$uid/') == true) {
      try {
        await sb.storage.from(bucketPerfil).remove([anterior!]);
      } catch (_) {}
    }
  }

  Future<void> quitar(String? anterior) async {
    await sb.rpc('aftr_cambiar_foto', params: {'p_archivo': null});
    final uid = sb.auth.currentUser?.id;
    if (uid != null && anterior?.startsWith('$uid/') == true) {
      try {
        await sb.storage.from(bucketPerfil).remove([anterior!]);
      } catch (_) {}
    }
  }
}

final fotoPerfilRepoProvider = Provider(
  (ref) => FotoPerfilRepo(ref.watch(supabaseProvider)),
);
