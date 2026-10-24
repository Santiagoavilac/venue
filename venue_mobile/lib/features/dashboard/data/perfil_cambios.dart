import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/config/env.dart';
import '../../../core/networking/supabase.dart';

/// Foto, credencial y cambios de perfil (db/34-excepciones-credencial.sql).
///
/// La primera foto entra directo. Después, cambiar foto o nombre es una
/// solicitud que el admin del boliche acepta o rechaza; los admins cambian
/// lo suyo sin pedir permiso. El servidor decide cuál de los dos casos es.
final perfilCambiosProvider =
    Provider<PerfilCambios>((ref) => PerfilCambios(ref.watch(supabaseProvider)));

/// La solicitud pendiente propia, si hay.
final miSolicitudProvider = FutureProvider.autoDispose<SolicitudPerfil?>(
    (ref) => ref.watch(perfilCambiosProvider).miSolicitud());

/// Las pendientes del boliche (solo admin).
final solicitudesPerfilProvider = FutureProvider.autoDispose.family<List<SolicitudPerfil>, String>(
    (ref, club) => ref.watch(perfilCambiosProvider).solicitudes(club));

/// La base todavía no tiene db/34.
bool faltaDb34(Object e) =>
    e is PostgrestException && const {'PGRST202', '42703', 'PGRST204', '42883'}.contains(e.code);

class SolicitudPerfil {
  const SolicitudPerfil({
    required this.id,
    required this.creada,
    this.nombreNuevo,
    this.fotoNueva,
    this.userId,
    this.nombre,
    this.usuario,
    this.fotoActual,
    this.team,
  });

  final String id;
  final DateTime creada;
  final String? nombreNuevo;
  final String? fotoNueva;

  // quién la pidió (en la lista del admin)
  final String? userId;
  final String? nombre;
  final String? usuario;
  final String? fotoActual;
  final String? team;

  factory SolicitudPerfil.desde(Map<String, dynamic> j) {
    final c = Map<String, dynamic>.from(j['cambios'] as Map? ?? const {});
    return SolicitudPerfil(
      id: j['id'] as String,
      creada: DateTime.tryParse(j['created_at'] as String? ?? '')?.toLocal() ?? DateTime.now(),
      nombreNuevo: c['nombre'] as String?,
      fotoNueva: c['foto_url'] as String?,
      userId: j['user_id'] as String?,
      nombre: j['nombre'] as String?,
      usuario: j['usuario'] as String?,
      fotoActual: j['foto_url'] as String?,
      team: j['team'] as String?,
    );
  }
}

class PerfilCambios {
  PerfilCambios(this._sb);
  final SupabaseClient _sb;

  /// Sube la foto a la carpeta propia del bucket `perfiles` y devuelve su URL.
  Future<String> subirFoto(Uint8List bytes) async {
    final uid = _sb.auth.currentUser!.id;
    final ruta = '$uid/${DateTime.now().millisecondsSinceEpoch}.jpg';
    await _sb.storage.from('perfiles').uploadBinary(ruta, bytes,
        fileOptions: const FileOptions(contentType: 'image/jpeg'));
    return '${Env.supabaseUrl}/storage/v1/object/public/perfiles/$ruta';
  }

  /// Pide el cambio. Devuelve true si quedó aplicado, false si espera al admin.
  Future<bool> solicitar({String? nombre, String? fotoUrl}) async {
    final cambios = <String, String>{
      'nombre': ?nombre,
      'foto_url': ?fotoUrl,
    };
    try {
      final r = await _sb.rpc('solicitar_cambio_perfil', params: {'p_cambios': cambios});
      return (r as Map?)?['estado'] != 'pendiente';
    } catch (e) {
      // base sin preparar: se guarda como antes, directo
      if (!faltaDb34(e)) rethrow;
      await _sb.from('profiles').update(cambios).eq('id', _sb.auth.currentUser!.id);
      return true;
    }
  }

  Future<SolicitudPerfil?> miSolicitud() async {
    try {
      final r = await _sb.rpc('mi_solicitud_perfil');
      return r == null ? null : SolicitudPerfil.desde(Map<String, dynamic>.from(r as Map));
    } catch (e) {
      if (faltaDb34(e)) return null;
      rethrow;
    }
  }

  Future<List<SolicitudPerfil>> solicitudes(String club) async {
    final r = await _sb.rpc('solicitudes_perfil', params: {'p_club': club});
    return (r as List? ?? const [])
        .map((x) => SolicitudPerfil.desde(Map<String, dynamic>.from(x as Map)))
        .toList();
  }

  Future<void> resolver(String id, {required bool aprobar}) =>
      _sb.rpc('resolver_solicitud_perfil', params: {'p_id': id, 'p_aprobar': aprobar});

  /// El código del QR de credencial propio (se crea la primera vez).
  Future<String> miCredencial() async => (await _sb.rpc('mi_credencial')) as String;

  /// Invalida el QR propio: el próximo [miCredencial] trae uno nuevo.
  Future<void> renovarCredencial() =>
      _sb.rpc('renovar_credencial', params: {'p_user': _sb.auth.currentUser!.id});
}
