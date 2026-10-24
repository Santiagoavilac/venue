import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../../core/media/imagenes.dart';
import '../../../core/networking/supabase.dart';
import '../../../core/theme/venue_theme.dart';
import '../../../core/widgets/avisos.dart';
import '../../../core/widgets/foto_persona.dart';
import '../../../core/widgets/patron.dart' hide MarcaClub;
import '../../authentication/data/sesion.dart';
import '../../clubs/data/clubs.dart';
import '../data/perfil_cambios.dart';

/// Elige una foto nueva y la manda. La primera queda puesta al toque; las
/// siguientes las aprueba el admin del boliche.
Future<void> cambiarMiFoto(BuildContext context, WidgetRef ref, Perfil perfil) async {
  final origen = await showModalBottomSheet<String>(
    context: context,
    builder: (c) => SafeArea(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        const SizedBox(height: 8),
        const Text('Foto de perfil', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
        const SizedBox(height: 4),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Text(
            perfil.fotoUrl == null
                ? 'Que se te vea bien la cara: es la que ve seguridad al escanear tu credencial.'
                : 'El cambio lo aprueba el administrador antes de que se vea.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13, color: VenueColors.textoSuave),
          ),
        ),
        const SizedBox(height: 8),
        ListTile(
          leading: const Icon(Icons.photo_camera_outlined),
          title: const Text('Sacar foto'),
          onTap: () => Navigator.pop(c, 'camara'),
        ),
        ListTile(
          leading: const Icon(Icons.photo_library_outlined),
          title: const Text('Elegir de la galería'),
          onTap: () => Navigator.pop(c, 'galeria'),
        ),
        const SizedBox(height: 8),
      ]),
    ),
  );
  if (origen == null) return;
  final bytes = await elegirImagen(camara: origen == 'camara', lado: 720);
  if (bytes == null || !context.mounted) return;
  avisar(context, 'Subiendo foto…');
  try {
    final repo = ref.read(perfilCambiosProvider);
    final url = await repo.subirFoto(bytes);
    final aplicada = await repo.solicitar(fotoUrl: url);
    ref.invalidate(perfilProvider);
    ref.invalidate(miSolicitudProvider);
    if (context.mounted) {
      avisar(context, aplicada ? 'Foto lista' : 'Foto enviada. La ve el administrador y la aprueba');
    }
  } catch (e) {
    if (!context.mounted) return;
    final sinBase = '$e'.contains('Bucket not found') || faltaDb34(e);
    avisar(
      context,
      sinBase ? 'Falta preparar la base para las fotos (db/34-excepciones-credencial.sql)' : mensajeDeError(e),
      tipo: TipoAviso.aviso,
    );
  }
}

/// La credencial propia: foto, nombre y un QR que seguridad escanea con el
/// mismo escáner de entradas.
Future<void> verMiCredencial(BuildContext context) => Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const _CredencialScreen()),
    );

final _codigoCredencialProvider =
    FutureProvider.autoDispose<String>((ref) => ref.watch(perfilCambiosProvider).miCredencial());

class _CredencialScreen extends ConsumerWidget {
  const _CredencialScreen();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final perfil = ref.watch(perfilProvider).value;
    final club = ref.watch(clubActivoProvider);
    final rol = ref.watch(rolProvider).value;
    final codigo = ref.watch(_codigoCredencialProvider);

    return Scaffold(
      backgroundColor: VenueColors.fondo,
      appBar: AppBar(title: const Text('Mi credencial')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
        children: [
          Container(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 22),
            decoration: BoxDecoration(
              color: VenueColors.superficie,
              borderRadius: BorderRadius.circular(22),
              border: bordeTarjeta,
              boxShadow: sombraTarjeta,
            ),
            child: Column(children: [
              if (club != null)
                Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  LogoClub(inicial: club.inicial, color: club.primario, url: club.logoUrl, lado: 26),
                  const SizedBox(width: 8),
                  Text(club.nombre,
                      style: TextStyle(fontWeight: FontWeight.w600, color: VenueColors.textoSuave)),
                ]),
              const SizedBox(height: 16),
              FotoPersona(nombre: perfil?.nombre ?? '·', url: perfil?.fotoUrl, tam: 116),
              const SizedBox(height: 12),
              Text(perfil?.nombre ?? '',
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
              const SizedBox(height: 2),
              Text(
                [if (perfil != null) '@${perfil.usuario}', if (rol != null) rol.etiqueta].join(' · '),
                style: TextStyle(color: VenueColors.textoSuave),
              ),
              const SizedBox(height: 18),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)),
                child: switch (codigo) {
                  AsyncData(:final value) when club != null => QrImageView(
                      data: 'CRD|${club.id}|$value',
                      size: 220,
                      backgroundColor: Colors.white,
                      errorCorrectionLevel: QrErrorCorrectLevel.M,
                    ),
                  AsyncError(:final error) => SizedBox(
                      width: 220,
                      height: 220,
                      child: Center(
                        child: Text(
                          faltaDb34(error)
                              ? 'Falta preparar la base para las credenciales (db/34).'
                              : mensajeDeError(error),
                          textAlign: TextAlign.center,
                          style: const TextStyle(color: Colors.black54),
                        ),
                      ),
                    ),
                  _ => const SizedBox(
                      width: 220, height: 220, child: Center(child: CircularProgressIndicator())),
                },
              ),
              const SizedBox(height: 10),
              Text('Mostrá este QR en la puerta. Es personal: no lo compartas.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 13, color: VenueColors.textoSuave)),
            ]),
          ),
          if (perfil != null && perfil.fotoUrl == null) ...[
            const SizedBox(height: 14),
            FilledButton.icon(
              onPressed: () => cambiarMiFoto(context, ref, perfil),
              icon: const Icon(Icons.photo_camera_outlined),
              label: const Text('Subir mi foto'),
            ),
          ],
          const SizedBox(height: 14),
          OutlinedButton(
            onPressed: () async {
              try {
                await ref.read(perfilCambiosProvider).renovarCredencial();
                ref.invalidate(_codigoCredencialProvider);
                if (context.mounted) avisar(context, 'QR nuevo listo');
              } catch (e) {
                if (context.mounted) avisar(context, mensajeDeError(e), tipo: TipoAviso.aviso);
              }
            },
            child: const Text('Generar un QR nuevo'),
          ),
          const SizedBox(height: 6),
          Text('Si alguien sacó foto a tu QR, generá uno nuevo: el anterior deja de servir.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12.5, color: VenueColors.textoSuave)),
        ],
      ),
    );
  }
}

