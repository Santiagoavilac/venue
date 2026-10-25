import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/networking/supabase.dart';
import '../../core/theme/aftr_theme.dart';
import '../../core/widgets/movimiento.dart';
import '../../core/widgets/piezas.dart';
import '../../core/widgets/tarjetas.dart';
import '../../data/aftr_repo.dart';
import '../../data/modelos.dart';
import '../auth/asegurar_cuenta.dart';

/// Abre Apple Maps con indicaciones hasta el lugar.
Future<void> comoLlegar(String nombre, double lat, double lng) => launchUrl(
      Uri.parse('https://maps.apple.com/?daddr=$lat,$lng&q=${Uri.encodeComponent(nombre)}'),
      mode: LaunchMode.externalApplication,
    );

/// El boliche: fotos en carrusel con puntos (como Resy), datos, seguir y sus
/// próximos eventos.
class LugarScreen extends ConsumerStatefulWidget {
  const LugarScreen({super.key, required this.id, this.previo});

  final String id;
  final Lugar? previo;

  @override
  ConsumerState<LugarScreen> createState() => _LugarScreenState();
}

class _LugarScreenState extends ConsumerState<LugarScreen> {
  final _pagina = PageController();
  int _foto = 0;
  bool? _sigo;

  @override
  void dispose() {
    _pagina.dispose();
    super.dispose();
  }

  Future<void> _seguir(Lugar l) async {
    if (!await asegurarCuenta(context, ref)) return;
    final antes = _sigo ?? l.siguiendo;
    setState(() => _sigo = !antes);
    try {
      final v = await ref.read(repoProvider).seguir(l.id);
      if (mounted) setState(() => _sigo = v);
      ref.invalidate(guardadosProvider);
    } catch (e) {
      if (mounted) {
        setState(() => _sigo = antes);
        avisar(context, mensajeDeError(e));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(lugarProvider(widget.id));
    final l = async.value ?? widget.previo;
    final ancho = MediaQuery.sizeOf(context).width;
    if (l == null) {
      return Scaffold(
        appBar: AppBar(),
        body: Center(
          child: async.isLoading
              ? const CircularProgressIndicator(color: Aftr.texto)
              : Text('Este lugar no está disponible.', style: Aftr.cuerpo(15)),
        ),
      );
    }
    final fotos = l.fotos.isNotEmpty ? l.fotos : [l.portada];
    final sigo = _sigo ?? l.siguiendo;
    return Scaffold(
      body: CustomScrollView(physics: const BouncingScrollPhysics(), slivers: [
        SliverAppBar(
          pinned: true,
          stretch: true,
          expandedHeight: ancho * 0.95,
          backgroundColor: Aftr.fondo,
          leading: Padding(
            padding: const EdgeInsets.all(8),
            child: CircleAvatar(
              backgroundColor: Aftr.fondo.withValues(alpha: 0.5),
              child: IconButton(
                onPressed: () => context.pop(),
                icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 16, color: Aftr.texto),
              ),
            ),
          ),
          flexibleSpace: FlexibleSpaceBar(
            stretchModes: const [StretchMode.zoomBackground],
            background: Stack(fit: StackFit.expand, children: [
              PageView.builder(
                controller: _pagina,
                itemCount: fotos.length,
                onPageChanged: (i) => setState(() => _foto = i),
                itemBuilder: (_, i) => ImagenRed(fotos[i], color: l.color),
              ),
              if (fotos.length > 1)
                Positioned(
                  bottom: 18,
                  left: 0,
                  right: 0,
                  child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                    for (var i = 0; i < fotos.length; i++)
                      AnimatedContainer(
                        duration: Aftr.medio,
                        margin: const EdgeInsets.symmetric(horizontal: 3),
                        width: i == _foto ? 18 : 6,
                        height: 6,
                        decoration: BoxDecoration(
                          color: i == _foto ? Aftr.texto : Aftr.texto.withValues(alpha: 0.45),
                          borderRadius: BorderRadius.circular(3),
                        ),
                      ),
                  ]),
                ),
            ]),
          ),
        ),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Aparecer(child: Text(l.nombre, style: Aftr.titular(38))),
                    if (l.subtitulo != null) ...[
                      const SizedBox(height: 6),
                      Text(l.subtitulo!, style: Aftr.cuerpo(15, c: Aftr.texto)),
                    ],
                  ]),
                ),
                const SizedBox(width: 12),
                Presionable(
                  onTap: () => _seguir(l),
                  child: AnimatedContainer(
                    duration: Aftr.medio,
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    decoration: BoxDecoration(
                      color: sigo ? Colors.transparent : Aftr.texto,
                      borderRadius: BorderRadius.circular(22),
                      border: Border.all(color: sigo ? Aftr.bordeFuerte : Aftr.texto),
                    ),
                    child: Text(sigo ? 'Siguiendo' : 'Seguir',
                        style: Aftr.cuerpo(14, c: sigo ? Aftr.texto : Aftr.fondo, w: FontWeight.w700)),
                  ),
                ),
              ]),
              const SizedBox(height: 14),
              Row(children: [
                const Icon(Icons.place_outlined, size: 16, color: Aftr.texto2),
                const SizedBox(width: 5),
                Expanded(
                  child: Text(
                    [l.direccion, l.zona, l.ciudad].whereType<String>().where((s) => s.isNotEmpty).join(', '),
                    style: Aftr.cuerpo(14, c: Aftr.texto),
                  ),
                ),
              ]),
              if (l.ubicado) ...[
                const SizedBox(height: 14),
                Pildora('Cómo llegar', icono: Icons.near_me_outlined, onTap: () => comoLlegar(l.nombre, l.lat!, l.lng!)),
              ],
              if ((l.descripcion ?? '').isNotEmpty) ...[
                const SizedBox(height: 22),
                Text(l.descripcion!, style: Aftr.cuerpo(15, c: Aftr.texto)),
              ],
            ]),
          ),
        ),
        const SliverToBoxAdapter(child: TituloSeccion('Próximos eventos')),
        if (l.eventos.isEmpty)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Text(
                async.isLoading ? 'Cargando...' : 'No hay eventos publicados por ahora. Seguilo para enterarte.',
                style: Aftr.cuerpo(14),
              ),
            ),
          )
        else
          SliverList.builder(
            itemCount: l.eventos.length,
            itemBuilder: (_, i) => Aparecer(orden: i, child: FilaEvento(l.eventos[i])),
          ),
        SliverToBoxAdapter(child: SizedBox(height: 40 + MediaQuery.paddingOf(context).bottom)),
      ]),
    );
  }
}
