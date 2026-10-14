import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/networking/supabase.dart';
import '../../../core/theme/venue_theme.dart';
import '../../../core/widgets/avisos.dart';
import '../../../core/widgets/estado_vista.dart';
import '../../authentication/data/sesion.dart';
import '../../clubs/data/clubs.dart';
import '../../events/data/eventos.dart';
import '../../teams/data/equipo.dart';
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
          icono: Icons.event_busy_rounded, titulo: 'No hay evento activo');
    }
    final cierre = ref.watch(cierreProvider);
    final equipo = ref.watch(equipoProvider).value ?? const <String, Miembro>{};
    final esAdmin = rol == Rol.admin;
    final miTeam = equipo[perfil.id]?.teamId;
    final puedeExcel = perfil.contabilidadTotal || (rol == Rol.jefe && miTeam != null);

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
                  ? c.personas.where((p) => p.teamId == miTeam || p.id == perfil.id).toList()
                  : c.personas.where((p) => p.id == perfil.id).toList();
          num s(num Function(StatsPersona) f) => mias.fold<num>(0, (a, p) => a + f(p));

          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
            children: [
              Text(esAdmin ? 'Cierre del evento' : rol == Rol.jefe ? 'Stats de mi team' : 'Mis stats',
                  style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
              Text('${ev.nombre} · ${ev.fechaCorta}',
                  style: const TextStyle(color: VenueColors.textoSuave)),
              const SizedBox(height: 12),
              if (esAdmin) const _Liquidacion(),
              Row(children: [
                Expanded(child: Kpi('Ingresaron de lista', '${c.listaIngresaron}', '/${c.listaAnotados}')),
                const SizedBox(width: 10),
                Expanded(child: Kpi('Entradas ingresadas', '${c.entUsadas}', '/${c.entVendidas}')),
                if (esAdmin) ...[
                  const SizedBox(width: 10),
                  Expanded(child: Kpi('Mesas vendidas', '${c.mesasN}', '')),
                ],
              ]),
              if (esAdmin && c.porLista.isNotEmpty) ...[
                const SizedBox(height: 14),
                const Text('Por lista · entraron / anotados',
                    style: TextStyle(fontWeight: FontWeight.w800)),
                const SizedBox(height: 6),
                Wrap(spacing: 8, runSpacing: 6, children: [
                  for (final l in c.porLista)
                    Chip(label: Text('${l.nombre}  ${l.ingresaron}/${l.anotados}')),
                ]),
              ],
              if (esAdmin) const _Fases(),
              if (rol == Rol.rrpp) ...[
                const SizedBox(height: 12),
                Kpi('Mis mesas', '${s((p) => p.mesas)}', ' · ${s((p) => p.brutoMesas)} Bs'),
                const SizedBox(height: 10),
                Kpi('Mi comisión total (entradas + mesas + bonos)',
                    '${s((p) => p.comRrpp + p.comRrppMesas + p.bono)} Bs', '',
                    color: VenueColors.ok),
              ],
              if (rol == Rol.jefe) ...[
                const SizedBox(height: 12),
                Row(children: [
                  Expanded(child: Kpi('Comisión RRPPs',
                      '${s((p) => p.comRrpp + p.comRrppMesas)} Bs', '')),
                  const SizedBox(width: 10),
                  Expanded(child: Kpi('Mi comisión (jefe)',
                      '${s((p) => p.comJefe + p.comJefeMesas)} Bs', '', color: VenueColors.ok)),
                ]),
                const SizedBox(height: 12),
                const Text('Mi team', style: TextStyle(fontWeight: FontWeight.w800)),
                for (final p in mias)
                  ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    title: Text(p.nombre, style: const TextStyle(fontWeight: FontWeight.w600)),
                    subtitle: Text(
                        '${p.ingresaron}/${p.anotados} lista · ${p.usadas}/${p.vendidas} entradas · ${p.mesas} mesas'),
                    trailing: const Icon(Icons.chevron_right_rounded),
                    onTap: () => hojaDetallePersona(context, p.id, p.nombre, ev),
                  ),
              ],
              if (!esAdmin) ...[
                const SizedBox(height: 12),
                Wrap(spacing: 8, runSpacing: 6, children: [
                  if (rol == Rol.rrpp)
                    OutlinedButton(
                      style: OutlinedButton.styleFrom(minimumSize: const Size(0, 44)),
                      onPressed: () => hojaDetallePersona(context, perfil.id, perfil.nombre, ev),
                      child: const Text('Ver mis nombres'),
                    ),
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(minimumSize: const Size(0, 44)),
                    onPressed: () => hojaEventosPasados(context, perfil.id, perfil.nombre),
                    icon: const Icon(Icons.history_rounded, size: 18),
                    label: const Text('Eventos pasados'),
                  ),
                ]),
              ],
              if (esAdmin) ...[
                const SizedBox(height: 6),
                ExpansionTile(
                  tilePadding: EdgeInsets.zero,
                  title: const Text('Ver desglose por comisiones'),
                  childrenPadding: const EdgeInsets.only(bottom: 10),
                  children: [
                    const Text(
                      'Otra forma de leer la misma noche: el bruto menos lo que se lleva cada relacionador. Es un control interno — la cifra que se paga es la de arriba.',
                      style: TextStyle(color: VenueColors.textoSuave, fontSize: 12.5, height: 1.35),
                    ),
                    Renglon('Bruto entradas', '${c.entBruto} Bs'),
                    Renglon('Bruto mesas', '${c.mesasBruto} Bs'),
                    Renglon('Comisiones + bonos', '− ${c.comisionesTotal} Bs', color: VenueColors.mal),
                    Renglon('Neto por comisiones', '${c.neto} Bs', fuerte: true),
                  ],
                ),
                const SizedBox(height: 6),
                Row(children: [
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: () async {
                        await Clipboard.setData(ClipboardData(
                            text: textoCierre(ev.nombre, club.nombre, ev.fechaCorta, c)));
                        if (context.mounted) avisar(context, 'Cierre copiado — pegalo en WhatsApp');
                      },
                      icon: const Icon(Icons.copy_rounded),
                      label: const Text('Copiar cierre'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  PopupMenuButton<String>(
                    tooltip: 'Más acciones',
                    onSelected: (k) => switch (k) {
                      'comis' => hojaComisiones(context),
                      'bonos' => hojaBonos(context),
                      'hist' => hojaHistorico(context),
                      'tel' => hojaTelefonos(context),
                      _ => hojaReporteFiltro(context),
                    },
                    itemBuilder: (_) => const [
                      PopupMenuItem(value: 'comis', child: Text('Comisiones')),
                      PopupMenuItem(value: 'bonos', child: Text('Bonos')),
                      PopupMenuItem(value: 'hist', child: Text('Histórico y ranking')),
                      PopupMenuItem(value: 'tel', child: Text('Teléfonos del equipo')),
                      PopupMenuItem(value: 'filtro', child: Text('Reporte de filtro')),
                    ],
                  ),
                ]),
                const SizedBox(height: 14),
                const Text('Por relacionador', style: TextStyle(fontWeight: FontWeight.w800)),
                for (final p in [...c.personas]
                  ..sort((a, b) => (b.usadas + b.mesas).compareTo(a.usadas + a.mesas)))
                  ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    title: Text(p.nombre, style: const TextStyle(fontWeight: FontWeight.w600)),
                    subtitle: Text(
                        '${p.ingresaron}/${p.anotados} lista · ${p.usadas} QR · ${p.mesas} mesas · ${equipo[p.id]?.team ?? ''}'),
                    trailing: Text('${p.aPagar} Bs',
                        style: const TextStyle(fontWeight: FontWeight.w800)),
                    onTap: () => hojaDetallePersona(context, p.id, p.nombre, ev),
                  ),
              ],
              if (puedeExcel) ...[
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: () => exportarContabilidad(context, ref),
                  icon: const Icon(Icons.table_view_outlined),
                  label: Text(perfil.contabilidadTotal
                      ? 'Exportar contabilidad Excel'
                      : 'Exportar contabilidad de mi team'),
                ),
              ],
            ],
          );
        },
      ),
    );
  }
}

