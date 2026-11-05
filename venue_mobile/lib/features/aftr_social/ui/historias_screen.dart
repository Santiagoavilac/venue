import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:video_player/video_player.dart';

import '../../../core/networking/supabase.dart';
import '../../../core/theme/venue_theme.dart';
import '../../../core/widgets/avisos.dart';
import '../../clubs/data/clubs.dart';
import '../../events/data/eventos.dart';
import '../data/social_aftr.dart';
import '../../../core/widgets/esqueleto.dart';

class HistoriasScreen extends ConsumerStatefulWidget {
  const HistoriasScreen({super.key});
  @override
  ConsumerState<HistoriasScreen> createState() => _HistoriasState();
}

class _HistoriasState extends ConsumerState<HistoriasScreen>
    with WidgetsBindingObserver {
  bool _ocupado = false;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed)
      ref.invalidate(historiasGestionProvider);
  }

  Future<void> _retirar(DatosSocial h) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Retirar historia'),
        content: const Text(
          'Dejará de estar disponible en AFTR inmediatamente.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('Volver'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(c, true),
            child: const Text('Retirar'),
          ),
        ],
      ),
    );
    if (ok != true || _ocupado) return;
    setState(() => _ocupado = true);
    try {
      await ref.read(socialAftrProvider).historias('retirar', {'id': h['id']});
      ref.invalidate(historiasGestionProvider);
      if (mounted) avisar(context, 'Historia retirada');
    } catch (e) {
      if (mounted) avisar(context, mensajeDeError(e), tipo: TipoAviso.aviso);
    } finally {
      if (mounted) setState(() => _ocupado = false);
    }
  }

  Future<void> _crear() async {
    final publicada = await Navigator.of(
      context,
    ).push<bool>(MaterialPageRoute(builder: (_) => const _EditorHistoria()));
    if (publicada == true) {
      ref.invalidate(historiasGestionProvider);
      if (mounted) avisar(context, 'Tu historia ya está en AFTR');
    }
  }

  @override
  Widget build(BuildContext context) {
    final datos = ref.watch(historiasGestionProvider);
    final rol = ref.watch(rolProvider).value;
    final puedePublicar = [Rol.admin, Rol.rrpp, Rol.jefe].contains(rol);
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  '24 horas para conectar con tu público',
                  style: TextStyle(color: VenueColors.textoSuave),
                ),
              ),
              IconButton(
                tooltip: 'Actualizar historias',
                onPressed: () => ref.invalidate(historiasGestionProvider),
                icon: const Icon(Icons.refresh),
              ),
            ],
          ),
        ),
        if (puedePublicar)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _ocupado ? null : _crear,
                icon: const Icon(Icons.add_circle_outline),
                label: const Text('Nueva historia'),
              ),
            ),
          ),
        if (_ocupado) const LinearProgressIndicator(),
        Expanded(
          child: datos.when(
            loading: () => const EsqueletoLista(),
            error: (e, _) => Center(
              child: TextButton(
                onPressed: () => ref.invalidate(historiasGestionProvider),
                child: Text(
                  '${mensajeDeError(e)}\nReintentar',
                  textAlign: TextAlign.center,
                ),
              ),
            ),
            data: (j) {
              final historias = filasSocial(j['historias']);
              final reportes = filasSocial(j['reportes']);
              return RefreshIndicator(
                onRefresh: () async {
                  ref.invalidate(historiasGestionProvider);
                  await ref.read(historiasGestionProvider.future);
                },
                child: ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    if (historias.isEmpty)
                      const SocialVacio(
                        icono: Icons.auto_awesome_outlined,
                        titulo: 'La próxima noche empieza acá',
                        detalle:
                            'Publicá una foto, un video o el arte del evento. Tus historias duran 24 horas.',
                      ),
                    for (final h in historias)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: _HistoriaGestion(
                          historia: h,
                          abrir: () => Navigator.of(context).push(
                            MaterialPageRoute<void>(
                              builder: (_) => _VistaHistoria(historia: h),
                            ),
                          ),
                          retirar: h['can_retirar'] == true && !_ocupado
                              ? () => _retirar(h)
                              : null,
                        ),
                      ),
                    if (reportes.isNotEmpty) ...[
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 14),
                        child: Text(
                          'Reportes de la comunidad',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      for (final r in reportes)
                        Card(
                          child: ListTile(
                            leading: Icon(
                              Icons.flag_outlined,
                              color: VenueColors.aviso,
                            ),
                            title: Text(textoSocial(r['motivo'])),
                            subtitle: Text(
                              '${textoSocial(r['autor'])} · ${fechaSocial(r['created_at'])}',
                            ),
                            trailing: const Icon(Icons.chevron_right),
                            onTap: () {
                              final h = historias
                                  .where((h) => h['id'] == r['historia_id'])
                                  .firstOrNull;
                              if (h != null) {
                                Navigator.of(context).push(
                                  MaterialPageRoute<void>(
                                    builder: (_) => _VistaHistoria(historia: h),
                                  ),
                                );
                              } else {
                                avisar(
                                  context,
                                  'Esta historia ya no está disponible',
                                  tipo: TipoAviso.aviso,
                                );
                              }
                            },
                          ),
                        ),
                    ],
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _HistoriaGestion extends ConsumerWidget {
  const _HistoriaGestion({
    required this.historia,
    required this.abrir,
    this.retirar,
  });
  final DatosSocial historia;
  final VoidCallback abrir;
  final VoidCallback? retirar;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final h = historia;
    final vence = DateTime.tryParse('${h['vence_at']}');
    final activa =
        h['retirada_at'] == null && (vence?.isAfter(DateTime.now()) ?? false);
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          ListTile(
            onTap: abrir,
            leading: Container(
              width: 48,
              height: 64,
              decoration: BoxDecoration(
                color: VenueColors.superficieAlta,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: activa ? VenueColors.ok : VenueColors.neutro,
                  width: 2,
                ),
              ),
              child: Icon(
                h['tipo'] == 'video'
                    ? Icons.play_arrow_rounded
                    : Icons.photo_outlined,
              ),
            ),
            title: Text(
              textoSocial(h['nombre']).isNotEmpty
                  ? textoSocial(h['nombre'])
                  : textoSocial(h['autor']),
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            subtitle: Text(
              '${textoSocial(h['evento'])}\n${activa ? 'Disponible hasta ${fechaSocial(h['vence_at'])}' : 'Finalizada o retirada'}',
            ),
            isThreeLine: true,
            trailing: const Icon(Icons.chevron_right),
          ),
          if (retirar != null && activa)
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: retirar,
                icon: const Icon(Icons.visibility_off_outlined, size: 18),
                label: const Text('Retirar'),
              ),
            ),
        ],
      ),
    );
  }
}

