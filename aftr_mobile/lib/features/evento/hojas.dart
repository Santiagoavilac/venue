import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/networking/supabase.dart';
import '../../core/theme/aftr_theme.dart';
import '../../core/widgets/listo.dart';
import '../../core/widgets/movimiento.dart';
import '../../core/widgets/piezas.dart';
import '../../data/aftr_repo.dart';
import '../../data/modelos.dart';

Future<void> _hoja(BuildContext context, Widget hijo) => showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useRootNavigator: true,
      builder: (_) => hijo,
    );

/// El paso de pago. Hoy hay uno solo: el boliche confirma el pedido desde
/// Venue y ahí aparecen los QR. Cuando haya pasarela, es otra variante acá.
class PasoPago extends StatelessWidget {
  const PasoPago({super.key});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(color: Aftr.superficie2, borderRadius: BorderRadius.circular(16)),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Icon(Icons.verified_outlined, color: Aftr.acento, size: 22),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'El boliche confirma tu pedido y tus QR aparecen en Accesos. Te avisamos ahí mismo.',
              style: Aftr.cuerpo(14, c: Aftr.texto),
            ),
          ),
        ]),
      );
}

/// Número que cambia con un deslizamiento vertical.
class NumeroAnimado extends StatelessWidget {
  const NumeroAnimado(this.texto, {super.key, required this.estilo});

  final String texto;
  final TextStyle estilo;

  @override
  Widget build(BuildContext context) => AnimatedSwitcher(
        duration: Aftr.rapido,
        transitionBuilder: (c, a) => FadeTransition(
          opacity: a,
          child: SlideTransition(position: Tween(begin: const Offset(0, 0.4), end: Offset.zero).animate(a), child: c),
        ),
        child: Text(texto, key: ValueKey(texto), style: estilo),
      );
}

// ── comprar entradas ───────────────────────────────────────────────────

Future<void> abrirCompra(BuildContext context, EventoDetalle d, Fase? fase) =>
    _hoja(context, _Compra(d: d, fase: fase));

class _Compra extends ConsumerStatefulWidget {
  const _Compra({required this.d, this.fase});

  final EventoDetalle d;
  final Fase? fase;

  @override
  ConsumerState<_Compra> createState() => _CompraState();
}

class _CompraState extends ConsumerState<_Compra> {
  int _n = 1;
  bool _enviando = false;
  bool _listo = false;

  int get _precio => widget.fase?.precio ?? widget.d.precio;
  int get _max => (widget.fase?.quedan ?? 10).clamp(1, 10);

  Future<void> _confirmar() async {
    setState(() => _enviando = true);
    try {
      await ref.read(repoProvider).comprar(widget.d.evento.id, widget.fase?.id, _n);
      ref.invalidate(accesosProvider);
      ref.invalidate(eventoProvider(widget.d.evento.id));
      if (mounted) setState(() => _listo = true);
    } catch (e) {
      if (mounted) avisar(context, mensajeDeError(e));
    } finally {
      if (mounted) setState(() => _enviando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_listo) {
      return HojaListo(
        titulo: 'Pedido enviado',
        texto: '${widget.d.evento.club.nombre} lo confirma y tus $_n ${_n == 1 ? 'entrada aparece' : 'entradas aparecen'} en Accesos.',
        accion: 'Ver en Accesos',
        onAccion: () {
          Navigator.of(context).pop();
          context.go('/accesos');
        },
        onCerrar: () => Navigator.of(context).pop(),
      );
    }
    final e = widget.d.evento;
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 0, 20, 16 + MediaQuery.paddingOf(context).bottom),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Manija(),
        const SizedBox(height: 10),
        Text(e.nombre, style: Aftr.fuerte(22)),
        const SizedBox(height: 4),
        Text('${e.club.nombre} · ${fechaCorta(e.fecha)} · ${e.horaInicio}', style: Aftr.cuerpo(14)),
        const SizedBox(height: 22),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(border: Border.all(color: Aftr.borde), borderRadius: BorderRadius.circular(18)),
          child: Row(children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(widget.fase?.nombre ?? 'Entrada general', style: Aftr.fuerte(16)),
                const SizedBox(height: 2),
                Text('${bs(_precio)} c/u', style: Aftr.cuerpo(14)),
              ]),
            ),
            _Paso(icono: Icons.remove_rounded, onTap: _n > 1 ? () => setState(() => _n--) : null),
            SizedBox(width: 40, child: Center(child: NumeroAnimado('$_n', estilo: Aftr.fuerte(20)))),
            _Paso(icono: Icons.add_rounded, onTap: _n < _max ? () => setState(() => _n++) : null),
          ]),
        ),
        const SizedBox(height: 14),
        const PasoPago(),
        const SizedBox(height: 22),
        Row(children: [
          Text('Total', style: Aftr.cuerpo(16, c: Aftr.texto)),
          const Spacer(),
          NumeroAnimado(bs(_precio * _n), estilo: Aftr.fuerte(24)),
        ]),
        const SizedBox(height: 16),
        BotonAftr('Confirmar pedido', cargando: _enviando, onTap: _confirmar),
      ]),
    );
  }
}

