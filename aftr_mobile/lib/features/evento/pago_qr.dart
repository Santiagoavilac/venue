import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/networking/supabase.dart';
import '../../core/theme/aftr_theme.dart';
import '../../core/widgets/movimiento.dart';
import '../../core/widgets/piezas.dart';
import '../../data/aftr_repo.dart';

/// Pagá con QR: el QR lo genera el Banco Económico para este pedido y por su
/// importe exacto. Mientras la pantalla está abierta se le pregunta al
/// servidor cada 4 segundos si EL BANCO confirmó el pago (además, el servidor
/// lo revisa solo cada minuto aunque se cierre la app). La entrada se emite
/// recién con esa confirmación.
Future<void> abrirPagoQr(BuildContext context, {required String orden, required String titulo}) =>
    Navigator.of(context, rootNavigator: true).push(MaterialPageRoute(
      fullscreenDialog: true,
      builder: (_) => PagoQrScreen(orden: orden, titulo: titulo),
    ));

class PagoQrScreen extends ConsumerStatefulWidget {
  const PagoQrScreen({super.key, required this.orden, required this.titulo});
  final String orden;
  final String titulo;

  @override
  ConsumerState<PagoQrScreen> createState() => _PagoQrState();
}

enum _Fase { cargando, esperando, pagado, problema }

class _PagoQrState extends ConsumerState<PagoQrScreen> {
  _Fase _fase = _Fase.cargando;
  PagoQr? _pago;
  String? _error;
  Timer? _consulta;

  @override
  void initState() {
    super.initState();
    _pedirQr();
  }

  @override
  void dispose() {
    _consulta?.cancel();
    super.dispose();
  }

  Future<void> _pedirQr() async {
    setState(() {
      _fase = _Fase.cargando;
      _error = null;
    });
    try {
      final p = PagoQr.desde(await ref.read(repoProvider).qrDePago(widget.orden));
      if (!mounted) return;
      setState(() {
        _pago = p;
        _fase = p.estado == 'pagado' ? _Fase.pagado : _Fase.esperando;
      });
      if (_fase == _Fase.esperando) {
        _consulta = Timer.periodic(const Duration(seconds: 4), (_) => _revisar());
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _fase = _Fase.problema;
          _error = mensajeDePago(e);
        });
      }
    }
  }

  Future<void> _revisar() async {
    try {
      final r = await ref.read(repoProvider).estadoPago(widget.orden);
      if (!mounted) return;
      if (r.orden == 'confirmada' || r.estado == 'pagado') {
        _consulta?.cancel();
        HapticFeedback.heavyImpact();
        ref.invalidate(accesosProvider);
        setState(() => _fase = _Fase.pagado);
      } else if (r.estado == 'anulado' || r.estado == 'vencido' || r.orden == 'vencida' || r.orden == 'cancelada') {
        _consulta?.cancel();
        setState(() {
          _fase = _Fase.problema;
          _error = 'Este QR ya no se puede pagar (el pedido venció o se canceló).';
        });
      } else if (r.estado == 'revisar') {
        _consulta?.cancel();
        setState(() {
          _fase = _Fase.problema;
          _error = 'Recibimos tu pago pero hay que revisarlo. El boliche lo confirma a mano; no pagues de nuevo.';
        });
      }
    } catch (_) {
      // sin señal un rato: se vuelve a intentar en la próxima vuelta
    }
  }

  Future<void> _guardar() async {
    final img = _pago?.imagen;
    if (img == null) return;
    await SharePlus.instance.share(ShareParams(
      files: [XFile.fromData(img, mimeType: 'image/png', name: 'qr-pago-aftr.png')],
      text: 'QR de pago · ${widget.titulo}',
    ));
  }

  @override
  Widget build(BuildContext context) {
    final abajo = MediaQuery.paddingOf(context).bottom;
    return Scaffold(
      backgroundColor: Aftr.fondo,
      appBar: AppBar(
        backgroundColor: Aftr.fondo,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.close_rounded, color: Aftr.texto),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text('Pagá con QR', style: Aftr.fuerte(17)),
        centerTitle: true,
      ),
      body: AnimatedSwitcher(
        duration: Aftr.medio,
        child: switch (_fase) {
          _Fase.cargando => const Center(key: ValueKey('c'), child: CircularProgressIndicator(color: Aftr.texto)),
          _Fase.pagado => _Pagado(key: const ValueKey('p'), titulo: widget.titulo),
          _Fase.problema => _Problema(key: const ValueKey('x'), texto: _error ?? '', onReintentar: _pedirQr),
          _Fase.esperando => ListView(
              key: const ValueKey('e'),
              padding: EdgeInsets.fromLTRB(24, 8, 24, 24 + abajo),
              children: [
                Aparecer(child: Text(widget.titulo, textAlign: TextAlign.center, style: Aftr.cuerpo(15))),
                const SizedBox(height: 6),
                Aparecer(
                  orden: 1,
                  child: Text(bs((_pago?.monto ?? 0).round()), textAlign: TextAlign.center, style: Aftr.titular(44)),
                ),
                const SizedBox(height: 22),
                Aparecer(
                  orden: 2,
                  child: Center(
                    child: Container(
                      padding: const EdgeInsets.all(18),
                      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(28)),
                      child: _pago?.imagen != null
                          ? Image.memory(_pago!.imagen!, width: 250, height: 250, filterQuality: FilterQuality.none, gaplessPlayback: true)
                          : const SizedBox(width: 250, height: 250),
                    ),
                  ),
                ),
                const SizedBox(height: 22),
                Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  const PuntoVivo(color: Aftr.acento, tam: 7),
                  const SizedBox(width: 8),
                  Text('Esperando el pago', style: Aftr.cuerpo(15, c: Aftr.texto)),
                ]),
                const SizedBox(height: 8),
                Text(
                  'Escanealo con la app de cualquier banco. Si estás en este celular, guardalo y subilo desde tu banco. '
                  'Apenas el banco confirma, tu entrada aparece en Accesos.',
                  textAlign: TextAlign.center,
                  style: Aftr.cuerpo(13.5),
                ),
                if (_pago?.vence != null) ...[
                  const SizedBox(height: 6),
                  Text('Vale hasta el ${_pago!.vence}', textAlign: TextAlign.center, style: Aftr.cuerpo(12.5, c: Aftr.texto3)),
                ],
                const SizedBox(height: 24),
                BotonAftr('Guardar QR', onTap: _guardar),
                const SizedBox(height: 10),
                Text('Cobro procesado por Banco Económico', textAlign: TextAlign.center, style: Aftr.cuerpo(12, c: Aftr.texto3)),
              ],
            ),
        },
      ),
    );
  }
}

