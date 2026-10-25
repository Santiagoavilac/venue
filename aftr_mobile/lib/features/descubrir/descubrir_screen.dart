import 'dart:ui';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/networking/supabase.dart';
import '../../core/theme/aftr_theme.dart';
import '../../core/widgets/logo.dart';
import '../../core/widgets/movimiento.dart';
import '../../core/widgets/piezas.dart';
import '../../core/widgets/tarjetas.dart';
import '../../data/aftr_repo.dart';
import '../auth/asegurar_cuenta.dart';
import '../../data/modelos.dart';
import '../splash/splash.dart';

/// La noche elegida en la tira de fechas; null es "Todo".
final nocheProvider = NotifierProvider<_Noche, DateTime?>(_Noche.new);

class _Noche extends Notifier<DateTime?> {
  @override
  DateTime? build() => null;
  void elegir(DateTime? d) => state = d;
}

/// Eventos del rango elegido.
List<Evento> enRango(List<Evento> todos, Cuando c, DateTime ahora) {
  final r = rangoDe(c, ahora);
  return todos.where((e) => !e.fecha.isBefore(r.desde) && !e.fecha.isAfter(r.hasta)).toList();
}

bool _mismoDia(DateTime a, DateTime b) => a.year == b.year && a.month == b.month && a.day == b.day;

/// Descubrir, como el Discover de Resy: destacado grande, carruseles por
/// momento y por estilo, y la lista de lugares.
class DescubrirScreen extends ConsumerWidget {
  const DescubrirScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final eventos = ref.watch(eventosProvider);
    final lugares = ref.watch(lugaresProvider);
    final noche = ref.watch(nocheProvider);
    final ahora = DateTime.now();

    ref.listen(eventosProvider, (_, v) {
      final urls = [for (final e in v.value ?? const <Evento>[]) if (e.flyer != null) e.flyer!];
      if (urls.isNotEmpty) guardarFlyersParaSplash(urls);
    });

    return Scaffold(
      body: CustomScrollView(
        physics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
        slivers: [
          const _Cabecera(),
          CupertinoSliverRefreshControl(
            onRefresh: () async {
              ref.invalidate(eventosProvider);
              ref.invalidate(lugaresProvider);
              await ref.read(eventosProvider.future);
            },
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 6, 20, 0),
              child: Aparecer(child: Text('Discover\nthe night.', style: Aftr.titular(44))),
            ),
          ),
          SliverToBoxAdapter(
            child: _TiraFechas(
              elegida: noche,
              conEventos: {for (final e in eventos.value ?? const <Evento>[]) e.fecha},
              onElegir: (d) => ref.read(nocheProvider.notifier).elegir(d),
            ),
          ),
          ...eventos.when(
            loading: () => [const SliverToBoxAdapter(child: _Cargando())],
            error: (e, _) => [SliverToBoxAdapter(child: _Vacio(mensajeDeError(e), reintentar: () => ref.invalidate(eventosProvider)))],
            data: (todos) => _secciones(todos, noche, ahora),
          ),
          ...lugares.maybeWhen(
            data: (l) => l.isEmpty
                ? const <Widget>[]
                : [
                    const SliverToBoxAdapter(child: TituloSeccion('Lugares')),
                    SliverList.builder(
                      itemCount: l.length,
                      itemBuilder: (_, i) => Aparecer(orden: i, child: FilaLugar(l[i])),
                    ),
                  ],
            orElse: () => const <Widget>[],
          ),
          SliverToBoxAdapter(child: SizedBox(height: 120 + MediaQuery.paddingOf(context).bottom)),
        ],
      ),
    );
  }

  List<Widget> _secciones(List<Evento> todos, DateTime? noche, DateTime ahora) {
    final todo = noche == null;
    final lista = todo ? enRango(todos, Cuando.todo, ahora) : todos.where((e) => _mismoDia(e.fecha, noche)).toList();
    if (lista.isEmpty) {
      return [
        SliverToBoxAdapter(
          child: _Vacio(todos.isEmpty
              ? 'Todavía no hay eventos publicados. Volvé más tarde.'
              : 'Esa noche no hay nada publicado todavía. Probá otro día.'),
        ),
      ];
    }
    final hoy = enRango(todos, Cuando.hoy, ahora);
    final finde = enRango(todos, Cuando.finde, ahora);
    final gratis = lista.where((e) => e.desdePrecio == 0 || e.tieneLista).toList();
    final conMesa = lista.where((e) => e.mesasLibres > 0).toList();
    final generos = <String, List<Evento>>{};
    for (final e in lista) {
      for (final g in e.generos) {
        (generos[g] ??= []).add(e);
      }
    }
    return [
      SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
          child: Aparecer(orden: 1, child: TarjetaDestacada(lista.first)),
        ),
      ),
      if (todo && hoy.isNotEmpty) ..._carrusel('Esta noche', hoy),
      if (todo && finde.isNotEmpty) ..._carrusel('Este fin de semana', finde),
      if (!todo && lista.length > 1) ..._carrusel('También', lista.skip(1).toList()),
      if (gratis.isNotEmpty) ..._carrusel('Gratis con lista', gratis),
      if (conMesa.isNotEmpty) ..._carrusel('Con mesas disponibles', conMesa),
      for (final g in generos.entries.take(3)) ..._carrusel(g.key, g.value),
      if (todo && lista.length > 1) ...[
        const SliverToBoxAdapter(child: TituloSeccion('Próximos')),
        SliverList.builder(
          itemCount: lista.length,
          itemBuilder: (_, i) => Aparecer(orden: i, child: FilaEvento(lista[i])),
        ),
      ],
    ];
  }

  List<Widget> _carrusel(String titulo, List<Evento> ev) => [
        SliverToBoxAdapter(child: TituloSeccion(titulo)),
        SliverToBoxAdapter(
          child: SizedBox(
            height: 318,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              physics: const BouncingScrollPhysics(),
              padding: const EdgeInsets.symmetric(horizontal: 20),
              itemCount: ev.length,
              separatorBuilder: (_, _) => const SizedBox(width: 14),
              itemBuilder: (_, i) => Aparecer(orden: i, desde: 0, child: TarjetaEvento(ev[i])),
            ),
          ),
        ),
      ];
}

