import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:video_player/video_player.dart';

import '../../core/networking/supabase.dart';
import '../../core/theme/aftr_theme.dart';
import '../../core/widgets/avatar.dart';
import '../../core/widgets/piezas.dart';
import '../../data/aftr_repo.dart';
import '../../data/modelos.dart';
import '../../data/firmas.dart';
import '../../data/social_repo.dart';
import '../auth/asegurar_cuenta.dart';

List<List<DatosSocial>> agruparHistorias(List<DatosSocial> historias) {
  final grupos = <String, List<DatosSocial>>{};
  for (final h in historias) {
    // `grupo` lo arma el servidor y no dice quién es el autor: antes se
    // agrupaba por autor_id, que ahora no viaja sin sesión.
    final key = '${h['grupo'] ?? '${h['identidad']}:${h['club_id'] ?? h['autor_id']}'}';
    (grupos[key] ??= []).add(h);
  }
  return grupos.values.toList();
}

class HistoriasFila extends ConsumerWidget {
  const HistoriasFila({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final feed = ref.watch(historiasProvider);
    final grupos = agruparHistorias(listaSocial(feed.value?['historias']));
    final yo = ref.watch(perfilProvider).value;
    return SizedBox(
      height: 116,
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(20, 10, 20, 8),
        scrollDirection: Axis.horizontal,
        separatorBuilder: (_, _) => const SizedBox(width: 15),
        itemCount: grupos.length + 1,
        itemBuilder: (_, i) {
          if (i == 0) {
            return _CirculoHistoria(nombre: 'Tu historia', agregar: true,
              foto: yo?.foto, archivo: yo?.archivoFoto,
              onTap: () async {
                if (!await asegurarCuenta(context, ref) || !context.mounted) return;
                await Navigator.of(context, rootNavigator: true).push<void>(
                  MaterialPageRoute(builder: (_) => const CrearHistoriaScreen()));
              });
          }
          final h = grupos[i - 1].first;
          return _CirculoHistoria(nombre: '${h['nombre'] ?? h['autor'] ?? 'AFTR'}',
            foto: h['foto'] as String?, clave: h['foto_key'] as String?,
            onTap: () => Navigator.of(context, rootNavigator: true).push<void>(
              MaterialPageRoute(builder: (_) => HistoriasVisor(
                grupos: grupos, grupoInicial: i - 1,
                desfase: desfaseSocial(feed.value ?? {})))));
        },
      ),
    );
  }
}

class _CirculoHistoria extends StatelessWidget {
  const _CirculoHistoria({required this.nombre, required this.onTap,
    this.agregar = false, this.foto, this.archivo, this.clave});
  final String nombre;
  final VoidCallback onTap;
  final bool agregar;
  /// Foto del autor: URL directa (logo del boliche) o ruta por firmar.
  final String? foto;
  final String? archivo;

