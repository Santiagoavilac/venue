import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:screen_brightness/screen_brightness.dart';

import '../../core/networking/supabase.dart';
import '../../core/theme/aftr_theme.dart';
import '../../core/widgets/logo.dart';
import '../../core/widgets/movimiento.dart';
import '../../core/widgets/fondo_video.dart';
import '../../core/widgets/piezas.dart';
import '../evento/pago_qr.dart';
import '../../data/aftr_repo.dart';
import '../auth/asegurar_cuenta.dart';
import '../../data/modelos.dart';
import '../lugar/lugar_screen.dart';
import 'enviar_sheet.dart';

/// La billetera: tarjetas apiladas como Apple Wallet. Tocar una la sube y
/// muestra el QR grande con el brillo al máximo; las demás bajan al fondo.
class AccesosScreen extends ConsumerStatefulWidget {
  const AccesosScreen({super.key});

  @override
  ConsumerState<AccesosScreen> createState() => _AccesosScreenState();
}

class _AccesosScreenState extends ConsumerState<AccesosScreen> {
  String? _abierta;
  bool _brillo = false;

  Future<void> _abrir(Acceso? a) async {
    setState(() => _abierta = a?.id);
    try {
      if (a != null && a.tieneQr) {
        await ScreenBrightness.instance.setApplicationScreenBrightness(1);
        _brillo = true;
      } else if (_brillo) {
        await ScreenBrightness.instance.resetApplicationScreenBrightness();
        _brillo = false;
      }
    } catch (_) {}
  }

  @override
  void dispose() {
    if (_brillo) ScreenBrightness.instance.resetApplicationScreenBrightness().ignore();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final logueado = ref.watch(usuarioIdProvider) != null;
    final async = ref.watch(accesosProvider);
    final ahora = DateTime.now();
    final arriba = MediaQuery.paddingOf(context).top;

    if (!logueado) {
      return Scaffold(
        body: _SinCuenta(onEntrar: () => asegurarCuenta(context, ref)),
      );
    }

    final accesos = async.value;
    final proximos = accesos?.proximos(ahora) ?? const <Acceso>[];
    final pasados = accesos?.pasados(ahora) ?? const <Acceso>[];
    final abierta = proximos.where((a) => a.id == _abierta).firstOrNull;

    return Scaffold(
      body: RefreshIndicator(
        color: Aftr.texto,
        backgroundColor: Aftr.superficie2,
        onRefresh: () => ref.refresh(accesosProvider.future),
        child: ListView(
          physics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
          padding: EdgeInsets.fromLTRB(16, arriba + 12, 16, 130 + MediaQuery.paddingOf(context).bottom),
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 0, 4, 18),
              child: Row(children: [
                Expanded(child: Text('Accesos', style: Aftr.titular(40))),
                if (abierta != null) Pildora('Cerrar', denso: true, onTap: () => _abrir(null)),
              ]),
            ),
            if (async.isLoading && accesos == null)
              const Esqueleto(alto: 200, radio: 24)
            else if (async.hasError && accesos == null)
              Text(mensajeDeError(async.error!), style: Aftr.cuerpo(15))
            else if (proximos.isEmpty)
              _Vacio(onExplorar: () => context.go('/'))
            else
              _Pila(accesos: proximos, abierta: abierta?.id, onTocar: (a) => _abrir(abierta?.id == a.id ? null : a)),
            if (pasados.isNotEmpty && abierta == null) ...[
              const SizedBox(height: 34),
              Padding(padding: const EdgeInsets.only(left: 4), child: Text('Historial', style: Aftr.fuerte(20))),
              const SizedBox(height: 8),
              for (final a in pasados.take(30)) _FilaPasada(a),
            ],
          ],
        ),
      ),
    );
  }
}

/// La pila: cada tarjeta asoma su cabecera; la abierta se ve entera arriba y
/// las demás se apilan apretadas abajo.
class _Pila extends StatelessWidget {
  const _Pila({required this.accesos, required this.abierta, required this.onTocar});

  final List<Acceso> accesos;
  final String? abierta;
  final ValueChanged<Acceso> onTocar;

  static const _cabecera = 86.0;
  static const _apretada = 14.0;

  @override
  Widget build(BuildContext context) {
    final ancho = MediaQuery.sizeOf(context).width - 32;
    final altoAbierta = ancho * 1.32;
    final altoCerrada = 210.0;
    final iAbierta = accesos.indexWhere((a) => a.id == abierta);
    final total = iAbierta < 0
        ? _cabecera * (accesos.length - 1) + altoCerrada
        : altoAbierta + 18 + _apretada * (accesos.length - 1) + _cabecera * 0.6;

    double top(int i) {
      if (iAbierta < 0) return _cabecera * i;
      if (i == iAbierta) return 0;
      final debajo = i < iAbierta ? i : i - 1;
      return altoAbierta + 18 + _apretada * debajo;
    }

    return AnimatedContainer(
      duration: Aftr.lento,
      curve: Aftr.curva,
      height: total,
      child: Stack(clipBehavior: Clip.none, children: [
        for (var i = 0; i < accesos.length; i++)
          AnimatedPositioned(
            key: ValueKey(accesos[i].id),
            duration: Aftr.lento,
            curve: Curves.easeOutBack,
            top: top(i),
            left: iAbierta >= 0 && i != iAbierta ? 8 : 0,
            right: iAbierta >= 0 && i != iAbierta ? 8 : 0,
            height: i == iAbierta ? altoAbierta : altoCerrada,
            child: Aparecer(
              orden: i,
              desde: 40,
              child: _Tarjeta(accesos[i], abierta: i == iAbierta, onTap: () => onTocar(accesos[i])),
            ),
          ),
      ]),
    );
  }
}

