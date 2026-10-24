import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/networking/supabase.dart';
import '../../../core/theme/venue_theme.dart';
import '../../../core/widgets/avisos.dart';
import '../../clubs/data/clubs.dart';
import '../../events/data/eventos.dart';
import '../../teams/data/equipo.dart';
import '../../vip_tables/data/mesas.dart';
import '../data/contabilidad.dart';
import '../data/reporte.dart';
import 'reporte_screen.dart';

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

Widget _lista(String titulo, List<Widget> hijos) => ListView(
      shrinkWrap: true,
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
      children: [
        Text(titulo, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
        const SizedBox(height: 8),
        ...hijos,
      ],
    );

Widget _cargando<T>(Future<T> f, Widget Function(T) pintar) => FutureBuilder<T>(
      future: f,
      builder: (context, s) {
        if (s.hasError) {
          return Padding(
              padding: const EdgeInsets.all(24),
              child: Text(mensajeDeError(s.error!),
                  style: TextStyle(color: VenueColors.aviso)));
        }
        if (!s.hasData) {
          return const Padding(
              padding: EdgeInsets.all(30), child: Center(child: CircularProgressIndicator()));
        }
        return pintar(s.data as T);
      },
    );

// ── nombre por nombre de una persona ──
Future<void> hojaDetallePersona(BuildContext context, String id, String nombre, Evento ev) =>
    _hoja(context, Consumer(builder: (context, ref, _) {
      return _cargando(ref.read(reporteRepositoryProvider).detalle(ev.id, id), (d) {
        String h(dynamic ts) {
          final t = DateTime.tryParse(ts as String? ?? '')?.toLocal();
          return t == null ? 'no ingresó' : 'ingresó ${horaCorta(t)}';
        }

        final sueltas = d.entradas.where((e) => e['mesa_id'] == null).toList();
        final deMesa = d.entradas.where((e) => e['mesa_id'] != null).toList();
        Widget fila(String a, String b, bool ok) => ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              title: Text(a),
              subtitle: Text(b),
              trailing: Icon(ok ? Icons.check_circle_rounded : Icons.radio_button_unchecked,
                  color: ok ? VenueColors.ok : VenueColors.linea, size: 20),
            );
        return _lista('$nombre · ${ev.nombre}', [
          if (d.registros.isEmpty && d.entradas.isEmpty)
            const Padding(padding: EdgeInsets.all(20), child: Text('Sin actividad en este evento.')),
          if (sueltas.isNotEmpty) Text('Entradas (${sueltas.length})', style: const TextStyle(fontWeight: FontWeight.w800)),
          for (final e in sueltas)
            fila('${e['cliente']}', '#${e['code']} · ${e['estado'] == 'usada' ? h(e['used_at']) : e['estado']}', e['estado'] == 'usada'),
          if (deMesa.isNotEmpty) Text('Manillas de mesa (${deMesa.length})', style: const TextStyle(fontWeight: FontWeight.w800)),
          for (final e in deMesa)
            fila('${e['cliente']}', '#${e['code']} · ${e['estado'] == 'usada' ? h(e['used_at']) : e['estado']}', e['estado'] == 'usada'),
          if (d.registros.isNotEmpty) Text('Listas (${d.registros.length})', style: const TextStyle(fontWeight: FontWeight.w800)),
          for (final r in d.registros)
            fila('${r['nombre']}', '${(r['l'] as Map?)?['nombre'] ?? 'Lista'} · ${h(r['ingreso_at'])}', r['ingreso_at'] != null),
        ]);
      });
    }));

// ── eventos pasados de una persona ──
Future<void> hojaEventosPasados(BuildContext context, String id, String nombre) =>
    _hoja(context, Consumer(builder: (context, ref, _) {
      final club = ref.watch(clubActivoIdProvider)!;
      return _cargando(ref.read(reporteRepositoryProvider).eventosPasados(club), (evs) {
        return _lista('Eventos pasados', [
          for (final e in evs)
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(e.nombre, style: const TextStyle(fontWeight: FontWeight.w600)),
              subtitle: Text('${e.fechaCorta} · ${e.estado}'),
              trailing: const Icon(Icons.chevron_right_rounded),
              onTap: () => hojaDetallePersona(context, id, nombre, e),
            ),
        ]);
      });
    }));

// ── comisiones por team (admin) ──
Future<void> hojaComisiones(BuildContext context) => _hoja(context, const _Comisiones());

class _Comisiones extends ConsumerStatefulWidget {
  const _Comisiones();
  @override
  ConsumerState<_Comisiones> createState() => _ComisionesState();
}

