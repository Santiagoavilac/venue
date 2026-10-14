import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show PostgrestException;

import '../../../core/networking/supabase.dart';
import '../../../core/theme/venue_theme.dart';
import '../../../core/widgets/avisos.dart';
import '../../../core/widgets/estado_vista.dart';
import '../../analytics/ui/reporte_screen.dart' show Kpi, Renglon;
import '../../clubs/data/clubs.dart';
import '../../events/data/eventos.dart';
import '../data/barra.dart';

Future<T?> _hoja<T>(BuildContext context, Widget child) => showModalBottomSheet<T>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      useSafeArea: true,
      backgroundColor: VenueColors.superficie,
      builder: (c) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(c).viewInsets.bottom),
        child: child,
      ),
    );

String _fecha(dynamic ts) {
  final t = DateTime.tryParse(ts as String? ?? '')?.toLocal();
  return t == null ? '' : '${t.day}/${t.month} ${horaCorta(t)}';
}

String _error(Object e) => e is PostgrestException && e.code == '23505'
    ? 'Ya existe uno con ese nombre.'
    : mensajeDeError(e);

/// Pequeño contenedor de recarga para hojas con datos propios.
class _Datos<T> extends StatefulWidget {
  const _Datos({super.key, required this.cargar, required this.pintar});
  final Future<T> Function() cargar;
  final Widget Function(BuildContext, T, VoidCallback recargar) pintar;
  @override
  State<_Datos<T>> createState() => _DatosState<T>();
}

class _DatosState<T> extends State<_Datos<T>> {
  late Future<T> _f = widget.cargar();
  void _recargar() => setState(() => _f = widget.cargar());

  @override
  Widget build(BuildContext context) => FutureBuilder<T>(
        future: _f,
        builder: (context, s) {
          if (s.hasError) {
            return MensajeVista(
                icono: Icons.error_outline, titulo: 'No se pudo cargar',
                detalle: mensajeDeError(s.error!), accion: 'Reintentar', alTocar: _recargar);
          }
          if (!s.hasData) return const Center(child: Padding(padding: EdgeInsets.all(30), child: CircularProgressIndicator()));
          return widget.pintar(context, s.data as T, _recargar);
        },
      );
}

