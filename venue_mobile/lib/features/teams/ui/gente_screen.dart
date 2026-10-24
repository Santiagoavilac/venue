import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show PostgrestException;

import '../../../core/networking/supabase.dart';
import '../../../core/theme/venue_theme.dart';
import '../../../core/widgets/avisos.dart';
import '../../../core/widgets/estado_vista.dart';
import '../../../core/widgets/patron.dart';
import '../../authentication/data/sesion.dart';
import '../../clubs/data/clubs.dart';
import '../../events/data/eventos.dart';
import '../data/equipo.dart';
import '../data/gente.dart';
import 'team_detalle_screen.dart';

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

String _error(Object e) => e is RechazoDelServidor ? e.motivo : mensajeDeError(e);

Future<String?> _pedirClave(BuildContext context, String nombre) {
  final t = TextEditingController();
  return showDialog<String>(
    context: context,
    builder: (c) => AlertDialog(
      title: Text('Nueva contraseña para $nombre'),
      content: TextField(
          controller: t,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'Mínimo 6 caracteres')),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c), child: const Text('Cancelar')),
        TextButton(
            onPressed: () => t.text.length < 6 ? null : Navigator.pop(c, t.text),
            child: const Text('Cambiar')),
      ],
    ),
  );
}

Future<void> _compartirInvitacion(BuildContext context, TeamInfo t, String boliche) async {
  await SharePlus.instance.share(ShareParams(text: mensajeDeInvitacion(t, boliche)));
}

// ═══════════════════════ MI TEAM (jefe) ═══════════════════════
/// El jefe gestiona a sus relacionadores: los suma, los pausa y les
/// restablece la contraseña.
class MiTeamScreen extends ConsumerWidget {
  const MiTeamScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final club = ref.watch(clubActivoProvider);
    final yo = ref.watch(usuarioIdProvider);
    final equipo = ref.watch(equipoProvider).value ?? const <String, Miembro>{};
    final teamId = equipo[yo]?.teamId;
    final gente = ref.watch(miTeamProvider);
    final ev = ref.watch(eventoActivoProvider);
    final repo = ref.read(genteRepositoryProvider);
    if (club == null) return const SizedBox.shrink();

    Future<void> hacer(Future<void> Function() f, String ok) async {
      try {
        await f();
        ref.invalidate(miTeamProvider);
        ref.invalidate(equipoProvider);
        if (context.mounted) avisar(context, ok);
      } catch (e) {
        if (context.mounted) avisar(context, _error(e), tipo: TipoAviso.aviso);
      }
    }

    return RefreshIndicator(
      onRefresh: () => ref.refresh(miTeamProvider.future),
      child: VistaAsync(
        valor: gente,
        reintentar: () => ref.invalidate(miTeamProvider),
        datos: (lista) => ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          children: [
            Text('${equipo[yo]?.team ?? 'Mi team'} · ${lista.length} relacionadores',
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
            const SizedBox(height: 10),
            if (teamId != null && club.usaRelacionadores && club.usaTeams) ...[
              _RepartoTeam(teamId: teamId, club: club, evento: ev),
              const SizedBox(height: 10),
            ],
            if (teamId != null)
              FutureBuilder(
                future: repo.team(teamId),
                builder: (context, s) {
                  final t = s.data;
                  if (t == null) return const SizedBox.shrink();
                  return Card(
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        const Text('Invitar a un relacionador',
                            style: TextStyle(fontWeight: FontWeight.w800)),
                        const SizedBox(height: 4),
                        Text(
                            'Mandale el link: se registra solo y queda en tu team.',
                            style: TextStyle(color: VenueColors.textoSuave)),
                        const SizedBox(height: 10),
                        Row(children: [
                          Expanded(
                            child: FilledButton.icon(
                              style: FilledButton.styleFrom(minimumSize: const Size(0, 46)),
                              onPressed: () => _compartirInvitacion(context, t, club.nombre),
                              icon: const Icon(Icons.ios_share_rounded, size: 18),
                              label: const Text('Compartir link'),
                            ),
                          ),
                          const SizedBox(width: 8),
                          OutlinedButton(
                            style: OutlinedButton.styleFrom(minimumSize: const Size(0, 46)),
                            onPressed: () async {
                              await Clipboard.setData(ClipboardData(text: t.invitacion));
                              if (context.mounted) avisar(context, 'Código copiado');
                            },
                            child: const Text('Copiar código'),
                          ),
                        ]),
                      ]),
                    ),
                  );
                },
              ),
            const SizedBox(height: 10),
            OutlinedButton.icon(
              onPressed: () async {
                final ok = await _hoja<bool>(context, const _AltaUsuario(deJefe: true));
                if (ok == true) {
                  ref.invalidate(miTeamProvider);
                  ref.invalidate(equipoProvider);
                }
              },
              icon: const Icon(Icons.person_add_alt_1_outlined),
              label: const Text('Crear relacionador'),
            ),
            const SizedBox(height: 8),
            if (lista.isEmpty)
              Padding(
                padding: EdgeInsets.all(24),
                child: Text('Todavía no tenés relacionadores en este boliche.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: VenueColors.textoSuave)),
              ),
            for (final g in lista)
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(g.nombre,
                    style: TextStyle(
                        fontWeight: FontWeight.w600,
                        color: g.activo ? null : VenueColors.textoSuave)),
                subtitle: Text('@${g.usuario}${g.activo ? '' : ' · en pausa'}'),
                onTap: () => abrirPersona(context, g.id, g.nombre, eventoId: ev?.id),
                trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                  IconButton(
                    tooltip: 'Restablecer contraseña',
                    icon: const Icon(Icons.key_outlined),
                    onPressed: () async {
                      final c = await _pedirClave(context, g.nombre);
                      if (c != null) {
                        await hacer(() => repo.resetearClave(g.id, c),
                            'Contraseña de ${g.nombre} cambiada');
                      }
                    },
                  ),
                  Switch(
                    value: g.activo,
                    onChanged: (v) => hacer(() => repo.activar(g.id, v),
                        v ? '${g.nombre} activado' : '${g.nombre} en pausa'),
                  ),
                ]),
              ),
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════ GENTE (admin) ═══════════════════════
class GenteScreen extends ConsumerWidget {
  const GenteScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final plataforma = ref.watch(plataformaProvider).value ?? false;
    return DefaultTabController(
      length: plataforma ? 3 : 2,
      child: NestedScrollView(
        headerSliverBuilder: (c, _) => [
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 20, 16, 4),
            sliver: SliverToBoxAdapter(child: _CabeceraGente(plataforma: plataforma)),
          ),
        ],
        body: TabBarView(children: [
          const _Usuarios(),
          const _Teams(),
          if (plataforma) const _Boliches(),
        ]),
      ),
    );
  }
}

