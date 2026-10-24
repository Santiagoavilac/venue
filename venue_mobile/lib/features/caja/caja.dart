import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/networking/supabase.dart';
import '../../core/theme/venue_theme.dart';
import '../../core/widgets/avisos.dart';
import '../../core/widgets/estado_vista.dart';
import '../access_control/data/persona_puerta.dart';
import '../clubs/data/clubs.dart';
import '../events/data/eventos.dart';
import '../teams/data/gente.dart';

/// Persona de la lista de la caja, con su marca de "atendido".
class PersonaCaja {
  const PersonaCaja({required this.id, required this.persona, required this.motivo});
  final String id;
  final Relacionador persona;

  /// Por qué está en la lista: 'todos', 'prepagadas' o 'manual'.
  final String motivo;
}

final cajaRepositoryProvider =
    Provider<CajaRepository>((ref) => CajaRepository(ref.watch(supabaseProvider)));

class CajaRepository {
  CajaRepository(this._sb);
  final SupabaseClient _sb;

  /// Lista de la caja. Con el filtro del evento puesto, solo quienes
  /// cargaron prepagadas más los agregados a mano. No trae plata.
  Future<List<PersonaCaja>> roster(String clubId, String? eventoId) async {
    final r = await _sb.rpc('roster_caja', params: {'p_club': clubId, 'p_evento': eventoId});
    return [
      for (final x in (r as List? ?? const []))
        PersonaCaja(
          id: x['id'] as String,
          persona: Relacionador.desde(Map<String, dynamic>.from(x as Map)),
          motivo: x['motivo'] as String? ?? 'todos',
        ),
    ];
  }

  Future<Set<String>> atendidos(String eventoId) async {
    final r = await _sb.from('caja_check').select('user_id').eq('evento_id', eventoId);
    return {for (final x in r) x['user_id'] as String};
  }

  /// Marca o desmarca que la persona ya pasó por caja (recibió sus manillas).
  Future<void> marcar(String eventoId, String usuarioId, bool atendido) => atendido
      ? _sb.from('caja_check').upsert({'evento_id': eventoId, 'user_id': usuarioId})
      : _sb.from('caja_check').delete().eq('evento_id', eventoId).eq('user_id', usuarioId);

  // ── filtro de la lista (cuenta principal) ──
  Future<bool> filtroActivo(String eventoId) async =>
      (await _sb.from('caja_filtro').select('activo').eq('evento_id', eventoId).maybeSingle())
          ?['activo'] == true;

  Future<void> activarFiltro(String eventoId, bool activo) => _sb.from('caja_filtro').upsert({
        'evento_id': eventoId, 'activo': activo,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      });

  Future<Set<String>> agregadosAMano(String eventoId) async {
    final r = await _sb.from('caja_filtro_excepcion').select('user_id').eq('evento_id', eventoId);
    return {for (final x in r) x['user_id'] as String};
  }

  Future<void> agregarAMano(String eventoId, String usuarioId, bool agregar) => agregar
      ? _sb.from('caja_filtro_excepcion').upsert({'evento_id': eventoId, 'user_id': usuarioId})
      : _sb.from('caja_filtro_excepcion').delete()
          .eq('evento_id', eventoId).eq('user_id', usuarioId);

  Future<List<PersonaCaja>> todosLosRelacionadores(String clubId) async {
    final r = await _sb.rpc('roster_relacionadores', params: {'p_club': clubId});
    return [
      for (final x in (r as List? ?? const []))
        PersonaCaja(
          id: x['id'] as String,
          persona: Relacionador.desde(Map<String, dynamic>.from(x as Map)),
          motivo: 'todos',
        ),
    ];
  }
}

/// Agrupa por team (los "Sin team" al final) y ordena por nombre.
Map<String, List<PersonaCaja>> agruparPorTeam(Iterable<PersonaCaja> gente) {
  final g = <String, List<PersonaCaja>>{};
  for (final p in gente) {
    g.putIfAbsent(p.persona.team, () => []).add(p);
  }
  for (final l in g.values) {
    l.sort((a, b) => a.persona.nombre.toLowerCase().compareTo(b.persona.nombre.toLowerCase()));
  }
  final claves = g.keys.toList()
    ..sort((a, b) => a == 'Sin team' ? 1 : b == 'Sin team' ? -1 : a.toLowerCase().compareTo(b.toLowerCase()));
  return {for (final k in claves) k: g[k]!};
}

