import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/networking/supabase.dart';
import '../../../core/theme/venue_theme.dart';
import '../../../core/widgets/avisos.dart';
import '../../../core/widgets/patron.dart';
import '../../access_control/ui/accesos_screen.dart';
import '../../analytics/ui/reporte_screen.dart';
import '../../authentication/data/sesion.dart';
import '../../clubs/data/clubs.dart';
import '../../dashboard/ui/panel_perfil.dart';
import '../../events/data/eventos.dart';
import '../../payments/ui/pagos_screen.dart';
import '../../teams/ui/gente_screen.dart';
import '../../vip_tables/ui/mesas_screen.dart';
import '../data/rrpp.dart';
import 'gestion_solicitudes.dart';

const _aftr = 'https://aftr-web.vercel.app/';

String _miles(num v) {
  final s = v.round().abs().toString();
  final b = StringBuffer(v < 0 ? '-' : '');
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) b.write('.');
    b.write(s[i]);
  }
  return b.toString();
}

String _bs(num v) => 'Bs ${_miles(v)}';
const _meses = ['ene', 'feb', 'mar', 'abr', 'may', 'jun', 'jul', 'ago', 'sep', 'oct', 'nov', 'dic'];
const _dias = ['lun', 'mar', 'mié', 'jue', 'vie', 'sáb', 'dom'];
String _fecha(DateTime d) => '${_dias[d.weekday - 1]} ${d.day} ${_meses[d.month - 1]}';
String _mesCorto(DateTime d) => "${_meses[d.month - 1]} ${'${d.year}'.substring(2)}";

/// Espacio personal del relacionador: cinco secciones de todos sus
/// boliches. Las herramientas de cada boliche (listas, entradas, mesas,
/// pagos, team) se abren desde un evento o desde Perfil.
class RrppShell extends ConsumerStatefulWidget {
  const RrppShell({super.key});
  @override
  ConsumerState<RrppShell> createState() => _RrppShellState();
}

class _RrppShellState extends ConsumerState<RrppShell> {
  int _i = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _revisarEnlace());
  }

  /// Si llegó por un enlace, lo primero es mandar la solicitud.
  void _revisarEnlace() {
    final code = ref.read(unirsePendienteProvider);
    if (code != null && mounted) abrirUnirse(context, ref, code);
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(unirsePendienteProvider, (_, code) {
      if (code != null) abrirUnirse(context, ref, code);
    });
    // las herramientas necesitan un boliche activo: el primero de los suyos
    ref.listen(clubsProvider, (_, l) {
      final lista = l.value ?? const <Club>[];
      final activo = ref.read(clubActivoIdProvider);
      if (lista.isNotEmpty && (activo == null || !lista.any((c) => c.id == activo))) {
        ref.read(clubActivoIdProvider.notifier).elegir(lista.first.id);
      } else if (lista.isEmpty && activo != null) {
        ref.read(clubActivoIdProvider.notifier).elegir(null);
      }
    });
    const destinos = [
      (Icons.home_outlined, Icons.home_rounded, 'Inicio'),
      (Icons.event_outlined, Icons.event_rounded, 'Eventos'),
      (Icons.bar_chart_outlined, Icons.bar_chart_rounded, 'Estadísticas'),
      (Icons.account_balance_wallet_outlined, Icons.account_balance_wallet_rounded, 'Ganancias'),
      (Icons.person_outline_rounded, Icons.person_rounded, 'Perfil'),
    ];
    const paginas = [_Inicio(), _Eventos(), _Stats(), _Ganancias(), _Perfil()];
    final ancho = MediaQuery.sizeOf(context).width >= 900;
    final cuerpo = SafeArea(
      bottom: false,
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 880),
          child: IndexedStack(index: _i, children: paginas),
        ),
      ),
    );
    return Scaffold(
      backgroundColor: VenueColors.fondo,
      body: ancho
          ? Row(children: [
              NavigationRail(
                selectedIndex: _i,
                onDestinationSelected: (i) => setState(() => _i = i),
                labelType: NavigationRailLabelType.all,
                destinations: [
                  for (final d in destinos)
                    NavigationRailDestination(icon: Icon(d.$1), selectedIcon: Icon(d.$2), label: Text(d.$3)),
                ],
              ),
              Expanded(child: cuerpo),
            ])
          : cuerpo,
      bottomNavigationBar: ancho
          ? null
          : NavigationBar(
              selectedIndex: _i,
              onDestinationSelected: (i) => setState(() => _i = i),
              destinations: [
                for (final d in destinos)
                  NavigationDestination(icon: Icon(d.$1), selectedIcon: Icon(d.$2), label: d.$3),
              ],
            ),
    );
  }
}

// ── piezas comunes ──────────────────────────────────────────────────────

Future<void> _refrescar(WidgetRef ref) async {
  refrescarRrpp(ref);
  ref.invalidate(clubsProvider);
  await ref.read(rrppEventosProvider.future).catchError((_) => const <EventoRrpp>[]);
}

/// Página con encabezado y pull-to-refresh; espera los eventos.
class _Pagina extends ConsumerWidget {
  const _Pagina({required this.titulo, required this.hijos, this.saludo});
  final String titulo;
  final String? saludo;
  final List<Widget> Function(List<EventoRrpp> eventos) hijos;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ev = ref.watch(rrppEventosProvider);
    return RefreshIndicator(
      onRefresh: () => _refrescar(ref),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
        children: [
          if (saludo != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text(saludo!, style: TextStyle(color: VenueColors.textoSuave, fontSize: 15)),
            ),
          Text(titulo, style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w700, letterSpacing: -.5)),
          const SizedBox(height: 12),
          ...ev.when(
            data: hijos,
            loading: () => const [Padding(padding: EdgeInsets.all(40), child: Center(child: CircularProgressIndicator()))],
            error: (e, _) => [
              _Vacio.accion('No pudimos cargar tus datos', mensajeDeError(e),
                  accion: OutlinedButton(onPressed: () => _refrescar(ref), child: const Text('Reintentar'))),
            ],
          ),
        ],
      ),
    );
  }
}

class _Filtros extends ConsumerWidget {
  const _Filtros({this.periodo = true});
  final bool periodo;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = ref.watch(periodoProvider);
    final club = ref.watch(filtroClubProvider);
    final boliches = ref.watch(misBolichesProvider).value ?? const <BolicheMio>[];
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        if (periodo)
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: SegmentedButton<Periodo>(
              showSelectedIcon: false,
              segments: [for (final x in Periodo.values) ButtonSegment(value: x, label: Text(x.corto))],
              selected: {p},
              onSelectionChanged: (s) => ref.read(periodoProvider.notifier).poner(s.first),
            ),
          ),
        if (boliches.length > 1) ...[
          const SizedBox(height: 10),
          DropdownButtonFormField<String?>(
            initialValue: club,
            isDense: true,
            decoration: const InputDecoration(isDense: true),
            items: [
              const DropdownMenuItem(value: null, child: Text('Todos los boliches')),
              for (final b in boliches) DropdownMenuItem(value: b.id, child: Text(b.nombre)),
            ],
            onChanged: (v) => ref.read(filtroClubProvider.notifier).poner(v),
          ),
        ],
      ]),
    );
  }
}

