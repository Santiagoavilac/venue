import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/networking/supabase.dart';
import '../../core/theme/aftr_theme.dart';
import '../../core/widgets/movimiento.dart';
import '../../core/widgets/piezas.dart';
import '../../data/aftr_repo.dart';
import '../../data/modelos.dart';
import '../auth/asegurar_cuenta.dart';
import 'hojas.dart';

/// Detalle del evento: flyer con parallax que se vuelve barra al subir,
/// fases como los horarios de Resy, listas, mesas y la barra de compra.
class EventoScreen extends ConsumerStatefulWidget {
  const EventoScreen({super.key, required this.id, this.previo});

  final String id;
  final Evento? previo;

  @override
  ConsumerState<EventoScreen> createState() => _EventoScreenState();
}

class _EventoScreenState extends ConsumerState<EventoScreen> {
  final _scroll = ScrollController();
  double _desplazado = 0;
  String? _fase;
  bool? _guardado;
  String? _anotando;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(() => setState(() => _desplazado = _scroll.offset));
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _guardar(EventoDetalle d) async {
    if (!await asegurarCuenta(context, ref)) return;
    final antes = _guardado ?? d.guardado;
    setState(() => _guardado = !antes);
    try {
      final ahora = await ref.read(repoProvider).guardar(d.evento.id);
      if (mounted) setState(() => _guardado = ahora);
      ref.invalidate(guardadosProvider);
    } catch (e) {
      if (mounted) {
        setState(() => _guardado = antes);
        avisar(context, mensajeDeError(e));
      }
    }
  }

  Future<void> _comprar(EventoDetalle d) async {
    if (!await asegurarCuenta(context, ref)) return;
    if (!mounted) return;
    final fase = d.ventaPorFases ? (d.fases.where((f) => f.id == _fase && f.comprable).firstOrNull ?? d.faseActual) : null;
    await abrirCompra(context, d, fase);
  }

  Future<void> _mesa(EventoDetalle d) async {
    if (!await asegurarCuenta(context, ref)) return;
    if (mounted) await abrirMesa(context, d);
  }

