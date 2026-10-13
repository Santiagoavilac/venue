import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/networking/supabase.dart';
import '../../../core/theme/venue_theme.dart';
import '../../../core/widgets/avisos.dart';
import '../../../core/widgets/estado_vista.dart';
import '../../clubs/data/clubs.dart';
import '../../events/data/eventos.dart';
import '../data/entradas.dart';
import 'ticket_sheet.dart';

/// Entradas prepagadas que vende la persona: generar, ver el QR, compartir
/// y anular.
class EntradasScreen extends ConsumerStatefulWidget {
  const EntradasScreen({super.key});

  @override
  ConsumerState<EntradasScreen> createState() => _EntradasScreenState();
}

class _EntradasScreenState extends ConsumerState<EntradasScreen> {
  final _cliente = TextEditingController();
  bool _generando = false;

  @override
  void dispose() {
    _cliente.dispose();
    super.dispose();
  }

  TicketDatos _ticket(Entrada e, Evento ev) {
    final club = ref.read(clubActivoProvider);
    return TicketDatos(
      payload: payloadEntrada(ev.id, e.codigo),
      codigo: e.codigo,
      cliente: e.cliente,
      boliche: club?.nombre ?? '',
      evento: ev.nombre,
      fecha: ev.fechaCorta,
      tipo: 'Entrada prepagada',
      color: club?.primario,
    );
  }

  Future<void> _generar(Evento ev) async {
    final nombre = _cliente.text.trim();
    if (nombre.length < 2 || _generando) return;
    setState(() => _generando = true);
    try {
      final e = await ref.read(entradasRepositoryProvider).generar(ev.id, nombre);
      _cliente.clear();
      ref.invalidate(misEntradasProvider);
      if (mounted) {
        FocusScope.of(context).unfocus();
        await mostrarTicket(context, _ticket(e, ev));
      }
    } catch (e) {
      if (mounted) avisar(context, mensajeDeError(e), tipo: TipoAviso.aviso);
    }
    if (mounted) setState(() => _generando = false);
  }

  Future<void> _anular(Entrada e) async {
    final si = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text('Anular la entrada de ${e.cliente}'),
        content: Text(
            'El QR #${e.codigo} deja de servir en la puerta. No se puede deshacer.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: const Text('Cancelar')),
          TextButton(
            onPressed: () => Navigator.pop(c, true),
            style: TextButton.styleFrom(foregroundColor: VenueColors.mal),
            child: const Text('Anular entrada'),
          ),
        ],
      ),
    );
    if (si != true) return;
    try {
      await ref.read(entradasRepositoryProvider).anular(e.id);
      ref.invalidate(misEntradasProvider);
      if (mounted) {
        avisar(context, 'Entrada de ${e.cliente} anulada', tipo: TipoAviso.aviso);
      }
    } catch (err) {
      if (mounted) avisar(context, mensajeDeError(err), tipo: TipoAviso.aviso);
    }
  }

  @override
  Widget build(BuildContext context) {
    final ev = ref.watch(eventoActivoProvider);
    if (ev == null) {
      return const MensajeVista(
          icono: Icons.event_busy_rounded, titulo: 'No hay evento activo');
    }
    final entradas = ref.watch(misEntradasProvider);

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _cliente,
                  textCapitalization: TextCapitalization.words,
                  textInputAction: TextInputAction.done,
                  onSubmitted: (_) => _generar(ev),
                  decoration: const InputDecoration(
                    labelText: 'Nombre del cliente',
                  ),
                ),
              ),
              const SizedBox(width: 10),
              SizedBox(
                width: 118,
                child: FilledButton(
                  onPressed: _generando ? null : () => _generar(ev),
                  child: _generando
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2.2))
                      : const Text('Generar'),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: RefreshIndicator(
            onRefresh: () => ref.refresh(misEntradasProvider.future),
            child: VistaAsync(
              valor: entradas,
              reintentar: () => ref.invalidate(misEntradasProvider),
              datos: (lista) {
                if (lista.isEmpty) {
                  return ListView(children: const [
                    SizedBox(height: 80),
                    MensajeVista(
                      icono: Icons.qr_code_2_rounded,
                      titulo: 'Todavía no vendiste entradas',
                      detalle:
                          'Escribí el nombre del cliente y tocá Generar. El precio lo pone el evento.',
                    ),
                  ]);
                }
                final usadas = lista.where((e) => e.estado == 'usada').length;
                final validas = lista.where((e) => e.valida).length;
                return ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                  itemCount: lista.length + 1,
                  separatorBuilder: (_, _) => const SizedBox(height: 8),
                  itemBuilder: (context, i) {
                    if (i == 0) {
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 6),
                        child: Text(
                          '${lista.length} entradas · $usadas ingresaron · $validas sin usar',
                          style: const TextStyle(
                              color: VenueColors.textoSuave,
                              fontWeight: FontWeight.w600),
                        ),
                      );
                    }
                    final e = lista[i - 1];
                    final (texto, color) = switch (e.estado) {
                      'usada' => (
                          'ingresó ${e.usedAt == null ? '' : horaCorta(e.usedAt!)}',
                          VenueColors.ok
                        ),
                      'anulada' => ('anulada', VenueColors.mal),
                      _ => ('sin usar', VenueColors.textoSuave),
                    };
                    return Card(
                      clipBehavior: Clip.antiAlias,
                      child: ListTile(
                        onTap: e.estado == 'anulada'
                            ? null
                            : () => mostrarTicket(context, _ticket(e, ev)),
                        title: Text(e.cliente,
                            style: const TextStyle(fontWeight: FontWeight.w700)),
                        subtitle: Text('#${e.codigo} · ${e.precio} Bs · $texto',
                            style: TextStyle(color: color)),
                        trailing: e.valida
                            ? IconButton(
                                tooltip: 'Anular entrada',
                                icon: const Icon(Icons.block_rounded),
                                onPressed: () => _anular(e),
                              )
                            : null,
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ),
      ],
    );
  }
}
