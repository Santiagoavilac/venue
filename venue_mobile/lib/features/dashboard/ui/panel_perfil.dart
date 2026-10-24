import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/sync/cola_offline.dart';
import '../../../core/theme/venue_theme.dart';
import '../../authentication/data/sesion.dart';
import '../../clubs/data/clubs.dart';
import '../../clubs/ui/selector_club_screen.dart';
import '../../vip_tables/ui/mesa_hojas.dart';

class CuentaScreen extends ConsumerWidget {
  const CuentaScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final perfil = ref.watch(perfilProvider).value;
    final club = ref.watch(clubActivoProvider);
    final rol = ref.watch(rolProvider).value;
    final variosClubs = (ref.watch(clubsProvider).value?.length ?? 0) > 1;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 26,
                  backgroundColor:
                      Theme.of(context).colorScheme.primary.withValues(alpha: .22),
                  child: Text(
                    perfil?.inicial ?? '·',
                    style: const TextStyle(
                        fontSize: 22, fontWeight: FontWeight.w800),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        perfil?.nombre ?? '',
                        style: const TextStyle(
                            fontSize: 18, fontWeight: FontWeight.w800),
                      ),
                      Text(
                        [
                          if (perfil != null) '@${perfil.usuario}',
                          if (rol != null) rol.etiqueta,
                        ].join(' · '),
                        style: const TextStyle(color: VenueColors.textoSuave),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        if (club != null)
          Card(
            clipBehavior: Clip.antiAlias,
            child: ListTile(
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              leading: MarcaClub(club: club, lado: 42),
              title: Text(club.nombre,
                  style: const TextStyle(fontWeight: FontWeight.w700)),
              subtitle: Text(variosClubs ? 'Cambiar de boliche' : 'Tu boliche'),
              trailing: variosClubs
                  ? const Icon(Icons.swap_horiz_rounded)
                  : null,
              onTap: variosClubs
                  ? () => ref.read(clubActivoIdProvider.notifier).elegir(null)
                  : null,
            ),
          ),
        // Los combos son de cada boliche: el admin los arma acá (también
        // siguen en el ⋯ de Mesas). El servidor solo deja escribir al admin.
        if (rol == Rol.admin && club != null) ...[
          const SizedBox(height: 12),
          Card(
            clipBehavior: Clip.antiAlias,
            child: ListTile(
              leading: const Icon(Icons.local_bar_outlined),
              title: const Text('Combos', style: TextStyle(fontWeight: FontWeight.w700)),
              subtitle: Text('Los de ${club.nombre}'),
              trailing: const Icon(Icons.chevron_right_rounded),
              onTap: () => hojaCombos(context),
            ),
          ),
        ],
        const SizedBox(height: 20),
        OutlinedButton.icon(
          onPressed: () async {
            final pend = ref.read(pendientesProvider);
            if (pend > 0) {
              final si = await showDialog<bool>(
                context: context,
                builder: (c) => AlertDialog(
                  title: Text('Hay $pend operación(es) sin enviar'),
                  content: const Text(
                      'Si cerrás sesión ahora se pierden: todavía no llegaron al servidor.'),
                  actions: [
                    TextButton(
                        onPressed: () => Navigator.pop(c, false),
                        child: const Text('Seguir conectado')),
                    TextButton(
                        onPressed: () => Navigator.pop(c, true),
                        style: TextButton.styleFrom(
                            foregroundColor: VenueColors.mal),
                        child: const Text('Cerrar y descartar')),
                  ],
                ),
              );
              if (si != true) return;
            }
            // La cola guarda nombres de clientes: no queda en el teléfono.
            await ref.read(colaOfflineProvider).vaciar();
            await ref.read(authRepositoryProvider).salir();
          },
          icon: const Icon(Icons.logout_rounded),
          label: const Text('Cerrar sesión'),
        ),
      ],
    );
  }
}