/// Encabezado, indicadores y pestañas de "Usuarios y equipos": lo mismo que
/// la pantalla de la web.
class _CabeceraGente extends ConsumerWidget {
  const _CabeceraGente({required this.plataforma});
  final bool plataforma;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final club = ref.watch(clubActivoProvider);
    final usuarios = ref.watch(usuariosProvider).value ?? const <Usuario>[];
    final teams = ref.watch(teamsInfoProvider).value ?? const <TeamInfo>[];
    final equipo = ref.watch(equipoProvider).value ?? const <String, Miembro>{};
    String rolDe(Usuario u) => equipo[u.id]?.rol ?? u.rol;
    final admins = usuarios.where((u) => rolDe(u) == 'admin').length;
    final activos = usuarios.where((u) => u.activo).length;
    String pl(int n, String s) => '$n $s${n == 1 ? '' : 's'}';

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Encabezado(
        titulo: 'Usuarios',
        contexto: '${club?.nombre ?? ''} · ${pl(usuarios.length, 'usuario')} · ${pl(teams.length, 'team')}',
        acciones: [
          FilledButton.icon(
            style: FilledButton.styleFrom(minimumSize: const Size(0, 50)),
            onPressed: () async {
              if (await _hoja<bool>(context, const _AltaUsuario()) == true) {
                ref.invalidate(usuariosProvider);
                ref.invalidate(equipoProvider);
              }
            },
            icon: const Icon(Icons.add_rounded, size: 20),
            label: const Text('Nuevo usuario'),
          ),
        ],
      ),
      FilaFichas(children: [
        FichaDato(
            icono: Icons.person_outline_rounded, etiqueta: 'Usuarios', valor: '${usuarios.length}'),
        FichaDato(
            icono: Icons.groups_outlined, etiqueta: 'Teams', valor: '${teams.length}',
            color: VenueColors.info),
        FichaDato(
            icono: Icons.shield_outlined, etiqueta: 'Admins', valor: '$admins',
            color: VenueColors.aviso),
        FichaDato(
            icono: Icons.check_circle_outline, etiqueta: 'Activos', valor: '$activos',
            color: VenueColors.ok),
      ]),
      const SizedBox(height: 16),
      Align(
        alignment: Alignment.centerLeft,
        child: Container(
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            color: VenueColors.superficie2,
            borderRadius: BorderRadius.circular(11),
          ),
          child: TabBar(
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            dividerHeight: 0,
            indicatorSize: TabBarIndicatorSize.tab,
            labelPadding: const EdgeInsets.symmetric(horizontal: 22),
            indicator: BoxDecoration(
              color: Theme.of(context).brightness == Brightness.dark
                  ? VenueColors.superficieAlta
                  : VenueColors.superficie,
              borderRadius: BorderRadius.circular(8),
            ),
            tabs: [
              const Tab(text: 'Usuarios', height: 42),
              const Tab(text: 'Teams', height: 42),
              if (plataforma) const Tab(text: 'Boliches', height: 42),
            ],
          ),
        ),
      ),
    ]);
  }
}

/// Rol con su ícono: el admin con el color del boliche, el jefe en azul.
class _RolBadge extends StatelessWidget {
  const _RolBadge(this.rol);
  final String rol;

  @override
  Widget build(BuildContext context) {
    final r = Rol.desde(rol);
    final esq = Theme.of(context).colorScheme;
    final (color, fondo, borde) = switch (r) {
      Rol.admin => (
          Color.lerp(esq.secondary, Colors.white, .3)!,
          esq.primary.withValues(alpha: .12),
          esq.primary.withValues(alpha: .7)
        ),
      Rol.jefe => (VenueColors.info, VenueColors.info.withValues(alpha: .12), VenueColors.info.withValues(alpha: .35)),
      _ => (VenueColors.textoSuave, VenueColors.superficie2, VenueColors.linea),
    };
    final icono = switch (r) {
      Rol.admin || Rol.portero => Icons.shield_outlined,
      Rol.jefe => Icons.groups_outlined,
      Rol.caja => Icons.point_of_sale_outlined,
      Rol.barra || Rol.propietario => Icons.local_bar_outlined,
      Rol.deposito => Icons.inventory_2_outlined,
      _ => Icons.person_outline_rounded,
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: fondo,
        borderRadius: BorderRadius.circular(9),
        border: Border.all(color: borde),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icono, size: 15, color: color),
        const SizedBox(width: 6),
        Text(r?.etiqueta ?? rol,
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: color)),
      ]),
    );
  }
}

class _Usuarios extends ConsumerStatefulWidget {
  const _Usuarios();
  @override
  ConsumerState<_Usuarios> createState() => _UsuariosState();
}

class _UsuariosState extends ConsumerState<_Usuarios> {
  String _q = '';

  /// Grupos (teams) desplegados. Arrancan plegados para no tener la lista
  /// entera encima; al buscar se abren todos.
  final _abiertos = <String>{};