class _ComisionesState extends ConsumerState<_Comisiones> {
  Map<String, num?>? _cuts;

  @override
  Widget build(BuildContext context) {
    final c = ref.watch(cierreProvider).value;
    final ev = ref.watch(eventoActivoProvider);
    final equipo = ref.watch(equipoProvider).value ?? const <String, Miembro>{};
    final teams = ref.watch(teamsClubProvider).value ?? const <String, String>{};
    if (c == null || ev == null) return const SizedBox(height: 120);
    final repo = ref.read(reporteRepositoryProvider);
    _cuts ?? repo.comisionesPropias(c.personas.map((p) => p.id)).then((m) {
      if (mounted) setState(() => _cuts = m);
    });
    num total = 0;
    final tarjetas = <Widget>[];
    for (final t in teams.entries) {
      final filas = c.personas.where((p) => p.teamId == t.key).toList();
      if (filas.isEmpty) continue;
      final comR = filas.fold<num>(0, (a, p) => a + p.comRrpp);
      final comJ = filas.fold<num>(0, (a, p) => a + p.comJefe);
      final man = filas.fold<int>(0, (a, p) => a + p.usadas);
      total += comR + comJ;
      final jefe = filas.where((p) => equipo[p.id]?.rol == 'jefe').firstOrNull;
      tarjetas.add(ExpansionTile(
        tilePadding: EdgeInsets.zero,
        title: Text(t.value, style: const TextStyle(fontWeight: FontWeight.w700)),
        subtitle: Text('$man manillas · ${comR + comJ} Bs a pagar'),
        children: [
          Renglon('Jefe: ${jefe?.nombre ?? '—'}', '$comJ Bs', color: VenueColors.ok),
          for (final p in filas.where((p) => equipo[p.id]?.rol == 'rrpp').toList()
            ..sort((a, b) => b.usadas.compareTo(a.usadas)))
            Row(children: [
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(p.nombre),
                  Text('${p.usadas} manillas · ${p.comRrpp} Bs',
                      style: TextStyle(color: VenueColors.textoSuave, fontSize: 12.5)),
                ]),
              ),
              SizedBox(
                width: 96,
                child: TextFormField(
                  key: ValueKey('${p.id}-${_cuts?[p.id]}'),
                  initialValue: _cuts?[p.id]?.toString() ?? '',
                  keyboardType: TextInputType.number,
                  textAlign: TextAlign.center,
                  decoration: const InputDecoration(
                      isDense: true, hintText: 'evento', suffixText: 'Bs'),
                  onFieldSubmitted: (v) async {
                    final cut = v.trim().isEmpty ? null : num.tryParse(v.trim());
                    if (cut != null && (cut < 0 || cut > ev.precioManilla)) {
                      avisar(context, 'Entre 0 y ${ev.precioManilla}', tipo: TipoAviso.aviso);
                      return;
                    }
                    try {
                      await repo.fijarComision(p.id, cut);
                      ref.invalidate(cierreProvider);
                      setState(() => _cuts = null);
                      if (context.mounted) avisar(context, 'Comisión de ${p.nombre} actualizada');
                    } catch (e) {
                      if (context.mounted) avisar(context, mensajeDeError(e), tipo: TipoAviso.aviso);
                    }
                  },
                ),
              ),
            ]),
        ],
      ));
    }
    return _lista('Comisiones · ${ev.nombre}', [
      Text(
        'Tocá un team para editar los Bs por manilla de cada relacionador (vacío = lo que fija el evento). Se paga solo sobre las ingresadas.',
        style: TextStyle(color: VenueColors.textoSuave, fontSize: 12.5, height: 1.35),
      ),
      if (tarjetas.isEmpty)
        const Padding(padding: EdgeInsets.all(20), child: Text('Sin actividad por teams todavía.')),
      ...tarjetas,
      const Divider(),
      Renglon('Total comisiones a pagar', '$total Bs', fuerte: true),
    ]);
  }
}

// ── bonos (admin) ──
Future<void> hojaBonos(BuildContext context) => _hoja(context, const _Bonos());

class _Bonos extends ConsumerStatefulWidget {
  const _Bonos();
  @override
  ConsumerState<_Bonos> createState() => _BonosState();
}

class _BonosState extends ConsumerState<_Bonos> {
  final _monto = TextEditingController(), _motivo = TextEditingController();
  String? _persona;
  int _v = 0;