  Future<void> _lista(EventoDetalle d, Lista l) async {
    if (!await asegurarCuenta(context, ref)) return;
    setState(() => _anotando = l.id);
    try {
      await ref.read(repoProvider).anotarmeLista(d.evento.id, l.id);
      ref.invalidate(accesosProvider);
      if (mounted) await abrirListaConfirmada(context, l);
    } catch (e) {
      if (mounted) avisar(context, mensajeDeError(e));
    } finally {
      if (mounted) setState(() => _anotando = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(eventoProvider(widget.id));
    final d = async.value;
    final e = d?.evento ?? widget.previo;
    final ancho = MediaQuery.sizeOf(context).width;
    final altoFlyer = ancho * 1.18;
    final arriba = MediaQuery.paddingOf(context).top;
    final barra = ((_desplazado - altoFlyer + 140) / 60).clamp(0.0, 1.0);

    if (e == null) {
      return Scaffold(
        body: Center(
          child: async.hasError
              ? Text(mensajeDeError(async.error!), style: Aftr.cuerpo(15))
              : async.isLoading
                  ? const CircularProgressIndicator(color: Aftr.texto)
                  : Text('Este evento ya no está disponible.', style: Aftr.cuerpo(15)),
        ),
      );
    }

    return Scaffold(
      body: Stack(children: [
        CustomScrollView(
          controller: _scroll,
          physics: const BouncingScrollPhysics(),
          slivers: [
            SliverToBoxAdapter(
              child: SizedBox(
                height: altoFlyer,
                child: Stack(fit: StackFit.expand, clipBehavior: Clip.none, children: [
                  // parallax: la foto se mueve a la mitad de velocidad y se
                  // agranda si se tira para abajo
                  Positioned(
                    top: _desplazado < 0 ? _desplazado : _desplazado * 0.5,
                    left: 0,
                    right: 0,
                    height: altoFlyer - (_desplazado < 0 ? _desplazado : 0),
                    child: Hero(tag: 'flyer-${e.id}', child: ImagenRed(e.flyer, color: e.club.color)),
                  ),
                  const DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        stops: [0, 0.2, 0.6, 1],
                        colors: [Color(0x88000000), Colors.transparent, Colors.transparent, Aftr.fondo],
                      ),
                    ),
                  ),
                ]),
              ),
            ),
            SliverToBoxAdapter(
              child: Transform.translate(
                offset: const Offset(0, -56),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Aparecer(
                      child: GestureDetector(
                        onTap: () => context.push('/lugar/${e.club.id}'),
                        child: Row(mainAxisSize: MainAxisSize.min, children: [
                          Text(e.club.nombre.toUpperCase(), style: Aftr.etiqueta(c: Aftr.acento)),
                          const Icon(Icons.chevron_right_rounded, size: 16, color: Aftr.acento),
                        ]),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Aparecer(orden: 1, child: Text(e.nombre, style: Aftr.titular(40))),
                    const SizedBox(height: 14),
                    Aparecer(
                      orden: 2,
                      child: Wrap(spacing: 14, runSpacing: 6, children: [
                        _Dato(Icons.calendar_today_outlined, fechaCorta(e.fecha)),
                        _Dato(Icons.schedule_rounded, '${e.horaInicio} a ${e.horaFin}'),
                        _Dato(Icons.badge_outlined, '+${e.edadMin}'),
                        if (e.club.zona != null) _Dato(Icons.place_outlined, e.club.zona!),
                      ]),
                    ),
                    if (e.generos.isNotEmpty) ...[
                      const SizedBox(height: 14),
                      Wrap(spacing: 6, runSpacing: 6, children: [for (final g in e.generos) Pildora(g, denso: true)]),
                    ],
                  ]),
                ),
              ),
            ),
            if (d == null)
              const SliverToBoxAdapter(
                child: Padding(padding: EdgeInsets.all(20), child: Esqueleto(alto: 120, radio: 18)),
              )
            else ..._cuerpo(d),
            SliverToBoxAdapter(child: SizedBox(height: 140 + MediaQuery.paddingOf(context).bottom)),
          ],
        ),
        // barra de arriba: botones redondos sobre la foto y título cuando sube
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          child: ClipRect(
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 18 * barra, sigmaY: 18 * barra),
              child: Container(
                padding: EdgeInsets.fromLTRB(12, arriba + 6, 12, 8),
                color: Aftr.fondo.withValues(alpha: 0.7 * barra),
                child: Row(children: [
                  _Redondo(Icons.arrow_back_ios_new_rounded, () => context.pop()),
                  Expanded(
                    child: Opacity(
                      opacity: barra,
                      child: Text(e.nombre, textAlign: TextAlign.center, maxLines: 1, overflow: TextOverflow.ellipsis, style: Aftr.fuerte(16)),
                    ),
                  ),
                  _Redondo(Icons.ios_share_rounded, () => SharePlus.instance.share(ShareParams(
                        text: '${e.nombre} · ${e.club.nombre} · ${fechaCorta(e.fecha)} ${e.horaInicio}. Lo vi en AFTR.',
                      ))),
                  const SizedBox(width: 8),
                  if (d != null)
                    _Redondo(
                      (_guardado ?? d.guardado) ? Icons.favorite_rounded : Icons.favorite_border_rounded,
                      () => _guardar(d),
                      color: (_guardado ?? d.guardado) ? Aftr.alerta : Aftr.texto,
                    ),
                ]),
              ),
            ),
          ),
        ),
        if (d != null) Positioned(left: 0, right: 0, bottom: 0, child: _BarraCompra(d: d, fase: _fase, onComprar: () => _comprar(d))),
      ]),
    );
  }

  List<Widget> _cuerpo(EventoDetalle d) {
    final e = d.evento;
    return [
      if (d.fases.isNotEmpty || !d.ventaPorFases) ...[
        _titulo('Entradas'),
        SliverToBoxAdapter(
          child: SizedBox(
            height: 74,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 20),
              children: d.ventaPorFases
                  ? [
                      for (final f in d.fases)
                        _Horario(
                          titulo: f.nombre,
                          sub: switch (f.estado) {
                            EstadoFase.agotada => 'Agotada',
                            EstadoFase.proxima => 'Pronto',
                            EstadoFase.cerrada => 'Cerrada',
                            EstadoFase.abierta => f.quedan != null ? '${bs(f.precio)} · quedan ${f.quedan}' : bs(f.precio),
                          },
                          activo: f.comprable,
                          elegido: f.comprable && (_fase ?? d.faseActual?.id) == f.id,
                          onTap: f.comprable ? () => setState(() => _fase = f.id) : null,
                        ),
                    ]
                  : [
                      _Horario(
                        titulo: 'General',
                        sub: d.ventaAbierta ? bs(d.precio) : 'Venta cerrada',
                        activo: d.ventaAbierta,
                        elegido: d.ventaAbierta,
                      ),
                    ],
            ),
          ),
        ),
      ],
      if (d.listas.isNotEmpty) ...[
        _titulo('Listas'),
        SliverList.list(children: [
          for (final l in d.listas)
            _FilaLista(l, cargando: _anotando == l.id, onTap: l.abierta && _anotando == null ? () => _lista(d, l) : null),
        ]),
      ],
      if (d.mesas.isNotEmpty) ...[
        _titulo('Mesas'),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Presionable(
              onTap: () => _mesa(d),
              child: Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  gradient: LinearGradient(colors: [Aftr.acento.withValues(alpha: 0.18), Aftr.superficie2]),
                  borderRadius: BorderRadius.circular(Aftr.radio),
                  border: Border.all(color: Aftr.acento.withValues(alpha: 0.35)),
                ),
                child: Row(children: [
                  const Icon(Icons.table_restaurant_outlined, color: Aftr.acento, size: 28),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('Reservá una mesa', style: Aftr.fuerte(17)),
                      const SizedBox(height: 3),
                      Text(
                        '${d.mesas.length} disponibles${d.combos.isNotEmpty ? ' · desde ${bs(d.combos.map((c) => c.precio).reduce((a, b) => a < b ? a : b))}' : ''}',
                        style: Aftr.cuerpo(14),
                      ),
                    ]),
                  ),
                  const Icon(Icons.chevron_right_rounded, color: Aftr.texto),
                ]),
              ),
            ),
          ),
        ),
      ],
      if ((e.descripcion ?? '').isNotEmpty) ...[
        _titulo('Sobre el evento'),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: _TextoLargo(e.descripcion!),
          ),
        ),
      ],
      _titulo('Dónde'),
      SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Presionable(
            onTap: () => context.push('/lugar/${e.club.id}'),
            child: Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(color: Aftr.superficie2, borderRadius: BorderRadius.circular(Aftr.radio)),
              child: Row(children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: SizedBox(width: 52, height: 52, child: ImagenRed(e.club.logo, color: e.club.color)),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(e.club.nombre, style: Aftr.fuerte(16)),
                    Text([e.club.zona, e.club.ciudad].whereType<String>().join(', '), style: Aftr.cuerpo(13)),
                  ]),
                ),
                const Icon(Icons.chevron_right_rounded, color: Aftr.texto3),
              ]),
            ),
          ),
        ),
      ),
    ];
  }

  Widget _titulo(String t) => SliverToBoxAdapter(
        child: Padding(padding: const EdgeInsets.fromLTRB(20, 8, 20, 12), child: Text(t, style: Aftr.fuerte(20))),
      );
}

