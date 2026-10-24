import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/media/imagenes.dart';
import '../../../core/networking/supabase.dart';
import '../../../core/sync/cola_offline.dart';
import '../../../core/theme/venue_theme.dart';
import '../../../core/widgets/avisos.dart';
import '../../../core/widgets/estado_vista.dart';
import '../../authentication/data/sesion.dart';
import '../../clubs/data/clubs.dart';
import '../../events/data/eventos.dart';
import '../../teams/data/equipo.dart';
import '../../vip_tables/ui/mesa_hojas.dart';
import '../data/pagos.dart';

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

/// Imagen de un QR de cobro: los de team son data-URI, los del boliche URL.
class ImagenQr extends StatelessWidget {
  const ImagenQr(this.url, {super.key, this.lado = 280});
  final String url;
  final double lado;

  @override
  Widget build(BuildContext context) {
    final b = bytesDeDataUri(url);
    return Container(
      padding: const EdgeInsets.all(10),
      decoration:
          BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14)),
      child: b != null
          ? Image.memory(b, width: lado, fit: BoxFit.contain)
          : Image.network(url, width: lado, fit: BoxFit.contain,
              errorBuilder: (_, _, _) => SizedBox(
                  width: lado, height: 80,
                  child: const Center(child: Text('No se pudo cargar el QR',
                      style: TextStyle(color: Colors.black54))))),
    );
  }
}

/// Pagos según quién mira:
/// - relacionador: su cuenta (manillas que ingresaron, comisión, a pagar) y
///   subir el comprobante;
/// - jefe: lo mismo para él, y la lista de su team con capturas y un check
///   de "pagó" por persona o para el team entero;
/// - admin: todos los teams, con los mismos checks, y la verificación de los
///   comprobantes contra el extracto.
class PagosScreen extends ConsumerWidget {
  const PagosScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ev = ref.watch(eventoActivoProvider);
    final rol = ref.watch(rolProvider).value;
    final club = ref.watch(clubActivoIdProvider);
    final yo = ref.watch(usuarioIdProvider);
    if (ev == null || rol == null || club == null || yo == null) {
      return const MensajeVista(
          icono: Icons.event_busy_rounded, titulo: 'No hay evento activo');
    }
    final pagos = ref.watch(pagosProvider);
    final rends = ref.watch(rendicionesProvider);
    final equipo = ref.watch(equipoProvider).value ?? const <String, Miembro>{};
    final miTeam = equipo[yo]?.teamId;
    final esAdmin = rol == Rol.admin;
    final rinde = rol == Rol.rrpp || rol == Rol.jefe;
    final controla = rol == Rol.jefe || esAdmin;
    final aQuien = rol == Rol.rrpp ? 'tu jefe' : 'el boliche';
    final repo = ref.read(pagosRepositoryProvider);

    void recargar() {
      ref.invalidate(pagosProvider);
      ref.invalidate(rendicionesProvider);
      ref.invalidate(miRendicionProvider);
    }

    Future<void> marcar(List<String> ids, bool pagado, String ok) async {
      try {
        await repo.marcar(ev.id, ids, pagado);
        ref.invalidate(rendicionesProvider);
        if (context.mounted) avisar(context, ok);
      } catch (e) {
        if (context.mounted) avisar(context, mensajeDeError(e), tipo: TipoAviso.aviso);
      }
    }

