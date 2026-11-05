import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../data/foto_perfil.dart';
import '../theme/aftr_theme.dart';

class AvatarAftr extends StatelessWidget {
  const AvatarAftr({super.key, this.nombre, this.foto, this.radio = 18});
  final String? nombre;
  final String? foto;
  final double radio;

  @override
  Widget build(BuildContext context) => ClipOval(
    child: SizedBox.square(
      dimension: radio * 2,
      child: foto == null || foto!.isEmpty
          ? _inicial()
          : CachedNetworkImage(
              imageUrl: foto!,
              cacheKey: Uri.parse(foto!).replace(query: '').toString(),
              fit: BoxFit.cover,
              fadeInDuration: Duration.zero,
              fadeOutDuration: Duration.zero,
              placeholder: (_, _) => _inicial(),
              errorWidget: (_, _, _) => _inicial(),
            ),
    ),
  );

  Widget _inicial() => ColoredBox(
    color: Aftr.superficie2,
    child: Center(
      child: Text(
        nombre?.trim().isNotEmpty == true
            ? nombre!.trim().characters.first.toUpperCase()
            : '?',
        style: Aftr.fuerte(radio * .85),
      ),
    ),
  );
}

/// La foto de otra persona, que llega como ruta del bucket privado y hay que
/// firmar antes de mostrarla. Mientras tanto, y si no tiene foto, queda la
/// inicial del nombre.
class AvatarRemoto extends ConsumerWidget {
  const AvatarRemoto({
    super.key,
    this.nombre,
    this.foto,
    this.archivo,
    this.radio = 18,
  });
  final String? nombre;

  /// URL directa (el logo de un boliche, o una foto antigua con URL pública).
  final String? foto;

  /// Ruta en el bucket de perfiles, que se firma para poder verla.
  final String? archivo;
  final double radio;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    var url = foto;
    if ((url == null || url.isEmpty) && archivo != null && archivo!.isNotEmpty) {
      url = ref.watch(fotoFirmadaProvider(archivo!)).value;
    }
    return AvatarAftr(nombre: nombre, foto: url, radio: radio);
  }
}
