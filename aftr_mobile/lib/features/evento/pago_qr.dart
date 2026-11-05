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
import '../../core/widgets/soporte.dart';
import '../../data/aftr_repo.dart';
import '../../data/pulse_repo.dart';

/// Pagá con QR: el QR lo genera el Banco Económico para este pedido y por su
/// importe exacto. Mientras la pantalla está abierta se le pregunta al
/// servidor cada 4 segundos si EL BANCO confirmó el pago (además, el servidor
/// lo revisa solo cada minuto aunque se cierre la app). La entrada se emite
/// recién con esa confirmación.
Future<void> abrirPagoQr(
  BuildContext context, {
  required String orden,
  required String titulo,
  String tipo = 'orden',
}) => Navigator.of(context, rootNavigator: true).push(
  MaterialPageRoute(
    fullscreenDialog: true,
    builder: (_) => PagoQrScreen(orden: orden, titulo: titulo, tipo: tipo),
  ),
);

class PagoQrScreen extends ConsumerStatefulWidget {
  const PagoQrScreen({
    super.key,
    required this.orden,
    required this.titulo,
    this.tipo = 'orden',
  });
  final String orden;
  final String titulo;
  final String tipo;

  @override
  ConsumerState<PagoQrScreen> createState() => _PagoQrState();
}

enum _Fase { cargando, esperando, pagado, problema }

class _PagoQrState extends ConsumerState<PagoQrScreen> {
  _Fase _fase = _Fase.cargando;
  PagoQr? _pago;
  String? _error;