class Kpi extends StatelessWidget {
  const Kpi(this.titulo, this.valor, this.sufijo, {super.key, this.color});
  final String titulo;
  final String valor;
  final String sufijo;
  final Color? color;

  @override
  Widget build(BuildContext context) => Card(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(titulo, style: const TextStyle(color: VenueColors.textoSuave, fontSize: 12.5)),
            const SizedBox(height: 3),
            Text.rich(TextSpan(children: [
              TextSpan(
                  text: valor,
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: color)),
              TextSpan(
                  text: sufijo,
                  style: const TextStyle(color: VenueColors.textoSuave, fontSize: 14)),
            ])),
          ]),
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
        child: Row(children: [
          Expanded(
              child: Text(k,
                  style: TextStyle(fontWeight: fuerte ? FontWeight.w800 : FontWeight.w500))),
          Text(v,
              style: TextStyle(
                  color: color, fontWeight: fuerte ? FontWeight.w800 : FontWeight.w600,
                  fontSize: fuerte ? 17 : 14)),
        ]),
      );
}

/// "Lo que se debería pagar al boliche" + manillas de externos.
class _Liquidacion extends ConsumerStatefulWidget {
  const _Liquidacion();

  @override
  ConsumerState<_Liquidacion> createState() => _LiquidacionState();
}

class _LiquidacionState extends ConsumerState<_Liquidacion> {
  final _ext = TextEditingController();
  bool _puesto = false;

