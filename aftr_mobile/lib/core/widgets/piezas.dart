import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../theme/aftr_theme.dart';
import 'movimiento.dart';

/// Bs 120 · sin decimales, como se cobra en la puerta.
String bs(num? v) => v == null ? '' : (v == 0 ? 'Gratis' : 'Bs ${v.round()}');

const _meses = ['ene', 'feb', 'mar', 'abr', 'may', 'jun', 'jul', 'ago', 'sep', 'oct', 'nov', 'dic'];
const _dias = ['lun', 'mar', 'mié', 'jue', 'vie', 'sáb', 'dom'];

/// "sáb 24 oct", o "Hoy" / "Mañana".
String fechaCorta(DateTime f, {DateTime? hoy}) {
  final h = hoy ?? DateTime.now();
  final d = DateTime(f.year, f.month, f.day).difference(DateTime(h.year, h.month, h.day)).inDays;
  if (d == 0) return 'Hoy';
  if (d == 1) return 'Mañana';
  return '${_dias[f.weekday - 1]} ${f.day} ${_meses[f.month - 1]}';
}

/// Imagen de la red con su fundido; sin imagen, un degradé oscuro del color
/// del boliche para que la tarjeta nunca quede vacía.
class ImagenRed extends StatelessWidget {
  const ImagenRed(this.url, {super.key, this.color, this.fit = BoxFit.cover});

  final String? url;
  final Color? color;
  final BoxFit fit;

  @override
  Widget build(BuildContext context) {
    final fondo = DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [(color ?? Aftr.superficie3).withValues(alpha: 0.55), Aftr.superficie],
        ),
      ),
    );
    final u = url;
    if (u == null || u.isEmpty) return fondo;
    return CachedNetworkImage(
      imageUrl: u,
      fit: fit,
      fadeInDuration: Aftr.medio,
      placeholder: (_, _) => fondo,
      errorWidget: (_, _, _) => fondo,
    );
  }
}

/// El botón principal: píldora blanca con texto negro.
class BotonAftr extends StatelessWidget {
  const BotonAftr(this.texto, {super.key, this.onTap, this.cargando = false, this.secundario = false, this.icono});

  final String texto;
  final VoidCallback? onTap;
  final bool cargando;
  final bool secundario;
  final Widget? icono;

  @override
  Widget build(BuildContext context) {
    final activo = onTap != null && !cargando;
    final fg = secundario ? Aftr.texto : Aftr.fondo;
    return Presionable(
      onTap: activo ? onTap : null,
      child: AnimatedContainer(
        duration: Aftr.rapido,
        height: 54,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: secundario ? Aftr.superficie2 : (activo || cargando ? Aftr.texto : Aftr.superficie3),
          borderRadius: BorderRadius.circular(28),
          border: secundario ? Border.all(color: Aftr.bordeFuerte) : null,
        ),
        child: cargando
            ? SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: fg))
            : Row(mainAxisSize: MainAxisSize.min, children: [
                if (icono != null) ...[icono!, const SizedBox(width: 10)],
                Text(texto,
                    style: TextStyle(
                        fontFamily: Aftr.sans,
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: activo || cargando ? fg : Aftr.texto3)),
              ]),
      ),
    );
  }
}

/// Píldora chica: filtros, horarios, categorías.
class Pildora extends StatelessWidget {
  const Pildora(this.texto, {super.key, this.activa = false, this.onTap, this.icono, this.denso = false});

  final String texto;
  final bool activa;
  final VoidCallback? onTap;
  final IconData? icono;
  final bool denso;

  @override
  Widget build(BuildContext context) => Presionable(
        onTap: onTap,
        child: AnimatedContainer(
          duration: Aftr.medio,
          curve: Aftr.curva,
          padding: EdgeInsets.symmetric(horizontal: denso ? 12 : 16, vertical: denso ? 7 : 10),
          decoration: BoxDecoration(
            color: activa ? Aftr.texto : Aftr.superficie2.withValues(alpha: 0.92),
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: activa ? Aftr.texto : Aftr.borde),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            if (icono != null) ...[
              Icon(icono, size: 16, color: activa ? Aftr.fondo : Aftr.texto),
              const SizedBox(width: 6),
            ],
            Text(texto,
                style: TextStyle(
                    fontFamily: Aftr.sans,
                    fontSize: denso ? 13 : 14,
                    fontWeight: FontWeight.w600,
                    color: activa ? Aftr.fondo : Aftr.texto)),
          ]),
        ),
      );
}

/// Título de sección estilo Resy: grande y apretado, con "Ver todo" opcional.
class TituloSeccion extends StatelessWidget {
  const TituloSeccion(this.texto, {super.key, this.accion, this.onAccion});

  final String texto;
  final String? accion;
  final VoidCallback? onAccion;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 30, 20, 14),
        child: Row(children: [
          Expanded(child: Text(texto, style: Aftr.fuerte(22))),
          if (accion != null)
            GestureDetector(
              onTap: onAccion,
              child: Text(accion!, style: Aftr.cuerpo(14, c: Aftr.texto, w: FontWeight.w600)),
            ),
        ]),
      );
}

/// Punto de "en vivo" que late.
class PuntoVivo extends StatefulWidget {
  const PuntoVivo({super.key, this.color = Aftr.vivo, this.tam = 8});

  final Color color;
  final double tam;

  @override
  State<PuntoVivo> createState() => _PuntoVivoState();
}

class _PuntoVivoState extends State<PuntoVivo> with SingleTickerProviderStateMixin {
  late final _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1400))..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SizedBox(
        width: widget.tam * 2.4,
        height: widget.tam * 2.4,
        child: AnimatedBuilder(
          animation: _c,
          builder: (_, _) => Stack(alignment: Alignment.center, children: [
            Container(
              width: widget.tam * (1 + 1.4 * _c.value),
              height: widget.tam * (1 + 1.4 * _c.value),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: widget.color.withValues(alpha: 0.45 * (1 - _c.value)),
              ),
            ),
            Container(
              width: widget.tam,
              height: widget.tam,
              decoration: BoxDecoration(shape: BoxShape.circle, color: widget.color),
            ),
          ]),
        ),
      );
}

/// Aviso corto abajo de la pantalla.
void avisar(BuildContext context, String texto) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(texto)));
}