class _Paso extends StatelessWidget {
  const _Paso({required this.icono, this.onTap});

  final IconData icono;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => Presionable(
        onTap: onTap,
        child: AnimatedOpacity(
          duration: Aftr.rapido,
          opacity: onTap == null ? 0.3 : 1,
          child: Container(
            width: 38,
            height: 38,
            decoration: const BoxDecoration(color: Aftr.superficie3, shape: BoxShape.circle),
            child: Icon(icono, color: Aftr.texto, size: 20),
          ),
        ),
      );
}

// ── reservar mesa ──────────────────────────────────────────────────────

Future<void> abrirMesa(BuildContext context, EventoDetalle d) => _hoja(context, _ReservaMesa(d: d));

class _ReservaMesa extends ConsumerStatefulWidget {
  const _ReservaMesa({required this.d});

  final EventoDetalle d;

  @override
  ConsumerState<_ReservaMesa> createState() => _ReservaMesaState();
}

class _ReservaMesaState extends ConsumerState<_ReservaMesa> {
  Mesa? _mesa;
  Combo? _combo;
  bool _enviando = false;
  bool _listo = false;

  List<Combo> get _combos => _mesa == null ? const [] : widget.d.combos.where((c) => c.sirvePara(_mesa!)).toList();

  bool get _puede => _mesa != null && (_combo != null || (!widget.d.comboObligatorio && _combos.isEmpty));

