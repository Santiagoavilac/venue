import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/tokens.dart';
import '../../../core/theme/venue_theme.dart';
import '../data/eventos.dart';

/// Elegir el evento de trabajo (el resto de la app opera sobre ese).
Future<void> cambiarEvento(BuildContext context, WidgetRef ref) async {
  final eventos = ref.read(eventosProvider).value ?? const <Evento>[];
  final actual = ref.read(eventoActivoProvider)?.id;
  // antes esto volvía sin hacer nada si había un solo evento, así que la
  // píldora parecía un cartel y nadie descubría que ahí se cambia de evento
  if (eventos.isEmpty) return;
  final elegido = await showModalBottomSheet<String>(
    context: context,
    builder: (c) => SafeArea(
      child: ListView(
        shrinkWrap: true,
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        children: [
          const Padding(
            padding: EdgeInsets.only(bottom: 10, left: 4),
            child: Text(
              'Evento',
              style: TextStyle(fontSize: 19, fontWeight: FontWeight.w700),
            ),
          ),
          for (final e in eventos)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Material(
                color: VenueColors.superficie2,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                  side: BorderSide(
                    color: e.id == actual
                        ? Theme.of(c).colorScheme.primary
                        : VenueColors.linea,
                  ),
                ),
                clipBehavior: Clip.antiAlias,
                child: ListTile(
                  leading: const Icon(Icons.calendar_today_outlined),
                  title: Text(
                    e.nombre,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  subtitle: Text(e.fechaCorta),
                  trailing: e.id == actual
                      ? const Icon(Icons.check_rounded)
                      : null,
                  onTap: () => Navigator.pop(c, e.id),
                ),
              ),
            ),
        ],
      ),
    ),
  );
  if (elegido != null) ref.read(eventoElegidoProvider.notifier).elegir(elegido);
}

/// La línea de arriba de una pantalla que trabaja sobre un evento: de cuál
/// son los números que se están mirando, y el toque para cambiarlo.
///
/// Mesas, Pagos y Accesos muestran los datos del evento activo sin decirlo. Si
/// el evento no es el que la persona cree —y hasta hace poco el que la app
/// elegía sola podía ser el más viejo sin cerrar— se termina contando plata o
/// dejando entrar gente del evento equivocado.
class DeQueEvento extends ConsumerWidget {
  const DeQueEvento({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ev = ref.watch(eventoActivoProvider);
    final marca = Theme.of(context).colorScheme.primary;
    return Material(
      color: VenueColors.superficie2,
      child: InkWell(
        onTap: () => cambiarEvento(context, ref),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: Esp.lg,
            vertical: Esp.md,
          ),
          child: Row(
            children: [
              Icon(Icons.calendar_today_outlined, size: 18, color: marca),
              const SizedBox(width: Esp.sm + 2),
              Expanded(
                child: Text.rich(
                  TextSpan(
                    children: [
                      TextSpan(
                        text: ev?.nombre ?? 'Sin evento',
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      if (ev != null)
                        TextSpan(
                          text: '  ·  ${ev.fechaCorta}',
                          style: TextStyle(color: VenueColors.textoSuave),
                        ),
                    ],
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Tipo.apoyo.copyWith(
                    fontSize: 14,
                    color: VenueColors.texto,
                  ),
                ),
              ),
              Text('Cambiar', style: Tipo.apoyo.copyWith(color: marca)),
              Icon(Icons.chevron_right_rounded, size: 20, color: marca),
            ],
          ),
        ),
      ),
    );
  }
}