class _Cifra extends StatelessWidget {
  const _Cifra(this.etiqueta, this.valor, {this.detalle, this.color});
  final String etiqueta, valor;
  final String? detalle;
  final Color? color;
  @override
  Widget build(BuildContext context) => Tarjeta(
        padding: const EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(etiqueta, style: TextStyle(fontSize: 13, color: VenueColors.textoSuave)),
          const SizedBox(height: 4),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(valor,
                style: TextStyle(
                    fontSize: 21, fontWeight: FontWeight.w700, color: color, fontFeatures: const [FontFeature.tabularFigures()])),
          ),
          if (detalle != null)
            Text(detalle!, maxLines: 2, style: TextStyle(fontSize: 12, color: VenueColors.textoTenue, height: 1.3)),
        ]),
      );
}

Widget _grilla(List<Widget> cifras) => LayoutBuilder(builder: (context, c) {
      final cols = c.maxWidth >= 640 ? 4 : 2;
      final w = (c.maxWidth - 10 * (cols - 1)) / cols;
      return Wrap(spacing: 10, runSpacing: 10, children: [for (final x in cifras) SizedBox(width: w, child: x)]);
    });

class _Vacio extends StatelessWidget {
  const _Vacio(this.titulo, [this.detalle]) : accion = null;
  final String titulo;
  final String? detalle;
  final Widget? accion;
  const _Vacio.accion(this.titulo, this.detalle, {required this.accion});
  @override
  Widget build(BuildContext context) => Tarjeta(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 22),
        child: Column(children: [
          Text(titulo, textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
          if (detalle != null) ...[
            const SizedBox(height: 6),
            Text(detalle!, textAlign: TextAlign.center, style: TextStyle(color: VenueColors.textoSuave, height: 1.4)),
          ],
          if (accion != null) ...[const SizedBox(height: 12), accion!],
        ]),
      );
}

class _Estado extends StatelessWidget {
  const _Estado(this.estado);
  final String estado;
  @override
  Widget build(BuildContext context) {
    final (t, c) = switch (estado) {
      'pagada' => ('Pagada', VenueColors.ok),
      'confirmada' => ('Por cobrar', VenueColors.aviso),
      _ => ('Estimada', VenueColors.textoTenue),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(color: c.withValues(alpha: .12), borderRadius: BorderRadius.circular(99)),
      child: Text(t, style: TextStyle(color: c, fontSize: 11.5, fontWeight: FontWeight.w600)),
    );
  }
}

Widget _dia(DateTime f) => Container(
      width: 44,
      height: 48,
      decoration: BoxDecoration(color: VenueColors.superficie2, borderRadius: BorderRadius.circular(12)),
      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        Text('${f.day}', style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700, height: 1)),
        Text(_meses[f.month - 1].toUpperCase(), style: TextStyle(fontSize: 10.5, color: VenueColors.textoSuave)),
      ]),
    );

Widget _fila({required Widget inicio, required String titulo, required String sub, Widget? fin, VoidCallback? alTocar}) =>
    InkWell(
      onTap: alTocar,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(children: [
          inicio,
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(titulo, maxLines: 1, overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
              const SizedBox(height: 2),
              Text(sub, maxLines: 1, overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 12.5, color: VenueColors.textoSuave)),
            ]),
          ),
          if (fin != null) ...[const SizedBox(width: 8), fin],
        ]),
      ),
    );

Widget _lista(List<Widget> filas) => Tarjeta(
      padding: EdgeInsets.zero,
      child: Column(children: [
        for (var i = 0; i < filas.length; i++) ...[
          if (i > 0) Divider(height: 1, color: VenueColors.lineaSuave),
          filas[i],
        ],
      ]),
    );

Widget _logo(String nombre, String? url) => ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: Container(
        width: 40,
        height: 40,
        color: VenueColors.superficie2,
        alignment: Alignment.center,
        child: url != null
            ? Image.network(url, fit: BoxFit.cover, width: 40, height: 40,
                errorBuilder: (_, _, _) => Text(nombre.isEmpty ? '?' : nombre[0]))
            : Text(nombre.isEmpty ? '?' : nombre[0], style: const TextStyle(fontWeight: FontWeight.w700)),
      ),
    );

Widget _filaProximo(BuildContext context, WidgetRef ref, Proximo e) => _fila(
      inicio: _dia(e.fecha),
      titulo: e.evento,
      sub: '${e.club}${e.hora != null ? ' · ${e.hora}' : ''}',
      fin: Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
        Text(_miles(e.anotados), style: const TextStyle(fontWeight: FontWeight.w700)),
        Text('anotados', style: TextStyle(fontSize: 11.5, color: VenueColors.textoTenue)),
      ]),
      alTocar: () => _abrirProximo(context, ref, e),
    );

Widget _filaPasado(BuildContext context, EventoRrpp e, {String? sub}) => _fila(
      inicio: _dia(e.fecha),
      titulo: e.evento,
      sub: sub ?? '${e.club} · ${_miles(e.entraron)} entraron${e.mesasConfirmadas > 0 ? ' · ${e.mesasConfirmadas} mesas' : ''}',
      fin: Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
        Text(_bs(e.comisionTotal), style: const TextStyle(fontWeight: FontWeight.w700)),
        const SizedBox(height: 4),
        _Estado(e.estadoComision),
      ]),
      alTocar: () => _abrirPasado(context, e),
    );