// ═══════════════════ INVENTARIO (propietario) ═══════════════════
/// Stock perpetuo del boliche, en ml. El costo y el valor los ve solo el
/// propietario.
class InventarioScreen extends ConsumerWidget {
  const InventarioScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final stock = ref.watch(stockProvider);
    final club = ref.watch(clubActivoIdProvider);
    if (club == null) return const SizedBox.shrink();
    void recargar() => ref.invalidate(stockProvider);
    return RefreshIndicator(
      onRefresh: () => ref.refresh(stockProvider.future),
      child: VistaAsync(
        valor: stock,
        reintentar: recargar,
        datos: (filas) {
          final valor = filas.fold<num>(0, (a, f) => a + (f['valor_bs'] as num? ?? 0));
          final bajos = filas.where((f) => f['bajo_stock'] == true).length;
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
            children: [
              Row(children: [
                Expanded(child: Kpi('Valor del stock', '$valor Bs', '')),
                const SizedBox(width: 10),
                Expanded(child: Kpi('Bajo stock', '$bajos', ' de ${filas.length}',
                    color: bajos > 0 ? VenueColors.aviso : null)),
              ]),
              const SizedBox(height: 10),
              Wrap(spacing: 8, runSpacing: 6, children: [
                _Boton('Recibir mercadería', Icons.download_rounded, () async {
                  await _hoja(context, const RecibirLote());
                  recargar();
                }),
                _Boton('Nueva bebida', Icons.add_rounded, () async {
                  await _hoja(context, const _NuevaBebida());
                  recargar();
                }),
                _Boton('Conteo de la noche', Icons.checklist_rtl_rounded,
                    () => _hoja(context, const _Conteo()).then((_) => recargar())),
                _Boton('Carta y recetas', Icons.menu_book_outlined, () => _hoja(context, const _Carta())),
                _Boton('Turno', Icons.badge_outlined, () => _hoja(context, const _Turno())),
                _Boton('Barras', Icons.storefront_outlined, () => _hoja(context, const _Barras())),
                _Boton('Cortesías', Icons.card_giftcard_rounded, () => _hoja(context, const _CortesiasConfig())),
              ]),
              const SizedBox(height: 10),
              if (filas.isEmpty)
                const Padding(
                  padding: EdgeInsets.only(top: 30),
                  child: MensajeVista(
                    icono: Icons.inventory_2_outlined,
                    titulo: 'Todavía no hay bebidas',
                    detalle: 'Creá una bebida y registrá su primera recepción de mercadería.',
                  ),
                ),
              for (final f in filas)
                Card(
                  margin: const EdgeInsets.only(top: 8),
                  clipBehavior: Clip.antiAlias,
                  child: ListTile(
                    onTap: () async {
                      await _hoja(context, _DetalleBebida(fila: f));
                      recargar();
                    },
                    title: Text('${f['nombre']}', style: const TextStyle(fontWeight: FontWeight.w700)),
                    subtitle: Text(
                        '${f['categoria'] ?? ''} · ${f['lotes_abiertos']} lote(s) · ${f['valor_bs']} Bs'),
                    trailing: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text('${f['botellas_equiv']}',
                            style: TextStyle(
                                fontSize: 20, fontWeight: FontWeight.w800,
                                color: f['bajo_stock'] == true ? VenueColors.aviso : null)),
                        Text(f['bajo_stock'] == true ? 'botellas · BAJO' : 'botellas',
                            style: const TextStyle(fontSize: 11, color: VenueColors.textoSuave)),
                      ],
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

class _Boton extends StatelessWidget {
  const _Boton(this.texto, this.icono, this.alTocar);
  final String texto;
  final IconData icono;
  final VoidCallback alTocar;
  @override
  Widget build(BuildContext context) => OutlinedButton.icon(
        style: OutlinedButton.styleFrom(
            minimumSize: const Size(0, 42), padding: const EdgeInsets.symmetric(horizontal: 12),
            textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
        onPressed: alTocar,
        icon: Icon(icono, size: 18),
        label: Text(texto),
      );
}

class _NuevaBebida extends ConsumerStatefulWidget {
  const _NuevaBebida();
  @override
  ConsumerState<_NuevaBebida> createState() => _NuevaBebidaState();
}

class _NuevaBebidaState extends ConsumerState<_NuevaBebida> {
  final _n = TextEditingController(), _v = TextEditingController(text: '750');
  final _u = TextEditingController(), _cat = TextEditingController();
  String? _categoria;

  @override
  void dispose() {
    for (final c in [_n, _v, _u, _cat]) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final repo = ref.read(barraRepositoryProvider);
    final club = ref.watch(clubActivoIdProvider)!;
    return _Datos<List<Fila>>(
      cargar: repo.categorias,
      pintar: (context, cats, recargar) => ListView(
        shrinkWrap: true,
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
        children: [
          const Text('Nueva bebida', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
          const SizedBox(height: 12),
          TextField(controller: _n, decoration: const InputDecoration(labelText: 'Nombre', hintText: 'Vodka Absolut 750')),
          const SizedBox(height: 10),
          Row(children: [
            Expanded(child: TextField(controller: _v, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'ml por botella'))),
            const SizedBox(width: 8),
            Expanded(child: TextField(controller: _u, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Avisar con menos de', hintText: 'botellas'))),
          ]),
          const SizedBox(height: 10),
          DropdownButtonFormField<String?>(
            initialValue: cats.any((c) => c['id'] == _categoria) ? _categoria : null,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'Categoría'),
            items: [for (final c in cats) DropdownMenuItem<String?>(value: c['id'] as String, child: Text('${c['nombre']}'))],
            onChanged: (v) => setState(() => _categoria = v),
          ),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(child: TextField(controller: _cat, decoration: const InputDecoration(labelText: 'o crear categoría', isDense: true))),
            IconButton(
              tooltip: 'Crear categoría',
              onPressed: () async {
                if (_cat.text.trim().isEmpty) return;
                try {
                  await repo.crearCategoria(_cat.text.trim(), cats.length + 1);
                  _cat.clear();
                  recargar();
                } catch (e) {
                  if (context.mounted) avisar(context, _error(e), tipo: TipoAviso.aviso);
                }
              },
              icon: const Icon(Icons.add_circle_outline_rounded),
            ),
          ]),
          const SizedBox(height: 14),
          FilledButton(
            onPressed: () async {
              final vol = int.tryParse(_v.text);
              if (_n.text.trim().isEmpty || vol == null || vol <= 0) {
                avisar(context, 'Poné el nombre y los ml por botella', tipo: TipoAviso.aviso);
                return;
              }
              try {
                await repo.crearBebida(club, nombre: _n.text.trim(), volumenMl: vol,
                    categoriaId: _categoria, umbralBajo: int.tryParse(_u.text));
                if (!context.mounted) return;
                Navigator.pop(context);
                avisar(context, 'Bebida creada');
              } catch (e) {
                if (context.mounted) {
                  avisar(context,
                      e is PostgrestException && e.code == '23505'
                          ? 'Ya tenés una bebida llamada "${_n.text.trim()}"'
                          : mensajeDeError(e),
                      tipo: TipoAviso.aviso);
                }
              }
            },
            child: const Text('Crear bebida'),
          ),
        ],
      ),
    );
  }
}

/// Registrar una recepción de mercadería (propietario y depósito). El costo
/// es opcional y solo lo carga quien lo conoce.
class RecibirLote extends ConsumerStatefulWidget {
  const RecibirLote({super.key, this.pedirCosto = true});
  final bool pedirCosto;
  @override
  ConsumerState<RecibirLote> createState() => _RecibirLoteState();
}

class _RecibirLoteState extends ConsumerState<RecibirLote> {
  final _q = TextEditingController(), _c = TextEditingController(), _n = TextEditingController();
  String? _bebida;
  bool _ocupado = false;

  @override
  void dispose() {
    for (final c in [_q, _c, _n]) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final repo = ref.read(barraRepositoryProvider);
    final club = ref.watch(clubActivoIdProvider)!;
    return _Datos<List<Fila>>(
      cargar: () => repo.bebidas(club),
      pintar: (context, bebidas, _) => ListView(
        shrinkWrap: true,
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
        children: [
          const Text('Recibir mercadería', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
          const SizedBox(height: 12),
          if (bebidas.isEmpty)
            const Text('Todavía no hay bebidas cargadas. Las crea el propietario.',
                style: TextStyle(color: VenueColors.aviso)),
          DropdownButtonFormField<String?>(
            initialValue: _bebida,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'Bebida'),
            items: [
              for (final b in bebidas)
                DropdownMenuItem<String?>(
                    value: b['id'] as String, child: Text('${b['nombre']} · ${b['volumen_ml']} ml')),
            ],
            onChanged: (v) => setState(() => _bebida = v),
          ),
          const SizedBox(height: 10),
          Row(children: [
            Expanded(child: TextField(controller: _q, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Botellas'))),
            if (widget.pedirCosto) ...[
              const SizedBox(width: 8),
              Expanded(child: TextField(controller: _c, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Costo por botella (Bs)'))),
            ],
          ]),
          const SizedBox(height: 10),
          TextField(controller: _n, decoration: const InputDecoration(labelText: 'Notas (opcional)', hintText: 'Proveedor, factura…')),
          const SizedBox(height: 14),
          FilledButton(
            onPressed: _ocupado
                ? null
                : () async {
                    final q = int.tryParse(_q.text);
                    if (_bebida == null || q == null || q <= 0) {
                      avisar(context, 'Elegí la bebida y cuántas botellas', tipo: TipoAviso.aviso);
                      return;
                    }
                    setState(() => _ocupado = true);
                    try {
                      final r = await repo.recibir(_bebida!, q,
                          costoUnitario: num.tryParse(_c.text),
                          notas: _n.text.trim().isEmpty ? null : _n.text.trim());
                      if (!context.mounted) return;
                      Navigator.pop(context);
                      avisar(context, 'Recibidas ${r['botellas']} botellas (${r['ml']} ml)');
                    } catch (e) {
                      if (context.mounted) {
                        avisar(context, mensajeDeError(e), tipo: TipoAviso.aviso);
                        setState(() => _ocupado = false);
                      }
                    }
                  },
            child: const Text('Registrar recepción'),
          ),
        ],
      ),
    );
  }
}

class _DetalleBebida extends ConsumerWidget {
  const _DetalleBebida({required this.fila});
  final Fila fila;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final repo = ref.read(barraRepositoryProvider);
    final ev = ref.watch(eventoActivoProvider);
    final vol = (fila['volumen_ml'] as num?)?.toInt() ?? 750;
    return _Datos<List<Fila>>(
      cargar: () => repo.lotes(fila['bebida_id'] as String),
      pintar: (context, lotes, recargar) {
        Future<void> ajustar(Fila l) async {
          final cerradas = TextEditingController(), abierta = TextEditingController(text: '0');
          final motivo = TextEditingController();
          final ok = await showDialog<bool>(
            context: context,
            builder: (c) => AlertDialog(
              title: Text('Conteo físico · ${l['codigo']}'),
              content: Column(mainAxisSize: MainAxisSize.min, children: [
                Text('El sistema dice ${l['ml_actual']} ml (${botellasDe(l['ml_actual'] as num, vol)} botellas).'),
                TextField(controller: cerradas, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Botellas cerradas')),
                TextField(controller: abierta, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'ml en la botella abierta')),
                TextField(controller: motivo, decoration: const InputDecoration(labelText: 'Motivo (opcional)')),
              ]),
              actions: [
                TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancelar')),
                TextButton(onPressed: () => Navigator.pop(c, true), child: const Text('Ajustar')),
              ],
            ),
          );
          if (ok != true) return;
          try {
            await repo.ajustar(l['id'] as String,
                mlContados(botellasCerradas: int.tryParse(cerradas.text) ?? 0,
                    mlAbierta: num.tryParse(abierta.text) ?? 0, volumenMl: vol),
                eventoId: ev?.id, motivo: motivo.text.trim().isEmpty ? null : motivo.text.trim());
            recargar();
            if (context.mounted) avisar(context, 'Stock ajustado');
          } catch (e) {
            if (context.mounted) avisar(context, mensajeDeError(e), tipo: TipoAviso.aviso);
          }
        }

        Future<void> baja(Fila l) async {
          final ml = TextEditingController(text: '$vol'), motivo = TextEditingController();
          final ok = await showDialog<bool>(
            context: context,
            builder: (c) => AlertDialog(
              title: Text('Dar de baja · ${l['codigo']}'),
              content: Column(mainAxisSize: MainAxisSize.min, children: [
                TextField(controller: ml, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'ml a dar de baja')),
                TextField(controller: motivo, decoration: const InputDecoration(labelText: 'Motivo', hintText: 'Rotura, vencimiento…')),
              ]),
              actions: [
                TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancelar')),
                TextButton(
                    onPressed: () => Navigator.pop(c, true),
                    style: TextButton.styleFrom(foregroundColor: VenueColors.mal),
                    child: const Text('Dar de baja')),
              ],
            ),
          );
          final n = num.tryParse(ml.text);
          if (ok != true || n == null || n <= 0) return;
          if (motivo.text.trim().isEmpty) {
            if (context.mounted) avisar(context, 'La baja necesita un motivo', tipo: TipoAviso.aviso);
            return;
          }
          try {
            await repo.baja(l['id'] as String, n, motivo.text.trim(), eventoId: ev?.id);
            recargar();
            if (context.mounted) avisar(context, 'Baja registrada', tipo: TipoAviso.aviso);
          } catch (e) {
            if (context.mounted) avisar(context, mensajeDeError(e), tipo: TipoAviso.aviso);
          }
        }

        return ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
          children: [
            Text('${fila['nombre']}', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
            Text('${fila['ml_total']} ml · ${fila['botellas_equiv']} botellas · ${fila['valor_bs']} Bs',
                style: const TextStyle(color: VenueColors.textoSuave)),
            const SizedBox(height: 8),
            if (lotes.isEmpty) const Text('Sin lotes con stock.'),
            for (final l in lotes)
              Card(
                margin: const EdgeInsets.only(top: 8),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(14, 8, 6, 8),
                  child: Row(children: [
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text('${l['codigo']} · ${botellasDe(l['ml_actual'] as num, vol)} botellas',
                            style: const TextStyle(fontWeight: FontWeight.w700)),
                        Text(
                            '${l['ml_actual']} ml · recibido ${_fecha(l['recibido_at'])}'
                            '${l['costo_unitario'] == null ? '' : ' · ${l['costo_unitario']} Bs c/u'}',
                            style: const TextStyle(color: VenueColors.textoSuave, fontSize: 12.5)),
                      ]),
                    ),
                    TextButton(onPressed: () => ajustar(l), child: const Text('Contar')),
                    TextButton(
                        onPressed: () => baja(l),
                        style: TextButton.styleFrom(foregroundColor: VenueColors.mal),
                        child: const Text('Baja')),
                  ]),
                ),
              ),
          ],
        );
      },
    );
  }
}

class _Barras extends ConsumerWidget {
  const _Barras();
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final repo = ref.read(barraRepositoryProvider);
    final club = ref.watch(clubActivoIdProvider)!;
    final nombre = TextEditingController(), planta = TextEditingController(text: '1');
    return _Datos<List<Fila>>(
      cargar: () => repo.barras(club),
      pintar: (context, barras, recargar) => ListView(
        shrinkWrap: true,
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
        children: [
          const Text('Barras', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
          for (final b in barras)
            ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.storefront_outlined),
                title: Text('${b['nombre']}'),
                subtitle: Text('Planta ${b['planta']}')),
          Row(children: [
            Expanded(child: TextField(controller: nombre, decoration: const InputDecoration(labelText: 'Nueva barra', isDense: true))),
            const SizedBox(width: 8),
            SizedBox(width: 80, child: TextField(controller: planta, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Planta', isDense: true))),
            IconButton.filledTonal(
              tooltip: 'Crear barra',
              onPressed: () async {
                if (nombre.text.trim().isEmpty) return;
                try {
                  await repo.crearBarra(club, nombre.text.trim(), int.tryParse(planta.text) ?? 1);
                  recargar();
                } catch (e) {
                  if (context.mounted) {
                    avisar(context,
                        e is PostgrestException && e.code == '23505'
                            ? 'Ya existe una barra con ese nombre'
                            : mensajeDeError(e),
                        tipo: TipoAviso.aviso);
                  }
                }
              },
              icon: const Icon(Icons.add_rounded),
            ),
          ]),
        ],
      ),
    );
  }
}

// ── conteo de la noche ──
class _Conteo extends ConsumerStatefulWidget {
  const _Conteo();
  @override
  ConsumerState<_Conteo> createState() => _ConteoState();
}

class _ConteoState extends ConsumerState<_Conteo> {
  String _momento = 'cierre';
  final _contado = <String, num>{};
  bool _grabando = false;

  @override
  Widget build(BuildContext context) {
    final ev = ref.watch(eventoActivoProvider);
    final repo = ref.read(barraRepositoryProvider);
    if (ev == null) {
      return const Padding(padding: EdgeInsets.all(30), child: Text('No hay evento abierto.'));
    }
    return _Datos<List<Fila>>(
      key: ValueKey(_momento),
      cargar: () => repo.conteoPendiente(ev.id, _momento),
      pintar: (context, filas, recargar) => ListView(
        shrinkWrap: true,
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
        children: [
          const Text('Conteo de la noche', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
          const Text('Contá lo que hay de verdad. Lo que no toques queda como dice el sistema.',
              style: TextStyle(color: VenueColors.textoSuave)),
          const SizedBox(height: 10),
          SegmentedButton<String>(
            showSelectedIcon: false,
            segments: const [
              ButtonSegment(value: 'apertura', label: Text('Apertura')),
              ButtonSegment(value: 'cierre', label: Text('Cierre')),
            ],
            selected: {_momento},
            onSelectionChanged: (s) => setState(() {
              _momento = s.first;
              _contado.clear();
            }),
          ),
          if (filas.isEmpty)
            const Padding(padding: EdgeInsets.all(20), child: Text('No hay lotes con stock para contar.')),
          for (final f in filas)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Row(children: [
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('${f['bebida']}', style: const TextStyle(fontWeight: FontWeight.w700)),
                    Text(
                        '${f['codigo']} · sistema ${botellasDe(f['ml_sistema'] as num, f['volumen_ml'] as num)} bot. (${f['ml_sistema']} ml)'
                        '${f['ml_contado'] == null ? '' : ' · ya contado ${f['ml_contado']} ml'}',
                        style: const TextStyle(color: VenueColors.textoSuave, fontSize: 12.5)),
                  ]),
                ),
                SizedBox(
                  width: 104,
                  child: TextField(
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    textAlign: TextAlign.center,
                    decoration: const InputDecoration(isDense: true, hintText: 'botellas'),
                    onChanged: (v) {
                      final b = num.tryParse(v.replaceAll(',', '.'));
                      b == null
                          ? _contado.remove(f['lote_id'])
                          : _contado[f['lote_id'] as String] = b * (f['volumen_ml'] as num);
                    },
                  ),
                ),
              ]),
            ),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: _grabando || filas.isEmpty
                ? null
                : () async {
                    setState(() => _grabando = true);
                    try {
                      await repo.grabarConteo(ev.id, _momento, Map.of(_contado));
                      if (!context.mounted) return;
                      Navigator.pop(context);
                      avisar(context, 'Conteo de $_momento grabado · ${_contado.length} lote(s) ajustados');
                    } catch (e) {
                      if (context.mounted) {
                        avisar(context, mensajeDeError(e), tipo: TipoAviso.aviso);
                        setState(() => _grabando = false);
                      }
                    }
                  },
            child: const Text('Grabar conteo'),
          ),
        ],
      ),
    );
  }
}

