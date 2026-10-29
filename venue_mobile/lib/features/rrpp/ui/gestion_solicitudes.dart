import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';

import '../../../core/networking/supabase.dart';
import '../../../core/theme/venue_theme.dart';
import '../../../core/widgets/avisos.dart';
import '../../../core/widgets/patron.dart';
import '../../clubs/data/clubs.dart';
import '../../teams/data/equipo.dart';
import '../../teams/data/gente.dart';
import '../data/rrpp.dart';

/// Web pública donde se abren los enlaces de invitación.
const webVenue = 'https://venue-web-amber.vercel.app/';

/// Solicitudes para sumarse al boliche activo. El admin aprueba (con o sin
/// team), invita con el enlace del boliche y decide si aparece en
/// "Explorar"; el jefe ve las de su team y las que no tienen team.
Future<void> abrirGestionSolicitudes(BuildContext context, WidgetRef ref) => showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      useSafeArea: true,
      backgroundColor: VenueColors.superficie,
      builder: (_) => const _Gestion(),
    );

class _Gestion extends ConsumerStatefulWidget {
  const _Gestion();
  @override
  ConsumerState<_Gestion> createState() => _GestionState();
}

class _GestionState extends ConsumerState<_Gestion> {
  late Future<_Datos> _datos = _cargar();
  final _team = <String, String?>{};

  Future<_Datos> _cargar() async {
    final club = ref.read(clubActivoIdProvider)!;
    final rol = ref.read(rolProvider).value;
    final repo = ref.read(rrppRepositoryProvider);
    final sols = await repo.solicitudesClub(club);
    final inv = rol == Rol.admin ? await repo.invitacionClub(club) : null;
    for (final s in sols) {
      _team.putIfAbsent(s.id, () => s.teamId);
    }
    return _Datos(sols, inv, rol == Rol.admin);
  }

  void _recargar() => setState(() => _datos = _cargar());

  Future<void> _hacer(Future<void> Function() f, String ok) async {
    try {
      await f();
      ref.invalidate(equipoProvider);
      if (mounted) avisar(context, ok);
      _recargar();
    } catch (e) {
      if (mounted) avisar(context, mensajeDeError(e), tipo: TipoAviso.aviso);
    }
  }