    return RefreshIndicator(
      onRefresh: () async {
        recargar();
        await ref.read(rendicionesProvider.future);
      },
      child: VistaAsync(
        valor: rends,
        reintentar: recargar,
        datos: (todas) {
          final mia = todas.where((r) => r.rrppId == yo).firstOrNull;
          // el jefe no se marca a sí mismo: a él lo marca el admin
          final otros = esAdmin
              ? todas
              : todas.where((r) => r.rrppId != yo && r.teamId == miTeam).toList();
          final porTeam = <String, List<Rendicion>>{};
          for (final r in otros) {
            porTeam.putIfAbsent(r.teamId ?? '', () => []).add(r);
          }
          final lista = pagos.value ?? const <Pago>[];

          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
            children: [
              if (rinde) ...[
                _MiCuenta(
                  r: mia,
                  aQuien: aQuien,
                  alSubir: () async {
                    final debe = (mia?.aPagar ?? 0) - (mia?.rendido ?? 0);
                    final ok = await _hoja<bool>(
                        context,
                        _Rendir(
                          sugerido: debe > 0 ? debe : (mia?.aPagar ?? 0),
                          esRendicion: true,
                          aQuien: aQuien,
                          teamId: rol == Rol.rrpp ? miTeam : null,
                        ));
                    if (ok == true) recargar();
                  },
                ),
                const SizedBox(height: 16),
              ],
              if (controla) ...[
                _ResumenTeams(lista: otros, titulo: esAdmin ? 'Todos los teams' : 'Mi team'),
                const SizedBox(height: 8),
                if (otros.isEmpty)
                  Padding(
                    padding: EdgeInsets.all(20),
                    child: Text('Nadie de tu team vendió entradas en este evento.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: VenueColors.textoSuave)),
                  ),
                for (final t in porTeam.entries)
                  _TarjetaTeam(
                    nombre: t.value.first.team,
                    filas: t.value,
                    // el jefe ve un solo team: el botón de "todo el team" es el suyo
                    alMarcarTodos: (pagado) => marcar(
                        [for (final r in t.value) r.rrppId],
                        pagado,
                        pagado
                            ? '${t.value.first.team}: todos marcados como pagados'
                            : '${t.value.first.team}: checks quitados'),
                    alMarcar: (r, pagado) => marcar([r.rrppId], pagado,
                        pagado ? '${r.nombre} marcado como pagado' : 'Check de ${r.nombre} quitado'),
                  ),
              ],
              const SizedBox(height: 10),
              Wrap(spacing: 8, runSpacing: 6, children: [
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(minimumSize: const Size(0, 42)),
                  onPressed: () => _hoja(context,
                      const Padding(padding: EdgeInsets.fromLTRB(20, 0, 20, 26), child: QrDeCobro())),
                  icon: const Icon(Icons.qr_code_rounded, size: 18),
                  label: const Text('QR de cobro'),
                ),
                if (esAdmin)
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(minimumSize: const Size(0, 42)),
                    onPressed: () => _hoja(context, const _QrsCobro()),
                    icon: const Icon(Icons.tune_rounded, size: 18),
                    label: const Text('QRs de cobro del boliche'),
                  ),
                if (rol == Rol.jefe && miTeam != null)
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(minimumSize: const Size(0, 42)),
                    onPressed: () async {
                      final b = await elegirImagen(lado: 900);
                      if (b == null) return;
                      try {
                        await repo.guardarQrDeMiTeam(b);
                        if (context.mounted) {
                          avisar(context, 'Tu QR quedó cargado — lo ven tus relacionadores');
                        }
                      } catch (e) {
                        if (context.mounted) {
                          avisar(context, mensajeDeError(e), tipo: TipoAviso.aviso);
                        }
                      }
                    },
                    icon: const Icon(Icons.upload_rounded, size: 18),
                    label: const Text('Mi QR de cobro'),
                  ),
              ]),
              const SizedBox(height: 16),
              Text(esAdmin ? 'Comprobantes · verificación' : 'Comprobantes subidos',
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
              if (lista.isEmpty)
                Padding(
                  padding: EdgeInsets.all(20),
                  child: Text('Todavía no se subió ningún comprobante.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: VenueColors.textoSuave)),
                ),
              for (final p in lista)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  onTap: () async {
                    await _hoja(context, _Comprobante(pago: p));
                    recargar();
                  },
                  leading: _Estado(p.estado),
                  title: Text('${p.monto} Bs — ${p.rrppNombre}',
                      style: const TextStyle(fontWeight: FontWeight.w700)),
                  subtitle: Text([
                    horaCorta(p.creado),
                    if (p.concepto.isNotEmpty) p.concepto,
                    if (p.comprobante != null) 'con captura',
                  ].join(' · ')),
                  trailing: esAdmin && p.siguiente != null
                      ? TextButton(
                          onPressed: () async {
                            try {
                              await repo.avanzar(p.id, p.siguiente!);
                              recargar();
                              if (context.mounted) {
                                avisar(context,
                                    'Pago marcado como ${etiquetaPago[p.siguiente]!.toLowerCase()}');
                              }
                            } catch (e) {
                              if (context.mounted) {
                                avisar(context, mensajeDeError(e), tipo: TipoAviso.aviso);
                              }
                            }
                          },
                          child: Text(p.siguiente == 'pagado' ? '→ Pagado' : '→ Verificar'),
                        )
                      : null,
                ),
            ],
          );
        },
      ),
    );
  }
}

