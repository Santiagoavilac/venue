import 'package:flutter/material.dart';
import 'package:skeletonizer/skeletonizer.dart';

import '../theme/tokens.dart';
import '../theme/venue_theme.dart';
import 'tarjeta_cifra.dart';

/// Lo que se ve mientras carga: la forma de lo que viene, en gris.
///
/// Antes había 46 ruleditas centradas. Una ruedita no dice nada —ni cuánto
/// falta, ni qué va a aparecer— y encima mueve todo cuando los datos llegan,
/// porque la pantalla pasa de un punto en el medio a una lista entera. El
/// informe de diseño lo pide al revés: que el espacio ya esté ocupado por la
/// forma del contenido.
///
/// Son filas de mentira, con el alto real de las de verdad.
class EsqueletoLista extends StatelessWidget {
  const EsqueletoLista({super.key, this.filas = 5, this.conFoto = true});

  final int filas;

  /// Las filas que empiezan con un avatar o una miniatura.
  final bool conFoto;

  @override
  Widget build(BuildContext context) => Skeletonizer(
    child: ListView.separated(
      padding: const EdgeInsets.all(Esp.lg),
      physics: const NeverScrollableScrollPhysics(),
      shrinkWrap: true,
      itemCount: filas,
      separatorBuilder: (_, _) => const SizedBox(height: Esp.md),
      itemBuilder: (_, i) => Card(
        margin: EdgeInsets.zero,
        child: ListTile(
          leading: conFoto ? const CircleAvatar(radius: 20) : null,
          title: Text('Nombre de ejemplo ${'·' * (i % 3)}'),
          subtitle: const Text('Una línea de apoyo con el detalle'),
          trailing: const Text('000'),
        ),
      ),
    ),
  );
}

/// Esqueleto de una pantalla que arranca con números arriba y una lista
/// abajo: Inicio, Accesos, Pagos.
class EsqueletoResumen extends StatelessWidget {
  const EsqueletoResumen({super.key, this.cifras = 4, this.filas = 3});

  final int cifras;
  final int filas;

  @override
  Widget build(BuildContext context) => Skeletonizer(
    child: ListView(
      padding: const EdgeInsets.all(Esp.lg),
      physics: const NeverScrollableScrollPhysics(),
      shrinkWrap: true,
      children: [
        GrillaCifras(
          children: [
            for (var i = 0; i < cifras; i++)
              const TarjetaCifra(etiqueta: 'Etiqueta', valor: '000'),
          ],
        ),
        const SizedBox(height: Esp.xl),
        for (var i = 0; i < filas; i++) ...[
          Card(
            margin: EdgeInsets.zero,
            child: const ListTile(
              title: Text('Nombre de ejemplo'),
              subtitle: Text('Una línea de apoyo'),
            ),
          ),
          const SizedBox(height: Esp.md),
        ],
      ],
    ),
  );
}

/// Para lo que no es una lista ni un resumen: un bloque gris del alto que
/// vaya a ocupar el contenido.
class EsqueletoBloque extends StatelessWidget {
  const EsqueletoBloque({super.key, this.alto = 120});

  final double alto;

  @override
  Widget build(BuildContext context) => Skeletonizer(
    child: Container(
      height: alto,
      margin: const EdgeInsets.all(Esp.lg),
      decoration: BoxDecoration(
        color: VenueColors.superficie,
        borderRadius: BorderRadius.circular(Radio_.tarjeta),
      ),
    ),
  );
}
