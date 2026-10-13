import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/networking/supabase.dart';
import '../../../core/theme/venue_theme.dart';
import '../../../core/widgets/avisos.dart';
import '../../../core/widgets/estado_vista.dart';
import '../../clubs/data/clubs.dart';
import '../../events/data/eventos.dart';
import '../../tickets/data/entradas.dart';
import '../../tickets/ui/ticket_sheet.dart';
import '../data/listas.dart';

/// Listas del evento: anotar invitados, ver los propios por lista con el
/// cupo, y mandarles su QR.
class ListasScreen extends ConsumerWidget {
  const ListasScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ev = ref.watch(eventoActivoProvider);
    if (ev == null) {
      return const MensajeVista(
          icono: Icons.event_busy_rounded, titulo: 'No hay evento activo');
    }
    final listas = ref.watch(listasProvider);
    final invitados = ref.watch(misInvitadosProvider).value ?? const <Invitado>[];
    final cupos = ref.watch(misCuposProvider).value ?? const <String, int>{};
    final ahora = DateTime.now();

    void recargar() {
      ref.invalidate(listasProvider);
      ref.invalidate(misInvitadosProvider);
      ref.invalidate(misCuposProvider);
    }

    return RefreshIndicator(
      onRefresh: () async {
        recargar();
        await ref.read(misInvitadosProvider.future);
      },
      child: VistaAsync(
        valor: listas,
        reintentar: recargar,
        datos: (ls) {
          if (ls.isEmpty) {
            return ListView(children: const [
              SizedBox(height: 100),
              MensajeVista(
                icono: Icons.list_alt_rounded,
                titulo: 'El evento no tiene listas',
                detalle: 'Las configura el administrador del boliche.',
              ),
            ]);
          }
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
            children: [
              for (final l in ls)
                _ListaCard(
                  lista: l,
                  evento: ev,
                  abierta: l.abierta(ahora),
                  cupo: cupos[l.id],
                  invitados:
                      invitados.where((i) => i.listaId == l.id).toList(),
                  alCambiar: recargar,
                ),
            ],
          );
        },
      ),
    );
  }
}

class _ListaCard extends ConsumerWidget {
  const _ListaCard({
    required this.lista,
    required this.evento,
    required this.abierta,
    required this.cupo,
    required this.invitados,
    required this.alCambiar,
  });

  final ListaTipo lista;
  final Evento evento;
  final bool abierta;
  final int? cupo;
  final List<Invitado> invitados;
  final VoidCallback alCambiar;