/// Barras por mes (fl_chart). Sin datos, un vacío prolijo.
class _Barras extends StatelessWidget {
  const _Barras(this.puntos, {this.plata = false});
  final List<({DateTime mes, num valor})> puntos;
  final bool plata;
  @override
  Widget build(BuildContext context) {
    if (puntos.every((p) => p.valor == 0)) {
      return const _Vacio('Sin datos en este período');
    }
    final color = Theme.of(context).colorScheme.primary;
    final max = puntos.map((p) => p.valor).reduce((a, b) => a > b ? a : b).toDouble();
    return Tarjeta(
      padding: const EdgeInsets.fromLTRB(8, 18, 8, 8),
      child: SizedBox(
        height: 190,
        child: BarChart(BarChartData(
          maxY: max * 1.2,
          gridData: const FlGridData(show: false),
          borderData: FlBorderData(show: false),
          titlesData: FlTitlesData(
            leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 24,
                getTitlesWidget: (v, _) => Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(_mesCorto(puntos[v.toInt()].mes),
                      style: TextStyle(fontSize: 11, color: VenueColors.textoSuave)),
                ),
              ),
            ),
          ),
          barTouchData: BarTouchData(
            touchTooltipData: BarTouchTooltipData(
              getTooltipItem: (g, _, r, _) => BarTooltipItem(plata ? _bs(r.toY) : _miles(r.toY),
                  const TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
            ),
          ),
          barGroups: [
            for (var i = 0; i < puntos.length; i++)
              BarChartGroupData(x: i, barRods: [
                BarChartRodData(
                  toY: puntos[i].valor.toDouble(),
                  width: 22,
                  color: i == puntos.length - 1 ? color : color.withValues(alpha: .35),
                  borderRadius: BorderRadius.circular(5),
                ),
              ]),
          ],
        )),
      ),
    );
  }
}

// ── INICIO ──────────────────────────────────────────────────────────────

class _Inicio extends ConsumerWidget {
  const _Inicio();
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final perfil = ref.watch(perfilProvider).value;
    final per = ref.watch(periodoProvider);
    final club = ref.watch(filtroClubProvider);
    final boliches = ref.watch(misBolichesProvider).value ?? const <BolicheMio>[];
    final sols = ref.watch(misSolicitudesProvider).value ?? const <SolicitudMia>[];
    final prox = ref.watch(rrppProximosProvider).value ?? const <Proximo>[];
    final pend = sols.where((s) => s.pendiente).toList();
    final activos = boliches.where((b) => b.activo).toList();
    return _Pagina(
      saludo: 'Hola, ${perfil?.primerNombre ?? ''}',
      titulo: 'Inicio',
      hijos: (todos) {
        final t = Totales.de(delPeriodo(todos, per, club));
        final rs = records(todos);
        final noche = rs.where((r) => r.titulo.startsWith('Asistentes')).firstOrNull;
        final ult = todos.firstOrNull;
        return [
          if (activos.isEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: _Vacio.accion(
                pend.isNotEmpty ? 'Tu solicitud está en camino' : 'Sumate a tu primer boliche',
                pend.isNotEmpty
                    ? 'Esperando que ${pend.map((s) => s.club).join(', ')} te apruebe. Mientras tanto podés pedir sumarte a otros.'
                    : 'Buscá el boliche con el que trabajás y pedí sumarte, o pegá el enlace que te pasaron.',
                accion: Wrap(spacing: 8, runSpacing: 8, alignment: WrapAlignment.center, children: [
                  FilledButton(onPressed: () => abrirExplorar(context, ref), child: const Text('Explorar boliches')),
                  OutlinedButton(onPressed: () => abrirCodigo(context, ref), child: const Text('Tengo un enlace')),
                ]),
              ),
            ),
          const _Filtros(),
          Text('Ganaste en ${per.largo}', style: TextStyle(color: VenueColors.textoSuave, fontSize: 13.5)),
          Text(_bs(t.comision),
              style: const TextStyle(fontSize: 44, fontWeight: FontWeight.w700, letterSpacing: -1.2, height: 1.15)),
          Text('${t.eventos} ${t.eventos == 1 ? 'evento' : 'eventos'}',
              style: TextStyle(color: VenueColors.textoSuave)),
          const SizedBox(height: 16),
          _grilla([
            _Cifra('Por cobrar', _bs(t.pendiente), detalle: 'estimado + confirmado', color: t.pendiente > 0 ? VenueColors.aviso : null),
            _Cifra('Cobrado', _bs(t.pagado), detalle: 'marcado como pagado', color: VenueColors.ok),
            _Cifra('Entraron', _miles(t.entraron), detalle: '${_miles(t.ingresaron)} de lista · ${_miles(t.manillas)} con QR'),
            _Cifra('Mesas', _miles(t.mesas), detalle: 'confirmadas'),
          ]),
          if (pend.isNotEmpty && activos.isNotEmpty) ...[
            const SizedBox(height: 12),
            Tarjeta(
              color: VenueColors.aviso.withValues(alpha: .12),
              child: Text(pend.length == 1 ? '1 solicitud pendiente' : '${pend.length} solicitudes pendientes',
                  style: TextStyle(color: VenueColors.aviso, fontWeight: FontWeight.w600)),
            ),
          ],
          const TituloBloque('Próximos eventos'),
          if (prox.isEmpty)
            _Vacio('No tenés eventos próximos', activos.isEmpty ? null : 'Cuando tus boliches creen uno, aparece acá.')
          else
            _lista([for (final e in prox.take(3)) _filaProximo(context, ref, e)]),
          if (noche != null) ...[
            const TituloBloque('Tu mejor noche'),
            Tarjeta(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('${_miles(noche.valor)} personas',
                    style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w700)),
                Text('${noche.evento!.evento} · ${noche.evento!.club} · ${_fecha(noche.evento!.fecha)}',
                    style: TextStyle(color: VenueColors.textoSuave, fontSize: 12.5)),
                const SizedBox(height: 8),
                Text(
                  ult != null && ult.eventoId != noche.evento!.eventoId
                      ? 'Te faltan ${_miles(noche.valor - ult.entraron + 1)} para superarla.'
                      : 'Es tu último evento: estás en tu mejor momento.',
                  style: TextStyle(color: VenueColors.textoSuave),
                ),
              ]),
            ),
          ],
        ];
      },
    );
  }
}

// ── EVENTOS ─────────────────────────────────────────────────────────────

class _Eventos extends ConsumerStatefulWidget {
  const _Eventos();
  @override
  ConsumerState<_Eventos> createState() => _EventosState();
}

class _EventosState extends ConsumerState<_Eventos> {
  bool _proximos = true;
  @override
  Widget build(BuildContext context) {
    final club = ref.watch(filtroClubProvider);
    final prox = (ref.watch(rrppProximosProvider).value ?? const <Proximo>[])
        .where((e) => club == null || e.clubId == club)
        .toList();
    return _Pagina(
      titulo: 'Eventos',
      hijos: (todos) {
        final pasados = delPeriodo(todos, Periodo.todo, club);
        return [
          SegmentedButton<bool>(
            showSelectedIcon: false,
            segments: const [ButtonSegment(value: true, label: Text('Próximos')), ButtonSegment(value: false, label: Text('Trabajados'))],
            selected: {_proximos},
            onSelectionChanged: (s) => setState(() => _proximos = s.first),
          ),
          const SizedBox(height: 12),
          const _Filtros(periodo: false),
          if (_proximos)
            prox.isEmpty
                ? const _Vacio('No hay eventos próximos', 'Los eventos de tus boliches aparecen acá apenas se crean.')
                : _lista([for (final e in prox) _filaProximo(context, ref, e)])
          else
            pasados.isEmpty
                ? const _Vacio('Todavía no trabajaste ningún evento', 'Cuando anotes invitados o vendas, tu historial se arma solo.')
                : _lista([for (final e in pasados) _filaPasado(context, e)]),
        ];
      },
    );
  }
}

