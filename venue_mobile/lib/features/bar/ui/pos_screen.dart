import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/networking/supabase.dart';
import '../../../core/sync/cola_offline.dart';
import '../../../core/theme/venue_theme.dart';
import '../../../core/widgets/avisos.dart';
import '../../../core/widgets/estado_vista.dart';
import '../../clubs/data/clubs.dart';
import '../../events/data/eventos.dart';
import '../data/barra.dart';

/// Punto de venta de la barra.
///
/// Pensado para servir rápido: la carta son botones grandes, un toque suma
/// un vaso, y cobrar es un botón. El bartender ve precio de venta y para
/// cuántos vasos alcanza; nunca el costo.
class PosScreen extends ConsumerStatefulWidget {
  const PosScreen({super.key});
  @override
  ConsumerState<PosScreen> createState() => _PosScreenState();
}

class _PosScreenState extends ConsumerState<PosScreen> {
  final _carrito = Carrito();
  List<Fila>? _barras;
  String? _barra;
  List<TragoCarta> _carta = const [];
  Object? _error;
  bool _cargando = true, _cobrando = false;
  Fila? _cortesia; // a nombre de quién va la cortesía
  String? _eventoCargado;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _cargar());
  }

  Future<void> _cargar() async {
    final ev = ref.read(eventoActivoProvider);
    final club = ref.read(clubActivoIdProvider);
    final rol = ref.read(rolProvider).value;
    if (ev == null || club == null) return;
    setState(() {
      _cargando = true;
      _error = null;
    });
    try {
      final repo = ref.read(barraRepositoryProvider);
      final barras = await repo.misBarras(club, ev.id, soloAsignadas: rol == Rol.barra);
      final barra = barras.any((b) => b['id'] == _barra)
          ? _barra
          : (barras.isEmpty ? null : barras.first['id'] as String);
      final carta = barra == null ? const <TragoCarta>[] : await repo.carta(club, barra);
      if (!mounted) return;
      setState(() {
        _barras = barras;
        _barra = barra;
        _carta = carta;
        _cargando = false;
        _eventoCargado = ev.id;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e;
          _cargando = false;
        });
      }
    }
  }

  Future<void> _cobrar(String forma) async {
    final ev = ref.read(eventoActivoProvider);
    if (ev == null || _barra == null || _carrito.vacio || _cobrando) return;
    final total = _carrito.total(_carta), vasos = _carrito.vasos;
    final args = BarraRepository.argsDeVenta(
      eventoId: ev.id, barraId: _barra!, items: _carrito.items(),
      cortesiaDe: _cortesia?['user_id'] as String?, forma: forma, clave: nuevoId(),
    );
    setState(() => _cobrando = true);
    try {
      final r = await venderTolerante(ref, args, 'Venta de $vasos vaso(s) · $total Bs');
      if (!mounted) return;
      HapticFeedback.mediumImpact();
      setState(() {
        _carrito.vaciar();
        _cortesia = null;
      });
      avisar(
        context,
        r.encolada
            ? 'Sin señal: la venta quedó guardada y se envía sola'
            : args['p_forma_pago'] == 'cortesia'
                ? 'Cortesía registrada · $vasos vaso(s)'
                : 'Cobrado $total Bs · $forma',
        tipo: r.encolada ? TipoAviso.aviso : TipoAviso.ok,
      );
      if (!r.encolada) _cargar();
    } catch (e) {
      if (!mounted) return;
      HapticFeedback.heavyImpact();
      avisar(context, mensajeDeError(e), tipo: TipoAviso.aviso);
      // "no hay stock": otro vendió lo que quedaba; se refresca la carta
      _cargar();
    }
    if (mounted) setState(() => _cobrando = false);
  }

  Future<void> _anularUltima() async {
    final ev = ref.read(eventoActivoProvider);
    if (ev == null) return;
    final repo = ref.read(barraRepositoryProvider);
    try {
      final u = await repo.ultimaVentaMia(ev.id);
      if (!mounted) return;
      if (u == null) {
        avisar(context, 'No tenés ventas para anular', tipo: TipoAviso.aviso);
        return;
      }
      final t = DateTime.parse(u['created_at'] as String).toLocal();
      final si = await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
          title: const Text('Anular la última venta'),
          content: Text(
              '${u['total']} Bs · ${u['estado']} · ${horaCorta(t)}\n\nEl stock vuelve al inventario y la anulación queda registrada a tu nombre.'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancelar')),
            TextButton(
                onPressed: () => Navigator.pop(c, true),
                style: TextButton.styleFrom(foregroundColor: VenueColors.mal),
                child: const Text('Anular venta')),
          ],
        ),
      );
      if (si != true) return;
      await repo.anular(u['id'] as String, 'Anulada en barra');
      if (mounted) avisar(context, 'Venta anulada', tipo: TipoAviso.aviso);
      _cargar();
    } catch (e) {
      if (mounted) avisar(context, mensajeDeError(e), tipo: TipoAviso.aviso);
    }
  }

  Future<void> _elegirCortesia() async {
    final ev = ref.read(eventoActivoProvider);
    if (ev == null) return;
    try {
      final l = await ref.read(barraRepositoryProvider).cortesias(ev.id);
      if (!mounted) return;
      final x = await showModalBottomSheet<Fila>(
        context: context,
        showDragHandle: true,
        backgroundColor: VenueColors.superficie,
        builder: (c) => SafeArea(
          child: ListView(shrinkWrap: true, children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: Text('Cortesía a nombre de…',
                  style: TextStyle(fontSize: 19, fontWeight: FontWeight.w800)),
            ),
            if (l.isEmpty)
              const Padding(
                  padding: EdgeInsets.all(20),
                  child: Text('Nadie tiene cupo de cortesías en este evento.')),
            for (final p in l)
              ListTile(
                title: Text('${p['nombre']}'),
                subtitle: Text(
                    '${p['team'] ?? ''} · usó ${p['usados'] ?? 0} de ${p['cupo'] ?? 0}'),
                enabled: ((p['cupo'] as num? ?? 0) - (p['usados'] as num? ?? 0)) > 0,
                onTap: () => Navigator.pop(c, p),
              ),
          ]),
        ),
      );
      if (x != null && mounted) setState(() => _cortesia = x);
    } catch (e) {
      if (mounted) avisar(context, mensajeDeError(e), tipo: TipoAviso.aviso);
    }
  }

  @override
  Widget build(BuildContext context) {
    final ev = ref.watch(eventoActivoProvider);
    if (ev == null) {
      return const MensajeVista(
          icono: Icons.event_busy_rounded,
          titulo: 'No hay ningún evento abierto en este boliche');
    }
    // cambió el evento de trabajo: la carta y las barras son otras
    if (_eventoCargado != null && _eventoCargado != ev.id && !_cargando) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _cargar());
    }
    if (_error != null) {
      return MensajeVista(
        icono: esFallaDeRed(_error!) ? Icons.wifi_off_rounded : Icons.error_outline,
        titulo: 'No se pudo cargar la carta',
        detalle: mensajeDeError(_error!),
        accion: 'Reintentar',
        alTocar: _cargar,
      );
    }
    if (_barras == null) return const Center(child: CircularProgressIndicator());
    if (_barras!.isEmpty) {
      return const MensajeVista(
        icono: Icons.local_bar_outlined,
        titulo: 'No tenés una barra asignada',
        detalle: 'El propietario te asigna en Turno antes de abrir.',
      );
    }
    final total = _carrito.total(_carta);
    final marca = Theme.of(context).colorScheme.primary;

    return Column(children: [
      if (_barras!.length > 1)
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: SegmentedButton<String>(
            showSelectedIcon: false,
            segments: [
              for (final b in _barras!)
                ButtonSegment(value: b['id'] as String, label: Text('${b['nombre']}')),
            ],
            selected: {_barra!},
            onSelectionChanged: (s) {
              setState(() {
                _barra = s.first;
                _carrito.vaciar();
              });
              _cargar();
            },
          ),
        ),
      Expanded(
        child: RefreshIndicator(
          onRefresh: _cargar,
          child: _carta.isEmpty
              ? ListView(children: const [
                  SizedBox(height: 80),
                  MensajeVista(
                    icono: Icons.no_drinks_outlined,
                    titulo: 'La carta está vacía',
                    detalle: 'El propietario tiene que cargar tragos con su receta y activarlos.',
                  ),
                ])
              : GridView.builder(
                  padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
                  gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                      maxCrossAxisExtent: 200, mainAxisExtent: 112,
                      crossAxisSpacing: 10, mainAxisSpacing: 10),
                  itemCount: _carta.length,
                  itemBuilder: (context, i) {
                    final t = _carta[i];
                    final n = _carrito.de(t.id);
                    final sinStock = t.alcanzaPara <= 0;
                    return Material(
                      color: n > 0 ? marca.withValues(alpha: .22) : VenueColors.superficie,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                        side: BorderSide(color: n > 0 ? marca : VenueColors.linea, width: n > 0 ? 2 : 1),
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: InkWell(
                        onTap: sinStock
                            ? null
                            : () {
                                if (_carrito.sumar(t)) {
                                  HapticFeedback.selectionClick();
                                  setState(() {});
                                } else {
                                  avisar(context, 'No alcanza el stock para más ${t.nombre}',
                                      tipo: TipoAviso.aviso);
                                }
                              },
                        onLongPress: n > 0 ? () => setState(() => _carrito.restar(t.id)) : null,
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                child: Text(t.nombre,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                        fontSize: 16, fontWeight: FontWeight.w800, height: 1.15,
                                        color: sinStock ? VenueColors.textoSuave : null)),
                              ),
                              Row(children: [
                                Text('${t.precio} Bs',
                                    style: const TextStyle(fontWeight: FontWeight.w700)),
                                const Spacer(),
                                if (n > 0)
                                  CircleAvatar(
                                      radius: 14,
                                      backgroundColor: marca,
                                      child: Text('$n',
                                          style: TextStyle(
                                              color: Theme.of(context).colorScheme.onPrimary,
                                              fontWeight: FontWeight.w800)))
                                else
                                  Text(sinStock ? 'sin stock' : 'quedan ${t.alcanzaPara}',
                                      style: TextStyle(
                                          fontSize: 12,
                                          color: sinStock || t.alcanzaPara <= 5
                                              ? VenueColors.aviso
                                              : VenueColors.textoSuave)),
                              ]),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
        ),
      ),
      // pie fijo: total, cobrar y lo que casi nunca se usa
      Container(
        padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
        decoration: const BoxDecoration(
            color: VenueColors.superficie,
            border: Border(top: BorderSide(color: VenueColors.linea))),
        child: Column(children: [
          if (_cortesia != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(children: [
                const Icon(Icons.card_giftcard_rounded, size: 18, color: VenueColors.aviso),
                const SizedBox(width: 8),
                Expanded(
                    child: Text('Cortesía a nombre de ${_cortesia!['nombre']}',
                        style: const TextStyle(color: VenueColors.aviso, fontWeight: FontWeight.w700))),
                TextButton(onPressed: () => setState(() => _cortesia = null), child: const Text('Quitar')),
              ]),
            ),
          Row(children: [
            Expanded(
              child: Text(
                _carrito.vacio ? 'Tocá un trago' : '${_carrito.vasos} vaso(s)',
                style: const TextStyle(color: VenueColors.textoSuave),
              ),
            ),
            Text(_cortesia != null ? '0 Bs' : '$total Bs',
                style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w900)),
          ]),
          const SizedBox(height: 8),
          if (_cortesia != null)
            FilledButton(
              onPressed: _carrito.vacio || _cobrando ? null : () => _cobrar('cortesia'),
              child: const Text('Registrar cortesía'),
            )
          else
            Row(children: [
              Expanded(
                flex: 3,
                child: FilledButton(
                  onPressed: _carrito.vacio || _cobrando ? null : () => _cobrar('efectivo'),
                  child: _cobrando
                      ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2.2))
                      : const Text('Efectivo'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                flex: 2,
                child: OutlinedButton(
                  onPressed: _carrito.vacio || _cobrando ? null : () => _cobrar('qr'),
                  child: const Text('QR'),
                ),
              ),
              PopupMenuButton<String>(
                tooltip: 'Más',
                onSelected: (k) => switch (k) {
                  'cortesia' => _elegirCortesia(),
                  'vaciar' => setState(_carrito.vaciar),
                  _ => _anularUltima(),
                },
                itemBuilder: (_) => const [
                  PopupMenuItem(value: 'cortesia', child: Text('Cortesía')),
                  PopupMenuItem(value: 'vaciar', child: Text('Vaciar pedido')),
                  PopupMenuItem(value: 'anular', child: Text('Anular la última venta')),
                ],
              ),
            ]),
        ]),
      ),
    ]);
  }
}
