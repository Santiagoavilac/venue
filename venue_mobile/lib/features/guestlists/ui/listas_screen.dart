import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/networking/supabase.dart';
import '../../../core/sync/cola_offline.dart';
import '../../../core/theme/venue_theme.dart';
import '../../../core/widgets/avisos.dart';
import '../../../core/widgets/estado_vista.dart';
import '../../authentication/data/sesion.dart';
import '../../clubs/data/clubs.dart';
import '../../events/data/eventos.dart';
import '../../events/ui/gestion_screen.dart';
import '../../teams/data/equipo.dart';
import '../../tickets/data/entradas.dart';
import '../../tickets/ui/ticket_sheet.dart';
import '../data/listas.dart';

/// Reglas de quién puede qué sobre un invitado. Son las mismas de la web;
/// el servidor las vuelve a aplicar en cada RPC.
class PermisosLista {
  const PermisosLista({
    required this.rol,
    required this.yo,
    required this.miTeam,
    required this.puedeTickear,
    required this.teamDe,
  });
  final Rol rol;
  final String yo;
  final String? miTeam;
  final bool puedeTickear;
  final String? Function(String usuarioId) teamDe;

  bool get anota => rol.vende;
  bool esMio(Invitado i) => i.rrppId == yo;

  /// Mandar el QR: los propios, los del team si es jefe, todos si es admin.
  bool mandar(Invitado i) =>
      anota &&
      (rol == Rol.admin ||
          esMio(i) ||
          (rol == Rol.jefe && miTeam != null && teamDe(i.rrppId) == miTeam));

  bool generarQr(Invitado i) => anota && !i.ingreso && (rol == Rol.admin || esMio(i));
  bool quitar(Invitado i) => anota && (rol == Rol.admin || esMio(i));

  /// Marcar el ingreso a mano desde Listas es del admin con `puede_tickear`.
  bool get tickea => rol == Rol.admin && puedeTickear;
}

/// Anota uno o varios nombres en [l] (con "a nombre de" si la persona puede).
/// Devuelve true si anotó a alguien.
Future<bool> anotarEnLista(BuildContext context, WidgetRef ref, ListaTipo l) async {
  final permisos = ref.read(permisosEventoProvider).value;
  final vendedores = (permisos?.aNombreDe ?? false)
      ? (ref.read(vendedoresProvider).value ?? const <Miembro>[])
      : const <Miembro>[];
  final r = await showModalBottomSheet<({List<String> nombres, String? de})>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    backgroundColor: VenueColors.superficie,
    builder: (_) => _AnotarSheet(lista: l, vendedores: vendedores),
  );
  if (r == null || r.nombres.isEmpty) return false;
  try {
    final x = await ref.read(listasRepositoryProvider).anotar(l.id, r.nombres, aNombreDe: r.de);
    ref.invalidate(listasProvider);
    ref.invalidate(invitadosProvider);
    ref.invalidate(misCuposProvider);
    if (context.mounted) {
      avisar(
        context,
        x.duplicados.isEmpty
            ? '${x.insertados} anotado(s) en ${l.nombre}'
            : '${x.insertados} anotado(s). Ojo, ya estaban en el evento: ${x.duplicados.join(', ')}',
        tipo: x.duplicados.isEmpty ? TipoAviso.ok : TipoAviso.aviso,
      );
    }
    return true;
  } catch (e) {
    if (context.mounted) avisar(context, mensajeDeError(e), tipo: TipoAviso.aviso);
    return false;
  }
}

