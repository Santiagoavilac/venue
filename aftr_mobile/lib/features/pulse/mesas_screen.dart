import '../../core/networking/supabase.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/theme/aftr_theme.dart';
import '../../core/widgets/piezas.dart';
import '../../data/pulse_repo.dart';
import '../evento/pago_qr.dart';
import 'pulse_screen.dart';

class MisMesasScreen extends ConsumerWidget {
  const MisMesasScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) => Scaffold(
    appBar: AppBar(title: const Text('Mis mesas')),
    body: ref
        .watch(misMesasProvider)
        .when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => Center(
            child: TextButton(
              onPressed: () => ref.invalidate(misMesasProvider),
              child: Text('${mensajeDeError(e)} · Reintentar'),
            ),
          ),
          data: (d) => RefreshIndicator(
            onRefresh: () async {
              ref.invalidate(misMesasProvider);
              await ref.read(misMesasProvider.future);
            },
            child: ListView(
              padding: const EdgeInsets.all(24),
              children: [
                if ((d['mesas'] as List).isEmpty)
                  Text(
                    'Tus mesas e invitaciones aparecerán acá.',
                    style: Aftr.cuerpo(16),
                  ),
                for (final m in d['mesas'] as List)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 24),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('${m['etiqueta']}', style: Aftr.titular(32)),
                        const SizedBox(height: 6),
                        Text(
                          '${m['evento']} · ${m['club']}\n${m['fecha']} · Planta ${m['planta']}',
                          style: Aftr.cuerpo(14),
                        ),
                        const SizedBox(height: 12),
                        if (m['mi_estado'] == 'invitado')
                          Row(
                            children: [
                              TextButton(
                                onPressed: () async {
                                  try {
                                    await ref.read(pulseRepoProvider).rpc(
                                      'aftr_mesa_responder',
                                      {'p_mesa': m['id'], 'p_aceptar': true},
                                    );
                                    ref.invalidate(misMesasProvider);
                                  } catch (e) {
                                    if (context.mounted) {
                                      avisar(context, mensajeDeError(e));
                                    }
                                  }
                                },
                                child: const Text('Aceptar invitación'),
                              ),
                              TextButton(
                                onPressed: () async {
                                  try {
                                    await ref.read(pulseRepoProvider).rpc(
                                      'aftr_mesa_responder',
                                      {'p_mesa': m['id'], 'p_aceptar': false},
                                    );
                                    ref.invalidate(misMesasProvider);
                                  } catch (e) {
                                    if (context.mounted) {
                                      avisar(context, mensajeDeError(e));
                                    }
                                  }
                                },
                                child: const Text('Declinar'),
                              ),
                            ],
                          )
                        else
                          BotonAftr(
                            'Ver mi mesa',
                            secundario: true,
                            onTap: () => Navigator.of(context).push(
                              MaterialPageRoute<void>(
                                builder: (_) => MesaAftrScreen(
                                  mesa: Map<String, dynamic>.from(m as Map),
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                if ((d['avisos'] as List).isNotEmpty) ...[
                  Text('Novedades', style: Aftr.fuerte(22)),
                  const SizedBox(height: 12),
                  for (final a in (d['avisos'] as List).take(10))
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Text('${a['texto']}', style: Aftr.cuerpo(14)),
                    ),
                ],
              ],
            ),
          ),
        ),
  );
}

class MesaAftrScreen extends ConsumerStatefulWidget {
  const MesaAftrScreen({super.key, required this.mesa});
  final DatosPulse mesa;
  @override
  ConsumerState<MesaAftrScreen> createState() => _MesaState();
}

class _MesaState extends ConsumerState<MesaAftrScreen> {
  final _carrito = <String, int>{};
  final _buscar = TextEditingController(), _nota = TextEditingController();
  String? _clave;
  bool _ocupado = false;
  String get id => widget.mesa['id'] as String;
  @override
  void dispose() {
    _buscar.dispose();
    _nota.dispose();
    super.dispose();
  }

