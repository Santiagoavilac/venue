import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
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