/// Admin: los cambios de foto y nombre que pidió su gente.
Future<void> verSolicitudesPerfil(BuildContext context, String club) => Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => _SolicitudesScreen(club: club)),
    );

class _SolicitudesScreen extends ConsumerWidget {
  const _SolicitudesScreen({required this.club});
  final String club;

  Future<void> _resolver(BuildContext context, WidgetRef ref, SolicitudPerfil s, bool si) async {
    try {
      await ref.read(perfilCambiosProvider).resolver(s.id, aprobar: si);
      ref.invalidate(solicitudesPerfilProvider(club));
      if (context.mounted) {
        avisar(context, si ? 'Cambio aprobado' : 'Cambio rechazado',
            tipo: si ? TipoAviso.ok : TipoAviso.aviso);
      }
    } catch (e) {
      if (context.mounted) avisar(context, mensajeDeError(e), tipo: TipoAviso.aviso);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final lista = ref.watch(solicitudesPerfilProvider(club));
    return Scaffold(
      backgroundColor: VenueColors.fondo,
      appBar: AppBar(title: const Text('Cambios de perfil')),
      body: switch (lista) {
        AsyncData(:final value) when value.isEmpty => Center(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Text(
                'Cuando alguien de tu equipo cambie su foto o su nombre, aparece acá para que lo apruebes.',
                textAlign: TextAlign.center,
                style: TextStyle(color: VenueColors.textoSuave),
              ),
            ),
          ),
        AsyncData(:final value) => RefreshIndicator(
            onRefresh: () => ref.refresh(solicitudesPerfilProvider(club).future),
            child: ListView.separated(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
              itemCount: value.length,
              separatorBuilder: (_, _) => const SizedBox(height: 10),
              itemBuilder: (_, i) => _TarjetaSolicitud(
                s: value[i],
                alResolver: (si) => _resolver(context, ref, value[i], si),
              ),
            ),
          ),
        AsyncError(:final error) => Center(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Text(
                faltaDb34(error)
                    ? 'Falta preparar la base para esto (db/34-excepciones-credencial.sql).'
                    : mensajeDeError(error),
                textAlign: TextAlign.center,
              ),
            ),
          ),
        _ => const Center(child: CircularProgressIndicator()),
      },
    );
  }
}

class _TarjetaSolicitud extends StatelessWidget {
  const _TarjetaSolicitud({required this.s, required this.alResolver});
  final SolicitudPerfil s;
  final void Function(bool aprobar) alResolver;

  @override
  Widget build(BuildContext context) {
    final nombre = s.nombre ?? '';
    Widget foto(String? url, String rotulo) => Column(children: [
          url == null
              ? Container(
                  width: 96,
                  height: 96,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(color: VenueColors.superficie2, shape: BoxShape.circle),
                  child: Text('Sin foto', style: TextStyle(fontSize: 12, color: VenueColors.textoSuave)),
                )
              : FotoPersona(nombre: nombre, url: url, tam: 96),
          const SizedBox(height: 4),
          Text(rotulo, style: TextStyle(fontSize: 12, color: VenueColors.textoSuave)),
        ]);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: VenueColors.superficie,
        borderRadius: BorderRadius.circular(18),
        border: bordeTarjeta,
        boxShadow: sombraTarjeta,
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          FotoPersona(nombre: nombre, url: s.fotoActual, tam: 40),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(nombre, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15.5)),
              Text(
                [if (s.usuario != null) '@${s.usuario}', if (s.team != null) s.team!].join(' · '),
                style: TextStyle(fontSize: 12.5, color: VenueColors.textoSuave),
              ),
            ]),
          ),
        ]),
        if (s.fotoNueva != null) ...[
          const SizedBox(height: 12),
          Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            foto(s.fotoActual, 'Ahora'),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              child: Icon(Icons.arrow_forward_rounded, color: VenueColors.textoSuave),
            ),
            foto(s.fotoNueva, 'Nueva'),
          ]),
        ],
        if (s.nombreNuevo != null) ...[
          const SizedBox(height: 10),
          Text.rich(TextSpan(children: [
            const TextSpan(text: 'Nombre: '),
            TextSpan(text: nombre, style: const TextStyle(decoration: TextDecoration.lineThrough)),
            const TextSpan(text: '  a  '),
            TextSpan(text: s.nombreNuevo, style: const TextStyle(fontWeight: FontWeight.w700)),
          ])),
        ],
        const SizedBox(height: 12),
        Row(children: [
          Expanded(child: OutlinedButton(onPressed: () => alResolver(false), child: const Text('Rechazar'))),
          const SizedBox(width: 10),
          Expanded(child: FilledButton(onPressed: () => alResolver(true), child: const Text('Aprobar'))),
        ]),
      ]),
    );
  }
}
