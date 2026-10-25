import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../data/modelos.dart';
import '../theme/aftr_theme.dart';
import 'movimiento.dart';
import 'piezas.dart';

/// Línea de datos: "sáb 24 oct · 23:00 · Equipetrol".
String lineaEvento(Evento e) =>
    [fechaCorta(e.fecha), e.horaInicio, e.club.zona].whereType<String>().where((s) => s.isNotEmpty).join(' · ');

String? precioDesde(Evento e) {
  if (e.desdePrecio == null) return e.tieneLista ? 'Lista free' : null;
  return e.desdePrecio == 0 ? 'Gratis' : 'Desde ${bs(e.desdePrecio)}';
}

/// La tarjeta grande de arriba de Descubrir (como el destacado de Resy): foto
/// alta, el nombre encima del degradé y los datos abajo.
class TarjetaDestacada extends StatelessWidget {
  const TarjetaDestacada(this.e, {super.key});

  final Evento e;

  @override
  Widget build(BuildContext context) {
    final ahora = e.esAhora(DateTime.now());
    return Presionable(
      onTap: () => context.push('/evento/${e.id}', extra: e),
      child: AspectRatio(
        aspectRatio: 0.82,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(Aftr.radio + 4),
          child: Stack(fit: StackFit.expand, children: [
            Hero(tag: 'flyer-${e.id}', child: ImagenRed(e.flyer, color: e.club.color)),
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  stops: [0.35, 1],
                  colors: [Colors.transparent, Color(0xF0000000)],
                ),
              ),
            ),
            Positioned(
              left: 18,
              right: 18,
              bottom: 18,
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  if (ahora) ...[const PuntoVivo(), const SizedBox(width: 4)],
                  Text((ahora ? 'ESTA NOCHE' : e.club.nombre.toUpperCase()), style: Aftr.etiqueta(c: ahora ? Aftr.vivo : Aftr.acento)),
                ]),
                const SizedBox(height: 8),
                Text(e.nombre, maxLines: 2, overflow: TextOverflow.ellipsis, style: Aftr.titular(36)),
                const SizedBox(height: 10),
                Text(lineaEvento(e), style: Aftr.cuerpo(14, c: Aftr.texto)),
                if (precioDesde(e) != null) ...[
                  const SizedBox(height: 14),
                  Pildora(precioDesde(e)!, activa: true, denso: true),
                ],
              ]),
            ),
          ]),
        ),
      ),
    );
  }
}

/// Tarjeta de carrusel: foto cuadrada y texto debajo.
class TarjetaEvento extends StatelessWidget {
  const TarjetaEvento(this.e, {super.key, this.ancho = 220});

  final Evento e;
  final double ancho;

  @override
  Widget build(BuildContext context) => Presionable(
        onTap: () => context.push('/evento/${e.id}', extra: e),
        child: SizedBox(
          width: ancho,
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            AspectRatio(
              aspectRatio: 0.9,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(Aftr.radio),
                child: Stack(fit: StackFit.expand, children: [
                  ImagenRed(e.flyer, color: e.club.color),
                  if (precioDesde(e) != null)
                    Positioned(left: 10, top: 10, child: Pildora(precioDesde(e)!, denso: true)),
                ]),
              ),
            ),
            const SizedBox(height: 10),
            Text(e.nombre, maxLines: 1, overflow: TextOverflow.ellipsis, style: Aftr.fuerte(17)),
            const SizedBox(height: 3),
            Text(e.club.nombre, maxLines: 1, overflow: TextOverflow.ellipsis, style: Aftr.cuerpo(13, c: Aftr.texto)),
            Text(lineaEvento(e), maxLines: 1, overflow: TextOverflow.ellipsis, style: Aftr.cuerpo(13)),
          ]),
        ),
      );
}

/// Fila compacta (lista de lugares de Resy): miniatura, nombre, datos y ›.
class FilaEvento extends StatelessWidget {
  const FilaEvento(this.e, {super.key, this.onTap});

  final Evento e;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => Presionable(
        onTap: onTap ?? () => context.push('/evento/${e.id}', extra: e),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
          child: Row(children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: SizedBox(width: 64, height: 64, child: ImagenRed(e.flyer, color: e.club.color)),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(e.nombre, maxLines: 1, overflow: TextOverflow.ellipsis, style: Aftr.fuerte(16)),
                const SizedBox(height: 3),
                Text('${e.club.nombre} · ${fechaCorta(e.fecha)} ${e.horaInicio}',
                    maxLines: 1, overflow: TextOverflow.ellipsis, style: Aftr.cuerpo(13, c: Aftr.texto)),
                if (precioDesde(e) != null)
                  Text(precioDesde(e)!, style: Aftr.cuerpo(13, c: Aftr.acento, w: FontWeight.w600)),
              ]),
            ),
            const Icon(Icons.chevron_right_rounded, color: Aftr.texto3),
          ]),
        ),
      );
}

/// Fila de lugar con su logo, zona y lo próximo.
class FilaLugar extends StatelessWidget {
  const FilaLugar(this.l, {super.key});

  final Lugar l;

  @override
  Widget build(BuildContext context) => Presionable(
        onTap: () => context.push('/lugar/${l.id}', extra: l),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
          child: Row(children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: SizedBox(width: 56, height: 56, child: ImagenRed(l.logo ?? l.portada, color: l.color)),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(l.nombre, style: Aftr.fuerte(16)),
                const SizedBox(height: 3),
                Row(children: [
                  const Icon(Icons.place_outlined, size: 13, color: Aftr.texto3),
                  const SizedBox(width: 3),
                  Flexible(
                    child: Text(
                      l.proximo != null ? '${l.zona ?? l.ciudad ?? ''} · ${l.proximo!.nombre}' : (l.zona ?? l.ciudad ?? ''),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Aftr.cuerpo(13),
                    ),
                  ),
                ]),
              ]),
            ),
            const Icon(Icons.chevron_right_rounded, color: Aftr.texto3),
          ]),
        ),
      );
}