// ── carta y recetas ──
class _Carta extends ConsumerWidget {
  const _Carta();
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final repo = ref.read(barraRepositoryProvider);
    final club = ref.watch(clubActivoIdProvider)!;
    final n = TextEditingController(), p = TextEditingController();
    return _Datos<List<dynamic>>(
      cargar: () => Future.wait([repo.tragos(club), repo.bebidas(club)]),
      pintar: (context, d, recargar) {
        final tragos = d[0] as List<Fila>, bebidas = d[1] as List<Fila>;
        Future<void> hacer(Future<void> Function() f) async {
          try {
            await f();
            recargar();
          } catch (e) {
            if (context.mounted) {
              avisar(context,
                  e is PostgrestException && e.code == '23505'
                      ? 'Esa bebida ya está en la receta'
                      : mensajeDeError(e),
                  tipo: TipoAviso.aviso);
            }
          }
        }

        return ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
          children: [
            const Text('Carta y recetas', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
            const Text('Un trago se puede activar recién cuando tiene receta: es lo que descuenta del stock.',
                style: TextStyle(color: VenueColors.textoSuave)),
            for (final t in tragos)
              ExpansionTile(
                tilePadding: EdgeInsets.zero,
                title: Text('${t['nombre']} · ${t['precio_venta']} Bs',
                    style: TextStyle(
                        fontWeight: FontWeight.w700,
                        color: t['activo'] == true ? null : VenueColors.textoSuave)),
                subtitle: Text(t['activo'] == true ? 'En la carta' : 'Inactivo'),
                children: [
                  for (final r in (t['r'] as List? ?? const []))
                    ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      title: Text('${(r['b'] as Map?)?['nombre'] ?? '?'}'),
                      subtitle: Text('${r['ml']} ml por vaso'),
                      trailing: IconButton(
                          tooltip: 'Quitar de la receta',
                          icon: const Icon(Icons.close_rounded),
                          onPressed: () => hacer(() => repo.quitarDeReceta(r['id'] as String))),
                    ),
                  _AgregarAReceta(
                      bebidas: bebidas,
                      alAgregar: (b, ml) => hacer(() => repo.agregarAReceta(t['id'] as String, b, ml))),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('En la carta'),
                    value: t['activo'] == true,
                    onChanged: (v) {
                      if (v && (t['r'] as List? ?? const []).isEmpty) {
                        avisar(context, 'Cargale la receta antes de activarlo', tipo: TipoAviso.aviso);
                        return;
                      }
                      hacer(() => repo.editarTrago(t['id'] as String, {'activo': v}));
                    },
                  ),
                ],
              ),
            const Divider(),
            Row(children: [
              Expanded(child: TextField(controller: n, decoration: const InputDecoration(labelText: 'Nuevo trago', isDense: true))),
              const SizedBox(width: 8),
              SizedBox(width: 90, child: TextField(controller: p, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Precio', isDense: true))),
              IconButton.filledTonal(
                tooltip: 'Crear trago',
                onPressed: () {
                  final precio = num.tryParse(p.text);
                  if (n.text.trim().isEmpty || precio == null || precio <= 0) {
                    avisar(context, 'Nombre y precio de venta', tipo: TipoAviso.aviso);
                    return;
                  }
                  hacer(() => repo.crearTrago(club, n.text.trim(), precio));
                },
                icon: const Icon(Icons.add_rounded),
              ),
            ]),
          ],
        );
      },
    );
  }
}

