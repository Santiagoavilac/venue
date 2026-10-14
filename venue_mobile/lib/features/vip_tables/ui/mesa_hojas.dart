import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/media/imagenes.dart';
import '../../../core/networking/supabase.dart';
import '../../../core/theme/venue_theme.dart';
import '../../../core/widgets/avisos.dart';
import '../../authentication/data/sesion.dart';
import '../../clubs/data/clubs.dart';
import '../../events/data/eventos.dart';
import '../../guestlists/data/listas.dart';
import '../../teams/data/equipo.dart';
import '../../tickets/data/entradas.dart';
import '../../tickets/ui/ticket_sheet.dart';
import '../data/mesas.dart';

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

/// Imagen de un comprobante: pide la URL firmada y la muestra. Si la persona
/// no tiene permiso, lo dice en vez de mostrar una imagen rota.
class ImagenComprobante extends ConsumerWidget {
  const ImagenComprobante({super.key, required this.referencia, this.ancho = 240});
  final String referencia;
  final double ancho;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return FutureBuilder(
      future: ref.read(archivosProvider).urlComprobante(referencia),
      builder: (context, s) {
        if (s.connectionState != ConnectionState.done) {
          return SizedBox(
              width: ancho, height: 120, child: const Center(child: CircularProgressIndicator()));
        }
        if (s.data == null) {
          return const Text('No tenés permiso para ver este comprobante.',
              style: TextStyle(color: VenueColors.textoSuave));
        }
        return ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: Image.network(s.data!, width: ancho, fit: BoxFit.contain),
        );
      },
    );
  }
}

// ───────────────────────── seguridad ─────────────────────────
/// El portero ve el nombre y el combo. Nada de plata.
Future<void> hojaMesaSeguridad(BuildContext context, Mesa m, Combo? combo) => _hoja(
      context,
      Padding(
        padding: const EdgeInsets.fromLTRB(22, 0, 22, 26),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('${m.esLounge ? 'Lounge' : 'Mesa'} ${m.etiqueta}',
                style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
            const SizedBox(height: 10),
            if (m.libre)
              const Text('Libre', style: TextStyle(color: VenueColors.textoSuave))
            else ...[
              Text(m.cliente ?? '—',
                  style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w800)),
              const SizedBox(height: 4),
              Text(
                [
                  if (combo != null) '${m.comboQty} × ${combo.nombre}',
                  etiquetaEstado[m.estado] ?? m.estado,
                ].join(' · '),
                style: const TextStyle(color: VenueColors.textoSuave, fontSize: 16),
              ),
            ],
          ],
        ),
      ),
    );

// ───────────────────────── vender ─────────────────────────
Future<bool> hojaVenderMesa(BuildContext context, Mesa mesa) async =>
    await _hoja<bool>(context, _VenderMesa(mesa: mesa)) ?? false;

class _VenderMesa extends ConsumerStatefulWidget {
  const _VenderMesa({required this.mesa});
  final Mesa mesa;

  @override
  ConsumerState<_VenderMesa> createState() => _VenderMesaState();
}

class _VenderMesaState extends ConsumerState<_VenderMesa> {
  final _cliente = TextEditingController();
  final _botellas = TextEditingController();
  final _manillas = TextEditingController(text: '0');
  final _nombres = TextEditingController();
  String? _combo;
  int _cantidad = 1;
  final _extra = <String>{};
  String? _aNombreDe;
  bool _cortesia = false;
  late String _estado;
  String _metodo = 'transferencia';
  String? _comprobante;
  Uint8List? _vista;
  bool _subiendo = false, _enviando = false, _verQr = false;

  @override
  void initState() {
    super.initState();
    final ev = ref.read(eventoActivoProvider)!;
    _estado = ev.permiteReserva ? 'reservada' : 'pagada';
  }

