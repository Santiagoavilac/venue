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
import '../reventa/reventa.dart' show precioReventa;
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
          // La reventa estaba sólo detrás de un botón de texto en Accesos, o
          // sea escondida para quien no fue a buscarla. Es un mercado: vive
          // donde la gente mira.
          const SliverToBoxAdapter(child: ReventaEnInicio()),
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
// El desenfoque de fondo cuesta una lectura de toda la pantalla en la GPU en
// CADA cuadro, así que sobre una lista que se desplaza se paga en cada píxel de
// scroll. Queda sólo sobre el mapa, donde el fondo no se mueve con el dedo y el
// efecto es el que hace legible la tarjeta. Acá va el mismo color translúcido
// sin el filtro: se ve casi igual y no cuesta nada.
      flexibleSpace: ClipRect(
        child: Container(color: Aftr.fondo.withValues(alpha: 0.94)),
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

/// La reventa oficial en el inicio: las entradas que hay ahora, y si no hay
/// ninguna, la puerta para publicar la tuya. Antes esto vivía detrás de un
/// botón de texto arriba de Accesos.
class ReventaEnInicio extends ConsumerWidget {
  const ReventaEnInicio({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mercado = ref.watch(mercadoProvider);
    final ofertas = listaSocial(mercado.value?['ofertas']);
    // mientras carga no se anuncia nada: el inicio no tiene que saltar
    if (mercado.isLoading && mercado.value == null) return const SizedBox.shrink();
    if (ofertas.isEmpty) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(20, 30, 20, 0),
        child: Presionable(
          onTap: () => context.push('/reventa'),
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Aftr.superficie,
              borderRadius: BorderRadius.circular(Aftr.radio),
              border: Border.all(color: Aftr.borde),
            ),
            child: Row(children: [
              const Icon(Icons.swap_horiz_rounded, color: Aftr.acento),
              const SizedBox(width: 14),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Reventa oficial', style: Aftr.fuerte(16)),
                const SizedBox(height: 2),
                Text('No podés ir: vendé tu entrada con el QR protegido.',
                  style: Aftr.cuerpo(13)),
              ])),
              const Icon(Icons.chevron_right_rounded, color: Aftr.texto3),
            ]),
          ),
        ),
      );
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      TituloSeccion('Reventa oficial',
        accion: 'Ver todo', onAccion: () => context.push('/reventa')),
      SizedBox(
        height: 164,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 20),
          itemCount: ofertas.length,
          separatorBuilder: (_, _) => const SizedBox(width: 12),
          itemBuilder: (_, i) => _OfertaChica(ofertas[i]),
        ),
      ),
    ]);
  }
}

class _OfertaChica extends StatelessWidget {
  const _OfertaChica(this.o);
  final DatosSocial o;

  @override
  Widget build(BuildContext context) {
    final enPago = o['estado'] == 'reservada';
    return Presionable(
      onTap: () => context.push('/reventa?evento=${o['evento_id']}'),
      child: Container(
        width: 232,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Aftr.superficie,
          borderRadius: BorderRadius.circular(Aftr.radio),
          border: Border.all(color: Aftr.borde),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            const Icon(Icons.verified_outlined, size: 14, color: Aftr.vivo),
            const SizedBox(width: 5),
            // Expanded y no a secas: la etiqueta va espaciada y con el texto
            // más grande del sistema se desborda la tarjeta.
            Expanded(child: Text('ENTRADA OFICIAL', maxLines: 1,
              overflow: TextOverflow.ellipsis, style: Aftr.etiqueta(c: Aftr.vivo))),
          ]),
          const SizedBox(height: 12),
          Text('${o['evento'] ?? ''}', maxLines: 2, overflow: TextOverflow.ellipsis,
            style: Aftr.fuerte(17)),
          const SizedBox(height: 4),
          Text('${o['club'] ?? ''}', maxLines: 1, overflow: TextOverflow.ellipsis,
            style: Aftr.cuerpo(12)),
          const Spacer(),
          Text(precioReventa(o['precio_centavos']), style: Aftr.fuerte(21)),
          Text(
            enPago
                ? 'En pago · vuelve en minutos'
                : 'Vende ${o['vendedor'] ?? 'alguien de AFTR'}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Aftr.cuerpo(12, c: enPago ? Aftr.acento : Aftr.texto2),
          ),
        ]),
      ),
    );
  }
}