  /// Nota del cobro en revisión: con PAGADO_FUERA_DE_PLAZO se muestra la
  /// tarjeta con el WhatsApp en vez del cartel genérico.
  String? _nota;
  Timer? _consulta;
  bool _consultando = false;

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
    _consulta?.cancel();
    setState(() {
      _fase = _Fase.cargando;
      _error = null;
      _nota = null;
    });
    try {
      final p = PagoQr.desde(
        await ref.read(repoProvider).qrDePago(widget.orden, tipo: widget.tipo),
      );
      if (!mounted) return;
      setState(() {
        _pago = p;
        if (p.estado == 'pagado') {
          _fase = _Fase.pagado;
          ref.invalidate(accesosProvider);
        } else if (p.estado == 'activo' && p.imagen != null) {
          _fase = _Fase.esperando;
        } else {
          _fase = _Fase.problema;
          _nota = p.estado == 'revisar' ? (p.nota ?? 'REVISION') : null;
          _error = p.estado == 'revisar'
              ? 'Este cobro necesita revisión. No vuelvas a pagar.'
              : 'Este QR no está disponible para pagar. Revisá tu pedido en Accesos.';
        }
      });
      if (_fase == _Fase.esperando) {
        _consulta = Timer.periodic(
          const Duration(seconds: 4),
          (_) => _revisar(),
        );
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
    if (_consultando) return;
    _consultando = true;
    try {
      final r = await ref
          .read(repoProvider)
          .estadoPago(widget.orden, tipo: widget.tipo);
      if (!mounted) return;
      if (r.estado == 'pagado' &&
          (r.orden == 'confirmada' ||
              widget.tipo == 'pedido' &&
                  [
                    'recibido',
                    'en_preparacion',
                    'listo',
                    'entregado',
                  ].contains(r.orden))) {
        _consulta?.cancel();
        HapticFeedback.heavyImpact();
        ref.invalidate(accesosProvider);
        ref.invalidate(pulseSaldoProvider);
        ref.invalidate(misMesasProvider);
        setState(() => _fase = _Fase.pagado);
      } else if (r.estado == 'anulado' ||
          r.estado == 'vencido' ||
          r.orden == 'vencida' ||
          r.orden == 'cancelada') {
        _consulta?.cancel();
        setState(() {
          _fase = _Fase.problema;
          _error =
              'Este QR ya no se puede pagar (el pedido venció o se canceló).';
        });
      } else if (r.estado == 'revisar') {
        _consulta?.cancel();
        ref.invalidate(accesosProvider);
        setState(() {
          _fase = _Fase.problema;
          _nota = r.nota ?? 'REVISION';
          _error =
              'Este cobro necesita revisión. No vuelvas a pagar; contactá al boliche con tu pedido.';
        });
      }
    } catch (_) {
      // sin señal un rato: se vuelve a intentar en la próxima vuelta
    } finally {
      _consultando = false;
    }
  }

  Future<void> _guardar() async {
    final img = _pago?.imagen;
    if (img == null) return;
    await SharePlus.instance.share(
      ShareParams(
        files: [
          XFile.fromData(img, mimeType: 'image/png', name: 'qr-pago-aftr.png'),
        ],
        text: 'QR de pago · ${widget.titulo}',
      ),
    );
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
          _Fase.cargando => const Center(
            key: ValueKey('c'),
            child: CircularProgressIndicator(color: Aftr.texto),
          ),
          _Fase.pagado => _Pagado(
            key: const ValueKey('p'),
            titulo: widget.titulo,
            tipo: widget.tipo,
          ),
          // La plata entró y no entregó nada: no alcanza con "necesita
          // revisión", hay que decir qué pasó y cómo se resuelve.
          _Fase.problema => _nota != null
              ? SingleChildScrollView(
                  key: const ValueKey('r'),
                  padding: const EdgeInsets.fromLTRB(20, 24, 20, 24),
                  child: AvisoPagoTarde(
                    monto: (_pago?.monto ?? 0).round(),
                    tarde: _nota == 'PAGADO_FUERA_DE_PLAZO',
                    evento: widget.titulo,
                  ),
                )
              : _Problema(
                  key: const ValueKey('x'),
                  texto: _error ?? '',
                  onReintentar: _pedirQr,
                ),
          _Fase.esperando => ListView(
            key: const ValueKey('e'),
            padding: EdgeInsets.fromLTRB(24, 8, 24, 24 + abajo),
            children: [
              Aparecer(
                child: Text(
                  widget.titulo,
                  textAlign: TextAlign.center,
                  style: Aftr.cuerpo(15),
                ),
              ),
              const SizedBox(height: 6),
              Aparecer(
                orden: 1,
                child: Text(
                  'Bs ${(_pago?.monto ?? 0).toStringAsFixed(2)}',
                  textAlign: TextAlign.center,
                  style: Aftr.titular(44),
                ),
              ),
              const SizedBox(height: 22),
              Aparecer(
                orden: 2,
                child: Center(
                  child: Container(
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(28),
                    ),
                    child: _pago?.imagen != null
                        ? Image.memory(
                            _pago!.imagen!,
                            width: 250,
                            height: 250,
                            filterQuality: FilterQuality.none,
                            gaplessPlayback: true,
                          )
                        : const SizedBox(width: 250, height: 250),
                  ),
                ),
              ),
              const SizedBox(height: 22),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const PuntoVivo(color: Aftr.acento, tam: 7),
                  const SizedBox(width: 8),
                  Text(
                    'Esperando el pago',
                    style: Aftr.cuerpo(15, c: Aftr.texto),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                'Escanealo con la app de cualquier banco. Si estás en este celular, guardalo y subilo desde tu banco. '
                'Apenas el banco confirma, tu entrada aparece en Accesos.',
                textAlign: TextAlign.center,
                style: Aftr.cuerpo(13.5),
              ),
              if (_pago?.limite != null || _pago?.vence != null) ...[
                const SizedBox(height: 6),
                Text(
                  _pago?.limite != null
                      ? 'Se puede pagar hasta las ${_hhmm(_pago!.limite!)}. '
                            'Después se anula y hay que pedir otro QR.'
                      : 'Vale hasta el ${_pago!.vence}',
                  textAlign: TextAlign.center,
                  style: Aftr.cuerpo(12.5, c: Aftr.texto3),
                ),
              ],
              const SizedBox(height: 24),
              BotonAftr('Guardar QR', onTap: _guardar),
              TextButton(
                onPressed: () async {
                  try {
                    await ref.read(pulseRepoProvider).rpc(
                      'aftr_cancelar_cobro',
                      {'p_tipo': widget.tipo, 'p_id': widget.orden},
                    );
                    if (context.mounted) {
                      avisar(
                        context,
                        'Cancelación solicitada. Esperá la confirmación bancaria antes de volver a pagar.',
                      );
                    }
                  } catch (e) {
                    if (context.mounted) avisar(context, mensajeDeError(e));
                  }
                },
                child: const Text('Solicitar cancelación del QR'),
              ),
              const SizedBox(height: 10),
              Text(
                'Cobro procesado por Banco Económico',
                textAlign: TextAlign.center,
                style: Aftr.cuerpo(12, c: Aftr.texto3),
              ),
            ],
          ),
        },
      ),
    );
  }
}