  @override
  void dispose() {
    for (final c in [_cliente, _botellas, _manillas, _nombres]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _foto({required bool camara}) async {
    final b = await elegirImagen(camara: camara);
    if (b == null) return;
    setState(() => _subiendo = true);
    try {
      final r = await ref
          .read(archivosProvider)
          .subirComprobante(b, 'mesa-${widget.mesa.id}');
      setState(() {
        _comprobante = r;
        _vista = b;
      });
    } catch (e) {
      if (mounted) avisar(context, mensajeDeError(e), tipo: TipoAviso.aviso);
    }
    if (mounted) setState(() => _subiendo = false);
  }

  @override
  Widget build(BuildContext context) {
    final m = widget.mesa;
    final ev = ref.watch(eventoActivoProvider)!;
    final rol = ref.watch(rolProvider).value;
    final todas = ref.watch(mesasProvider).value ?? const <Mesa>[];
    final combos = (ref.watch(combosProvider).value ?? const <Combo>[])
        .where((c) => c.activo)
        .toList();
    final permisos = ref.watch(permisosEventoProvider).value;
    final vendedores = ref.watch(vendedoresProvider).value ?? const <Miembro>[];
    final yo = ref.watch(usuarioIdProvider);
    final esAdmin = rol == Rol.admin;

    final cats = {
      m.categoria,
      for (final id in _extra) todas.firstWhere((x) => x.id == id).categoria,
    };
    final validos = combos.where((c) => c.valePara(cats)).toList();
    if (_combo != null && !validos.any((c) => c.id == _combo)) _combo = null;
    _combo ??= ev.comboObligatorio && validos.isNotEmpty ? validos.first.id : _combo;
    final combo = validos.where((c) => c.id == _combo).firstOrNull;
    final libresPiso = todas
        .where((x) => x.planta == m.planta && x.libre && x.id != m.id)
        .toList();
    final pagada = _estado == 'pagada';
    final transferencia = pagada && !_cortesia && _metodo == 'transferencia';
    final pideFoto = transferencia && !esAdmin;
    final incluidas = (combo?.incluyeManillas ?? 0) * _cantidad +
        (int.tryParse(_manillas.text) ?? 0);
    final total = _cortesia ? 0 : (combo?.precio ?? 0) * _cantidad;

    Future<void> confirmar() async {
      final cli = _cliente.text.trim();
      if (cli.isEmpty) {
        avisar(context, 'Nombre del cliente', tipo: TipoAviso.aviso);
        return;
      }
      if (_combo == null && ev.comboObligatorio) {
        avisar(context,
            'No hay ningún combo habilitado para este tipo de mesa. Pedile al admin que habilite uno.',
            tipo: TipoAviso.aviso);
        return;
      }
      setState(() => _enviando = true);
      try {
        final repo = ref.read(mesasRepositoryProvider);
        final r = await repo.vender(
          [m.id, ..._extra],
          DatosVenta(
            cliente: cli,
            comboId: _combo,
            estado: _estado,
            cantidad: _cantidad,
            botellas: _botellas.text
                .split(',')
                .map((s) => s.trim())
                .where((s) => s.isNotEmpty)
                .toList(),
            manillasExtra: int.tryParse(_manillas.text) ?? 0,
            comprobante: transferencia ? _comprobante : null,
            efectivo: pagada && _metodo == 'efectivo',
            aNombreDe: _aNombreDe,
            cortesia: _cortesia,
          ),
        );
        // cada nombre genera su manilla con QR, incluida en el combo
        var manillas = 0;
        for (final n in separarNombres(_nombres.text)) {
          try {
            await ref.read(supabaseProvider).rpc('generar_entrada',
                params: {'p_evento': ev.id, 'p_cliente': n, 'p_mesa': r.primaria});
            manillas++;
          } catch (_) {}
        }
        ref.invalidate(mesasProvider);
        if (!context.mounted) return;
        Navigator.pop(context, true);
        final extra = manillas > 0 ? ' · $manillas manilla(s) con QR' : '';
        avisar(
          context,
          _estado == 'reservada'
              ? '${r.etiqueta} reservada$extra — tenés ${ev.horasReserva} h para confirmar el pago o se libera sola'
              : esAdmin
                  ? '${r.etiqueta} vendida · ${r.precio} Bs$extra'
                  : '${r.etiqueta} pagada en $_metodo · por verificar$extra',
          tipo: _estado == 'pagada' && esAdmin ? TipoAviso.ok : TipoAviso.aviso,
        );
      } catch (e) {
        if (context.mounted) {
          avisar(context, mensajeDeError(e), tipo: TipoAviso.aviso);
          setState(() => _enviando = false);
        }
      }
    }

    return ListView(
      shrinkWrap: true,
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
      children: [
        Text('Vender ${m.etiqueta} · ${m.esLounge ? 'Lounge' : 'Mesa'}',
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
        const SizedBox(height: 14),
        TextField(
          controller: _cliente,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(labelText: 'Cliente'),
        ),
        const SizedBox(height: 12),
        DropdownButtonFormField<String?>(
          initialValue: _combo,
          isExpanded: true,
          decoration: InputDecoration(
              labelText: ev.comboObligatorio ? 'Combo' : 'Combo (opcional)'),
          items: [
            if (!ev.comboObligatorio)
              const DropdownMenuItem<String?>(value: null, child: Text('Sin combo — 0 Bs')),
            for (final c in validos)
              DropdownMenuItem<String?>(
                value: c.id,
                child: Text(
                    '${c.nombre} · ${c.precio} Bs${c.incluyeManillas > 0 ? ' · ${c.incluyeManillas} manillas' : ''}',
                    overflow: TextOverflow.ellipsis),
              ),
          ],
          onChanged: (v) => setState(() => _combo = v),
        ),
        if (validos.isEmpty && ev.comboObligatorio)
          const Padding(
            padding: EdgeInsets.only(top: 6),
            child: Text('Ningún combo habilitado para este tipo de mesa.',
                style: TextStyle(color: VenueColors.aviso)),
          ),
        const SizedBox(height: 12),
        Row(children: [
          const Expanded(child: Text('Cantidad de combos')),
          IconButton.filledTonal(
              onPressed: () => setState(() => _cantidad = (_cantidad - 1).clamp(1, 20)),
              icon: const Icon(Icons.remove_rounded)),
          SizedBox(
              width: 44,
              child: Text('$_cantidad',
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800))),
          IconButton.filledTonal(
              onPressed: () => setState(() => _cantidad = (_cantidad + 1).clamp(1, 20)),
              icon: const Icon(Icons.add_rounded)),
        ]),
        Text(_cortesia ? 'Total: 0 Bs (cortesía)' : 'Total: $total Bs',
            style: const TextStyle(fontWeight: FontWeight.w700)),
        if (libresPiso.isNotEmpty && ev.permiteAgrupar) ...[
          const SizedBox(height: 14),
          const Text('Sumar más mesas al mismo combo (opcional)'),
          const SizedBox(height: 6),
          Wrap(spacing: 8, runSpacing: 4, children: [
            for (final x in libresPiso)
              FilterChip(
                label: Text(x.etiqueta),
                selected: _extra.contains(x.id),
                onSelected: (v) =>
                    setState(() => v ? _extra.add(x.id) : _extra.remove(x.id)),
              ),
          ]),
          Text(
            ev.comboPorMesa
                ? 'Cada mesa paga su propio combo.'
                : 'El combo se cobra una sola vez para todas las mesas seleccionadas.',
            style: const TextStyle(color: VenueColors.textoSuave, fontSize: 12.5),
          ),
        ],
        const SizedBox(height: 12),
        Row(children: [
          Expanded(
            child: TextField(
              controller: _botellas,
              decoration: const InputDecoration(
                  labelText: 'Botellas (opcional)', hintText: 'Vodka, Fernet'),
            ),
          ),
          if (rol != Rol.rrpp) ...[
            const SizedBox(width: 10),
            SizedBox(
              width: 120,
              child: TextField(
                controller: _manillas,
                keyboardType: TextInputType.number,
                onChanged: (_) => setState(() {}),
                decoration: const InputDecoration(labelText: 'Manillas extra'),
              ),
            ),
          ],
        ]),
        const SizedBox(height: 12),
        TextField(
          controller: _nombres,
          minLines: 2,
          maxLines: 5,
          textCapitalization: TextCapitalization.words,
          decoration: InputDecoration(
            labelText: 'Nombres de las manillas (incluye $incluidas)',
            hintText: 'Uno por línea. Podés cargarlos después.',
            helperText: 'Cada nombre genera su entrada con QR, incluida en el combo.',
          ),
        ),
        if (permisos?.aNombreDe ?? false) ...[
          const SizedBox(height: 12),
          DropdownButtonFormField<String?>(
            initialValue: _aNombreDe,
            isExpanded: true,
            decoration: const InputDecoration(
              labelText: 'A nombre de',
              helperText: 'La mesa y su comisión quedan de quien elijas.',
            ),
            items: [
              const DropdownMenuItem<String?>(value: null, child: Text('Vos')),
              for (final v in vendedores.where((v) => v.id != yo))
                DropdownMenuItem<String?>(
                    value: v.id,
                    child: Text(
                        v.team == 'Sin team' ? v.nombre : '${v.nombre} · ${v.team}',
                        overflow: TextOverflow.ellipsis)),
            ],
            onChanged: (v) => setState(() => _aNombreDe = v),
          ),
        ],
        if (permisos?.cortesia ?? false) ...[
          const SizedBox(height: 12),
          SegmentedButton<bool>(
            showSelectedIcon: false,
            segments: const [
              ButtonSegment(value: false, label: Text('Se cobra')),
              ButtonSegment(value: true, label: Text('Cortesía')),
            ],
            selected: {_cortesia},
            onSelectionChanged: (s) => setState(() => _cortesia = s.first),
          ),
          Text(
            _cortesia
                ? 'Queda en 0 Bs. No se pide comprobante ni genera comisión.'
                : 'Una cortesía mantiene el combo pero queda en 0 Bs y no paga comisión.',
            style: const TextStyle(color: VenueColors.textoSuave, fontSize: 12.5),
          ),
        ],
        const SizedBox(height: 12),
        DropdownButtonFormField<String>(
          initialValue: _estado,
          decoration: InputDecoration(
            labelText: 'Estado',
            helperText: !ev.permiteReserva
                ? 'En este evento las mesas se venden solo pagadas.'
                : !pagada
                    ? 'Si en ${ev.horasReserva} horas no se confirma el pago, la reserva se libera sola.'
                    : esAdmin
                        ? 'Queda pagada y verificada.'
                        : 'Queda como pagada · por verificar, hasta que el admin confirme.',
            helperMaxLines: 2,
          ),
          items: [
            if (ev.permiteReserva)
              DropdownMenuItem(
                  value: 'reservada',
                  child: Text('Reservada — ${ev.horasReserva} h para pagar')),
            const DropdownMenuItem(value: 'pagada', child: Text('Ya pagó')),
          ],
          onChanged: (v) => setState(() => _estado = v!),
        ),
        if (pagada && !_cortesia) ...[
          const SizedBox(height: 12),
          SegmentedButton<String>(
            showSelectedIcon: false,
            segments: const [
              ButtonSegment(value: 'transferencia', label: Text('Transferencia')),
              ButtonSegment(value: 'efectivo', label: Text('Efectivo')),
            ],
            selected: {_metodo},
            onSelectionChanged: (s) => setState(() => _metodo = s.first),
          ),
          if (transferencia) ...[
            const SizedBox(height: 10),
            OutlinedButton.icon(
              onPressed: () => setState(() => _verQr = !_verQr),
              icon: const Icon(Icons.qr_code_rounded),
              label: Text(_verQr ? 'Ocultar QR' : 'Ver QR para que pague'),
            ),
            if (_verQr) const QrDeCobro(),
            const SizedBox(height: 10),
            if (_vista != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Center(
                  child: ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: Image.memory(_vista!, width: 200)),
                ),
              ),
            Row(children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _subiendo ? null : () => _foto(camara: true),
                  icon: const Icon(Icons.photo_camera_outlined),
                  label: const Text('Foto'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _subiendo ? null : () => _foto(camara: false),
                  icon: const Icon(Icons.image_outlined),
                  label: Text(_comprobante == null ? 'Galería' : 'Cambiar'),
                ),
              ),
            ]),
          ],
        ],
        const SizedBox(height: 18),
        FilledButton(
          onPressed: _enviando || _subiendo || (pideFoto && _comprobante == null)
              ? null
              : confirmar,
          child: Text(pideFoto && _comprobante == null
              ? 'Subí el comprobante para confirmar'
              : 'Confirmar venta'),
        ),
      ],
    );
  }
}