/// La cuenta propia: cuántas manillas ingresaron, comisión, lo que hay que
/// pagar y si ya le pusieron el check.
class _MiCuenta extends StatelessWidget {
  const _MiCuenta({required this.r, required this.aQuien, required this.alSubir});
  final Rendicion? r;
  final String aQuien;
  final VoidCallback alSubir;

  @override
  Widget build(BuildContext context) {
    final x = r;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            const Expanded(
                child: Text('Tu cuenta', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800))),
            if (x != null) _ChipPagado(x),
          ]),
          const SizedBox(height: 10),
          if (x == null)
            Text('No vendiste entradas en este evento.',
                style: TextStyle(color: VenueColors.textoSuave))
          else ...[
            _Linea('Ingresaron', '${x.ingresaron} de ${x.vendidas} vendidas'),
            _Linea('Cobrado (las que ingresaron)', '${x.cobrado} Bs'),
            _Linea('Tu comisión (${x.comisionUnit} × ${x.ingresaron})', '− ${x.comision} Bs'),
            if (x.rendido > 0) _Linea('Comprobantes que subiste', '${x.rendido} Bs'),
            const Divider(height: 18),
            Row(children: [
              Expanded(
                  child: Text('A pagar a $aQuien',
                      style: const TextStyle(fontWeight: FontWeight.w700))),
              Text('${x.aPagar} Bs',
                  style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                      color: x.pagado ? VenueColors.ok : VenueColors.aviso)),
            ]),
          ],
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: alSubir,
            icon: const Icon(Icons.upload_file_rounded),
            label: const Text('Subir comprobante de pago'),
          ),
          if (x != null && x.comprobantes.isNotEmpty) ...[
            const SizedBox(height: 10),
            _Capturas(x.comprobantes),
          ],
        ]),
      ),
    );
  }
}

class _Linea extends StatelessWidget {
  const _Linea(this.t, this.v);
  final String t;
  final String v;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(children: [
          Expanded(child: Text(t, style: TextStyle(color: VenueColors.textoSuave))),
          Text(v, style: const TextStyle(fontWeight: FontWeight.w700)),
        ]),
      );
}

class _ChipPagado extends StatelessWidget {
  const _ChipPagado(this.r);
  final Rendicion r;

  @override
  Widget build(BuildContext context) {
    final c = r.pagado ? VenueColors.ok : VenueColors.aviso;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
          color: c.withValues(alpha: .14), borderRadius: BorderRadius.circular(99)),
      child: Text(r.pagado ? 'Pagado ✓' : 'Pendiente',
          style: TextStyle(color: c, fontWeight: FontWeight.w800, fontSize: 12.5)),
    );
  }
}

/// Totales de lo que se controla: cuánto hay que cobrar y cuánto ya tiene check.
class _ResumenTeams extends StatelessWidget {
  const _ResumenTeams({required this.lista, required this.titulo});
  final List<Rendicion> lista;
  final String titulo;