  @override
  Widget build(BuildContext context) {
    final usuarios = ref.watch(usuariosProvider);
    final equipo = ref.watch(equipoProvider).value ?? const <String, Miembro>{};
    final yo = ref.watch(usuarioIdProvider);
    final tabla = MediaQuery.sizeOf(context).width >= 900;
    void recargar() {
      ref.invalidate(usuariosProvider);
      ref.invalidate(equipoProvider);
    }

    return VistaAsync(
      valor: usuarios,
      reintentar: recargar,
      datos: (todos) {
        final q = normalizar(_q.trim());
        final lista = q.isEmpty
            ? todos
            : todos.where((u) => normalizar(
                    '${u.nombre} @${u.usuario} ${u.rolEtiqueta} ${equipo[u.id]?.team ?? ''}')
                .contains(q)).toList();

        Future<void> abrir(Usuario u) async {
          if (await _hoja<bool>(context, _EditarUsuario(usuario: u)) == true) recargar();
        }

        Widget fila(Usuario u) {
          final rol = equipo[u.id]?.rol ?? u.rol;
          final team = equipo[u.id]?.teamId != null ? equipo[u.id]!.team : null;
          final nombre = Row(children: [
            Flexible(
              child: Text(u.nombre,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      fontSize: 15.5,
                      fontWeight: FontWeight.w600,
                      color: u.activo ? null : VenueColors.textoSuave)),
            ),
            if (u.id == yo) ...[
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: VenueColors.superficie2,
                  borderRadius: BorderRadius.circular(7),
                  border: Border.all(color: VenueColors.linea),
                ),
                child: Text('Vos',
                    style: TextStyle(fontSize: 11.5, color: VenueColors.textoSuave)),
              ),
            ],
          ]);
          final teamW = Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.groups_outlined, size: 16, color: VenueColors.textoTenue),
            const SizedBox(width: 6),
            Flexible(
              child: Text(team ?? 'Sin team',
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 13.5, color: VenueColors.textoSuave)),
            ),
          ]);
          final estado = u.activo
              ? const PillEstado('Activo')
              : const PillEstado('Pausado', tono: Tono.neutro);
          if (tabla) {
            return InkWell(
              onTap: () => abrir(u),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                decoration: BoxDecoration(
                    border: Border(bottom: BorderSide(color: VenueColors.lineaSuave))),
                child: Row(children: [
                  Inicial(u.nombre, lado: 42),
                  const SizedBox(width: 16),
                  Expanded(flex: 15, child: nombre),
                  Expanded(
                      flex: 11,
                      child: Text('@${u.usuario}',
                          style: TextStyle(color: VenueColors.textoSuave, fontSize: 14))),
                  Expanded(flex: 11, child: Align(alignment: Alignment.centerLeft, child: _RolBadge(rol))),
                  Expanded(flex: 10, child: teamW),
                  Expanded(flex: 8, child: Align(alignment: Alignment.centerLeft, child: estado)),
                  Icon(Icons.more_horiz_rounded, color: VenueColors.textoSuave),
                ]),
              ),
            );
          }
          return Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Material(
              color: VenueColors.superficie,
              elevation: elevacionTarjeta,
              shadowColor: const Color(0x29101828),
              shape: formaTarjeta,
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: () => abrir(u),
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Inicial(u.nombre),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Row(children: [
                          Expanded(child: nombre),
                          const SizedBox(width: 8),
                          estado,
                        ]),
                        const SizedBox(height: 3),
                        Text('@${u.usuario}',
                            style: TextStyle(fontSize: 13, color: VenueColors.textoTenue)),
                        const SizedBox(height: 9),
                        Wrap(
                          spacing: 12,
                          runSpacing: 6,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [_RolBadge(rol), teamW],
                        ),
                      ]),
                    ),
                  ]),
                ),
              ),
            ),
          );
        }

        return ListView(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
          children: [
            TextField(
              onChanged: (v) => setState(() => _q = v),
              autocorrect: false,
              decoration: InputDecoration(
                hintText: 'Buscar por nombre, usuario, rol o team…',
                prefixIcon: const Icon(Icons.search_rounded),
                suffixText: '${lista.length}',
              ),
            ),
            const SizedBox(height: 14),
            if (tabla)
              Container(
                decoration: BoxDecoration(
                  color: VenueColors.superficie,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: VenueColors.linea),
                ),
                clipBehavior: Clip.antiAlias,
                child: Column(children: [
                  const Padding(
                    padding: EdgeInsets.fromLTRB(78, 16, 20, 12),
                    child: Row(children: [
                      Expanded(flex: 15, child: _Cab('Nombre')),
                      Expanded(flex: 11, child: _Cab('Usuario')),
                      Expanded(flex: 11, child: _Cab('Rol')),
                      Expanded(flex: 10, child: _Cab('Team')),
                      Expanded(flex: 8, child: _Cab('Estado')),
                      SizedBox(width: 24),
                    ]),
                  ),
                  Divider(height: 1, color: VenueColors.linea),
                  for (final u in lista) fila(u),
                ]),
              )
            else
              ..._grupos(lista, equipo, fila, abiertosTodos: q.isNotEmpty),
          ],
        );
      },
    );
  }

  /// La gente agrupada por team (sin team al final), cada grupo plegable.
  List<Widget> _grupos(List<Usuario> lista, Map<String, Miembro> equipo,
      Widget Function(Usuario) fila, {required bool abiertosTodos}) {
    const sinTeam = 'Sin team';
    final porTeam = <String, List<Usuario>>{};
    for (final u in lista) {
      final t = equipo[u.id]?.teamId != null ? equipo[u.id]!.team : sinTeam;
      (porTeam[t] ??= []).add(u);
    }
    final nombres = porTeam.keys.toList()
      ..sort((a, b) => a == sinTeam ? 1 : b == sinTeam ? -1 : a.compareTo(b));
    return [
      for (final t in nombres) ...[
        _CabeceraGrupo(
          titulo: t,
          cantidad: porTeam[t]!.length,
          activos: porTeam[t]!.where((u) => u.activo).length,
          abierto: abiertosTodos || _abiertos.contains(t),
          alTocar: abiertosTodos
              ? null
              : () => setState(() => _abiertos.contains(t) ? _abiertos.remove(t) : _abiertos.add(t)),
        ),
        if (abiertosTodos || _abiertos.contains(t)) ...[
          for (final u in porTeam[t]!) fila(u),
          const SizedBox(height: 6),
        ],
      ],
    ];
  }
}

class _CabeceraGrupo extends StatelessWidget {
  const _CabeceraGrupo({
    required this.titulo,
    required this.cantidad,
    required this.activos,
    required this.abierto,
    this.alTocar,
  });
  final String titulo;
  final int cantidad, activos;
  final bool abierto;
  final VoidCallback? alTocar;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Tarjeta(
          padding: EdgeInsets.zero,
          child: InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: alTocar,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
              child: Row(children: [
                Inicial(titulo, lado: 34),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(titulo, style: const TextStyle(fontSize: 15.5, fontWeight: FontWeight.w600)),
                    Text(
                      '$cantidad ${cantidad == 1 ? 'persona' : 'personas'}'
                      '${activos < cantidad ? ' · ${cantidad - activos} en pausa' : ''}',
                      style: TextStyle(fontSize: 13, color: VenueColors.textoSuave),
                    ),
                  ]),
                ),
                AnimatedRotation(
                  turns: abierto ? .5 : 0,
                  duration: const Duration(milliseconds: 180),
                  child: Icon(Icons.keyboard_arrow_down_rounded, color: VenueColors.textoSuave),
                ),
              ]),
            ),
          ),
        ),
      );
}

class _Cab extends StatelessWidget {
  const _Cab(this.t);
  final String t;
  @override
  Widget build(BuildContext context) => Text(t.toUpperCase(),
      style: TextStyle(
          fontSize: 11.5, fontWeight: FontWeight.w600, letterSpacing: 1, color: VenueColors.textoTenue));
}

