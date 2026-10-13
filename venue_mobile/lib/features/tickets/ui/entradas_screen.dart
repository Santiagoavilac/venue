import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/networking/supabase.dart';
import '../../../core/theme/venue_theme.dart';
import '../../../core/widgets/avisos.dart';
import '../../../core/widgets/estado_vista.dart';
import '../../authentication/data/sesion.dart';
import '../../clubs/data/clubs.dart';
import '../../events/data/eventos.dart';
import '../../teams/data/equipo.dart';
import '../data/entradas.dart';
import 'ticket_sheet.dart';

enum _Alcance { mias, team, todas }

/// ¿Se puede vender ahora según la ventana? Devuelve el motivo si no.
String? motivoVentaCerrada(({DateTime? desde, DateTime? hasta}) v, DateTime ahora) {
  String f(DateTime t) =>
      '${t.day.toString().padLeft(2, '0')}/${t.month.toString().padLeft(2, '0')} ${horaCorta(t)}';
  if (v.desde != null && ahora.isBefore(v.desde!)) {
    return 'La venta abre el ${f(v.desde!)}';
  }
  if (v.hasta != null && ahora.isAfter(v.hasta!)) {
    return 'La venta cerró el ${f(v.hasta!)}';
  }
  return null;
}

/// Entradas prepagadas: generar, ver el QR, compartir (una o en tanda),
/// anular y eliminar. El relacionador ve las suyas; el jefe, además las de
/// su team; el admin, todas, con filtro por relacionador.
class EntradasScreen extends ConsumerStatefulWidget {
  const EntradasScreen({super.key});

  @override
  ConsumerState<EntradasScreen> createState() => _EntradasScreenState();
}

class _EntradasScreenState extends ConsumerState<EntradasScreen> {
  final _cliente = TextEditingController();
  bool _generando = false;
  _Alcance _alcance = _Alcance.mias;
  String _q = '';
  String? _vendedor;
  final _marcadas = <String>{};

  @override
  void dispose() {
    _cliente.dispose();
    super.dispose();
  }

  void _recargar() {
    ref.invalidate(entradasProvider);
    ref.invalidate(misEntradasProvider);
    ref.invalidate(faseVigenteProvider);
  }

  TicketDatos _ticket(Entrada e, Evento ev, Map<String, Fase> fases, Set<String> casa) {
    final club = ref.read(clubActivoProvider);
    final fase = fases[e.faseId];
    final artePropio = fase?.ticketUrl?.isNotEmpty ?? false;
    return TicketDatos(
      payload: payloadEntrada(ev.id, e.codigo),
      codigo: e.codigo,
      cliente: e.cliente,
      boliche: club?.nombre ?? '',
      evento: ev.nombre,
      fecha: ev.fechaCorta,
      tipo: fase?.nombre ?? 'Entrada prepagada',
      color: club?.primario,
      arteUrl: artePropio ? fase!.ticketUrl : ev.ticketUrl,
      // si la fase trae su propio arte, el sello sobra
      fase: artePropio ? null : fase?.nombre,
      oro: casa.contains(e.rrppId.isEmpty ? ref.read(usuarioIdProvider) : e.rrppId),
    );
  }

  Future<void> _generar(Evento ev, Map<String, Fase> fases, Set<String> casa) async {
    final nombre = _cliente.text.trim();
    if (nombre.length < 2 || _generando) return;
    setState(() => _generando = true);
    try {
      final e = await ref.read(entradasRepositoryProvider).generar(ev.id, nombre);
      _cliente.clear();
      _recargar();
      if (mounted) {
        FocusScope.of(context).unfocus();
        await mostrarTicket(context, _ticket(e, ev, fases, casa));
      }
    } catch (e) {
      if (mounted) avisar(context, mensajeDeError(e), tipo: TipoAviso.aviso);
    }
    if (mounted) setState(() => _generando = false);
  }