  /// Clave opaca de la foto del autor, que firma el servidor.
  final String? clave;
  bool get _conFoto =>
    (foto ?? '').isNotEmpty || (archivo ?? '').isNotEmpty || (clave ?? '').isNotEmpty;
  @override
  Widget build(BuildContext context) => Semantics(
    button: true, label: agregar ? 'Publicar una historia' : 'Historias de $nombre',
    child: InkWell(onTap: onTap, borderRadius: BorderRadius.circular(40), child: SizedBox(
      width: 70,
      child: Column(children: [
        Container(width: 66, height: 66, padding: const EdgeInsets.all(3),
          decoration: BoxDecoration(shape: BoxShape.circle,
            gradient: agregar ? null : const LinearGradient(colors: [Aftr.acento, Color(0xFFBD7D49), Aftr.acento]),
            border: agregar ? Border.all(color: Aftr.bordeFuerte) : null),
          child: Container(alignment: Alignment.center,
            decoration: const BoxDecoration(color: Aftr.superficie2, shape: BoxShape.circle,
              border: Border.fromBorderSide(BorderSide(color: Aftr.fondo, width: 3))),
            // la foto de perfil del autor; sin foto queda la inicial, y en el
            // propio círculo el + sigue visible en una esquina
            child: !_conFoto
              ? (agregar ? const Icon(Icons.add_rounded, color: Aftr.texto) :
                  Text(nombre.isEmpty ? 'A' : nombre.substring(0, 1).toUpperCase(), style: Aftr.titular(28)))
              : Stack(alignment: Alignment.bottomRight, children: [
                  AvatarRemoto(nombre: nombre, foto: foto, archivo: archivo, clave: clave, radio: 27),
                  if (agregar) Container(
                    decoration: BoxDecoration(color: Aftr.acento, shape: BoxShape.circle,
                      border: Border.all(color: Aftr.fondo, width: 2)),
                    child: const Icon(Icons.add_rounded, size: 13, color: Aftr.fondo)),
                ])),
        ),
        const SizedBox(height: 7),
        Text(nombre, maxLines: 1, overflow: TextOverflow.ellipsis, style: Aftr.cuerpo(11, c: Aftr.texto)),
      ]),
    )),
  );
}

class HistoriasVisor extends ConsumerStatefulWidget {
  const HistoriasVisor({super.key, required this.grupos, required this.grupoInicial,
    this.desfase = Duration.zero});
  final List<List<DatosSocial>> grupos;
  final int grupoInicial;
  final Duration desfase;
  @override
  ConsumerState<HistoriasVisor> createState() => _VisorState();
}

class _VisorState extends ConsumerState<HistoriasVisor> with WidgetsBindingObserver {
  late int _grupo = widget.grupoInicial;
  int _indice = 0, _generacion = 0;
  VideoPlayerController? _video;
  String? _url, _error;
  bool _lista = false, _pausa = false, _fondo = false, _menu = false;
  /// Ya se pidió cerrar el visor. El reloj sigue latiendo mientras la pantalla
  /// se va, y sin esto volvía a pedir el cierre en cada latido.
  bool _saliendo = false;
  Duration _imagen = Duration.zero;
  DateTime _ultimo = DateTime.now();
  /// Las que ya se dejaron descargadas, para no precargarlas dos veces. Las
  /// URL no se guardan acá: las guarda Firmas, que sabe cuándo vencen.
  final Set<String> _precargadas = {};
  Timer? _reloj;
  DatosSocial get _h => widget.grupos[_grupo][_indice];
  bool get _detenida => _pausa || _fondo || _menu || !_lista;
  bool get _esVideo => _h['tipo'] == 'video';
  double get _avance => _esVideo
    ? (_video == null || _video!.value.duration.inMilliseconds == 0 ? 0 :
       _video!.value.position.inMilliseconds / _video!.value.duration.inMilliseconds).clamp(0.0, 1.0).toDouble()
    : (_imagen.inMilliseconds / 5000).clamp(0.0, 1.0).toDouble();