/// QR de cobro vigente del boliche: a esa cuenta entra la plata de las mesas.
class QrDeCobro extends ConsumerWidget {
  const QrDeCobro({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final club = ref.watch(clubActivoIdProvider);
    if (club == null) return const SizedBox.shrink();
    return FutureBuilder(
      future: ref.read(mesasRepositoryProvider).qrCobro(club),
      builder: (context, s) {
        if (s.connectionState != ConnectionState.done) {
          return const Padding(
              padding: EdgeInsets.all(16),
              child: Center(child: CircularProgressIndicator()));
        }
        final q = s.data;
        if (q == null) {
          return const Padding(
            padding: EdgeInsets.all(12),
            child: Text('El admin todavía no cargó ningún QR de cobro.',
                style: TextStyle(color: VenueColors.aviso)),
          );
        }
        return Column(children: [
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(9),
            decoration: BoxDecoration(
                color: Colors.white, borderRadius: BorderRadius.circular(12)),
            child: Image.network(q.url, width: 230, fit: BoxFit.contain),
          ),
          const SizedBox(height: 6),
          Text('La plata de las mesas entra siempre a ${q.nombre}.',
              textAlign: TextAlign.center,
              style: const TextStyle(color: VenueColors.textoSuave, fontSize: 13)),
        ]);
      },
    );
  }
}