  Future<void> _accion(Entrada e, {required bool eliminar}) async {
    final si = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text('${eliminar ? 'Eliminar' : 'Anular'} la entrada de ${e.cliente}'),
        content: Text(eliminar
            ? 'La entrada #${e.codigo} se borra por completo. No se puede deshacer.'
            : 'El QR #${e.codigo} deja de servir en la puerta. No se puede deshacer.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(c, false), child: const Text('Cancelar')),
          TextButton(
            onPressed: () => Navigator.pop(c, true),
            style: TextButton.styleFrom(foregroundColor: VenueColors.mal),
            child: Text(eliminar ? 'Eliminar entrada' : 'Anular entrada'),
          ),
        ],
      ),
    );
    if (si != true) return;
    try {
      final repo = ref.read(entradasRepositoryProvider);
      eliminar ? await repo.eliminar(e.id) : await repo.anular(e.id);
      _marcadas.remove(e.id);
      _recargar();
      if (mounted) {
        avisar(context,
            'Entrada de ${e.cliente} ${eliminar ? 'eliminada' : 'anulada'}',
            tipo: TipoAviso.aviso);
      }
    } catch (err) {
      if (mounted) avisar(context, mensajeDeError(err), tipo: TipoAviso.aviso);
    }
  }

  @override
  Widget build(BuildContext context) {
    final ev = ref.watch(eventoActivoProvider);
    final rol = ref.watch(rolProvider).value;
    final yo = ref.watch(usuarioIdProvider);
    if (ev == null || rol == null || yo == null) {
      return const MensajeVista(
          icono: Icons.event_busy_rounded, titulo: 'No hay evento activo');
    }
    final veOtras = rol == Rol.admin || rol == Rol.jefe;
    final alcance = veOtras ? _alcance : _Alcance.mias;
    final entradas = alcance == _Alcance.mias
        ? ref.watch(misEntradasProvider)
        : ref.watch(entradasProvider);
    final equipo = ref.watch(equipoProvider).value ?? const <String, Miembro>{};
    final fases = {
      for (final f in ref.watch(fasesProvider).value ?? const <Fase>[]) f.id: f
    };
    final vigente = ref.watch(faseVigenteProvider).value;
    final casa = ref.watch(sinTopeProvider).value ?? const <String>{};
    final cerrada = motivoVentaCerrada(
        ref.watch(ventanaProvider).value ?? (desde: null, hasta: null),
        DateTime.now());
    final miTeam = equipo[yo]?.teamId;

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (cerrada != null)
                _Cartel(Icons.lock_clock_rounded, cerrada, VenueColors.aviso)
              else if (ev.ventaPorFases)
                _Cartel(
                  Icons.local_activity_rounded,
                  vigente == null
                      ? 'No hay ninguna fase de venta abierta'
                      : '${vigente.nombre} · ${vigente.precio} Bs'
                          '${vigente.quedan == null ? '' : ' · quedan ${vigente.quedan}'}',
                  vigente == null ? VenueColors.aviso : VenueColors.ok,
                ),
              Row(children: [
                Expanded(
                  child: TextField(
                    controller: _cliente,
                    enabled: cerrada == null,
                    textCapitalization: TextCapitalization.words,
                    textInputAction: TextInputAction.done,
                    onSubmitted: (_) => _generar(ev, fases, casa),
                    decoration:
                        const InputDecoration(labelText: 'Nombre del cliente'),
                  ),
                ),
                const SizedBox(width: 10),
                SizedBox(
                  width: 118,
                  child: FilledButton(
                    onPressed: _generando || cerrada != null
                        ? null
                        : () => _generar(ev, fases, casa),
                    child: _generando
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2.2))
                        : const Text('Generar'),
                  ),
                ),
              ]),
              if (veOtras) ...[
                const SizedBox(height: 10),
                SegmentedButton<_Alcance>(
                  showSelectedIcon: false,
                  segments: [
                    const ButtonSegment(value: _Alcance.mias, label: Text('Mías')),
                    if (miTeam != null)
                      const ButtonSegment(value: _Alcance.team, label: Text('Mi team')),
                    if (rol == Rol.admin)
                      const ButtonSegment(value: _Alcance.todas, label: Text('Todas')),
                  ],
                  selected: {alcance},
                  onSelectionChanged: (s) => setState(() {
                    _alcance = s.first;
                    _vendedor = null;
                    _marcadas.clear();
                  }),
                ),
              ],
              const SizedBox(height: 10),
              TextField(
                onChanged: (v) => setState(() => _q = v),
                autocorrect: false,
                decoration: const InputDecoration(
                  hintText: 'Buscar por cliente o código…',
                  prefixIcon: Icon(Icons.search_rounded),
                  isDense: true,
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: RefreshIndicator(
            onRefresh: () async {
              _recargar();
              await ref.read(misEntradasProvider.future);
            },
            child: VistaAsync(
              valor: entradas,
              reintentar: _recargar,
              datos: (todas) {
                var lista = todas;
                if (alcance == _Alcance.team) {
                  lista = lista.where((e) => equipo[e.rrppId]?.teamId == miTeam).toList();
                }
                final vendedores = {
                  for (final e in lista)
                    if (e.rrppNombre.isNotEmpty) e.rrppId: e.rrppNombre
                };
                if (_vendedor != null) {
                  lista = lista.where((e) => e.rrppId == _vendedor).toList();
                }
                final q = normalizar(_q.trim());
                if (q.isNotEmpty) {
                  lista = lista
                      .where((e) =>
                          normalizar(e.cliente).contains(q) ||
                          e.codigo.toLowerCase().contains(q))
                      .toList();
                }
                if (todas.isEmpty) {
                  return ListView(children: const [
                    SizedBox(height: 60),
                    MensajeVista(
                      icono: Icons.qr_code_2_rounded,
                      titulo: 'Todavía no hay entradas',
                      detalle:
                          'Escribí el nombre del cliente y tocá Generar. El precio lo pone el evento.',
                    ),
                  ]);
                }
                final usadas = lista.where((e) => e.estado == 'usada').length;
                final validas = lista.where((e) => e.valida).length;
                final total = lista
                    .where((e) => e.estado != 'anulada')
                    .fold<num>(0, (a, e) => a + e.precio);
                final marcadas =
                    lista.where((e) => _marcadas.contains(e.id)).toList();

                return ListView(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                  children: [
                    Text(
                      '${lista.length} entradas · $usadas ingresaron · $validas sin usar · $total Bs',
                      style: const TextStyle(
                          color: VenueColors.textoSuave, fontWeight: FontWeight.w600),
                    ),
                    if (alcance == _Alcance.todas && vendedores.length > 1) ...[
                      const SizedBox(height: 8),
                      DropdownButtonFormField<String?>(
                        initialValue: _vendedor,
                        isExpanded: true,
                        decoration: const InputDecoration(isDense: true),
                        items: [
                          const DropdownMenuItem<String?>(
                              value: null, child: Text('Todos los relacionadores')),
                          for (final v in (vendedores.entries.toList()
                            ..sort((a, b) => a.value.compareTo(b.value))))
                            DropdownMenuItem<String?>(value: v.key, child: Text(v.value)),
                        ],
                        onChanged: (v) => setState(() => _vendedor = v),
                      ),
                    ],
                    if (marcadas.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Row(children: [
                          Expanded(
                              child: Text('${marcadas.length} marcadas',
                                  style: const TextStyle(fontWeight: FontWeight.w700))),
                          TextButton(
                              onPressed: () => setState(_marcadas.clear),
                              child: const Text('Limpiar')),
                          FilledButton.icon(
                            style: FilledButton.styleFrom(
                                minimumSize: const Size(0, 44),
                                padding: const EdgeInsets.symmetric(horizontal: 14)),
                            onPressed: () async {
                              await compartirTanda(context, [
                                for (final e in marcadas) _ticket(e, ev, fases, casa)
                              ]);
                              if (mounted) setState(_marcadas.clear);
                            },
                            icon: const Icon(Icons.send_rounded, size: 18),
                            label: const Text('Enviar'),
                          ),
                        ]),
                      ),
                    const SizedBox(height: 8),
                    for (final e in lista)
                      _FilaEntrada(
                        entrada: e,
                        fase: fases[e.faseId]?.nombre,
                        vendedor: alcance == _Alcance.mias ? null : e.rrppNombre,
                        deLaCasa: casa.contains(e.rrppId),
                        marcada: _marcadas.contains(e.id),
                        alMarcar: e.valida
                            ? (v) => setState(() =>
                                v ? _marcadas.add(e.id) : _marcadas.remove(e.id))
                            : null,
                        alAbrir: e.estado == 'anulada'
                            ? null
                            : () => mostrarTicket(context, _ticket(e, ev, fases, casa)),
                        alAnular: e.valida ? () => _accion(e, eliminar: false) : null,
                        alEliminar: () => _accion(e, eliminar: true),
                      ),
                  ],
                );
              },
            ),
          ),
        ),
      ],
    );
  }
}