Future<void> _hoja(BuildContext context, Widget Function(BuildContext) hijo) => showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      useSafeArea: true,
      backgroundColor: VenueColors.superficie,
      builder: (c) => ListView(shrinkWrap: true, padding: const EdgeInsets.fromLTRB(16, 0, 16, 28), children: [hijo(c)]),
    );

Widget _tituloHoja(String t, String sub) => Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(t, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700)),
        Text(sub, style: TextStyle(color: VenueColors.textoSuave)),
      ]),
    );

String? _miRef;
Future<String> _linkVenta(WidgetRef ref, Proximo e) async {
  _miRef ??= await ref.read(rrppRepositoryProvider).miRef();
  return '$_aftr?r=$_miRef#/evento/${e.eventoId}';
}

void _abrirProximo(BuildContext context, WidgetRef ref, Proximo e) => _hoja(
      context,
      (c) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        _tituloHoja(e.evento, '${e.club} · ${_fecha(e.fecha)}${e.hora != null ? ' · ${e.hora}' : ''}'),
        _grilla([
          _Cifra('Anotados', _miles(e.anotados), detalle: e.cupoTotal != null ? 'de ${e.cupoTotal} de cupo' : 'en tus listas'),
          _Cifra('Entradas QR', _miles(e.entradasVendidas), detalle: 'vendidas'),
          _Cifra('Mesas', _miles(e.mesas), detalle: 'a tu nombre'),
          _Cifra('Por manilla', e.porManilla > 0 ? _bs(e.porManilla) : '—', detalle: 'comisión estimada'),
        ]),
        if (e.porManilla > 0 && e.entradasVendidas > 0)
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Text(
                'Si entran todas tus entradas, serían unos ${_bs(e.porManilla * e.entradasVendidas)} por manillas (sin contar mesas ni bonos).',
                style: TextStyle(color: VenueColors.textoSuave, height: 1.4)),
          ),
        const TituloBloque('Vender'),
        if (e.aftrPublico) ...[
          Row(children: [
            Expanded(
              child: FilledButton(
                onPressed: () async {
                  final url = await _linkVenta(ref, e);
                  await SharePlus.instance.share(ShareParams(text: '${e.evento} en ${e.club}, ${_fecha(e.fecha)}. Sacá tu entrada acá: $url'));
                },
                child: const Text('Compartir'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: OutlinedButton(
                onPressed: () async {
                  await Clipboard.setData(ClipboardData(text: await _linkVenta(ref, e)));
                  if (c.mounted) avisar(c, 'Enlace copiado');
                },
                child: const Text('Copiar mi enlace'),
              ),
            ),
          ]),
          const SizedBox(height: 6),
          Text('El enlace lleva tu código: cada visita y compra que llega por él queda a tu nombre.',
              style: TextStyle(color: VenueColors.textoTenue, fontSize: 12.5)),
        ] else
          Text('Este evento no está a la venta en AFTR, así que no tiene enlace público.',
              style: TextStyle(color: VenueColors.textoSuave)),
        const TituloBloque('Herramientas'),
        _lista([
          _fila(inicio: const Icon(Icons.how_to_reg_outlined), titulo: 'Listas y entradas', sub: 'Anotá invitados y vendé QR',
              fin: const Icon(Icons.chevron_right_rounded),
              alTocar: () => abrirHerramienta(c, ref, 'Listas y entradas', const AccesosScreen(), club: e.clubId, evento: e.eventoId)),
          _fila(inicio: const Icon(Icons.table_bar_outlined), titulo: 'Mesas y reservas', sub: 'El plano del boliche',
              fin: const Icon(Icons.chevron_right_rounded),
              alTocar: () => abrirHerramienta(c, ref, 'Mesas', const MesasScreen(), club: e.clubId, evento: e.eventoId)),
        ]),
      ]),
    );

/// Abre una herramienta de siempre con el boliche y el evento ya elegidos.
void abrirHerramienta(BuildContext context, WidgetRef ref, String titulo, Widget pantalla, {String? club, String? evento}) {
  if (club != null && ref.read(clubActivoIdProvider) != club) ref.read(clubActivoIdProvider.notifier).elegir(club);
  if (evento != null) ref.read(eventoElegidoProvider.notifier).elegir(evento);
  final nav = Navigator.of(context, rootNavigator: true);
  if (Navigator.of(context).canPop() && ModalRoute.of(context) is ModalBottomSheetRoute) Navigator.of(context).pop();
  nav.push(MaterialPageRoute<void>(
    builder: (_) => Scaffold(
      backgroundColor: VenueColors.fondo,
      appBar: AppBar(title: Text(titulo)),
      body: pantalla,
    ),
  ));
}

void _abrirPasado(BuildContext context, EventoRrpp e) {
  final filas = [
    if (e.comisionEntradas > 0)
      ('Entradas${e.porManilla > 0 ? ' (${_bs(e.porManilla)} c/u)' : ''}', e.comisionEntradas),
    if (e.comisionMesas > 0) ('Mesas', e.comisionMesas),
    if (e.comisionJefe > 0) ('Comisión de jefe (tu team)', e.comisionJefe),
    if (e.bono > 0) ('Bonos', e.bono),
  ];
  _hoja(
    context,
    (c) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      _tituloHoja(e.evento, '${e.club} · ${_fecha(e.fecha)}'),
      _grilla([
        _Cifra('Entraron', _miles(e.entraron), detalle: '${e.ingresaron}/${e.anotados} de lista · ${e.entradasUsadas} QR'),
        _Cifra('Entradas', _miles(e.entradasVendidas), detalle: '${e.entradasUsadas} usadas'),
        _Cifra('Mesas', _miles(e.mesasConfirmadas), detalle: e.mesasReservadas > 0 ? '${e.mesasReservadas} reservadas' : 'confirmadas'),
        _Cifra('Ventas', _bs(e.ventas), detalle: 'para el boliche'),
      ]),
      TituloBloque('Tu comisión', accion: _Estado(e.estadoComision)),
      Tarjeta(
        child: Column(children: [
          for (final (k, v) in filas)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Row(children: [Expanded(child: Text(k)), Text(_bs(v), style: const TextStyle(fontWeight: FontWeight.w600))]),
            ),
          if (filas.isEmpty) const Text('Sin comisión en este evento'),
          Divider(color: VenueColors.lineaSuave),
          Row(children: [
            const Expanded(child: Text('Total', style: TextStyle(fontWeight: FontWeight.w600))),
            Text(_bs(e.comisionTotal), style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 17)),
          ]),
        ]),
      ),
      const SizedBox(height: 10),
      Text(
        switch (e.estadoComision) {
          'pagada' => 'Marcada como pagada.',
          'confirmada' => 'El evento cerró: es lo que te corresponde. Figura como pagada cuando el boliche o tu jefe lo marquen.',
          _ => 'El evento sigue abierto: el número puede cambiar hasta el cierre.',
        },
        style: TextStyle(color: VenueColors.textoSuave, height: 1.4),
      ),
    ]),
  );
}

