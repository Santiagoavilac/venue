import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import '../../core/networking/supabase.dart';
import '../../core/theme/aftr_theme.dart';
import '../../core/widgets/avatar.dart';
import '../../core/widgets/piezas.dart';
import '../../data/aftr_repo.dart';
import '../../data/foto_perfil.dart';
import '../../data/modelos.dart';

Future<void> editarFoto(BuildContext context, Cliente perfil) =>
    showModalBottomSheet<void>(
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      builder: (_) => _EditorFoto(perfil: perfil),
    );

class _EditorFoto extends ConsumerStatefulWidget {
  const _EditorFoto({required this.perfil});
  final Cliente perfil;
  @override
  ConsumerState<_EditorFoto> createState() => _EditorFotoState();
}

class _EditorFotoState extends ConsumerState<_EditorFoto> {
  Uint8List? _bytes;
  bool _ocupado = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    // Android puede recrear la actividad mientras el selector está abierto.
    _recuperar();
  }

  Future<void> _recuperar() async {
    try {
      final r = await ImagePicker().retrieveLostData();
      if (r.files?.isNotEmpty == true) {
        final b = await r.files!.first.readAsBytes();
        extensionFoto(b);
        if (mounted) setState(() => _bytes = b);
      }
    } catch (_) {}
  }

  Future<void> _elegir() async {
    setState(() {
      _ocupado = true;
      _error = null;
    });
    try {
      final f = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        maxWidth: 800,
        maxHeight: 800,
        imageQuality: 82,
        requestFullMetadata: false,
      );
      if (f == null) return;
      final b = await f.readAsBytes();
      extensionFoto(b);
      if (b.length > 2 * 1024 * 1024) {
        throw const FormatException('La foto debe pesar menos de 2 MB.');
      }
      if (mounted) setState(() => _bytes = b);
    } catch (e) {
      if (mounted) setState(() => _error = mensajeDeError(e));
    } finally {
      if (mounted) setState(() => _ocupado = false);
    }
  }

  Future<void> _guardar({bool quitar = false}) async {
    setState(() {
      _ocupado = true;
      _error = null;
    });
    try {
      final repo = ref.read(fotoPerfilRepoProvider);
      if (quitar) {
        await repo.quitar(widget.perfil.archivoFoto);
      } else {
        await repo.guardar(_bytes!, widget.perfil.archivoFoto);
      }
      ref.invalidate(perfilProvider);
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (mounted) setState(() => _error = mensajeDeError(e));
    } finally {
      if (mounted) setState(() => _ocupado = false);
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_ocupado,
    child: Padding(
      padding: EdgeInsets.fromLTRB(
        24,
        12,
        24,
        24 + MediaQuery.paddingOf(context).bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text('Foto de perfil', style: Aftr.fuerte(22)),
              const Spacer(),
              IconButton(
                tooltip: 'Cerrar',
                onPressed: _ocupado ? null : () => Navigator.pop(context),
                icon: const Icon(Icons.close),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Center(
            child: _bytes == null
                ? AvatarAftr(
                    nombre: widget.perfil.nombre,
                    foto: widget.perfil.foto,
                    radio: 64,
                  )
                : ClipOval(
                    child: Image.memory(
                      _bytes!,
                      width: 128,
                      height: 128,
                      fit: BoxFit.cover,
                      errorBuilder: (_, _, _) => const SizedBox.square(
                        dimension: 128,
                        child: Center(child: Text('Imagen no válida')),
                      ),
                    ),
                  ),
          ),
          const SizedBox(height: 20),
          TextButton(
            onPressed: _ocupado ? null : _elegir,
            child: const Text('Elegir de mis fotos'),
          ),
          if (widget.perfil.foto != null && _bytes == null)
            TextButton(
              onPressed: _ocupado ? null : () => _guardar(quitar: true),
              child: const Text('Quitar foto'),
            ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Text(_error!, style: Aftr.cuerpo(14, c: Aftr.alerta)),
            ),
          if (_bytes != null)
            BotonAftr(
              'Guardar foto',
              cargando: _ocupado,
              onTap: _ocupado ? null : _guardar,
            ),
          if (_ocupado && _bytes == null) const LinearProgressIndicator(),
        ],
      ),
    ),
  );
}
