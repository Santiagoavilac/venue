import 'dart:async';
import 'dart:ui';

import 'package:apple_maps_flutter/apple_maps_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/aftr_theme.dart';
import '../../core/widgets/movimiento.dart';
import '../../core/widgets/piezas.dart';
import '../../core/widgets/tarjetas.dart';
import '../../data/aftr_repo.dart';
import '../../data/modelos.dart';
import 'mapa_logica.dart';
import 'pines.dart';

/// El mapa (Search de Resy): Apple Maps oscuro a pantalla completa, búsqueda y
/// filtros arriba, y una hoja abajo con las tarjetas sincronizadas con los
/// pines. Si se jala la hoja, salen todos los eventos en lista.
class MapaScreen extends ConsumerStatefulWidget {
  const MapaScreen({super.key});

  @override
  ConsumerState<MapaScreen> createState() => _MapaScreenState();
}

class _MapaScreenState extends ConsumerState<MapaScreen> {
  static const _peek = 0.34;
  static const _medio = 0.6;
  static const _lleno = 0.93;

  final _hoja = DraggableScrollableController();
  final _tarjetas = PageController(viewportFraction: 0.86);
  final _busqueda = TextEditingController();
  AppleMapController? _mapa;
  Pines? _pines;
  final _iconos = <String, BitmapDescriptor>{};
  final _filtros = <FiltroMapa>{};
  int _elegido = 0;
  double _extension = _peek;
  bool _moviendoPorTarjeta = false;

  @override
  void initState() {
    super.initState();
    _hoja.addListener(() => setState(() => _extension = _hoja.size));
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _pines ??= Pines(MediaQuery.devicePixelRatioOf(context));
  }

  @override
  void dispose() {
    _hoja.dispose();
    _tarjetas.dispose();
    _busqueda.dispose();
    super.dispose();
  }

  Future<void> _prepararIconos(List<PinLugar> pines, DateTime ahora) async {
    var cambio = false;
    for (var i = 0; i < pines.length; i++) {
      final p = pines[i];
      final inicial = p.lugar.nombre.isEmpty ? 'A' : p.lugar.nombre.characters.first.toUpperCase();
      final elegido = i == _elegido;
      final clave = '${p.lugar.id}|${p.esHoy(ahora)}|$elegido|${p.evento == null}';
      if (_iconos.containsKey(clave)) continue;
      final bytes = await _pines!.pin(inicial, hoy: p.esHoy(ahora), elegido: elegido, apagado: p.evento == null);
      _iconos[clave] = BitmapDescriptor.fromBytes(bytes);
      cambio = true;
    }
    if (cambio && mounted) setState(() {});
  }

  void _elegir(int i, List<PinLugar> pines, {bool desdePin = false}) {
    if (i < 0 || i >= pines.length) return;
    setState(() => _elegido = i);
    final p = pines[i].lugar;
    _mapa?.animateCamera(CameraUpdate.newLatLng(LatLng(p.lat! - 0.0035, p.lng!)));
    if (desdePin) {
      HapticFeedback.selectionClick();
      _moviendoPorTarjeta = true;
      _tarjetas
          .animateToPage(i, duration: Aftr.medio, curve: Aftr.curva)
          .whenComplete(() => _moviendoPorTarjeta = false);
      if (_hoja.size > _peek + 0.02) {
        _hoja.animateTo(_peek, duration: Aftr.medio, curve: Aftr.curva);
      }
    }
  }

  void _centrar(List<PinLugar> pines) {
    final c = encuadre(pines);
    _mapa?.animateCamera(CameraUpdate.newLatLngZoom(LatLng(c.lat - 0.004, c.lng), c.zoom));
  }

