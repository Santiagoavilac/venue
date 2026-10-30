import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/networking/supabase.dart';
import '../../../core/theme/venue_theme.dart';
import '../../../core/widgets/avisos.dart';
import '../../clubs/data/clubs.dart';
import '../../events/data/eventos.dart';
import '../data/listas.dart';

/// Límites de lista del jefe en una lista: el suyo y el de cada relacionador
/// de su team. Vacío = sin límite.
class CupoJefe {
  const CupoJefe({
    required this.listaId,
    required this.lista,
    this.mio,
    this.team,
    required this.anotadosMios,
    required this.teamPersonas,
  });
  final String listaId;
  final String lista;
  final int? mio;
  final int? team;
  final int anotadosMios;
  final int teamPersonas;

  factory CupoJefe.desde(Map<String, dynamic> j) => CupoJefe(
        listaId: j['lista_tipo_id'] as String,
        lista: j['lista'] as String? ?? '',
        mio: (j['cupo_mio'] as num?)?.toInt(),
        team: (j['cupo_team'] as num?)?.toInt(),
        anotadosMios: (j['anotados_mios'] as num?)?.toInt() ?? 0,
        teamPersonas: (j['team_personas'] as num?)?.toInt() ?? 0,
      );
}

/// Un cambio de límites hecho por un jefe, para que lo vea el admin.
class CambioCupo {
  const CambioCupo({
    required this.jefe,
    this.team,
    required this.evento,
    required this.lista,
    this.cupoJefe,
    this.cupoTeam,
    required this.personas,
    required this.cuando,
  });
  final String jefe;
  final String? team;
  final String evento;
  final String lista;
  final int? cupoJefe;
  final int? cupoTeam;
  final int personas;
  final DateTime cuando;

  factory CambioCupo.desde(Map<String, dynamic> j) => CambioCupo(
        jefe: j['jefe'] as String? ?? '',
        team: j['team'] as String?,
        evento: j['evento'] as String? ?? '',
        lista: j['lista'] as String? ?? '',
        cupoJefe: (j['cupo_jefe'] as num?)?.toInt(),
        cupoTeam: (j['cupo_team'] as num?)?.toInt(),
        personas: (j['personas'] as num?)?.toInt() ?? 0,
        cuando: DateTime.parse(j['created_at'] as String).toLocal(),
      );
}

final cuposJefeProvider = FutureProvider.autoDispose<List<CupoJefe>>((ref) async {
  final ev = ref.watch(eventoActivoProvider);
  if (ev == null) return const [];
  final r = await ref.watch(supabaseProvider).rpc('jefe_cupos', params: {'p_evento': ev.id});
  return (r as List? ?? const [])
      .map((x) => CupoJefe.desde(Map<String, dynamic>.from(x as Map)))
      .toList();
});

final cambiosCupoProvider = FutureProvider.autoDispose<List<CambioCupo>>((ref) async {
  final club = ref.watch(clubActivoIdProvider);
  if (club == null) return const [];
  final r = await ref.watch(supabaseProvider).rpc('cambios_cupo_pendientes', params: {'p_club': club});
  return (r as List? ?? const [])
      .map((x) => CambioCupo.desde(Map<String, dynamic>.from(x as Map)))
      .toList();
});

String _txt(int? v) => v == null ? 'sin límite' : '$v';

/// Abre la hoja de límites del jefe. Antes de aplicar, el jefe acepta que
/// administración recibe aviso de cualquier cambio (queda en el servidor).
Future<void> abrirLimitesJefe(BuildContext context, WidgetRef ref) async {
  final filas = await ref.read(cuposJefeProvider.future).catchError((Object e) {
    if (context.mounted) avisar(context, mensajeDeError(e), tipo: TipoAviso.aviso);
    return const <CupoJefe>[];
  });
  if (!context.mounted || filas.isEmpty) return;
  final cambiado = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => _LimitesSheet(filas: filas),
  );
  if (cambiado == true) {
    ref.invalidate(cuposJefeProvider);
    ref.invalidate(misCuposProvider);
    if (context.mounted) avisar(context, 'Límites actualizados. Administración fue avisada.');
  }
}

class _LimitesSheet extends ConsumerStatefulWidget {
  const _LimitesSheet({required this.filas});
  final List<CupoJefe> filas;
  @override
  ConsumerState<_LimitesSheet> createState() => _LimitesSheetState();
}

class _LimitesSheetState extends ConsumerState<_LimitesSheet> {
  late final _mio = {for (final f in widget.filas) f.listaId: TextEditingController(text: f.mio?.toString() ?? '')};
  late final _team = {for (final f in widget.filas) f.listaId: TextEditingController(text: f.team?.toString() ?? '')};
  bool _ocupado = false;

  @override
  void dispose() {
    for (final c in [..._mio.values, ..._team.values]) {
      c.dispose();
    }
    super.dispose();
  }

