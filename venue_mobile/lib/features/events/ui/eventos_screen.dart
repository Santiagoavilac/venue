import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/venue_theme.dart';
import '../../../core/widgets/estado_vista.dart';
import '../data/eventos.dart';
import 'gestion_screen.dart';

/// Eventos abiertos del boliche. Tocar uno lo deja como evento de trabajo
/// para el resto de la app (escáner, listas…).
class EventosScreen extends ConsumerWidget {
  const EventosScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final eventos = ref.watch(eventosProvider);
    final activo = ref.watch(eventoActivoProvider);
    final ahora = DateTime.now();

    return RefreshIndicator(
      onRefresh: () => ref.refresh(eventosProvider.future),
      child: VistaAsync(
        valor: eventos,
        reintentar: () => ref.invalidate(eventosProvider),
        datos: (lista) {
          if (lista.isEmpty) {
            return ListView(
              children: const [
                SizedBox(height: 120),
                MensajeVista(
                  icono: Icons.event_outlined,
                  titulo: 'No hay eventos próximos',
                  detalle: 'Cuando el administrador publique uno va a aparecer acá.',
                ),
              ],
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
            // arriba, el resumen del evento de trabajo
            itemCount: lista.length + (activo == null ? 0 : 1),
            separatorBuilder: (_, _) => const SizedBox(height: 10),
            itemBuilder: (context, i) {
              if (activo != null && i == 0) return _Resumen(activo);
              final e = lista[activo == null ? i : i - 1];
              final sel = e.id == activo?.id;
              final vivo = e.enCurso(ahora);
              final marca = Theme.of(context).colorScheme.primary;
              return Card(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                  side: BorderSide(
                    color: sel ? marca : VenueColors.linea,
                    width: sel ? 1.8 : 1,
                  ),
                ),
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                  onTap: () =>
                      ref.read(eventoElegidoProvider.notifier).elegir(e.id),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                e.nombre,
                                style: const TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                '${e.fechaCorta} · ${e.horaInicio} a ${e.horaFin}',
                                style: const TextStyle(
                                    color: VenueColors.textoSuave),
                              ),
                            ],
                          ),
                        ),
                        if (vivo)
                          const _Etiqueta('EN VIVO', VenueColors.ok)
                        else if (e.esHoy(ahora))
                          const _Etiqueta('HOY', VenueColors.aviso),
                        if (sel) ...[
                          const SizedBox(width: 10),
                          Icon(Icons.check_circle_rounded, color: marca),
                        ],
                      ],
                    ),
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}

class _Etiqueta extends StatelessWidget {
  const _Etiqueta(this.texto, this.color);
  final String texto;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .16),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        texto,
        style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w800),
      ),
    );
  }
}

/// Resumen del evento de trabajo: nombre, fecha, horario, precio y números.
class _Resumen extends StatelessWidget {
  const _Resumen(this.e);
  final Evento e;

  @override
  Widget build(BuildContext context) {
    final marca = Theme.of(context).colorScheme.primary;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: VenueColors.superficie,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: marca.withValues(alpha: .45)),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [marca.withValues(alpha: .16), VenueColors.superficie],
        ),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text(e.nombre.toUpperCase(),
            style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w900, letterSpacing: .5)),
        const SizedBox(height: 4),
        Text(
          '${e.fechaCorta} · ${e.horaInicio}–${e.horaFin} hs · Manilla ${e.precioManilla} Bs',
          style: const TextStyle(color: VenueColors.textoSuave),
        ),
        const SizedBox(height: 14),
        NumerosEvento(eventoId: e.id),
      ]),
    );
  }
}