  @override
  void initState() {
    super.initState(); WidgetsBinding.instance.addObserver(this); _cargar();
    _reloj = Timer.periodic(const Duration(milliseconds: 50), (_) {
      if (!mounted || _saliendo) return;
      final ahora = DateTime.now();
      final transcurrido = ahora.difference(_ultimo); _ultimo = ahora;
      if (tiempoRestante(_h['vence_at'], ahora.add(widget.desfase)) == Duration.zero) {
        _siguiente(); return;
      }
      if (_detenida || _video?.value.isBuffering == true || _error != null) return;
      if (!_esVideo) _imagen += transcurrido;
      if (_avance >= 0.999) { _siguiente(); } else { setState(() {}); }
    });
  }
  @override
  void dispose() {
    _generacion++; _reloj?.cancel(); _video?.dispose();
    WidgetsBinding.instance.removeObserver(this); super.dispose();
  }
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _fondo = state != AppLifecycleState.resumed; _sincronizar();
    // Al volver de segundo plano la firma pudo vencerse. No se mide el tiempo
    // a mano: se pregunta a Firmas, que guarda cada URL hasta el 80 % de su
    // plazo y vuelve a firmar sola.
    final clave = _h['media_key'] as String?;
    if (!_fondo && _url != null && clave != null &&
        ref.read(firmasProvider).enCache(clave) == null) {
      _cargar();
    }
  }
  void _sincronizar() {
    if (_detenida) { _video?.pause(); } else { _video?.play(); }
    _ultimo = DateTime.now();
  }
  Future<void> _cargar() async {
    final version = ++_generacion;
    final anterior = _video; _video = null; anterior?.dispose();
    _lista = false; _error = null; _url = null; _imagen = Duration.zero;
    if (mounted) setState(() {});
    try {
      // la firma de la siguiente ya puede estar pedida: abrir sin esperarla
      final url = await _firmar(_h);
      if (!mounted || version != _generacion || url == null) {
        if (url == null && mounted && version == _generacion) {
          setState(() => _error = 'No pudimos abrir esta historia.');
        }
        return;
      }
      _precargadas.add(_h['id'] as String);
      if (_esVideo) {
        final video = VideoPlayerController.networkUrl(Uri.parse(url));
        await video.initialize();
        if (!mounted || version != _generacion) { video.dispose(); return; }
        _video = video; _lista = true; _sincronizar();
      } else {
        // la foto entra ya descargada: nada de ver media imagen o un salto
        await precacheImage(NetworkImage(url), context);
        if (!mounted || version != _generacion) return;
      }
      setState(() => _url = url);
      _precargarSiguiente();
    } catch (e) {
      if (mounted && version == _generacion) setState(() => _error = mensajeDeError(e));
    }
  }

  /// Deja lista la que sigue mientras se mira la actual, como Instagram: al
  /// tocar para avanzar ya está firmada y descargada.
  Future<void> _precargarSiguiente() async {
    final h = _despuesDe(_grupo, _indice);
    if (h == null || _precargadas.contains(h['id'])) return;
    try {
      final url = await _firmar(h);
      if (!mounted || url == null) return;
      _precargadas.add(h['id'] as String);
      if (h['tipo'] != 'video') await precacheImage(NetworkImage(url), context);
    } catch (_) {
      // si falla, la siguiente se pide igual cuando toque: no molestamos acá
    }
  }

  /// La URL del archivo de una historia. Por clave opaca cuando el servidor la
  /// manda -lo normal-, y por la ruta vieja mientras queden historias
  /// publicadas antes de la clave.
  Future<String?> _firmar(DatosSocial h) async {
    final clave = h['media_key'] as String?;
    if (clave != null && clave.isNotEmpty) {
      return ref.read(firmasProvider).url(clave);
    }
    final ruta = h['storage_path'] as String?;
    if (ruta == null || ruta.isEmpty) return null;
    return ref.read(socialRepoProvider).firmar('aftr-historias', ruta);
  }

  /// La historia que viene después de una posición, saltando de autor si hace
  /// falta. Devuelve null en la última.
  DatosSocial? _despuesDe(int grupo, int indice) {
    if (indice + 1 < widget.grupos[grupo].length) {
      return widget.grupos[grupo][indice + 1];
    }
    if (grupo + 1 < widget.grupos.length) return widget.grupos[grupo + 1][0];
    return null;
  }
  /// Cierra el visor una sola vez.
  ///
  /// Al terminar la última historia la pantalla quedaba negra: el reloj de 50
  /// ms seguía corriendo mientras la pantalla se iba, veía el avance completo
  /// otra vez y volvía a cerrar, así que después de la última historia se
  /// llevaba también la pantalla de abajo.
  void _salir() {
    if (_saliendo) return;
    _saliendo = true; _reloj?.cancel();
    if (mounted) Navigator.of(context).pop();
  }
  void _siguiente({bool autor = false}) {
    if (_saliendo) return;
    if (!autor && _indice + 1 < widget.grupos[_grupo].length) { _indice++; }
    else if (_grupo + 1 < widget.grupos.length) { _grupo++; _indice = 0; }
    else { _salir(); return; }
    _cargar();
  }
  void _anterior({bool autor = false}) {
    if (_saliendo) return;
    if (!autor && _indice > 0) { _indice--; }
    else if (_grupo > 0) { _grupo--; _indice = 0; }
    else { _imagen = Duration.zero; _video?.seekTo(Duration.zero); return; }
    _cargar();
  }
  Future<void> _opciones() async {
    _menu = true; _sincronizar();
    final propia = _h['autor_id'] == ref.read(usuarioIdProvider);
    final accion = await showModalBottomSheet<String>(context: context, builder: (ctx) => SafeArea(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        if (propia) ListTile(leading: const Icon(Icons.delete_outline), title: const Text('Eliminar historia'),
          onTap: () => Navigator.pop(ctx, 'retirar')),
        ListTile(leading: const Icon(Icons.flag_outlined), title: const Text('Reportar historia'),
          onTap: () => Navigator.pop(ctx, 'reportar')),
        // bloquear es silencioso: el otro no se entera y se puede deshacer
        // desde Cuenta → Ajustes → Cuentas bloqueadas
        if (!propia) ListTile(leading: const Icon(Icons.block_outlined), title: const Text('Bloquear a esta persona'),
          subtitle: const Text('No vas a ver más sus historias'),
          onTap: () => Navigator.pop(ctx, 'bloquear')),
      ])));
    if (!mounted) return;
    if (accion != null) {
      try {
        if (!await asegurarCuenta(context, ref) || !mounted) return;
        // el motivo era un texto fijo: quien modera no sabía de qué se
        // trataba el reporte hasta abrir la historia
        String? motivo;
        if (accion == 'reportar') {
          motivo = await _motivoDelReporte();
          if (motivo == null || !mounted) { _menu = false; _sincronizar(); return; }
        }
        await ref.read(socialRepoProvider).historias(accion, {
          if (accion == 'bloquear') 'usuario': _h['autor_id'] else 'id': _h['id'],
          if (motivo != null) 'motivo': motivo,
        });
        ref.invalidate(historiasProvider);
        if (mounted) {
          avisar(context, switch (accion) {
            'retirar' => 'Historia eliminada.',
            'bloquear' => 'Listo, no vas a ver más sus historias.',
            _ => 'Reporte enviado.',
          });
          _siguiente();
        }
      } catch (e) { if (mounted) avisar(context, mensajeDeError(e)); }
    }
    _menu = false; _sincronizar();
  }
  /// Por qué se reporta. Devuelve null si la persona se arrepiente.
  Future<String?> _motivoDelReporte() => showModalBottomSheet<String>(
    context: context,
    builder: (ctx) => SafeArea(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        const Padding(
          padding: EdgeInsets.fromLTRB(20, 18, 20, 8),
          child: Text('¿Por qué la reportás?',
            style: TextStyle(fontWeight: FontWeight.w700, fontSize: 17)),
        ),
        for (final m in const [
          'Desnudez o contenido sexual',
          'Violencia o amenazas',
          'Odio o discriminación',
          'Acoso a una persona',
          'Drogas ilegales',
          'Estafa o spam',
          'Es de un menor de edad',
          'Otro motivo',
        ])
          ListTile(title: Text(m), onTap: () => Navigator.pop(ctx, m)),
      ]),
    ),
  );

  @override
  Widget build(BuildContext context) {
    ref.listen(historiasProvider, (_, siguiente) {
      final datos = siguiente.value;
      if (datos != null && !_saliendo &&
          !listaSocial(datos['historias']).any((h) => h['id'] == _h['id'])) {
        _salir();
      }
    });
    final grupo = widget.grupos[_grupo];
    return Scaffold(backgroundColor: Colors.black, body: SafeArea(child: Stack(fit: StackFit.expand, children: [
      if (_url != null && !_esVideo) Center(child: Image.network(_url!, fit: BoxFit.contain,
        frameBuilder: (_, child, frame, synchronous) {
          if ((frame != null || synchronous) && !_lista) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted && !_lista) { setState(() => _lista = true); _sincronizar(); }
            });
          }
          return child;
        }, errorBuilder: (_, _, _) => Center(child: TextButton(onPressed: _cargar, child: const Text('No se pudo cargar. Reintentar'))))),
      if (_video != null) Center(child: AspectRatio(aspectRatio: _video!.value.aspectRatio, child: VideoPlayer(_video!))),
      if (!_lista && _error == null) const Center(child: CircularProgressIndicator(color: Aftr.acento)),
      if (_error != null) Center(child: Padding(padding: const EdgeInsets.all(30), child: Column(mainAxisSize: MainAxisSize.min, children: [
        Text(_error!, textAlign: TextAlign.center, style: Aftr.cuerpo(15)),
        TextButton(onPressed: _cargar, child: const Text('Reintentar')),
      ]))),
      Positioned.fill(child: GestureDetector(behavior: HitTestBehavior.translucent,
        onTapUp: (d) => d.localPosition.dx < MediaQuery.sizeOf(context).width * .3 ? _anterior() : _siguiente(),
        onLongPressStart: (_) { _pausa = true; _sincronizar(); },
        onLongPressEnd: (_) { _pausa = false; _sincronizar(); },
        onHorizontalDragEnd: (d) { if ((d.primaryVelocity ?? 0) < -150) _siguiente(autor: true); else if ((d.primaryVelocity ?? 0) > 150) _anterior(autor: true); },
        onVerticalDragEnd: (d) { if ((d.primaryVelocity ?? 0) > 200) _salir(); })),
      Positioned(top: 0, left: 0, right: 0, child: Container(
        padding: const EdgeInsets.fromLTRB(14, 8, 8, 26),
        decoration: const BoxDecoration(gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Colors.black87, Colors.transparent])),
        child: Column(children: [
          Row(children: [for (var i = 0; i < grupo.length; i++) Expanded(child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 2),
            child: LinearProgressIndicator(value: i < _indice ? 1 : i == _indice ? _avance : 0,
              minHeight: 3, color: Aftr.texto, backgroundColor: Colors.white30, borderRadius: BorderRadius.circular(3))))]),
          const SizedBox(height: 8),
          Row(children: [
            AvatarRemoto(nombre: '${_h['nombre'] ?? _h['autor'] ?? 'AFTR'}',
              foto: _h['foto'] as String?, clave: _h['foto_key'] as String?, radio: 16),
            const SizedBox(width: 10),
            Expanded(child: Text('${_h['nombre'] ?? _h['autor'] ?? 'AFTR'}', style: Aftr.fuerte(16))),
            IconButton(onPressed: _opciones, icon: const Icon(Icons.more_horiz)),
            IconButton(onPressed: _salir, icon: const Icon(Icons.close)),
          ]),
        ]))),
      if (_h['evento_id'] != null) Positioned(bottom: 24, left: 24, right: 24, child: Column(children: [
        Text('${_h['evento'] ?? ''}', textAlign: TextAlign.center, style: Aftr.fuerte(19)),
        const SizedBox(height: 12),
        BotonAftr(_h['cta'] == 'mesa' ? 'Reservar mesa' : _h['cta'] == 'entrada' ? 'Comprar entradas' : 'Ver evento',
          onTap: () {
            final h = _h; final router = GoRouter.of(context);
            _salir();
            router.push('/evento/${h['evento_id']}?historia=${Uri.encodeQueryComponent('${h['id']}')}${h['cta'] == null ? '' : '&accion=${h['cta']}'}');
          }),
      ])),
    ])));
  }
}

