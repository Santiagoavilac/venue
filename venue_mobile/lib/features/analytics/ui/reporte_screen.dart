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

          final ancho = MediaQuery.sizeOf(context).width >= 1100;
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 20, 16, 28),
            children: [
              Encabezado(
                etiqueta: esAdmin ? 'Reporte' : 'Stats',
                titulo: esAdmin
                    ? 'Cierre del evento'
                    : rol == Rol.jefe
                    ? 'Stats de mi team'
                    : 'Mis stats',
                contexto: '${ev.nombre} · ${ev.fechaCorta}',
              ),
              if (esAdmin)
                ancho
                    ? const Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(flex: 162, child: _Liquidacion()),
                          SizedBox(width: 14),
                          Expanded(flex: 100, child: _AjustesCierre()),
                        ],
                      )
                    : const Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _Liquidacion(),
                          SizedBox(height: 12),
                          _AjustesCierre(),
                        ],
                      ),
              if (esAdmin) const SizedBox(height: 14),
              GrillaIndicadores(
                maxColumnas: 3,
                children: [
                  Indicador(
                    icono: Icons.groups_outlined,
                    etiqueta: 'Ingresaron de lista',
                    valor: '${c.listaIngresaron}',
                    de: '${c.listaAnotados}',
                  ),
                  Indicador(
                    icono: Icons.confirmation_number_outlined,
                    etiqueta: 'Entradas ingresadas',
                    valor: '${c.entUsadas}',
                    de: '${c.entVendidas}',
                  ),
                  if (esAdmin)
                    Indicador(
                      icono: Icons.weekend_outlined,
                      etiqueta: 'Mesas vendidas',
                      valor: '${c.mesasN}',
                    ),
                  if (rol == Rol.rrpp) ...[
                    Indicador(
                      icono: Icons.weekend_outlined,
                      etiqueta: 'Mis mesas',
                      valor: '${s((p) => p.mesas)}',
                      detalle: 'Bs ${s((p) => p.brutoMesas)}',
                    ),
                    Indicador(
                      icono: Icons.payments_outlined,
                      etiqueta: 'Mi comisión total',
                      valor:
                          'Bs ${s((p) => p.comRrpp + p.comRrppMesas + p.bono)}',
                      detalle: 'Entradas + mesas + bonos',
                      tono: Tono.ok,
                    ),
                  ],
                  if (rol == Rol.jefe) ...[
                    Indicador(
                      icono: Icons.groups_outlined,
                      etiqueta: 'Comisión RRPPs',
                      valor: 'Bs ${s((p) => p.comRrpp + p.comRrppMesas)}',
                    ),
                    Indicador(
                      icono: Icons.payments_outlined,
                      etiqueta: 'Mi comisión (jefe)',
                      valor: 'Bs ${s((p) => p.comJefe + p.comJefeMesas)}',
                      tono: Tono.ok,
                    ),
                  ],
                ],
              ),
              if (esAdmin && c.porLista.isNotEmpty) ...[
                const SizedBox(height: 14),
                const Text(
                  'Por lista · entraron / anotados',
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
                ),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  children: [
                    for (final l in c.porLista)
                      Chip(
                        label: Text(
                          '${l.nombre}  ${l.ingresaron}/${l.anotados}',
                        ),
                      ),
                  ],
                ),
              ],
              if (esAdmin) const _Fases(),
              if (rol == Rol.jefe) ...[
                const SizedBox(height: 12),
                const Text(
                  'Mi team',
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
                ),
                for (final p in mias)
                  ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    title: Text(
                      p.nombre,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    subtitle: Text(
                      '${p.ingresaron}/${p.anotados} lista · ${p.usadas}/${p.vendidas} entradas · ${p.mesas} mesas',
                    ),
                    trailing: const Icon(Icons.chevron_right_rounded),
                    onTap: () =>
                        hojaDetallePersona(context, p.id, p.nombre, ev),
                  ),
              ],
              if (!esAdmin) ...[
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  children: [
                    if (rol == Rol.rrpp)
                      OutlinedButton(
                        style: OutlinedButton.styleFrom(
                          minimumSize: const Size(0, 44),
                        ),
                        onPressed: () => hojaDetallePersona(
                          context,
                          perfil.id,
                          perfil.nombre,
                          ev,
                        ),
                        child: const Text('Ver mis nombres'),
                      ),
                    OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size(0, 44),
                      ),
                      onPressed: () =>
                          hojaEventosPasados(context, perfil.id, perfil.nombre),
                      icon: const Icon(Icons.history_rounded, size: 18),
                      label: const Text('Eventos pasados'),
                    ),
                  ],
                ),
              ],
              if (esAdmin) ...[
                const SizedBox(height: 14),
                Container(
                  decoration: BoxDecoration(
                    color: VenueColors.superficie,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: VenueColors.linea),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: ExpansionTile(
                    shape: const Border(),
                    collapsedShape: const Border(),
                    tilePadding: const EdgeInsets.symmetric(
                      horizontal: 18,
                      vertical: 4,
                    ),
                    iconColor: VenueColors.textoSuave,
                    collapsedIconColor: VenueColors.textoSuave,
                    title: const Text(
                      'Ver desglose por comisiones',
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 15.5,
                      ),
                    ),
                    childrenPadding: const EdgeInsets.fromLTRB(18, 0, 18, 14),
                    children: [
                      const Text(
                        'Otra forma de leer la misma noche: el bruto menos lo que se lleva cada relacionador. Es un control interno — la cifra que se paga es la de arriba.',
                        style: TextStyle(
                          color: VenueColors.textoSuave,
                          fontSize: 12.5,
                          height: 1.35,
                        ),
                      ),
                      Renglon('Bruto entradas', '${c.entBruto} Bs'),
                      Renglon('Bruto mesas', '${c.mesasBruto} Bs'),
                      Renglon(
                        'Comisiones + bonos',
                        '− ${c.comisionesTotal} Bs',
                        color: VenueColors.mal,
                      ),
                      Renglon(
                        'Neto por comisiones',
                        '${c.neto} Bs',
                        fuerte: true,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                // Como el mockup: Copiar cierre, Excel y ⋯ a la derecha. En el
                // teléfono no entran los tres y el Excel pasa al menú ⋯.
                Builder(
                  builder: (context) {
                    final fila = MediaQuery.sizeOf(context).width >= 700;
                    const tam = Size(0, 52);
                    final copiar = FilledButton.icon(
                      style: FilledButton.styleFrom(
                        minimumSize: tam,
                        padding: const EdgeInsets.symmetric(horizontal: 22),
                      ),
                      onPressed: () async {
                        await Clipboard.setData(
                          ClipboardData(
                            text: textoCierre(
                              ev.nombre,
                              club.nombre,
                              ev.fechaCorta,
                              c,
                            ),
                          ),
                        );
                        if (context.mounted) {
                          avisar(
                            context,
                            'Cierre copiado — pegalo en WhatsApp',
                          );
                        }
                      },
                      icon: const Icon(Icons.copy_rounded, size: 20),
                      label: const Text('Copiar cierre'),
                    );
                    return Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        if (fila) copiar else Expanded(child: copiar),
                        if (fila && puedeExcel) ...[
                          const SizedBox(width: 10),
                          OutlinedButton.icon(
                            style: OutlinedButton.styleFrom(
                              minimumSize: tam,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 20,
                              ),
                            ),
                            onPressed: () => exportarContabilidad(context, ref),
                            icon: const Icon(
                              Icons.description_outlined,
                              size: 20,
                            ),
                            label: const Text('Exportar contabilidad Excel'),
                          ),
                        ],
                        const SizedBox(width: 10),
                        PopupMenuButton<String>(
                          tooltip: 'Más acciones',
                          color: VenueColors.superficie2,
                          child: Container(
                            width: 54,
                            height: 52,
                            decoration: BoxDecoration(
                              color: VenueColors.superficie,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: VenueColors.linea),
                            ),
                            child: const Icon(Icons.more_horiz_rounded),
                          ),
                          onSelected: (k) => switch (k) {
                            'excel' => exportarContabilidad(context, ref),
                            'comis' => hojaComisiones(context),
                            'bonos' => hojaBonos(context),
                            'hist' => hojaHistorico(context),
                            'tel' => hojaTelefonos(context),
                            _ => hojaReporteFiltro(context),
                          },
                          itemBuilder: (_) => [
                            if (!fila && puedeExcel)
                              const PopupMenuItem(
                                value: 'excel',
                                child: Text('Exportar contabilidad Excel'),
                              ),
                            const PopupMenuItem(
                              value: 'comis',
                              child: Text('Comisiones'),
                            ),
                            PopupMenuItem(value: 'bonos', child: Text('Bonos')),
                            PopupMenuItem(
                              value: 'hist',
                              child: Text('Histórico y ranking'),
                            ),
                            PopupMenuItem(
                              value: 'tel',
                              child: Text('Teléfonos del equipo'),
                            ),
                            const PopupMenuItem(
                              value: 'filtro',
                              child: Text('Reporte de filtro'),
                            ),
                          ],
                        ),
                      ],
                    );
                  },
                ),
                const SizedBox(height: 22),
                const Text(
                  'Por relacionador',
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
                ),
                for (final p
                    in [...c.personas]..sort(
                      (a, b) =>
                          (b.usadas + b.mesas).compareTo(a.usadas + a.mesas),
                    ))
                  ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    title: Text(
                      p.nombre,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    subtitle: Text(
                      '${p.ingresaron}/${p.anotados} lista · ${p.usadas} QR · ${p.mesas} mesas · ${equipo[p.id]?.team ?? ''}',
                    ),
                    trailing: Text(
                      '${p.aPagar} Bs',
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                    onTap: () =>
                        hojaDetallePersona(context, p.id, p.nombre, ev),
                  ),
              ],
              if (puedeExcel && !esAdmin) ...[
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: () => exportarContabilidad(context, ref),
                  icon: const Icon(Icons.description_outlined, size: 20),
                  label: Text(
                    perfil.contabilidadTotal
                        ? 'Exportar contabilidad Excel'
                        : 'Exportar contabilidad de mi team',
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
          style: const TextStyle(
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
                style: const TextStyle(
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
    final marca = Theme.of(context).colorScheme.primary;
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
              Container(
                width: angosto ? 52 : 64,
                height: angosto ? 52 : 64,
                decoration: BoxDecoration(
                  color: Color.lerp(marca, Colors.black, .45),
                  borderRadius: BorderRadius.circular(angosto ? 13 : 15),
                ),
                child: Icon(
                  Icons.storage_rounded,
                  color: Colors.white,
                  size: angosto ? 24 : 30,
                ),
              ),
              SizedBox(width: angosto ? 14 : 20),
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
                          fontSize: angosto ? 42 : 58,
                          height: 1.08,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -1.6,
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
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 20),
            child: Divider(height: 1, color: VenueColors.linea),
          ),
          LayoutBuilder(
            builder: (context, k) {
              final cols = k.maxWidth >= 560 ? 3 : 1;
              final w = (k.maxWidth - 12 * (cols - 1)) / cols;
              return Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [for (final x in subs) SizedBox(width: w, child: x)],
              );
            },
          ),
          if (l.puerta.nombre != null &&
              l.puerta.ingresaron > 0 &&
              l.puerta.precio <= 0) ...[
            const SizedBox(height: 12),
            Text(
              '${l.puerta.ingresaron} persona(s) de ${l.puerta.nombre} ingresaron, pero esa lista todavía no tiene precio cargado, así que no se descuenta nada.',
              style: const TextStyle(
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

  @override
  Widget build(BuildContext context) => Tarjeta(
    color: VenueColors.superficie2,
    padding: const EdgeInsets.all(16),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        IconoRecuadro(icono, lado: 42),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                k,
                style: const TextStyle(
                  fontSize: 13.5,
                  color: VenueColors.textoSuave,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                v,
                style: TextStyle(
                  fontSize: 23,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.4,
                  color: negativo ? VenueColors.mal : null,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                d,
                style: const TextStyle(
                  fontSize: 12.5,
                  color: VenueColors.textoTenue,
                ),
              ),
            ],
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
          const Text(
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
                decoration: const BoxDecoration(
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
                    const Divider(height: 1, color: VenueColors.linea),
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
            style: const TextStyle(
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
