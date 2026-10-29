import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';

import '../../../core/media/imagenes.dart';
import '../../../core/networking/supabase.dart';
import '../../../core/sync/tiempo_real.dart';
import '../../../core/theme/venue_theme.dart';
import '../../../core/widgets/avisos.dart';
import '../../../core/widgets/estado_vista.dart';
import '../../authentication/data/sesion.dart';
import '../../clubs/data/clubs.dart';
import '../../events/data/eventos.dart';
import '../data/mesas.dart';
import 'mesa_hojas.dart';
import 'plano.dart';

/// Mesas del evento sobre el plano del local.
///
/// Todos los roles de puerta y venta lo ven; cada uno con lo suyo: seguridad
/// solo nombre y combo (sin plata), los que venden pueden vender y cobrar, y
/// el admin además edita el plano.
class MesasScreen extends ConsumerStatefulWidget {
  const MesasScreen({super.key});

  @override
  ConsumerState<MesasScreen> createState() => _MesasScreenState();
}

class _MesasScreenState extends ConsumerState<MesasScreen> {
  final _planoKey = GlobalKey();
  String? _planta;
  bool _editando = false, _mover = false, _barrido = false, _ocupado = false;

  /// Pisos agregados a mano que todavía no tienen mesas: quedan guardados
  /// cuando se les pone la primera (la base guarda el piso en cada mesa).
  final _pisosNuevos = <String>{};

  /// Plano o lista, elegido a mano por piso. Sin elegir: lista si el piso no
  /// tiene fondo (boliches sin plano, mesa por mesa).
  final _vista = <String, bool>{};

  Future<void> _agregarPiso(List<String> pisos) async {
    final nombre = await _pedirPiso(context, pisos);
    if (nombre == null || !mounted) return;
    final id = idDePiso(nombre);
    setState(() {
      _pisosNuevos.add(id);
      _planta = id;
      _editando = true;
    });
    avisar(context, '${nombrePiso(id)} agregado: sumale mesas');
  }

  Future<void> _hacer(Future<void> Function() f, {String? ok}) async {
    setState(() => _ocupado = true);
    try {
      await f();
      ref.invalidate(mesasProvider);
      if (mounted && ok != null) avisar(context, ok);
    } catch (e) {
      if (mounted) avisar(context, mensajeDeError(e), tipo: TipoAviso.aviso);
    }
    if (mounted) setState(() => _ocupado = false);
  }

  Future<void> _barrer(Evento ev) async {
    _barrido = true;
    final mias = await ref.read(mesasRepositoryProvider).barrerVencidas(ev.id);
    if (!mounted) return;
    if (mias.isNotEmpty) {
      ref.invalidate(mesasProvider);
      avisar(context, 'Se liberó ${mias.join(', ')} — la reserva venció sin pago',
          tipo: TipoAviso.aviso);
    }
  }

  Future<void> _guardarImagen(Evento ev, String planta) async {
    try {
      final b = _planoKey.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final img = await b.toImage(pixelRatio: 3);
      final png = await img.toByteData(format: ui.ImageByteFormat.png);
      final f = File(
          '${Directory.systemTemp.path}/plano-${ev.nombre.replaceAll(RegExp(r'\s+'), '-')}-$planta.png');
      await f.writeAsBytes(png!.buffer.asUint8List());
      await SharePlus.instance
          .share(ShareParams(files: [XFile(f.path, mimeType: 'image/png')]));
    } catch (_) {
      if (mounted) avisar(context, 'No se pudo generar la imagen', tipo: TipoAviso.aviso);
    }
  }

  Future<void> _copiarDeOtro(Evento ev, String club) async {
    final otros = await ref
        .read(supabaseProvider)
        .from('eventos')
        .select('id, nombre, fecha')
        .eq('club_id', club)
        .neq('id', ev.id)
        .order('fecha', ascending: false)
        .limit(30);
    if (!mounted) return;
    final desde = await showDialog<String>(
      context: context,
      builder: (c) => SimpleDialog(
        title: const Text('Copiar el plano de…'),
        children: [
          SimpleDialogOption(
              onPressed: () => Navigator.pop(c, '__ultimo__'),
              child: const Text('El evento anterior del boliche')),
          for (final o in otros)
            SimpleDialogOption(
                onPressed: () => Navigator.pop(c, o['id'] as String),
                child: Text('${o['nombre']} · ${o['fecha']}')),
        ],
      ),
    );
    if (desde == null) return;
    final repo = ref.read(mesasRepositoryProvider);
    await _hacer(
        () => desde == '__ultimo__' ? repo.heredar(ev.id) : repo.copiar(desde, ev.id),
        ok: 'Plano copiado');
  }