  @override
  Widget build(BuildContext context) {
    final ahora = DateTime.now();
    final lugares = ref.watch(lugaresProvider).value ?? const <Lugar>[];
    final eventos = ref.watch(eventosProvider).value ?? const <Evento>[];
    final filtrados = filtrarEventos(eventos, _filtros, _busqueda.text, ahora);
    final todos = _filtros.isEmpty && _busqueda.text.trim().isEmpty;
    final pines = pinesPara(lugares, filtrados, todos: todos);
    if (_elegido >= pines.length) _elegido = 0;
    unawaited(_prepararIconos(pines, ahora));
    final c = encuadre(pines);
    final arriba = MediaQuery.paddingOf(context).top;
    final oscurecer = ((_extension - _medio) / (_lleno - _medio)).clamp(0.0, 1.0);

    final anotaciones = <Annotation>{
      for (var i = 0; i < pines.length; i++)
        if (_iconos['${pines[i].lugar.id}|${pines[i].esHoy(ahora)}|${i == _elegido}|${pines[i].evento == null}']
            case final icono?)
          Annotation(
            annotationId: AnnotationId(pines[i].lugar.id),
            position: LatLng(pines[i].lugar.lat!, pines[i].lugar.lng!),
            anchor: const Offset(0.5, 0.5),
            icon: icono,
            zIndex: i == _elegido ? 10 : (pines[i].esHoy(ahora) ? 5 : 1),
            onTap: () => _elegir(i, pines, desdePin: true),
          ),
    };

    return Scaffold(
      resizeToAvoidBottomInset: false,
      body: Stack(children: [
        Positioned.fill(
          child: AppleMap(
            initialCameraPosition: CameraPosition(target: LatLng(c.lat - 0.004, c.lng), zoom: c.zoom),
            onMapCreated: (m) => _mapa = m,
            annotations: anotaciones,
            myLocationEnabled: true,
            compassEnabled: false,
            pitchGesturesEnabled: false,
            insetsLayoutMarginsFromSafeArea: false,
            onTap: (_) => FocusScope.of(context).unfocus(),
          ),
        ),
        // al subir la hoja el mapa se apaga
        IgnorePointer(child: Container(color: Aftr.fondo.withValues(alpha: 0.7 * oscurecer))),
        // búsqueda y filtros
        Positioned(
          top: arriba + 8,
          left: 0,
          right: 0,
          child: Column(children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: _Vidrio(
                radio: 18,
                child: TextField(
                  controller: _busqueda,
                  onChanged: (_) => setState(() => _elegido = 0),
                  style: Aftr.cuerpo(16, c: Aftr.texto),
                  textInputAction: TextInputAction.search,
                  decoration: InputDecoration(
                    filled: false,
                    hintText: 'Buscar fiestas, lugares, géneros',
                    prefixIcon: const Icon(Icons.search_rounded, color: Aftr.texto),
                    suffixIcon: _busqueda.text.isEmpty
                        ? null
                        : IconButton(
                            onPressed: () => setState(() {
                              _busqueda.clear();
                              _elegido = 0;
                            }),
                            icon: const Icon(Icons.close_rounded, color: Aftr.texto2, size: 20),
                          ),
                  ),
                ),
              ),
            ),
            SizedBox(
              height: 52,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
                children: [
                  for (final f in FiltroMapa.values)
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: Pildora(
                        f.texto,
                        denso: true,
                        activa: _filtros.contains(f),
                        onTap: () => setState(() {
                          _filtros.contains(f) ? _filtros.remove(f) : _filtros.add(f);
                          _elegido = 0;
                        }),
                      ),
                    ),
                ],
              ),
            ),
          ]),
        ),
        // centrar: sube y baja con la hoja
        Positioned(
          right: 16,
          bottom: MediaQuery.sizeOf(context).height * _extension.clamp(_peek, _medio) + 12,
          child: Opacity(
            opacity: 1 - oscurecer,
            child: Presionable(
              onTap: () => _centrar(pines),
              child: const _Vidrio(
                radio: 14,
                child: SizedBox(width: 46, height: 46, child: Icon(Icons.near_me_rounded, color: Aftr.texto, size: 20)),
              ),
            ),
          ),
        ),
        DraggableScrollableSheet(
          controller: _hoja,
          initialChildSize: _peek,
          minChildSize: _peek,
          maxChildSize: _lleno,
          snap: true,
          snapSizes: const [_peek, _medio, _lleno],
          builder: (context, scroll) => _Hoja(
            scroll: scroll,
            pines: pines,
            eventos: filtrados,
            tarjetas: _tarjetas,
            elegido: _elegido,
            onPagina: (i) {
              if (!_moviendoPorTarjeta) _elegir(i, pines);
            },
          ),
        ),
      ]),
    );
  }
}

class _Vidrio extends StatelessWidget {
  const _Vidrio({required this.child, this.radio = 16});
  final Widget child;
  final double radio;

  @override
  Widget build(BuildContext context) => ClipRRect(
        borderRadius: BorderRadius.circular(radio),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
          child: Container(
            decoration: BoxDecoration(
              color: Aftr.superficie.withValues(alpha: 0.78),
              borderRadius: BorderRadius.circular(radio),
              border: Border.all(color: Aftr.borde),
            ),
            child: child,
          ),
        ),
      );
}

class _Hoja extends StatelessWidget {
  const _Hoja({
    required this.scroll,
    required this.pines,
    required this.eventos,
    required this.tarjetas,
    required this.elegido,
    required this.onPagina,
  });