// ── ESTADÍSTICAS ────────────────────────────────────────────────────────

final _serieProvider = NotifierProvider<_Serie, int>(_Serie.new);

class _Serie extends Notifier<int> {
  @override
  int build() => 0;
  void poner(int v) => state = v;
}

final _series = <(String, num Function(EventoRrpp), bool)>[
  ('Comisión', (e) => e.comisionTotal, true),
  ('Entradas', (e) => e.entradasVendidas, false),
  ('Manillas', (e) => e.entradasUsadas, false),
  ('Mesas', (e) => e.mesasConfirmadas, false),
  ('Asistentes', (e) => e.entraron, false),
];

class _Stats extends ConsumerWidget {
  const _Stats();
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final per = ref.watch(periodoProvider);
    final club = ref.watch(filtroClubProvider);
    final serie = ref.watch(_serieProvider);
    return _Pagina(
      titulo: 'Estadísticas',
      hijos: (todos) {
        final l = delPeriodo(todos, per, club);
        final t = Totales.de(l), tt = Totales.de(todos);
        final rs = records(todos);
        final porClub = <String, (String, num, int)>{};
        for (final e in l) {
          final o = porClub[e.clubId] ?? (e.club, 0, 0);
          porClub[e.clubId] = (o.$1, o.$2 + e.comisionTotal, o.$3 + 1);
        }
        final clubs = porClub.values.toList()..sort((a, b) => b.$2.compareTo(a.$2));
        final maxC = clubs.isEmpty ? 1 : clubs.first.$2 == 0 ? 1 : clubs.first.$2;
        final mejores = [...l]..sort((a, b) => b.comisionTotal.compareTo(a.comisionTotal));
        final primero = todos.lastOrNull;
        return [
          const _Filtros(),
          _grilla([
            _Cifra('Asistencia', '${t.asistencia}%', detalle: '${_miles(t.ingresaron)} de ${_miles(t.anotados)} anotados'),
            _Cifra('Comisión promedio', _bs(t.promedio), detalle: 'por evento'),
            _Cifra('Ventas generadas', _bs(t.ventas), detalle: 'para los boliches'),
            _Cifra('Eventos', _miles(t.eventos), detalle: 'trabajados'),
          ]),
          const TituloBloque('Evolución mensual'),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: SegmentedButton<int>(
              showSelectedIcon: false,
              segments: [for (var i = 0; i < _series.length; i++) ButtonSegment(value: i, label: Text(_series[i].$1))],
              selected: {serie},
              onSelectionChanged: (s) => ref.read(_serieProvider.notifier).poner(s.first),
            ),
          ),
          const SizedBox(height: 10),
          _Barras(porMes(l, _series[serie].$2), plata: _series[serie].$3),
          if (clubs.length > 1) ...[
            const TituloBloque('Por boliche'),
            Tarjeta(
              child: Column(children: [
                for (final c in clubs)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Row(children: [
                      Expanded(
                        flex: 3,
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(c.$1, style: const TextStyle(fontWeight: FontWeight.w600)),
                          Text('${c.$3} eventos', style: TextStyle(fontSize: 12, color: VenueColors.textoSuave)),
                        ]),
                      ),
                      Expanded(
                        flex: 2,
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(99),
                          child: LinearProgressIndicator(value: c.$2 / maxC, minHeight: 8),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Text(_bs(c.$2), style: const TextStyle(fontWeight: FontWeight.w600)),
                    ]),
                  ),
              ]),
            ),
          ],
          const TituloBloque('Mejores eventos'),
          mejores.isEmpty
              ? const _Vacio('Sin eventos en este período')
              : _lista([for (final e in mejores.take(5)) _filaPasado(context, e)]),
          const TituloBloque('Mis récords'),
          if (rs.isEmpty)
            const _Vacio('Tus récords aparecen con tu primer evento')
          else
            _grilla([
              for (final r in rs)
                _Cifra(r.titulo, r.plata ? _bs(r.valor) : _miles(r.valor),
                    detalle: r.evento != null
                        ? '${r.evento!.evento} · ${r.evento!.club} · ${_fecha(r.evento!.fecha)}'
                        : r.mes != null
                            ? _mesCorto(r.mes!)
                            : primero != null
                                ? 'desde ${_fecha(primero.fecha)}'
                                : null),
            ]),
          TituloBloque('Trayectoria',
              accion: Text('Privada', style: TextStyle(fontSize: 12, color: VenueColors.textoTenue))),
          Tarjeta(
            child: Column(children: [
              for (final (k, v) in [
                ('Eventos trabajados', _miles(tt.eventos)),
                ('Boliches', _miles(todos.map((e) => e.clubId).toSet().length)),
                ('Personas que entraron por vos', _miles(tt.entraron)),
                ('Entradas vendidas', _miles(tt.entradas)),
                ('Mesas confirmadas', _miles(tt.mesas)),
                ('Ventas generadas', _bs(tt.ventas)),
                ('Ganancias totales', _bs(tt.comision)),
                if (primero != null) ('En VENUE desde', _fecha(primero.fecha)),
              ])
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Row(children: [
                    Expanded(child: Text(k, style: TextStyle(color: VenueColors.textoSuave))),
                    Text(v, style: const TextStyle(fontWeight: FontWeight.w600)),
                  ]),
                ),
            ]),
          ),
          const TituloBloque('Clientes que vuelven'),
          _Recurrentes(club: club),
          const TituloBloque('Tu enlace de venta'),
          _Links(desde: per.desde(DateTime.now())),
        ];
      },
    );
  }
}

class _Recurrentes extends ConsumerWidget {
  const _Recurrentes({this.club});
  final String? club;
  @override
  Widget build(BuildContext context, WidgetRef ref) => FutureBuilder(
        future: ref.read(rrppRepositoryProvider).recurrentes(club),
        builder: (_, s) {
          final l = s.data ?? const [];
          if (!s.hasData) return const SizedBox(height: 60, child: Center(child: CircularProgressIndicator()));
          if (l.isEmpty) {
            return const _Vacio('Todavía no hay invitados que repitan',
                'Cuando alguien vuelva a entrar por tu lista en otro evento, lo vas a ver acá.');
          }
          return Tarjeta(
            child: Column(children: [
              for (final r in l.take(10))
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Row(children: [
                    Expanded(child: Text(r.nombre)),
                    Text('${r.eventos} eventos', style: const TextStyle(fontWeight: FontWeight.w600)),
                  ]),
                ),
            ]),
          );
        },
      );
}

