import '../../core/networking/supabase.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/theme/aftr_theme.dart';
import '../../core/widgets/piezas.dart';
import '../../data/aftr_repo.dart';
import '../../data/pulse_repo.dart';
import '../evento/pago_qr.dart';

class PulseScreen extends ConsumerStatefulWidget {
  const PulseScreen({super.key});
  @override
  ConsumerState<PulseScreen> createState() => _PulseState();
}

class _PulseState extends ConsumerState<PulseScreen> {
  final _importe = TextEditingController();
  String? _clave;
  bool _ocupado = false;
  @override
  void dispose() {
    _importe.dispose();
    super.dispose();
  }

  Future<void> _recargar() async {
    final n = centavosDe(_importe.text);
    if (n == null || n < 100) {
      avisar(
        context,
        'Ingresá un importe desde Bs 1, con hasta dos decimales.',
      );
      return;
    }
    setState(() => _ocupado = true);
    try {
      final r = await ref
          .read(pulseRepoProvider)
          .recargar(n, _clave ??= nuevaOperacion());
      if (!mounted) return;
      _clave = null;
      await abrirPagoQr(
        context,
        orden: r['id'] as String,
        titulo: 'Recarga PULSE',
        tipo: 'recarga',
      );
      ref.invalidate(pulseSaldoProvider);
    } catch (e) {
      if (mounted) avisar(context, mensajeDeError(e));
    } finally {
      if (mounted) setState(() => _ocupado = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final saldo = ref.watch(pulseSaldoProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('PULSE')),
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(pulseSaldoProvider);
          await ref.read(pulseSaldoProvider.future);
        },
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            Text('AFTR WALLET', style: Aftr.etiqueta()),
            const SizedBox(height: 18),
            saldo.when(
              data: (s) => Text(
                importePulse(s['saldo_centavos']),
                style: Aftr.titular(64),
              ),
              loading: () => const LinearProgressIndicator(),
              error: (e, _) => Text(mensajeDeError(e)),
            ),
            Text('PULSE', style: Aftr.cuerpo(16, c: Aftr.texto)),
            const SizedBox(height: 8),
            Text('1 PULSE = Bs 1', style: Aftr.cuerpo(14)),
            const SizedBox(height: 32),
            TextField(
              controller: _importe,
              enabled: !_ocupado,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: const InputDecoration(
                labelText: 'Importe en Bs',
                hintText: '100.00',
                // El tope se decide en el servidor; acá se dice antes, para no
                // mandar a alguien a generar un QR que no va a poder pagar.
                helperText: 'Hasta Bs 300 por semana',
              ),
            ),
            const SizedBox(height: 16),
            BotonAftr(
              _ocupado ? 'Preparando…' : 'Recargar con QR',
              onTap: _ocupado ? null : _recargar,
            ),
            const SizedBox(height: 30),
            for (final r in (saldo.value?['recargas'] as List? ?? []))
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(
                  'Recarga · ${importePulse(r['importe_centavos'])} PULSE',
                ),
                subtitle: const Text('Pendiente de pago'),
                onTap: () async {
                  await abrirPagoQr(
                    context,
                    orden: r['id'] as String,
                    titulo: 'Recarga PULSE',
                    tipo: 'recarga',
                  );
                  ref.invalidate(pulseSaldoProvider);
                },
              ),
            Text('Movimientos', style: Aftr.fuerte(22)),
            const SizedBox(height: 12),
            if ((saldo.value?['movimientos'] as List? ?? []).isEmpty)
              Text('Todavía no tenés movimientos.', style: Aftr.cuerpo(14)),
            for (final m in (saldo.value?['movimientos'] as List? ?? []))
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text('${m['concepto']}'),
                subtitle: Text(
                  '${m['created_at']}'.split('.').first.replaceFirst('T', ' '),
                ),
                trailing: Text(
                  '${(m['importe_centavos'] as num) > 0 ? '+' : ''}${importePulse(m['importe_centavos'])}',
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Dos acciones explícitas, sin chips ni controles de estado decorativos.
Future<void> elegirPago(
  BuildContext context,
  WidgetRef ref, {
  required String orden,
  required String titulo,
}) async {
  await showModalBottomSheet<void>(
    context: context,
    useRootNavigator: true,
    isScrollControlled: true,
    builder: (ctx) => _ElegirPago(orden: orden, titulo: titulo),
  );
}

class _ElegirPago extends ConsumerStatefulWidget {
  const _ElegirPago({required this.orden, required this.titulo});
  final String orden, titulo;
  @override
  ConsumerState<_ElegirPago> createState() => _ElegirPagoState();
}

class _ElegirPagoState extends ConsumerState<_ElegirPago> {
  bool ocupado = false;
  @override
  Widget build(BuildContext context) {
    final saldo = ref.watch(pulseSaldoProvider);
    // Quien compró sin cuenta no tiene PULSE: el saldo es plata y vive en la
    // cuenta, no en el teléfono. Para ese caso queda el QR del banco, que es
    // lo que vino a hacer.
    final conCuenta = ref.watch(conCuentaProvider);
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(widget.titulo, style: Aftr.fuerte(24)),
            const SizedBox(height: 12),
            Text(
              !conCuenta
                  ? 'Pagá con el QR de tu banco. Tu entrada queda en Accesos.'
                  : saldo.hasValue
                  ? 'Tu saldo: ${importePulse(saldo.value!['saldo_centavos'])} PULSE'
                  : 'Tu saldo se verifica al pagar.',
              style: Aftr.cuerpo(15),
            ),
            const SizedBox(height: 24),
            if (conCuenta) BotonAftr(
              ocupado ? 'Procesando…' : 'Pagar con PULSE',
              onTap: ocupado
                  ? null
                  : () async {
                      setState(() => ocupado = true);
                      try {
                        await ref
                            .read(pulseRepoProvider)
                            .pagarOrden(widget.orden);
                        ref.invalidate(pulseSaldoProvider);
                        ref.invalidate(accesosProvider);
                        ref.invalidate(misMesasProvider);
                        if (context.mounted) {
                          Navigator.pop(context);
                          avisar(
                            context,
                            'Compra confirmada. Revisá tus accesos.',
                          );
                        }
                      } catch (e) {
                        if (context.mounted) avisar(context, mensajeDeError(e));
                      } finally {
                        if (mounted) setState(() => ocupado = false);
                      }
                    },
            ),
            if (conCuenta) const SizedBox(height: 12),
            BotonAftr(
              'Pagar con QR',
              secundario: !conCuenta ? false : true,
              onTap: ocupado
                  ? null
                  : () async {
                      await abrirPagoQr(
                        context,
                        orden: widget.orden,
                        titulo: widget.titulo,
                      );
                    },
            ),
            TextButton(
              onPressed: ocupado
                  ? null
                  : () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => const PulseScreen(),
                      ),
                    ),
              child: const Text('Recargar PULSE'),
            ),
          ],
        ),
      ),
    );
  }
}