final _cajaProvider = FutureProvider.autoDispose<
    ({List<PersonaCaja> gente, Set<String> atendidos, bool filtro})>((ref) async {
  final club = ref.watch(clubActivoIdProvider);
  final ev = ref.watch(eventoActivoProvider);
  if (club == null) return (gente: const <PersonaCaja>[], atendidos: const <String>{}, filtro: false);
  final repo = ref.watch(cajaRepositoryProvider);
  final gente = await repo.roster(club, ev?.id);
  if (ev == null) return (gente: gente, atendidos: const <String>{}, filtro: false);
  return (gente: gente, atendidos: await repo.atendidos(ev.id), filtro: await repo.filtroActivo(ev.id));
});

/// Caja: los relacionadores por team, para entregarles sus manillas y
/// marcar a quién ya se atendió.
class CajaScreen extends ConsumerStatefulWidget {
  const CajaScreen({super.key});
  @override
  ConsumerState<CajaScreen> createState() => _CajaScreenState();
}

class _CajaScreenState extends ConsumerState<CajaScreen> {
  String _q = '';
  final _local = <String, bool>{}; // marcas optimistas mientras viaja la escritura

  @override
  Widget build(BuildContext context) {
    final ev = ref.watch(eventoActivoProvider);
    final datos = ref.watch(_cajaProvider);
    final plataforma = ref.watch(plataformaProvider).value ?? false;
    final repo = ref.read(cajaRepositoryProvider);

    return RefreshIndicator(
      onRefresh: () async {
        _local.clear();
        ref.invalidate(_cajaProvider);
        await ref.read(_cajaProvider.future);
      },
      child: VistaAsync(
        valor: datos,
        reintentar: () => ref.invalidate(_cajaProvider),
        datos: (d) {
          bool atendido(String id) => _local[id] ?? d.atendidos.contains(id);
          final q = normalizar(_q.trim());
          final visibles = q.length < 2
              ? d.gente
              : d.gente.where((p) =>
                  normalizar('${p.persona.nombre} ${p.persona.usuario}').contains(q)).toList();
          final grupos = agruparPorTeam(visibles);
          final hechos = d.gente.where((p) => atendido(p.id)).length;

          Future<void> tocar(PersonaCaja p) async {
            if (ev == null) return;
            final nuevo = !atendido(p.id);
            setState(() => _local[p.id] = nuevo);
            try {
              await repo.marcar(ev.id, p.id, nuevo);
            } catch (e) {
              if (!mounted) return;
              setState(() => _local[p.id] = !nuevo); // no se guardó: se deshace a la vista
              avisar(this.context, mensajeDeError(e), tipo: TipoAviso.aviso);
            }
          }

          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
            children: [
              Row(children: [
                Expanded(
                  child: Text(
                    ev == null
                        ? 'Sin evento abierto'
                        : '${ev.nombre} · $hechos/${d.gente.length} atendidos',
                    style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
                  ),
                ),
                if (plataforma && ev != null)
                  TextButton.icon(
                    onPressed: () async {
                      await showModalBottomSheet<void>(
                        context: context,
                        isScrollControlled: true,
                        showDragHandle: true,
                        useSafeArea: true,
                        backgroundColor: VenueColors.superficie,
                        builder: (_) => _FiltroCaja(eventoId: ev.id),
                      );
                      ref.invalidate(_cajaProvider);
                    },
                    icon: const Icon(Icons.filter_alt_outlined, size: 18),
                    label: Text(d.filtro ? 'Filtro: sí' : 'Filtro: no'),
                  ),
              ]),
              if (d.filtro)
                Padding(
                  padding: EdgeInsets.only(bottom: 6),
                  child: Text('Lista filtrada: solo quienes cargaron prepagadas y los agregados a mano.',
                      style: TextStyle(color: VenueColors.aviso, fontSize: 12.5)),
                ),
              const SizedBox(height: 6),
              TextField(
                onChanged: (v) => setState(() => _q = v),
                autocorrect: false,
                decoration: const InputDecoration(
                    hintText: 'Buscar relacionador…', prefixIcon: Icon(Icons.search_rounded)),
              ),
              if (visibles.isEmpty)
                Padding(
                  padding: EdgeInsets.all(28),
                  child: Text('Nadie en la lista.',
                      textAlign: TextAlign.center, style: TextStyle(color: VenueColors.textoSuave)),
                ),
              for (final g in grupos.entries) ...[
                Padding(
                  padding: const EdgeInsets.fromLTRB(2, 16, 2, 4),
                  child: Text(
                    '${g.key.toUpperCase()} · ${g.value.where((p) => atendido(p.id)).length}/${g.value.length}',
                    style: TextStyle(
                        color: VenueColors.textoSuave, fontSize: 12.5,
                        fontWeight: FontWeight.w800, letterSpacing: .6),
                  ),
                ),
                for (final p in g.value)
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    controlAffinity: ListTileControlAffinity.trailing,
                    value: atendido(p.id),
                    onChanged: ev == null ? null : (_) => tocar(p),
                    title: Text(p.persona.nombre,
                        style: TextStyle(
                            fontSize: 16, fontWeight: FontWeight.w600,
                            decoration: atendido(p.id) ? TextDecoration.lineThrough : null,
                            color: atendido(p.id) ? VenueColors.textoSuave : null)),
                    subtitle: Text(
                        '@${p.persona.usuario}${p.persona.esJefe ? ' · JEFE' : ''}${p.motivo == 'manual' ? ' · agregado a mano' : ''}'),
                  ),
              ],
            ],
          );
        },
      ),
    );
  }
}