class _Pagado extends StatelessWidget {
  const _Pagado({super.key, required this.titulo});
  final String titulo;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.all(28),
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          TweenAnimationBuilder<double>(
            tween: Tween(begin: 0.6, end: 1),
            duration: Aftr.medio,
            curve: Curves.elasticOut,
            builder: (_, v, c) => Transform.scale(scale: v, child: c),
            child: Container(
              width: 92,
              height: 92,
              decoration: const BoxDecoration(color: Aftr.vivo, shape: BoxShape.circle),
              child: const Icon(Icons.check_rounded, color: Colors.black, size: 54),
            ),
          ),
          const SizedBox(height: 24),
          Text('Pago confirmado', style: Aftr.titular(34)),
          const SizedBox(height: 8),
          Text('El banco confirmó tu pago. Tu entrada para $titulo ya está en Accesos.',
              textAlign: TextAlign.center, style: Aftr.cuerpo(15, c: Aftr.texto)),
          const SizedBox(height: 28),
          BotonAftr('Ver mi entrada', onTap: () {
            Navigator.of(context).pop();
            GoRouter.of(context).go('/accesos');
          }),
        ]),
      );
}

class _Problema extends StatelessWidget {
  const _Problema({super.key, required this.texto, required this.onReintentar});
  final String texto;
  final VoidCallback onReintentar;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.all(28),
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          const Icon(Icons.qr_code_2_rounded, color: Aftr.texto3, size: 56),
          const SizedBox(height: 18),
          Text('No pudimos mostrar el QR', textAlign: TextAlign.center, style: Aftr.fuerte(20)),
          const SizedBox(height: 8),
          Text(texto, textAlign: TextAlign.center, style: Aftr.cuerpo(14, c: Aftr.texto)),
          const SizedBox(height: 8),
          Text('Tu pedido quedó guardado en Accesos.', textAlign: TextAlign.center, style: Aftr.cuerpo(13)),
          const SizedBox(height: 24),
          BotonAftr('Reintentar', onTap: onReintentar),
        ]),
      );
}

/// Mensaje claro para errores del cobro (sin detalles técnicos del banco).
String mensajeDePago(Object e) {
  final s = '$e';
  if (s.contains('no habilitado')) return 'El cobro con QR todavía no está habilitado por el banco.';
  if (s.contains('Iniciá sesión')) return 'Iniciá sesión para pagar.';
  return mensajeDeError(e);
}

/// QR de pago tal como lo devuelve el servidor.
class PagoQr {
  const PagoQr({required this.estado, this.monto, this.vence, this.imagen});
  final String estado;
  final num? monto;
  final String? vence;
  final Uint8List? imagen;

  factory PagoQr.desde(Map<String, dynamic> j) {
    final img = j['imagen'] as String?;
    return PagoQr(
      estado: j['estado'] as String? ?? 'activo',
      monto: j['monto'] as num? ?? num.tryParse('${j['monto']}'),
      vence: j['vence'] as String?,
      imagen: img == null || img.isEmpty ? null : base64Decode(img),
    );
  }
}