class _Links extends ConsumerWidget {
  const _Links({this.desde});
  final DateTime? desde;
  @override
  Widget build(BuildContext context, WidgetRef ref) => FutureBuilder(
        future: ref.read(rrppRepositoryProvider).links(desde),
        builder: (_, s) {
          final d = s.data;
          if (d == null) return const SizedBox(height: 60, child: Center(child: CircularProgressIndicator()));
          if (d.visitas == 0) {
            return const _Vacio('Sin visitas por tu enlace todavía',
                'Compartí tu enlace desde un evento próximo: acá vas a ver cuánta gente entra y cuántos compran.');
          }
          return _grilla([
            _Cifra('Visitas', _miles(d.visitas)),
            _Cifra('Compras', _miles(d.compras),
                detalle: d.clientes > 0 ? '${(d.compras * 100 / d.clientes).round()}% de quienes iniciaron sesión' : null),
          ]);
        },
      );
}

// ── GANANCIAS ───────────────────────────────────────────────────────────

class _Ganancias extends ConsumerWidget {
  const _Ganancias();
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final per = ref.watch(periodoProvider);
    final club = ref.watch(filtroClubProvider);
    return _Pagina(
      titulo: 'Ganancias',
      hijos: (todos) {
        final l = delPeriodo(todos, per, club);
        final t = Totales.de(l);
        Widget renglon(String k, String d, num v, {bool total = false}) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Row(children: [
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(k, style: TextStyle(fontWeight: total ? FontWeight.w600 : FontWeight.w400)),
                    if (d.isNotEmpty) Text(d, style: TextStyle(fontSize: 12, color: VenueColors.textoTenue)),
                  ]),
                ),
                Text(_bs(v), style: TextStyle(fontWeight: FontWeight.w700, fontSize: total ? 17 : 14.5)),
              ]),
            );
        return [
          const _Filtros(),
          Text('Tu comisión en ${per.largo}', style: TextStyle(color: VenueColors.textoSuave, fontSize: 13.5)),
          Text(_bs(t.comision),
              style: const TextStyle(fontSize: 44, fontWeight: FontWeight.w700, letterSpacing: -1.2, height: 1.15)),
          Text('Lo que vendiste para los boliches: ${_bs(t.ventas)}. Eso no es tu ganancia: tu ganancia es la comisión.',
              style: TextStyle(color: VenueColors.textoSuave, height: 1.4)),
          const SizedBox(height: 14),
          Tarjeta(
            child: Column(children: [
              renglon('Estimadas', 'eventos todavía abiertos', t.estimado),
              renglon('Confirmadas', 'evento cerrado, falta pagar', t.confirmado),
              renglon('Pagadas', 'marcadas por el boliche o tu jefe', t.pagado),
              Divider(color: VenueColors.lineaSuave),
              renglon('Total', '', t.comision, total: true),
            ]),
          ),
          const TituloBloque('Por evento'),
          if (l.isEmpty)
            const _Vacio('Sin comisiones en este período')
          else
            _lista([
              for (final e in l)
                _filaPasado(context, e,
                    sub: [
                      e.club,
                      if (e.comisionEntradas > 0) 'entradas ${_bs(e.comisionEntradas)}',
                      if (e.comisionMesas > 0) 'mesas ${_bs(e.comisionMesas)}',
                      if (e.comisionJefe > 0) 'jefe ${_bs(e.comisionJefe)}',
                      if (e.bono > 0) 'bono ${_bs(e.bono)}',
                    ].join(' · ')),
            ]),
          const SizedBox(height: 14),
          Text(
              'Cada boliche paga distinto: el monto por manilla y por combo sale de la configuración de ese boliche y de tu team. '
              'Una comisión figura como pagada solo cuando el boliche o tu jefe la marca.',
              style: TextStyle(color: VenueColors.textoTenue, fontSize: 12.5, height: 1.4)),
        ];
      },
    );
  }
}

// ── PERFIL ──────────────────────────────────────────────────────────────

class _Perfil extends ConsumerWidget {
  const _Perfil();
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final perfil = ref.watch(perfilProvider).value;
    final user = ref.watch(supabaseProvider).auth.currentUser;
    final correo = (user?.email ?? '').endsWith('@plataforma.local') ? null : user?.email;
    final boliches = ref.watch(misBolichesProvider).value ?? const <BolicheMio>[];
    final sols = ref.watch(misSolicitudesProvider).value ?? const <SolicitudMia>[];
    final club = ref.watch(clubActivoProvider);
    final rol = ref.watch(rolProvider).value;
    final todos = ref.watch(rrppEventosProvider).value ?? const <EventoRrpp>[];
    final repo = ref.read(rrppRepositoryProvider);
    final flecha = const Icon(Icons.chevron_right_rounded);

