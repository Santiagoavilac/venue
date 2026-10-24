import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/networking/supabase.dart';
import '../../../core/theme/venue_theme.dart';
import '../../../core/widgets/avisos.dart';
import '../../../core/widgets/estado_vista.dart';
import '../../../core/widgets/patron.dart';
import '../../authentication/data/sesion.dart';
import '../../clubs/data/clubs.dart';
import '../../events/data/eventos.dart';
import '../../teams/data/equipo.dart';
import '../../teams/ui/team_detalle_screen.dart';
import '../data/reporte.dart';
import 'reporte_hojas.dart';

/// Reporte del evento. Admin: cierre completo. Jefe: su team. Relacionador:
/// lo suyo. Los datos que llegan ya vienen recortados por RLS a lo que cada
/// uno puede ver.
class ReporteScreen extends ConsumerWidget {
  const ReporteScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ev = ref.watch(eventoActivoProvider);
    final rol = ref.watch(rolProvider).value;
    final perfil = ref.watch(perfilProvider).value;
    final club = ref.watch(clubActivoProvider);
    if (ev == null || rol == null || perfil == null || club == null) {
      return const MensajeVista(
        icono: Icons.event_busy_rounded,
        titulo: 'No hay evento activo',
      );
    }
    final cierre = ref.watch(cierreProvider);
    final equipo = ref.watch(equipoProvider).value ?? const <String, Miembro>{};
    final eventos = ref.watch(eventosProvider).value ?? const <Evento>[];
    final esAdmin = rol == Rol.admin;
    final miTeam = equipo[perfil.id]?.teamId;
    final puedeExcel =
        perfil.contabilidadTotal || (rol == Rol.jefe && miTeam != null);