class _Pagado extends StatelessWidget {
  const _Pagado({super.key, required this.titulo, required this.tipo});
  final String titulo;
  final String tipo;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(28),
    child: Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        TweenAnimationBuilder<double>(
          tween: Tween(begin: 0.6, end: 1),
          duration: Aftr.medio,
          curve: Curves.elasticOut,
          builder: (_, v, c) => Transform.scale(scale: v, child: c),
          child: Container(
            width: 92,
            height: 92,
            decoration: const BoxDecoration(
              color: Aftr.vivo,
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.check_rounded,
              color: Colors.black,
              size: 54,
            ),
          ),
        ),
        const SizedBox(height: 24),
        Text('Pago confirmado', style: Aftr.titular(34)),
        const SizedBox(height: 8),
        Text(
          tipo == 'recarga'
              ? 'El banco confirmó tu recarga. Tu saldo PULSE ya está disponible.'
              : tipo == 'pedido'
              ? 'Tu pedido está pagado y fue recibido por la barra.'
              : 'El banco confirmó tu pago. Tus accesos para $titulo ya están disponibles.',
          textAlign: TextAlign.center,
          style: Aftr.cuerpo(15, c: Aftr.texto),
        ),
        const SizedBox(height: 28),
        BotonAftr(
          tipo == 'orden' ? 'Ver mis accesos' : 'Volver',
          onTap: () {
            Navigator.of(context).pop();
            if (tipo == 'orden') GoRouter.of(context).go('/accesos');
          },
        ),
      ],
    ),
  );
}

class _Problema extends StatelessWidget {
  const _Problema({super.key, required this.texto, required this.onReintentar});
  final String texto;
  final VoidCallback onReintentar;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(28),
    child: Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const Icon(Icons.qr_code_2_rounded, color: Aftr.texto3, size: 56),
        const SizedBox(height: 18),
        Text(
          'No pudimos mostrar el QR',
          textAlign: TextAlign.center,
          style: Aftr.fuerte(20),
        ),
        const SizedBox(height: 8),
        Text(
          texto,
          textAlign: TextAlign.center,
          style: Aftr.cuerpo(14, c: Aftr.texto),
        ),
        const SizedBox(height: 8),
        Text(
          'Tu pedido quedó guardado en Accesos.',
          textAlign: TextAlign.center,
          style: Aftr.cuerpo(13),
        ),
        const SizedBox(height: 24),
        BotonAftr('Reintentar', onTap: onReintentar),
      ],
    ),
  );
}

String _hhmm(DateTime t) =>
    '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

/// Mensaje claro para errores del cobro (sin detalles técnicos del banco).
String mensajeDePago(Object e) {
  final s = '$e';
  if (s.contains('no habilitado')) {
    return 'El cobro con QR todavía no está habilitado por el banco.';
  }
  if (s.contains('Iniciá sesión')) return 'Iniciá sesión para pagar.';
  return mensajeDeError(e);
}

/// QR de pago tal como lo devuelve el servidor.
class PagoQr {
  const PagoQr({required this.estado, this.monto, this.vence, this.imagen, this.nota, this.limite});
  final String estado;
  final num? monto;
  final String? vence;
  final Uint8List? imagen;

  /// Por qué quedó en revisión: PAGADO_FUERA_DE_PLAZO y compañía.
  final String? nota;

  /// Cuando el banco deja de cobrarlo: diez minutos desde que se generó.
  final DateTime? limite;

  factory PagoQr.desde(Map<String, dynamic> j) {
    final img = j['imagen'] as String?;
    return PagoQr(
      estado: j['estado'] as String? ?? 'activo',
      monto: j['monto'] is num
          ? j['monto'] as num
          : num.tryParse('${j['monto']}'),
      vence: j['vence'] as String?,
      nota: j['nota'] as String?,
      limite: DateTime.tryParse('${j['limite'] ?? ''}')?.toLocal(),
      imagen: img == null || img.isEmpty
          ? null
          : base64Decode(
              img.startsWith('data:')
                  ? img.substring(img.indexOf(',') + 1)
                  : img,
            ),
    );
  }
}