class _Dato extends StatelessWidget {
  const _Dato(this.icono, this.texto);
  final IconData icono;
  final String texto;

  @override
  Widget build(BuildContext context) => Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icono, size: 15, color: Aftr.texto2),
        const SizedBox(width: 5),
        Text(texto, style: Aftr.cuerpo(14, c: Aftr.texto)),
      ]);
}

class _Redondo extends StatelessWidget {
  const _Redondo(this.icono, this.onTap, {this.color = Aftr.texto});
  final IconData icono;
  final VoidCallback onTap;
  final Color color;

  @override
  Widget build(BuildContext context) => Presionable(
        onTap: onTap,
        child: ClipOval(
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
            child: Container(
              width: 40,
              height: 40,
              color: Aftr.fondo.withValues(alpha: 0.45),
              child: AnimatedSwitcher(
                duration: Aftr.rapido,
                transitionBuilder: (c, a) => ScaleTransition(scale: a, child: c),
                child: Icon(icono, key: ValueKey(icono), size: 18, color: color),
              ),
            ),
          ),
        ),
      );
}

/// Píldora de fase, como los horarios de Resy.
class _Horario extends StatelessWidget {
  const _Horario({required this.titulo, required this.sub, required this.activo, this.elegido = false, this.onTap});

  final String titulo;
  final String sub;
  final bool activo;
  final bool elegido;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(right: 10),
        child: Presionable(
          onTap: onTap,
          child: AnimatedContainer(
            duration: Aftr.medio,
            curve: Aftr.curva,
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
            decoration: BoxDecoration(
              color: elegido ? Aftr.texto : (activo ? Aftr.superficie2 : Colors.transparent),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: elegido ? Aftr.texto : Aftr.borde),
            ),
            child: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(titulo,
                  style: Aftr.fuerte(15, c: elegido ? Aftr.fondo : (activo ? Aftr.texto : Aftr.texto3))),
              const SizedBox(height: 2),
              Text(sub.toUpperCase(),
                  style: Aftr.etiqueta(c: elegido ? Aftr.fondo.withValues(alpha: 0.7) : (activo ? Aftr.texto2 : Aftr.texto3))),
            ]),
          ),
        ),
      );
}

