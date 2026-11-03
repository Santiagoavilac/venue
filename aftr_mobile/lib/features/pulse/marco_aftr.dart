import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/networking/supabase.dart';
import '../../core/routing/router.dart';
import '../../core/theme/aftr_theme.dart';
import '../../data/aftr_repo.dart';
import '../../data/pulse_repo.dart';
import '../guia/guia.dart';

/// El saldo ocupa una línea propia, incluso en un evento o en el checkout.
class MarcoAftr extends ConsumerStatefulWidget {
  const MarcoAftr({super.key, required this.child, required this.iniciado});
  final Widget child;
  final bool iniciado;
  @override
  ConsumerState<MarcoAftr> createState() => _MarcoAftrState();
}

class _MarcoAftrState extends ConsumerState<MarcoAftr>
    with WidgetsBindingObserver {
  String? _comprobado;
  String? _guiaUid;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      ref.invalidate(pulseSaldoProvider);
      ref.invalidate(perfilProvider);
    }
  }

  Future<void> _comprobar() async {
    final uid = ref.read(usuarioIdProvider);
    if (!widget.iniciado ||
        uid == null ||
        ref.read(perfilProvider).value == null ||
        _comprobado == uid) {
      return;
    }
    _comprobado = uid;
    try {
      if (!await guiaVista(uid) &&
          mounted &&
          ref.read(usuarioIdProvider) == uid) {
        setState(() => _guiaUid = uid);
      }
    } catch (_) {
      /* La guía se puede abrir desde Cuenta si falla el almacenamiento local. */
    }
  }

  void _terminar() {
    final uid = _guiaUid;
    setState(() => _guiaUid = null);
    if (uid != null) guardarGuiaVista(uid).catchError((_) {});
  }

  @override
  Widget build(BuildContext context) {
    final uid = ref.watch(usuarioIdProvider);
    final perfil = ref.watch(perfilProvider).value;
    final conCuenta = uid != null && perfil != null && perfil.id == uid;
    final saldo = conCuenta ? ref.watch(pulseSaldoProvider) : null;
    ref.listen(pedidoGuiaProvider, (_, _) {
      if (conCuenta) setState(() => _guiaUid = uid);
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _comprobar();
    });
    final router = ref.read(routerProvider);
    return Stack(
      children: [
        Column(
          children: [
            if (conCuenta)
              Material(
                color: Aftr.fondo,
                child: SafeArea(
                  bottom: false,
                  child: InkWell(
                    key: pulseGuia,
                    onTap: () {
                      if (router.routeInformationProvider.value.uri.path !=
                          '/pulse') {
                        router.push('/pulse');
                      }
                    },
                    child: Container(
                      constraints: const BoxConstraints(minHeight: 36),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 7,
                      ),
                      decoration: const BoxDecoration(
                        border: Border(bottom: BorderSide(color: Aftr.borde)),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          Flexible(
                            child: Text(
                              saldo!.when(
                                data: (s) =>
                                    '${importePulse(s['saldo_centavos'])} PULSE',
                                loading: () => 'PULSE · …',
                                error: (_, _) => 'PULSE · Reintentar',
                              ),
                              style: Aftr.cuerpo(
                                13,
                                c: Aftr.texto,
                                w: FontWeight.w600,
                              ),
                            ),
                          ),
                          const SizedBox(width: 7),
                          const Icon(
                            Icons.north_east,
                            size: 13,
                            color: Aftr.texto3,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            Expanded(
              child: conCuenta
                  ? MediaQuery.removePadding(
                      context: context,
                      removeTop: true,
                      child: widget.child,
                    )
                  : widget.child,
            ),
          ],
        ),
        if (conCuenta && _guiaUid == uid)
          Positioned.fill(
            child: GuiaAftr(
              alTerminar: _terminar,
              alMostrar: (ruta) => router.go(ruta),
            ),
          ),
      ],
    );
  }
}