    return RefreshIndicator(
      onRefresh: () async {
        ref.invalidate(cierreProvider);
        ref.invalidate(liquidacionProvider);
        await ref.read(cierreProvider.future);
      },
      child: VistaAsync(
        valor: cierre,
        reintentar: () => ref.invalidate(cierreProvider),
        datos: (c) {
          // el jefe ve su team; el relacionador, su fila
          final mias = esAdmin
              ? c.personas
              : rol == Rol.jefe
              ? c.personas
                    .where((p) => p.teamId == miTeam || p.id == perfil.id)
                    .toList()
              : c.personas.where((p) => p.id == perfil.id).toList();
          num s(num Function(StatsPersona) f) =>
              mias.fold<num>(0, (a, p) => a + f(p));
          int si(num Function(StatsPersona) f) => s(f).toInt();

          final ancho = MediaQuery.sizeOf(context).width >= 1100;
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
            children: [
              Encabezado(
                titulo: esAdmin
                    ? 'Reporte del evento'
                    : rol == Rol.jefe
                    ? 'Números de mi team'
                    : 'Mis números',
                contexto: club.nombre,
              ),
              ChipFiltro(
                etiqueta: 'Evento',
                valor: '${ev.nombre} · ${ev.fechaCorta}',
                alTocar: eventos.length < 2 ? null : () => _elegirEvento(context, ref, eventos, ev),
              ),
              const SizedBox(height: 14),
              if (esAdmin) ...[
                ancho
                    ? const Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(flex: 162, child: _Liquidacion()),
                          SizedBox(width: 14),
                          Expanded(flex: 100, child: _AjustesCierre()),
                        ],
                      )
                    : const _Liquidacion(),
                const TituloBloque('De dónde sale la plata'),
                _Composicion(c: c),
              ],
              const TituloBloque('Asistencia'),
              Tarjeta(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                child: Column(children: [
                  BarraProgreso(
                    etiqueta: 'Invitados de lista que entraron',
                    valor: esAdmin ? c.listaIngresaron : si((p) => p.ingresaron),
                    de: esAdmin ? c.listaAnotados : si((p) => p.anotados),
                    color: VenueColors.ok,
                  ),
                  BarraProgreso(
                    etiqueta: 'Entradas con QR usadas',
                    valor: esAdmin ? c.entUsadas : si((p) => p.usadas),
                    de: esAdmin ? c.entVendidas : si((p) => p.vendidas),
                  ),
                  if (esAdmin)
                    for (final l in c.porLista)
                      BarraProgreso(
                        etiqueta: l.nombre,
                        valor: l.ingresaron,
                        de: l.anotados,
                        color: VenueColors.aviso,
                      ),
                ]),
              ),
              if (!esAdmin) ...[
                const TituloBloque('Plata'),
                TarjetaDatos(filas: [
                  [
                    Dato('Mesas', '${si((p) => p.mesas)}', detalle: _bs(s((p) => p.brutoMesas))),
                    rol == Rol.jefe
                        ? Dato('Comisión RRPPs', _bs(s((p) => p.comRrpp + p.comRrppMesas)))
                        : Dato('Bonos', _bs(s((p) => p.bono))),
                  ],
                  [
                    rol == Rol.jefe
                        ? Dato('Mi comisión (jefe)', _bs(s((p) => p.comJefe + p.comJefeMesas)),
                            tono: Tono.ok)
                        : Dato('Mi comisión total', _bs(s((p) => p.comRrpp + p.comRrppMesas + p.bono)),
                            detalle: 'entradas + mesas + bonos', tono: Tono.ok),
                  ],
                ]),
              ],
              if (esAdmin || rol == Rol.jefe) ...[
                TituloBloque(
                  esAdmin ? 'Top relacionadores' : 'Mi team',
                  verTodo: mias.length > 5
                      ? () => _verTodos(context, esAdmin ? 'Relacionadores' : 'Mi team', mias, equipo, ev)
                      : null,
                ),
                _TablaTop(personas: mias, equipo: equipo, evento: ev, limite: 5),
              ],
              if (esAdmin) ...[
                const TituloBloque('Por team'),
                _PorTeam(personas: mias, equipo: equipo, evento: ev),
              ],
              const TituloBloque('Acciones'),
              GrillaAcciones(children: [
                if (esAdmin)
                  AccionRapida(
                    icono: Icons.copy_rounded,
                    titulo: 'Copiar cierre',
                    detalle: 'Para WhatsApp',
                    alTocar: () async {
                      await Clipboard.setData(ClipboardData(
                          text: textoCierre(ev.nombre, club.nombre, ev.fechaCorta, c)));
                      if (context.mounted) avisar(context, 'Cierre copiado — pegalo en WhatsApp');
                    },
                  ),
                if (rol == Rol.rrpp)
                  AccionRapida(
                    icono: Icons.receipt_long_outlined,
                    titulo: 'A quién le vendí',
                    detalle: 'Nombre por nombre',
                    alTocar: () => abrirPersona(context, perfil.id, perfil.nombre, eventoId: ev.id),
                  ),
                if (puedeExcel)
                  AccionRapida(
                    icono: Icons.description_outlined,
                    titulo: 'Excel',
                    detalle: perfil.contabilidadTotal ? 'Contabilidad' : 'De mi team',
                    color: VenueColors.ok,
                    alTocar: () => exportarContabilidad(context, ref),
                  ),
                if (esAdmin) ...[
                  AccionRapida(
                    icono: Icons.handshake_outlined,
                    titulo: 'Comisiones',
                    detalle: 'Por team',
                    color: VenueColors.info,
                    alTocar: () => hojaComisiones(context),
                  ),
                  AccionRapida(
                    icono: Icons.card_giftcard_outlined,
                    titulo: 'Bonos',
                    detalle: 'Premios extra',
                    color: VenueColors.aviso,
                    alTocar: () => hojaBonos(context),
                  ),
                  AccionRapida(
                    icono: Icons.leaderboard_outlined,
                    titulo: 'Histórico',
                    detalle: 'Y ranking',
                    color: const Color(0xFF7A5AF8),
                    alTocar: () => hojaHistorico(context),
                  ),
                  AccionRapida(
                    icono: Icons.phone_outlined,
                    titulo: 'Teléfonos',
                    detalle: 'Del equipo',
                    color: const Color(0xFF0BA5EC),
                    alTocar: () => hojaTelefonos(context),
                  ),
                  AccionRapida(
                    icono: Icons.filter_alt_outlined,
                    titulo: 'Filtro',
                    detalle: 'Reporte de puerta',
                    color: VenueColors.neutro,
                    alTocar: () => hojaReporteFiltro(context),
                  ),
                ],
                if (!esAdmin)
                  AccionRapida(
                    icono: Icons.history_rounded,
                    titulo: 'Eventos pasados',
                    detalle: 'Lo que hiciste antes',
                    color: VenueColors.info,
                    alTocar: () => hojaEventosPasados(context, perfil.id, perfil.nombre),
                  ),
              ]),
              if (esAdmin) ...[
                if (!ancho) ...[const SizedBox(height: 12), const _AjustesCierre()],
                const _Fases(),
                const SizedBox(height: 12),
                Tarjeta(
                  padding: EdgeInsets.zero,
                  child: ExpansionTile(
                    shape: const Border(),
                    collapsedShape: const Border(),
                    tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
                    iconColor: VenueColors.textoSuave,
                    collapsedIconColor: VenueColors.textoSuave,
                    title: const Text('Ver desglose por comisiones',
                        style: TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
                    childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
                    children: [
                      Text(
                        'Otra forma de leer la misma noche: el bruto menos lo que se lleva cada relacionador. Es un control interno — la cifra que se paga es la de arriba.',
                        style: TextStyle(color: VenueColors.textoSuave, fontSize: 12.5, height: 1.35),
                      ),
                      Renglon('Bruto entradas', '${c.entBruto} Bs'),
                      Renglon('Bruto mesas', '${c.mesasBruto} Bs'),
                      Renglon('Comisiones + bonos', '− ${c.comisionesTotal} Bs', color: VenueColors.mal),
                      Renglon('Neto por comisiones', '${c.neto} Bs', fuerte: true),
                    ],
                  ),
                ),
              ],
            ],
          );
        },
      ),
    );
  }
}

