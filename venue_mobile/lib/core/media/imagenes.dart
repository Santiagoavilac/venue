import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config/env.dart';
import '../networking/supabase.dart';

/// Elige una foto (cámara o galería) ya achicada: un comprobante legible no
/// necesita más de ~1100 px y en la red del boliche cada MB cuenta.
Future<Uint8List?> elegirImagen({bool camara = false, double lado = 1100}) async {
  final f = await ImagePicker().pickImage(
    source: camara ? ImageSource.camera : ImageSource.gallery,
    maxWidth: lado,
    maxHeight: lado,
    imageQuality: 82,
  );
  return f?.readAsBytes();
}

final archivosProvider =
    Provider<Archivos>((ref) => Archivos(ref.watch(supabaseProvider)));

/// Subida y lectura de imágenes en los dos buckets de Venue.
class Archivos {
  Archivos(this._sb);
  final SupabaseClient _sb;

  static final _rutaComprobante =
      RegExp(r'/storage/v1/object/(?:public|sign)/comprobantes/([^?]+)');

  /// Sube un comprobante a la carpeta del propio usuario (lo exige la
  /// política del bucket) y devuelve la referencia que se guarda en la base.
  ///
  /// Se guarda con la MISMA forma que usa la web (la URL "pública" del
  /// objeto) para que las dos lean lo mismo; el bucket es privado y esa URL
  /// no abre: para mostrarla hay que pedir [urlComprobante].
  Future<String> subirComprobante(Uint8List bytes, String nombre) async {
    final uid = _sb.auth.currentUser!.id;
    final ruta = '$uid/$nombre-${DateTime.now().millisecondsSinceEpoch}.jpg';
    await _sb.storage.from('comprobantes').uploadBinary(ruta, bytes,
        fileOptions: const FileOptions(upsert: true, contentType: 'image/jpeg'));
    return '${Env.supabaseUrl}/storage/v1/object/public/comprobantes/$ruta';
  }

  /// URL firmada (5 min) de un comprobante. null si la persona no tiene
  /// permiso de verlo o la referencia no es de un comprobante.
  Future<String?> urlComprobante(String? referencia) async {
    final m = _rutaComprobante.firstMatch(referencia ?? '');
    if (m == null) return null;
    try {
      return await _sb.storage
          .from('comprobantes')
          .createSignedUrl(Uri.decodeComponent(m.group(1)!), 300);
    } catch (_) {
      return null;
    }
  }

  /// Sube una imagen pública de diseño (arte, fondo de plano, QR de cobro).
  /// Solo el admin tiene permiso de escritura en ese bucket.
  Future<String> subirDiseno(Uint8List bytes, String ruta) async {
    await _sb.storage.from('disenos').uploadBinary(ruta, bytes,
        fileOptions: const FileOptions(upsert: true, contentType: 'image/jpeg'));
    final url = _sb.storage.from('disenos').getPublicUrl(ruta);
    return '$url?v=${DateTime.now().millisecondsSinceEpoch}';
  }
}