// ───────────────────────── mesa vendida ─────────────────────────
Future<void> hojaMesaVendida(BuildContext context, Mesa mesa) =>
    _hoja(context, _MesaVendida(mesa: mesa));

final _manillasMesaProvider =
    FutureProvider.autoDispose.family<List<Entrada>, String>((ref, mesaId) async {
  final r = await ref
      .watch(supabaseProvider)
      .from('entradas')
      .select('id, code, cliente, precio, estado, used_at, rrpp_id, fase_id, filtro_at')
      .eq('mesa_id', mesaId)
      .order('created_at', ascending: true);
  return r.map(Entrada.desde).toList();
});

class _MesaVendida extends ConsumerStatefulWidget {
  const _MesaVendida({required this.mesa});
  final Mesa mesa;

  @override
  ConsumerState<_MesaVendida> createState() => _MesaVendidaState();
}

class _MesaVendidaState extends ConsumerState<_MesaVendida> {
  final _nuevas = TextEditingController();
  List<Mesa>? _grupo;
  bool _ocupado = false;

  @override
  void initState() {
    super.initState();
    final g = widget.mesa.grupoId;
    if (g != null) {
      ref.read(mesasRepositoryProvider).grupo(g).then((l) {
        if (mounted) setState(() => _grupo = l);
      });
    }
  }

  @override
  void dispose() {
    _nuevas.dispose();
    super.dispose();
  }

  Future<void> _hacer(Future<void> Function() f, {String? ok, bool cerrar = true}) async {
    setState(() => _ocupado = true);
    try {
      await f();
      ref.invalidate(mesasProvider);
      if (!mounted) return;
      if (cerrar) Navigator.pop(context);
      if (ok != null) avisar(context, ok);
    } catch (e) {
      if (mounted) avisar(context, mensajeDeError(e), tipo: TipoAviso.aviso);
    }
    if (mounted) setState(() => _ocupado = false);
  }