  Future<void> _confirmar() async {
    setState(() => _enviando = true);
    try {
      await ref.read(repoProvider).reservarMesa(widget.d.evento.id, _mesa!.id, _combo?.id);
      ref.invalidate(accesosProvider);
      ref.invalidate(eventoProvider(widget.d.evento.id));
      if (mounted) setState(() => _listo = true);
    } catch (e) {
      if (mounted) avisar(context, mensajeDeError(e));
    } finally {
      if (mounted) setState(() => _enviando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_listo) {
      return HojaListo(
        titulo: 'Mesa ${_mesa!.etiqueta} reservada',
        texto: 'La guardamos para vos mientras ${widget.d.evento.club.nombre} confirma. Las manillas llegan a Accesos.',
        accion: 'Ver en Accesos',
        onAccion: () {
          Navigator.of(context).pop();
          context.go('/accesos');
        },
        onCerrar: () => Navigator.of(context).pop(),
      );
    }
    final porCategoria = <String, List<Mesa>>{};
    for (final m in widget.d.mesas) {
      (porCategoria[m.categoria.isEmpty ? 'Mesas' : m.categoria] ??= []).add(m);
    }
    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.86),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        const Manija(),
        Flexible(
          child: ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.fromLTRB(20, 10, 20, 10),
            children: [
              Text('Reservá una mesa', style: Aftr.fuerte(22)),
              const SizedBox(height: 4),
              Text('${widget.d.mesas.length} disponibles · ${widget.d.evento.club.nombre}', style: Aftr.cuerpo(14)),
              for (final cat in porCategoria.entries) ...[
                const SizedBox(height: 22),
                Text(cat.key.toUpperCase(), style: Aftr.etiqueta()),
                const SizedBox(height: 10),
                Wrap(spacing: 8, runSpacing: 8, children: [
                  for (final m in cat.value)
                    Pildora(m.etiqueta, activa: _mesa?.id == m.id, onTap: () => setState(() {
                          _mesa = m;
                          if (_combo != null && !_combo!.sirvePara(m)) _combo = null;
                        })),
                ]),
              ],
              AnimatedSize(
                duration: Aftr.medio,
                curve: Aftr.curva,
                child: _mesa == null || _combos.isEmpty
                    ? const SizedBox(width: double.infinity)
                    : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        const SizedBox(height: 26),
                        Text('ELEGÍ TU COMBO', style: Aftr.etiqueta()),
                        const SizedBox(height: 10),
                        for (final c in _combos) _FilaCombo(c, elegido: _combo?.id == c.id, onTap: () => setState(() => _combo = c)),
                      ]),
              ),
            ],
          ),
        ),
        Padding(
          padding: EdgeInsets.fromLTRB(20, 6, 20, 16 + MediaQuery.paddingOf(context).bottom),
          child: Column(children: [
            const PasoPago(),
            const SizedBox(height: 14),
            Row(children: [
              Text(_mesa == null ? 'Elegí una mesa' : 'Mesa ${_mesa!.etiqueta}', style: Aftr.cuerpo(16, c: Aftr.texto)),
              const Spacer(),
              NumeroAnimado(_combo == null ? '' : bs(_combo!.precio), estilo: Aftr.fuerte(22)),
            ]),
            const SizedBox(height: 14),
            BotonAftr('Reservar', cargando: _enviando, onTap: _puede ? _confirmar : null),
          ]),
        ),
      ]),
    );
  }
}

class _FilaCombo extends StatelessWidget {
  const _FilaCombo(this.c, {required this.elegido, required this.onTap});

  final Combo c;
  final bool elegido;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Presionable(
        onTap: onTap,
        child: AnimatedContainer(
          duration: Aftr.medio,
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: elegido ? Aftr.superficie3 : Aftr.superficie2,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: elegido ? Aftr.texto : Aftr.borde, width: elegido ? 1.5 : 1),
          ),
          child: Row(children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(c.nombre, style: Aftr.fuerte(16)),
                if (c.productos.isNotEmpty || c.descripcion != null) ...[
                  const SizedBox(height: 4),
                  Text(c.productos.isNotEmpty ? c.productos.join(' · ') : c.descripcion!, style: Aftr.cuerpo(13)),
                ],
                if (c.manillas > 0) ...[
                  const SizedBox(height: 4),
                  Text('Incluye ${c.manillas} manillas', style: Aftr.cuerpo(13, c: Aftr.acento)),
                ],
              ]),
            ),
            Text(bs(c.precio), style: Aftr.fuerte(17)),
          ]),
        ),
      );
}

// ── lista ──────────────────────────────────────────────────────────────

Future<void> abrirListaConfirmada(BuildContext context, Lista l) => _hoja(
      context,
      Builder(
        builder: (ctx) => HojaListo(
          titulo: 'Estás en la lista',
          texto: '${l.nombre}${l.hasta != null ? ' · entrás hasta las ${l.hasta}' : ''}. Tu QR ya está en Accesos.',
          accion: 'Ver mi QR',
          onAccion: () {
            Navigator.of(ctx).pop();
            ctx.go('/accesos');
          },
          onCerrar: () => Navigator.of(ctx).pop(),
        ),
      ),
    );