String _bs(num n) => '${n == n.roundToDouble() ? n.round() : n.toStringAsFixed(1)} Bs';

/// Cambia el evento de trabajo (el mismo de la barra de arriba).
Future<void> _elegirEvento(BuildContext context, WidgetRef ref, List<Evento> lista, Evento actual) async {
  final e = await showModalBottomSheet<String>(
    context: context,
    builder: (c) => SafeArea(
      child: ListView(
        shrinkWrap: true,
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        children: [
          const Padding(
            padding: EdgeInsets.only(left: 4, bottom: 8),
            child: Text('Evento', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
          ),
          for (final x in lista)
            ListTile(
              title: Text(x.nombre, style: const TextStyle(fontWeight: FontWeight.w500)),
              subtitle: Text(x.fechaCorta),
              trailing: x.id == actual.id ? const Icon(Icons.check_rounded) : null,
              onTap: () => Navigator.pop(c, x.id),
            ),
        ],
      ),
    ),
  );
  if (e != null) ref.read(eventoElegidoProvider.notifier).elegir(e);
}

/// Dona con lo facturado (entradas y mesas) y lo que se va en comisiones.
class _Composicion extends StatelessWidget {
  const _Composicion({required this.c});
  final Cierre c;

  @override
  Widget build(BuildContext context) {
    final marca = Theme.of(context).colorScheme.primary;
    final partes = [
      ('Entradas', c.entBruto, marca),
      ('Mesas', c.mesasBruto, VenueColors.info),
    ];
    final total = c.entBruto + c.mesasBruto;
    return Tarjeta(
      padding: const EdgeInsets.all(16),
      child: Row(children: [
        SizedBox(
          width: 128,
          height: 128,
          child: Stack(alignment: Alignment.center, children: [
            PieChart(PieChartData(
              sectionsSpace: 3,
              centerSpaceRadius: 44,
              startDegreeOffset: -90,
              sections: total <= 0
                  ? [PieChartSectionData(value: 1, color: VenueColors.superficie2, radius: 16, showTitle: false)]
                  : [
                      for (final (_, v, col) in partes)
                        if (v > 0)
                          PieChartSectionData(value: v.toDouble(), color: col, radius: 16, showTitle: false),
                    ],
            )),
            Column(mainAxisSize: MainAxisSize.min, children: [
              Text(_bs(total), style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
              Text('facturado', style: TextStyle(fontSize: 11.5, color: VenueColors.textoTenue)),
            ]),
          ]),
        ),
        const SizedBox(width: 18),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            for (final (n, v, col) in partes) _Leyenda(n, _bs(v), col, total <= 0 ? null : v / total),
            Divider(height: 18, color: VenueColors.lineaSuave),
            _Leyenda('Comisiones y bonos', '− ${_bs(c.comisionesTotal)}', VenueColors.mal, null),
          ]),
        ),
      ]),
    );
  }
}

