import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../../core/networking/supabase.dart';
import '../../../core/sync/tiempo_real.dart';
import '../../../core/theme/venue_theme.dart';
import '../../../core/widgets/avisos.dart';
import '../../../core/widgets/estado_vista.dart';
import '../../events/data/eventos.dart';
import '../data/puerta_repository.dart';
import '../data/qr.dart';
import '../data/resultado.dart';
import 'veredicto_card.dart';

class _Registro {
  _Registro(this.resultado) : cuando = DateTime.now();
  final ResultadoEscaneo resultado;
  final DateTime cuando;
}

/// Escáner de puerta: cámara nativa, linterna, resultado inmediato, ingreso
/// manual del código y los últimos escaneos del turno.
class EscanerScreen extends ConsumerStatefulWidget {
  const EscanerScreen({super.key});

  @override
  ConsumerState<EscanerScreen> createState() => _EscanerScreenState();
}

class _EscanerScreenState extends ConsumerState<EscanerScreen> {
  final _camara = MobileScannerController(
    detectionSpeed: DetectionSpeed.noDuplicates,
    formats: const [BarcodeFormat.qrCode],
  );
  final _codigo = TextEditingController();
  final _historial = <_Registro>[];

  ResultadoEscaneo? _ultimo;
  bool _validando = false;

  /// Modo filtro: el QR se rechaza SIN consumirse y queda marcado "no pasó
  /// el filtro" (con el relacionador que lo trajo). Las entradas de la casa
  /// no se filtran: siguen de largo y se validan normalmente.
  bool _modoFiltro = false;
  bool _ultimoMarcado = false;
  String? _ultimoCrudo;
  DateTime _ultimoEn = DateTime.fromMillisecondsSinceEpoch(0);

  @override
  void dispose() {
    _camara.dispose();
    _codigo.dispose();
    super.dispose();
  }

  Future<void> _validar(String crudo) async {
    final evento = ref.read(eventoActivoProvider);
    if (evento == null || _validando) return;

    // La cámara ve el mismo QR varias veces por segundo mientras la persona
    // lo sostiene: sin esta pausa el segundo cuadro mostraría "YA INGRESÓ"
    // encima del "PASA" que acaba de salir.
    final ahora = DateTime.now();
    if (crudo == _ultimoCrudo &&
        ahora.difference(_ultimoEn) < const Duration(seconds: 4)) {
      return;
    }
    _ultimoCrudo = crudo;
    _ultimoEn = ahora;

    setState(() => _validando = true);
    final repo = ref.read(puertaRepositoryProvider);
    ResultadoEscaneo? r;
    final qr = QrLeido.interpretar(crudo);
    if (_modoFiltro && qr != null && !qr.esDeOtroEvento(evento.id)) {
      try {
        final f = await repo.marcarFiltroQr(eventoId: evento.id, qr: qr);
        if (f['resultado'] != 'protegida') {
          // Se muestra igual que un código inválido, a propósito: quien
          // mira la pantalla no distingue un filtrado de un QR falso.
          r = ResultadoEscaneo(
            veredicto: Veredicto.noValido,
            codigo: qr.codigo,
            detalle: '#${qr.codigo} no existe para este evento.',
          );
        }
      } catch (e) {
        r = ResultadoEscaneo(
          veredicto: esFallaDeRed(e) ? Veredicto.sinConexion : Veredicto.noValido,
          codigo: qr.codigo,
          detalle: mensajeDeError(e),
        );
      }
    }
    final res = r ?? await repo.validar(eventoId: evento.id, crudo: crudo);
    if (!mounted) return;
    _ultimoMarcado = false;

    if (res.veredicto.dejaPasar) {
      HapticFeedback.mediumImpact();
      SystemSound.play(SystemSoundType.click);
    } else {
      HapticFeedback.heavyImpact();
      Future.delayed(const Duration(milliseconds: 140), HapticFeedback.heavyImpact);
    }
    setState(() {
      _validando = false;
      _ultimo = res;
      _historial.insert(0, _Registro(res));
      if (_historial.length > 30) _historial.removeLast();
    });
    if (res.veredicto != Veredicto.sinConexion) {
      ref.invalidate(aforoProvider(evento.id));
    }
  }