  @override
  Widget build(BuildContext context) {
    final m = widget.mesa;
    final ev = ref.watch(eventoActivoProvider)!;
    final rol = ref.watch(rolProvider).value;
    final yo = ref.watch(usuarioIdProvider);
    final equipo = ref.watch(equipoProvider).value ?? const <String, Miembro>{};
    final combos = {
      for (final c in ref.watch(combosProvider).value ?? const <Combo>[]) c.id: c
    };
    final grupo = _grupo ?? [m];
    // la mesa primaria (precio > 0) lleva el combo y las manillas del grupo
    final prim = grupo.where((x) => x.precio > 0).firstOrNull ?? grupo.first;
    final combo = combos[prim.comboId];
    final esGrupo = grupo.length > 1;
    final esAdmin = rol == Rol.admin;
    final mia = m.vendidoPor == yo;
    // el jefe solo mira las mesas ajenas; las suyas las gestiona
    final soloVer = rol == Rol.jefe && !mia;
    final gestiona = esAdmin || mia;
    final repo = ref.read(mesasRepositoryProvider);
    final manillas = ref.watch(_manillasMesaProvider(prim.id));
    final incluidas = (combo?.incluyeManillas ?? 0) * prim.comboQty + prim.manillas;
    final vendedor = equipo[m.vendidoPor];
    final vence = m.vence(ev.horasReserva);
    final club = ref.watch(clubActivoProvider);

    return ListView(
      shrinkWrap: true,
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
      children: [
        Text(
          esGrupo ? grupo.map((x) => x.etiqueta).join(' + ') : '${m.esLounge ? 'Lounge' : 'Mesa'} ${m.etiqueta}',
          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 6),
        Text(prim.cliente ?? '—',
            style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800)),
        const SizedBox(height: 4),
        Text(
          [
            if (combo != null) '${prim.comboQty} × ${combo.nombre}',
            prim.cortesia ? 'Cortesía · 0 Bs' : '${prim.precio} Bs',
            etiquetaEstado[m.estado] ?? m.estado,
          ].join(' · '),
          style: const TextStyle(color: VenueColors.textoSuave, fontSize: 15),
        ),
        if (vendedor != null)
          Text('La vendió ${vendedor.nombre} · ${vendedor.team}',
              style: const TextStyle(color: VenueColors.textoSuave)),
        if (prim.botellas.isNotEmpty)
          Text('Botellas: ${prim.botellas.join(', ')}',
              style: const TextStyle(color: VenueColors.textoSuave)),
        if (m.estado == 'reservada' && vence != null)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text('Reserva sin pago · vence ${horaCorta(vence)}',
                style: const TextStyle(
                    color: VenueColors.aviso, fontWeight: FontWeight.w700)),
          ),
        if (m.estado == 'pagada' && !prim.pagoVerificado && prim.precio > 0)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
                'Pago por verificar${prim.metodoPago == null ? '' : ' · cobrado en ${prim.metodoPago}'} — falta que el admin lo confirme',
                style: const TextStyle(
                    color: VenueColors.aviso, fontWeight: FontWeight.w700)),
          ),
        if (m.estado == 'pagada' && prim.pagoVerificado)
          const Padding(
            padding: EdgeInsets.only(top: 6),
            child: Text('Pago verificado',
                style: TextStyle(color: VenueColors.ok, fontWeight: FontWeight.w700)),
          ),
        if (prim.comprobanteUrl != null && (gestiona || rol == Rol.jefe)) ...[
          const SizedBox(height: 10),
          Center(child: ImagenComprobante(referencia: prim.comprobanteUrl!)),
        ],
        const Divider(height: 28),
        Text('Manillas (${manillas.value?.length ?? 0} de $incluidas)',
            style: const TextStyle(fontWeight: FontWeight.w800)),
        for (final e in manillas.value ?? const <Entrada>[])
          ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            title: Text(e.cliente),
            subtitle: Text('#${e.codigo} · ${e.estado == 'usada' ? 'ingresó' : e.estado}'),
            onTap: e.estado == 'anulada'
                ? null
                : () => mostrarTicket(
                      context,
                      TicketDatos(
                        payload: payloadEntrada(ev.id, e.codigo),
                        codigo: e.codigo,
                        cliente: e.cliente,
                        boliche: club?.nombre ?? '',
                        evento: ev.nombre,
                        fecha: ev.fechaCorta,
                        tipo: 'Manilla · ${prim.etiqueta}',
                        color: club?.primario,
                        arteUrl: ev.ticketUrl,
                      ),
                    ),
            trailing: gestiona && e.estado == 'valida'
                ? IconButton(
                    tooltip: 'Eliminar manilla',
                    icon: const Icon(Icons.close_rounded),
                    onPressed: () => _hacer(() async {
                      await ref.read(entradasRepositoryProvider).eliminar(e.id);
                      ref.invalidate(_manillasMesaProvider(prim.id));
                    }, ok: 'Manilla de ${e.cliente} eliminada', cerrar: false),
                  )
                : const Icon(Icons.qr_code_2_rounded),
          ),
        if ((gestiona || rol == Rol.jefe) && !soloVer) ...[
          TextField(
            controller: _nuevas,
            minLines: 1,
            maxLines: 4,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(
                hintText: 'Nombres de manillas, uno por línea'),
          ),
          const SizedBox(height: 8),
          OutlinedButton(
            onPressed: _ocupado
                ? null
                : () => _hacer(() async {
                      var n = 0;
                      for (final nm in separarNombres(_nuevas.text)) {
                        await ref.read(supabaseProvider).rpc('generar_entrada', params: {
                          'p_evento': ev.id, 'p_cliente': nm, 'p_mesa': prim.id,
                        });
                        n++;
                      }
                      _nuevas.clear();
                      ref.invalidate(_manillasMesaProvider(prim.id));
                      if (n == 0) throw const FormatException('Escribí al menos un nombre');
                    }, ok: 'Manillas generadas', cerrar: false),
            child: const Text('Generar QR de esas manillas'),
          ),
        ],
        if (!soloVer && (gestiona || rol == Rol.jefe)) ...[
          const Divider(height: 28),
          if (gestiona || rol == Rol.jefe)
            OutlinedButton.icon(
              onPressed: _ocupado ? null : () => _editar(prim, combos.values.toList()),
              icon: const Icon(Icons.edit_outlined),
              label: const Text('Editar nombre y combo'),
            ),
          if (m.estado != 'pagada') ...[
            const SizedBox(height: 9),
            OutlinedButton.icon(
              onPressed: () => _hoja(context,
                  const Padding(padding: EdgeInsets.fromLTRB(20, 0, 20, 26), child: QrDeCobro())),
              icon: const Icon(Icons.qr_code_rounded),
              label: const Text('Mostrar QR de cobro'),
            ),
            const SizedBox(height: 9),
            FilledButton.icon(
              onPressed: _ocupado ? null : () => _pagar(esAdmin),
              icon: const Icon(Icons.attach_file_rounded),
              label: Text('Marcar pagada${esGrupo ? ' (grupo)' : ''}'),
            ),
          ],
          if (esAdmin && m.estado == 'pagada' && !prim.pagoVerificado) ...[
            const SizedBox(height: 9),
            FilledButton.icon(
              onPressed: _ocupado
                  ? null
                  : () => _hacer(() => repo.verificar(m.id, true), ok: 'Pago confirmado'),
              icon: const Icon(Icons.check_rounded),
              label: const Text('Confirmar que el pago entró'),
            ),
            const SizedBox(height: 9),
            OutlinedButton(
              onPressed: _ocupado
                  ? null
                  : () => _hacer(() => repo.verificar(m.id, false),
                      ok: 'Pago rechazado: la mesa volvió a reservada'),
              style: OutlinedButton.styleFrom(foregroundColor: VenueColors.mal),
              child: const Text('Rechazar — volver a reservada'),
            ),
          ],
          if (m.estado != 'ocupada') ...[
            const SizedBox(height: 9),
            OutlinedButton(
              onPressed: _ocupado
                  ? null
                  : () => _hacer(() => repo.estado(m.id, 'ocupada'), ok: 'Mesa ocupada'),
              child: const Text('Marcar ocupada (llegaron)'),
            ),
          ],
          const SizedBox(height: 9),
          OutlinedButton(
            onPressed: _ocupado
                ? null
                : () async {
                    final si = await showDialog<bool>(
                      context: context,
                      builder: (c) => AlertDialog(
                        title: Text(
                            'Liberar ${esGrupo ? 'las ${grupo.length} mesas' : m.etiqueta}'),
                        content: Text(
                            'Se borra la venta de ${prim.cliente ?? 'esta mesa'}'
                            '${prim.precio > 0 ? ' (${prim.precio} Bs)' : ''} y sus manillas dejan de valer. No se puede deshacer.'),
                        actions: [
                          TextButton(
                              onPressed: () => Navigator.pop(c, false),
                              child: const Text('Cancelar')),
                          TextButton(
                              onPressed: () => Navigator.pop(c, true),
                              style: TextButton.styleFrom(
                                  foregroundColor: VenueColors.mal),
                              child: const Text('Liberar mesa')),
                        ],
                      ),
                    );
                    if (si == true) {
                      await _hacer(() => repo.estado(m.id, 'disponible'),
                          ok: 'Mesa liberada');
                    }
                  },
            style: OutlinedButton.styleFrom(foregroundColor: VenueColors.mal),
            child: Text('Liberar ${esGrupo ? 'las ${grupo.length} mesas' : 'mesa'}'),
          ),
        ],
      ],
    );
  }

  Future<void> _editar(Mesa prim, List<Combo> combos) async {
    final cli = TextEditingController(text: prim.cliente ?? '');
    String? combo = prim.comboId;
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, set) => AlertDialog(
          title: const Text('Editar venta'),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(
                controller: cli,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(labelText: 'Cliente')),
            const SizedBox(height: 12),
            DropdownButtonFormField<String?>(
              initialValue: combos.any((x) => x.id == combo) ? combo : null,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Combo'),
              items: [
                for (final x in combos.where((x) => x.activo || x.id == combo))
                  DropdownMenuItem<String?>(
                      value: x.id,
                      child: Text('${x.nombre} · ${x.precio} Bs',
                          overflow: TextOverflow.ellipsis)),
              ],
              onChanged: (v) => set(() => combo = v),
            ),
          ]),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(c, false), child: const Text('Cancelar')),
            FilledButton(
                onPressed: () => Navigator.pop(c, true),
                style: FilledButton.styleFrom(minimumSize: const Size(100, 44)),
                child: const Text('Guardar')),
          ],
        ),
      ),
    );
    if (ok == true) {
      await _hacer(
          () => ref
              .read(mesasRepositoryProvider)
              .editarVenta(prim.id, cli.text.trim(), combo),
          ok: 'Mesa actualizada');
    }
    cli.dispose();
  }

  /// Marcar pagada: el comprobante es obligatorio salvo para el admin o si
  /// se cobró en efectivo.
  Future<void> _pagar(bool esAdmin) async {
    final metodo = await showDialog<String>(
      context: context,
      builder: (c) => SimpleDialog(
        title: const Text('¿Cómo pagó?'),
        children: [
          SimpleDialogOption(
              onPressed: () => Navigator.pop(c, 'foto'),
              child: const Text('Transferencia · sacar foto del comprobante')),
          SimpleDialogOption(
              onPressed: () => Navigator.pop(c, 'galeria'),
              child: const Text('Transferencia · elegir de la galería')),
          SimpleDialogOption(
              onPressed: () => Navigator.pop(c, 'efectivo'),
              child: const Text('Efectivo')),
          if (esAdmin)
            SimpleDialogOption(
                onPressed: () => Navigator.pop(c, 'sin'),
                child: const Text('Transferencia · sin comprobante (admin)')),
        ],
      ),
    );
    if (metodo == null) return;
    await _hacer(() async {
      String? comp;
      if (metodo == 'foto' || metodo == 'galeria') {
        final b = await elegirImagen(camara: metodo == 'foto');
        if (b == null) throw const FormatException('No se eligió ninguna imagen');
        comp = await ref
            .read(archivosProvider)
            .subirComprobante(b, 'mesa-${widget.mesa.id}');
      }
      await ref
          .read(mesasRepositoryProvider)
          .pagar(widget.mesa.id, comprobante: comp, efectivo: metodo == 'efectivo');
    }, ok: esAdmin ? 'Mesa pagada y verificada' : 'Mesa pagada · por verificar');
  }
}