/// "Nuevo cliente" en dos pasos: elegir la lista y después los nombres.
Future<void> nuevoCliente(BuildContext context, WidgetRef ref) async {
  final ahora = DateTime.now();
  List<ListaTipo> ls;
  try {
    ls = (await ref.read(listasProvider.future)).where((l) => l.abierta(ahora)).toList();
  } catch (e) {
    if (context.mounted) avisar(context, mensajeDeError(e), tipo: TipoAviso.aviso);
    return;
  }
  if (!context.mounted) return;
  if (ls.isEmpty) {
    avisar(context, 'No hay ninguna lista abierta para anotar', tipo: TipoAviso.aviso);
    return;
  }
  final l = ls.length == 1
      ? ls.first
      : await showModalBottomSheet<ListaTipo>(
          context: context,
          showDragHandle: true,
          backgroundColor: VenueColors.superficie,
          builder: (c) => ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
            children: [
              const Text('Nuevo cliente · elegí la lista',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
              const SizedBox(height: 8),
              for (final l in ls)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(l.nombre, style: const TextStyle(fontWeight: FontWeight.w700)),
                  subtitle: Text([
                    (l.precio ?? 0) > 0 ? '${l.precio} Bs' : 'Free',
                    if (l.ingresoHasta != null) 'entran hasta ${l.ingresoHasta}',
                  ].join(' · ')),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () => Navigator.pop(c, l),
                ),
            ],
          ),
        );
  if (l == null || !context.mounted) return;
  await anotarEnLista(context, ref, l);
}

class ListasScreen extends ConsumerStatefulWidget {
  const ListasScreen({super.key});

  @override
  ConsumerState<ListasScreen> createState() => _ListasScreenState();
}

class _ListasScreenState extends ConsumerState<ListasScreen> {
  String _q = '';
  String? _team; // '' = sin team
  String? _vendedor;
  String? _abierta;
  bool _ingresaronArriba = false;
  final _marcados = <String>{};
  String? _armado;
  Timer? _desarmar;

  @override
  void dispose() {
    _desarmar?.cancel();
    super.dispose();
  }

  void _recargar() {
    ref.invalidate(listasProvider);
    ref.invalidate(invitadosProvider);
    ref.invalidate(misCuposProvider);
  }

  /// Segundo toque para acciones que no conviene hacer por error.
  bool _confirmado(String clave, String mensaje) {
    if (_armado == clave) {
      setState(() => _armado = null);
      return true;
    }
    setState(() => _armado = clave);
    _desarmar?.cancel();
    _desarmar = Timer(const Duration(seconds: 3), () {
      if (mounted) setState(() => _armado = null);
    });
    avisar(context, mensaje, tipo: TipoAviso.aviso);
    return false;
  }

  Future<void> _hacer(Future<void> Function() f) async {
    try {
      await f();
    } catch (e) {
      if (mounted) avisar(context, mensajeDeError(e), tipo: TipoAviso.aviso);
    }
  }

  TicketDatos _ticket(Invitado i, String codigo, Evento ev, String lista) {
    final club = ref.read(clubActivoProvider);
    return TicketDatos(
      payload: payloadLista(ev.id, codigo),
      codigo: codigo,
      cliente: i.nombre,
      boliche: club?.nombre ?? '',
      evento: ev.nombre,
      fecha: ev.fechaCorta,
      tipo: lista,
      color: club?.primario,
      arteUrl: ev.ticketUrl,
    );
  }

  Future<void> _verQr(Invitado i, Evento ev, String lista, PermisosLista p) =>
      _hacer(() async {
        var codigo = i.codigo;
        if (codigo == null) {
          if (!p.generarQr(i)) {
            avisar(context, 'Este invitado todavía no tiene QR', tipo: TipoAviso.aviso);
            return;
          }
          codigo = await ref.read(listasRepositoryProvider).generarQr(i.id);
          ref.invalidate(invitadosProvider);
        }
        if (mounted) await mostrarTicket(context, _ticket(i, codigo, ev, lista));
      });

