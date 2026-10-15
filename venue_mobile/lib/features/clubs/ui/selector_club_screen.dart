import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/venue_theme.dart';
import '../../../core/widgets/estado_vista.dart';
import '../../authentication/data/sesion.dart';
import '../../teams/data/gente.dart';
import '../../teams/ui/gente_screen.dart';
import '../data/clubs.dart';

class MarcaClub extends StatelessWidget {
  const MarcaClub({super.key, required this.club, this.lado = 48});
  final Club club;
  final double lado;

  @override
  Widget build(BuildContext context) {
    final a = club.primario ?? VenueColors.marcaPorDefecto;
    final b = club.secundario ?? a;
    return Container(
      width: lado,
      height: lado,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(lado * .28),
        gradient: LinearGradient(
          colors: [a, b],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Text(
        club.inicial,
        style: TextStyle(
          fontSize: lado * .46,
          fontWeight: FontWeight.w900,
          color: ThemeData.estimateBrightnessForColor(a) == Brightness.dark
              ? Colors.white
              : Colors.black,
        ),
      ),
    );
  }
}

/// Elegir el boliche en el que se va a trabajar. Con uno solo, se entra
/// directo (lo resuelve el router).
class SelectorClubScreen extends ConsumerWidget {
  const SelectorClubScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final clubs = ref.watch(clubsProvider);
    final perfil = ref.watch(perfilProvider).value;
    final plataforma = ref.watch(plataformaProvider).value ?? false;
    // el superadmin da de alta boliches desde acá, como en la web
    Future<void> nuevo() async {
      if (await abrirNuevoBoliche(context) == true) ref.invalidate(clubsProvider);
    }

    return Scaffold(
      body: SafeArea(
        child: VistaAsync(
          valor: clubs,
          reintentar: () => ref.invalidate(clubsProvider),
          datos: (lista) {
            if (lista.isEmpty && plataforma) {
              return MensajeVista(
                icono: Icons.add_business_outlined,
                titulo: 'Todavía no hay ningún boliche',
                detalle: 'Creá el primero para empezar a cargar eventos.',
                accion: 'Nuevo boliche',
                alTocar: nuevo,
              );
            }
            if (lista.isEmpty) {
              return MensajeVista(
                icono: Icons.storefront_outlined,
                titulo: 'Todavía no tenés un boliche asignado',
                detalle:
                    'Pedile al administrador que te sume a su local. Si acabás de registrarte, probá de nuevo en un momento.',
                accion: 'Cerrar sesión',
                alTocar: () => ref.read(authRepositoryProvider).salir(),
              );
            }
            return ListView(
              padding: const EdgeInsets.fromLTRB(20, 36, 20, 24),
              children: [
                Text(
                  perfil == null ? 'Hola' : 'Hola, ${perfil.primerNombre}',
                  style: const TextStyle(fontSize: 30, fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 4),
                const Text(
                  'Elegí el boliche en el que vas a trabajar',
                  style: TextStyle(color: VenueColors.textoSuave, fontSize: 16),
                ),
                const SizedBox(height: 24),
                for (final c in lista)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Card(
                      clipBehavior: Clip.antiAlias,
                      child: InkWell(
                        onTap: () =>
                            ref.read(clubActivoIdProvider.notifier).elegir(c.id),
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Row(
                            children: [
                              MarcaClub(club: c, lado: 54),
                              const SizedBox(width: 14),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      c.nombre,
                                      style: const TextStyle(
                                        fontSize: 19,
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                    if (c.subtitulo?.isNotEmpty ?? false)
                                      Text(
                                        c.subtitulo!,
                                        style: const TextStyle(
                                            color: VenueColors.textoSuave),
                                      ),
                                  ],
                                ),
                              ),
                              const Icon(Icons.chevron_right_rounded,
                                  color: VenueColors.textoSuave),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                if (plataforma)
                  OutlinedButton.icon(
                    onPressed: nuevo,
                    icon: const Icon(Icons.add_rounded),
                    label: const Text('Nuevo boliche'),
                  ),
                const SizedBox(height: 12),
                TextButton(
                  onPressed: () => ref.read(authRepositoryProvider).salir(),
                  child: const Text('Cerrar sesión'),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}