class _AgregarAReceta extends StatefulWidget {
  const _AgregarAReceta({required this.bebidas, required this.alAgregar});
  final List<Fila> bebidas;
  final void Function(String bebidaId, num ml) alAgregar;
  @override
  State<_AgregarAReceta> createState() => _AgregarARecetaState();
}

class _AgregarARecetaState extends State<_AgregarAReceta> {
  String? _b;
  final _ml = TextEditingController(text: '50');
  @override
  void dispose() {
    _ml.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Row(children: [
        Expanded(
          child: DropdownButtonFormField<String?>(
            initialValue: _b,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'Bebida', isDense: true),
            items: [
              for (final b in widget.bebidas)
                DropdownMenuItem<String?>(value: b['id'] as String, child: Text('${b['nombre']}', overflow: TextOverflow.ellipsis)),
            ],
            onChanged: (v) => setState(() => _b = v),
          ),
        ),
        const SizedBox(width: 8),
        SizedBox(width: 76, child: TextField(controller: _ml, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'ml', isDense: true))),
        IconButton(
          tooltip: 'Agregar a la receta',
          onPressed: () {
            final ml = num.tryParse(_ml.text);
            if (_b != null && ml != null && ml > 0) widget.alAgregar(_b!, ml);
          },
          icon: const Icon(Icons.add_circle_outline_rounded),
        ),
      ]);
}