  Future<void> _tickear(Invitado i) => _hacer(() async {
        final r = await ref
            .read(pendientesProvider.notifier)
            .ejecutar('checkin_registro', {'p_registro': i.id}, 'Ingreso de ${i.nombre}');
        ref.invalidate(invitadosProvider);
        if (!mounted) return;
        avisar(
          context,
          r.encolada
              ? 'Sin señal: el ingreso de ${i.nombre} se envía cuando vuelva'
              : (r.dato as Map?)?['resultado'] == 'ok'
                  ? 'Ingreso: ${i.nombre}'
                  : 'Ya había ingresado',
          tipo: r.encolada ? TipoAviso.aviso : TipoAviso.ok,
        );
      });

  Future<void> _enviarTanda(List<Invitado> todos, Evento ev,
          Map<String, String> nombreLista) =>
      _hacer(() async {
        final repo = ref.read(listasRepositoryProvider);
        final elegidos = todos.where((i) => _marcados.contains(i.id)).toList();
        final tickets = <TicketDatos>[];
        for (final i in elegidos) {
          final codigo = i.codigo ?? await repo.generarQr(i.id);
          tickets.add(_ticket(i, codigo, ev, nombreLista[i.listaId] ?? 'Lista'));
        }
        ref.invalidate(invitadosProvider);
        if (!mounted) return;
        await compartirTanda(context, tickets);
        if (mounted) setState(_marcados.clear);
      });

  Future<void> _anotar(ListaTipo l) async {
    if (await anotarEnLista(context, ref, l) && mounted) {
      setState(() => _abierta = l.id);
    }
  }