  @override
  void dispose() {
    _monto.dispose();
    _motivo.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ev = ref.watch(eventoActivoProvider)!;
    final equipo = ref.watch(equipoProvider).value ?? const <String, Miembro>{};
    final gente = equipo.values.where((m) => m.rol == 'rrpp' || m.rol == 'jefe').toList()
      ..sort((a, b) => a.nombre.compareTo(b.nombre));
    final repo = ref.read(reporteRepositoryProvider);
    Future<void> hacer(Future<void> Function() f, String ok) async {
      try {
        await f();
        ref.invalidate(cierreProvider);
        if (!mounted) return;
        setState(() => _v++);
        avisar(this.context, ok);
      } catch (e) {
        if (mounted) avisar(this.context, mensajeDeError(e), tipo: TipoAviso.aviso);
      }
    }

    return _lista('Bonos · ${ev.nombre}', [
      DropdownButtonFormField<String?>(
        borderRadius: BorderRadius.circular(12),
        dropdownColor: VenueColors.superficie,
        icon: Icon(Icons.keyboard_arrow_down_rounded, color: VenueColors.textoSuave),
        menuMaxHeight: 420,
        initialValue: _persona,
        isExpanded: true,
        decoration: const InputDecoration(labelText: 'Persona'),
        items: [
          for (final g in gente)
            DropdownMenuItem<String?>(value: g.id, child: Text('${g.nombre} · ${g.team}')),
        ],
        onChanged: (v) => setState(() => _persona = v),
      ),
      const SizedBox(height: 10),
      Row(children: [
        SizedBox(
          width: 120,
          child: TextField(
              controller: _monto,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Monto Bs')),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: TextField(
              controller: _motivo,
              decoration: const InputDecoration(labelText: 'Motivo', hintText: 'Meta de ventas')),
        ),
      ]),
      const SizedBox(height: 10),
      FilledButton(
        onPressed: () {
          final m = num.tryParse(_monto.text);
          if (_persona == null || m == null || m <= 0) {
            avisar(context, 'Elegí la persona y un monto mayor a 0', tipo: TipoAviso.aviso);
            return;
          }
          hacer(() async {
            await repo.crearBono(ev.id, _persona!, m,
                _motivo.text.trim().isEmpty ? null : _motivo.text.trim());
            _monto.clear();
            _motivo.clear();
          }, 'Bono agregado');
        },
        child: const Text('Agregar bono'),
      ),
      const Divider(height: 26),
      _cargando(repo.bonos(ev.id).then((l) => (l, _v)), (r) {
        final l = r.$1;
        if (l.isEmpty) return const Text('Sin bonos en este evento.');
        return Column(children: [
          for (final b in l)
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text('${b['monto']} Bs — ${(b['p'] as Map?)?['nombre'] ?? '?'}'),
              subtitle: b['motivo'] == null ? null : Text('${b['motivo']}'),
              trailing: IconButton(
                  tooltip: 'Eliminar bono',
                  icon: Icon(Icons.close_rounded, color: VenueColors.mal),
                  onPressed: () => hacer(() => repo.borrarBono(b['id'] as String), 'Bono eliminado')),
            ),
        ]);
      }),
    ]);
  }
}

// ── histórico y ranking (admin) ──
Future<void> hojaHistorico(BuildContext context) => _hoja(context, const _Historico());

class _Historico extends ConsumerStatefulWidget {
  const _Historico();
  @override
  ConsumerState<_Historico> createState() => _HistoricoState();
}

class _HistoricoState extends ConsumerState<_Historico> {
  bool _mes = true;

  @override
  Widget build(BuildContext context) {
    final club = ref.watch(clubActivoIdProvider)!;
    final repo = ref.read(reporteRepositoryProvider);
    final ahora = DateTime.now();
    final desde = _mes ? DateTime(ahora.year, ahora.month, 1) : DateTime(2000);
    return _lista('Histórico', [
      SegmentedButton<bool>(
        showSelectedIcon: false,
        segments: const [
          ButtonSegment(value: true, label: Text('Este mes')),
          ButtonSegment(value: false, label: Text('Todo')),
        ],
        selected: {_mes},
        onSelectionChanged: (s) => setState(() => _mes = s.first),
      ),
      const SizedBox(height: 10),
      const Text('Ranking de relacionadores', style: TextStyle(fontWeight: FontWeight.w800)),
      _cargando(repo.ranking(club, desde), (r) => Column(children: [
            if (r.isEmpty) const Padding(padding: EdgeInsets.all(12), child: Text('Sin datos en el período.')),
            for (var i = 0; i < r.length; i++)
              ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                leading: Text('${i + 1}', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                title: Text('${r[i]['nombre']}'),
                subtitle: Text(
                    '${r[i]['ingresados']}/${r[i]['anotados']} lista · ${r[i]['entradas']} entradas · ${r[i]['mesas']} mesas'),
                trailing: Text('${r[i]['comision']} Bs', style: const TextStyle(fontWeight: FontWeight.w700)),
              ),
          ])),
      const Divider(),
      const Text('Eventos', style: TextStyle(fontWeight: FontWeight.w800)),
      _cargando(repo.historico(club), (h) => Column(children: [
            for (final e in h)
              ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                title: Text('${e['nombre']} · ${e['fecha']}'),
                subtitle: Text(
                    '${e['lista_in']}/${e['lista_total']} lista · ${e['entradas_usadas']}/${e['entradas_vendidas']} entradas · ${e['mesas']} mesas'),
                trailing: Text('${e['utilidad']} Bs', style: const TextStyle(fontWeight: FontWeight.w700)),
              ),
          ])),
    ]);
  }
}

