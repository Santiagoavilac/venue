import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/networking/supabase.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/theme/venue_theme.dart';
import '../../../core/widgets/avisos.dart';
import '../../../core/widgets/esqueleto.dart';
import '../../../core/widgets/estado_vista.dart';
import '../../../core/widgets/insignia.dart';
import '../../../core/widgets/patron.dart';
import '../../dashboard/ui/tutorial.dart';
import '../data/incidencias.dart';

/// El WhatsApp de soporte de AFTR, el mismo que ve la persona en la app.
const _soporte = '59175028040';

/// Cobros que entraron y no entregaron nada.
///
/// Antes esto se resolvía con SQL a mano y nadie se enteraba: el cobro quedaba
/// en `revisar` y la persona veía un QR esperando para siempre. Acá está quién
/// pagó, cuánto, cuándo, qué dijo el banco, y las tres salidas posibles.
class IncidenciasScreen extends ConsumerStatefulWidget {
  const IncidenciasScreen({super.key});

  @override
  ConsumerState<IncidenciasScreen> createState() => _IncidenciasState();
}

class _IncidenciasState extends ConsumerState<IncidenciasScreen> {
  String _estado = 'abierta';

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(incidenciasProvider(_estado));
    final datos = async.value;

    return GuiaDePantalla(
      guia: 'incidencias',
      pasos: () => [
        PasoTutorial(
          icono: Icons.error_outline_rounded,
          titulo: 'Plata que entró y no entregó nada',
          texto:
              'El QR del banco se cobra hasta diez minutos después de generarse. '
              'Si la plata llega más tarde, el cupo ya volvió al evento, así que '
              'el sistema no emite la entrada: la deja acá para que vos decidas.',
          objetivo: () => null,
        ),
        PasoTutorial(
          icono: Icons.done_all_rounded,
          titulo: 'Tres salidas',
          texto:
              'Emitir la entrada si todavía hay lugar, devolver la plata por el '
              'banco, o cerrar el caso si ya se resolvió por fuera. Siempre con '
              'una nota, que queda con tu nombre.',
          objetivo: () => null,
        ),
      ],
      child: Column(
        children: [
          Encabezado(
            etiqueta: 'AFTR',
            titulo: 'Cobros a resolver',
            contexto: datos == null
                ? null
                : datos.abiertas == 0
                ? 'Nada pendiente'
                : '${datos.abiertas} esperando',
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: Esp.lg),
            child: SegmentedButton<String>(
              showSelectedIcon: false,
              segments: const [
                ButtonSegment(value: 'abierta', label: Text('Pendientes')),
                ButtonSegment(value: 'resuelta', label: Text('Resueltos')),
                ButtonSegment(value: 'todas', label: Text('Todos')),
              ],
              selected: {_estado},
              onSelectionChanged: (s) => setState(() => _estado = s.first),
            ),
          ),
          Expanded(
            child: RefreshIndicator(
              onRefresh: () => ref.refresh(incidenciasProvider(_estado).future),
              child: switch (async) {
                AsyncValue(hasError: true, :final error) => ListView(
                  padding: const EdgeInsets.all(Esp.lg),
                  children: [BloqueVacio('No se pudo cargar', mensajeDeError(error!))],
                ),
                AsyncValue(value: null) => const EsqueletoLista(filas: 3, conFoto: false),
                AsyncValue(:final value?) when value.lista.isEmpty => ListView(
                  padding: const EdgeInsets.all(Esp.lg),
                  children: [
                    BloqueVacio(
                      _estado == 'abierta' ? 'Ningún cobro pendiente' : 'Nada por acá',
                      _estado == 'abierta'
                          ? 'Cuando a alguien se le cobre y no reciba su entrada, '
                                'aparece acá con el monto y el comprobante del banco.'
                          : 'Los casos resueltos quedan con la nota de quien los cerró.',
                    ),
                  ],
                ),
                AsyncValue(:final value?) => ListView.separated(
                  padding: const EdgeInsets.fromLTRB(Esp.lg, Esp.sm, Esp.lg, Esp.xl),
                  itemCount: value.lista.length,
                  separatorBuilder: (_, _) => const SizedBox(height: Esp.sm),
                  itemBuilder: (_, i) => _Fila(value.lista[i], estado: _estado),
                ),
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _Fila extends ConsumerStatefulWidget {
  const _Fila(this.i, {required this.estado});
  final Incidencia i;
  final String estado;

  @override
  ConsumerState<_Fila> createState() => _FilaState();
}

class _FilaState extends ConsumerState<_Fila> {
  bool _ocupado = false;

  Future<void> _resolver(String accion, String comoSeLlama) async {
    final nota = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(comoSeLlama),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              switch (accion) {
                'emitir' =>
                  'Se emite la entrada igual, aunque el pago llegó tarde. '
                      'Hacelo solo si todavía hay lugar en el evento.',
                'devolver' =>
                  'La devolución se hace en el banco: acá queda escrito que la '
                      'hiciste, con tu nombre y la fecha.',
                _ =>
                  'El caso se cierra sin emitir ni devolver. Contá por qué, para '
                      'que mañana se entienda.',
              },
              style: Tipo.cuerpo,
            ),
            const SizedBox(height: Esp.md),
            TextField(
              controller: nota,
              minLines: 2,
              maxLines: 4,
              maxLength: 500,
              decoration: const InputDecoration(labelText: 'Qué se hizo'),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Volver')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: Text(comoSeLlama)),
        ],
      ),
    );
    final texto = nota.text.trim();
    // El diálogo termina su animación antes de que se libere el controlador.
    Future<void>.delayed(const Duration(seconds: 1), nota.dispose);
    if (ok != true || !mounted) return;
    if (texto.length < 5) {
      avisar(context, 'Escribí qué se hizo', tipo: TipoAviso.aviso);
      return;
    }
    setState(() => _ocupado = true);
    try {
      final n = await ref
          .read(incidenciasRepositoryProvider)
          .resolver(widget.i.id, accion, texto);
      ref.invalidate(incidenciasProvider(widget.estado));
      ref.invalidate(incidenciasProvider('abierta'));
      if (mounted) {
        avisar(
          context,
          n > 0 ? 'Listo: $n entrada${n == 1 ? '' : 's'} emitida${n == 1 ? '' : 's'}' : 'Caso cerrado',
        );
      }
    } catch (e) {
      if (mounted) avisar(context, mensajeDeError(e), tipo: TipoAviso.aviso);
    } finally {
      if (mounted) setState(() => _ocupado = false);
    }
  }

  Future<void> _escribirle() async {
    final i = widget.i;
    final texto = Uri.encodeComponent(
      'Hola ${i.cliente ?? ''}, soy del boliche. Vimos que pagaste Bs ${i.monto} '
      '${i.evento == null ? '' : 'para ${i.evento} '}y no recibiste tu entrada. '
      'Lo estamos resolviendo.',
    );
    await launchUrl(
      Uri.parse('https://wa.me/?text=$texto'),
      mode: LaunchMode.externalApplication,
    );
  }

  @override
  Widget build(BuildContext context) {
    final i = widget.i;
    return Tarjeta(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '${i.monto} Bs · ${i.cliente ?? 'sin perfil'}',
                  style: Tipo.fila,
                ),
              ),
              Insignia(
                i.abierta ? (i.tarde ? 'Llegó tarde' : 'Sin emitir') : 'Resuelto',
                tono: i.abierta ? Tono.mal : Tono.ok,
              ),
            ],
          ),
          const SizedBox(height: Esp.xs),
          Text(
            [
              if (i.usuario != null) '@${i.usuario}',
              if (i.evento != null) i.evento!,
              if (i.cantidad != null) '${i.cantidad} entrada${i.cantidad == 1 ? '' : 's'}',
              '${i.creado.day}/${i.creado.month} ${horaCorta(i.creado)}',
            ].join(' · '),
            style: Tipo.apoyo,
          ),
          const SizedBox(height: Esp.sm),
          Text(i.detalle, style: Tipo.cuerpo),
          if (i.bancoTx != null) ...[
            const SizedBox(height: Esp.xs),
            SelectableText(
              'Transacción del banco: ${i.bancoTx}',
              style: Tipo.apoyo.copyWith(color: VenueColors.textoTenue),
            ),
          ],
          if (i.resolucion != null) ...[
            const SizedBox(height: Esp.sm),
            Text(i.resolucion!, style: Tipo.apoyo.copyWith(color: VenueColors.ok)),
          ],
          if (i.abierta) ...[
            const SizedBox(height: Esp.md),
            if (_ocupado)
              const LinearProgressIndicator()
            else
              Wrap(
                spacing: Esp.sm,
                runSpacing: Esp.xs,
                children: [
                  if (i.puedeEmitir)
                    FilledButton.tonalIcon(
                      onPressed: () => _resolver('emitir', 'Emitir la entrada'),
                      icon: const Icon(Icons.confirmation_number_outlined, size: 18),
                      label: const Text('Emitir'),
                    ),
                  OutlinedButton.icon(
                    onPressed: () => _resolver('devolver', 'Marcar como devuelto'),
                    icon: const Icon(Icons.undo_rounded, size: 18),
                    label: const Text('Devolví la plata'),
                  ),
                  TextButton(
                    onPressed: () => _resolver('cerrar', 'Cerrar el caso'),
                    child: const Text('Cerrar'),
                  ),
                  TextButton.icon(
                    onPressed: _escribirle,
                    icon: const Icon(Icons.chat_bubble_outline_rounded, size: 18),
                    label: const Text('Escribirle'),
                  ),
                ],
              ),
            const SizedBox(height: Esp.xs),
            Text(
              'La persona ve en su app que el pago llegó tarde y tiene el WhatsApp '
              'de soporte de AFTR ($_soporte).',
              style: Tipo.apoyo.copyWith(color: VenueColors.textoTenue),
            ),
          ],
        ],
      ),
    );
  }
}