class _Cartel extends StatelessWidget {
  const _Cartel(this.icono, this.texto, this.color);
  final IconData icono;
  final String texto;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: color.withValues(alpha: .14),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(children: [
          Icon(icono, color: color, size: 20),
          const SizedBox(width: 10),
          Expanded(
              child: Text(texto,
                  style: TextStyle(color: color, fontWeight: FontWeight.w700))),
        ]),
      );
}

class _FilaEntrada extends StatelessWidget {
  const _FilaEntrada({
    required this.entrada,
    required this.fase,
    required this.vendedor,
    required this.deLaCasa,
    required this.marcada,
    required this.alMarcar,
    required this.alAbrir,
    required this.alAnular,
    required this.alEliminar,
  });

  final Entrada entrada;
  final String? fase;
  final String? vendedor;
  final bool deLaCasa;
  final bool marcada;
  final ValueChanged<bool>? alMarcar;
  final VoidCallback? alAbrir;
  final VoidCallback? alAnular;
  final VoidCallback alEliminar;

  @override
  Widget build(BuildContext context) {
    final e = entrada;
    final (texto, color) = switch (e.estado) {
      'usada' => (
          'ingresó${e.usedAt == null ? '' : ' ${horaCorta(e.usedAt!)}'}',
          VenueColors.ok
        ),
      'anulada' => ('anulada', VenueColors.mal),
      _ => ('sin usar', VenueColors.textoSuave),
    };
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Container(
        decoration: BoxDecoration(
          color: VenueColors.superficie,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
              color: deLaCasa ? const Color(0xFFE8B530) : VenueColors.linea),
        ),
        child: Row(children: [
          if (alMarcar != null)
            Checkbox(value: marcada, onChanged: (v) => alMarcar!(v ?? false))
          else
            const SizedBox(width: 14),
          Expanded(
            child: InkWell(
              onTap: alAbrir,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(e.cliente,
                        style: const TextStyle(
                            fontSize: 16, fontWeight: FontWeight.w700)),
                    Text(
                      [
                        '#${e.codigo}',
                        '${e.precio} Bs',
                        ?fase,
                        if (deLaCasa) 'de la casa',
                        if (e.filtrada) 'no pasó filtro',
                        texto,
                      ].join(' · '),
                      style: TextStyle(color: color, fontSize: 12.5),
                    ),
                    if (vendedor != null && vendedor!.isNotEmpty)
                      Text('la vendió $vendedor',
                          style: const TextStyle(
                              color: VenueColors.textoSuave, fontSize: 12.5)),
                  ],
                ),
              ),
            ),
          ),
          PopupMenuButton<String>(
            tooltip: 'Acciones',
            onSelected: (v) => v == 'anular' ? alAnular?.call() : alEliminar(),
            itemBuilder: (_) => [
              if (alAnular != null)
                const PopupMenuItem(value: 'anular', child: Text('Anular entrada')),
              const PopupMenuItem(value: 'eliminar', child: Text('Eliminar entrada')),
            ],
          ),
        ]),
      ),
    );
  }
}