  int? _num(TextEditingController c) {
    final t = c.text.trim();
    if (t.isEmpty) return null;
    return (int.tryParse(t) ?? 0).clamp(0, 500);
  }

  Future<void> _guardar() async {
    final cambios = [
      for (final f in widget.filas)
        (f: f, mio: _num(_mio[f.listaId]!), team: _num(_team[f.listaId]!)),
    ].where((c) => c.mio != c.f.mio || c.team != c.f.team).toList();
    if (cambios.isEmpty) {
      Navigator.pop(context, false);
      return;
    }
    final acepta = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Confirmar cambios'),
        content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          for (final x in cambios)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text('${x.f.lista}: vos ${_txt(x.mio)} · cada uno del team ${_txt(x.team)}'),
            ),
          const SizedBox(height: 6),
          const Text('Al aceptar, los límites se aplican de inmediato y administración recibe un aviso de cualquier cambio.',
              style: TextStyle(fontWeight: FontWeight.w600)),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Acepto')),
        ],
      ),
    );
    if (acepta != true || !mounted) return;
    setState(() => _ocupado = true);
    try {
      final sb = ref.read(supabaseProvider);
      for (final x in cambios) {
        await sb.rpc('jefe_fijar_cupos', params: {'p_lista': x.f.listaId, 'p_mio': x.mio, 'p_team': x.team});
      }
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        setState(() => _ocupado = false);
        avisar(context, mensajeDeError(e), tipo: TipoAviso.aviso);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final personas = widget.filas.first.teamPersonas;
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 18, 20, 20 + MediaQuery.viewInsetsOf(context).bottom),
      child: SingleChildScrollView(
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const Text('Límites de lista', style: TextStyle(fontSize: 19, fontWeight: FontWeight.w700)),
          const SizedBox(height: 6),
          Text(
            'Cuántas personas podés anotar vos y cuántas cada relacionador de tu team '
            '($personas ${personas == 1 ? 'persona' : 'personas'}). Vacío = sin límite.',
            style: TextStyle(fontSize: 13.5, color: VenueColors.textoSuave),
          ),
          const SizedBox(height: 16),
          for (final f in widget.filas) ...[
            Text('${f.lista} · anotaste ${f.anotadosMios}',
                style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
            const SizedBox(height: 8),
            Row(children: [
              Expanded(
                child: TextField(
                  controller: _mio[f.listaId],
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Mi límite'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: TextField(
                  controller: _team[f.listaId],
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Cada uno de mi team'),
                ),
              ),
            ]),
            const SizedBox(height: 16),
          ],
          FilledButton(
            onPressed: _ocupado ? null : _guardar,
            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(50)),
            child: Text(_ocupado ? 'Guardando…' : 'Guardar'),
          ),
        ]),
      ),
    );
  }
}

/// Admin: aviso de cambios de límites hechos por jefes que todavía no vio.
class AvisoCambiosCupo extends ConsumerWidget {
  const AvisoCambiosCupo({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = ref.watch(cambiosCupoProvider).value ?? const <CambioCupo>[];
    if (cs.isEmpty) return const SizedBox.shrink();
    final n = cs.length;
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: OutlinedButton(
        style: OutlinedButton.styleFrom(
          foregroundColor: VenueColors.aviso,
          side: BorderSide(color: VenueColors.aviso),
          alignment: Alignment.centerLeft,
          padding: const EdgeInsets.all(14),
        ),
        onPressed: () => _ver(context, ref, cs),
        child: Text('$n cambio${n == 1 ? '' : 's'} de límites hecho${n == 1 ? '' : 's'} por jefes. Tocá para ver.'),
      ),
    );
  }

  Future<void> _ver(BuildContext context, WidgetRef ref, List<CambioCupo> cs) async {
    final visto = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (c) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const Text('Cambios de límites', style: TextStyle(fontSize: 19, fontWeight: FontWeight.w700)),
          const SizedBox(height: 10),
          Flexible(
            child: ListView(shrinkWrap: true, children: [
              for (final x in cs)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text('${x.jefe}${x.team == null ? '' : ' · ${x.team}'}'),
                  subtitle: Text('${x.evento} · ${x.lista} · ${horaCorta(x.cuando)}\n'
                      'Él: ${_txt(x.cupoJefe)} · Su team: ${_txt(x.cupoTeam)} (${x.personas})'),
                  isThreeLine: true,
                ),
            ]),
          ),
          const SizedBox(height: 10),
          FilledButton(
            onPressed: () => Navigator.pop(c, true),
            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(50)),
            child: const Text('Marcar como vistos'),
          ),
        ]),
      ),
    );
    if (visto != true) return;
    final club = ref.read(clubActivoIdProvider);
    try {
      await ref.read(supabaseProvider).rpc('marcar_cambios_cupo_vistos', params: {'p_club': club});
      ref.invalidate(cambiosCupoProvider);
    } catch (e) {
      if (context.mounted) avisar(context, mensajeDeError(e), tipo: TipoAviso.aviso);
    }
  }
}