  @override
  Widget build(BuildContext context) {
    num suma(Iterable<Rendicion> l) => l.fold<num>(0, (a, r) => a + r.aPagar);
    final pag = lista.where((r) => r.pagado);
    final pen = lista.where((r) => !r.pagado);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Text(titulo, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
      const SizedBox(height: 8),
      Row(children: [
        Expanded(child: _Caja('Pagaron (${pag.length})', '${suma(pag)} Bs', VenueColors.ok)),
        const SizedBox(width: 10),
        Expanded(child: _Caja('Falta pagar (${pen.length})', '${suma(pen)} Bs', VenueColors.aviso)),
      ]),
    ]);
  }
}

class _TarjetaTeam extends StatelessWidget {
  const _TarjetaTeam({
    required this.nombre,
    required this.filas,
    required this.alMarcarTodos,
    required this.alMarcar,
  });
  final String nombre;
  final List<Rendicion> filas;
  final ValueChanged<bool> alMarcarTodos;
  final void Function(Rendicion r, bool pagado) alMarcar;

  @override
  Widget build(BuildContext context) {
    final todos = filas.every((r) => r.pagado);
    final total = filas.fold<num>(0, (a, r) => a + r.aPagar);
    return Card(
      margin: const EdgeInsets.only(top: 10),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 10, 8, 8),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(nombre, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
                Text(
                    '${filas.where((r) => r.pagado).length}/${filas.length} pagaron · $total Bs en total',
                    style: TextStyle(color: VenueColors.textoSuave, fontSize: 12.5)),
              ]),
            ),
            TextButton.icon(
              onPressed: () => alMarcarTodos(!todos),
              icon: Icon(todos ? Icons.remove_done_rounded : Icons.done_all_rounded, size: 18),
              label: Text(todos ? 'Quitar todos' : 'Marcar todos'),
            ),
          ]),
          const Divider(height: 14),
          for (final r in filas)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Checkbox(value: r.pagado, onChanged: (v) => alMarcar(r, v ?? false)),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    const SizedBox(height: 10),
                    Text(r.nombre, style: const TextStyle(fontWeight: FontWeight.w700)),
                    Text(
                      '${r.ingresaron} de ${r.vendidas} ingresaron · paga ${r.aPagar} Bs'
                      '${r.rendido > 0 ? ' · subió ${r.rendido} Bs' : ''}',
                      style: TextStyle(color: VenueColors.textoSuave, fontSize: 12.5),
                    ),
                    if (r.pagado && r.marcadoPor != null)
                      Text('check de ${r.marcadoPor}',
                          style: TextStyle(color: VenueColors.ok, fontSize: 12)),
                    if (r.comprobantes.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      _Capturas(r.comprobantes),
                    ] else
                      Text('sin captura',
                          style: TextStyle(color: VenueColors.aviso, fontSize: 12)),
                  ]),
                ),
              ]),
            ),
        ]),
      ),
    );
  }
}

/// Miniaturas de los comprobantes; al tocar una se ve grande.
class _Capturas extends StatelessWidget {
  const _Capturas(this.refs);
  final List<String> refs;

  @override
  Widget build(BuildContext context) => SizedBox(
        height: 74,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          itemCount: refs.length,
          separatorBuilder: (_, _) => const SizedBox(width: 8),
          itemBuilder: (_, i) => GestureDetector(
            onTap: () => _hoja(
                context,
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                  child: Center(child: ImagenComprobante(referencia: refs[i], ancho: 320)),
                )),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: SizedBox(
                width: 60,
                height: 74,
                child: FittedBox(
                    fit: BoxFit.cover,
                    clipBehavior: Clip.hardEdge,
                    child: ImagenComprobante(referencia: refs[i], ancho: 120)),
              ),
            ),
          ),
        ),
      );
}

class _Caja extends StatelessWidget {
  const _Caja(this.titulo, this.valor, this.color);
  final String titulo;
  final String valor;
  final Color? color;

  @override
  Widget build(BuildContext context) => Card(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(titulo,
                style: TextStyle(color: VenueColors.textoSuave, fontSize: 12.5)),
            const SizedBox(height: 3),
            Text(valor,
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: color)),
          ]),
        ),
      );
}

class _Estado extends StatelessWidget {
  const _Estado(this.estado);
  final String estado;