// ── turno: qué bartender atiende qué barra ──
class _Turno extends ConsumerWidget {
  const _Turno();
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final repo = ref.read(barraRepositoryProvider);
    final club = ref.watch(clubActivoIdProvider)!;
    final ev = ref.watch(eventoActivoProvider);
    if (ev == null) return const Padding(padding: EdgeInsets.all(30), child: Text('No hay evento abierto.'));
    return _Datos<List<dynamic>>(
      cargar: () => Future.wait([repo.barras(club), repo.bartenders(club), repo.turno(ev.id)]),
      pintar: (context, d, recargar) {
        final barras = d[0] as List<Fila>, gente = d[1] as List<Fila>, turno = d[2] as Set<String>;
        return ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
          children: [
            Text('Turno · ${ev.nombre}', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
            const Text('Cada bartender vende solo en las barras que tenga marcadas.',
                style: TextStyle(color: VenueColors.textoSuave)),
            if (gente.isEmpty)
              const Padding(padding: EdgeInsets.all(16), child: Text('No hay cuentas con rol Barra en este boliche.')),
            for (final g in gente) ...[
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text('${g['nombre']}', style: const TextStyle(fontWeight: FontWeight.w800)),
              ),
              Wrap(spacing: 8, children: [
                for (final b in barras)
                  FilterChip(
                    label: Text('${b['nombre']}'),
                    selected: turno.contains('${b['id']}|${g['id']}'),
                    onSelected: (v) async {
                      try {
                        await repo.asignar(ev.id, b['id'] as String, g['id'] as String, v);
                        recargar();
                      } catch (e) {
                        if (context.mounted) avisar(context, mensajeDeError(e), tipo: TipoAviso.aviso);
                      }
                    },
                  ),
              ]),
            ],
          ],
        );
      },
    );
  }
}