/// Alta de una cuenta. Para el jefe: siempre relacionador de su team.
class _AltaUsuario extends ConsumerStatefulWidget {
  const _AltaUsuario({this.deJefe = false});
  final bool deJefe;
  @override
  ConsumerState<_AltaUsuario> createState() => _AltaUsuarioState();
}

class _AltaUsuarioState extends ConsumerState<_AltaUsuario> {
  final _n = TextEditingController(), _u = TextEditingController(), _c = TextEditingController();
  String _rol = 'rrpp';
  String? _team;
  bool _ocupado = false;

  @override
  void dispose() {
    for (final x in [_n, _u, _c]) {
      x.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final club = ref.watch(clubActivoIdProvider)!;
    final teams = ref.watch(teamsInfoProvider).value ?? const <TeamInfo>[];
    final plataforma = ref.watch(plataformaProvider).value ?? false;
    return ListView(
      shrinkWrap: true,
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
      children: [
        Text(widget.deJefe ? 'Crear relacionador' : 'Nuevo usuario',
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
        const SizedBox(height: 12),
        TextField(
            controller: _n,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(labelText: 'Nombre y apellido')),
        const SizedBox(height: 10),
        TextField(
            controller: _u,
            autocorrect: false,
            decoration: const InputDecoration(labelText: 'Usuario (corto, sin espacios)')),
        const SizedBox(height: 10),
        TextField(
            controller: _c, decoration: const InputDecoration(labelText: 'Contraseña (mín. 6)')),
        if (!widget.deJefe) ...[
          const SizedBox(height: 10),
          Row(children: [
            Expanded(
              child: DropdownButtonFormField<String>(
                borderRadius: BorderRadius.circular(12),
                dropdownColor: VenueColors.superficie,
                icon: Icon(Icons.keyboard_arrow_down_rounded, color: VenueColors.textoSuave),
                menuMaxHeight: 420,
                initialValue: _rol,
                decoration: const InputDecoration(labelText: 'Rol'),
                items: [
                  for (final r in rolesAsignables.where((r) => r != 'admin' || plataforma))
                    DropdownMenuItem(value: r, child: Text(Rol.desde(r)?.etiqueta ?? r)),
                ],
                onChanged: (v) => setState(() => _rol = v!),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: DropdownButtonFormField<String?>(
                borderRadius: BorderRadius.circular(12),
                dropdownColor: VenueColors.superficie,
                icon: Icon(Icons.keyboard_arrow_down_rounded, color: VenueColors.textoSuave),
                menuMaxHeight: 420,
                initialValue: _team,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Team'),
                items: [
                  const DropdownMenuItem<String?>(value: null, child: Text('— sin team —')),
                  for (final t in teams)
                    DropdownMenuItem<String?>(
                        value: t.id, child: Text(t.nombre, overflow: TextOverflow.ellipsis)),
                ],
                onChanged: (v) => setState(() => _team = v),
              ),
            ),
          ]),
        ],
        const SizedBox(height: 16),
        FilledButton(
          onPressed: _ocupado
              ? null
              : () async {
                  if (_n.text.trim().isEmpty || _u.text.trim().length < 3 || _c.text.length < 6) {
                    avisar(context, 'Completá nombre, usuario y clave (6+)',
                        tipo: TipoAviso.aviso);
                    return;
                  }
                  setState(() => _ocupado = true);
                  try {
                    final u = await ref.read(genteRepositoryProvider).crear(
                          usuario: _u.text, nombre: _n.text.trim(), clave: _c.text,
                          rol: widget.deJefe ? 'rrpp' : _rol,
                          teamId: widget.deJefe ? null : _team,
                          // sin team hay que decirle en qué boliche opera
                          clubs: widget.deJefe || _team != null ? null : [club],
                        );
                    if (!context.mounted) return;
                    Navigator.pop(context, true);
                    avisar(context, '@$u creado');
                  } catch (e) {
                    if (context.mounted) {
                      avisar(context, _error(e), tipo: TipoAviso.aviso);
                      setState(() => _ocupado = false);
                    }
                  }
                },
          child: const Text('Crear usuario'),
        ),
      ],
    );
  }
}

class _EditarUsuario extends ConsumerStatefulWidget {
  const _EditarUsuario({required this.usuario});
  final Usuario usuario;
  @override
  ConsumerState<_EditarUsuario> createState() => _EditarUsuarioState();
}

class _EditarUsuarioState extends ConsumerState<_EditarUsuario> {
  late final g = widget.usuario;
  late final _nombre = TextEditingController(text: g.nombre);
  late String _rol = g.rol;
  late String? _team = g.teamId;
  late final _clubs = {...g.clubs};
  final _rolEn = <String, String>{}, _teamEn = <String, String?>{};
  bool _ocupado = false, _cargado = false;

  @override
  void initState() {
    super.initState();
    ref.read(genteRepositoryProvider).membresias(g.id).then((ms) {
      if (!mounted) return;
      setState(() {
        for (final m in ms) {
          _rolEn[m.clubId] = m.rol;
          _teamEn[m.clubId] = m.teamId;
        }
        _cargado = true;
      });
    });
  }

  @override
  void dispose() {
    _nombre.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final clubs = ref.watch(clubsProvider).value ?? const <Club>[];
    final teams = ref.watch(teamsInfoProvider).value ?? const <TeamInfo>[];
    final plataforma = ref.watch(plataformaProvider).value ?? false;
    final yo = ref.watch(usuarioIdProvider);
    final repo = ref.read(genteRepositoryProvider);
    // la cuenta principal solo la toca su dueño
    final protegida = g.adminPrincipal && g.id != yo;
    final porBoliche = _clubs.length >= 2 && _rol != 'admin';
    final roles = rolesAsignables.where((r) => r != 'admin' || plataforma || g.rol == 'admin').toList();

    Future<void> hacer(Future<void> Function() f, String ok) async {
      setState(() => _ocupado = true);
      try {
        await f();
        if (!context.mounted) return;
        Navigator.pop(context, true);
        avisar(context, ok);
      } catch (e) {
        if (context.mounted) {
          avisar(context, _error(e), tipo: TipoAviso.aviso);
          setState(() => _ocupado = false);
        }
      }
    }

    return ListView(
      shrinkWrap: true,
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
      children: [
        Text('@${g.usuario}', style: TextStyle(color: VenueColors.textoSuave)),
        if (protegida)
          Padding(
            padding: EdgeInsets.symmetric(vertical: 10),
            child: Text('Esta cuenta administrativa está protegida: solo su dueño puede modificarla.',
                style: TextStyle(color: VenueColors.aviso)),
          ),
        const SizedBox(height: 8),
        TextField(
            controller: _nombre,
            enabled: !protegida,
            decoration: const InputDecoration(labelText: 'Nombre')),
        const SizedBox(height: 10),
        Row(children: [
          Expanded(
            child: DropdownButtonFormField<String>(
              borderRadius: BorderRadius.circular(12),
              dropdownColor: VenueColors.superficie,
              icon: Icon(Icons.keyboard_arrow_down_rounded, color: VenueColors.textoSuave),
              menuMaxHeight: 420,
              initialValue: roles.contains(_rol) ? _rol : null,
              decoration: const InputDecoration(labelText: 'Rol base'),
              items: [
                for (final r in roles)
                  DropdownMenuItem(value: r, child: Text(Rol.desde(r)?.etiqueta ?? r)),
              ],
              onChanged: protegida ? null : (v) => setState(() => _rol = v!),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: DropdownButtonFormField<String?>(
              borderRadius: BorderRadius.circular(12),
              dropdownColor: VenueColors.superficie,
              icon: Icon(Icons.keyboard_arrow_down_rounded, color: VenueColors.textoSuave),
              menuMaxHeight: 420,
              initialValue: teams.any((t) => t.id == _team) ? _team : null,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Team base'),
              items: [
                const DropdownMenuItem<String?>(value: null, child: Text('— sin team —')),
                for (final t in teams)
                  DropdownMenuItem<String?>(
                      value: t.id, child: Text(t.nombre, overflow: TextOverflow.ellipsis)),
              ],
              onChanged: protegida ? null : (v) => setState(() => _team = v),
            ),
          ),
        ]),
        const SizedBox(height: 12),
        const Text('Boliches donde opera'),
        Wrap(spacing: 8, children: [
          for (final c in clubs)
            FilterChip(
              label: Text(c.nombre),
              selected: _clubs.contains(c.id),
              onSelected: protegida
                  ? null
                  : (v) => setState(() => v ? _clubs.add(c.id) : _clubs.remove(c.id)),
            ),
        ]),
        if (porBoliche && _cargado) ...[
          const SizedBox(height: 8),
          const Text('Rol y team en cada boliche',
              style: TextStyle(fontWeight: FontWeight.w700)),
          for (final c in clubs.where((c) => _clubs.contains(c.id)))
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Row(children: [
                SizedBox(width: 86, child: Text(c.nombre, overflow: TextOverflow.ellipsis)),
                Expanded(
                  child: DropdownButtonFormField<String>(
                    borderRadius: BorderRadius.circular(12),
                    dropdownColor: VenueColors.superficie,
                    icon: Icon(Icons.keyboard_arrow_down_rounded, color: VenueColors.textoSuave),
                    menuMaxHeight: 420,
                    initialValue: _rolEn[c.id] ?? _rol,
                    isExpanded: true,
                    decoration: const InputDecoration(isDense: true),
                    items: [
                      for (final r in rolesAsignables.where((r) => r != 'admin'))
                        DropdownMenuItem(value: r, child: Text(Rol.desde(r)?.etiqueta ?? r)),
                    ],
                    onChanged: (v) => setState(() => _rolEn[c.id] = v!),
                  ),
                ),
              ]),
            ),
        ],
        const SizedBox(height: 16),
        if (!protegida) ...[
          FilledButton(
            onPressed: _ocupado
                ? null
                : () {
                    if (_nombre.text.trim().isEmpty) {
                      avisar(context, 'Poné el nombre', tipo: TipoAviso.aviso);
                      return;
                    }
                    if (_clubs.isEmpty) {
                      avisar(context, 'Elegí al menos un boliche', tipo: TipoAviso.aviso);
                      return;
                    }
                    hacer(
                        () => repo.editar(
                              g.id,
                              nombre: _nombre.text.trim(), rol: _rol, teamId: _team,
                              clubs: _clubs.toList(),
                              porBoliche: [
                                for (final c in _clubs)
                                  Membresia(
                                      clubId: c,
                                      rol: _rolEn[c] ?? _rol,
                                      teamId: _teamEn[c] ?? _team),
                              ],
                            ),
                        'Usuario actualizado');
                  },
            child: const Text('Guardar'),
          ),
          const SizedBox(height: 9),
          Row(children: [
            Expanded(
              child: OutlinedButton(
                onPressed: _ocupado
                    ? null
                    : () async {
                        final c = await _pedirClave(context, g.nombre);
                        if (c != null) {
                          await hacer(() => repo.resetearClave(g.id, c), 'Contraseña cambiada');
                        }
                      },
                child: const Text('Cambiar clave'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: OutlinedButton(
                onPressed: _ocupado
                    ? null
                    : () => hacer(() => repo.activar(g.id, !g.activo),
                        g.activo ? '${g.nombre} en pausa' : '${g.nombre} activado'),
                child: Text(g.activo ? 'Pausar' : 'Activar'),
              ),
            ),
          ]),
          const SizedBox(height: 9),
          OutlinedButton(
            style: OutlinedButton.styleFrom(foregroundColor: VenueColors.mal),
            onPressed: _ocupado
                ? null
                : () async {
                    final si = await showDialog<bool>(
                      context: context,
                      builder: (c) => AlertDialog(
                        title: Text('Eliminar a ${g.nombre}'),
                        content: Text(
                            '@${g.usuario} · ${g.rolEtiqueta}\n\nSi tiene ventas o invitados, la cuenta se archiva y su historia queda con su nombre. Si no, se borra por completo.'),
                        actions: [
                          TextButton(
                              onPressed: () => Navigator.pop(c, false),
                              child: const Text('Cancelar')),
                          TextButton(
                              onPressed: () => Navigator.pop(c, true),
                              style: TextButton.styleFrom(foregroundColor: VenueColors.mal),
                              child: const Text('Eliminar usuario')),
                        ],
                      ),
                    );
                    if (si != true) return;
                    setState(() => _ocupado = true);
                    try {
                      final modo = await repo.eliminar(g.id);
                      if (!context.mounted) return;
                      Navigator.pop(context, true);
                      avisar(
                          context,
                          modo == 'archivado'
                              ? '${g.nombre} eliminado — sus manillas y listas quedan con su nombre'
                              : '${g.nombre} eliminado',
                          tipo: TipoAviso.aviso);
                    } catch (e) {
                      if (context.mounted) {
                        avisar(context, _error(e), tipo: TipoAviso.aviso);
                        setState(() => _ocupado = false);
                      }
                    }
                  },
            child: const Text('Eliminar usuario'),
          ),
        ],
      ],
    );
  }
}

// ── teams ──
class _Teams extends ConsumerWidget {
  const _Teams();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final teams = ref.watch(teamsInfoProvider);
    final club = ref.watch(clubActivoProvider);
    final equipo = ref.watch(equipoProvider).value ?? const <String, Miembro>{};
    final clubs = ref.watch(clubsProvider).value ?? const <Club>[];
    final repo = ref.read(genteRepositoryProvider);
    if (club == null) return const SizedBox.shrink();
    void recargar() {
      ref.invalidate(teamsInfoProvider);
      ref.invalidate(equipoProvider);
    }

    Future<void> hacer(Future<void> Function() f, String ok) async {
      try {
        await f();
        recargar();
        if (context.mounted) avisar(context, ok);
      } catch (e) {
        if (context.mounted) avisar(context, _error(e), tipo: TipoAviso.aviso);
      }
    }

    Future<void> formulario([TeamInfo? t]) async {
      final nombre = TextEditingController(text: t?.nombre ?? '');
      final sel = {...?t?.clubs, if (t == null) club.id};
      final ok = await showDialog<bool>(
        context: context,
        builder: (c) => StatefulBuilder(
          builder: (c, set) => AlertDialog(
            title: Text(t == null ? 'Nuevo team' : 'Editar team'),
            content: Column(mainAxisSize: MainAxisSize.min, children: [
              TextField(
                  controller: nombre,
                  autofocus: true,
                  decoration: const InputDecoration(labelText: 'Nombre')),
              if (t != null) ...[
                const SizedBox(height: 10),
                Wrap(spacing: 8, children: [
                  for (final b in clubs)
                    FilterChip(
                        label: Text(b.nombre),
                        selected: sel.contains(b.id),
                        onSelected: (v) => set(() => v ? sel.add(b.id) : sel.remove(b.id))),
                ]),
              ],
            ]),
            actions: [
              TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancelar')),
              TextButton(onPressed: () => Navigator.pop(c, true), child: const Text('Guardar')),
            ],
          ),
        ),
      );
      final n = nombre.text.trim();
      if (ok != true || n.isEmpty) return;
      await hacer(
          () => t == null ? repo.crearTeam(n, club.id) : repo.editarTeam(t.id, n, sel.toList()),
          t == null ? 'Team creado' : 'Team actualizado');
    }

    return VistaAsync(
      valor: teams,
      reintentar: recargar,
      datos: (lista) => ListView(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 24),
        children: [
          OutlinedButton.icon(
            onPressed: formulario,
            icon: const Icon(Icons.group_add_outlined),
            label: const Text('Nuevo team'),
          ),
          for (final t in lista)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Tarjeta(
                padding: EdgeInsets.zero,
                child: InkWell(
                  borderRadius: BorderRadius.circular(14),
                  onTap: () => abrirTeam(context, t),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(14, 10, 4, 10),
                    child: Row(children: [
                          Inicial(t.nombre, lado: 38),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Text(t.nombre,
                                  style: const TextStyle(fontSize: 15.5, fontWeight: FontWeight.w600)),
                              const SizedBox(height: 1),
                              Text(
                                '${equipo.values.where((m) => m.teamId == t.id).length} personas'
                                '${equipo[t.jefeId] == null ? '' : ' · jefe ${equipo[t.jefeId]!.nombre}'}',
                                style: TextStyle(fontSize: 13, color: VenueColors.textoSuave),
                              ),
                            ]),
                          ),
                          IconButton(
                              tooltip: 'Compartir invitación',
                              onPressed: () => _compartirInvitacion(context, t, club.nombre),
                              icon: Icon(Icons.ios_share_rounded, size: 20, color: VenueColors.textoSuave)),
                          PopupMenuButton<String>(
                            onSelected: (k) async {
                              if (k == 'editar') return formulario(t);
                              final otros = lista.where((x) => x.id != t.id).toList();
                              String? destino;
                              final si = await showDialog<bool>(
                                context: context,
                                builder: (c) => StatefulBuilder(
                                  builder: (c, set) => AlertDialog(
                                    title: Text('Eliminar ${t.nombre}'),
                                    content: Column(mainAxisSize: MainAxisSize.min, children: [
                                      const Text('Su gente pasa al team que elijas, o queda sin team.'),
                                      const SizedBox(height: 10),
                                      DropdownButtonFormField<String?>(
                                        borderRadius: BorderRadius.circular(12),
                                        dropdownColor: VenueColors.superficie,
                                        icon: Icon(Icons.keyboard_arrow_down_rounded, color: VenueColors.textoSuave),
                                        menuMaxHeight: 420,
                                        initialValue: destino,
                                        isExpanded: true,
                                        items: [
                                          const DropdownMenuItem<String?>(
                                              value: null, child: Text('— dejar sin team —')),
                                          for (final o in otros)
                                            DropdownMenuItem<String?>(value: o.id, child: Text(o.nombre)),
                                        ],
                                        onChanged: (v) => set(() => destino = v),
                                      ),
                                    ]),
                                    actions: [
                                      TextButton(
                                          onPressed: () => Navigator.pop(c, false),
                                          child: const Text('Cancelar')),
                                      TextButton(
                                          onPressed: () => Navigator.pop(c, true),
                                          style: TextButton.styleFrom(foregroundColor: VenueColors.mal),
                                          child: const Text('Eliminar team')),
                                    ],
                                  ),
                                ),
                              );
                              if (si == true) {
                                await hacer(() => repo.eliminarTeam(t.id, destino: destino),
                                    '${t.nombre} eliminado');
                              }
                            },
                            itemBuilder: (_) => const [
                              PopupMenuItem(value: 'editar', child: Text('Editar')),
                              PopupMenuItem(value: 'eliminar', child: Text('Eliminar')),
                            ],
                          ),
                          Icon(Icons.chevron_right_rounded, color: VenueColors.textoTenue),
                    ]),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// ── boliches (plataforma) ──
class _Boliches extends ConsumerWidget {
  const _Boliches();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final clubs = ref.watch(clubsProvider);
    Future<void> abrir([Club? c]) async {
      if (await _hoja<bool>(context, _BolicheForm(club: c)) == true) {
        ref.invalidate(clubsProvider);
      }
    }

    return VistaAsync(
      valor: clubs,
      reintentar: () => ref.invalidate(clubsProvider),
      datos: (lista) => ListView(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 24),
        children: [
          OutlinedButton.icon(
            onPressed: abrir,
            icon: const Icon(Icons.add_business_outlined),
            label: const Text('Nuevo boliche'),
          ),
          for (final c in lista)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: CircleAvatar(
                  backgroundColor: c.primario ?? VenueColors.marcaPorDefecto,
                  child: Text(c.inicial,
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800))),
              title: Text(c.nombre, style: const TextStyle(fontWeight: FontWeight.w700)),
              subtitle: Text([c.id, if (c.subtitulo?.isNotEmpty ?? false) c.subtitulo!].join(' · ')),
              trailing: const Icon(Icons.edit_outlined),
              onTap: () => abrir(c),
            ),
        ],
      ),
    );
  }
}

/// Alta de boliche desde fuera de esta pantalla (el selector de boliche).
/// Devuelve true si se creó.
Future<bool?> abrirNuevoBoliche(BuildContext context) =>
    _hoja<bool>(context, const _BolicheForm());

String _hex(Color? c, String defecto) => c == null
    ? defecto
    : '#${(c.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase()}';

class _BolicheForm extends ConsumerStatefulWidget {
  const _BolicheForm({this.club});
  final Club? club;
  @override
  ConsumerState<_BolicheForm> createState() => _BolicheFormState();
}

class _BolicheFormState extends ConsumerState<_BolicheForm> {
  late final c = widget.club;
  late final _nombre = TextEditingController(text: c?.nombre ?? '');
  late final _id = TextEditingController(text: c?.id ?? '');
  late final _sub = TextEditingController(text: c?.subtitulo ?? '');
  late final _p = TextEditingController(text: _hex(c?.primario, '#7C3AED'));
  late final _s = TextEditingController(text: _hex(c?.secundario, '#A855F7'));
  final _a = TextEditingController(text: '#22D3EE');
  bool _ocupado = false;
  bool _idTocado = false;
  late final _opciones = {
    'usa_relacionadores': c?.usaRelacionadores ?? true,
    'usa_teams': c?.usaTeams ?? true,
    'comision_manillas': c?.comisionManillas ?? true,
    'comision_combos': c?.comisionCombos ?? true,
  };

  @override
  void initState() {
    super.initState();
    // igual que la web: el identificador se arma solo desde el nombre hasta
    // que la persona lo edita a mano
    if (c == null) {
      _nombre.addListener(() {
        if (!_idTocado) _id.text = _slug(_nombre.text);
      });
    }
  }

  static String _slug(String t) {
    const de = 'áàäâãéèëêíìïîóòöôõúùüûñç', a = 'aaaaaeeeeiiiiooooouuuunc';
    final b = StringBuffer();
    for (final ch in t.trim().toLowerCase().split('')) {
      final i = de.indexOf(ch);
      b.write(i >= 0 ? a[i] : ch);
    }
    final r = b.toString().replaceAll(RegExp(r'[^a-z0-9]+'), '-').replaceAll(RegExp(r'^-+|-+$'), '');
    return r.length > 30 ? r.substring(0, 30) : r;
  }

  @override
  void dispose() {
    for (final x in [_nombre, _id, _sub, _p, _s, _a]) {
      x.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final repo = ref.read(genteRepositoryProvider);
    Future<void> hacer(Future<void> Function() f, String ok) async {
      setState(() => _ocupado = true);
      try {
        await f();
        if (!context.mounted) return;
        Navigator.pop(context, true);
        avisar(context, ok);
      } catch (e) {
        if (context.mounted) {
          avisar(
              context,
              e is PostgrestException && e.code == '23505'
                  ? 'Ya existe un boliche con el slug "${_id.text.trim()}"'
                  : _error(e),
              tipo: TipoAviso.aviso);
          setState(() => _ocupado = false);
        }
      }
    }

    Widget color(String l, TextEditingController t) => Expanded(
          child: TextField(
            controller: t,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              labelText: l,
              suffixIcon: Padding(
                padding: const EdgeInsets.all(12),
                child: CircleAvatar(
                    radius: 9,
                    backgroundColor: colorDesdeHex(t.text) ?? Colors.transparent),
              ),
            ),
          ),
        );

    return ListView(
      shrinkWrap: true,
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
      children: [
        Text(c == null ? 'Nuevo boliche' : 'Editar boliche',
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
        const SizedBox(height: 12),
        TextField(controller: _nombre, decoration: const InputDecoration(labelText: 'Nombre')),
        const SizedBox(height: 10),
        TextField(
          controller: _id,
          enabled: c == null,
          onChanged: (_) => _idTocado = true,
          autocorrect: false,
          decoration: const InputDecoration(
              labelText: 'Identificador',
              helperText: 'Minúsculas, números y guiones. No se puede cambiar después.'),
        ),
        const SizedBox(height: 10),
        TextField(
            controller: _sub,
            decoration: const InputDecoration(labelText: 'Subtítulo (zona, ciudad…)')),
        const SizedBox(height: 10),
        Row(children: [color('Primario', _p), const SizedBox(width: 8), color('Secundario', _s)]),
        const SizedBox(height: 10),
        Row(children: [color('Acento', _a), const Spacer()]),
        const SizedBox(height: 16),
        if (c == null) ...[
          const Text('Cómo trabaja', style: TextStyle(fontWeight: FontWeight.w700)),
          OpcionesBoliche(
            valores: _opciones,
            alCambiar: (k, v) => setState(() => _opciones[k] = v),
          ),
          const SizedBox(height: 10),
        ],
        FilledButton(
          onPressed: _ocupado
              ? null
              : () {
                  final nombre = _nombre.text.trim(), id = _id.text.trim();
                  if (nombre.isEmpty || !slugValido(id)) {
                    avisar(context, 'Completá el nombre y un identificador válido',
                        tipo: TipoAviso.aviso);
                    return;
                  }
                  if (![_p, _s, _a].every((t) => colorValido(t.text.trim()))) {
                    avisar(context, 'Los colores van como #RRGGBB', tipo: TipoAviso.aviso);
                    return;
                  }
                  final sub = _sub.text.trim().isEmpty ? null : _sub.text.trim();
                  hacer(
                      () => c == null
                          ? repo
                              .crearClub(
                                  id: id, nombre: nombre, subtitulo: sub, primario: _p.text.trim(),
                                  secundario: _s.text.trim(), acento: _a.text.trim(),
                                  opciones: _opciones)
                              .then((completo) {
                              if (!completo && context.mounted) {
                                avisar(context, 'Se creó con la configuración de siempre: falta db/33 en la base',
                                    tipo: TipoAviso.aviso);
                              }
                            })
                          : repo.editarClub(c!.id,
                              nombre: nombre, subtitulo: sub, primario: _p.text.trim(),
                              secundario: _s.text.trim(), acento: _a.text.trim()),
                      c == null ? 'Boliche creado' : 'Boliche actualizado');
                },
          child: const Text('Guardar'),
        ),
        if (c != null) ...[
          const SizedBox(height: 9),
          OutlinedButton(
            style: OutlinedButton.styleFrom(foregroundColor: VenueColors.mal),
            onPressed: _ocupado
                ? null
                : () => hacer(() => repo.desactivarClub(c!.id), '${c!.nombre} desactivado'),
            child: const Text('Desactivar boliche'),
          ),
        ],
      ],
    );
  }
}


/// Las cuatro opciones de cómo trabaja un boliche con relacionadores.
class OpcionesBoliche extends StatelessWidget {
  const OpcionesBoliche({super.key, required this.valores, required this.alCambiar});
  final Map<String, bool> valores;
  final void Function(String clave, bool valor) alCambiar;

  static const textos = {
    'usa_relacionadores': ('Trabaja con relacionadores', 'Si no, venden el admin y el personal, sin comisiones'),
    'usa_teams': ('Con teams y jefes', 'Sin teams, cada relacionador cobra su comisión entera'),
    'comision_manillas': ('Comisión por manilla', 'Lo que no es del boliche de cada manilla'),
    'comision_combos': ('Comisión por combo', 'La comisión de cada combo de mesa'),
  };

  @override
  Widget build(BuildContext context) => Column(children: [
        for (final e in textos.entries)
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(e.value.$1, style: const TextStyle(fontWeight: FontWeight.w600)),
            subtitle: Text(e.value.$2, style: TextStyle(color: VenueColors.textoSuave, fontSize: 13)),
            value: valores[e.key] ?? true,
            // sin relacionadores, lo demás no aplica
            onChanged: e.key != 'usa_relacionadores' && !(valores['usa_relacionadores'] ?? true)
                ? null
                : (v) => alCambiar(e.key, v),
          ),
      ]);
}


/// Reparto del jefe: de la comisión del team por manilla (lo que no es del
/// boliche) y por combo, cuánto va a cada relacionador. El resto es del
/// jefe; lo que vende el jefe es todo suyo. Vacío = la regla de siempre.
class _RepartoTeam extends ConsumerStatefulWidget {
  const _RepartoTeam({required this.teamId, required this.club, required this.evento});
  final String teamId;
  final Club club;
  final Evento? evento;

  @override
  ConsumerState<_RepartoTeam> createState() => _RepartoTeamState();
}

class _RepartoTeamState extends ConsumerState<_RepartoTeam> {
  final _man = TextEditingController();
  final _combo = TextEditingController();
  bool _cargado = false, _sinBase = false, _ocupado = false;

  @override
  void initState() {
    super.initState();
    ref.read(genteRepositoryProvider).reparto(widget.teamId).then((r) {
      if (!mounted) return;
      setState(() {
        _man.text = r.porManilla == null ? '' : _num(r.porManilla!);
        _combo.text = r.porCombo == null ? '' : _num(r.porCombo!);
        _cargado = true;
      });
    }).catchError((_) {
      // base sin db/33: la tarjeta no se muestra
      if (mounted) setState(() => _sinBase = true);
    });
  }

  static String _num(num v) => v == v.roundToDouble() ? '${v.round()}' : '$v';
  static num? _leer(TextEditingController c) {
    final v = num.tryParse(c.text.trim().replaceAll(',', '.'));
    return v == null ? null : (v < 0 ? 0 : v);
  }

  @override
  void dispose() {
    _man.dispose();
    _combo.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_sinBase || !_cargado) return const SizedBox.shrink();
    final ev = widget.evento;
    final porTeam = ev == null ? null : ev.precioManilla * (1 - ev.pctBoliche / 100);
    final man = _leer(_man);
    return Tarjeta(
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        const Text('Reparto de comisiones del team', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
        const SizedBox(height: 4),
        Text(
          '${porTeam == null ? '' : 'En ${ev!.nombre} tu team gana ${_num(porTeam)} Bs por manilla. '}'
          'Elegí cuánto de eso le das a cada relacionador; el resto es tuyo.',
          style: TextStyle(color: VenueColors.textoSuave, fontSize: 13.5, height: 1.35),
        ),
        const SizedBox(height: 12),
        Row(children: [
          if (widget.club.comisionManillas)
            Expanded(
              child: TextField(
                controller: _man,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                onChanged: (_) => setState(() {}),
                decoration: const InputDecoration(labelText: 'Por manilla (Bs)', hintText: 'Sin fijar'),
              ),
            ),
          if (widget.club.comisionManillas && widget.club.comisionCombos) const SizedBox(width: 10),
          if (widget.club.comisionCombos)
            Expanded(
              child: TextField(
                controller: _combo,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Por combo (Bs)', hintText: 'Sin fijar'),
              ),
            ),
        ]),
        if (porTeam != null && widget.club.comisionManillas) ...[
          const SizedBox(height: 8),
          Text(
            man == null
                ? 'Sin fijar: corre la regla de siempre.'
                : 'Cada relacionador cobra ${_num(man > porTeam ? porTeam : man)} Bs y vos '
                    '${_num(porTeam - man < 0 ? 0 : porTeam - man)} Bs por manilla. Lo que vendés vos: ${_num(porTeam)} Bs.',
            style: TextStyle(fontSize: 13, color: VenueColors.textoSuave),
          ),
        ],
        const SizedBox(height: 12),
        FilledButton(
          onPressed: _ocupado
              ? null
              : () async {
                  setState(() => _ocupado = true);
                  try {
                    await ref.read(genteRepositoryProvider).fijarReparto(widget.teamId,
                        porManilla: _leer(_man), porCombo: _leer(_combo));
                    if (context.mounted) avisar(context, 'Reparto guardado: ya se ve en las comisiones');
                  } catch (e) {
                    if (context.mounted) avisar(context, _error(e), tipo: TipoAviso.aviso);
                  }
                  if (mounted) setState(() => _ocupado = false);
                },
          child: const Text('Guardar reparto'),
        ),
      ]),
    );
  }
}
