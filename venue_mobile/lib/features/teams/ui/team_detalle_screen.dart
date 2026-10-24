import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';

import '../../../core/theme/venue_theme.dart';
import '../../../core/widgets/avisos.dart';
import '../../../core/widgets/estado_vista.dart';
import '../../../core/widgets/patron.dart';
import '../../analytics/data/reporte.dart';
import '../../clubs/data/clubs.dart';
import '../../events/data/eventos.dart';
import '../data/equipo.dart';
import '../data/gente.dart';

/// Abre la página de un team: su gente con lo que vendió cada uno.
Future<void> abrirTeam(BuildContext context, TeamInfo team) => Navigator.of(context)
    .push(MaterialPageRoute(builder: (_) => TeamDetalleScreen(team: team)));

/// Abre el detalle de una persona: qué vendió y a quién.
Future<void> abrirPersona(BuildContext context, String id, String nombre,
        {String? eventoId}) =>
    Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => PersonaDetalleScreen(id: id, nombre: nombre, eventoId: eventoId)));

String _bs(num n) => '${n == n.roundToDouble() ? n.round() : n.toStringAsFixed(1)} Bs';

/// Evento sobre el que se miran los números. Arranca en el de trabajo y se
/// puede cambiar por cualquier otro del boliche (también los cerrados).
Evento? _eventoInicial(WidgetRef ref, String? id, List<Evento> lista) {
  final activo = ref.read(eventoActivoProvider);
  return lista.where((e) => e.id == (id ?? activo?.id)).firstOrNull ?? activo ?? lista.firstOrNull;
}

Future<Evento?> _elegirEvento(BuildContext context, List<Evento> lista, Evento? actual) =>
    showModalBottomSheet<Evento>(
      context: context,
      isScrollControlled: true,
      builder: (c) => SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(c).height * .7),
          child: ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            children: [
              const Padding(
                padding: EdgeInsets.only(left: 4, bottom: 8),
                child: Text('Evento', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
              ),
              for (final e in lista)
                ListTile(
                  title: Text(e.nombre, style: const TextStyle(fontWeight: FontWeight.w500)),
                  subtitle: Text('${e.fechaCorta}${e.estado == 'cerrado' ? ' · cerrado' : ''}'),
                  trailing: e.id == actual?.id ? const Icon(Icons.check_rounded) : null,
                  onTap: () => Navigator.pop(c, e),
                ),
            ],
          ),
        ),
      ),
    );

/// Barra de las páginas de detalle: volver y el contexto chico.
PreferredSizeWidget _barra(String contexto) => AppBar(
      titleSpacing: 0,
      title: Text(contexto,
          style: TextStyle(fontSize: 15, fontWeight: FontWeight.w500, color: VenueColors.textoSuave)),
      bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Divider(height: 1, color: VenueColors.lineaSuave)),
    );

// ═══════════════════════ TEAM ═══════════════════════
class TeamDetalleScreen extends ConsumerStatefulWidget {
  const TeamDetalleScreen({super.key, required this.team});
  final TeamInfo team;

  @override
  ConsumerState<TeamDetalleScreen> createState() => _TeamDetalleScreenState();
}

class _TeamDetalleScreenState extends ConsumerState<TeamDetalleScreen> {
  String? _eventoId;

  @override
  Widget build(BuildContext context) {
    final t = widget.team;
    final club = ref.watch(clubActivoProvider);
    final equipo = ref.watch(equipoProvider).value ?? const <String, Miembro>{};
    final eventos = ref.watch(eventosDelClubProvider).value ?? const <Evento>[];
    final ev = _eventoInicial(ref, _eventoId, eventos);
    final cierre = ev == null ? null : ref.watch(cierreDeProvider(ev.id));
    final miembros = equipo.values.where((m) => m.teamId == t.id).toList();
    final jefe = equipo[t.jefeId];

    return Scaffold(
      appBar: _barra('Teams'),
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(equipoProvider);
          if (ev == null) return;
          ref.invalidate(cierreDeProvider(ev.id));
          await ref.read(cierreDeProvider(ev.id).future);
        },
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 18, 16, 32),
          children: [
            Encabezado(
              etiqueta: club?.nombre,
              titulo: t.nombre,
              contexto: [
                '${miembros.length} ${miembros.length == 1 ? 'persona' : 'personas'}',
                if (jefe != null) 'Jefe: ${jefe.nombre}',
              ].join(' · '),
            ),
            if (ev != null)
              ChipFiltro(
                etiqueta: 'Evento',
                valor: '${ev.nombre} · ${ev.fechaCorta}',
                alTocar: eventos.length < 2
                    ? null
                    : () async {
                        final e = await _elegirEvento(context, eventos, ev);
                        if (e != null) setState(() => _eventoId = e.id);
                      },
              ),
            const SizedBox(height: 14),
            if (cierre == null)
              const MensajeVista(
                  icono: Icons.event_busy_outlined,
                  titulo: 'Sin eventos',
                  detalle: 'Cuando haya un evento vas a ver acá lo que vendió el team.')
            else
              VistaAsync(
                valor: cierre,
                reintentar: () => ref.invalidate(cierreDeProvider(ev!.id)),
                datos: (c) => _CuerpoTeam(team: t, miembros: miembros, cierre: c, evento: ev!),
              ),
          ],
        ),
      ),
    );
  }
}