class _EditorHistoria extends ConsumerStatefulWidget {
  const _EditorHistoria();
  @override
  ConsumerState<_EditorHistoria> createState() => _EditorState();
}

class _EditorState extends ConsumerState<_EditorHistoria> {
  String? _evento, _arte, _path;
  String _cta = 'ninguna';
  String? _identidad;
  Uint8List? _foto;
  VideoPlayerController? _video;
  bool _ocupado = false, _publicada = false;
  String? _error;
  String _mime = 'image/jpeg';

  @override
  void dispose() {
    _video?.dispose();
    super.dispose();
  }

  Future<void> _elegir(bool video) async {
    if (_ocupado) return;
    setState(() {
      _ocupado = true;
      _error = null;
    });
    VideoPlayerController? controlador;
    var asignado = false;
    try {
      final picker = ImagePicker();
      final f = video
          ? await picker.pickVideo(
              source: ImageSource.gallery,
              maxDuration: const Duration(seconds: 30),
            )
          : await picker.pickImage(
              source: ImageSource.gallery,
              imageQuality: 90,
              maxWidth: 1800,
              maxHeight: 2400,
            );
      if (f == null) return;
      if (await f.length() > 30 * 1024 * 1024)
        throw Exception('El archivo supera 30 MB.');
      final bytes = await f.readAsBytes();
      final extension = f.name.toLowerCase();
      final mime = video
          ? (extension.endsWith('.mov') ? 'video/quicktime' : 'video/mp4')
          : (extension.endsWith('.png')
                ? 'image/png'
                : extension.endsWith('.webp')
                ? 'image/webp'
                : 'image/jpeg');
      // El servidor vuelve a comprobar formato y duración antes de publicar.
      // La URL local de XFile funciona como URI en los destinos de la app.
      if (video) {
        controlador = kIsWeb
            ? VideoPlayerController.networkUrl(Uri.parse(f.path))
            : VideoPlayerController.file(File(f.path));
        await controlador.initialize();
        if (controlador.value.duration > const Duration(seconds: 30)) {
          await controlador.dispose();
          throw Exception('El video debe durar como máximo 30 segundos.');
        }
        await controlador.setLooping(true);
        await controlador.play();
      }
      if (!mounted) {
        await controlador?.dispose();
        return;
      }
      // Se conserva el archivo ya validado al reintentar la publicación.
      final path = await ref.read(socialAftrProvider).subir(bytes, mime);
      if (!mounted) {
        await controlador?.dispose();
        return;
      }
      await _video?.dispose();
      setState(() {
        _video = controlador;
        _foto = video ? null : bytes;
        _arte = null;
        _path = path;
        _mime = mime;
      });
      asignado = true;
    } catch (e) {
      if (mounted) setState(() => _error = mensajeDeError(e));
    } finally {
      if (!asignado) await controlador?.dispose();
      if (mounted) setState(() => _ocupado = false);
    }
  }