  /// Bandera sobre el último QR de entrada: "no pasó el control".
  Future<void> _alternarBandera() async {
    final evento = ref.read(eventoActivoProvider);
    final u = _ultimo;
    if (evento == null || u == null || u.codigo.isEmpty) return;
    try {
      final f = await ref.read(puertaRepositoryProvider).marcarFiltroQr(
          eventoId: evento.id, qr: QrLeido(codigo: u.codigo, esLista: false));
      if (!mounted) return;
      if (f['resultado'] != 'ok') {
        avisar(context, 'No se encontró la entrada', tipo: TipoAviso.aviso);
        return;
      }
      final marcado = f['marcado'] == true;
      setState(() => _ultimoMarcado = marcado);
      avisar(
        context,
        marcado
            ? '${f['nombre']} marcado · lo vendió ${f['rrpp']}'
            : 'Marca quitada a ${f['nombre']}',
        tipo: marcado ? TipoAviso.aviso : TipoAviso.ok,
      );
    } catch (e) {
      if (mounted) avisar(context, mensajeDeError(e), tipo: TipoAviso.aviso);
    }
  }

  void _validarManual() {
    final t = _codigo.text.trim();
    if (t.isEmpty) return;
    FocusScope.of(context).unfocus();
    _ultimoCrudo = null; // un código tipeado siempre se valida
    _validar(t);
    _codigo.clear();
  }