  Future<void> _invitar() async {
    final usuario = TextEditingController();
    final nombre = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Invitar a mi mesa'),
        content: TextField(
          controller: usuario,
          decoration: const InputDecoration(labelText: 'Usuario AFTR sin @'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, usuario.text.trim()),
            child: const Text('Invitar'),
          ),
        ],
      ),
    );
    usuario.dispose();
    if (nombre == null || nombre.isEmpty) return;
    try {
      await ref.read(pulseRepoProvider).rpc('aftr_mesa_invitar', {
        'p_mesa': id,
        'p_usuario': nombre,
      });
      ref.invalidate(misMesasProvider);
      if (mounted) avisar(context, 'Invitación enviada.');
    } catch (e) {
      if (mounted) avisar(context, mensajeDeError(e));
    }
  }

  Future<void> _comprar(String metodo) async {
    if (_ocupado || _carrito.isEmpty) return;
    setState(() => _ocupado = true);
    try {
      final p = await ref
          .read(pulseRepoProvider)
          .pedir(
            id,
            [
              for (final x in _carrito.entries)
                {
                  'trago_id': x.key,
                  'qty': x.value,
                  'revision':
                      (ref.read(cartaMesaProvider(id)).value?['productos']
                                  as List? ??
                              [])
                          .where((p) => p['id'] == x.key)
                          .firstOrNull?['revision'],
                },
            ],
            metodo,
            _clave ??= nuevaOperacion(),
            _nota.text,
          );
      _clave = null;
      _carrito.clear();
      _nota.clear();
      ref.invalidate(pulseSaldoProvider);
      ref.invalidate(pedidosMesaProvider(id));
      ref.invalidate(cartaMesaProvider(id));
      if (!mounted) return;
      if (metodo == 'qr') {
        await abrirPagoQr(
          context,
          orden: p['id'] as String,
          titulo: 'Pedido · ${widget.mesa['etiqueta']}',
          tipo: 'pedido',
        );
      } else {
        avisar(context, 'Pedido pagado y recibido por la barra.');
      }
    } catch (e) {
      ref.invalidate(cartaMesaProvider(id));
      if (mounted) avisar(context, mensajeDeError(e));
    } finally {
      if (mounted) setState(() => _ocupado = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final carta = ref.watch(cartaMesaProvider(id));
    final pedidos = ref.watch(pedidosMesaProvider(id));
    final mesa =
        (ref.watch(misMesasProvider).value?['mesas'] as List? ?? [])
            .where((m) => m['id'] == id)
            .firstOrNull ??
        widget.mesa;
    final productos = (carta.value?['productos'] as List? ?? []);
    final visibles = productos
        .where(
          (p) => '${p['nombre']} ${p['categoria']}'.toLowerCase().contains(
            _buscar.text.toLowerCase(),
          ),
        )
        .toList();
    final total = productos.fold<int>(
      0,
      (n, p) =>
          n + (p['precio_centavos'] as num).toInt() * (_carrito[p['id']] ?? 0),
    );
    final abierto = carta.value?['abierto'] == true;
    return Scaffold(
      appBar: AppBar(title: Text('${mesa['etiqueta']}')),
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(cartaMesaProvider(id));
          ref.invalidate(pedidosMesaProvider(id));
          ref.invalidate(misMesasProvider);
        },
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            Text('${mesa['evento']}', style: Aftr.titular(34)),
            const SizedBox(height: 8),
            Text(
              '${mesa['club']} · Planta ${mesa['planta']}\nCapacidad: ${mesa['capacidad'] ?? 'por configurar'}',
              style: Aftr.cuerpo(14),
            ),
            if (mesa['titular'] == true) ...[
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton(
                  onPressed: _invitar,
                  child: const Text('Invitar a una cuenta AFTR'),
                ),
              ),
              for (final i in (mesa['miembros'] as List? ?? []))
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text('${i['nombre']}'),
                  subtitle: Text('${i['estado']}'),
                  trailing: TextButton(
                    child: const Text('Retirar'),
                    onPressed: () async {
                      try {
                        await ref.read(pulseRepoProvider).rpc(
                          'aftr_mesa_retirar',
                          {'p_mesa': id, 'p_cliente': i['cliente_id']},
                        );
                        ref.invalidate(misMesasProvider);
                      } catch (e) {
                        if (context.mounted) avisar(context, mensajeDeError(e));
                      }
                    },
                  ),
                ),
            ],
            const SizedBox(height: 26),
            Text('Carta', style: Aftr.fuerte(24)),
            const SizedBox(height: 8),
            Text(
              abierto
                  ? 'Pedidos disponibles'
                  : 'Pedidos no disponibles en este momento',
              style: Aftr.cuerpo(14),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _buscar,
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(
                labelText: 'Buscar bebidas o tragos',
                prefixIcon: Icon(Icons.search),
              ),
            ),
            const SizedBox(height: 20),
            if (carta.isLoading) const LinearProgressIndicator(),
            if (carta.hasError)
              TextButton(
                onPressed: () => ref.invalidate(cartaMesaProvider(id)),
                child: Text('${mensajeDeError(carta.error!)} · Reintentar'),
              ),
            if (!carta.isLoading && !carta.hasError && productos.isEmpty)
              Text(
                'El boliche todavía no publicó productos.',
                style: Aftr.cuerpo(14),
              ),
            LayoutBuilder(
              builder: (context, size) => Wrap(
                spacing: 16,
                runSpacing: 22,
                children: [
                  for (final p in visibles)
                    SizedBox(
                      width: (size.maxWidth - 16) / 2,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          AspectRatio(
                            aspectRatio: 1,
                            child: Container(
                              color: Aftr.superficie,
                              child: p['foto_url'] == null
                                  ? const Icon(Icons.local_bar_outlined)
                                  : Image.network(
                                      '${p['foto_url']}',
                                      fit: BoxFit.contain,
                                      errorBuilder: (_, _, _) =>
                                          const Icon(Icons.local_bar_outlined),
                                    ),
                            ),
                          ),
                          const SizedBox(height: 10),
                          Text('${p['nombre']}', style: Aftr.fuerte(16)),
                          const SizedBox(height: 4),
                          Text(
                            '${p['presentacion'] ?? ''}',
                            style: Aftr.cuerpo(12),
                          ),
                          Text(
                            'Bs ${importePulse(p['precio_centavos'])}',
                            style: Aftr.cuerpo(15, c: Aftr.texto),
                          ),
                          if ((p['disponibles'] as num) <= 0)
                            Text('Agotado', style: Aftr.cuerpo(12))
                          else
                            Row(
                              children: [
                                IconButton(
                                  onPressed: _ocupado
                                      ? null
                                      : () {
                                          setState(() {
                                            final n =
                                                (_carrito[p['id']] ?? 0) - 1;
                                            if (n <= 0) {
                                              _carrito.remove(p['id']);
                                            } else {
                                              _carrito[p['id'] as String] = n;
                                            }
                                            _clave = null;
                                          });
                                        },
                                  icon: const Icon(Icons.remove, size: 18),
                                ),
                                Text('${_carrito[p['id']] ?? 0}'),
                                IconButton(
                                  onPressed:
                                      !abierto ||
                                          _ocupado ||
                                          (_carrito[p['id']] ?? 0) >=
                                              (p['disponibles'] as num)
                                      ? null
                                      : () => setState(() {
                                          _carrito[p['id'] as String] =
                                              (_carrito[p['id']] ?? 0) + 1;
                                          _clave = null;
                                        }),
                                  icon: const Icon(Icons.add, size: 18),
                                ),
                              ],
                            ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
            if (_carrito.isNotEmpty) ...[
              const SizedBox(height: 28),
              Text('Total · Bs ${importePulse(total)}', style: Aftr.fuerte(24)),
              const SizedBox(height: 14),
              TextField(
                controller: _nota,
                maxLength: 300,
                decoration: const InputDecoration(
                  labelText: 'Observaciones para la barra',
                ),
              ),
              const SizedBox(height: 14),
              BotonAftr(
                _ocupado ? 'Procesando…' : 'Comprar con PULSE',
                onTap: abierto && !_ocupado ? () => _comprar('pulse') : null,
              ),
              const SizedBox(height: 12),
              BotonAftr(
                'Pagar con QR',
                secundario: true,
                onTap: abierto && !_ocupado ? () => _comprar('qr') : null,
              ),
              TextButton(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(builder: (_) => const PulseScreen()),
                ),
                child: const Text('Recargar PULSE'),
              ),
            ],
            const SizedBox(height: 32),
            Text('Mis pedidos', style: Aftr.fuerte(24)),
            if (pedidos.isLoading) const LinearProgressIndicator(),
            if (pedidos.hasError)
              TextButton(
                onPressed: () => ref.invalidate(pedidosMesaProvider(id)),
                child: const Text('Reintentar pedidos'),
              ),
            for (final p in pedidos.value ?? [])
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${p['estado']}'.replaceAll('_', ' '),
                      style: Aftr.fuerte(18),
                    ),
                    const SizedBox(height: 8),
                    for (final i in (p['items'] as List? ?? []))
                      Text(
                        '${i['qty']} × ${i['nombre']}',
                        style: Aftr.cuerpo(14),
                      ),
                    Text(
                      'Bs ${importePulse(p['total_centavos'])} · ${p['metodo'] == 'pulse' ? 'PULSE' : 'QR'}',
                      style: Aftr.cuerpo(14),
                    ),
                    if (p['estado'] == 'pendiente')
                      TextButton(
                        onPressed: () => abrirPagoQr(
                          context,
                          orden: p['id'] as String,
                          titulo: 'Pedido de bebidas',
                          tipo: 'pedido',
                        ),
                        child: const Text('Continuar pago QR'),
                      ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}