class _CuerpoTeam extends ConsumerWidget {
  const _CuerpoTeam({
    required this.team,
    required this.miembros,
    required this.cierre,
    required this.evento,
  });
  final TeamInfo team;
  final List<Miembro> miembros;
  final Cierre cierre;
  final Evento evento;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final stats = {for (final p in cierre.personas) p.id: p};
    // los del team, más quien vendió para el team en ese evento y ya no está
    final ids = {
      ...miembros.map((m) => m.id),
      ...cierre.personas.where((p) => p.teamId == team.id).map((p) => p.id),
    };
    final nombres = {for (final m in miembros) m.id: m.nombre};
    final filas = [
      for (final id in ids)
        (
          id: id,
          nombre: nombres[id] ?? stats[id]?.nombre ?? '',
          rol: miembros.where((m) => m.id == id).firstOrNull?.rol,
          s: stats[id],
        ),
    ]..sort((a, b) {
        int peso(StatsPersona? s) => s == null ? 0 : s.usadas + s.ingresaron + s.mesas;
        final x = peso(b.s).compareTo(peso(a.s));
        if (x != 0) return x;
        final y = (b.s?.vendidas ?? 0).compareTo(a.s?.vendidas ?? 0);
        return y != 0 ? y : a.nombre.compareTo(b.nombre);
      });

    num sum(num Function(StatsPersona) f) => filas.fold<num>(0, (a, r) => a + (r.s == null ? 0 : f(r.s!)));
    final vendidas = sum((s) => s.vendidas).toInt();
    final usadas = sum((s) => s.usadas).toInt();
    final anotados = sum((s) => s.anotados).toInt();
    final ingresaron = sum((s) => s.ingresaron).toInt();
    final mesas = sum((s) => s.mesas).toInt();
    final bruto = sum((s) => s.brutoEntradas + s.brutoMesas);
    final aPagar = sum((s) => s.aPagar);

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      TarjetaDatos(filas: [
        [
          Dato('Entradas vendidas', '$vendidas', detalle: '$usadas ingresaron'),
          Dato('En lista', '$ingresaron / $anotados', detalle: 'ingresaron / anotados'),
        ],
        [
          Dato('Mesas', '$mesas'),
          Dato('Facturado', _bs(bruto)),
        ],
        [Dato('A pagar al team', _bs(aPagar), detalle: 'comisiones y bonos', tono: Tono.ok)],
      ]),
      TituloBloque(
        'Personas',
        accion: IconButton(
          tooltip: 'Invitar al team',
          icon: Icon(Icons.person_add_alt_1_outlined, color: VenueColors.textoSuave),
          onPressed: () => SharePlus.instance.share(ShareParams(
              text: mensajeDeInvitacion(team, ref.read(clubActivoProvider)?.nombre ?? ''))),
        ),
      ),
      if (filas.isEmpty)
        Padding(
          padding: const EdgeInsets.all(24),
          child: Text('Este team todavía no tiene gente.',
              textAlign: TextAlign.center, style: TextStyle(color: VenueColors.textoSuave)),
        )
      else
        Tarjeta(
          padding: EdgeInsets.zero,
          child: Column(children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 10),
              child: Row(children: [
                Expanded(child: _Cab('Persona')),
                SizedBox(width: 64, child: _Cab('Vendidas', derecha: true)),
                SizedBox(width: 72, child: _Cab('Ingresaron', derecha: true)),
              ]),
            ),
            Divider(height: 1, color: VenueColors.lineaSuave),
            for (var i = 0; i < filas.length; i++) ...[
              if (i > 0) Divider(height: 1, indent: 60, color: VenueColors.lineaSuave),
              InkWell(
                onTap: () => abrirPersona(context, filas[i].id, filas[i].nombre, eventoId: evento.id),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
                  child: Row(children: [
                    Inicial(filas[i].nombre, lado: 32),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(filas[i].nombre,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500)),
                        Text(
                          [
                            Rol.desde(filas[i].rol)?.etiqueta ?? 'Ya no está en el team',
                            if ((filas[i].s?.mesas ?? 0) > 0)
                              '${filas[i].s!.mesas} ${filas[i].s!.mesas == 1 ? 'mesa' : 'mesas'}',
                          ].join(' · '),
                          style: TextStyle(fontSize: 12.5, color: VenueColors.textoTenue),
                        ),
                      ]),
                    ),
                    SizedBox(
                      width: 64,
                      child: Text('${filas[i].s?.vendidas ?? 0}',
                          textAlign: TextAlign.right, style: _numero),
                    ),
                    SizedBox(
                      width: 72,
                      child: Text(
                          '${(filas[i].s?.usadas ?? 0) + (filas[i].s?.ingresaron ?? 0)}',
                          textAlign: TextAlign.right,
                          style: _numero),
                    ),
                  ]),
                ),
              ),
            ],
          ]),
        ),
      Padding(
        padding: const EdgeInsets.fromLTRB(4, 10, 4, 0),
        child: Text(
            'Ingresaron = entradas usadas + invitados de lista que entraron. Tocá una persona para ver a quién le vendió.',
            style: TextStyle(fontSize: 12.5, color: VenueColors.textoTenue)),
      ),
    ]);
  }
}

