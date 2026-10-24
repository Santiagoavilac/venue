import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/routing/secciones.dart';
import '../../../core/theme/venue_theme.dart';
import '../../../core/widgets/estado_vista.dart';
import '../../../core/widgets/patron.dart';
import '../../authentication/data/sesion.dart';
import '../../clubs/data/clubs.dart';
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
          final perfil = ref.watch(perfilProvider).value;
          final rol = ref.watch(rolProvider).value;
          void ir(String t) => ref.read(seccionPedidaProvider.notifier).ir(t);
          final otros = lista.where((e) => e.id != activo?.id).toList();
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
            children: [
              Saludo(
                nombre: perfil?.primerNombre ?? '',
                detalle: activo == null ? 'Elegí un evento para trabajar' : 'Lo de tu próximo evento',
              ),
              // arriba, el evento de trabajo en grande
              if (activo != null)
                _Resumen(activo, atajos: [
                  if (rol?.vende ?? false)
                    (Icons.format_list_bulleted_rounded, 'Listas', () => ir('Accesos')),
                  if (rol?.validaIngresos ?? false)
                    (Icons.qr_code_scanner_rounded, 'Escanear QR', () => ir('Escáner')),
                  if (rol?.veEventos ?? false) (Icons.table_bar_outlined, 'Mesas', () => ir('Mesas')),
                ]),
              if (rol?.vende ?? false) ...[
                const TituloBloque('Accesos rápidos'),
                GrillaAcciones(children: [
                  AccionRapida(
                    icono: Icons.person_add_alt_1_outlined,
                    titulo: 'Anotar invitados',
                    detalle: 'Listas y entradas',
                    alTocar: () => ir('Accesos'),
                  ),
                  AccionRapida(
                    icono: Icons.table_bar_outlined,
                    titulo: 'Mesas',
                    detalle: 'Vender y reservar',
                    color: VenueColors.info,
                    alTocar: () => ir('Mesas'),
                  ),
                  AccionRapida(
                    icono: Icons.payments_outlined,
                    titulo: 'Pagos',
                    detalle: 'Lo que cobraste',
                    color: VenueColors.ok,
                    alTocar: () => ir('Pagos'),
                  ),
                  AccionRapida(
                    icono: Icons.bar_chart_rounded,
                    titulo: 'Mis números',
                    detalle: 'Ventas y comisión',
                    color: VenueColors.aviso,
                    alTocar: () => ir('Stats'),
                  ),
                ]),
              ],
              if (otros.isNotEmpty) const TituloBloque('Otros eventos'),
              for (final e in otros) ...[
                _FilaEvento(
                  e: e,
                  vivo: e.enCurso(ahora),
                  hoy: e.esHoy(ahora),
                  alTocar: () => ref.read(eventoElegidoProvider.notifier).elegir(e.id),
                ),
                const SizedBox(height: 8),
              ],
            ],
          );
        },
      ),
    );
  }
}

/// Un evento que no es el de trabajo: tocarlo lo elige.
class _FilaEvento extends StatelessWidget {
  const _FilaEvento({required this.e, required this.vivo, required this.hoy, required this.alTocar});
  final Evento e;
  final bool vivo, hoy;
  final VoidCallback alTocar;

  @override
  Widget build(BuildContext context) {
    final marca = Theme.of(context).colorScheme.primary;
    return Tarjeta(
      padding: EdgeInsets.zero,
      child: InkWell(
        onTap: alTocar,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(children: [
            // fecha en un cuadrito, como las agendas de referencia
            Container(
              width: 52,
              padding: const EdgeInsets.symmetric(vertical: 6),
              decoration: BoxDecoration(
                color: marca.withValues(alpha: .10),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(children: [
                Text(e.fechaCorta.split(' ').last.toUpperCase(),
                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: marca)),
                Text('${e.fecha.day}',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: marca, height: 1.1)),
              ]),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(e.nombre,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                const SizedBox(height: 2),
                Text('${e.horaInicio} – ${e.horaFin} hs',
                    style: TextStyle(fontSize: 13, color: VenueColors.textoSuave)),
              ]),
            ),
            if (vivo)
              _Etiqueta('EN VIVO', VenueColors.ok)
            else if (hoy)
              _Etiqueta('HOY', VenueColors.aviso),
            Icon(Icons.chevron_right_rounded, color: VenueColors.textoTenue),
          ]),
        ),
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

/// Resumen del evento de trabajo: la misma tarjeta grande que ve el admin.
class _Resumen extends StatelessWidget {
  const _Resumen(this.e, {this.atajos = const []});
  final Evento e;
  final List<(IconData, String, VoidCallback)> atajos;

  @override
  Widget build(BuildContext context) {
    final ahora = DateTime.now();
    return HeroEvento(
      eventoId: e.id,
      nombre: e.nombre,
      detalle: '${fechaLarga(e.fecha)} · ${e.horaInicio} – ${e.horaFin} hs · Manilla ${e.precioManilla} Bs',
      imagen: e.ticketUrl,
      estado: e.enCurso(ahora)
          ? ('en vivo', VenueColors.ok)
          : e.esHoy(ahora)
              ? ('hoy', VenueColors.aviso)
              : ('próximo', null),
      atajos: atajos,
    );
  }
}