class _Leyenda extends StatelessWidget {
  const _Leyenda(this.nombre, this.valor, this.color, this.parte);
  final String nombre;
  final String valor;
  final Color color;
  final num? parte;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(children: [
          Container(width: 10, height: 10, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
                parte == null ? nombre : '$nombre · ${(parte! * 100).round()}%',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 13, color: VenueColors.textoSuave)),
          ),
          Text(valor, style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600)),
        ]),
      );
}

/// Ranking como el "Top 5" de Fourvenues: puesto, persona, entradas que
/// ingresaron y lo que hay que pagarle. Tocar una persona abre su detalle.
class _TablaTop extends StatelessWidget {
  const _TablaTop({required this.personas, required this.equipo, required this.evento, this.limite});
  final List<StatsPersona> personas;
  final Map<String, Miembro> equipo;
  final Evento evento;
  final int? limite;

  @override
  Widget build(BuildContext context) {
    final orden = [...personas]
      ..sort((a, b) => (b.usadas + b.ingresaron + b.mesas).compareTo(a.usadas + a.ingresaron + a.mesas));
    final filas = limite == null ? orden : orden.take(limite!).toList();
    if (filas.isEmpty) {
      return Tarjeta(
        child: Text('Todavía nadie vendió en este evento.',
            textAlign: TextAlign.center, style: TextStyle(color: VenueColors.textoSuave)),
      );
    }
    const medallas = [Color(0xFFF5B400), Color(0xFF98A2B3), Color(0xFFCD7F32)];
    TextStyle cab = TextStyle(fontSize: 12.5, fontWeight: FontWeight.w500, color: VenueColors.textoTenue);
    return Tarjeta(
      padding: EdgeInsets.zero,
      child: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 10),
          child: Row(children: [
            SizedBox(width: 30, child: Text('#', style: cab)),
            Expanded(child: Text('Persona', style: cab)),
            SizedBox(width: 62, child: Text('Entraron', textAlign: TextAlign.right, style: cab)),
            SizedBox(width: 78, child: Text('A pagar', textAlign: TextAlign.right, style: cab)),
          ]),
        ),
        Divider(height: 1, color: VenueColors.lineaSuave),
        for (var i = 0; i < filas.length; i++) ...[
          if (i > 0) Divider(height: 1, indent: 16, color: VenueColors.lineaSuave),
          InkWell(
            onTap: () => abrirPersona(context, filas[i].id, filas[i].nombre, eventoId: evento.id),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
              child: Row(children: [
                SizedBox(
                  width: 30,
                  child: i < 3
                      ? Icon(Icons.emoji_events_rounded, size: 18, color: medallas[i])
                      : Text('${i + 1}', style: TextStyle(color: VenueColors.textoTenue)),
                ),
                Inicial(filas[i].nombre, lado: 32),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(filas[i].nombre,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w500)),
                    Text(
                      [
                        equipo[filas[i].id]?.team ?? '',
                        if (filas[i].mesas > 0) '${filas[i].mesas} mesas',
                      ].where((x) => x.isNotEmpty).join(' · '),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 12, color: VenueColors.textoTenue),
                    ),
                  ]),
                ),
                SizedBox(
                  width: 62,
                  child: Text('${filas[i].usadas + filas[i].ingresaron}',
                      textAlign: TextAlign.right,
                      style: const TextStyle(fontWeight: FontWeight.w600, fontFeatures: [FontFeature.tabularFigures()])),
                ),
                SizedBox(
                  width: 78,
                  child: Text(_bs(filas[i].aPagar),
                      textAlign: TextAlign.right,
                      style: const TextStyle(fontWeight: FontWeight.w600, fontFeatures: [FontFeature.tabularFigures()])),
                ),
              ]),
            ),
          ),
        ],
      ]),
    );
  }
}