const _numero = TextStyle(
    fontSize: 15, fontWeight: FontWeight.w600, fontFeatures: [FontFeature.tabularFigures()]);

class _Cab extends StatelessWidget {
  const _Cab(this.t, {this.derecha = false});
  final String t;
  final bool derecha;

  @override
  Widget build(BuildContext context) => Text(t,
      textAlign: derecha ? TextAlign.right : TextAlign.left,
      style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w500, color: VenueColors.textoTenue));
}

// ═══════════════════════ PERSONA ═══════════════════════
typedef _Clave = ({String evento, String persona});

final _ventasProvider = FutureProvider.autoDispose.family<
    ({List<Map<String, dynamic>> entradas, List<Map<String, dynamic>> registros, List<Map<String, dynamic>> mesas}),
    _Clave>((ref, k) async {
  final repo = ref.watch(reporteRepositoryProvider);
  final r = await Future.wait([repo.detalle(k.evento, k.persona), repo.mesasDe(k.evento, k.persona)]);
  final d = r[0] as ({List<Map<String, dynamic>> registros, List<Map<String, dynamic>> entradas});
  return (entradas: d.entradas, registros: d.registros, mesas: r[1] as List<Map<String, dynamic>>);
});

/// Lo de los últimos 90 días de la persona (mismas cuentas que el ranking).
final _historicoProvider =
    FutureProvider.autoDispose.family<Map<String, dynamic>?, String>((ref, usuario) async {
  final club = ref.watch(clubActivoIdProvider);
  if (club == null) return null;
  final r = await ref
      .watch(reporteRepositoryProvider)
      .ranking(club, DateTime.now().subtract(const Duration(days: 90)));
  return r.where((x) => x['usuario'] == usuario).firstOrNull;
});

enum _Pestana { entradas, listas, mesas }

class PersonaDetalleScreen extends ConsumerStatefulWidget {
  const PersonaDetalleScreen({super.key, required this.id, required this.nombre, this.eventoId});
  final String id;
  final String nombre;
  final String? eventoId;

  @override
  ConsumerState<PersonaDetalleScreen> createState() => _PersonaDetalleScreenState();
}

class _PersonaDetalleScreenState extends ConsumerState<PersonaDetalleScreen> {
  late String? _eventoId = widget.eventoId;
  _Pestana _p = _Pestana.entradas;
  String _q = '';