class _CortesiasConfig extends ConsumerWidget {
  const _CortesiasConfig();
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final repo = ref.read(barraRepositoryProvider);
    final club = ref.watch(clubActivoIdProvider)!;
    return _Datos<int>(
      cargar: () => repo.cupoCortesia(club),
      pintar: (context, cupo, recargar) {
        final t = TextEditingController(text: '$cupo');
        return ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
          children: [
            const Text('Cortesías', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
            const Text('Cuántos vasos de cortesía puede pedir cada relacionador por evento. 0 = ninguno.',
                style: TextStyle(color: VenueColors.textoSuave)),
            const SizedBox(height: 12),
            TextField(controller: t, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Vasos por persona')),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: () async {
                final n = int.tryParse(t.text);
                if (n == null || n < 0) return;
                try {
                  await repo.fijarCupoCortesia(club, n);
                  if (!context.mounted) return;
                  Navigator.pop(context);
                  avisar(context, 'Cupo de cortesías guardado');
                } catch (e) {
                  if (context.mounted) avisar(context, mensajeDeError(e), tipo: TipoAviso.aviso);
                }
              },
              child: const Text('Guardar'),
            ),
          ],
        );
      },
    );
  }
}

// ═══════════════════ MOVIMIENTOS ═══════════════════
class MovimientosScreen extends ConsumerWidget {
  const MovimientosScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final club = ref.watch(clubActivoIdProvider);
    if (club == null) return const SizedBox.shrink();
    return _Datos<List<Fila>>(
      cargar: () => ref.read(barraRepositoryProvider).movimientos(club),
      pintar: (context, m, recargar) => RefreshIndicator(
        onRefresh: () async => recargar(),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          children: [
            if (m.isEmpty)
              const Padding(
                  padding: EdgeInsets.only(top: 60),
                  child: MensajeVista(icono: Icons.swap_vert_rounded, titulo: 'Sin movimientos todavía')),
            for (final x in m)
              ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                leading: Icon(
                  switch (x['tipo']) {
                    'entrada' => Icons.south_west_rounded,
                    'salida' => Icons.north_east_rounded,
                    'baja' => Icons.delete_outline_rounded,
                    'anulacion' => Icons.undo_rounded,
                    _ => Icons.tune_rounded,
                  },
                  color: (x['ml_delta'] as num? ?? 0) >= 0 ? VenueColors.ok : VenueColors.textoSuave,
                ),
                title: Text('${x['bebida']} · ${x['ml_delta']} ml'),
                subtitle: Text([
                  _fecha(x['created_at']),
                  '${x['motivo'] ?? x['tipo']}'.split(':').first,
                  if (x['quien'] != null) '${x['quien']}',
                ].join(' · ')),
                trailing: x['costo'] == null ? null : Text('${x['costo']} Bs'),
              ),
          ],
        ),
      ),
    );
  }
}