/// Lo de cada team: sus números juntos y, al abrirlo, cada relacionador con
/// lo que vendió y lo que hay que pagarle.
class _PorTeam extends StatefulWidget {
  const _PorTeam({required this.personas, required this.equipo, required this.evento});
  final List<StatsPersona> personas;
  final Map<String, Miembro> equipo;
  final Evento evento;

  @override
  State<_PorTeam> createState() => _PorTeamState();
}

class _PorTeamState extends State<_PorTeam> {
  final _abiertos = <String>{};

  @override
  Widget build(BuildContext context) {
    final grupos = <String, List<StatsPersona>>{};
    final nombres = <String, String>{};
    for (final p in widget.personas) {
      final k = p.teamId ?? '';
      grupos.putIfAbsent(k, () => []).add(p);
    }
    // el nombre del team sale de cualquiera de sus miembros
    for (final m in widget.equipo.values) {
      if (m.teamId != null) nombres.putIfAbsent(m.teamId!, () => m.team);
    }
    num vendido(StatsPersona p) => p.brutoEntradas + p.brutoMesas;
    num suma(List<StatsPersona> l, num Function(StatsPersona) f) => l.fold<num>(0, (a, p) => a + f(p));
    final orden = grupos.entries.toList()
      ..sort((a, b) => suma(b.value, vendido).compareTo(suma(a.value, vendido)));
    if (orden.isEmpty) {
      return Tarjeta(
        child: Text('Todavía ningún team vendió en este evento.',
            textAlign: TextAlign.center, style: TextStyle(color: VenueColors.textoSuave)),
      );
    }
    final cifra = TextStyle(
        fontWeight: FontWeight.w600, fontFeatures: const [FontFeature.tabularFigures()]);
    final suave = TextStyle(fontSize: 12.5, color: VenueColors.textoSuave);

    return Column(children: [
      for (final g in orden) ...[
        Builder(builder: (context) {
          final l = [...g.value]..sort((a, b) => vendido(b).compareTo(vendido(a)));
          final nombre = g.key.isEmpty ? 'Sin team' : nombres[g.key] ?? 'Team';
          final abierto = _abiertos.contains(g.key);
          final entraron = suma(l, (p) => p.ingresaron + p.usadas).toInt();
          return Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Tarjeta(
              padding: EdgeInsets.zero,
              child: Column(children: [
                InkWell(
                  onTap: () => setState(() => abierto ? _abiertos.remove(g.key) : _abiertos.add(g.key)),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 14, 10, 14),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Row(children: [
                        Inicial(nombre, lado: 38),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text(nombre,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                            Text('${l.length} ${l.length == 1 ? 'relacionador' : 'relacionadores'}',
                                style: suave),
                          ]),
                        ),
                        Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                          Text(_bs(suma(l, vendido)), style: cifra.copyWith(fontSize: 16)),
                          Text('vendido', style: suave),
                        ]),
                        Icon(abierto ? Icons.expand_less_rounded : Icons.expand_more_rounded,
                            color: VenueColors.textoTenue),
                      ]),
                      const SizedBox(height: 12),
                      FilaFichas(children: [
                        _MiniDato('Entraron', '$entraron', VenueColors.ok),
                        _MiniDato('Listas',
                            '${suma(l, (p) => p.ingresaron).toInt()}/${suma(l, (p) => p.anotados).toInt()}',
                            VenueColors.aviso),
                        _MiniDato('QR', '${suma(l, (p) => p.usadas).toInt()}/${suma(l, (p) => p.vendidas).toInt()}',
                            Theme.of(context).colorScheme.primary),
                        _MiniDato('Mesas', '${suma(l, (p) => p.mesas).toInt()}', VenueColors.info),
                      ]),
                      const SizedBox(height: 10),
                      Text('A pagar al team: ${_bs(suma(l, (p) => p.aPagar))}', style: suave),
                    ]),
                  ),
                ),
                if (abierto) ...[
                  Divider(height: 1, color: VenueColors.lineaSuave),
                  for (var k = 0; k < l.length; k++) ...[
                    if (k > 0) Divider(height: 1, indent: 16, color: VenueColors.lineaSuave),
                    InkWell(
                      onTap: () => abrirPersona(context, l[k].id, l[k].nombre, eventoId: widget.evento.id),
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(16, 10, 12, 10),
                        child: Row(children: [
                          Inicial(l[k].nombre, lado: 32),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Text(l[k].nombre,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w500)),
                              Text(
                                [
                                  'lista ${l[k].ingresaron}/${l[k].anotados}',
                                  'QR ${l[k].usadas}/${l[k].vendidas}',
                                  if (l[k].mesas > 0) '${l[k].mesas} mesas',
                                ].join(' · '),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(fontSize: 12, color: VenueColors.textoTenue),
                              ),
                            ]),
                          ),
                          Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                            Text(_bs(vendido(l[k])), style: cifra),
                            Text('a pagar ${_bs(l[k].aPagar)}',
                                style: TextStyle(fontSize: 12, color: VenueColors.textoTenue)),
                          ]),
                        ]),
                      ),
                    ),
                  ],
                ],
              ]),
            ),
          );
        }),
      ],
    ]);
  }
}