  Future<void> _publicar(List<Evento> eventos) async {
    if (_ocupado || _publicada) return;
    final club = ref.read(clubActivoIdProvider);
    if (club == null || (_path == null && _arte == null)) return;
    setState(() {
      _ocupado = true;
      _error = null;
    });
    try {
      final repo = ref.read(socialAftrProvider);
      final path = _path ?? await repo.subirArte(_arte!);
      _path = path;
      await repo.historias('publicar', {
        'identidad':
            _identidad ??
            (ref.read(rolProvider).value == Rol.admin ? 'club' : 'rrpp'),
        'club_id': club,
        'storage_path': path,
        if (_evento != null) 'evento_id': _evento,
        'cta': _evento == null || _cta == 'ninguna' ? null : _cta,
      });
      _publicada = true;
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) setState(() => _error = mensajeDeError(e));
    } finally {
      if (mounted) setState(() => _ocupado = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final eventos = ref.watch(eventosProvider);
    final rol = ref.watch(rolProvider).value;
    final club = ref.watch(clubActivoProvider);
    final lista = eventos.value ?? const <Evento>[];
    final puedePublicar = _path != null || _arte != null;
    return PopScope(
      canPop: !_ocupado,
      child: Scaffold(
        appBar: AppBar(title: const Text('Nueva historia')),
        body: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 640),
              child: ListView(
                padding: const EdgeInsets.all(20),
                children: [
                  Text(
                    club?.nombre ?? 'AFTR',
                    style: const TextStyle(
                      fontSize: 26,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  Text(
                    'Fotos de 5 segundos · Videos hasta 30 segundos · 24 horas en AFTR',
                    style: TextStyle(color: VenueColors.textoSuave),
                  ),
                  const SizedBox(height: 20),
                  if (rol == Rol.admin)
                    DropdownButtonFormField<String>(
                      initialValue: _identidad ?? 'club',
                      decoration: const InputDecoration(
                        labelText: 'Publicar como',
                      ),
                      items: const [
                        DropdownMenuItem(value: 'club', child: Text('Boliche')),
                        DropdownMenuItem(
                          value: 'rrpp',
                          child: Text('Mi perfil de relacionador'),
                        ),
                      ],
                      onChanged: _ocupado
                          ? null
                          : (v) => setState(() => _identidad = v),
                    ),
                  const SizedBox(height: 14),
                  AspectRatio(
                    aspectRatio: 9 / 12,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(22),
                      child: ColoredBox(
                        color: Colors.black,
                        child: _video != null
                            ? Center(
                                child: AspectRatio(
                                  aspectRatio: _video!.value.aspectRatio,
                                  child: VideoPlayer(_video!),
                                ),
                              )
                            : _foto != null
                            ? Image.memory(_foto!, fit: BoxFit.contain)
                            : _arte != null
                            ? Image.network(
                                _arte!,
                                fit: BoxFit.contain,
                                errorBuilder: (_, _, _) => const Center(
                                  child: Text('No se pudo cargar el arte'),
                                ),
                              )
                            : Center(
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Icon(
                                      Icons.auto_awesome_outlined,
                                      color: Colors.white70,
                                      size: 48,
                                    ),
                                    const SizedBox(height: 12),
                                    Text(
                                      'Tu próxima noche, en una historia',
                                      style: TextStyle(
                                        color: Colors.white.withValues(
                                          alpha: .8,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _ocupado ? null : () => _elegir(false),
                          icon: const Icon(Icons.photo_outlined),
                          label: const Text('Foto'),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _ocupado ? null : () => _elegir(true),
                          icon: const Icon(Icons.videocam_outlined),
                          label: const Text('Video'),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  DropdownButtonFormField<String>(
                    initialValue: _evento,
                    decoration: const InputDecoration(
                      labelText: 'Vincular un evento',
                    ),
                    items: [
                      const DropdownMenuItem(
                        value: '',
                        child: Text('Sin evento'),
                      ),
                      for (final e in lista)
                        DropdownMenuItem(
                          value: e.id,
                          child: Text(
                            e.nombre,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                    ],
                    isExpanded: true,
                    onChanged: _ocupado
                        ? null
                        : (v) => setState(() {
                            _evento = v == '' ? null : v;
                            _cta = 'ninguna';
                          }),
                  ),
                  if (eventos.hasError)
                    TextButton(
                      onPressed: () => ref.invalidate(eventosProvider),
                      child: const Text('Reintentar carga de eventos'),
                    ),
                  if (_evento != null) ...[
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      key: ValueKey('cta-$_evento'),
                      initialValue: _cta,
                      decoration: const InputDecoration(
                        labelText: 'Botón de la historia',
                      ),
                      items: const [
                        DropdownMenuItem(
                          value: 'ninguna',
                          child: Text('Ver evento'),
                        ),
                        DropdownMenuItem(
                          value: 'entrada',
                          child: Text('Comprar entradas'),
                        ),
                        DropdownMenuItem(
                          value: 'mesa',
                          child: Text('Reservar mesa'),
                        ),
                      ],
                      onChanged: _ocupado
                          ? null
                          : (v) => setState(() => _cta = v ?? 'ninguna'),
                    ),
                    if (lista
                        .where((e) => e.id == _evento && e.ticketUrl != null)
                        .isNotEmpty)
                      TextButton.icon(
                        onPressed: _ocupado
                            ? null
                            : () async {
                                final arte = lista
                                    .firstWhere((e) => e.id == _evento)
                                    .ticketUrl!;
                                await _video?.dispose();
                                if (mounted)
                                  setState(() {
                                    _arte = arte;
                                    _foto = null;
                                    _video = null;
                                    _path = null;
                                    _mime = 'image/jpeg';
                                  });
                              },
                        icon: const Icon(Icons.palette_outlined),
                        label: const Text('Usar arte del evento'),
                      ),
                  ],
                  const SizedBox(height: 16),
                  if (_error != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Text(
                        _error!,
                        style: TextStyle(color: VenueColors.mal),
                      ),
                    ),
                  if (_ocupado) const LinearProgressIndicator(),
                  FilledButton.icon(
                    onPressed: !_ocupado && puedePublicar
                        ? () => _publicar(lista)
                        : null,
                    icon: const Icon(Icons.arrow_upward_rounded),
                    label: Text(
                      _ocupado
                          ? 'Preparando historia…'
                          : 'Publicar por 24 horas',
                    ),
                  ),
                  if ((_identidad ?? (rol == Rol.admin ? 'club' : 'rrpp')) ==
                      'rrpp')
                    Padding(
                      padding: const EdgeInsets.only(top: 10),
                      child: Text(
                        'Las compras desde esta historia se atribuyen automáticamente a tu perfil.',
                        style: TextStyle(color: VenueColors.textoSuave),
                      ),
                    ),
                  if (_mime.startsWith('video'))
                    TextButton(
                      onPressed: () {
                        final v = _video;
                        if (v != null) v.value.isPlaying ? v.pause() : v.play();
                      },
                      child: const Text('Pausar / reproducir vista previa'),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _VistaHistoria extends ConsumerStatefulWidget {
  const _VistaHistoria({required this.historia});
  final DatosSocial historia;
  @override
  ConsumerState<_VistaHistoria> createState() => _VistaHistoriaState();
}

class _VistaHistoriaState extends ConsumerState<_VistaHistoria> {
  String? _url, _error;
  VideoPlayerController? _video;
  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    try {
      final repo = ref.read(socialAftrProvider);
      // Por clave opaca: la ruta del archivo ya no viaja en el feed. Queda la
      // ruta como respaldo para las historias publicadas antes de la clave.
      final clave = widget.historia['media_key'] as String?;
      final url = clave != null
          ? await repo.medioPorClave(clave)
          : await repo.medio(
              'aftr-historias',
              widget.historia['storage_path'] as String,
            );
      if (url == null) throw Exception('No pudimos abrir esta historia.');
      VideoPlayerController? video;
      if (widget.historia['tipo'] == 'video') {
        video = VideoPlayerController.networkUrl(Uri.parse(url));
        await video.initialize();
        await video.setLooping(true);
        await video.play();
      }
      if (!mounted) {
        await video?.dispose();
        return;
      }
      setState(() {
        _url = url;
        _video = video;
        _error = null;
      });
    } catch (e) {
      if (mounted) setState(() => _error = mensajeDeError(e));
    }
  }

  @override
  void dispose() {
    _video?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: Colors.black,
    appBar: AppBar(
      backgroundColor: Colors.black,
      foregroundColor: Colors.white,
      title: Text(textoSocial(widget.historia['nombre'])),
    ),
    body: SafeArea(
      child: Center(
        child: _error != null
            ? TextButton(
                onPressed: _cargar,
                child: Text('$_error\nReintentar', textAlign: TextAlign.center),
              )
            : _url == null
            ? const CircularProgressIndicator()
            : _video != null
            ? GestureDetector(
                onTap: () {
                  final v = _video!;
                  v.value.isPlaying ? v.pause() : v.play();
                },
                child: AspectRatio(
                  aspectRatio: _video!.value.aspectRatio,
                  child: VideoPlayer(_video!),
                ),
              )
            : Image.network(
                _url!,
                fit: BoxFit.contain,
                errorBuilder: (_, _, _) => TextButton(
                  onPressed: _cargar,
                  child: const Text('Recargar historia'),
                ),
              ),
      ),
    ),
    bottomNavigationBar: SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Text(
          '${textoSocial(widget.historia['evento'])}\nDisponible hasta ${fechaSocial(widget.historia['vence_at'])}',
          style: const TextStyle(color: Colors.white70),
          textAlign: TextAlign.center,
        ),
      ),
    ),
  );
}

String fechaSocial(dynamic valor) {
  final d = DateTime.tryParse('$valor')?.toLocal();
  if (d == null) return '';
  return '${d.day}/${d.month} ${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
}

class SocialVacio extends StatelessWidget {
  const SocialVacio({
    super.key,
    required this.icono,
    required this.titulo,
    required this.detalle,
  });
  final IconData icono;
  final String titulo, detalle;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 44, horizontal: 20),
    child: Column(
      children: [
        Icon(icono, size: 52, color: VenueColors.textoTenue),
        const SizedBox(height: 18),
        Text(
          titulo,
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 10),
        Text(
          detalle,
          textAlign: TextAlign.center,
          style: TextStyle(color: VenueColors.textoSuave),
        ),
      ],
    ),
  );
}