class _Tarjeta extends ConsumerWidget {
  const _Tarjeta(this.a, {required this.abierta, required this.onTap});

  final Acceso a;
  final bool abierta;
  final VoidCallback onTap;

  String get _tipo => switch (a.tipo) {
        TipoAcceso.entrada => 'ENTRADA',
        TipoAcceso.lista => 'LISTA',
        TipoAcceso.mesa => 'MESA',
        TipoAcceso.pedido => 'PEDIDO',
      };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final e = a.evento;
    final color = e.club.color ?? Aftr.superficie3;
    final pendiente = a.estado == EstadoAcceso.pendiente;
    return Presionable(
      escala: 0.985,
      onTap: onTap,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: Stack(fit: StackFit.expand, children: [
          ImagenRed(e.flyer, color: color),
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Colors.black.withValues(alpha: 0.35), Colors.black.withValues(alpha: abierta ? 0.88 : 0.75)],
              ),
              border: Border.all(color: Aftr.borde),
              borderRadius: BorderRadius.circular(24),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Text(_tipo, style: Aftr.etiqueta(c: Aftr.texto)),
                const Spacer(),
                if (pendiente) ...[
                  const PuntoVivo(color: Aftr.acento, tam: 6),
                  Text(a.tipo == TipoAcceso.pedido ? 'FALTA PAGAR' : 'ESPERANDO AL BOLICHE', style: Aftr.etiqueta(c: Aftr.acento)),
                ] else
                  const MarcaAftr(alto: 16),
              ]),
              const SizedBox(height: 10),
              Text(e.nombre, maxLines: 1, overflow: TextOverflow.ellipsis, style: Aftr.titular(28)),
              const SizedBox(height: 4),
              Text('${e.club.nombre} · ${fechaCorta(e.fecha)} · ${e.horaInicio}',
                  maxLines: 1, overflow: TextOverflow.ellipsis, style: Aftr.cuerpo(13, c: Aftr.texto)),
              const Spacer(),
              AnimatedSwitcher(
                duration: Aftr.medio,
                switchInCurve: Aftr.curva,
                transitionBuilder: (c, an) => FadeTransition(
                  opacity: an,
                  child: ScaleTransition(scale: Tween(begin: 0.94, end: 1.0).animate(an), child: c),
                ),
                child: abierta ? _Abierta(a, key: const ValueKey(1)) : _Pie(a, key: const ValueKey(0)),
              ),
            ]),
          ),
        ]),
      ),
    );
  }
}

class _Pie extends StatelessWidget {
  const _Pie(this.a, {super.key});
  final Acceso a;

  @override
  Widget build(BuildContext context) => Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(a.titulo, style: Aftr.fuerte(18)),
            if ((a.detalle ?? '').isNotEmpty) Text(a.detalle!, style: Aftr.cuerpo(13, c: Aftr.texto)),
          ]),
        ),
        if (a.total != null && a.estado == EstadoAcceso.pendiente) Text(bs(a.total), style: Aftr.fuerte(18)),
        if (a.tieneQr) const Icon(Icons.qr_code_2_rounded, color: Aftr.texto, size: 30),
      ]);
}

/// Lo que se ve con la tarjeta abierta: QR grande y acciones.
class _Abierta extends ConsumerStatefulWidget {
  const _Abierta(this.a, {super.key});
  final Acceso a;

  @override
  ConsumerState<_Abierta> createState() => _AbiertaState();
}

class _AbiertaState extends ConsumerState<_Abierta> {
  bool _cancelando = false;