/// Barra de arriba: ciudad a la izquierda, AFTR al centro y la cuenta a la
/// derecha. Se vuelve vidrio al bajar.
class _Cabecera extends ConsumerWidget {
  const _Cabecera();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final perfil = ref.watch(perfilProvider).value;
    final logueado = ref.watch(usuarioIdProvider) != null;
    return SliverAppBar(
      pinned: true,
      backgroundColor: Colors.transparent,
      toolbarHeight: 60,
      flexibleSpace: ClipRect(
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
          child: Container(color: Aftr.fondo.withValues(alpha: 0.72)),
        ),
      ),
      titleSpacing: 20,
      centerTitle: false,
      title: Row(children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(color: Aftr.superficie2, borderRadius: BorderRadius.circular(20)),
          child: Row(children: [
            Text('Santa Cruz', style: Aftr.cuerpo(14, c: Aftr.texto, w: FontWeight.w600)),
            const SizedBox(width: 4),
            const Icon(Icons.keyboard_arrow_down_rounded, size: 18, color: Aftr.texto),
          ]),
        ),
        const Spacer(),
        const PalabraAftr(alto: 16),
        const Spacer(),
        Presionable(
          onTap: () => logueado ? context.go('/cuenta') : asegurarCuenta(context, ref),
          child: CircleAvatar(
            radius: 18,
            backgroundColor: Aftr.superficie2,
            child: perfil != null
                ? Text(perfil.nombre.characters.first.toUpperCase(), style: Aftr.fuerte(15))
                : const Icon(Icons.person_outline_rounded, size: 20, color: Aftr.texto),
          ),
        ),
      ]),
    );
  }
}

class _Cargando extends StatelessWidget {
  const _Cargando();

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const AspectRatio(aspectRatio: 0.82, child: Esqueleto(radio: Aftr.radio + 4)),
          const SizedBox(height: 30),
          const Esqueleto(alto: 22, ancho: 160),
          const SizedBox(height: 16),
          Row(children: const [
            Expanded(child: AspectRatio(aspectRatio: 0.9, child: Esqueleto(radio: Aftr.radio))),
            SizedBox(width: 14),
            Expanded(child: AspectRatio(aspectRatio: 0.9, child: Esqueleto(radio: Aftr.radio))),
          ]),
        ]),
      );
}

class _Vacio extends StatelessWidget {
  const _Vacio(this.texto, {this.reintentar});