// ───────────────────────── editor de plano ─────────────────────────
Future<void> hojaEditarMesa(BuildContext context, Mesa mesa, List<String> pisos) =>
    _hoja(context, _EditarMesa(mesa: mesa, pisos: pisos));

class _EditarMesa extends ConsumerStatefulWidget {
  const _EditarMesa({required this.mesa, required this.pisos});
  final Mesa mesa;
  final List<String> pisos;

  @override
  ConsumerState<_EditarMesa> createState() => _EditarMesaState();
}

class _EditarMesaState extends ConsumerState<_EditarMesa> {
  late final _etiqueta = TextEditingController(text: widget.mesa.etiqueta);
  late String _cat = widget.mesa.categoria;
  late double _w = widget.mesa.w.clamp(8, 30).toDouble();
  late double _h = (widget.mesa.h ?? 21).clamp(8, 45).toDouble();
  late String? _team = widget.mesa.teamId;
  late String _planta = widget.mesa.planta;

  @override
  void dispose() {
    _etiqueta.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final m = widget.mesa;
    final teams = ref.watch(teamsClubProvider).value ?? const <String, String>{};
    final repo = ref.read(mesasRepositoryProvider);
    final pisos = {...ordenPisos.where((p) => widget.pisos.contains(p) || p == _planta), ...ordenPisos}.toList();

    Future<void> hacer(Future<void> Function() f, String ok) async {
      try {
        await f();
        ref.invalidate(mesasProvider);
        if (!context.mounted) return;
        Navigator.pop(context);
        avisar(context, ok);
      } catch (e) {
        if (context.mounted) avisar(context, mensajeDeError(e), tipo: TipoAviso.aviso);
      }
    }

    return ListView(
      shrinkWrap: true,
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
      children: [
        Text('Editar ${m.etiqueta}',
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
        const SizedBox(height: 14),
        Row(children: [
          Expanded(
            child: TextField(
                controller: _etiqueta,
                decoration: const InputDecoration(labelText: 'Etiqueta')),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: DropdownButtonFormField<String>(
              initialValue: _cat,
              decoration: const InputDecoration(labelText: 'Categoría'),
              items: const [
                DropdownMenuItem(value: 'mesa', child: Text('Mesa')),
                DropdownMenuItem(value: 'lounge', child: Text('Lounge')),
              ],
              onChanged: (v) => setState(() => _cat = v!),
            ),
          ),
        ]),
        const SizedBox(height: 14),
        Text('Ancho: ${_w.round()} %'),
        Slider(
            value: _w, min: 8, max: 30, divisions: 22,
            onChanged: (v) => setState(() => _w = v)),
        Text('Alto: ${_h.round()} %'),
        Slider(
            value: _h, min: 8, max: 45, divisions: 37,
            onChanged: (v) => setState(() => _h = v)),
        Row(children: [
          Expanded(
            child: DropdownButtonFormField<String?>(
              initialValue: teams.containsKey(_team) ? _team : null,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Team asignado'),
              items: [
                const DropdownMenuItem<String?>(value: null, child: Text('— libre —')),
                for (final t in teams.entries)
                  DropdownMenuItem<String?>(
                      value: t.key, child: Text(t.value, overflow: TextOverflow.ellipsis)),
              ],
              onChanged: (v) => setState(() => _team = v),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: DropdownButtonFormField<String>(
              initialValue: _planta,
              decoration: const InputDecoration(labelText: 'Piso'),
              items: [
                for (final p in pisos)
                  DropdownMenuItem(value: p, child: Text(etiquetaPiso[p] ?? p)),
              ],
              onChanged: (v) => setState(() => _planta = v!),
            ),
          ),
        ]),
        const SizedBox(height: 18),
        FilledButton(
          onPressed: () => hacer(
              () => repo.editarForma(
                    m.id,
                    etiqueta: _etiqueta.text.trim().isEmpty ? m.etiqueta : _etiqueta.text.trim(),
                    categoria: _cat,
                    w: _w.round(),
                    h: _h.round(),
                    teamId: _team,
                    planta: _planta,
                  ),
              'Mesa actualizada'),
          child: const Text('Guardar'),
        ),
        const SizedBox(height: 9),
        OutlinedButton(
          style: OutlinedButton.styleFrom(foregroundColor: VenueColors.mal),
          onPressed: () async {
            final si = await showDialog<bool>(
              context: context,
              builder: (c) => AlertDialog(
                title: Text('Eliminar ${m.etiqueta}'),
                content: Text(m.libre
                    ? 'Libre, sin venta asociada.'
                    : 'Esta mesa tiene una venta asociada (${m.cliente ?? ''}, ${m.estado}). Al eliminarla se pierde su registro en el plano y en los reportes.'),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(c, false),
                      child: const Text('Cancelar')),
                  TextButton(
                      onPressed: () => Navigator.pop(c, true),
                      style: TextButton.styleFrom(foregroundColor: VenueColors.mal),
                      child: const Text('Eliminar mesa')),
                ],
              ),
            );
            if (si == true) await hacer(() => repo.borrar(m.id), '${m.etiqueta} eliminada');
          },
          child: const Text('Eliminar mesa'),
        ),
      ],
    );
  }
}

