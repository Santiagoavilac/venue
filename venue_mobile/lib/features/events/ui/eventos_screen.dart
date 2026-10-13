import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/venue_theme.dart';
import '../../../core/widgets/estado_vista.dart';
import '../data/eventos.dart';

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
            itemCount: lista.length,
            separatorBuilder: (_, _) => const SizedBox(height: 10),
            itemBuilder: (context, i) {
              final e = lista[i];
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