  @override
  Widget build(BuildContext context) {
    final ev = ref.watch(eventoActivoProvider);
    final rol = ref.watch(rolProvider).value;
    final perfil = ref.watch(perfilProvider).value;
    if (ev == null || rol == null || perfil == null) {
      return const MensajeVista(
          icono: Icons.event_busy_rounded, titulo: 'No hay evento activo');
    }
    final listas = ref.watch(listasProvider);
    final invitados = ref.watch(invitadosProvider);
    final cupos = ref.watch(misCuposProvider).value ?? const <String, int>{};
    final equipo = ref.watch(equipoProvider).value ?? const <String, Miembro>{};
    ref.watch(permisosEventoProvider);
    ref.watch(vendedoresProvider);

    final p = PermisosLista(
      rol: rol,
      yo: perfil.id,
      miTeam: equipo[perfil.id]?.teamId,
      puedeTickear: perfil.puedeTickear,
      teamDe: (u) => equipo[u]?.teamId,
    );

    return RefreshIndicator(
      onRefresh: () async {
        _recargar();
        await ref.read(invitadosProvider.future);
      },
      child: VistaAsync(
        valor: listas,
        reintentar: _recargar,
        datos: (ls) {
          if (ls.isEmpty) {
            return ListView(children: [
              const SizedBox(height: 90),
              MensajeVista(
                icono: Icons.list_alt_rounded,
                titulo: 'Todavía no hay listas para este evento',
                detalle: rol == Rol.admin
                    ? 'Creálas en Eventos → Listas.'
                    : 'Pedile al admin que las cree.',
                accion: 'Reintentar',
                alTocar: _recargar,
              ),
            ]);
          }
          final todos = invitados.value ?? const <Invitado>[];
          final nombreLista = {for (final l in ls) l.id: l.nombre};
          final esAdmin = rol == Rol.admin;

          bool pasaTeam(Invitado i) =>
              _team == null || (equipo[i.rrppId]?.teamId ?? '') == _team;
          final filtrados = todos
              .where((i) => pasaTeam(i) && (_vendedor == null || i.rrppId == _vendedor))
              .toList();
          final q = normalizar(_q.trim());
          final ahora = DateTime.now();

          // opciones de filtro: solo teams y relacionadores con anotados
          final teams = <String, String>{};
          final vendedores = <String, String>{};
          for (final i in todos) {
            final m = equipo[i.rrppId];
            teams[m?.teamId ?? ''] = m?.team ?? 'Sin team';
            if (pasaTeam(i)) vendedores[i.rrppId] = i.rrppNombre;
          }

          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
            children: [
              Text(
                '${filtrados.length} anotados · ${filtrados.where((i) => i.ingreso).length} ingresaron',
                style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
              ),
              const SizedBox(height: 10),
              TextField(
                onChanged: (v) => setState(() => _q = v),
                autocorrect: false,
                decoration: const InputDecoration(
                  hintText: 'Buscar por nombre en todas las listas…',
                  prefixIcon: Icon(Icons.search_rounded),
                ),
              ),
              if (esAdmin && todos.isNotEmpty) ...[
                const SizedBox(height: 10),
                Row(children: [
                  Expanded(
                    child: _Desplegable(
                      valor: _team,
                      vacio: 'Todos los teams',
                      opciones: teams,
                      alCambiar: (v) => setState(() {
                        _team = v;
                        _vendedor = null;
                      }),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _Desplegable(
                      valor: _vendedor,
                      vacio: 'Todos los relacionadores',
                      opciones: vendedores,
                      alCambiar: (v) => setState(() => _vendedor = v),
                    ),
                  ),
                ]),
              ],
              const SizedBox(height: 12),
              if (invitados.isLoading && todos.isEmpty)
                const Padding(
                    padding: EdgeInsets.all(24),
                    child: Center(child: CircularProgressIndicator()))
              else if (q.length >= 2) ...[
                // buscador global: encuentra al anotado en cualquier lista
                for (final i in filtrados
                    .where((i) => normalizar(i.nombre).contains(q))
                    .take(40))
                  _FilaInvitado(
                    invitado: i,
                    sub: '${nombreLista[i.listaId] ?? '?'} · lo anotó ${i.rrppNombre}',
                    permisos: p,
                    marcado: _marcados.contains(i.id),
                    armado: _armado,
                    alMarcar: null,
                    alVerQr: () => _verQr(i, ev, nombreLista[i.listaId] ?? 'Lista', p),
                    alTickear: null,
                    alDesmarcar: null,
                    alQuitar: null,
                  ),
                if (!filtrados.any((i) => normalizar(i.nombre).contains(q)))
                  const Padding(
                    padding: EdgeInsets.all(24),
                    child: Text('Nadie anotado con ese nombre.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: VenueColors.textoSuave)),
                  ),
              ] else
                for (final l in ls)
                  _tarjetaLista(l, ev, p, filtrados, cupos[l.id], l.abierta(ahora),
                      nombreLista),
            ],
          );
        },
      ),
    );
  }

  Widget _tarjetaLista(ListaTipo l, Evento ev, PermisosLista p,
      List<Invitado> filtrados, int? cupo, bool abiertaParaAnotar,
      Map<String, String> nombreLista) {
    var rs = filtrados.where((i) => i.listaId == l.id).toList();
    final propios = rs.where(p.esMio).length;
    final lleno = cupo != null && propios >= cupo;
    final on = _abierta == l.id;
    if (_ingresaronArriba) {
      rs = [...rs]..sort((a, b) {
          if (a.ingreso != b.ingreso) return a.ingreso ? -1 : 1;
          final c = a.rrppNombre.toLowerCase().compareTo(b.rrppNombre.toLowerCase());
          return c != 0 ? c : a.nombre.compareTo(b.nombre);
        });
    }
    final marcadosAca = rs.where((i) => _marcados.contains(i.id)).length;

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Card(
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            InkWell(
              onTap: () => setState(() => _abierta = on ? null : l.id),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 12, 14),
                child: Row(children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(l.nombre,
                            style: const TextStyle(
                                fontSize: 18, fontWeight: FontWeight.w800)),
                        const SizedBox(height: 6),
                        // lo que la puerta necesita de un vistazo, sin abrir la lista
                        Wrap(spacing: 6, runSpacing: 6, children: [
                          _Chip('${rs.length} anotados'),
                          _Chip('${rs.where((i) => i.ingreso).length} ingresaron',
                              color: VenueColors.ok),
                          if (l.ingresoHasta != null)
                            _Chip('hasta ${l.ingresoHasta}', color: VenueColors.aviso),
                          _Chip((l.precio ?? 0) > 0 ? '${l.precio} Bs' : 'Free',
                              color: const Color(0xFFE8B530), borde: true),
                        ]),
                      ],
                    ),
                  ),
                  Icon(on ? Icons.expand_less_rounded : Icons.expand_more_rounded,
                      color: VenueColors.textoSuave),
                ]),
              ),
            ),
            if (on) ...[
              const Divider(height: 1),
              Container(
                margin: const EdgeInsets.fromLTRB(12, 12, 12, 4),
                padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
                decoration: BoxDecoration(
                  color: VenueColors.superficie2,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: VenueColors.linea),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              cupo != null ? '$propios / $cupo' : '$propios',
                              style: TextStyle(
                                  fontSize: 22,
                                  fontWeight: FontWeight.w800,
                                  color: lleno ? VenueColors.aviso : VenueColors.texto),
                            ),
                            Text(
                              cupo != null
                                  ? (lleno ? 'tuyos · cupo lleno' : 'tuyos · quedan ${cupo - propios}')
                                  : 'tuyos${p.rol == Rol.admin ? ' · sin límite' : ''}',
                              style: const TextStyle(
                                  color: VenueColors.textoSuave, fontSize: 13),
                            ),
                          ],
                        ),
                      ),
                      if (p.rol == Rol.admin)
                        IconButton(
                          tooltip: 'Límites y horarios de la lista',
                          onPressed: () async {
                            await abrirEditarLista(context, ref, ev.id, l.id);
                            _recargar();
                          },
                          icon: const Icon(Icons.tune_rounded,
                              color: VenueColors.textoSuave),
                        ),
                      if (rs.length > 1)
                        IconButton(
                          tooltip: _ingresaronArriba
                              ? 'Orden normal'
                              : 'Los que ingresaron arriba',
                          onPressed: () =>
                              setState(() => _ingresaronArriba = !_ingresaronArriba),
                          icon: Icon(Icons.vertical_align_top_rounded,
                              color: _ingresaronArriba
                                  ? Theme.of(context).colorScheme.primary
                                  : VenueColors.textoSuave),
                        ),
                    ]),
                    if (p.anota) ...[
                      const SizedBox(height: 10),
                      Padding(
                        padding: const EdgeInsets.only(right: 6),
                        child: FilledButton.icon(
                          onPressed:
                              abiertaParaAnotar && !lleno ? () => _anotar(l) : null,
                          style: FilledButton.styleFrom(minimumSize: const Size(0, 46)),
                          icon: const Icon(Icons.add_rounded, size: 20),
                          label: Text(lleno
                              ? 'Cupo lleno'
                              : abiertaParaAnotar
                                  ? 'Agregar invitados'
                                  : 'Cerrada'),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              if (rs.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(20),
                  child: Text('Nadie anotado todavía.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: VenueColors.textoSuave)),
                ),
              for (final i in rs)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: _FilaInvitado(
                    invitado: i,
                    sub: i.rrppNombre.isEmpty ? null : 'lo anotó ${i.rrppNombre}',
                    permisos: p,
                    marcado: _marcados.contains(i.id),
                    armado: _armado,
                    alMarcar: p.mandar(i)
                        ? (v) => setState(() =>
                            v ? _marcados.add(i.id) : _marcados.remove(i.id))
                        : null,
                    alVerQr: () => _verQr(i, ev, l.nombre, p),
                    alTickear: p.tickea && !i.ingreso ? () => _tickear(i) : null,
                    alDesmarcar: p.tickea && i.ingreso
                        ? () {
                            if (!_confirmado('des:${i.id}',
                                'Tocá de nuevo para desmarcar el ingreso')) {
                              return;
                            }
                            _hacer(() async {
                              await ref
                                  .read(supabaseProvider)
                                  .rpc('descheckin_registro', params: {'p_registro': i.id});
                              ref.invalidate(invitadosProvider);
                              if (mounted) {
                                avisar(context, 'Ingreso desmarcado',
                                    tipo: TipoAviso.aviso);
                              }
                            });
                          }
                        : null,
                    alQuitar: p.quitar(i)
                        ? () {
                            if (!_confirmado('del:${i.id}',
                                'Tocá de nuevo para quitar a ${i.nombre}')) {
                              return;
                            }
                            _hacer(() async {
                              await ref.read(listasRepositoryProvider).eliminar(i.id);
                              _marcados.remove(i.id);
                              _recargar();
                              if (mounted) {
                                avisar(context, '${i.nombre} eliminado de la lista',
                                    tipo: TipoAviso.aviso);
                              }
                            });
                          }
                        : null,
                  ),
                ),
              if (marcadosAca > 0 || _marcados.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 6, 12, 12),
                  child: Row(children: [
                    Expanded(
                        child: Text('${_marcados.length} marcados',
                            style: const TextStyle(fontWeight: FontWeight.w700))),
                    TextButton(
                        onPressed: () => setState(_marcados.clear),
                        child: const Text('Limpiar')),
                    const SizedBox(width: 6),
                    FilledButton.icon(
                      style: FilledButton.styleFrom(
                          minimumSize: const Size(0, 44),
                          padding: const EdgeInsets.symmetric(horizontal: 14)),
                      onPressed: () => _enviarTanda(filtrados, ev, nombreLista),
                      icon: const Icon(Icons.send_rounded, size: 18),
                      label: const Text('Enviar QRs'),
                    ),
                  ]),
                )
              else
                const SizedBox(height: 8),
            ],
          ],
        ),
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip(this.texto, {this.color = VenueColors.textoSuave, this.borde = false});
  final String texto;
  final Color color;
  final bool borde;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
        decoration: BoxDecoration(
          color: borde ? Colors.transparent : color.withValues(alpha: .12),
          borderRadius: BorderRadius.circular(99),
          border: borde ? Border.all(color: color.withValues(alpha: .7)) : null,
        ),
        child: Text(texto,
            style: TextStyle(color: color, fontSize: 12.5, fontWeight: FontWeight.w700)),
      );
}