  @override
  Widget build(BuildContext context) {
    final ev = ref.watch(eventoActivoProvider);
    final rol = ref.watch(rolProvider).value;
    final yo = ref.watch(usuarioIdProvider);
    final club = ref.watch(clubActivoIdProvider);
    if (ev == null || rol == null || club == null) {
      return const MensajeVista(
          icono: Icons.event_busy_rounded, titulo: 'No hay evento activo');
    }
    if (!_barrido) WidgetsBinding.instance.addPostFrameCallback((_) => _barrer(ev));

    // Otro vendió o cobró una mesa: el plano se actualiza solo. Mientras el
    // admin arrastra mesas no se repinta, para no moverle el piso.
    ref.listen(cambiosEventoProvider(ev.id), (_, c) {
      if (!_editando && (c.value?.contains('mesas') ?? false)) {
        ref.invalidate(mesasProvider);
      }
    });

    final mesas = ref.watch(mesasProvider);
    final combos = {
      for (final c in ref.watch(combosProvider).value ?? const <Combo>[]) c.id: c
    };
    final fondos = ref.watch(fondosProvider).value ?? const <String, String>{};
    final teams = ref.watch(teamsClubProvider).value ?? const <String, String>{};
    final esAdmin = rol == Rol.admin;
    final esPortero = rol == Rol.portero;
    final repo = ref.read(mesasRepositoryProvider);

    return VistaAsync(
      valor: mesas,
      reintentar: () => ref.invalidate(mesasProvider),
      datos: (todas) {
        // Los pisos con mesas, más el que se eligió a mano: un piso nuevo
        // todavía no tiene mesas y aun así hay que poder pararse en él.
        final pisos = pisosDe(todas, extra: [...fondos.keys, ..._pisosNuevos, ?_planta]);
        final planta = pisos.contains(_planta) ? _planta! : pisos.first;
        final enLista = _vista[planta] ?? fondos[planta] == null;
        final enPlanta = todas.where((m) => m.planta == planta).toList();
        final vendidas = todas.where((m) => !m.libre).toList();
        final porVerif = todas.where((m) => m.porVerificar).toList();
        final misReservas = todas
            .where((m) => m.estado == 'reservada' && m.vendidoPor == yo && m.reservadaAt != null)
            .toList();
        final total = vendidas.fold<num>(0, (a, m) => a + m.precio);

        void tocar(Mesa m) {
          if (_editando) {
            hojaEditarMesa(context, m, pisos);
          } else if (esPortero) {
            hojaMesaSeguridad(context, m, combos[m.comboId]);
          } else if (m.libre) {
            if (!rol.vende) return;
            if (!combos.values.any((c) => c.activo) && ev.comboObligatorio) {
              avisar(context, 'El admin debe crear combos primero', tipo: TipoAviso.aviso);
              return;
            }
            hojaVenderMesa(context, m);
          } else {
            hojaMesaVendida(context, m);
          }
        }

        return RefreshIndicator(
          onRefresh: () async {
            _barrido = false;
            ref.invalidate(mesasProvider);
            await ref.read(mesasProvider.future);
          },
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
            children: [
              Text(
                '${vendidas.length} de ${todas.length} ${esPortero ? 'ocupadas' : 'vendidas'}'
                '${!esPortero && vendidas.isNotEmpty ? ' · $total Bs' : ''}',
                style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
              ),
              if (misReservas.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    'Reservas sin pago: ${misReservas.map((m) => '${m.etiqueta} vence ${horaCorta(m.vence(ev.horasReserva)!)}').join(' · ')} — confirmá el pago o se liberan solas.',
                    style: TextStyle(color: VenueColors.aviso, height: 1.35),
                  ),
                ),
              const SizedBox(height: 10),
              if (pisos.length > 1)
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(children: [
                    for (final p in pisos)
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: ChoiceChip(
                          label: Text(nombrePiso(p)),
                          selected: p == planta,
                          showCheckmark: false,
                          onSelected: (_) => setState(() => _planta = p),
                        ),
                      ),
                  ]),
                ),
              const SizedBox(height: 10),
              Wrap(spacing: 8, runSpacing: 6, children: [
                if (!_editando && esAdmin && porVerif.isNotEmpty)
                  FilledButton.tonalIcon(
                    style: FilledButton.styleFrom(
                        minimumSize: const Size(0, 42),
                        backgroundColor: VenueColors.aviso.withValues(alpha: .22)),
                    onPressed: () => hojaConfirmarPagos(context),
                    icon: const Icon(Icons.verified_outlined, size: 18),
                    label: Text('Confirmar pagos (${porVerif.length})'),
                  ),
                if (!_editando && vendidas.isNotEmpty && !esPortero)
                  _Accion('Registro de combos', Icons.copy_rounded, () async {
                    await Clipboard.setData(ClipboardData(
                        text: registroDeCombos(ev.nombre, ev.fechaCorta, vendidas, combos)));
                    if (context.mounted) {
                      avisar(context, 'Registro copiado — precios ya sin comisión');
                    }
                  }),
                if (!_editando && !enLista)
                  _Accion('Guardar imagen', Icons.image_outlined,
                      () => _guardarImagen(ev, planta)),
                _Accion(enLista ? 'Ver plano' : 'Ver lista',
                    enLista ? Icons.map_outlined : Icons.view_list_rounded,
                    () => setState(() => _vista[planta] = !enLista)),
                if (esAdmin && !_editando) ...[
                  _Accion(enLista ? 'Editar mesas' : 'Editar plano', Icons.edit_location_alt_outlined,
                      () => setState(() {
                            _editando = true;
                            _mover = false;
                          })),
                  _Accion('Combos', Icons.local_bar_outlined, () => hojaCombos(context)),
                ],
                if (esAdmin && _editando) ...[
                  FilledButton(
                    style: FilledButton.styleFrom(minimumSize: const Size(0, 42)),
                    onPressed: () => setState(() {
                      _editando = false;
                      _mover = false;
                      ref.invalidate(mesasProvider);
                    }),
                    child: const Text('Listo'),
                  ),
                  FilterChip(
                    label: Text(_mover ? 'Mover: activado' : 'Posiciones bloqueadas'),
                    selected: _mover,
                    onSelected: (v) => setState(() => _mover = v),
                  ),
                  _Accion('Agregar mesas', Icons.add_rounded,
                      _ocupado
                          ? null
                          : () async {
                              final r = await _hojaNuevasMesas(context, pisos, planta, todas);
                              if (r == null) return;
                              final yaHay = todas.where((m) => m.tipo.id == r.tipo.id).length;
                              await _hacer(
                                  () => repo.crearVarias(ev.id, r.planta, r.tipo, r.cantidad,
                                      desde: yaHay + 1,
                                      ya: todas.where((m) => m.planta == r.planta).length),
                                  ok: r.cantidad == 1
                                      ? '${r.tipo.nombre} agregada'
                                      : '${r.cantidad} ${r.tipo.plural.toLowerCase()} agregadas');
                              if (mounted) setState(() => _planta = r.planta);
                            }),
                  _Accion(
                      'Fondo${fondos[planta] != null ? ' ✓' : ''}',
                      Icons.wallpaper_rounded,
                      _ocupado
                          ? null
                          : () async {
                              final b = await elegirImagen(lado: 1400);
                              if (b == null) return;
                              await _hacer(() async {
                                final url = await ref
                                    .read(archivosProvider)
                                    .subirDiseno(b, 'fondo-$club-$planta.jpg');
                                await repo.guardarFondo(club, planta, url);
                                ref.invalidate(fondosProvider);
                              }, ok: 'Fondo de ${nombrePiso(planta)} actualizado');
                            }),
                  if (todas.isEmpty)
                    _Accion('Copiar de otro evento', Icons.content_copy_rounded,
                        () => _copiarDeOtro(ev, club)),
                  _Accion('Agregar piso', Icons.layers_outlined, () => _agregarPiso(pisos)),
                ],
              ]),
              const SizedBox(height: 12),
              if (enLista)
                _ListaMesas(
                  mesas: enPlanta,
                  teams: teams,
                  conPlata: !esPortero,
                  alTocar: tocar,
                  vacio: 'No hay mesas en ${nombrePiso(planta)}.'
                      '${esAdmin ? ' Agregalas con "Editar mesas".' : ''}',
                ),
              // El plano se puede ampliar y desplazar con dos dedos. En modo
              // mover, un dedo arrastra la mesa y el plano queda quieto.
              if (!enLista) Builder(builder: (context) {
                // El visor necesita un alto propio: dentro de una lista no
                // tiene de dónde sacarlo y el plano quedaba invisible.
                final visible = MediaQuery.of(context).size.width - 32;
                final ancho = visible < 640 ? 640.0 : visible;
                final proporcion = ref.watch(proporcionPlanoProvider(fondos[planta])).value ??
                    Plano.proporcion;
                return SizedBox(
                  height: ancho / proporcion,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(16),
                    child: InteractiveViewer(
                      minScale: 1,
                      maxScale: 5,
                      panEnabled: !_mover,
                      constrained: false,
                      child: SizedBox(
                        width: ancho,
                        child: RepaintBoundary(
                          key: _planoKey,
                          child: Plano(
                            mesas: enPlanta,
                            planta: planta,
                            fondoUrl: fondos[planta],
                            aspecto: proporcion,
                            mover: _editando && _mover,
                            teams: teams,
                            alTocar: tocar,
                            alMover: (m, x, y) async {
                              try {
                                await repo.mover(m.id, x, y);
                                ref.invalidate(mesasProvider);
                                return true;
                              } catch (e) {
                                if (context.mounted) {
                                  avisar(context, mensajeDeError(e), tipo: TipoAviso.aviso);
                                }
                                return false;
                              }
                            },
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              }),
              if (!enLista && (MediaQuery.of(context).size.width - 32) < 640)
                Padding(
                  padding: EdgeInsets.only(top: 6),
                  child: Text('← deslizá el plano de lado →',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: VenueColors.textoSuave, fontSize: 12)),
                ),
              const SizedBox(height: 10),
              if (!enLista) const LeyendaPlano(),
              const SizedBox(height: 6),
              if (!enLista) Text(
                _editando
                    ? (_mover
                        ? 'Arrastrá una mesa para acomodarla · tocá para editarla'
                        : 'Posiciones bloqueadas — activá Mover para arrastrar · tocá para editar')
                    : esPortero
                        ? 'Tocá una mesa para ver el nombre y su combo'
                        : 'Tocá una mesa para venderla o ver su detalle · pellizcá para ampliar',
                style: TextStyle(color: VenueColors.textoSuave, fontSize: 12.5),
              ),
              if (todas.isEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 24),
                  child: MensajeVista(
                    icono: Icons.table_bar_outlined,
                    titulo: 'Este evento todavía no tiene mesas',
                    detalle: esAdmin
                        ? 'Tocá "Editar ${enLista ? 'mesas' : 'plano'}" para agregarlas o copiarlas de otro evento.'
                        : 'Las carga el administrador del boliche.',
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

class _Accion extends StatelessWidget {
  const _Accion(this.texto, this.icono, this.alTocar);
  final String texto;
  final IconData icono;
  final VoidCallback? alTocar;

  @override
  Widget build(BuildContext context) => OutlinedButton.icon(
        style: OutlinedButton.styleFrom(
            minimumSize: const Size(0, 42),
            padding: const EdgeInsets.symmetric(horizontal: 12),
            textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
        onPressed: alTocar,
        icon: Icon(icono, size: 18),
        label: Text(texto),
      );
}


/// Pedir el nombre de un piso nuevo, con sugerencias.
Future<String?> _pedirPiso(BuildContext context, List<String> yaHay) {
  final c = TextEditingController();
  final sugeridos = ['Planta baja', 'Planta alta', 'Piso 1', 'Piso 2', 'Piso 3', 'Terraza', 'Rooftop', 'Sector VIP']
      .where((n) => !yaHay.any((p) => nombrePiso(p).toLowerCase() == n.toLowerCase()))
      .toList();
  return showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    backgroundColor: VenueColors.superficie,
    builder: (ctx) => Padding(
      padding: EdgeInsets.fromLTRB(20, 0, 20, 24 + MediaQuery.of(ctx).viewInsets.bottom),
      child: StatefulBuilder(
        builder: (ctx, set) => Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const Text('Agregar piso', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
          const SizedBox(height: 12),
          TextField(
            controller: c,
            autofocus: true,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(labelText: 'Nombre del piso', hintText: 'Terraza, Piso 2, Sector VIP…'),
            onChanged: (_) => set(() {}),
          ),
          const SizedBox(height: 10),
          Wrap(spacing: 8, runSpacing: 6, children: [
            for (final n in sugeridos)
              ActionChip(label: Text(n), onPressed: () => set(() => c.text = n)),
          ]),
          const SizedBox(height: 10),
          Text(
            'El piso queda guardado cuando le agregás la primera mesa. Con el dibujo del piso '
            '(Fondo) se ve como plano; sin dibujo, las mesas se ven como lista.',
            style: TextStyle(color: VenueColors.textoSuave, fontSize: 13, height: 1.35),
          ),
          const SizedBox(height: 14),
          FilledButton(
            onPressed: c.text.trim().isEmpty ? null : () => Navigator.pop(ctx, c.text.trim()),
            child: const Text('Agregar piso'),
          ),
        ]),
      ),
    ),
  );
}

/// Agregar una o varias mesas de un tipo, en el piso que se elija.
Future<({TipoMesa tipo, int cantidad, String planta})?> _hojaNuevasMesas(
    BuildContext context, List<String> pisos, String planta, List<Mesa> todas) {
  var tipo = tiposMesa.first;
  var cantidad = 1;
  var piso = planta;
  final nuevo = TextEditingController();
  const otro = '__nuevo';
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    backgroundColor: VenueColors.superficie,
    builder: (ctx) => Padding(
      padding: EdgeInsets.fromLTRB(20, 0, 20, 24 + MediaQuery.of(ctx).viewInsets.bottom),
      child: StatefulBuilder(builder: (ctx, set) {
        final desde = todas.where((m) => m.tipo.id == tipo.id).length + 1;
        final destino = piso == otro ? idDePiso(nuevo.text) : piso;
        return Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const Text('Agregar mesas', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
          const SizedBox(height: 12),
          const Text('Tipo', style: TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(height: 6),
          Wrap(spacing: 8, runSpacing: 6, children: [
            for (final t in tiposMesa)
              ChoiceChip(
                label: Text(t.nombre),
                selected: t.id == tipo.id,
                showCheckmark: false,
                onSelected: (_) => set(() => tipo = t),
              ),
          ]),
          const SizedBox(height: 14),
          Row(children: [
            const Expanded(child: Text('Cuántas', style: TextStyle(fontWeight: FontWeight.w600))),
            IconButton.outlined(
                onPressed: cantidad > 1 ? () => set(() => cantidad--) : null,
                icon: const Icon(Icons.remove_rounded)),
            SizedBox(
                width: 44,
                child: Text('$cantidad',
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800))),
            IconButton.outlined(
                onPressed: cantidad < 40 ? () => set(() => cantidad++) : null,
                icon: const Icon(Icons.add_rounded)),
          ]),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            borderRadius: BorderRadius.circular(12),
            dropdownColor: VenueColors.superficie,
            icon: Icon(Icons.keyboard_arrow_down_rounded, color: VenueColors.textoSuave),
            initialValue: piso,
            decoration: const InputDecoration(labelText: 'Piso'),
            items: [
              for (final p in pisos) DropdownMenuItem(value: p, child: Text(nombrePiso(p))),
              const DropdownMenuItem(value: otro, child: Text('Nuevo piso…')),
            ],
            onChanged: (v) => set(() => piso = v!),
          ),
          if (piso == otro) ...[
            const SizedBox(height: 10),
            TextField(
              controller: nuevo,
              decoration: const InputDecoration(labelText: 'Nombre del piso nuevo', hintText: 'Terraza, Piso 2…'),
              onChanged: (_) => set(() {}),
            ),
          ],
          const SizedBox(height: 10),
          Text(
            cantidad == 1
                ? 'Se crea ${tipo.prefijo}$desde. Después le podés cambiar el nombre.'
                : 'Se crean ${tipo.prefijo}$desde a ${tipo.prefijo}${desde + cantidad - 1}. Después les podés cambiar el nombre.',
            style: TextStyle(color: VenueColors.textoSuave, fontSize: 13),
          ),
          const SizedBox(height: 14),
          FilledButton(
            onPressed: destino.isEmpty
                ? null
                : () => Navigator.pop(ctx, (tipo: tipo, cantidad: cantidad, planta: destino)),
            child: const Text('Agregar'),
          ),
        ]);
      }),
    ),
  );
}

/// Mesas de un piso sin plano: tarjetas agrupadas por tipo.
class _ListaMesas extends StatelessWidget {
  const _ListaMesas({
    required this.mesas,
    required this.teams,
    required this.conPlata,
    required this.alTocar,
    required this.vacio,
  });
  final List<Mesa> mesas;
  final Map<String, String> teams;
  final bool conPlata;
  final ValueChanged<Mesa> alTocar;
  final String vacio;

  Color _color(BuildContext context, String estado) => switch (estado) {
        'reservada' => VenueColors.aviso,
        'pagada' => VenueColors.ok,
        'ocupada' => Theme.of(context).colorScheme.primary,
        _ => VenueColors.textoSuave,
      };

  @override
  Widget build(BuildContext context) {
    if (mesas.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 28),
        child: Text(vacio, textAlign: TextAlign.center, style: TextStyle(color: VenueColors.textoSuave)),
      );
    }
    final porTipo = <String, List<Mesa>>{};
    for (final m in mesas) {
      porTipo.putIfAbsent(m.tipo.id, () => []).add(m);
    }
    int pos(String id) {
      final i = tiposMesa.indexWhere((t) => t.id == id);
      return i < 0 ? tiposMesa.length : i;
    }
    final orden = porTipo.keys.toList()..sort((a, b) => pos(a).compareTo(pos(b)));
    int natural(Mesa a, Mesa b) {
      final na = int.tryParse(a.etiqueta.replaceAll(RegExp(r'\D'), ''));
      final nb = int.tryParse(b.etiqueta.replaceAll(RegExp(r'\D'), ''));
      return na != null && nb != null && na != nb ? na.compareTo(nb) : a.etiqueta.compareTo(b.etiqueta);
    }

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      for (final t in orden) ...[
        Padding(
          padding: const EdgeInsets.fromLTRB(2, 6, 2, 8),
          child: Row(children: [
            Text(tipoMesa(t).plural, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
            const SizedBox(width: 8),
            Text('${porTipo[t]!.where((m) => m.libre).length} libres de ${porTipo[t]!.length}',
                style: TextStyle(fontSize: 13, color: VenueColors.textoSuave)),
          ]),
        ),
        LayoutBuilder(builder: (context, c) {
          final cols = c.maxWidth >= 700 ? 4 : c.maxWidth >= 460 ? 3 : 2;
          const gap = 10.0;
          final ancho = (c.maxWidth - gap * (cols - 1)) / cols;
          return Wrap(spacing: gap, runSpacing: gap, children: [
            for (final m in porTipo[t]!..sort(natural))
              SizedBox(
                width: ancho,
                child: Material(
                  color: VenueColors.superficie,
                  borderRadius: BorderRadius.circular(16),
                  clipBehavior: Clip.antiAlias,
                  elevation: 0,
                  child: InkWell(
                    onTap: () => alTocar(m),
                    child: Container(
                      padding: const EdgeInsets.fromLTRB(12, 10, 10, 10),
                      decoration: BoxDecoration(
                        border: Border(left: BorderSide(color: _color(context, m.estado), width: 4)),
                      ),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Row(children: [
                          Text(m.etiqueta, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
                          const Spacer(),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: _color(context, m.estado).withValues(alpha: .14),
                              borderRadius: BorderRadius.circular(99),
                            ),
                            child: Text(etiquetaEstado[m.estado] ?? m.estado,
                                style: TextStyle(
                                    fontSize: 11.5, fontWeight: FontWeight.w600, color: _color(context, m.estado))),
                          ),
                        ]),
                        const SizedBox(height: 4),
                        Text(m.libre ? 'Libre' : ((m.cliente ?? '').trim().isEmpty ? '—' : m.cliente!.trim()),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w500)),
                        Text(
                          [
                            if (m.teamId != null && teams[m.teamId] != null) teams[m.teamId]!,
                            if (conPlata && m.precio > 0) '${m.precio} Bs',
                          ].join(' · '),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 12.5, color: VenueColors.textoSuave),
                        ),
                      ]),
                    ),
                  ),
                ),
              ),
          ]);
        }),
        const SizedBox(height: 8),
      ],
    ]);
  }
}