  Future<void> _cancelar() async {
    setState(() => _cancelando = true);
    try {
      await ref.read(repoProvider).cancelarPedido(widget.a.id);
      ref.invalidate(accesosProvider);
    } catch (e) {
      if (mounted) avisar(context, mensajeDeError(e));
    } finally {
      if (mounted) setState(() => _cancelando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final a = widget.a;
    final club = a.evento.club;
    return Column(mainAxisSize: MainAxisSize.min, children: [
      if (a.tieneQr) ...[
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20)),
          child: QrImageView(data: a.qr!, size: 210, padding: EdgeInsets.zero, backgroundColor: Colors.white),
        ),
        const SizedBox(height: 10),
        Text(a.code ?? '', style: Aftr.cuerpo(15, c: Aftr.texto, w: FontWeight.w600).copyWith(letterSpacing: 3)),
        const SizedBox(height: 4),
        Text([a.titulo, a.detalle].whereType<String>().where((s) => s.isNotEmpty).join(' · '),
            textAlign: TextAlign.center, style: Aftr.cuerpo(13)),
      ] else ...[
        const Icon(Icons.hourglass_top_rounded, color: Aftr.acento, size: 40),
        const SizedBox(height: 12),
        Text(a.titulo, style: Aftr.fuerte(20)),
        const SizedBox(height: 6),
        Text(
          a.tipo == TipoAcceso.pedido
              ? 'Pagalo con el QR del banco y tus entradas aparecen acá solas.'
              : '${club.nombre} tiene que confirmar tu pedido. Cuando lo haga, tus QR aparecen acá solos.',
          textAlign: TextAlign.center,
          style: Aftr.cuerpo(14, c: Aftr.texto),
        ),
        if (a.total != null) ...[
          const SizedBox(height: 10),
          Text(bs(a.total), style: Aftr.fuerte(24)),
        ],
      ],
      const SizedBox(height: 16),
      Row(children: [
        if (a.transferible)
          Expanded(
            child: BotonAftr('Enviar a un amigo', onTap: () => enviarEntrada(context, a)),
          ),
        if (a.tipo == TipoAcceso.pedido) ...[
          Expanded(child: BotonAftr('Pagar con QR', onTap: () => abrirPagoQr(context, orden: a.id, titulo: a.evento.nombre))),
          const SizedBox(width: 10),
          Expanded(child: BotonAftr('Cancelar', secundario: true, cargando: _cancelando, onTap: _cancelar)),
        ],
        if (club.ubicado) ...[
          if (a.transferible || a.tipo == TipoAcceso.pedido) const SizedBox(width: 10),
          Presionable(
            onTap: () => comoLlegar(club.nombre, club.lat!, club.lng!),
            child: Container(
              width: 54,
              height: 54,
              decoration: BoxDecoration(color: Aftr.superficie2, shape: BoxShape.circle, border: Border.all(color: Aftr.bordeFuerte)),
              child: const Icon(Icons.near_me_outlined, color: Aftr.texto),
            ),
          ),
        ],
      ]),
    ]);
  }
}

class _FilaPasada extends StatelessWidget {
  const _FilaPasada(this.a);
  final Acceso a;

  @override
  Widget build(BuildContext context) {
    final estado = switch (a.estado) {
      EstadoAcceso.usada => 'Usada',
      EstadoAcceso.anulada => 'Anulada',
      EstadoAcceso.valida => 'Sin usar',
      EstadoAcceso.pendiente => 'Pendiente',
    };
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
      child: Row(children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: SizedBox(width: 48, height: 48, child: ImagenRed(a.evento.flyer, color: a.evento.club.color)),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(a.evento.nombre, maxLines: 1, overflow: TextOverflow.ellipsis, style: Aftr.fuerte(15)),
            Text('${a.titulo} · ${fechaCorta(a.evento.fecha)}', style: Aftr.cuerpo(13)),
          ]),
        ),
        Text(estado, style: Aftr.cuerpo(13, c: Aftr.texto3)),
      ]),
    );
  }
}

class _Vacio extends StatelessWidget {
  const _Vacio({required this.onExplorar});
  final VoidCallback onExplorar;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.fromLTRB(24, 40, 24, 28),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: Aftr.borde),
          gradient: const LinearGradient(colors: [Aftr.superficie2, Aftr.fondo], begin: Alignment.topCenter, end: Alignment.bottomCenter),
        ),
        child: Column(children: [
          const MarcaAftr(alto: 44, color: Aftr.texto3),
          const SizedBox(height: 18),
          Text('Tu próxima noche va acá', style: Aftr.fuerte(20)),
          const SizedBox(height: 6),
          Text('Las entradas, listas y mesas que consigas aparecen con su QR.',
              textAlign: TextAlign.center, style: Aftr.cuerpo(14)),
          const SizedBox(height: 20),
          BotonAftr('Explorar eventos', onTap: onExplorar),
        ]),
      );
}

class _SinCuenta extends StatelessWidget {
  const _SinCuenta({required this.onEntrar});
  final VoidCallback onEntrar;

  @override
  Widget build(BuildContext context) => FondoVideo(
        'assets/fondos/acceso.mp4',
        child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Accesos', style: Aftr.titular(40)),
            const Spacer(),
            const MarcaAftr(alto: 56),
            const SizedBox(height: 24),
            Text('Tus entradas, en un solo lugar.', style: Aftr.titular(30)),
            const SizedBox(height: 10),
            Text('Entrá para comprar, anotarte en listas, reservar mesas y recibir entradas de tus amigos.',
                style: Aftr.cuerpo(15, c: Aftr.texto)),
            const SizedBox(height: 24),
            BotonAftr('Entrar', onTap: onEntrar),
            const SizedBox(height: 110),
          ]),
        ),
        ),
      );
}