class _FilaLista extends StatelessWidget {
  const _FilaLista(this.l, {this.onTap, this.cargando = false});

  final Lista l;
  final VoidCallback? onTap;
  final bool cargando;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
        child: Container(
          padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
          decoration: BoxDecoration(color: Aftr.superficie2, borderRadius: BorderRadius.circular(16)),
          child: Row(children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(l.nombre, style: Aftr.fuerte(16)),
                const SizedBox(height: 2),
                Text(
                  [
                    (l.precio ?? 0) > 0 ? '${bs(l.precio)} en puerta' : 'Free',
                    if (l.hasta != null) 'hasta ${l.hasta}',
                  ].join(' · '),
                  style: Aftr.cuerpo(13),
                ),
              ]),
            ),
            SizedBox(
              width: 112,
              child: l.abierta
                  ? _BotonChico(cargando ? '...' : 'Anotarme', onTap: onTap)
                  : Text('Cerrada', textAlign: TextAlign.center, style: Aftr.cuerpo(13, c: Aftr.texto3)),
            ),
          ]),
        ),
      );
}

class _BotonChico extends StatelessWidget {
  const _BotonChico(this.texto, {this.onTap});
  final String texto;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => Presionable(
        onTap: onTap,
        child: Container(
          height: 38,
          alignment: Alignment.center,
          decoration: BoxDecoration(color: Aftr.texto, borderRadius: BorderRadius.circular(20)),
          child: Text(texto, style: Aftr.cuerpo(14, c: Aftr.fondo, w: FontWeight.w700)),
        ),
      );
}

class _TextoLargo extends StatefulWidget {
  const _TextoLargo(this.texto);
  final String texto;

  @override
  State<_TextoLargo> createState() => _TextoLargoState();
}

class _TextoLargoState extends State<_TextoLargo> {
  bool _abierto = false;

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: () => setState(() => _abierto = !_abierto),
        child: AnimatedSize(
          duration: Aftr.medio,
          curve: Aftr.curva,
          alignment: Alignment.topCenter,
          child: Text(
            widget.texto,
            maxLines: _abierto ? null : 4,
            overflow: _abierto ? null : TextOverflow.ellipsis,
            style: Aftr.cuerpo(15, c: Aftr.texto),
          ),
        ),
      );
}

/// Barra fija de abajo: precio a la izquierda y Comprar.
class _BarraCompra extends StatelessWidget {
  const _BarraCompra({required this.d, required this.fase, required this.onComprar});

  final EventoDetalle d;
  final String? fase;
  final VoidCallback onComprar;

  @override
  Widget build(BuildContext context) {
    final f = d.fases.where((x) => x.id == fase && x.comprable).firstOrNull ?? d.faseActual;
    final precio = d.ventaPorFases ? f?.precio : d.precio;
    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: Container(
          padding: EdgeInsets.fromLTRB(20, 14, 20, 14 + MediaQuery.paddingOf(context).bottom),
          decoration: BoxDecoration(
            color: Aftr.fondo.withValues(alpha: 0.78),
            border: const Border(top: BorderSide(color: Aftr.borde)),
          ),
          child: Row(children: [
            Expanded(
              child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(d.seVende ? (d.ventaPorFases ? (f?.nombre ?? '') : 'Entrada') : 'Entradas', style: Aftr.cuerpo(13)),
                NumeroAnimado(d.seVende ? bs(precio) : 'No disponibles', estilo: Aftr.fuerte(20)),
              ]),
            ),
            SizedBox(width: 170, child: BotonAftr('Comprar', onTap: d.seVende ? onComprar : null)),
          ]),
        ),
      ),
    );
  }
}