  @override
  Widget build(BuildContext context) {
    final c = switch (estado) {
      'verificado' => VenueColors.ok,
      'pagado' => Theme.of(context).colorScheme.primary,
      _ => VenueColors.aviso,
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
          color: c.withValues(alpha: .16), borderRadius: BorderRadius.circular(8)),
      child: Text(etiquetaPago[estado] ?? estado,
          style: TextStyle(color: c, fontSize: 11.5, fontWeight: FontWeight.w800)),
    );
  }
}

/// Registrar una rendición: QR a quien se transfiere, monto, concepto y la
/// foto de la transferencia (obligatoria salvo para el admin).
class _Rendir extends ConsumerStatefulWidget {
  const _Rendir({
    required this.sugerido, required this.esRendicion, required this.aQuien,
    required this.teamId,
  });
  final num sugerido;
  final bool esRendicion;
  final String aQuien;

  /// Team cuyo QR se muestra (relacionador → su jefe). null = QR del boliche.
  final String? teamId;

  @override
  ConsumerState<_Rendir> createState() => _RendirState();
}

class _RendirState extends ConsumerState<_Rendir> {
  late final _monto = TextEditingController(text: '${widget.sugerido}');
  final _op = TextEditingController();
  late final _concepto = TextEditingController(
      text: '${widget.esRendicion ? 'Rendición' : 'Manilla'} ${ref.read(eventoActivoProvider)?.nombre ?? ''}');

  /// Una clave por hoja abierta: si el envío se reintenta, es el mismo pago.
  final _clave = nuevoId();
  String? _comprobante;
  Uint8List? _vista;
  bool _ocupado = false;
  late final Future<String?> _qr = () {
    final repo = ref.read(pagosRepositoryProvider);
    final club = ref.read(clubActivoIdProvider)!;
    return widget.teamId != null ? repo.qrDelTeam(widget.teamId!) : repo.qrDelClub(club);
  }();