// ═══════════════════ CIERRE ═══════════════════
/// Cuánto se vendió en la noche, por barra, y las cortesías usadas.
class CierreBarraScreen extends ConsumerWidget {
  const CierreBarraScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ev = ref.watch(eventoActivoProvider);
    final repo = ref.read(barraRepositoryProvider);
    if (ev == null) {
      return const MensajeVista(icono: Icons.event_busy_rounded, titulo: 'No hay evento abierto');
    }
    return _Datos<List<dynamic>>(
      key: ValueKey(ev.id),
      cargar: () => Future.wait([repo.cierre(ev.id), repo.cortesias(ev.id)]),
      pintar: (context, d, recargar) {
        final filas = d[0] as List<Fila>, cort = d[1] as List<Fila>;
        num s(String k) => filas.fold<num>(0, (a, f) => a + (f[k] as num? ?? 0));
        return RefreshIndicator(
          onRefresh: () async => recargar(),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
            children: [
              Text('Cierre · ${ev.nombre}', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
              const SizedBox(height: 10),
              Row(children: [
                Expanded(child: Kpi('Vendido', '${s('bs')} Bs', '')),
                const SizedBox(width: 10),
                Expanded(child: Kpi('Vasos', '${s('tragos')}', ' · ${s('ventas')} ventas')),
              ]),
              const SizedBox(height: 10),
              Kpi('Cortesías', '${s('cortesias')}', ' vasos sin cobrar', color: VenueColors.aviso),
              const SizedBox(height: 12),
              const Text('Por barra', style: TextStyle(fontWeight: FontWeight.w800)),
              if (filas.isEmpty) const Padding(padding: EdgeInsets.all(14), child: Text('Todavía no hubo ventas.')),
              for (final f in filas)
                Renglon('${f['barra']} · ${f['tragos']} vasos · ${f['cortesias']} cortesías', '${f['bs']} Bs'),
              if (cort.isNotEmpty) ...[
                const Divider(height: 26),
                const Text('Cortesías por persona', style: TextStyle(fontWeight: FontWeight.w800)),
                for (final c in cort)
                  Renglon('${c['nombre']} · ${c['team'] ?? ''}', '${c['usados'] ?? 0} de ${c['cupo'] ?? 0}'),
              ],
            ],
          ),
        );
      },
    );
  }
}

// ═══════════════════ ANALÍTICA ═══════════════════
/// El Cierre dice cuánto se vendió. Esto dice cuánto QUEDÓ: descuenta el
/// costo de lo servido, lo que se regaló y lo que se perdió.
class AnaliticaBarraScreen extends ConsumerStatefulWidget {
  const AnaliticaBarraScreen({super.key});
  @override
  ConsumerState<AnaliticaBarraScreen> createState() => _AnaliticaBarraScreenState();
}

class _AnaliticaBarraScreenState extends ConsumerState<AnaliticaBarraScreen> {
  final _asistentes = TextEditingController(text: '500');
  List<Fila>? _compra;