  @override
  Widget build(BuildContext context) {
    final equipo = ref.watch(equipoProvider).value ?? const <String, Miembro>{};
    final usuarios = ref.watch(usuariosProvider).value ?? const <Usuario>[];
    final eventos = ref.watch(eventosDelClubProvider).value ?? const <Evento>[];
    final yo = equipo[widget.id];
    final u = usuarios.where((x) => x.id == widget.id).firstOrNull;
    final ev = _eventoInicial(ref, _eventoId, eventos);
    final stats = ev == null
        ? null
        : ref.watch(cierreDeProvider(ev.id)).whenData(
            (c) => c.personas.where((p) => p.id == widget.id).firstOrNull);
    final ventas = ev == null ? null : ref.watch(_ventasProvider((evento: ev.id, persona: widget.id)));
    final historico = u == null ? null : ref.watch(_historicoProvider(u.usuario)).value;

    return Scaffold(
      appBar: _barra(yo?.teamId != null ? yo!.team : 'Persona'),
      body: RefreshIndicator(
        onRefresh: () async {
          if (ev == null) return;
          ref.invalidate(cierreDeProvider(ev.id));
          final k = (evento: ev.id, persona: widget.id);
          ref.invalidate(_ventasProvider(k));
          await ref.read(_ventasProvider(k).future);
        },
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 18, 16, 32),
          children: [
            Encabezado(
              inicio: Inicial(widget.nombre, lado: 52),
              titulo: widget.nombre,
              contexto: [
                if (u != null) '@${u.usuario}',
                Rol.desde(yo?.rol ?? u?.rol)?.etiqueta ?? '',
                if (u != null && !u.activo) 'en pausa',
              ].where((x) => x.isNotEmpty).join(' · '),
            ),
            if (ev != null)
              ChipFiltro(
                etiqueta: 'Evento',
                valor: '${ev.nombre} · ${ev.fechaCorta}',
                alTocar: eventos.length < 2
                    ? null
                    : () async {
                        final e = await _elegirEvento(context, eventos, ev);
                        if (e != null) setState(() => _eventoId = e.id);
                      },
              ),
            const SizedBox(height: 14),
            if (stats != null)
              VistaAsync(
                valor: stats,
                reintentar: () => ref.invalidate(cierreDeProvider(ev!.id)),
                datos: (s) => TarjetaDatos(filas: [
                  [
                    Dato('Entradas vendidas', '${s?.vendidas ?? 0}',
                        detalle: '${s?.usadas ?? 0} ingresaron'),
                    Dato('En lista', '${s?.ingresaron ?? 0} / ${s?.anotados ?? 0}',
                        detalle: 'ingresaron / anotados'),
                  ],
                  [
                    Dato('Mesas', '${s?.mesas ?? 0}', detalle: _bs(s?.brutoMesas ?? 0)),
                    Dato('A pagarle', _bs(s?.aPagar ?? 0),
                        detalle: (s?.bono ?? 0) > 0 ? 'incluye ${_bs(s!.bono)} de bono' : 'comisiones',
                        tono: Tono.ok),
                  ],
                ]),
              ),
            if (ventas != null) ...[
              const TituloBloque('A quién le vendió'),
              VistaAsync(
                valor: ventas,
                reintentar: () =>
                    ref.invalidate(_ventasProvider((evento: ev!.id, persona: widget.id))),
                datos: (v) => _Ventas(
                  v: v,
                  pestana: _p,
                  busqueda: _q,
                  alCambiar: (p) => setState(() => _p = p),
                  alBuscar: (q) => setState(() => _q = q),
                ),
              ),
            ],
            if (historico != null) ...[
              const TituloBloque('Últimos 90 días'),
              TarjetaDatos(filas: [
                [
                  Dato('Entradas que ingresaron', '${historico['entradas'] ?? 0}'),
                  Dato('Lista', '${historico['ingresados'] ?? 0} / ${historico['anotados'] ?? 0}'),
                ],
                [
                  Dato('Mesas', '${historico['mesas'] ?? 0}'),
                  Dato('Comisiones', _bs(historico['comision'] as num? ?? 0)),
                ],
              ]),
            ],
          ],
        ),
      ),
    );
  }
}

class _Ventas extends StatelessWidget {
  const _Ventas({
    required this.v,
    required this.pestana,
    required this.busqueda,
    required this.alCambiar,
    required this.alBuscar,
  });
  final ({List<Map<String, dynamic>> entradas, List<Map<String, dynamic>> registros, List<Map<String, dynamic>> mesas}) v;
  final _Pestana pestana;
  final String busqueda;
  final ValueChanged<_Pestana> alCambiar;
  final ValueChanged<String> alBuscar;