  @override
  void dispose() {
    for (final c in [_monto, _op, _concepto]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _foto(bool camara) async {
    final b = await elegirImagen(camara: camara);
    if (b == null) return;
    setState(() => _ocupado = true);
    try {
      final r = await ref.read(archivosProvider).subirComprobante(b, 'pago');
      setState(() {
        _comprobante = r;
        _vista = b;
      });
    } catch (e) {
      if (mounted) avisar(context, mensajeDeError(e), tipo: TipoAviso.aviso);
    }
    if (mounted) setState(() => _ocupado = false);
  }

  Future<void> _registrar() async {
    final monto = num.tryParse(_monto.text.replaceAll(',', '.'));
    if (monto == null || monto <= 0) {
      avisar(context, 'Monto inválido', tipo: TipoAviso.aviso);
      return;
    }
    setState(() => _ocupado = true);
    try {
      await ref.read(pagosRepositoryProvider).crear(
            eventoId: ref.read(eventoActivoProvider)!.id,
            monto: monto,
            concepto: _concepto.text,
            clave: _clave,
            nroOperacion: _op.text,
            comprobante: _comprobante,
          );
      if (!mounted) return;
      Navigator.pop(context, true);
      avisar(context, 'Comprobante subido — ${widget.aQuien == 'tu jefe' ? 'tu jefe' : 'el admin'} te marca cuando lo vea');
    } catch (e) {
      if (mounted) {
        avisar(
            context,
            esFallaDeRed(e)
                ? 'Sin señal. Tocá de nuevo cuando vuelva: no se va a duplicar.'
                : mensajeDeError(e),
            tipo: TipoAviso.aviso);
        setState(() => _ocupado = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final esAdmin = ref.watch(rolProvider).value == Rol.admin;
    return ListView(
      shrinkWrap: true,
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
      children: [
        Text('${widget.esRendicion ? 'Rendir' : 'Pagar'} a ${widget.aQuien}',
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
        const SizedBox(height: 12),
        FutureBuilder(
          future: _qr,
          builder: (context, s) {
            if (s.connectionState != ConnectionState.done) {
              return const SizedBox(height: 80, child: Center(child: CircularProgressIndicator()));
            }
            final url = s.data;
            if (url == null || url.isEmpty) {
              return Padding(
                padding: EdgeInsets.only(bottom: 12),
                child: Text(
                    'Todavía no hay QR de cobro cargado — pedíselo antes de transferir.',
                    style: TextStyle(color: VenueColors.aviso)),
              );
            }
            return Padding(
                padding: const EdgeInsets.only(bottom: 14),
                child: Center(child: ImagenQr(url)));
          },
        ),
        Row(children: [
          Expanded(
            child: TextField(
                controller: _monto,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(labelText: 'Monto Bs')),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: TextField(
                controller: _op,
                decoration: const InputDecoration(labelText: 'N° de operación (opcional)')),
          ),
        ]),
        const SizedBox(height: 12),
        TextField(controller: _concepto, decoration: const InputDecoration(labelText: 'Concepto')),
        const SizedBox(height: 12),
        if (_vista != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Center(
                child: ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: Image.memory(_vista!, width: 200))),
          ),
        Row(children: [
          Expanded(
            child: OutlinedButton.icon(
                onPressed: _ocupado ? null : () => _foto(true),
                icon: const Icon(Icons.photo_camera_outlined),
                label: const Text('Foto')),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: OutlinedButton.icon(
                onPressed: _ocupado ? null : () => _foto(false),
                icon: const Icon(Icons.image_outlined),
                label: Text(_comprobante == null ? 'Galería' : 'Cambiar')),
          ),
        ]),
        const SizedBox(height: 12),
        FilledButton(
          onPressed: _ocupado || (!esAdmin && _comprobante == null) ? null : _registrar,
          child: const Text('Registrar pago hecho'),
        ),
        const SizedBox(height: 8),
        Text(
          esAdmin
              ? 'El pago nace pendiente hasta que lo verifiques contra el extracto.'
              : 'Sin la foto de la transferencia el pago no se puede registrar. Nace pendiente hasta que el admin lo verifique contra el extracto.',
          style: TextStyle(color: VenueColors.textoSuave, fontSize: 12.5, height: 1.35),
        ),
      ],
    );
  }
}

/// Detalle de un pago con su captura. Quien lo registró puede adjuntar o
/// cambiar la captura mientras no esté verificado.
class _Comprobante extends ConsumerWidget {
  const _Comprobante({required this.pago});
  final Pago pago;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = pago;
    final yo = ref.watch(usuarioIdProvider);
    final esAdmin = ref.watch(rolProvider).value == Rol.admin;
    final puedeAdjuntar = !p.verificado && (esAdmin || p.rrppId == yo);
    return ListView(
      shrinkWrap: true,
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
      children: [
        Row(children: [
          Expanded(
            child: Text('${p.monto} Bs',
                style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w800)),
          ),
          _Estado(p.estado),
        ]),
        Text(p.rrppNombre, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
        Text(
          [
            '${p.creado.day}/${p.creado.month} ${horaCorta(p.creado)}',
            if (p.concepto.isNotEmpty) p.concepto,
            if (p.nroOperacion != null) 'Op. ${p.nroOperacion}',
          ].join(' · '),
          style: TextStyle(color: VenueColors.textoSuave),
        ),
        const SizedBox(height: 14),
        if (p.comprobante != null)
          Center(child: ImagenComprobante(referencia: p.comprobante!, ancho: 300))
        else
          Text('Sin captura adjunta.', style: TextStyle(color: VenueColors.aviso)),
        if (puedeAdjuntar) ...[
          const SizedBox(height: 14),
          OutlinedButton.icon(
            onPressed: () async {
              final b = await elegirImagen();
              if (b == null) return;
              try {
                final r = await ref.read(archivosProvider).subirComprobante(b, 'pago');
                await ref.read(pagosRepositoryProvider).adjuntar(p.id, r);
                if (context.mounted) {
                  Navigator.pop(context);
                  avisar(context, 'Captura adjuntada');
                }
              } catch (e) {
                if (context.mounted) {
                  avisar(context, mensajeDeError(e), tipo: TipoAviso.aviso);
                }
              }
            },
            icon: const Icon(Icons.attach_file_rounded),
            label: Text(p.comprobante == null
                ? 'Adjuntar captura de la transferencia'
                : 'Cambiar captura'),
          ),
        ],
      ],
    );
  }
}

/// Admin: los QR de cobro del boliche, uno por cada cuenta que cobra.
class _QrsCobro extends ConsumerStatefulWidget {
  const _QrsCobro();

  @override
  ConsumerState<_QrsCobro> createState() => _QrsCobroState();
}

class _QrsCobroState extends ConsumerState<_QrsCobro> {
  late Future<List<QrCobro>> _lista = _cargar();
  final _nombre = TextEditingController();

  Future<List<QrCobro>> _cargar() =>
      ref.read(pagosRepositoryProvider).qrs(ref.read(clubActivoIdProvider)!);

  @override
  void dispose() {
    _nombre.dispose();
    super.dispose();
  }

  Future<void> _hacer(Future<void> Function() f, String ok) async {
    try {
      await f();
      if (!mounted) return;
      setState(() => _lista = _cargar());
      avisar(context, ok);
    } catch (e) {
      if (mounted) avisar(context, mensajeDeError(e), tipo: TipoAviso.aviso);
    }
  }

  @override
  Widget build(BuildContext context) {
    final club = ref.watch(clubActivoIdProvider)!;
    final repo = ref.read(pagosRepositoryProvider);
    return FutureBuilder(
      future: _lista,
      builder: (context, s) {
        final lista = s.data ?? const <QrCobro>[];
        return ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
          children: [
            const Text('QRs de cobro',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
            Text('Cargá un QR por cada cuenta que cobra. Se muestra el primero activo.',
                style: TextStyle(color: VenueColors.textoSuave)),
            if (s.connectionState != ConnectionState.done)
              const Padding(
                  padding: EdgeInsets.all(20),
                  child: Center(child: CircularProgressIndicator())),
            for (final q in lista)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Container(
                        color: Colors.white,
                        child: Image.network(q.url, width: 44, height: 44, fit: BoxFit.cover,
                            errorBuilder: (_, _, _) => const SizedBox(width: 44, height: 44)))),
                title: Text(q.nombre),
                subtitle: Text(q.activo ? 'Activo' : 'En pausa'),
                trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                  TextButton(
                      onPressed: () => _hacer(() => repo.activarQr(q.id, !q.activo),
                          q.activo ? 'QR en pausa' : 'QR activado'),
                      child: Text(q.activo ? 'Pausar' : 'Activar')),
                  IconButton(
                      tooltip: 'Eliminar ${q.nombre}',
                      onPressed: () => _hacer(() => repo.borrarQr(q.id), 'QR eliminado'),
                      icon: Icon(Icons.close_rounded, color: VenueColors.mal)),
                ]),
              ),
            const Divider(height: 26),
            TextField(
                controller: _nombre,
                decoration: const InputDecoration(
                    labelText: 'Nombre de la cuenta', hintText: 'Banco Unión · Aurora SRL')),
            const SizedBox(height: 10),
            FilledButton.icon(
              onPressed: () async {
                final nombre = _nombre.text.trim();
                if (nombre.isEmpty) {
                  avisar(context, 'Poné el nombre de la cuenta', tipo: TipoAviso.aviso);
                  return;
                }
                final b = await elegirImagen(lado: 900);
                if (b == null) return;
                await _hacer(() async {
                  final url = await ref.read(archivosProvider).subirDiseno(
                      b, 'qr-$club-${DateTime.now().millisecondsSinceEpoch}.jpg');
                  await repo.crearQr(club, nombre, url, lista.length + 1);
                  _nombre.clear();
                }, 'QR cargado');
              },
              icon: const Icon(Icons.add_photo_alternate_outlined),
              label: const Text('Subir imagen del QR'),
            ),
          ],
        );
      },
    );
  }
}