  final ScrollController scroll;
  final List<PinLugar> pines;
  final List<Evento> eventos;
  final PageController tarjetas;
  final int elegido;
  final ValueChanged<int> onPagina;

  @override
  Widget build(BuildContext context) {
    final hoy = eventos.where((e) => e.esAhora(DateTime.now()) || fechaCorta(e.fecha) == 'Hoy').length;
    return ClipRRect(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
        child: Container(
          decoration: BoxDecoration(
            color: Aftr.superficie.withValues(alpha: 0.9),
            border: const Border(top: BorderSide(color: Aftr.borde)),
          ),
          child: CustomScrollView(
            controller: scroll,
            physics: const ClampingScrollPhysics(),
            slivers: [
              SliverToBoxAdapter(
                child: Column(children: [
                  Center(
                    child: Container(
                      margin: const EdgeInsets.only(top: 10),
                      width: 38,
                      height: 5,
                      decoration: BoxDecoration(color: Aftr.bordeFuerte, borderRadius: BorderRadius.circular(3)),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
                    child: Row(children: [
                      if (hoy > 0) ...[const PuntoVivo(), const SizedBox(width: 4)],
                      Expanded(
                        child: Text(
                          eventos.isEmpty
                              ? 'Sin eventos con estos filtros'
                              : (hoy > 0 ? '$hoy esta noche · ${eventos.length} en total' : '${eventos.length} eventos'),
                          style: Aftr.fuerte(16),
                        ),
                      ),
                      Text('Deslizá para ver todos', style: Aftr.cuerpo(12, c: Aftr.texto3)),
                    ]),
                  ),
                  if (pines.isNotEmpty)
                    SizedBox(
                      height: 132,
                      child: PageView.builder(
                        controller: tarjetas,
                        itemCount: pines.length,
                        onPageChanged: onPagina,
                        itemBuilder: (_, i) => AnimatedScale(
                          duration: Aftr.medio,
                          curve: Aftr.curva,
                          scale: i == elegido ? 1 : 0.94,
                          child: AnimatedOpacity(
                            duration: Aftr.medio,
                            opacity: i == elegido ? 1 : 0.6,
                            child: _TarjetaPin(pines[i]),
                          ),
                        ),
                      ),
                    ),
                ]),
              ),
              if (eventos.isNotEmpty) ...[
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 26, 20, 8),
                    child: Text('Todos los eventos', style: Aftr.fuerte(20)),
                  ),
                ),
                SliverList.builder(
                  itemCount: eventos.length,
                  itemBuilder: (_, i) => Aparecer(orden: i, child: FilaEvento(eventos[i])),
                ),
              ],
              SliverToBoxAdapter(child: SizedBox(height: 110 + MediaQuery.paddingOf(context).bottom)),
            ],
          ),
        ),
      ),
    );
  }
}

/// Tarjeta de la hoja: foto, lugar, el evento que viene y su precio.
class _TarjetaPin extends StatelessWidget {
  const _TarjetaPin(this.p);
  final PinLugar p;

  @override
  Widget build(BuildContext context) {
    final e = p.evento;
    return Presionable(
      onTap: () => e != null ? context.push('/evento/${e.id}', extra: e) : context.push('/lugar/${p.lugar.id}', extra: p.lugar),
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 6),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: Aftr.superficie2,
          borderRadius: BorderRadius.circular(Aftr.radio),
          border: Border.all(color: Aftr.borde),
        ),
        child: Row(children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(14),
            child: SizedBox(width: 108, height: double.infinity, child: ImagenRed(e?.flyer ?? p.lugar.portada, color: p.lugar.color)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(p.lugar.nombre.toUpperCase(), maxLines: 1, overflow: TextOverflow.ellipsis, style: Aftr.etiqueta(c: Aftr.acento)),
              const SizedBox(height: 4),
              Text(e?.nombre ?? 'Sin eventos próximos', maxLines: 2, overflow: TextOverflow.ellipsis, style: Aftr.fuerte(16)),
              const SizedBox(height: 4),
              if (e != null) Text(lineaEvento(e), maxLines: 1, overflow: TextOverflow.ellipsis, style: Aftr.cuerpo(13)),
              if (e != null && precioDesde(e) != null) ...[
                const SizedBox(height: 6),
                Text(precioDesde(e)!, style: Aftr.cuerpo(13, c: Aftr.texto, w: FontWeight.w700)),
              ],
            ]),
          ),
        ]),
      ),
    );
  }
}