  @override
  Widget build(BuildContext context) {
    final evento = ref.watch(eventoActivoProvider);
    final eventos = ref.watch(eventosProvider);

    if (evento == null) {
      return VistaAsync(
        valor: eventos,
        reintentar: () => ref.invalidate(eventosProvider),
        datos: (_) => const MensajeVista(
          icono: Icons.event_busy_rounded,
          titulo: 'No hay evento activo',
          detalle: 'Cuando haya un evento abierto en este boliche vas a poder escanear.',
        ),
      );
    }

    ref.listen(cambiosEventoProvider(evento.id), (_, c) {
      if (c.value?.any(const {'entradas', 'registros'}.contains) ?? false) {
        ref.invalidate(aforoProvider(evento.id));
      }
    });
    final aforo = ref.watch(aforoProvider(evento.id));
    final color = _ultimo == null ? null : colorDeVeredicto(_ultimo!.veredicto);

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                '${evento.nombre} · ${evento.fechaCorta}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  color: VenueColors.textoSuave,
                ),
              ),
            ),
            aforo.maybeWhen(
              data: (a) => Text(
                '${a.ingresaron} adentro · ${a.pendientes} por llegar',
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              orElse: () => const SizedBox.shrink(),
            ),
          ],
        ),
        const SizedBox(height: 10),
        AspectRatio(
          aspectRatio: 1,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(20),
            child: Stack(
              fit: StackFit.expand,
              children: [
                MobileScanner(
                  controller: _camara,
                  onDetect: (captura) {
                    final v = captura.barcodes.firstOrNull?.rawValue;
                    if (v != null) _validar(v);
                  },
                  errorBuilder: (context, error) => MensajeVista(
                    icono: Icons.no_photography_outlined,
                    titulo: 'No se pudo abrir la cámara',
                    detalle: error.errorCode ==
                            MobileScannerErrorCode.permissionDenied
                        ? 'Dale permiso de cámara a Venue en Ajustes. Mientras tanto podés escribir el código abajo.'
                        : 'Podés escribir el código abajo.',
                  ),
                ),
                // Marco: toma el color del último veredicto para que se vea
                // de reojo, sin bajar la vista a la tarjeta.
                IgnorePointer(
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    margin: const EdgeInsets.all(26),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(
                        color: color ?? Colors.white70,
                        width: color == null ? 2 : 5,
                      ),
                    ),
                  ),
                ),
                if (_validando)
                  const ColoredBox(
                    color: Colors.black54,
                    child: Center(child: CircularProgressIndicator()),
                  ),
                Positioned(
                  left: 12,
                  bottom: 12,
                  child: IconButton.filled(
                    tooltip: _modoFiltro
                        ? 'Modo filtro activado'
                        : 'Modo filtro: rechaza sin consumir la entrada',
                    iconSize: 28,
                    style: IconButton.styleFrom(
                      backgroundColor:
                          _modoFiltro ? VenueColors.mal : Colors.black54,
                      foregroundColor: Colors.white,
                      minimumSize: const Size(56, 56),
                    ),
                    onPressed: () {
                      setState(() => _modoFiltro = !_modoFiltro);
                      avisar(
                        context,
                        _modoFiltro
                            ? 'Modo filtro: los QR se rechazan sin consumirse'
                            : 'Modo filtro apagado',
                        tipo: _modoFiltro ? TipoAviso.aviso : TipoAviso.ok,
                      );
                    },
                    icon: const Icon(Icons.bolt_rounded),
                  ),
                ),
                Positioned(
                  right: 12,
                  bottom: 12,
                  child: ValueListenableBuilder(
                    valueListenable: _camara,
                    builder: (context, estado, _) {
                      if (estado.torchState == TorchState.unavailable) {
                        return const SizedBox.shrink();
                      }
                      final on = estado.torchState == TorchState.on;
                      return IconButton.filled(
                        tooltip: on ? 'Apagar linterna' : 'Encender linterna',
                        iconSize: 28,
                        style: IconButton.styleFrom(
                          backgroundColor: on ? VenueColors.aviso : Colors.black54,
                          foregroundColor: on ? Colors.black : Colors.white,
                          minimumSize: const Size(56, 56),
                        ),
                        onPressed: _camara.toggleTorch,
                        icon: Icon(on
                            ? Icons.flashlight_on_rounded
                            : Icons.flashlight_off_rounded),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        if (_ultimo != null) ...[
          VeredictoCard(resultado: _ultimo!),
          // La bandera vale para entradas con QR que el servidor reconoció.
          if (const {Veredicto.pasa, Veredicto.yaIngreso}
                  .contains(_ultimo!.veredicto) &&
              !(_ultimo!.tipo?.contains('casa') ?? false))
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: _alternarBandera,
                icon: Icon(_ultimoMarcado
                    ? Icons.flag_rounded
                    : Icons.flag_outlined),
                label: Text(_ultimoMarcado
                    ? 'Marcado: no pasó el control'
                    : 'Marcar: no pasó el control'),
                style: TextButton.styleFrom(
                  foregroundColor:
                      _ultimoMarcado ? VenueColors.mal : VenueColors.textoSuave,
                ),
              ),
            ),
        ] else
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 14),
            child: Text(
              'Apuntá al QR de la entrada',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 16, color: VenueColors.textoSuave),
            ),
          ),
        const SizedBox(height: 14),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _codigo,
                autocorrect: false,
                enableSuggestions: false,
                textCapitalization: TextCapitalization.characters,
                textInputAction: TextInputAction.go,
                onSubmitted: (_) => _validarManual(),
                decoration: const InputDecoration(
                  labelText: 'O escribí el código',
                  hintText: 'A2F9B1',
                ),
              ),
            ),
            const SizedBox(width: 10),
            SizedBox(
              width: 112,
              child: FilledButton(
                onPressed: _validando ? null : _validarManual,
                child: const Text('Validar'),
              ),
            ),
          ],
        ),
        if (_historial.isNotEmpty) ...[
          const SizedBox(height: 22),
          const Text(
            'Últimos escaneos',
            style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
          ),
          const SizedBox(height: 6),
          for (final h in _historial)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 7),
              child: Row(
                children: [
                  Container(
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(
                      color: colorDeVeredicto(h.resultado.veredicto),
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      h.resultado.nombre ?? h.resultado.veredicto.texto,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Text(
                    '#${h.resultado.codigo}',
                    style: const TextStyle(
                      color: VenueColors.textoSuave,
                      fontFeatures: [FontFeature.tabularFigures()],
                    ),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    '${h.cuando.hour.toString().padLeft(2, '0')}:${h.cuando.minute.toString().padLeft(2, '0')}',
                    style: const TextStyle(color: VenueColors.textoSuave),
                  ),
                ],
              ),
            ),
        ],
      ],
    );
  }
}