  @override
  Widget build(BuildContext context) {
    String? hora(dynamic ts) {
      final t = DateTime.tryParse(ts as String? ?? '')?.toLocal();
      return t == null ? null : horaCorta(t);
    }

    final q = normalizar(busqueda.trim());
    bool pasa(String s) => q.isEmpty || normalizar(s).contains(q);

    final filas = <({String nombre, String detalle, String estado, Tono tono})>[
      if (pestana == _Pestana.entradas)
        for (final e in v.entradas)
          if (pasa('${e['cliente']} ${e['code']}'))
            (
              nombre: '${e['cliente'] ?? '—'}',
              detalle: [
                '#${e['code']}',
                if (e['mesa_id'] != null) 'de mesa',
                if (hora(e['used_at']) != null) 'entró ${hora(e['used_at'])}',
              ].join(' · '),
              estado: switch (e['estado']) {
                'usada' => 'Ingresó',
                'anulada' => 'Anulada',
                _ => 'Pendiente',
              },
              tono: switch (e['estado']) {
                'usada' => Tono.ok,
                'anulada' => Tono.mal,
                _ => Tono.neutro,
              },
            ),
      if (pestana == _Pestana.listas)
        for (final r in v.registros)
          if (pasa('${r['nombre']}'))
            (
              nombre: '${r['nombre'] ?? '—'}',
              detalle: [
                '${(r['l'] as Map?)?['nombre'] ?? 'Lista'}',
                if (hora(r['ingreso_at']) != null) 'entró ${hora(r['ingreso_at'])}',
              ].join(' · '),
              estado: r['ingreso_at'] != null ? 'Ingresó' : 'No vino aún',
              tono: r['ingreso_at'] != null ? Tono.ok : Tono.neutro,
            ),
      if (pestana == _Pestana.mesas)
        for (final m in v.mesas)
          if (pasa('${m['cliente']} ${m['etiqueta']}'))
            (
              nombre: '${m['cliente'] ?? 'Sin nombre'}',
              detalle: [
                '${m['etiqueta']}',
                _bs(m['precio'] as num? ?? 0),
                if ((m['manillas'] as num? ?? 0) > 0) '${m['manillas']} manillas',
              ].join(' · '),
              estado: m['pago_verificado'] == true
                  ? 'Pagada'
                  : m['estado'] == 'reservada'
                      ? 'Reservada'
                      : 'Vendida',
              tono: m['pago_verificado'] == true
                  ? Tono.ok
                  : m['estado'] == 'reservada'
                      ? Tono.aviso
                      : Tono.neutro,
            ),
    ];
    final total = switch (pestana) {
      _Pestana.entradas => v.entradas.length,
      _Pestana.listas => v.registros.length,
      _Pestana.mesas => v.mesas.length,
    };

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      SegmentedButton<_Pestana>(
        showSelectedIcon: false,
        segments: [
          ButtonSegment(value: _Pestana.entradas, label: Text('Entradas ${v.entradas.length}')),
          ButtonSegment(value: _Pestana.listas, label: Text('Listas ${v.registros.length}')),
          ButtonSegment(value: _Pestana.mesas, label: Text('Mesas ${v.mesas.length}')),
        ],
        selected: {pestana},
        onSelectionChanged: (s) => alCambiar(s.first),
      ),
      if (total > 8) ...[
        const SizedBox(height: 10),
        TextField(
          onChanged: alBuscar,
          autocorrect: false,
          decoration: const InputDecoration(
            isDense: true,
            hintText: 'Buscar cliente…',
            prefixIcon: Icon(Icons.search_rounded),
          ),
        ),
      ],
      const SizedBox(height: 10),
      if (filas.isEmpty)
        Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
              total == 0 ? 'Nada en este evento.' : 'Sin resultados.',
              textAlign: TextAlign.center,
              style: TextStyle(color: VenueColors.textoSuave)),
        )
      else
        Tarjeta(
          padding: EdgeInsets.zero,
          child: Column(children: [
            for (var i = 0; i < filas.length; i++) ...[
              if (i > 0) Divider(height: 1, indent: 16, color: VenueColors.lineaSuave),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 11, 12, 11),
                child: Row(children: [
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(filas[i].nombre,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500)),
                      const SizedBox(height: 1),
                      Text(filas[i].detalle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 12.5, color: VenueColors.textoTenue)),
                    ]),
                  ),
                  const SizedBox(width: 8),
                  PillEstado(filas[i].estado, tono: filas[i].tono),
                ]),
              ),
            ],
          ]),
        ),
    ]);
  }
}