  final String texto;
  final VoidCallback? reintentar;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(32, 60, 32, 20),
        child: Column(children: [
          const MarcaAftr(alto: 40, color: Aftr.texto3),
          const SizedBox(height: 20),
          Text(texto, textAlign: TextAlign.center, style: Aftr.cuerpo(15)),
          if (reintentar != null) ...[
            const SizedBox(height: 16),
            Pildora('Reintentar', onTap: reintentar),
          ],
        ]),
      );
}

/// La tira de fechas (como Dice o RA): "Todo" y los próximos 21 días, con el
/// nombre chico arriba, el número grande en la serif, un punto dorado si esa
/// noche hay algo y una línea que se desliza hasta el elegido. Sin cajas.
class _TiraFechas extends StatelessWidget {
  const _TiraFechas({required this.elegida, required this.conEventos, required this.onElegir});

  final DateTime? elegida;
  final Set<DateTime> conEventos;
  final ValueChanged<DateTime?> onElegir;

  static const _anchoTodo = 60.0;
  static const _anchoDia = 48.0;
  static const _dias = ['lun', 'mar', 'mié', 'jue', 'vie', 'sáb', 'dom'];

  @override
  Widget build(BuildContext context) {
    final h = DateTime.now();
    final hoy = DateTime(h.year, h.month, h.day);
    final dias = [for (var i = 0; i < 21; i++) DateTime(hoy.year, hoy.month, hoy.day + i)];
    final i = elegida == null ? -1 : dias.indexWhere((d) => _mismoDia(d, elegida!));
    final centro = i < 0 ? _anchoTodo / 2 : _anchoTodo + _anchoDia * i + _anchoDia / 2;
    return Container(
      height: 86,
      decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: Aftr.borde))),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.symmetric(horizontal: 14),
        child: Stack(children: [
          Row(children: [
            _Dia(ancho: _anchoTodo, arriba: '', numero: 'Todo', elegido: elegida == null, hay: false, onTap: () => onElegir(null)),
            for (var j = 0; j < dias.length; j++)
              _Dia(
                ancho: _anchoDia,
                arriba: j == 0 ? 'HOY' : (j == 1 ? 'MAÑ' : _dias[dias[j].weekday - 1].toUpperCase()),
                numero: '${dias[j].day}',
                elegido: j == i,
                hay: conEventos.any((f) => _mismoDia(f, dias[j])),
                onTap: () => onElegir(dias[j]),
              ),
          ]),
          AnimatedPositioned(
            duration: const Duration(milliseconds: 450),
            curve: Aftr.curva,
            left: centro - 9,
            bottom: 0,
            child: Container(width: 18, height: 2, decoration: BoxDecoration(color: Aftr.texto, borderRadius: BorderRadius.circular(1))),
          ),
        ]),
      ),
    );
  }
}

class _Dia extends StatelessWidget {
  const _Dia({required this.ancho, required this.arriba, required this.numero, required this.elegido, required this.hay, required this.onTap});

  final double ancho;
  final String arriba;
  final String numero;
  final bool elegido;
  final bool hay;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = elegido ? Aftr.texto : (hay ? Aftr.texto2 : Aftr.texto3);
    final esTodo = arriba.isEmpty;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: SizedBox(
        width: ancho,
        child: Padding(
          padding: const EdgeInsets.only(top: 18, bottom: 10),
          child: Column(children: [
            Text(arriba, style: TextStyle(fontFamily: Aftr.sans, fontSize: 10, fontWeight: FontWeight.w600, letterSpacing: 1.4, color: color)),
            const SizedBox(height: 2),
            AnimatedScale(
              duration: Aftr.medio,
              curve: Curves.easeOutBack,
              scale: elegido ? 1.12 : 1,
              child: Text(
                numero,
                style: esTodo
                    ? TextStyle(fontFamily: Aftr.sans, fontSize: 15, fontWeight: FontWeight.w700, color: color, height: 1.9)
                    : TextStyle(fontFamily: Aftr.serif, fontSize: 26, color: color, height: 1.1),
              ),
            ),
            const SizedBox(height: 3),
            Container(
              width: 4,
              height: 4,
              decoration: BoxDecoration(shape: BoxShape.circle, color: hay ? Aftr.acento : Colors.transparent),
            ),
          ]),
        ),
      ),
    );
  }
}