  @override
  Widget build(BuildContext context) {
    final club = ref.watch(clubActivoProvider);
    final repo = ref.read(rrppRepositoryProvider);
    // teams que trabajan en este boliche (sin boliches = todos)
    final teams = (ref.watch(teamsInfoProvider).value ?? const <TeamInfo>[])
        .where((t) => t.activo && (t.clubs.isEmpty || t.clubs.contains(club?.id)))
        .toList();
    return FutureBuilder<_Datos>(
      future: _datos,
      builder: (context, snap) {
        if (!snap.hasData) {
          return SizedBox(
              height: 240,
              child: Center(
                  child: snap.hasError
                      ? Text(mensajeDeError(snap.error!), textAlign: TextAlign.center)
                      : const CircularProgressIndicator()));
        }
        final d = snap.data!;
        final link = d.inv == null ? '' : '$webVenue?unirse=${d.inv!.code}';
        return ListView(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 28),
          shrinkWrap: true,
          children: [
            Text(d.esAdmin ? 'Relacionadores' : 'Quieren unirse a tu team',
                style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700)),
            Text(club?.nombre ?? '', style: TextStyle(color: VenueColors.textoSuave)),
            TituloBloque('Solicitudes${d.sols.isEmpty ? '' : ' · ${d.sols.length}'}'),
            if (d.sols.isEmpty)
              Tarjeta(
                  child: Text('No hay solicitudes pendientes.',
                      textAlign: TextAlign.center, style: TextStyle(color: VenueColors.textoSuave)))
            else
              for (final s in d.sols)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Tarjeta(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                      Row(children: [
                        Inicial(s.nombre, lado: 40),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text(s.nombre, style: const TextStyle(fontSize: 15.5, fontWeight: FontWeight.w600)),
                            Text('${s.email ?? '@${s.usuario}'} · ${s.origenTexto}${s.team != null ? ' (${s.team})' : ''}',
                                style: TextStyle(fontSize: 12.5, color: VenueColors.textoSuave)),
                            Text(
                                s.eventosTrabajados > 0
                                    ? '${s.eventosTrabajados} eventos trabajados en VENUE'
                                    : 'Sin eventos en VENUE todavía',
                                style: TextStyle(fontSize: 12.5, color: VenueColors.textoTenue)),
                          ]),
                        ),
                      ]),
                      if (d.esAdmin && teams.isNotEmpty) ...[
                        const SizedBox(height: 10),
                        DropdownButtonFormField<String?>(
                          initialValue: _team[s.id],
                          decoration: const InputDecoration(labelText: 'Team', isDense: true),
                          items: [
                            const DropdownMenuItem(value: null, child: Text('Sin team')),
                            for (final t in teams) DropdownMenuItem(value: t.id, child: Text(t.nombre)),
                          ],
                          onChanged: (v) => _team[s.id] = v,
                        ),
                      ],
                      const SizedBox(height: 10),
                      Row(children: [
                        Expanded(
                          child: FilledButton(
                            onPressed: () => _hacer(() => repo.resolver(s.id, true, team: _team[s.id]),
                                'Aprobado: ya puede trabajar en el boliche'),
                            child: const Text('Aprobar'),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () => _hacer(() => repo.resolver(s.id, false), 'Solicitud rechazada'),
                            child: const Text('Rechazar'),
                          ),
                        ),
                      ]),
                    ]),
                  ),
                ),
            if (d.inv != null && club != null) ...[
              const TituloBloque('Invitar relacionadores'),
              Tarjeta(
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  Text('Quien abra este enlace entra por Relacionadores y te manda una solicitud. Nadie entra sin que la apruebes.',
                      style: TextStyle(color: VenueColors.textoSuave, height: 1.4)),
                  const SizedBox(height: 10),
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(color: VenueColors.superficie2, borderRadius: BorderRadius.circular(10)),
                    child: Text(link,
                        style: TextStyle(
                            fontSize: 12.5,
                            decoration: d.inv!.activo ? null : TextDecoration.lineThrough,
                            color: d.inv!.activo ? null : VenueColors.textoTenue)),
                  ),
                  const SizedBox(height: 10),
                  Row(children: [
                    Expanded(
                      child: FilledButton(
                        onPressed: !d.inv!.activo
                            ? null
                            : () => SharePlus.instance.share(ShareParams(
                                text: 'Sumate como relacionador de ${club.nombre} en VENUE: $link')),
                        child: const Text('Compartir'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton(
                        onPressed: !d.inv!.activo
                            ? null
                            : () async {
                                await Clipboard.setData(ClipboardData(text: link));
                                if (context.mounted) avisar(context, 'Enlace copiado');
                              },
                        child: const Text('Copiar'),
                      ),
                    ),
                  ]),
                  const SizedBox(height: 8),
                  Row(children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => _hacer(() => repo.configurar(club.id, activo: !d.inv!.activo),
                            d.inv!.activo ? 'Enlace desactivado' : 'Enlace activado'),
                        child: Text(d.inv!.activo ? 'Desactivar' : 'Activar'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () async {
                          final ok = await showDialog<bool>(
                            context: context,
                            builder: (c) => AlertDialog(
                              title: const Text('¿Generar un enlace nuevo?'),
                              content: const Text('El enlace actual deja de funcionar.'),
                              actions: [
                                TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancelar')),
                                FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Generar')),
                              ],
                            ),
                          );
                          if (ok == true) await _hacer(() => repo.regenerar(club.id), 'Enlace nuevo listo');
                        },
                        child: const Text('Nuevo enlace'),
                      ),
                    ),
                  ]),
                ]),
              ),
              const TituloBloque('Solicitudes públicas'),
              Tarjeta(
                padding: EdgeInsets.zero,
                child: SwitchListTile(
                  value: d.inv!.publicas,
                  onChanged: (v) => _hacer(() => repo.configurar(club.id, publicas: v),
                      v ? 'Ya aparecés en Explorar' : 'Ya no aparecés en Explorar'),
                  title: const Text('Aparecer en "Explorar boliches"'),
                  subtitle: Text('Cualquier relacionador puede encontrar ${club.nombre} y pedir sumarse.'),
                ),
              ),
            ],
          ],
        );
      },
    );
  }
}

class _Datos {
  const _Datos(this.sols, this.inv, this.esAdmin);
  final List<SolicitudClub> sols;
  final ({String code, bool activo, bool publicas})? inv;
  final bool esAdmin;
}