// ───────────────────────── combos (admin) ─────────────────────────
Future<void> hojaCombos(BuildContext context) => _hoja(context, const _Combos());

class _Combos extends ConsumerWidget {
  const _Combos();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final combos = ref.watch(combosProvider).value ?? const <Combo>[];
    return ListView(
      shrinkWrap: true,
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
      children: [
        const Text('Combos',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
        for (final c in combos)
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(c.nombre,
                style: TextStyle(
                    fontWeight: FontWeight.w700,
                    color: c.activo ? null : VenueColors.textoSuave)),
            subtitle: Text([
              '${c.precio} Bs',
              if (c.incluyeManillas > 0) '${c.incluyeManillas} manillas',
              'comisión ${c.comisionRrpp}+${c.comisionJefe}',
              if (c.categorias.isNotEmpty) 'solo ${c.categorias.join(', ')}',
              if (!c.activo) 'inactivo',
            ].join(' · ')),
            trailing: const Icon(Icons.edit_outlined),
            onTap: () => _hoja(context, _ComboForm(combo: c)),
          ),
        const SizedBox(height: 10),
        FilledButton.icon(
          onPressed: () => _hoja(context, const _ComboForm()),
          icon: const Icon(Icons.add_rounded),
          label: const Text('Nuevo combo'),
        ),
      ],
    );
  }
}

class _ComboForm extends ConsumerStatefulWidget {
  const _ComboForm({this.combo});
  final Combo? combo;

  @override
  ConsumerState<_ComboForm> createState() => _ComboFormState();
}

class _ComboFormState extends ConsumerState<_ComboForm> {
  late final c = widget.combo;
  late final _nombre = TextEditingController(text: c?.nombre ?? '');
  late final _precio = TextEditingController(text: '${c?.precio ?? ''}');
  late final _productos = TextEditingController(text: c?.productos.join(', ') ?? '');
  late final _comR = TextEditingController(text: '${c?.comisionRrpp ?? 0}');
  late final _comJ = TextEditingController(text: '${c?.comisionJefe ?? 0}');
  late final _man = TextEditingController(text: '${c?.incluyeManillas ?? 0}');
  late bool _activo = c?.activo ?? true;
  late final _cats = {...?c?.categorias};