class _FilaInvitado extends StatelessWidget {
  const _FilaInvitado({
    required this.invitado,
    required this.sub,
    required this.permisos,
    required this.marcado,
    required this.armado,
    required this.alMarcar,
    required this.alVerQr,
    required this.alTickear,
    required this.alDesmarcar,
    required this.alQuitar,
  });

  final Invitado invitado;
  final String? sub;
  final PermisosLista permisos;
  final bool marcado;
  final String? armado;
  final ValueChanged<bool>? alMarcar;
  final VoidCallback alVerQr;
  final VoidCallback? alTickear;
  final VoidCallback? alDesmarcar;
  final VoidCallback? alQuitar;

  @override
  Widget build(BuildContext context) {
    final i = invitado;
    return Row(
      children: [
        if (alMarcar != null)
          Checkbox(value: marcado, onChanged: (v) => alMarcar!(v ?? false))
        else
          const SizedBox(width: 12),
        Expanded(
          child: InkWell(
            onTap: alVerQr,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(i.nombre,
                      style: const TextStyle(
                          fontSize: 15.5, fontWeight: FontWeight.w600)),
                  Text(
                    [
                      i.ingreso ? 'Ingresó ${horaCorta(i.ingresoAt!)}' : 'No ingresó',
                      if (i.codigo != null) 'QR',
                      ?sub,
                    ].join(' · '),
                    style: TextStyle(
                        fontSize: 12.5,
                        color: i.ingreso ? VenueColors.ok : VenueColors.textoSuave),
                  ),
                ],
              ),
            ),
          ),
        ),
        if (alTickear != null || alDesmarcar != null)
          IconButton(
            tooltip: i.ingreso ? 'Desmarcar ingreso' : 'Marcar ingreso',
            onPressed: alTickear ?? alDesmarcar,
            icon: Icon(
              i.ingreso ? Icons.check_box_rounded : Icons.check_box_outline_blank_rounded,
              color: armado == 'des:${i.id}'
                  ? VenueColors.mal
                  : i.ingreso
                      ? VenueColors.ok
                      : VenueColors.textoSuave,
            ),
          ),
        if (alQuitar != null)
          IconButton(
            tooltip: 'Quitar de la lista',
            onPressed: alQuitar,
            icon: Icon(Icons.close_rounded,
                color: armado == 'del:${i.id}' ? VenueColors.mal : VenueColors.textoSuave),
          ),
      ],
    );
  }
}

