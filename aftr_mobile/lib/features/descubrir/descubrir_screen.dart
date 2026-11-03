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
import '../../core/widgets/avatar.dart';
import '../../data/aftr_repo.dart';
import '../auth/asegurar_cuenta.dart';
import '../../data/modelos.dart';
import '../splash/splash.dart';
import '../historias/historias.dart';
import '../../data/social_repo.dart';

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
              ref.invalidate(historiasProvider);
              await ref.read(eventosProvider.future);
            },
          ),
          const SliverToBoxAdapter(child: HistoriasFila()),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 6, 20, 0),
              child: Aparecer(child: Text('Descubrir', style: Aftr.titular(32))),
            ),
          ),
          SliverToBoxAdapter(
            child: FechasAftr(
              elegida: noche,
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
    final restantes = todos.where((e) => e.id != lista.first.id).toList();
    final hoy = enRango(restantes, Cuando.hoy, ahora);
    final finde = enRango(restantes, Cuando.finde, ahora);
    final gratis = lista.skip(1).where((e) => e.desdePrecio == 0 || e.tieneLista).toList();
    final conMesa = lista.skip(1).where((e) => e.mesasLibres > 0).toList();
    final generos = <String, List<Evento>>{};
    for (final e in lista.skip(1)) {
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
        Text('Santa Cruz', style: Aftr.cuerpo(13, c: Aftr.texto2)),
        const Spacer(),
        const PalabraAftr(alto: 16),
        const Spacer(),
        Presionable(
          onTap: () => logueado ? context.go('/cuenta') : asegurarCuenta(context, ref),
          child: AvatarAftr(nombre: perfil?.nombre, foto: perfil?.foto),
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

/// Fechas en una sola línea, con el mismo alto de toque para cada opción.
class FechasAftr extends StatelessWidget {
  const FechasAftr({super.key, required this.elegida, required this.onElegir});
  final DateTime? elegida;
  final ValueChanged<DateTime?> onElegir;
  static const _dias = ['Lun', 'Mar', 'Mié', 'Jue', 'Vie', 'Sáb', 'Dom'];

  @override
  Widget build(BuildContext context) {
    final ahora = DateTime.now();
    final hoy = DateTime(ahora.year, ahora.month, ahora.day);
    final opciones = <(String, DateTime?)>[
      ('Todo', null),
      for (var i = 0; i < 21; i++)
        (i == 0 ? 'Hoy' : i == 1 ? 'Mañana' : '${_dias[DateTime(hoy.year, hoy.month, hoy.day + i).weekday - 1]} ${DateTime(hoy.year, hoy.month, hoy.day + i).day}',
         DateTime(hoy.year, hoy.month, hoy.day + i)),
    ];
    return SizedBox(
      height: 44,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        children: [for (final o in opciones)
          Semantics(
            button: true,
            selected: elegida == null ? o.$2 == null : o.$2 != null && _mismoDia(elegida!, o.$2!),
            child: InkWell(
              onTap: () => onElegir(o.$2),
              child: Container(
                alignment: Alignment.center,
                margin: const EdgeInsets.only(right: 22),
                decoration: BoxDecoration(border: Border(bottom: BorderSide(
                  color: (elegida == null ? o.$2 == null : o.$2 != null && _mismoDia(elegida!, o.$2!)) ? Aftr.texto : Colors.transparent,
                  width: 1,
                ))),
                child: Text(o.$1, style: Aftr.cuerpo(13,
                  c: (elegida == null ? o.$2 == null : o.$2 != null && _mismoDia(elegida!, o.$2!)) ? Aftr.texto : Aftr.texto3,
                  w: FontWeight.w500)),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