  @override
  void dispose() {
    _ext.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = ref.watch(liquidacionProvider).value;
    final c = ref.watch(cierreProvider).value;
    final ev = ref.watch(eventoActivoProvider);
    if (l == null || c == null || ev == null) return const SizedBox.shrink();
    final s = l.servidor;
    num n(String k) => s[k] as num? ?? 0;
    if (!_puesto) {
      _ext.text = '${n('manillas_externas')}';
      _puesto = true;
    }
    final liq = liquidacion(
      brutoPrepagadasIngresadas: c.entBruto,
      totalMesas: n('total_mesas'),
      puertaIngresaron: l.puerta.ingresaron,
      puertaPrecio: l.puerta.precio,
    );
    const pct = 50;
    final unit = c.entUsadas > 0 ? (c.entBruto / c.entUsadas).round() : 0;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Lo que se debería pagar al boliche',
                style: TextStyle(color: VenueColors.textoSuave, fontWeight: FontWeight.w600)),
            Renglon('Prepagadas — $pct%', '${liq.prepagadas} Bs'),
            Text('${c.entUsadas} ingresaron${unit > 0 ? ' × $unit Bs' : ''} × $pct%',
                style: const TextStyle(color: VenueColors.textoSuave, fontSize: 12)),
            Renglon('Mesas netas', '${liq.mesas} Bs'),
            Text('${n('bruto_mesas')} − ${n('comision_mesas')} comisiones',
                style: const TextStyle(color: VenueColors.textoSuave, fontSize: 12)),
            if (liq.puerta > 0) ...[
              Renglon('Menos Compra en Puerta — $pct%', '−${liq.puerta} Bs', color: VenueColors.mal),
              Text('${l.puerta.ingresaron} ingresaron × ${l.puerta.precio} Bs × $pct%',
                  style: const TextStyle(color: VenueColors.textoSuave, fontSize: 12)),
            ],
            const Divider(height: 18),
            Renglon('Total', '${liq.total} Bs', fuerte: true),
            if (l.puerta.nombre != null && l.puerta.ingresaron > 0 && l.puerta.precio <= 0)
              Text(
                '${l.puerta.ingresaron} persona(s) de ${l.puerta.nombre} ingresaron, pero esa lista todavía no tiene precio cargado, así que no se descuenta nada.',
                style: const TextStyle(color: VenueColors.aviso, fontSize: 12.5, height: 1.35),
              ),
            const SizedBox(height: 10),
            Row(children: [
              Expanded(
                child: TextField(
                  controller: _ext,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                      labelText: 'Manillas de externos (no se reparten)', isDense: true),
                ),
              ),
              const SizedBox(width: 8),
              OutlinedButton(
                style: OutlinedButton.styleFrom(minimumSize: const Size(90, 48)),
                onPressed: () async {
                  try {
                    await ref.read(reporteRepositoryProvider)
                        .manillasExternas(ev.id, int.tryParse(_ext.text) ?? 0);
                    ref.invalidate(liquidacionProvider);
                    if (context.mounted) avisar(context, 'Manillas de externos actualizadas');
                  } catch (e) {
                    if (context.mounted) avisar(context, mensajeDeError(e), tipo: TipoAviso.aviso);
                  }
                },
                child: const Text('Aplicar'),
              ),
            ]),
            const SizedBox(height: 4),
            Text(
              'De las ${n('manillas_usadas')} que ingresaron se descuentan ${n('manillas_externas')}. Queda guardado en el evento.',
              style: const TextStyle(color: VenueColors.textoSuave, fontSize: 12),
            ),
          ]),
        ),
      ),
    );
  }
}

final _fasesReporteProvider = FutureProvider.autoDispose<Map<String, dynamic>?>((ref) async {
  final ev = ref.watch(eventoActivoProvider);
  if (ev == null) return null;
  return ref.watch(reporteRepositoryProvider).fases(ev.id);
});

/// Cómo se movió cada fase de preventa: vendido e INGRESADO por separado.
class _Fases extends ConsumerWidget {
  const _Fases();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final r = ref.watch(_fasesReporteProvider).value;
    if (r == null || r['usa_fases'] != true) return const SizedBox.shrink();
    final fases = ((r['fases'] as List?) ?? const [])
        .map((x) => Map<String, dynamic>.from(x as Map)).toList();
    return Padding(
      padding: const EdgeInsets.only(top: 14),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Fases de preventa · ${r['bruto_total']} Bs',
            style: const TextStyle(fontWeight: FontWeight.w800)),
        for (final f in [...fases, if (r['sin_fase'] is Map) {'nombre': 'Sin fase', ...Map<String, dynamic>.from(r['sin_fase'] as Map)}])
          if ((f['vendidas'] as num? ?? 0) > 0 || f['nombre'] != 'Sin fase')
            Renglon('${f['nombre']}',
                '${f['vendidas'] ?? 0} vendidas · ${f['ingresaron'] ?? 0} ingresaron · ${f['bruto'] ?? 0} Bs'),
      ]),
    );
  }
}