class _Desplegable extends StatelessWidget {
  const _Desplegable({
    required this.valor,
    required this.vacio,
    required this.opciones,
    required this.alCambiar,
  });
  final String? valor;
  final String vacio;
  final Map<String, String> opciones;
  final ValueChanged<String?> alCambiar;

  @override
  Widget build(BuildContext context) {
    final orden = opciones.entries.toList()
      ..sort((a, b) => a.value.toLowerCase().compareTo(b.value.toLowerCase()));
    return DropdownButtonFormField<String?>(
      initialValue: opciones.containsKey(valor) ? valor : null,
      isExpanded: true,
      decoration: const InputDecoration(
          contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10)),
      items: [
        DropdownMenuItem<String?>(value: null, child: Text(vacio, overflow: TextOverflow.ellipsis)),
        for (final e in orden)
          DropdownMenuItem<String?>(
              value: e.key, child: Text(e.value, overflow: TextOverflow.ellipsis)),
      ],
      onChanged: alCambiar,
    );
  }
}

class _AnotarSheet extends StatefulWidget {
  const _AnotarSheet({required this.lista, required this.vendedores});
  final ListaTipo lista;
  final List<Miembro> vendedores;

  @override
  State<_AnotarSheet> createState() => _AnotarSheetState();
}