/// Interruptor por evento: con él puesto, la caja (y la consulta de la
/// puerta) ve solo a quienes cargaron prepagadas, más los agregados a mano.
class _FiltroCaja extends ConsumerStatefulWidget {
  const _FiltroCaja({required this.eventoId});
  final String eventoId;
  @override
  ConsumerState<_FiltroCaja> createState() => _FiltroCajaState();
}

class _FiltroCajaState extends ConsumerState<_FiltroCaja> {
  int _v = 0;
  String _q = '';

  @override
  Widget build(BuildContext context) {
    final repo = ref.read(cajaRepositoryProvider);
    final club = ref.watch(clubActivoIdProvider)!;
    Future<void> hacer(Future<void> Function() f) async {
      try {
        await f();
        if (mounted) setState(() => _v++);
      } catch (e) {
        if (mounted) avisar(this.context, mensajeDeError(e), tipo: TipoAviso.aviso);
      }
    }

    return FutureBuilder(
      key: ValueKey(_v),
      future: Future.wait([
        repo.filtroActivo(widget.eventoId),
        repo.agregadosAMano(widget.eventoId),
        repo.todosLosRelacionadores(club),
      ]),
      builder: (context, s) {
        if (!s.hasData) {
          return const SizedBox(height: 180, child: Center(child: CircularProgressIndicator()));
        }
        final activo = s.data![0] as bool;
        final manual = s.data![1] as Set<String>;
        final todos = s.data![2] as List<PersonaCaja>;
        final q = normalizar(_q.trim());
        final lista = q.length < 2
            ? todos.where((p) => manual.contains(p.id)).toList()
            : todos.where((p) => normalizar(p.persona.nombre).contains(q)).take(30).toList();
        return ListView(
          shrinkWrap: true,
          padding: EdgeInsets.fromLTRB(20, 0, 20, 24 + MediaQuery.of(context).viewInsets.bottom),
          children: [
            const Text('Lista de la caja', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Mostrar solo a quienes cargaron prepagadas'),
              subtitle: const Text('Vale para este evento. La puerta consulta la misma lista.'),
              value: activo,
              onChanged: (v) => hacer(() => repo.activarFiltro(widget.eventoId, v)),
            ),
            const Text('Agregados a mano', style: TextStyle(fontWeight: FontWeight.w800)),
            TextField(
              onChanged: (v) => setState(() => _q = v),
              decoration: const InputDecoration(
                  hintText: 'Buscar para agregar…', isDense: true,
                  prefixIcon: Icon(Icons.search_rounded)),
            ),
            if (lista.isEmpty)
              Padding(
                  padding: EdgeInsets.all(14),
                  child: Text('Nadie agregado a mano.',
                      style: TextStyle(color: VenueColors.textoSuave))),
            for (final p in lista)
              SwitchListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                title: Text(p.persona.nombre),
                subtitle: Text(p.persona.team),
                value: manual.contains(p.id),
                onChanged: (v) => hacer(() => repo.agregarAMano(widget.eventoId, p.id, v)),
              ),
          ],
        );
      },
    );
  }
}