class CrearHistoriaScreen extends ConsumerStatefulWidget {
  const CrearHistoriaScreen({super.key});
  @override
  ConsumerState<CrearHistoriaScreen> createState() => _CrearHistoriaState();
}

class _CrearHistoriaState extends ConsumerState<CrearHistoriaScreen> {
  Uint8List? _bytes;
  VideoPlayerController? _video;
  Evento? _evento;
  String? _cta, _subida;
  String? _error;
  bool _ocupado = false, _publicada = false;
  @override
  void dispose() {
    _video?.dispose();
    if (!_publicada && _subida != null) ref.read(socialRepoProvider).borrar('aftr-historias', _subida!);
    super.dispose();
  }
  Future<void> _elegir({bool video = false}) async {
    setState(() { _ocupado = true; _error = null; });
    try {
      final picker = ImagePicker();
      final archivo = video ? await picker.pickVideo(source: ImageSource.gallery, maxDuration: const Duration(seconds: 30)) :
        await picker.pickImage(source: ImageSource.gallery, maxWidth: 2160, maxHeight: 3840, imageQuality: 88);
      if (archivo == null) return;
      if (await archivo.length() > 30 * 1024 * 1024) throw const FormatException('El archivo debe pesar menos de 30 MB.');
      final bytes = await archivo.readAsBytes(); final tipo = tipoMedio(bytes);
      VideoPlayerController? controlador;
      if (tipo.video) {
        controlador = VideoPlayerController.file(File(archivo.path));
        await controlador.initialize();
        if (controlador.value.duration > const Duration(seconds: 30)) {
          await controlador.dispose(); throw const FormatException('El video debe durar hasta 30 segundos.');
        }
        await controlador.setLooping(true); await controlador.play();
      }
      if (!mounted) { controlador?.dispose(); return; }
      _video?.dispose();
      if (_subida != null) { await ref.read(socialRepoProvider).borrar('aftr-historias', _subida!); _subida = null; }
      setState(() { _bytes = bytes; _video = controlador; });
    } catch (e) { if (mounted) setState(() => _error = mensajeDeError(e)); }
    finally { if (mounted) setState(() => _ocupado = false); }
  }
  Future<void> _arte() async {
    final url = Uri.tryParse(_evento?.flyer ?? '');
    if (url == null || url.scheme != 'https') { setState(() => _error = 'Este evento no tiene un arte disponible.'); return; }
    setState(() { _ocupado = true; _error = null; });
    final cliente = HttpClient()..connectionTimeout = const Duration(seconds: 15);
    try {
      final respuesta = await (await cliente.getUrl(url)).close().timeout(const Duration(seconds: 20));
      if (respuesta.statusCode != 200) throw const FormatException('No se pudo obtener el arte.');
      final builder = BytesBuilder(copy: false);
      await for (final parte in respuesta.timeout(const Duration(seconds: 20))) {
        builder.add(parte);
        if (builder.length > 30 * 1024 * 1024) throw const FormatException('El arte supera 30 MB.');
      }
      final bytes = builder.takeBytes();
      if (tipoMedio(bytes).video) throw const FormatException('El arte debe ser una imagen.');
      if (!mounted) return;
      _video?.dispose(); _video = null;
      if (_subida != null) { await ref.read(socialRepoProvider).borrar('aftr-historias', _subida!); _subida = null; }
      setState(() => _bytes = bytes);
    } catch (e) { if (mounted) setState(() => _error = mensajeDeError(e)); }
    finally { cliente.close(force: true); if (mounted) setState(() => _ocupado = false); }
  }
  Future<void> _publicar() async {
    if (_bytes == null || _ocupado) return;
    setState(() { _ocupado = true; _error = null; });
    try {
      _subida ??= await ref.read(socialRepoProvider).subir(_bytes!, historia: true);
      await ref.read(socialRepoProvider).historias('publicar', {
        'identidad': 'usuario', 'storage_path': _subida,
        'evento_id': _evento?.id, 'cta': _evento == null ? null : _cta,
      });
      _publicada = true; ref.invalidate(historiasProvider);
      if (mounted) { avisar(context, 'Tu historia está publicada por 24 horas.'); Navigator.pop(context); }
    } catch (e) { if (mounted) setState(() => _error = mensajeDeError(e)); }
    finally { if (mounted) setState(() => _ocupado = false); }
  }
  @override
  Widget build(BuildContext context) {
    final eventos = ref.watch(eventosProvider);
    return Scaffold(appBar: AppBar(title: const Text('Tu historia')), body: ListView(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 40), children: [
        Text('24 horas en la noche.', style: Aftr.titular(32)),
        const SizedBox(height: 8), Text('Fotos, videos de hasta 30 segundos o el arte de un evento.', style: Aftr.cuerpo(14)),
        const SizedBox(height: 20),
        ClipRRect(borderRadius: BorderRadius.circular(24), child: AspectRatio(aspectRatio: 9 / 12,
          child: Container(color: Aftr.superficie2, alignment: Alignment.center,
            child: _video != null ? AspectRatio(aspectRatio: _video!.value.aspectRatio, child: VideoPlayer(_video!)) :
            _bytes != null ? Image.memory(_bytes!, fit: BoxFit.contain) : const Icon(Icons.add_photo_alternate_outlined, size: 58, color: Aftr.texto3)))),
        const SizedBox(height: 14),
        Row(children: [Expanded(child: OutlinedButton.icon(onPressed: _ocupado ? null : () => _elegir(), icon: const Icon(Icons.photo_outlined), label: const Text('Foto'))),
          const SizedBox(width: 12), Expanded(child: OutlinedButton.icon(onPressed: _ocupado ? null : () => _elegir(video: true), icon: const Icon(Icons.videocam_outlined), label: const Text('Video')))]),
        const SizedBox(height: 20),
        DropdownButtonFormField<String>(initialValue: _evento?.id, isExpanded: true,
          decoration: const InputDecoration(labelText: 'Vincular un evento (opcional)'),
          items: [const DropdownMenuItem(value: '', child: Text('Sin evento')),
            for (final e in eventos.value ?? <Evento>[]) DropdownMenuItem(value: e.id, child: Text(e.nombre, overflow: TextOverflow.ellipsis))],
          onChanged: _ocupado ? null : (id) => setState(() { _evento = eventos.value?.where((e) => e.id == id).firstOrNull; _cta = null; })),
        if (eventos.hasError) TextButton(onPressed: () => ref.invalidate(eventosProvider), child: const Text('Reintentar cargar eventos')),
        if (_evento != null) ...[
          const SizedBox(height: 10),
          if (_evento!.flyer != null) TextButton.icon(onPressed: _ocupado ? null : _arte, icon: const Icon(Icons.auto_awesome_outlined), label: const Text('Usar arte de este evento')),
          DropdownButtonFormField<String>(key: ValueKey(_evento?.id), initialValue: _cta ?? '',
            decoration: const InputDecoration(labelText: 'Botón de la historia'),
            items: const [DropdownMenuItem(value: '', child: Text('Ver evento')),
              DropdownMenuItem(value: 'entrada', child: Text('Comprar entradas')),
              DropdownMenuItem(value: 'mesa', child: Text('Reservar mesa'))],
            onChanged: _ocupado ? null : (v) => setState(() => _cta = v == '' ? null : v)),
        ],
        if (_error != null) Padding(padding: const EdgeInsets.symmetric(vertical: 14), child: Text(_error!, style: Aftr.cuerpo(14, c: Aftr.alerta))),
        const SizedBox(height: 24),
        BotonAftr('Publicar historia', cargando: _ocupado, onTap: _bytes == null ? null : _publicar),
      ]));
  }
}