/// Número chico teñido dentro de la tarjeta de un team.
class _MiniDato extends StatelessWidget {
  const _MiniDato(this.etiqueta, this.valor, this.color);
  final String etiqueta, valor;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
        decoration: BoxDecoration(
          color: color.withValues(alpha: .09),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(children: [
          Text(etiqueta,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: color)),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(valor,
                style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                    color: color,
                    fontFeatures: const [FontFeature.tabularFigures()])),
          ),
        ]),
      );
}

Future<void> _verTodos(BuildContext context, String titulo, List<StatsPersona> personas,
        Map<String, Miembro> equipo, Evento ev) =>
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => Scaffold(
        appBar: AppBar(title: Text(titulo)),
        body: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
          children: [_TablaTop(personas: personas, equipo: equipo, evento: ev)],
        ),
      ),
    ));

/// Indicador sin ícono para las pantallas que solo tienen el dato (Barra).
/// Mismo marco y tipografía que [Indicador].
class Kpi extends StatelessWidget {
  const Kpi(this.titulo, this.valor, this.sufijo, {super.key, this.color});
  final String titulo;
  final String valor;
  final String sufijo;
  final Color? color;

  @override
  Widget build(BuildContext context) => Tarjeta(
    padding: const EdgeInsets.all(16),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          titulo,
          style: TextStyle(
            color: VenueColors.textoSuave,
            fontSize: 13.5,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 4),
        Text.rich(
          TextSpan(
            children: [
              TextSpan(
                text: valor,
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.4,
                  color: color,
                ),
              ),
              TextSpan(
                text: sufijo,
                style: TextStyle(
                  color: VenueColors.textoTenue,
                  fontSize: 14,
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

class Renglon extends StatelessWidget {
  const Renglon(this.k, this.v, {super.key, this.color, this.fuerte = false});
  final String k;
  final String v;
  final Color? color;
  final bool fuerte;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 5),
    child: Row(
      children: [
        Expanded(
          child: Text(
            k,
            style: TextStyle(
              fontWeight: fuerte ? FontWeight.w800 : FontWeight.w500,
            ),
          ),
        ),
        Text(
          v,
          style: TextStyle(
            color: color,
            fontWeight: fuerte ? FontWeight.w800 : FontWeight.w600,
            fontSize: fuerte ? 17 : 14,
          ),
        ),
      ],
    ),
  );
}

/// Total a pagar al boliche, con los términos de los que sale.
class _Liquidacion extends ConsumerWidget {
  const _Liquidacion();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = ref.watch(liquidacionProvider).value;
    final c = ref.watch(cierreProvider).value;
    final ev = ref.watch(eventoActivoProvider);
    if (l == null || c == null || ev == null) {
      return const Tarjeta(child: SizedBox(height: 120));
    }
    final s = l.servidor;
    num n(String k) => s[k] as num? ?? 0;
    final liq = liquidacion(
      brutoPrepagadasIngresadas: c.entBruto,
      totalMesas: n('total_mesas'),
      puertaIngresaron: l.puerta.ingresaron,
      puertaPrecio: l.puerta.precio,
    );
    const pct = 50;
    final unit = c.entUsadas > 0 ? (c.entBruto / c.entUsadas).round() : 0;
    final cerrado = ev.estado == 'cerrado';
    final angosto = MediaQuery.sizeOf(context).width < 600;
    final estado = PillEstado(
      cerrado ? 'Cerrado' : 'Pendiente de cierre',
      tono: cerrado ? Tono.ok : Tono.aviso,
    );

    final subs = [
      _Sub(
        Icons.confirmation_number_outlined,
        'Prepagadas — $pct%',
        'Bs ${liq.prepagadas}',
        '${c.entUsadas} ingresaron${unit > 0 ? ' × $unit Bs' : ''} × $pct%',
      ),
      _Sub(
        Icons.weekend_outlined,
        'Mesas netas',
        'Bs ${liq.mesas}',
        '${n('bruto_mesas')} − ${n('comision_mesas')} comisiones',
      ),
      if (liq.puerta > 0)
        _Sub(
          Icons.shopping_bag_outlined,
          'Menos Compra en Puerta — $pct%',
          '−Bs ${liq.puerta}',
          '${l.puerta.ingresaron} ingresaron × ${l.puerta.precio} Bs × $pct%',
          negativo: true,
        ),
      _Sub(
        Icons.watch_outlined,
        'Manillas externas',
        '${n('manillas_externas')}',
        'No se reparten',
      ),
    ];

    return Tarjeta(
      padding: EdgeInsets.all(angosto ? 18 : 26),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (angosto) ...[
            Align(alignment: Alignment.centerLeft, child: estado),
            const SizedBox(height: 14),
          ],
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Total a pagar al boliche',
                      style: TextStyle(
                        fontSize: angosto ? 14.5 : 17,
                        color: VenueColors.textoSuave,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Text(
                        'Bs ${liq.total}',
                        style: TextStyle(
                          fontSize: angosto ? 36 : 48,
                          height: 1.1,
                          fontWeight: FontWeight.w700,
                          letterSpacing: -1.2,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              if (!angosto) estado,
            ],
          ),
          Padding(
            padding: const EdgeInsets.only(top: 18, bottom: 4),
            child: Divider(height: 1, color: VenueColors.linea),
          ),
          for (var i = 0; i < subs.length; i++) ...[
            if (i > 0) Divider(height: 1, color: VenueColors.lineaSuave),
            subs[i],
          ],
          if (l.puerta.nombre != null &&
              l.puerta.ingresaron > 0 &&
              l.puerta.precio <= 0) ...[
            const SizedBox(height: 12),
            Text(
              '${l.puerta.ingresaron} persona(s) de ${l.puerta.nombre} ingresaron, pero esa lista todavía no tiene precio cargado, así que no se descuenta nada.',
              style: TextStyle(
                color: VenueColors.aviso,
                fontSize: 12.5,
                height: 1.35,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _Sub extends StatelessWidget {
  const _Sub(this.icono, this.k, this.v, this.d, {this.negativo = false});
  final IconData icono;
  final String k;
  final String v;
  final String d;
  final bool negativo;

  // Renglón del desglose: concepto y detalle a la izquierda, monto a la
  // derecha (como "Target / Forecast" en Fourvenues).
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 12),
    child: Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(k, style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w500)),
              const SizedBox(height: 2),
              Text(d, style: TextStyle(fontSize: 12.5, color: VenueColors.textoTenue)),
            ],
          ),
        ),
        const SizedBox(width: 12),
        Text(
          v,
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: negativo ? VenueColors.mal : null,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
      ],
    ),
  );
}

/// Manillas de externos: lo único editable del cierre.
class _AjustesCierre extends ConsumerStatefulWidget {
  const _AjustesCierre();

  @override
  ConsumerState<_AjustesCierre> createState() => _AjustesCierreState();
}

class _AjustesCierreState extends ConsumerState<_AjustesCierre> {
  final _ext = TextEditingController();
  bool _puesto = false;

  @override
  void dispose() {
    _ext.dispose();
    super.dispose();
  }

  void _paso(int d) {
    final v = (int.tryParse(_ext.text) ?? 0) + d;
    _ext.text = '${v < 0 ? 0 : v}';
  }

  @override
  Widget build(BuildContext context) {
    final l = ref.watch(liquidacionProvider).value;
    final ev = ref.watch(eventoActivoProvider);
    if (l == null || ev == null) {
      return const Tarjeta(child: SizedBox(height: 120));
    }
    num n(String k) => l.servidor[k] as num? ?? 0;
    if (!_puesto) {
      _ext.text = '${n('manillas_externas')}';
      _puesto = true;
    }
    return Tarjeta(
      padding: const EdgeInsets.all(22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Row(
            children: [
              IconoRecuadro(Icons.settings_outlined, lado: 42),
              SizedBox(width: 14),
              Text(
                'Ajustes del cierre',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
              ),
            ],
          ),
          const SizedBox(height: 18),
          Text(
            'Manillas de externos (no se reparten)',
            style: TextStyle(fontSize: 14, color: VenueColors.textoSuave),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _ext,
            keyboardType: TextInputType.number,
            style: const TextStyle(fontSize: 17),
            decoration: InputDecoration(
              // altura fija: el sufijo recibe alto sin límite y los Expanded
              // de las flechas no tendrían de dónde repartir
              suffixIcon: Container(
                width: 46,
                height: 54,
                decoration: BoxDecoration(
                  border: Border(left: BorderSide(color: VenueColors.linea)),
                ),
                child: Column(
                  children: [
                    Expanded(
                      child: InkWell(
                        onTap: () => _paso(1),
                        child: const Center(
                          child: Icon(
                            Icons.keyboard_arrow_up_rounded,
                            size: 20,
                          ),
                        ),
                      ),
                    ),
                    Divider(height: 1, color: VenueColors.linea),
                    Expanded(
                      child: InkWell(
                        onTap: () => _paso(-1),
                        child: const Center(
                          child: Icon(
                            Icons.keyboard_arrow_down_rounded,
                            size: 20,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'De las ${n('manillas_usadas')} que ingresaron se descuentan ${n('manillas_externas')}. Es otra cosa que Compra en Puerta: acá se sacan manillas del reparto. Queda guardado en el evento.',
            style: TextStyle(
              color: VenueColors.textoTenue,
              fontSize: 13,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 16),
          Align(
            alignment: Alignment.centerRight,
            child: OutlinedButton(
              style: OutlinedButton.styleFrom(minimumSize: const Size(120, 48)),
              onPressed: () async {
                try {
                  await ref
                      .read(reporteRepositoryProvider)
                      .manillasExternas(ev.id, int.tryParse(_ext.text) ?? 0);
                  ref.invalidate(liquidacionProvider);
                  if (context.mounted) {
                    avisar(context, 'Manillas de externos actualizadas');
                  }
                } catch (e) {
                  if (context.mounted) {
                    avisar(context, mensajeDeError(e), tipo: TipoAviso.aviso);
                  }
                }
              },
              child: const Text('Aplicar'),
            ),
          ),
        ],
      ),
    );
  }
}

final _fasesReporteProvider = FutureProvider.autoDispose<Map<String, dynamic>?>(
  (ref) async {
    final ev = ref.watch(eventoActivoProvider);
    if (ev == null) return null;
    return ref.watch(reporteRepositoryProvider).fases(ev.id);
  },
);

/// Cómo se movió cada fase de preventa: vendido e INGRESADO por separado.
class _Fases extends ConsumerWidget {
  const _Fases();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final r = ref.watch(_fasesReporteProvider).value;
    if (r == null || r['usa_fases'] != true) return const SizedBox.shrink();
    final fases = ((r['fases'] as List?) ?? const [])
        .map((x) => Map<String, dynamic>.from(x as Map))
        .toList();
    return Padding(
      padding: const EdgeInsets.only(top: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Fases de preventa · ${r['bruto_total']} Bs',
            style: const TextStyle(fontWeight: FontWeight.w800),
          ),
          for (final f in [
            ...fases,
            if (r['sin_fase'] is Map)
              {
                'nombre': 'Sin fase',
                ...Map<String, dynamic>.from(r['sin_fase'] as Map),
              },
          ])
            if ((f['vendidas'] as num? ?? 0) > 0 || f['nombre'] != 'Sin fase')
              Renglon(
                '${f['nombre']}',
                '${f['vendidas'] ?? 0} vendidas · ${f['ingresaron'] ?? 0} ingresaron · ${f['bruto'] ?? 0} Bs',
              ),
        ],
      ),
    );
  }
}