  Future<void> _anotar(BuildContext context, WidgetRef ref) async {
    final texto = TextEditingController();
    final nombres = await showModalBottomSheet<List<String>>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: VenueColors.superficie,
      builder: (c) => Padding(
        padding: EdgeInsets.fromLTRB(
            20, 0, 20, 20 + MediaQuery.of(c).viewInsets.bottom),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Anotar en ${lista.nombre}',
                style:
                    const TextStyle(fontSize: 19, fontWeight: FontWeight.w800)),
            const SizedBox(height: 4),
            const Text('Un nombre completo por línea.',
                style: TextStyle(color: VenueColors.textoSuave)),
            const SizedBox(height: 12),
            TextField(
              controller: texto,
              autofocus: true,
              minLines: 4,
              maxLines: 8,
              textCapitalization: TextCapitalization.words,
              decoration:
                  const InputDecoration(hintText: 'Ana Paz\nJorge Vaca'),
            ),
            const SizedBox(height: 14),
            FilledButton(
              onPressed: () => Navigator.pop(c, separarNombres(texto.text)),
              child: const Text('Anotar'),
            ),
          ],
        ),
      ),
    );
    if (nombres == null || nombres.isEmpty || !context.mounted) return;
    try {
      final r = await ref.read(listasRepositoryProvider).anotar(lista.id, nombres);
      alCambiar();
      if (!context.mounted) return;
      avisar(
        context,
        r.duplicados.isEmpty
            ? '${r.insertados} anotado(s)'
            : '${r.insertados} anotado(s). Ojo, ya estaban en el evento: ${r.duplicados.join(', ')}',
        tipo: r.duplicados.isEmpty ? TipoAviso.ok : TipoAviso.aviso,
      );
    } catch (e) {
      if (context.mounted) {
        avisar(context, mensajeDeError(e), tipo: TipoAviso.aviso);
      }
    }
  }

  Future<void> _qr(BuildContext context, WidgetRef ref, Invitado i) async {
    try {
      final codigo =
          i.codigo ?? await ref.read(listasRepositoryProvider).generarQr(i.id);
      if (i.codigo == null) alCambiar();
      if (!context.mounted) return;
      final club = ref.read(clubActivoProvider);
      await mostrarTicket(
        context,
        TicketDatos(
          payload: payloadLista(evento.id, codigo),
          codigo: codigo,
          cliente: i.nombre,
          boliche: club?.nombre ?? '',
          evento: evento.nombre,
          fecha: evento.fechaCorta,
          tipo: lista.nombre,
          color: club?.primario,
        ),
      );
    } catch (e) {
      if (context.mounted) {
        avisar(context, mensajeDeError(e), tipo: TipoAviso.aviso);
      }
    }
  }

  Future<void> _quitar(BuildContext context, WidgetRef ref, Invitado i) async {
    try {
      await ref.read(listasRepositoryProvider).eliminar(i.id);
      alCambiar();
      if (context.mounted) {
        avisar(context, '${i.nombre} eliminado de la lista',
            tipo: TipoAviso.aviso);
      }
    } catch (e) {
      if (context.mounted) {
        avisar(context, mensajeDeError(e), tipo: TipoAviso.aviso);
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final lleno = cupo != null && invitados.length >= cupo!;
    final ingresaron = invitados.where((i) => i.ingreso).length;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 8, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(lista.nombre,
                            style: const TextStyle(
                                fontSize: 18, fontWeight: FontWeight.w800)),
                        Text(
                          [
                            cupo == null
                                ? '${invitados.length} anotados'
                                : '${invitados.length} de $cupo',
                            '$ingresaron ingresaron',
                            if (lista.ingresoHasta != null)
                              'entran hasta ${lista.ingresoHasta}',
                            if (!abierta) 'cerrada para anotar',
                          ].join(' · '),
                          style: TextStyle(
                              color: abierta
                                  ? VenueColors.textoSuave
                                  : VenueColors.aviso,
                              fontSize: 13),
                        ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: FilledButton.tonal(
                      onPressed: abierta && !lleno
                          ? () => _anotar(context, ref)
                          : null,
                      style: FilledButton.styleFrom(
                          minimumSize: const Size(96, 44)),
                      child: Text(lleno ? 'Cupo lleno' : 'Anotar'),
                    ),
                  ),
                ],
              ),
              if (invitados.isNotEmpty) const Divider(height: 20),
              for (final i in invitados)
                Row(
                  children: [
                    Icon(
                      i.ingreso
                          ? Icons.check_circle_rounded
                          : Icons.radio_button_unchecked,
                      size: 20,
                      color: i.ingreso ? VenueColors.ok : VenueColors.linea,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        i.ingreso
                            ? '${i.nombre} · ${horaCorta(i.ingresoAt!)}'
                            : i.nombre,
                        style: const TextStyle(fontSize: 15.5),
                      ),
                    ),
                    IconButton(
                      tooltip: 'QR de ${i.nombre}',
                      icon: const Icon(Icons.qr_code_2_rounded),
                      onPressed: () => _qr(context, ref, i),
                    ),
                    if (!i.ingreso)
                      IconButton(
                        tooltip: 'Quitar a ${i.nombre}',
                        icon: const Icon(Icons.close_rounded,
                            color: VenueColors.textoSuave),
                        onPressed: () => _quitar(context, ref, i),
                      ),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }
}