  @override
  void dispose() {
    _asistentes.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ev = ref.watch(eventoActivoProvider);
    final club = ref.watch(clubActivoIdProvider);
    final repo = ref.read(barraRepositoryProvider);
    if (ev == null || club == null) {
      return const MensajeVista(icono: Icons.event_busy_rounded, titulo: 'No hay evento abierto');
    }
    return _Datos(
      key: ValueKey(ev.id),
      cargar: () => repo.analitica(ev.id),
      pintar: (context, a, recargar) {
        final e = a.evento ?? const <String, dynamic>{}, m = a.margen ?? const <String, dynamic>{};
        return RefreshIndicator(
          onRefresh: () async => recargar(),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
            children: [
              Text('Analítica · ${ev.nombre}', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
              const SizedBox(height: 10),
              Row(children: [
                Expanded(child: Kpi('Ingresos', '${e['ingresos'] ?? 0} Bs', '')),
                const SizedBox(width: 10),
                Expanded(child: Kpi('Margen neto', '${m['margen_neto'] ?? 0} Bs',
                    m['margen_pct'] == null ? '' : ' · ${m['margen_pct']}%', color: VenueColors.ok)),
              ]),
              const SizedBox(height: 10),
              Row(children: [
                Expanded(child: Kpi('Vasos', '${e['vasos'] ?? 0}', ' · ${e['vasos_cortesia'] ?? 0} cortesía')),
                const SizedBox(width: 10),
                Expanded(child: Kpi('Ticket promedio', '${e['ticket_promedio'] ?? 0} Bs', '')),
              ]),
              const SizedBox(height: 12),
              Renglon('Costo de lo vendido', '${m['costo_vendido'] ?? 0} Bs'),
              Renglon('Costo de cortesías', '${m['costo_cortesias'] ?? 0} Bs'),
              Renglon('Merma', '${m['merma_bs'] ?? 0} Bs', color: VenueColors.mal),
              const Divider(height: 24),
              const Text('Por barra', style: TextStyle(fontWeight: FontWeight.w800)),
              for (final b in a.porBarra)
                Renglon('${b['barra']} · ${b['vasos']} vasos', '${b['ingresos']} Bs · ${b['pct_del_evento']}%'),
              const Divider(height: 24),
              const Text('Lo más vendido', style: TextStyle(fontWeight: FontWeight.w800)),
              for (final t in a.top)
                Renglon('${t['puesto_evento']}. ${t['trago']} · ${t['vasos']} vasos', '${t['ingresos']} Bs'),
              if (a.merma.isNotEmpty) ...[
                const Divider(height: 24),
                const Text('Merma por bebida', style: TextStyle(fontWeight: FontWeight.w800)),
                for (final x in a.merma)
                  Renglon('${x['bebida'] ?? x['nombre'] ?? '?'}', '${x['merma_bs']} Bs', color: VenueColors.mal),
              ],
              const Divider(height: 24),
              const Text('Proyección de compra', style: TextStyle(fontWeight: FontWeight.w800)),
              Row(children: [
                Expanded(
                  child: TextField(
                      controller: _asistentes,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(labelText: 'Asistentes esperados', isDense: true)),
                ),
                const SizedBox(width: 8),
                OutlinedButton(
                  style: OutlinedButton.styleFrom(minimumSize: const Size(100, 48)),
                  onPressed: () async {
                    try {
                      final r = await repo.proyeccion(club, int.tryParse(_asistentes.text) ?? 500);
                      if (mounted) setState(() => _compra = r);
                    } catch (x) {
                      if (context.mounted) avisar(context, mensajeDeError(x), tipo: TipoAviso.aviso);
                    }
                  },
                  child: const Text('Calcular'),
                ),
              ]),
              for (final c in _compra ?? const <Fila>[])
                Renglon('${c['bebida']} · hay ${c['stock_botellas']}, hacen falta ${c['necesita_botellas']}',
                    'comprar ${c['comprar_botellas']}',
                    color: (c['comprar_botellas'] as num? ?? 0) > 0 ? VenueColors.aviso : null),
            ],
          ),
        );
      },
    );
  }
}

// ═══════════════════ RECEPCIÓN (depósito) ═══════════════════
class RecepcionScreen extends StatelessWidget {
  const RecepcionScreen({super.key});
  @override
  Widget build(BuildContext context) => const RecibirLote(pedirCosto: false);
}

class MisRecepcionesScreen extends ConsumerWidget {
  const MisRecepcionesScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) => _Datos<List<Fila>>(
        cargar: ref.read(barraRepositoryProvider).misRecepciones,
        pintar: (context, l, recargar) => RefreshIndicator(
          onRefresh: () async => recargar(),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
            children: [
              if (l.isEmpty)
                const Padding(
                    padding: EdgeInsets.only(top: 60),
                    child: MensajeVista(
                        icono: Icons.inventory_outlined,
                        titulo: 'Todavía no registraste recepciones')),
              for (final x in l)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text('${(x['b'] as Map?)?['nombre'] ?? '?'} · ${x['cant_inicial']} botellas',
                      style: const TextStyle(fontWeight: FontWeight.w600)),
                  subtitle: Text('${x['codigo']} · ${_fecha(x['recibido_at'])}'),
                ),
            ],
          ),
        ),
      );
}