// ── teléfonos del equipo ──
Future<void> hojaTelefonos(BuildContext context) =>
    _hoja(context, Consumer(builder: (context, ref, _) {
      final club = ref.watch(clubActivoIdProvider)!;
      final esAdmin = ref.watch(rolProvider).value == Rol.admin;
      final repo = ref.read(reporteRepositoryProvider);
      return StatefulBuilder(builder: (context, set) {
        return _cargando(repo.telefonos(club), (l) {
          final con = l.where((x) => x['telefono'] != null).length;
          return _lista('Teléfonos · $con de ${l.length}', [
            for (final x in l)
              ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                title: Text('${x['nombre']}'),
                subtitle: Text('@${x['usuario']} · ${x['rol']}${x['team'] == null ? '' : ' · ${x['team']}'}'),
                trailing: x['telefono'] != null
                    ? TextButton(
                        onPressed: () async {
                          await Clipboard.setData(ClipboardData(text: '+${x['telefono']}'));
                          if (context.mounted) avisar(context, 'Número copiado');
                        },
                        child: Text('+${x['telefono']}'))
                    : esAdmin
                        ? TextButton(
                            onPressed: () async {
                              final t = TextEditingController();
                              final v = await showDialog<String>(
                                context: context,
                                builder: (c) => AlertDialog(
                                  title: Text('Número de ${x['nombre']}'),
                                  content: TextField(
                                      controller: t,
                                      autofocus: true,
                                      keyboardType: TextInputType.phone,
                                      decoration: const InputDecoration(prefixText: '+591  ')),
                                  actions: [
                                    TextButton(onPressed: () => Navigator.pop(c), child: const Text('Cancelar')),
                                    TextButton(onPressed: () => Navigator.pop(c, t.text), child: const Text('Guardar')),
                                  ],
                                ),
                              );
                              if (v == null || v.trim().isEmpty) return;
                              try {
                                await repo.guardarTelefonoDe(x['user_id'] as String, v);
                                set(() {});
                              } catch (e) {
                                if (context.mounted) avisar(context, mensajeDeError(e), tipo: TipoAviso.aviso);
                              }
                            },
                            child: const Text('Cargar'))
                        : Text('sin número', style: TextStyle(color: VenueColors.textoSuave)),
              ),
          ]);
        });
      });
    }));

// ── reporte de filtro (quién no pasó el control y quién lo trajo) ──
Future<void> hojaReporteFiltro(BuildContext context) =>
    _hoja(context, Consumer(builder: (context, ref, _) {
      final ev = ref.watch(eventoActivoProvider)!;
      return _cargando(ref.read(reporteRepositoryProvider).filtro(ev.id), (l) {
        return _lista('No pasaron el filtro · ${l.length}', [
          if (l.isEmpty) const Text('Nadie marcado en este evento.'),
          for (final x in l)
            ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              title: Text('${x['nombre'] ?? x['cliente'] ?? '—'}'),
              subtitle: Text([
                if (x['rrpp'] != null) 'lo trajo ${x['rrpp']}',
                if (x['team'] != null) '${x['team']}',
                if (x['lista'] != null) '${x['lista']}',
              ].join(' · ')),
            ),
        ]);
      });
    }));

/// Exporta el libro contable y abre la hoja de compartir.
Future<void> exportarContabilidad(BuildContext context, WidgetRef ref) async {
  final ev = ref.read(eventoActivoProvider);
  final club = ref.read(clubActivoProvider);
  if (ev == null || club == null) return;
  avisar(context, 'Generando el libro…');
  try {
    await compartirContabilidad(ref.read(supabaseProvider), ev, club.nombre);
  } catch (e) {
    if (context.mounted) avisar(context, mensajeDeError(e), tipo: TipoAviso.aviso);
  }
}
