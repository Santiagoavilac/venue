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
        final pisos = pisosDe(todas);
        final planta = pisos.contains(_planta) ? _planta! : pisos.first;
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
                    style: const TextStyle(color: VenueColors.aviso, height: 1.35),
                  ),
                ),
              const SizedBox(height: 10),
              if (pisos.length > 1)
                SegmentedButton<String>(
                  showSelectedIcon: false,
                  segments: [
                    for (final p in pisos)
                      ButtonSegment(value: p, label: Text(etiquetaPiso[p] ?? p)),
                  ],
                  selected: {planta},
                  onSelectionChanged: (s) => setState(() => _planta = s.first),
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
                if (!_editando)
                  _Accion('Guardar imagen', Icons.image_outlined,
                      () => _guardarImagen(ev, planta)),
                if (esAdmin && !_editando) ...[
                  _Accion('Editar plano', Icons.edit_location_alt_outlined,
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
                  _Accion('Mesa', Icons.add_rounded,
                      _ocupado ? null : () => _hacer(() => repo.crear(ev.id, planta, 'mesa', todas.length + 1), ok: 'Mesa agregada')),
                  _Accion('Lounge', Icons.add_rounded,
                      _ocupado ? null : () => _hacer(() => repo.crear(ev.id, planta, 'lounge', todas.length + 1), ok: 'Lounge agregado')),
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
                              }, ok: 'Fondo de ${etiquetaPiso[planta] ?? planta} actualizado');
                            }),
                  if (todas.isEmpty)
                    _Accion('Copiar de otro evento', Icons.content_copy_rounded,
                        () => _copiarDeOtro(ev, club)),
                  for (final p in ordenPisos.where((p) => !pisos.contains(p)).take(1))
                    _Accion('Piso: ${etiquetaPiso[p]}', Icons.layers_outlined,
                        () => setState(() => _planta = p)),
                ],
              ]),
              const SizedBox(height: 12),
              // El plano se puede ampliar y desplazar con dos dedos. En modo
              // mover, un dedo arrastra la mesa y el plano queda quieto.
              ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: InteractiveViewer(
                  minScale: 1,
                  maxScale: 5,
                  panEnabled: !_mover,
                  constrained: false,
                  child: SizedBox(
                    width: (MediaQuery.of(context).size.width - 32).clamp(640.0, 2000.0),
                    child: RepaintBoundary(
                      key: _planoKey,
                      child: Plano(
                        mesas: enPlanta,
                        planta: planta,
                        fondoUrl: fondos[planta],
                        mover: _editando && _mover,
                        teams: teams,
                        alTocar: tocar,
                        alMover: (m, x, y) async {
                          try {
                            await repo.mover(m.id, x, y);
                            ref.invalidate(mesasProvider);
                          } catch (e) {
                            if (context.mounted) {
                              avisar(context, mensajeDeError(e), tipo: TipoAviso.aviso);
                            }
                          }
                        },
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              const LeyendaPlano(),
              const SizedBox(height: 6),
              Text(
                _editando
                    ? (_mover
                        ? 'Arrastrá una mesa para acomodarla · tocá para editarla'
                        : 'Posiciones bloqueadas — activá Mover para arrastrar · tocá para editar')
                    : esPortero
                        ? 'Tocá una mesa para ver el nombre y su combo'
                        : 'Tocá una mesa para venderla o ver su detalle · pellizcá para ampliar',
                style: const TextStyle(color: VenueColors.textoSuave, fontSize: 12.5),
              ),
              if (todas.isEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 24),
                  child: MensajeVista(
                    icono: Icons.table_bar_outlined,
                    titulo: 'Este evento todavía no tiene mesas',
                    detalle: esAdmin
                        ? 'Tocá "Editar plano" para agregarlas o copiarlas de otro evento.'
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