class _AnotarSheetState extends State<_AnotarSheet> {
  final _texto = TextEditingController();
  String? _de;

  @override
  void dispose() {
    _texto.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
          20, 0, 20, 20 + MediaQuery.of(context).viewInsets.bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Anotar en ${widget.lista.nombre}',
              style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w800)),
          const SizedBox(height: 4),
          const Text('Un nombre completo por línea.',
              style: TextStyle(color: VenueColors.textoSuave)),
          const SizedBox(height: 12),
          TextField(
            controller: _texto,
            autofocus: true,
            minLines: 4,
            maxLines: 8,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(hintText: 'Ana Paz\nJorge Vaca'),
          ),
          if (widget.vendedores.isNotEmpty) ...[
            const SizedBox(height: 12),
            DropdownButtonFormField<String?>(
              initialValue: _de,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'A nombre de'),
              items: [
                const DropdownMenuItem<String?>(value: null, child: Text('Mío')),
                for (final v in widget.vendedores)
                  DropdownMenuItem<String?>(
                      value: v.id,
                      child: Text(
                          v.team == 'Sin team' ? v.nombre : '${v.nombre} · ${v.team}',
                          overflow: TextOverflow.ellipsis)),
              ],
              onChanged: (v) => setState(() => _de = v),
            ),
          ],
          const SizedBox(height: 14),
          FilledButton(
            onPressed: () => Navigator.pop(
                context, (nombres: separarNombres(_texto.text), de: _de)),
            child: const Text('Anotar'),
          ),
        ],
      ),
    );
  }
}
