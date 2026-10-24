import 'package:flutter/material.dart';

import 'patron.dart';

/// La foto de perfil de alguien; si no tiene (o mientras carga, o si falla),
/// su inicial con el tono de siempre.
class FotoPersona extends StatelessWidget {
  const FotoPersona({super.key, required this.nombre, this.url, this.tam = 42});

  final String nombre;
  final String? url;
  final double tam;

  @override
  Widget build(BuildContext context) {
    final inicial = Inicial(nombre, lado: tam);
    final u = url;
    if (u == null || u.isEmpty) return inicial;
    return ClipOval(
      child: Image.network(
        u,
        width: tam,
        height: tam,
        fit: BoxFit.cover,
        cacheWidth: (tam * MediaQuery.devicePixelRatioOf(context)).round(),
        loadingBuilder: (_, child, progreso) => progreso == null ? child : inicial,
        errorBuilder: (_, _, _) => inicial,
      ),
    );
  }
}