    return RefreshIndicator(
      onRefresh: () => _refrescar(ref),
      child: ListView(padding: const EdgeInsets.fromLTRB(16, 12, 16, 28), children: [
        Row(children: [
          Inicial(perfil?.nombre ?? '?', lado: 52),
          const SizedBox(width: 14),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(perfil?.nombre ?? '', style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w700)),
              Text(correo ?? '@${perfil?.usuario ?? ''}', style: TextStyle(color: VenueColors.textoSuave)),
            ]),
          ),
        ]),
        TituloBloque('Mis establecimientos',
            accion: TextButton(onPressed: () => abrirExplorar(context, ref), child: const Text('Explorar'))),
        if (boliches.isEmpty)
          _Vacio.accion('Todavía no trabajás con ningún boliche', null,
              accion: Wrap(spacing: 8, children: [
                FilledButton(onPressed: () => abrirExplorar(context, ref), child: const Text('Explorar boliches')),
                OutlinedButton(onPressed: () => abrirCodigo(context, ref), child: const Text('Tengo un enlace')),
              ]))
        else
          _lista([
            for (final b in boliches)
              _fila(
                inicio: _logo(b.nombre, b.logoUrl),
                titulo: b.nombre,
                sub: b.activo
                    ? '${b.rol == 'jefe' ? 'Jefe' : 'Relacionador'}${b.team != null ? ' · ${b.team}' : ''}'
                    : 'Sin acceso · conservás tu historial',
                fin: b.activo && b.id == club?.id
                    ? Text('Activo', style: TextStyle(color: VenueColors.ok, fontWeight: FontWeight.w600, fontSize: 12.5))
                    : flecha,
                alTocar: () => _abrirBoliche(context, ref, b, todos),
              ),
          ]),
        if (sols.isNotEmpty) ...[
          const TituloBloque('Solicitudes'),
          _lista([
            for (final s in sols)
              _fila(
                inicio: _logo(s.club, s.logoUrl),
                titulo: s.club,
                sub: '${s.team != null ? '${s.team} · ' : ''}${_fecha(s.creada)}',
                fin: s.pendiente
                    ? TextButton(
                        onPressed: () async {
                          try {
                            await repo.cancelar(s.id);
                            refrescarRrpp(ref);
                          } catch (e) {
                            if (context.mounted) avisar(context, mensajeDeError(e), tipo: TipoAviso.aviso);
                          }
                        },
                        child: const Text('Cancelar'))
                    : Text(switch (s.estado) { 'aprobada' => 'Aprobada', 'rechazada' => 'Rechazada', _ => 'Cancelada' },
                        style: TextStyle(
                            color: s.estado == 'aprobada' ? VenueColors.ok : s.estado == 'rechazada' ? VenueColors.mal : VenueColors.textoTenue,
                            fontWeight: FontWeight.w600,
                            fontSize: 12.5)),
              ),
          ]),
        ],
        const SizedBox(height: 10),
        OutlinedButton(onPressed: () => abrirCodigo(context, ref), child: const Text('Tengo un enlace de invitación')),
        if (club != null) ...[
          TituloBloque('Herramientas · ${club.nombre}'),
          _lista([
            _fila(inicio: const Icon(Icons.how_to_reg_outlined), titulo: 'Listas y entradas', sub: 'Anotar invitados y vender QR', fin: flecha,
                alTocar: () => abrirHerramienta(context, ref, 'Listas y entradas', const AccesosScreen())),
            _fila(inicio: const Icon(Icons.table_bar_outlined), titulo: 'Mesas', sub: 'Vender y reservar', fin: flecha,
                alTocar: () => abrirHerramienta(context, ref, 'Mesas', const MesasScreen())),
            _fila(inicio: const Icon(Icons.payments_outlined), titulo: 'Pagos', sub: 'Lo que rendís al boliche', fin: flecha,
                alTocar: () => abrirHerramienta(context, ref, 'Pagos', const PagosScreen())),
            if (rol == Rol.jefe) ...[
              _fila(inicio: const Icon(Icons.groups_outlined), titulo: 'Mi team', sub: 'Tu gente y el reparto', fin: flecha,
                  alTocar: () => abrirHerramienta(context, ref, 'Mi team', const MiTeamScreen())),
              _fila(inicio: const Icon(Icons.bar_chart_outlined), titulo: 'Stats del team', sub: 'Tu team y el top de teams', fin: flecha,
                  alTocar: () => abrirHerramienta(context, ref, 'Stats del team', const ReporteScreen())),
              _fila(inicio: const Icon(Icons.person_add_alt_outlined), titulo: 'Quieren unirse', sub: 'Solicitudes para tu team', fin: flecha,
                  alTocar: () => abrirGestionSolicitudes(context, ref)),
            ],
          ]),
        ],
        const TituloBloque('Cuenta'),
        _lista([
          _fila(inicio: const Icon(Icons.manage_accounts_outlined), titulo: 'Mis datos y ajustes', sub: 'Foto, teléfono, contraseña y tema',
              fin: flecha,
              alTocar: () => showModalBottomSheet<void>(
                  context: context, isScrollControlled: true, useSafeArea: true, builder: (_) => const PanelPerfil())),
          if (correo == null)
            _fila(inicio: const Icon(Icons.alternate_email_rounded), titulo: 'Agregar mi correo', sub: 'Para entrar con él y recuperar la contraseña',
                fin: flecha, alTocar: () => _agregarCorreo(context, ref)),
          _fila(inicio: const Icon(Icons.logout_rounded), titulo: 'Cerrar sesión', sub: 'Salir de VENUE en este teléfono',
              alTocar: () => ref.read(authRepositoryProvider).salir()),
        ]),
      ]),
    );
  }
}

void _agregarCorreo(BuildContext context, WidgetRef ref) {
  final c = TextEditingController();
  _hoja(
    context,
    (h) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      _tituloHoja('Agregar mi correo', 'Te mandamos un enlace para confirmarlo.'),
      TextField(controller: c, keyboardType: TextInputType.emailAddress, decoration: const InputDecoration(labelText: 'Correo')),
      const SizedBox(height: 12),
      FilledButton(
        onPressed: () async {
          try {
            await ref.read(supabaseProvider).auth.updateUser(UserAttributes(email: c.text.trim().toLowerCase()),
                emailRedirectTo: redireccionApp);
            if (h.mounted) {
              Navigator.pop(h);
              avisar(context, 'Te mandamos un enlace para confirmarlo');
            }
          } catch (e) {
            if (h.mounted) avisar(h, mensajeDeError(e), tipo: TipoAviso.aviso);
          }
        },
        child: const Text('Mandar confirmación'),
      ),
    ]),
  );
}

void _abrirBoliche(BuildContext context, WidgetRef ref, BolicheMio b, List<EventoRrpp> todos) {
  final l = todos.where((e) => e.clubId == b.id).toList();
  final t = Totales.de(l);
  final prox = (ref.read(rrppProximosProvider).value ?? const <Proximo>[]).where((e) => e.clubId == b.id).toList();
  _hoja(
    context,
    (c) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      _tituloHoja(b.nombre, b.activo ? (b.rol == 'jefe' ? 'Jefe' : 'Relacionador') + (b.team != null ? ' · ${b.team}' : '') : 'Sin acceso'),
      _grilla([
        _Cifra('Eventos', _miles(t.eventos), detalle: 'trabajados'),
        _Cifra('Entraron', _miles(t.entraron), detalle: '${_miles(t.manillas)} manillas'),
        _Cifra('Comisiones', _bs(t.comision), detalle: '${_bs(t.pendiente)} por cobrar', color: VenueColors.ok),
        _Cifra('Ventas', _bs(t.ventas), detalle: '${_miles(t.mesas)} mesas'),
      ]),
      const SizedBox(height: 12),
      _Barras(porMes(l, (e) => e.comisionTotal), plata: true),
      if (prox.isNotEmpty) ...[
        const TituloBloque('Próximos'),
        _lista([for (final e in prox) _filaProximo(c, ref, e)]),
      ],
      if (l.isNotEmpty) ...[
        const TituloBloque('Historial'),
        _lista([for (final e in l.take(12)) _filaPasado(c, e)]),
      ],
      if (b.activo && ref.read(clubActivoIdProvider) != b.id) ...[
        const SizedBox(height: 14),
        FilledButton(
          onPressed: () {
            ref.read(clubActivoIdProvider.notifier).elegir(b.id);
            Navigator.pop(c);
            avisar(context, 'Ahora trabajás en ${b.nombre}');
          },
          child: Text('Trabajar en ${b.nombre}'),
        ),
      ],
    ]),
  );
}