  @override
  void dispose() {
    for (final x in [_nombre, _precio, _productos, _comR, _comJ, _man]) {
      x.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final club = ref.watch(clubActivoIdProvider)!;
    final repo = ref.read(mesasRepositoryProvider);
    Future<void> hacer(Future<void> Function() f, String ok) async {
      try {
        await f();
        ref.invalidate(combosProvider);
        if (!context.mounted) return;
        Navigator.pop(context);
        avisar(context, ok);
      } catch (e) {
        if (context.mounted) avisar(context, mensajeDeError(e), tipo: TipoAviso.aviso);
      }
    }

    Widget num(String l, TextEditingController t) => Expanded(
          child: TextField(
              controller: t,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(labelText: l)),
        );

    return ListView(
      shrinkWrap: true,
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
      children: [
        Text(c == null ? 'Nuevo combo' : 'Editar combo',
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
        const SizedBox(height: 14),
        TextField(controller: _nombre, decoration: const InputDecoration(labelText: 'Nombre')),
        const SizedBox(height: 12),
        TextField(
            controller: _productos,
            decoration: const InputDecoration(
                labelText: 'Productos', hintText: 'Vodka 750, 6 energizantes')),
        const SizedBox(height: 12),
        Row(children: [num('Precio (Bs)', _precio), const SizedBox(width: 10), num('Manillas incluidas', _man)]),
        const SizedBox(height: 12),
        Row(children: [num('Comisión RRPP', _comR), const SizedBox(width: 10), num('Comisión jefe', _comJ)]),
        const SizedBox(height: 12),
        const Text('Se vende en (sin marcar = en todas)'),
        Wrap(spacing: 8, children: [
          for (final k in const ['mesa', 'lounge'])
            FilterChip(
              label: Text(k == 'mesa' ? 'Mesas' : 'Lounges'),
              selected: _cats.contains(k),
              onSelected: (v) => setState(() => v ? _cats.add(k) : _cats.remove(k)),
            ),
        ]),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Activo'),
          value: _activo,
          onChanged: (v) => setState(() => _activo = v),
        ),
        FilledButton(
          onPressed: () {
            if (_nombre.text.trim().isEmpty) {
              avisar(context, 'Poné un nombre', tipo: TipoAviso.aviso);
              return;
            }
            final nuevo = Combo(
              id: c?.id ?? '',
              nombre: _nombre.text.trim(),
              precio: int.tryParse(_precio.text) ?? 0,
              productos: _productos.text.split(',').map((s) => s.trim()).where((s) => s.isNotEmpty).toList(),
              comisionRrpp: int.tryParse(_comR.text) ?? 0,
              comisionJefe: int.tryParse(_comJ.text) ?? 0,
              incluyeManillas: int.tryParse(_man.text) ?? 0,
              activo: _activo,
              categorias: _cats.toList(),
              descripcion: c?.descripcion,
            );
            hacer(() => repo.guardarCombo(club, nuevo, nuevo: c == null), 'Combo guardado');
          },
          child: const Text('Guardar'),
        ),
        if (c != null) ...[
          const SizedBox(height: 9),
          OutlinedButton(
            style: OutlinedButton.styleFrom(foregroundColor: VenueColors.mal),
            onPressed: () => hacer(() => repo.borrarCombo(c!.id), 'Combo eliminado'),
            child: const Text('Eliminar combo'),
          ),
        ],
      ],
    );
  }
}

// ───────────────────────── confirmar pagos (admin) ─────────────────────────
Future<void> hojaConfirmarPagos(BuildContext context) =>
    _hoja(context, const _ConfirmarPagos());

class _ConfirmarPagos extends ConsumerWidget {
  const _ConfirmarPagos();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pend = (ref.watch(mesasProvider).value ?? const <Mesa>[])
        .where((m) => m.porVerificar)
        .toList();
    final equipo = ref.watch(equipoProvider).value ?? const <String, Miembro>{};
    final repo = ref.read(mesasRepositoryProvider);
    Future<void> hacer(Mesa m, bool ok) async {
      try {
        await repo.verificar(m.id, ok);
        ref.invalidate(mesasProvider);
        if (context.mounted) {
          avisar(context,
              ok ? '${m.etiqueta}: pago confirmado' : '${m.etiqueta}: rechazado, volvió a reservada',
              tipo: ok ? TipoAviso.ok : TipoAviso.aviso);
        }
      } catch (e) {
        if (context.mounted) avisar(context, mensajeDeError(e), tipo: TipoAviso.aviso);
      }
    }

    return ListView(
      shrinkWrap: true,
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
      children: [
        Text('Confirmar pagos (${pend.length})',
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
        const SizedBox(height: 4),
        const Text('Mesas cobradas que esperan que confirmes que la plata entró.',
            style: TextStyle(color: VenueColors.textoSuave)),
        if (pend.isEmpty)
          const Padding(
              padding: EdgeInsets.all(24),
              child: Text('No hay pagos por confirmar.', textAlign: TextAlign.center)),
        for (final m in pend) ...[
          const Divider(height: 24),
          Text('${m.etiqueta} · ${m.cliente ?? ''}',
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
          Text(
              '${m.precio} Bs · ${m.metodoPago ?? 'sin método'} · la vendió ${equipo[m.vendidoPor]?.nombre ?? '?'}',
              style: const TextStyle(color: VenueColors.textoSuave)),
          if (m.comprobanteUrl != null)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: ImagenComprobante(referencia: m.comprobanteUrl!, ancho: 200),
            )
          else
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 6),
              child: Text('Sin comprobante adjunto',
                  style: TextStyle(color: VenueColors.aviso)),
            ),
          Row(children: [
            Expanded(
              child: OutlinedButton(
                style: OutlinedButton.styleFrom(
                    foregroundColor: VenueColors.mal, minimumSize: const Size(0, 46)),
                onPressed: () => hacer(m, false),
                child: const Text('Rechazar'),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: FilledButton(
                style: FilledButton.styleFrom(minimumSize: const Size(0, 46)),
                onPressed: () => hacer(m, true),
                child: const Text('Entró'),
              ),
            ),
          ]),
        ],
      ],
    );
  }
}