// ── sumarse a un boliche ────────────────────────────────────────────────

void abrirExplorar(BuildContext context, WidgetRef ref) => showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      useSafeArea: true,
      backgroundColor: VenueColors.superficie,
      builder: (_) => const _Explorar(),
    );

class _Explorar extends ConsumerStatefulWidget {
  const _Explorar();
  @override
  ConsumerState<_Explorar> createState() => _ExplorarState();
}

class _ExplorarState extends ConsumerState<_Explorar> {
  String _q = '';
  late Future<List<BolicheExplorar>> _f = ref.read(rrppRepositoryProvider).explorar('');

  void _buscar(String q) => setState(() {
        _q = q;
        _f = ref.read(rrppRepositoryProvider).explorar(q.trim());
      });

  @override
  Widget build(BuildContext context) => Padding(
        padding: EdgeInsets.fromLTRB(16, 0, 16, 16 + MediaQuery.viewInsetsOf(context).bottom),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          _tituloHoja('Explorar boliches', 'Pedí sumarte; el boliche te aprueba.'),
          TextField(
            onChanged: _buscar,
            decoration: const InputDecoration(prefixIcon: Icon(Icons.search_rounded), hintText: 'Buscar por nombre o ciudad'),
          ),
          const SizedBox(height: 12),
          Flexible(
            child: FutureBuilder<List<BolicheExplorar>>(
              future: _f,
              builder: (_, s) {
                if (s.hasError) return Text(mensajeDeError(s.error!));
                if (!s.hasData) return const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator()));
                final l = s.data!;
                if (l.isEmpty) {
                  return _Vacio(_q.isEmpty ? 'Todavía no hay boliches abiertos a solicitudes' : 'No encontramos boliches',
                      'Si te pasaron un enlace, usá "Tengo un enlace".');
                }
                return SingleChildScrollView(
                  child: _lista([
                    for (final b in l)
                      _fila(
                        inicio: _logo(b.nombre, b.logoUrl),
                        titulo: b.nombre,
                        sub: b.lugar ?? '',
                        fin: b.yaMiembro
                            ? Text('Ya trabajás acá', style: TextStyle(color: VenueColors.ok, fontSize: 12.5))
                            : b.pendiente
                                ? Text('Pendiente', style: TextStyle(color: VenueColors.aviso, fontSize: 12.5))
                                : FilledButton(
                                    onPressed: () async {
                                      try {
                                        await ref.read(rrppRepositoryProvider).solicitar(b.id);
                                        refrescarRrpp(ref);
                                        if (context.mounted) avisar(context, 'Solicitud enviada');
                                        _buscar(_q);
                                      } catch (e) {
                                        if (context.mounted) avisar(context, mensajeDeError(e), tipo: TipoAviso.aviso);
                                      }
                                    },
                                    child: const Text('Solicitar'),
                                  ),
                      ),
                  ]),
                );
              },
            ),
          ),
        ]),
      );
}

void abrirCodigo(BuildContext context, WidgetRef ref) {
  final c = TextEditingController();
  _hoja(
    context,
    (h) => Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(h).bottom),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        _tituloHoja('Tengo un enlace', 'Pegá el enlace o el código que te pasó el boliche o tu jefe de team.'),
        TextField(controller: c, autocorrect: false, decoration: const InputDecoration(hintText: 'https://… o código')),
        const SizedBox(height: 12),
        FilledButton(
          onPressed: () {
            final code = codigoDeUnion(c.text);
            if (code.length < 8) return avisar(h, 'Ese código no parece completo', tipo: TipoAviso.aviso);
            Navigator.pop(h);
            abrirUnirse(context, ref, code);
          },
          child: const Text('Continuar'),
        ),
      ]),
    ),
  );
}

/// Muestra a qué boliche (o team) lleva el código y manda la solicitud.
Future<void> abrirUnirse(BuildContext context, WidgetRef ref, String code) async {
  ref.read(unirsePendienteProvider.notifier).poner(null);
  final repo = ref.read(rrppRepositoryProvider);
  Invitacion? inv;
  try {
    inv = await repo.verInvitacion(code);
  } catch (_) {}
  if (!context.mounted) return;
  if (inv == null || inv.clubs.isEmpty) {
    return _hoja(context, (_) => _tituloHoja('Enlace no válido', 'El enlace venció o fue desactivado. Pedile uno nuevo a quien te lo pasó.'));
  }
  final invitacion = inv;
  String? elegido = invitacion.clubs.length == 1 ? invitacion.clubs.first.id : null;
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    useSafeArea: true,
    backgroundColor: VenueColors.superficie,
    builder: (h) => StatefulBuilder(
      builder: (h, set) => ListView(shrinkWrap: true, padding: const EdgeInsets.fromLTRB(16, 0, 16, 28), children: [
        _tituloHoja(invitacion.team != null ? 'Sumarte al team ${invitacion.team}' : 'Sumarte',
            invitacion.clubs.length > 1 ? 'Este team trabaja en varios boliches. Elegí en cuál.' : 'Mandá tu solicitud.'),
        _lista([
          for (final c in invitacion.clubs)
            _fila(
              inicio: _logo(c.nombre, c.logo),
              titulo: c.nombre,
              sub: '',
              fin: elegido == c.id ? Icon(Icons.check_circle_rounded, color: VenueColors.ok) : null,
              alTocar: () => set(() => elegido = c.id),
            ),
        ]),
        const SizedBox(height: 10),
        Text('Tu solicitud queda pendiente hasta que ${invitacion.team != null ? 'tu jefe de team o ' : ''}el boliche la apruebe. Recién ahí ves sus eventos.',
            style: TextStyle(color: VenueColors.textoSuave, height: 1.4)),
        const SizedBox(height: 14),
        FilledButton(
          onPressed: elegido == null
              ? null
              : () async {
                  try {
                    await repo.solicitar(elegido, code: code);
                    refrescarRrpp(ref);
                    if (h.mounted) Navigator.pop(h);
                    if (context.mounted) avisar(context, 'Solicitud enviada: te avisamos cuando te aprueben');
                  } catch (e) {
                    if (h.mounted) Navigator.pop(h);
                    if (context.mounted) avisar(context, mensajeDeError(e), tipo: TipoAviso.aviso);
                  }
                },
          child: const Text('Solicitar unirme'),
        ),
        TextButton(onPressed: () => Navigator.pop(h), child: const Text('Ahora no')),
      ]),
    ),
  );
}
