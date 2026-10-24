import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/media/imagenes.dart';
import '../../../core/networking/supabase.dart';
import '../../../core/routing/secciones.dart';
import '../../../core/theme/venue_theme.dart';
import '../../../core/widgets/avisos.dart';
import '../../../core/widgets/estado_vista.dart';
import '../../../core/widgets/patron.dart';
import '../../authentication/data/sesion.dart';
import '../../clubs/data/clubs.dart';
import '../../teams/data/gente.dart';
import '../../tickets/data/ticket_imagen.dart';
import '../data/eventos.dart';
import '../data/gestion.dart';

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

/// Fases de preventa del evento (precio, stock, cupos por team), para
/// abrirlas desde Entradas sin pasar por Más → Eventos.
Future<void> abrirFases(BuildContext context, Evento ev) => _hoja(
    context,
    _Fases(evento: {'id': ev.id, 'nombre': ev.nombre, 'venta_por_fases': ev.ventaPorFases}));

/// Límites y horarios de una lista, para abrirlos desde su tarjeta en Listas.
Future<void> abrirEditarLista(
    BuildContext context, WidgetRef ref, String eventoId, String listaId) async {
  final ls = await ref.read(gestionRepositoryProvider).listas(eventoId);
  final i = ls.indexWhere((l) => l['id'] == listaId);
  if (i < 0 || !context.mounted) return;
  await _hoja(context, _ListaForm(eventoId: eventoId, lista: ls[i], orden: i));
}

String _fh(dynamic ts) {
  final t = DateTime.tryParse(ts as String? ?? '')?.toLocal();
  if (t == null) return 'sin límite';
  return '${t.day.toString().padLeft(2, '0')}/${t.month.toString().padLeft(2, '0')} ${horaCorta(t)}';
}

/// Fecha y hora con los selectores del sistema. null si se cancela.
Future<DateTime?> elegirFechaHora(BuildContext context, {DateTime? inicial}) async {
  final base = inicial ?? DateTime.now();
  final d = await showDatePicker(
      context: context,
      initialDate: base,
      firstDate: DateTime(base.year - 1),
      lastDate: DateTime(base.year + 2));
  if (d == null || !context.mounted) return null;
  final h = await showTimePicker(context: context, initialTime: TimeOfDay.fromDateTime(base));
  if (h == null) return null;
  return DateTime(d.year, d.month, d.day, h.hour, h.minute);
}

/// Campo de fecha y hora opcional.
class CampoFechaHora extends StatelessWidget {
  const CampoFechaHora({super.key, required this.etiqueta, required this.valor, required this.alCambiar});
  final String etiqueta;
  final DateTime? valor;
  final ValueChanged<DateTime?> alCambiar;

  @override
  Widget build(BuildContext context) => InkWell(
        onTap: () async {
          final v = await elegirFechaHora(context, inicial: valor);
          if (v != null) alCambiar(v);
        },
        child: InputDecorator(
          decoration: InputDecoration(
            labelText: etiqueta,
            isDense: true,
            suffixIcon: valor == null
                ? const Icon(Icons.schedule_rounded)
                : IconButton(
                    tooltip: 'Quitar',
                    icon: const Icon(Icons.close_rounded),
                    onPressed: () => alCambiar(null)),
          ),
          child: Text(valor == null ? 'sin límite' : _fh(valor!.toIso8601String())),
        ),
      );
}

DateTime? _dt(dynamic v) => DateTime.tryParse(v as String? ?? '')?.toLocal();
int? _int(TextEditingController c) => int.tryParse(c.text.trim());

/// Gestión de eventos del admin: crear, publicar, editar, listas, fases,
/// horarios de venta, arte del ticket, cerrar y eliminar.
class GestionEventosScreen extends ConsumerWidget {
  const GestionEventosScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final eventos = ref.watch(eventosGestionProvider);
    final activo = ref.watch(eventoActivoProvider);
    final club = ref.watch(clubActivoIdProvider);
    final perfil = ref.watch(perfilProvider).value;
    final repo = ref.read(gestionRepositoryProvider);
    if (club == null) return const SizedBox.shrink();

    void recargar() {
      ref.invalidate(eventosGestionProvider);
      ref.invalidate(eventosProvider);
    }

    Future<void> hacer(Future<void> Function() f, String ok) async {
      try {
        await f();
        recargar();
        if (context.mounted) avisar(context, ok);
      } catch (e) {
        if (context.mounted) avisar(context, mensajeDeError(e), tipo: TipoAviso.aviso);
      }
    }

    Future<bool> confirmar(String titulo, String cuerpo, String accion) async =>
        await showDialog<bool>(
          context: context,
          builder: (c) => AlertDialog(
            title: Text(titulo),
            content: Text(cuerpo),
            actions: [
              TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancelar')),
              TextButton(
                  onPressed: () => Navigator.pop(c, true),
                  style: TextButton.styleFrom(foregroundColor: VenueColors.mal),
                  child: Text(accion)),
            ],
          ),
        ) ??
        false;

    return RefreshIndicator(
      onRefresh: () async {
        recargar();
        await ref.read(eventosGestionProvider.future);
      },
      child: VistaAsync(
        valor: eventos,
        reintentar: recargar,
        datos: (lista) {
          // arriba el evento de trabajo en grande; después los accesos
          // rápidos y el resto de los eventos
          final hayHero = lista.any((e) => e['id'] == activo?.id && e['estado'] != 'cerrado');
          final orden = [
            ...lista.where((e) => hayHero && e['id'] == activo?.id),
            ...lista.where((e) => !(hayHero && e['id'] == activo?.id)),
          ];
          final accionesRapidas = <Widget>[
            const TituloBloque('Accesos rápidos'),
            GrillaAcciones(children: [
              AccionRapida(
                icono: Icons.calendar_today_outlined,
                titulo: 'Crear evento',
                alTocar: () async {
                  if (await _hoja<bool>(context, const _NuevoEvento()) == true) recargar();
                },
              ),
              AccionRapida(
                icono: Icons.groups_outlined,
                titulo: 'Ver invitados',
                color: VenueColors.aviso,
                alTocar: () => ref.read(seccionPedidaProvider.notifier).ir('Accesos'),
              ),
              AccionRapida(
                icono: Icons.campaign_outlined,
                titulo: 'Avisos',
                color: VenueColors.info,
                alTocar: () => _hoja(context, const _Avisos()),
              ),
              AccionRapida(
                icono: Icons.bar_chart_rounded,
                titulo: 'Reporte',
                color: VenueColors.ok,
                alTocar: () => ref.read(seccionPedidaProvider.notifier).ir('Reporte'),
              ),
            ]),
            if (orden.length > 1) const TituloBloque('Otros eventos'),
          ];
          return ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
          children: [
            Saludo(
              nombre: perfil?.primerNombre ?? '',
              detalle: hayHero ? 'Gestioná tu próximo evento' : 'Elegí un evento para trabajar',
            ),
            if (!hayHero) ...accionesRapidas,
            if (lista.isEmpty)
              const Padding(
                padding: EdgeInsets.only(top: 40),
                child: MensajeVista(
                  icono: Icons.event_outlined,
                  titulo: 'Todavía no hay eventos',
                  detalle: 'Creá el primero. Nace como borrador: nadie lo ve hasta que lo publiques.',
                ),
              ),
            for (final (k, e) in orden.indexed) ...[
              _TarjetaEvento(
                evento: e,
                seleccionado: e['id'] == activo?.id,
                alElegir: e['estado'] == 'cerrado'
                    ? null
                    : () => ref.read(eventoElegidoProvider.notifier).elegir(e['id'] as String),
                alIr: (t) => ref.read(seccionPedidaProvider.notifier).ir(t),
                alAccion: (k) async {
                  final id = e['id'] as String, nombre = e['nombre'] as String;
                  switch (k) {
                    case 'publicar':
                      try {
                        final r = await repo.publicar(id);
                        recargar();
                        if (context.mounted) {
                          avisar(context,
                              '$nombre publicado · ${r['listas']} listas · ${r['mesas']} mesas');
                        }
                      } catch (x) {
                        if (context.mounted) avisar(context, mensajeDeError(x), tipo: TipoAviso.aviso);
                      }
                    case 'editar':
                      if (await _hoja<bool>(context, _EditarEvento(evento: e)) == true) recargar();
                    case 'listas':
                      await _hoja(context, _Listas(eventoId: id, nombre: nombre));
                      ref.invalidate(numerosEventoProvider(id));
                    case 'fases':
                      await _hoja(context, _Fases(evento: e));
                      recargar();
                    case 'horarios':
                      await _hoja(context, _Horarios(evento: e));
                      recargar();
                    case 'arte':
                      final b = await elegirImagen(lado: 1400);
                      if (b == null) return;
                      await hacer(() async {
                        final url = await ref.read(archivosProvider).subirDiseno(b, 'ticket-$id.jpg');
                        await repo.editar(id, {'ticket_url': url});
                      }, 'Imagen del evento actualizada');
                    case 'cerrar':
                      if (await confirmar('Cerrar $nombre',
                          'Deja de aparecer para el equipo y pasa al histórico. Sus datos se conservan.',
                          'Cerrar evento')) {
                        await hacer(() => repo.cerrar(id), '$nombre cerrado');
                      }
                    case 'eliminar':
                      if (await confirmar('Eliminar $nombre',
                          'Se borran TODAS sus entradas, invitados, mesas, pagos y ventas de barra. No se puede deshacer.',
                          'Eliminar evento')) {
                        await hacer(() => repo.eliminar(id), '$nombre eliminado');
                      }
                  }
                },
              ),
              if (k == 0 && hayHero) ...accionesRapidas,
            ],
          ],
          );
        },
      ),
    );
  }
}

class _TarjetaEvento extends StatelessWidget {
  const _TarjetaEvento({
    required this.evento, required this.seleccionado, required this.alElegir, required this.alAccion,
    required this.alIr,
  });
  final Fila evento;
  final bool seleccionado;
  final VoidCallback? alElegir;
  final Future<void> Function(String) alAccion;

  /// Ir a otra sección del inicio ("Escáner", "Mesas").
  final ValueChanged<String> alIr;

  @override
  Widget build(BuildContext context) {
    final e = evento;
    final a = accionesDeEvento(e);
    final cerrado = e['estado'] == 'cerrado';
    String hora(dynamic h) => '$h'.padRight(5).substring(0, 5);
    final fecha = DateTime.tryParse('${e['fecha']}');
    final fechaTxt = fecha == null ? '${e['fecha']}' : fechaLarga(fecha);
    final menu = PopupMenuButton<String>(
      tooltip: 'Acciones del evento',
      icon: const Icon(Icons.more_horiz_rounded),
      onSelected: alAccion,
      itemBuilder: (_) => [
        const PopupMenuItem(value: 'editar', child: Text('Editar')),
        const PopupMenuItem(value: 'listas', child: Text('Listas y cupos')),
        const PopupMenuItem(value: 'fases', child: Text('Fases de preventa')),
        const PopupMenuItem(value: 'horarios', child: Text('Horario de venta')),
        const PopupMenuItem(value: 'arte', child: Text('Imagen del evento')),
        if (a.cerrar) const PopupMenuItem(value: 'cerrar', child: Text('Cerrar evento')),
        const PopupMenuItem(value: 'eliminar', child: Text('Eliminar')),
      ],
    );

    // el evento elegido se abre grande, con su imagen, sus números y sus
    // acciones a la vista (como la app de Bowie y BurTown)
    if (seleccionado && !cerrado) {
      return Padding(
        padding: const EdgeInsets.only(top: 12),
        child: HeroEvento(
          eventoId: e['id'] as String,
          nombre: '${e['nombre']}',
          detalle: [
            fechaTxt,
            if (e['hora_inicio'] != null) '${hora(e['hora_inicio'])} – ${hora(e['hora_fin'])} hs',
            'Manilla ${e['precio_manilla']} Bs',
          ].join(' · '),
          imagen: e['ticket_url'] as String?,
          estado: e['publicado'] == false
              ? ('borrador', VenueColors.aviso)
              : fecha != null && _esHoy(fecha)
                  ? ('hoy', VenueColors.ok)
                  : ('próximo', null),
          menu: menu,
          principal: a.publicar
              ? FilledButton.icon(
                  onPressed: () => alAccion('publicar'),
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(52),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                  icon: const Icon(Icons.campaign_rounded, size: 20),
                  label: const Text('Publicar evento'),
                )
              : null,
          gestionar: () => Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => _EventoDetalle(eventoId: e['id'] as String, alAccion: alAccion))),
          atajos: [
            (Icons.format_list_bulleted_rounded, 'Listas', () => alAccion('listas')),
            (Icons.qr_code_scanner_rounded, 'Escanear QR', () => alIr('Escáner')),
            (Icons.table_bar_outlined, 'Mesas', () => alIr('Mesas')),
          ],
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Tarjeta(
        padding: EdgeInsets.zero,
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: alElegir,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 4, 12),
            child: Row(children: [
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('${e['nombre']}',
                      style: TextStyle(
                          fontSize: 16, fontWeight: FontWeight.w600,
                          color: cerrado ? VenueColors.textoSuave : null)),
                  const SizedBox(height: 2),
                  Text(
                    [
                      fechaTxt,
                      '${e['precio_manilla']} Bs',
                      if (e['publicado'] == false) 'borrador · solo lo ves vos',
                      if (cerrado) 'cerrado',
                      if (e['venta_por_fases'] == true) 'por fases',
                    ].join(' · '),
                    style: TextStyle(
                        color: e['publicado'] == false ? VenueColors.aviso : VenueColors.textoSuave,
                        fontSize: 13),
                  ),
                ]),
              ),
              if (a.publicar)
                TextButton(onPressed: () => alAccion('publicar'), child: const Text('Publicar')),
              menu,
            ]),
          ),
        ),
      ),
    );
  }
}

bool _esHoy(DateTime f) {
  final h = DateTime.now();
  return f.year == h.year && f.month == h.month && f.day == h.day;
}

const _diasLargos = ['lun', 'mar', 'mié', 'jue', 'vie', 'sáb', 'dom'];
const _mesesLargos = ['ene', 'feb', 'mar', 'abr', 'may', 'jun', 'jul', 'ago', 'sep', 'oct', 'nov', 'dic'];

/// "sáb, 24 oct".
String fechaLarga(DateTime f) => '${_diasLargos[f.weekday - 1]}, ${f.day} ${_mesesLargos[f.month - 1]}';

/// Tarjeta grande del evento de trabajo: la foto con el estado, el nombre y
/// el horario; abajo los cuatro números, "Gestionar evento" y los atajos de
/// la noche.
class HeroEvento extends StatelessWidget {
  const HeroEvento({
    super.key,
    required this.eventoId,
    required this.nombre,
    required this.detalle,
    this.imagen,
    this.estado,
    this.menu,
    this.principal,
    this.gestionar,
    this.atajos = const [],
  });

  final String eventoId;
  final String nombre;
  final String detalle;
  final String? imagen;

  /// Texto y color de la etiqueta (null: el de la marca).
  final (String, Color?)? estado;
  final Widget? menu;
  final Widget? principal;
  final VoidCallback? gestionar;

  /// (ícono, texto, al tocar): los botones chicos de abajo.
  final List<(IconData, String, VoidCallback)> atajos;

  @override
  Widget build(BuildContext context) {
    final marca = Theme.of(context).colorScheme.primary;
    final conImagen = imagen != null && imagen!.isNotEmpty;
    final ce = estado?.$2 ?? marca;
    final fondo = DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color.lerp(marca, Colors.black, .35)!, Color.lerp(marca, Colors.black, .8)!],
        ),
      ),
    );
    final etiqueta = estado == null
        ? null
        : estado!.$1.isEmpty
            ? ''
            : estado!.$1[0].toUpperCase() + estado!.$1.substring(1);

    final portada = ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: SizedBox(
        height: conImagen ? 200 : 170,
        child: Stack(fit: StackFit.expand, children: [
          if (conImagen)
            Image.network(imagen!, fit: BoxFit.cover, errorBuilder: (_, _, _) => fondo)
          else
            fondo,
          // velo para que el texto se lea sobre cualquier foto
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.black.withValues(alpha: .15),
                  Colors.black.withValues(alpha: .35),
                  Colors.black.withValues(alpha: .80),
                ],
                stops: const [0, .45, 1],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 10, 16),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Row(children: [
                if (etiqueta != null)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: Color.lerp(ce, Colors.white, .80),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(color: ce, shape: BoxShape.circle),
                      ),
                      const SizedBox(width: 6),
                      Text(etiqueta,
                          style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: Color.lerp(ce, Colors.black, .45))),
                    ]),
                  ),
                const Spacer(),
                if (menu != null)
                  Container(
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: .35),
                      shape: BoxShape.circle,
                    ),
                    child: IconTheme(
                        data: const IconThemeData(color: Colors.white), child: menu!),
                  ),
              ]),
              const Spacer(),
              Text(nombre,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 28,
                    height: 1.08,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.4,
                    color: Colors.white,
                    shadows: [Shadow(color: Colors.black.withValues(alpha: .5), blurRadius: 12)],
                  )),
              const SizedBox(height: 6),
              Text(detalle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 14, color: Colors.white.withValues(alpha: .88))),
            ]),
          ),
        ]),
      ),
    );

    final botonGestionar = gestionar == null
        ? null
        : (principal != null ? FilledButton.tonal : FilledButton.new)(
            onPressed: gestionar,
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(52),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
            child: const Row(children: [
              SizedBox(width: 22),
              Expanded(
                child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  Icon(Icons.settings_rounded, size: 22),
                  SizedBox(width: 10),
                  Text('Gestionar evento'),
                ]),
              ),
              Icon(Icons.chevron_right_rounded, size: 22),
            ]),
          );

    return Tarjeta(
      padding: const EdgeInsets.all(10),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        portada,
        const SizedBox(height: 10),
        NumerosEvento(eventoId: eventoId),
        if (principal != null) ...[
          const SizedBox(height: 10),
          principal!,
        ],
        if (botonGestionar != null) ...[
          const SizedBox(height: 10),
          botonGestionar,
        ],
        if (atajos.isNotEmpty) ...[
          const SizedBox(height: 10),
          Row(children: [
            for (final (k, (icono, texto, f)) in atajos.indexed) ...[
              if (k > 0) const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton(
                  onPressed: f,
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size.fromHeight(46),
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    foregroundColor: VenueColors.texto,
                    backgroundColor: VenueColors.superficie2,
                    side: BorderSide(color: VenueColors.linea),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      Icon(icono, size: 20),
                      const SizedBox(width: 8),
                      Text(texto, style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w500)),
                    ]),
                  ),
                ),
              ),
            ],
          ]),
        ],
      ]),
    );
  }
}

/// Pantalla de un evento: su portada, cómo se ve la entrada en cada fase
/// (se elige la fase arriba y se ve el ticket) y todo lo que se le puede
/// tocar. Las acciones son las mismas de la tarjeta del inicio.
class _EventoDetalle extends ConsumerStatefulWidget {
  const _EventoDetalle({required this.eventoId, required this.alAccion});
  final String eventoId;
  final Future<void> Function(String) alAccion;

  @override
  ConsumerState<_EventoDetalle> createState() => _EventoDetalleState();
}

class _EventoDetalleState extends ConsumerState<_EventoDetalle> {
  late Future<List<Fila>> _fases = _cargarFases();

  /// Fase de la vista previa (null: la vigente o la primera).
  String? _fase;
  bool _saliendo = false;

  Future<List<Fila>> _cargarFases() => ref.read(gestionRepositoryProvider).fases(widget.eventoId);

  Future<void> _hacer(String k) async {
    await widget.alAccion(k);
    if (mounted) setState(() => _fases = _cargarFases());
  }

  Future<void> _arteDeFase(Fila f) async {
    try {
      final b = await elegirImagen(lado: 1400);
      if (b == null) return;
      final url = await ref.read(archivosProvider).subirDiseno(b, 'fase-${f['id']}.jpg');
      await ref.read(gestionRepositoryProvider).arteDeFase(f['id'] as String, url);
      if (mounted) {
        setState(() => _fases = _cargarFases());
        avisar(context, 'Arte de ${f['nombre']} actualizado');
      }
    } catch (e) {
      if (mounted) avisar(context, mensajeDeError(e), tipo: TipoAviso.aviso);
    }
  }

  @override
  Widget build(BuildContext context) {
    final lista = ref.watch(eventosGestionProvider).value;
    final e = lista?.where((x) => x['id'] == widget.eventoId).firstOrNull;
    // eliminado o cerrado: vuelve al inicio
    if (lista != null && (e == null || e['estado'] == 'cerrado')) {
      if (!_saliendo) {
        _saliendo = true;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) Navigator.of(context).maybePop();
        });
      }
      return const Scaffold();
    }
    if (e == null) return const Scaffold(body: Center(child: CircularProgressIndicator()));

    final a = accionesDeEvento(e);
    final club = ref.watch(clubActivoProvider);
    final marca = Theme.of(context).colorScheme.primary;
    String hora(dynamic h) => '$h'.padRight(5).substring(0, 5);
    final fecha = DateTime.tryParse('${e['fecha']}');
    final fechaTxt = fecha == null ? '${e['fecha']}' : fechaLarga(fecha);
    final horario = e['hora_inicio'] == null ? null : '${hora(e['hora_inicio'])} – ${hora(e['hora_fin'])} hs';
    final imagen = e['ticket_url'] as String?;
    final conImagen = imagen != null && imagen.isNotEmpty;
    final porFases = e['venta_por_fases'] == true;
    final borrador = e['publicado'] == false;

    final portada = SizedBox(
      height: 300,
      child: Stack(fit: StackFit.expand, children: [
        if (conImagen)
          Image.network(imagen, fit: BoxFit.cover,
              errorBuilder: (_, _, _) => ColoredBox(color: Color.lerp(marca, Colors.black, .7)!))
        else
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color.lerp(marca, Colors.black, .3)!, Color.lerp(marca, Colors.black, .8)!],
              ),
            ),
          ),
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Colors.black.withValues(alpha: .45),
                Colors.black.withValues(alpha: .10),
                Colors.black.withValues(alpha: .85),
              ],
              stops: const [0, .4, 1],
            ),
          ),
        ),
        SafeArea(
          bottom: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 4, 12, 18),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                _BotonRedondo(
                  icono: Icons.arrow_back_rounded,
                  tooltip: 'Volver',
                  alTocar: () => Navigator.of(context).maybePop(),
                ),
                const Spacer(),
                _BotonRedondo(
                  icono: Icons.image_outlined,
                  tooltip: 'Cambiar imagen',
                  alTocar: () => _hacer('arte'),
                ),
              ]),
              const Spacer(),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: .18),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(borrador ? 'Borrador · solo lo ves vos' : 'Publicado',
                        style: const TextStyle(
                            color: Colors.white, fontSize: 12.5, fontWeight: FontWeight.w600)),
                  ),
                  const SizedBox(height: 10),
                  Text('${e['nombre']}',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          color: Colors.white, fontSize: 30, height: 1.05, fontWeight: FontWeight.w800)),
                  const SizedBox(height: 6),
                  Text([fechaTxt, ?horario, 'Manilla ${e['precio_manilla']} Bs'].join(' · '),
                      style: TextStyle(color: Colors.white.withValues(alpha: .88), fontSize: 14.5)),
                ]),
              ),
            ]),
          ),
        ),
      ]),
    );

    Widget fila(IconData icono, Color color, String titulo, String? detalle, String accion,
            {bool peligro = false}) =>
        ListTile(
          contentPadding: const EdgeInsets.fromLTRB(14, 4, 10, 4),
          leading: Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(color: color.withValues(alpha: .14), shape: BoxShape.circle),
            child: Icon(icono, size: 21, color: color),
          ),
          title: Text(titulo,
              style: TextStyle(fontWeight: FontWeight.w600, color: peligro ? VenueColors.mal : null)),
          subtitle: detalle == null
              ? null
              : Text(detalle, style: TextStyle(color: VenueColors.textoSuave, fontSize: 13)),
          trailing: peligro ? null : Icon(Icons.chevron_right_rounded, color: VenueColors.textoTenue),
          onTap: () => _hacer(accion),
        );

    return Scaffold(
      body: ListView(
        padding: EdgeInsets.zero,
        children: [
          portada,
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              NumerosEvento(eventoId: widget.eventoId),
              if (a.publicar) ...[
                const SizedBox(height: 12),
                FilledButton.icon(
                  onPressed: () => _hacer('publicar'),
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(52),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                  icon: const Icon(Icons.campaign_rounded, size: 20),
                  label: const Text('Publicar evento'),
                ),
              ],
              const TituloBloque('Así se ve la entrada'),
              FutureBuilder<List<Fila>>(
                future: _fases,
                builder: (context, snap) {
                  final fs = porFases ? (snap.data ?? const <Fila>[]) : const <Fila>[];
                  final vigente = fs.where((f) => f['vigente'] == true).firstOrNull;
                  final elegida = fs.where((f) => f['id'] == _fase).firstOrNull ?? vigente ?? fs.firstOrNull;
                  final artePropio = (elegida?['ticket_url'] as String?)?.isNotEmpty ?? false;
                  final datos = TicketDatos(
                    payload: 'EVT:${widget.eventoId}:VISTA-PREVIA',
                    codigo: 'VISTA PREVIA',
                    cliente: 'Nombre del cliente',
                    boliche: club?.nombre ?? '',
                    evento: '${e['nombre']}',
                    fecha: fechaTxt,
                    tipo: elegida?['nombre'] as String? ?? 'Entrada prepagada',
                    color: club?.primario,
                    arteUrl: artePropio ? elegida!['ticket_url'] as String : imagen,
                    fase: artePropio ? null : elegida?['nombre'] as String?,
                  );
                  return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    // las fases como en la venta: se toca una y se ve su entrada
                    SizedBox(
                      height: 72,
                      child: ListView(
                        scrollDirection: Axis.horizontal,
                        children: [
                          if (fs.isEmpty)
                            _OpcionFase(
                              titulo: 'Precio único',
                              precio: '${e['precio_manilla']} Bs',
                              detalle: porFases ? 'sin fases cargadas' : 'sin fases',
                              elegida: true,
                              alTocar: () {},
                            ),
                          for (final f in fs) ...[
                            _OpcionFase(
                              titulo: '${f['nombre']}',
                              precio: '${f['precio']} Bs',
                              detalle: f['agotada'] == true
                                  ? 'agotada'
                                  : f['vigente'] == true
                                      ? 'a la venta'
                                      : f['cupo'] == null
                                          ? '${f['vendidas'] ?? 0} vendidas'
                                          : 'quedan ${f['quedan']}',
                              vigente: f['vigente'] == true,
                              elegida: f['id'] == elegida?['id'],
                              alTocar: () => setState(() => _fase = f['id'] as String),
                            ),
                            const SizedBox(width: 8),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    _VistaEntrada(datos: datos),
                    const SizedBox(height: 10),
                    Row(children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: elegida == null ? () => _hacer('arte') : () => _arteDeFase(elegida),
                          icon: const Icon(Icons.image_outlined, size: 18),
                          label: Text(elegida == null ? 'Cambiar imagen' : 'Arte de ${elegida['nombre']}'),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () => _hacer('fases'),
                          icon: const Icon(Icons.layers_outlined, size: 18),
                          label: Text(porFases ? 'Editar fases' : 'Vender por fases'),
                        ),
                      ),
                    ]),
                  ]);
                },
              ),
              const TituloBloque('Configuración'),
              Tarjeta(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Column(children: [
                  fila(Icons.edit_outlined, marca, 'Datos del evento',
                      [fechaTxt, ?horario, 'Manilla ${e['precio_manilla']} Bs'].join(' · '), 'editar'),
                  Divider(height: 1, indent: 68, color: VenueColors.lineaSuave),
                  fila(Icons.format_list_bulleted_rounded, VenueColors.aviso, 'Listas y cupos',
                      'Quién anota en cada lista y cuántos', 'listas'),
                  Divider(height: 1, indent: 68, color: VenueColors.lineaSuave),
                  fila(Icons.layers_outlined, VenueColors.info, 'Fases de preventa',
                      porFases ? 'Precio y stock por fase' : 'Apagado: un solo precio', 'fases'),
                  Divider(height: 1, indent: 68, color: VenueColors.lineaSuave),
                  fila(Icons.schedule_rounded, VenueColors.ok, 'Horario de venta',
                      'Desde y hasta cuándo se vende', 'horarios'),
                  Divider(height: 1, indent: 68, color: VenueColors.lineaSuave),
                  fila(Icons.image_outlined, marca, 'Imagen del evento',
                      conImagen ? 'Tocá para cambiarla' : 'Sin imagen', 'arte'),
                ]),
              ),
              const SizedBox(height: 16),
              Tarjeta(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Column(children: [
                  if (a.cerrar) ...[
                    fila(Icons.lock_outline_rounded, VenueColors.mal, 'Cerrar evento',
                        'Pasa al histórico; los datos se conservan', 'cerrar', peligro: true),
                    Divider(height: 1, indent: 68, color: VenueColors.lineaSuave),
                  ],
                  fila(Icons.delete_outline_rounded, VenueColors.mal, 'Eliminar evento',
                      'Borra todo lo del evento', 'eliminar', peligro: true),
                ]),
              ),
            ]),
          ),
        ],
      ),
    );
  }
}

class _BotonRedondo extends StatelessWidget {
  const _BotonRedondo({required this.icono, required this.tooltip, required this.alTocar});
  final IconData icono;
  final String tooltip;
  final VoidCallback alTocar;

  @override
  Widget build(BuildContext context) => Material(
        color: Colors.black.withValues(alpha: .35),
        shape: const CircleBorder(),
        child: IconButton(
          tooltip: tooltip,
          onPressed: alTocar,
          icon: Icon(icono, color: Colors.white),
        ),
      );
}

/// Una fase para elegir en la vista previa: nombre, precio y estado.
class _OpcionFase extends StatelessWidget {
  const _OpcionFase({
    required this.titulo,
    required this.precio,
    required this.detalle,
    required this.elegida,
    required this.alTocar,
    this.vigente = false,
  });
  final String titulo, precio, detalle;
  final bool elegida, vigente;
  final VoidCallback alTocar;

  @override
  Widget build(BuildContext context) {
    final marca = Theme.of(context).colorScheme.primary;
    return Material(
      color: elegida ? marca.withValues(alpha: .10) : VenueColors.superficie,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: elegida ? marca : VenueColors.linea, width: elegida ? 1.6 : 1),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: alTocar,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 10, 16, 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Row(mainAxisSize: MainAxisSize.min, children: [
                if (vigente) ...[
                  Container(
                    width: 7,
                    height: 7,
                    decoration: BoxDecoration(color: VenueColors.ok, shape: BoxShape.circle),
                  ),
                  const SizedBox(width: 6),
                ],
                Text(titulo, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14.5)),
                const SizedBox(width: 8),
                Text(precio,
                    style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14.5, color: marca)),
              ]),
              const SizedBox(height: 2),
              Text(detalle, style: TextStyle(fontSize: 12.5, color: VenueColors.textoSuave)),
            ],
          ),
        ),
      ),
    );
  }
}

/// El ticket dibujado como sale al venderlo. Se redibuja cuando cambia la
/// fase o el arte.
class _VistaEntrada extends StatefulWidget {
  const _VistaEntrada({required this.datos});
  final TicketDatos datos;

  @override
  State<_VistaEntrada> createState() => _VistaEntradaState();
}

class _VistaEntradaState extends State<_VistaEntrada> {
  late Future<Uint8List> _img = dibujarTicket(widget.datos);

  String _clave(TicketDatos d) => '${d.tipo}|${d.arteUrl}|${d.fase}|${d.evento}|${d.fecha}|${d.color}';

  @override
  void didUpdateWidget(_VistaEntrada old) {
    super.didUpdateWidget(old);
    if (_clave(old.datos) != _clave(widget.datos)) _img = dibujarTicket(widget.datos);
  }

  @override
  Widget build(BuildContext context) => Container(
        constraints: const BoxConstraints(maxHeight: 520),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: VenueColors.superficie2,
          borderRadius: BorderRadius.circular(radioTarjeta),
        ),
        padding: const EdgeInsets.all(12),
        child: FutureBuilder<Uint8List>(
          future: _img,
          builder: (context, s) {
            if (s.hasError) {
              return Padding(
                padding: const EdgeInsets.all(30),
                child: Text('No se pudo dibujar la vista previa',
                    style: TextStyle(color: VenueColors.textoSuave)),
              );
            }
            if (!s.hasData) {
              return const SizedBox(height: 260, child: Center(child: CircularProgressIndicator()));
            }
            return ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Image.memory(s.data!, fit: BoxFit.contain, gaplessPlayback: true),
            );
          },
        ),
      );
}

/// Anotados en listas, QR emitidos, mesas vendidas e ingresos por lista.
class NumerosEvento extends ConsumerWidget {
  const NumerosEvento({super.key, required this.eventoId});
  final String eventoId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final n = ref.watch(numerosEventoProvider(eventoId)).value;
    String v(int? x) => x == null ? '…' : '$x';
    return FilaFichas(children: [
      FichaDato(
          icono: Icons.groups_outlined, etiqueta: 'Listas', valor: v(n?.listas),
          color: VenueColors.aviso),
      FichaDato(icono: Icons.qr_code_2_rounded, etiqueta: 'QR', valor: v(n?.qr)),
      FichaDato(icono: Icons.table_bar_outlined, etiqueta: 'Mesas', valor: v(n?.mesas)),
      FichaDato(
          icono: Icons.how_to_reg_outlined, etiqueta: 'Entraron', valor: v(n?.ingresaron),
          color: VenueColors.ok),
    ]);
  }
}

class _NuevoEvento extends ConsumerStatefulWidget {
  const _NuevoEvento();
  @override
  ConsumerState<_NuevoEvento> createState() => _NuevoEventoState();
}

class _NuevoEventoState extends ConsumerState<_NuevoEvento> {
  final _n = TextEditingController();
  final _p = TextEditingController(text: '60'), _pct = TextEditingController(text: '50');
  final _cut = TextEditingController(text: '15');
  DateTime _fecha = DateTime.now();
  bool _ocupado = false;

  @override
  void dispose() {
    for (final c in [_n, _p, _pct, _cut]) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final club = ref.watch(clubActivoIdProvider)!;
    final f = _fecha.toIso8601String().substring(0, 10);
    return ListView(
      shrinkWrap: true,
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
      children: [
        const Text('Nuevo evento', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
        const SizedBox(height: 12),
        TextField(
            controller: _n,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(labelText: 'Nombre')),
        const SizedBox(height: 10),
        InkWell(
          onTap: () async {
            final d = await showDatePicker(
                context: context, initialDate: _fecha,
                firstDate: DateTime.now().subtract(const Duration(days: 30)),
                lastDate: DateTime.now().add(const Duration(days: 730)));
            if (d != null) setState(() => _fecha = d);
          },
          child: InputDecorator(
              decoration: const InputDecoration(labelText: 'Fecha'), child: Text(f)),
        ),
        const SizedBox(height: 10),
        Row(children: [
          Expanded(child: TextField(controller: _p, keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Precio manilla'))),
          const SizedBox(width: 8),
          Expanded(child: TextField(controller: _pct, keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: '% boliche'))),
          const SizedBox(width: 8),
          Expanded(child: TextField(controller: _cut, keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Bs por manilla al RRPP'))),
        ]),
        const SizedBox(height: 8),
        Text('Nace como borrador, con las listas "Invitados" y "Free Cover Girls".',
            style: TextStyle(color: VenueColors.textoSuave, fontSize: 12.5)),
        const SizedBox(height: 14),
        FilledButton(
          onPressed: _ocupado
              ? null
              : () async {
                  final precio = num.tryParse(_p.text) ?? 60, pct = num.tryParse(_pct.text) ?? 50;
                  final cut = num.tryParse(_cut.text) ?? 15;
                  final mal = validarEvento(
                      nombre: _n.text, fecha: f, precio: precio, pctBoliche: pct, cut: cut);
                  if (mal != null) {
                    avisar(context, mal, tipo: TipoAviso.aviso);
                    return;
                  }
                  setState(() => _ocupado = true);
                  try {
                    await ref.read(gestionRepositoryProvider).crear(club,
                        nombre: _n.text, fecha: f, precio: precio, pctBoliche: pct, cut: cut);
                    if (!context.mounted) return;
                    Navigator.pop(context, true);
                    avisar(context, 'Evento creado como borrador');
                  } catch (e) {
                    if (context.mounted) {
                      avisar(context, mensajeDeError(e), tipo: TipoAviso.aviso);
                      setState(() => _ocupado = false);
                    }
                  }
                },
          child: const Text('Crear evento'),
        ),
      ],
    );
  }
}

class _EditarEvento extends ConsumerStatefulWidget {
  const _EditarEvento({required this.evento});
  final Fila evento;
  @override
  ConsumerState<_EditarEvento> createState() => _EditarEventoState();
}

class _EditarEventoState extends ConsumerState<_EditarEvento> {
  late final e = widget.evento;
  late final _n = TextEditingController(text: '${e['nombre']}');
  late final _f = TextEditingController(text: '${e['fecha']}');
  late final _p = TextEditingController(text: '${e['precio_manilla']}');
  late final _pct = TextEditingController(text: '${e['pct_boliche']}');
  late final _cut = TextEditingController(text: '${e['cut_rrpp'] ?? 15}');
  late final _hi = TextEditingController(text: '${e['hora_inicio']}'.substring(0, 5));
  late final _hf = TextEditingController(text: '${e['hora_fin']}'.substring(0, 5));
  late final _hr = TextEditingController(text: '${e['horas_reserva'] ?? 3}');
  late DateTime? _qr = _dt(e['entrada_hasta']);
  late bool _res = e['permite_reserva'] != false, _agr = e['permite_agrupar'] != false;
  late bool _cxm = e['combo_por_mesa'] == true, _cob = e['combo_obligatorio'] != false;

  @override
  void dispose() {
    for (final c in [_n, _f, _p, _pct, _cut, _hi, _hf, _hr]) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    Widget campo(String l, TextEditingController c, {bool num = false}) => Expanded(
          child: TextField(
              controller: c,
              keyboardType: num ? TextInputType.number : null,
              decoration: InputDecoration(labelText: l, isDense: true)),
        );
    Widget sw(String t, String s, bool v, ValueChanged<bool> f) => SwitchListTile(
        contentPadding: EdgeInsets.zero, dense: true, title: Text(t), subtitle: Text(s),
        value: v, onChanged: f);
    return ListView(
      shrinkWrap: true,
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
      children: [
        const Text('Editar evento', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
        const SizedBox(height: 12),
        TextField(controller: _n, decoration: const InputDecoration(labelText: 'Nombre', isDense: true)),
        const SizedBox(height: 10),
        Row(children: [campo('Fecha (AAAA-MM-DD)', _f), const SizedBox(width: 8), campo('Precio manilla', _p, num: true)]),
        const SizedBox(height: 10),
        Row(children: [campo('% boliche', _pct, num: true), const SizedBox(width: 8), campo('Bs por manilla al RRPP', _cut, num: true)]),
        const SizedBox(height: 10),
        Row(children: [campo('Hora inicio (HH:MM)', _hi), const SizedBox(width: 8), campo('Hora fin (HH:MM)', _hf)]),
        const SizedBox(height: 10),
        CampoFechaHora(
            etiqueta: 'Ingreso con QR hasta', valor: _qr, alCambiar: (v) => setState(() => _qr = v)),
        const Divider(height: 24),
        const Text('Mesas', style: TextStyle(fontWeight: FontWeight.w800)),
        sw('Permitir reservas', 'Si no, las mesas se venden solo pagadas', _res, (v) => setState(() => _res = v)),
        if (_res)
          Row(children: [campo('Horas para pagar una reserva (1 a 24)', _hr, num: true)]),
        sw('Permitir unir mesas', 'Vender varias mesas en una sola venta', _agr, (v) => setState(() => _agr = v)),
        sw('Combo por mesa', 'En un grupo, cada mesa paga su combo', _cxm, (v) => setState(() => _cxm = v)),
        sw('Combo obligatorio', 'No se vende una mesa sin combo', _cob, (v) => setState(() => _cob = v)),
        const SizedBox(height: 10),
        FilledButton(
          onPressed: () async {
            final precio = num.tryParse(_p.text) ?? 0, pct = num.tryParse(_pct.text) ?? 0;
            final cut = num.tryParse(_cut.text) ?? 15;
            final mal = validarEvento(
                nombre: _n.text, fecha: _f.text.trim(), precio: precio, pctBoliche: pct, cut: cut);
            final hhmm = RegExp(r'^([01]\d|2[0-3]):[0-5]\d$');
            if (mal != null || !hhmm.hasMatch(_hi.text.trim()) || !hhmm.hasMatch(_hf.text.trim())) {
              avisar(context, mal ?? 'Las horas van como HH:MM', tipo: TipoAviso.aviso);
              return;
            }
            try {
              await ref.read(gestionRepositoryProvider).editar(e['id'] as String, {
                'nombre': _n.text.trim(), 'fecha': _f.text.trim(), 'precio_manilla': precio,
                'pct_boliche': pct, 'cut_rrpp': cut, 'hora_inicio': _hi.text.trim(),
                'hora_fin': _hf.text.trim(), 'entrada_hasta': _qr?.toUtc().toIso8601String(),
                'permite_reserva': _res,
                'horas_reserva': (_int(_hr) ?? 3).clamp(1, 24),
                'permite_agrupar': _agr, 'combo_por_mesa': _cxm, 'combo_obligatorio': _cob,
              });
              if (!context.mounted) return;
              Navigator.pop(context, true);
              avisar(context, 'Evento actualizado');
            } catch (x) {
              if (context.mounted) avisar(context, mensajeDeError(x), tipo: TipoAviso.aviso);
            }
          },
          child: const Text('Guardar'),
        ),
      ],
    );
  }
}

// ── listas y cupos ──
class _Listas extends ConsumerStatefulWidget {
  const _Listas({required this.eventoId, required this.nombre});
  final String eventoId;
  final String nombre;
  @override
  ConsumerState<_Listas> createState() => _ListasState();
}

class _ListasState extends ConsumerState<_Listas> {
  late Future<List<Fila>> _f = _cargar();
  Future<List<Fila>> _cargar() => ref.read(gestionRepositoryProvider).listas(widget.eventoId);
  void _recargar() => setState(() => _f = _cargar());

  @override
  Widget build(BuildContext context) {
    final repo = ref.read(gestionRepositoryProvider);
    return FutureBuilder(
      future: _f,
      builder: (context, s) {
        final ls = s.data ?? const <Fila>[];
        return ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
          children: [
            Text('Listas · ${widget.nombre}',
                style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
            if (!s.hasData)
              const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator())),
            for (var i = 0; i < ls.length; i++)
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text('${ls[i]['nombre']}', style: const TextStyle(fontWeight: FontWeight.w700)),
                subtitle: Text([
                  if (ls[i]['cupo_por_rrpp'] != null) '${ls[i]['cupo_por_rrpp']} por RRPP',
                  if (ls[i]['cupo_jefe'] != null) '${ls[i]['cupo_jefe']} por jefe',
                  if (ls[i]['cupo_total'] != null) 'total ${ls[i]['cupo_total']}',
                  'anotan hasta ${_fh(ls[i]['registro_hasta'])}',
                  if (ls[i]['ingreso_hasta'] != null) 'entran hasta ${'${ls[i]['ingreso_hasta']}'.substring(0, 5)}',
                  if (ls[i]['precio'] != null) '${ls[i]['precio']} Bs',
                ].join(' · ')),
                trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                  if (i > 0)
                    IconButton(
                        tooltip: 'Subir',
                        icon: const Icon(Icons.arrow_upward_rounded),
                        onPressed: () async {
                          await repo.intercambiarOrden(ls[i], ls[i - 1]);
                          _recargar();
                        }),
                  const Icon(Icons.edit_outlined),
                ]),
                onTap: () async {
                  await _hoja(context, _ListaForm(eventoId: widget.eventoId, lista: ls[i], orden: i));
                  _recargar();
                },
              ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: () async {
                await _hoja(context, _ListaForm(eventoId: widget.eventoId, orden: ls.length));
                _recargar();
              },
              icon: const Icon(Icons.add_rounded),
              label: const Text('Nueva lista'),
            ),
          ],
        );
      },
    );
  }
}

class _ListaForm extends ConsumerStatefulWidget {
  const _ListaForm({required this.eventoId, required this.orden, this.lista});
  final String eventoId;
  final int orden;
  final Fila? lista;
  @override
  ConsumerState<_ListaForm> createState() => _ListaFormState();
}

class _ListaFormState extends ConsumerState<_ListaForm> {
  late final l = widget.lista;
  String _t(String k) => l?[k] == null ? '' : '${l![k]}';
  late final _n = TextEditingController(text: _t('nombre'));
  late final _c = TextEditingController(text: _t('cupo_por_rrpp'));
  late final _cj = TextEditingController(text: _t('cupo_jefe'));
  late final _ca = TextEditingController(text: _t('cupo_admin'));
  late final _tot = TextEditingController(text: _t('cupo_total'));
  late final _ing = TextEditingController(
      text: l?['ingreso_hasta'] == null ? '' : '${l!['ingreso_hasta']}'.substring(0, 5));
  late final _precio = TextEditingController(text: _t('precio'));
  late DateTime? _d = _dt(l?['registro_desde']), _h = _dt(l?['registro_hasta']);

  @override
  void dispose() {
    for (final c in [_n, _c, _cj, _ca, _tot, _ing, _precio]) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final repo = ref.read(gestionRepositoryProvider);
    final club = ref.watch(clubActivoIdProvider)!;
    Widget nro(String e, TextEditingController c) => Expanded(
        child: TextField(
            controller: c,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(labelText: e, isDense: true, hintText: 'sin tope')));

    Future<void> guardar() async {
      if (_n.text.trim().isEmpty) {
        avisar(context, 'Poné el nombre', tipo: TipoAviso.aviso);
        return;
      }
      final ing = _ing.text.trim();
      if (ing.isNotEmpty && !RegExp(r'^([01]\d|2[0-3]):[0-5]\d$').hasMatch(ing)) {
        avisar(context, 'La hora tope de ingreso va como HH:MM', tipo: TipoAviso.aviso);
        return;
      }
      final precio = _precio.text.trim().isEmpty ? null : num.tryParse(_precio.text.trim());
      if (precio != null && precio < 0) {
        avisar(context, 'El precio no puede ser negativo', tipo: TipoAviso.aviso);
        return;
      }
      final campos = <String, dynamic>{
        'nombre': _n.text.trim(), 'cupo_por_rrpp': _int(_c), 'cupo_jefe': _int(_cj),
        'cupo_admin': _int(_ca), 'cupo_total': _int(_tot),
        'registro_desde': _d?.toUtc().toIso8601String(),
        'registro_hasta': _h?.toUtc().toIso8601String(),
        'ingreso_hasta': ing.isEmpty ? null : ing, 'precio': precio,
      };
      try {
        l == null
            ? await repo.crearLista(widget.eventoId, campos, widget.orden)
            : await repo.editarLista(l!['id'] as String, campos);
        if (!context.mounted) return;
        Navigator.pop(context);
        avisar(context, l == null ? 'Lista creada' : 'Lista actualizada');
      } catch (e) {
        if (context.mounted) avisar(context, mensajeDeError(e), tipo: TipoAviso.aviso);
      }
    }

    return ListView(
      shrinkWrap: true,
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
      children: [
        Text(l == null ? 'Nueva lista' : 'Editar lista',
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
        const SizedBox(height: 12),
        TextField(controller: _n, decoration: const InputDecoration(labelText: 'Nombre', isDense: true)),
        const SizedBox(height: 10),
        Row(children: [nro('Cupo por RRPP', _c), const SizedBox(width: 8), nro('Cupo por jefe', _cj)]),
        const SizedBox(height: 10),
        Row(children: [nro('Cupo del admin', _ca), const SizedBox(width: 8), nro('Cupo total', _tot)]),
        const SizedBox(height: 10),
        CampoFechaHora(etiqueta: 'Se anota desde', valor: _d, alCambiar: (v) => setState(() => _d = v)),
        const SizedBox(height: 10),
        CampoFechaHora(etiqueta: 'Se anota hasta', valor: _h, alCambiar: (v) => setState(() => _h = v)),
        const SizedBox(height: 10),
        Row(children: [
          Expanded(
            child: TextField(
                controller: _ing,
                decoration: const InputDecoration(
                    labelText: 'Entran hasta (HH:MM)', isDense: true, hintText: 'sin tope')),
          ),
          const SizedBox(width: 8),
          nro('Precio (Compra en puerta)', _precio),
        ]),
        const SizedBox(height: 14),
        FilledButton(onPressed: guardar, child: const Text('Guardar')),
        if (l != null) ...[
          const SizedBox(height: 9),
          OutlinedButton(
            style: OutlinedButton.styleFrom(foregroundColor: VenueColors.mal),
            onPressed: () async {
              try {
                await repo.borrarLista(l!['id'] as String);
                if (!context.mounted) return;
                Navigator.pop(context);
                avisar(context, 'Lista eliminada', tipo: TipoAviso.aviso);
              } catch (e) {
                if (context.mounted) {
                  avisar(context,
                      'No se puede eliminar: tiene invitados anotados. ${mensajeDeError(e)}',
                      tipo: TipoAviso.aviso);
                }
              }
            },
            child: const Text('Eliminar lista'),
          ),
          const Divider(height: 28),
          const Text('Cupos especiales', style: TextStyle(fontWeight: FontWeight.w800)),
          Text(
              'El cupo de acá manda sobre el general. Ejemplo: la lista da 1 invitado a cada relacionador, pero a una persona puntual le das 3.',
              style: TextStyle(color: VenueColors.textoSuave, fontSize: 12.5, height: 1.35)),
          _CuposEspeciales(listaId: l!['id'] as String, club: club),
        ],
      ],
    );
  }
}

/// Cupos especiales de una lista con filtros: buscar por nombre, por team y
/// por rol, ver quién ya tiene uno, y darle el mismo cupo a todos los que
/// quedaron filtrados (por ejemplo, 3 a todo un team).
class _CuposEspeciales extends ConsumerStatefulWidget {
  const _CuposEspeciales({required this.listaId, required this.club});
  final String listaId;
  final String club;
  @override
  ConsumerState<_CuposEspeciales> createState() => _CuposEspecialesState();
}

class _CuposEspecialesState extends ConsumerState<_CuposEspeciales> {
  late Future<List<List<Fila>>> _f = _cargar();
  String _q = '';
  String? _team;
  String? _rol;
  final _todos = TextEditingController();

  Future<List<List<Fila>>> _cargar() {
    final repo = ref.read(gestionRepositoryProvider);
    return Future.wait([repo.cuposDeLista(widget.listaId), repo.personasConCupo(widget.club)]);
  }

  void _recargar() => setState(() => _f = _cargar());

  @override
  void dispose() {
    _todos.dispose();
    super.dispose();
  }

  Future<void> _hacer(Future<void> Function() f, String ok) async {
    try {
      await f();
      _recargar();
      if (mounted) avisar(context, ok);
    } catch (e) {
      if (mounted) avisar(context, mensajeDeError(e), tipo: TipoAviso.aviso);
    }
  }

  Future<void> _editar(Fila g, int? actual) async {
    final c = TextEditingController(text: actual?.toString() ?? '');
    final r = await showDialog<String>(
      context: context,
      builder: (d) => AlertDialog(
        title: Text('Cupo de ${g['nombre']}'),
        content: TextField(
          controller: c,
          autofocus: true,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(labelText: 'Invitados en esta lista'),
        ),
        actions: [
          if (actual != null)
            TextButton(
                onPressed: () => Navigator.pop(d, 'quitar'),
                style: TextButton.styleFrom(foregroundColor: VenueColors.mal),
                child: const Text('Quitar')),
          TextButton(onPressed: () => Navigator.pop(d), child: const Text('Cancelar')),
          FilledButton(
              style: FilledButton.styleFrom(minimumSize: const Size(0, 42)),
              onPressed: () => Navigator.pop(d, c.text),
              child: const Text('Guardar')),
        ],
      ),
    );
    if (r == null) return;
    final repo = ref.read(gestionRepositoryProvider);
    final id = g['id'] as String;
    if (r == 'quitar') {
      return _hacer(() => repo.quitarCupo(widget.listaId, id), 'Cupo especial quitado');
    }
    final n = int.tryParse(r.trim());
    if (n == null || n < 0) return;
    await _hacer(() => repo.fijarCupo(widget.listaId, id, n), 'Cupo de ${g['nombre']}: $n');
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder(
      future: _f,
      builder: (context, s) {
        if (!s.hasData) {
          return const Padding(
              padding: EdgeInsets.all(16), child: Center(child: CircularProgressIndicator()));
        }
        final cupos = {for (final c in s.data![0]) c['user_id'] as String: (c['cupo'] as num).toInt()};
        final gente = s.data![1];
        final teams = {for (final g in gente) '${g['team'] ?? 'Sin team'}'}.toList()..sort();
        final q = normalizar(_q.trim());
        final filtrados = gente.where((g) {
          if (_team != null && '${g['team'] ?? 'Sin team'}' != _team) return false;
          if (_rol != null && g['rol'] != _rol) return false;
          return q.isEmpty || normalizar('${g['nombre']} ${g['usuario'] ?? ''}').contains(q);
        }).toList()
          ..sort((a, b) {
            // primero los que ya tienen cupo especial
            final ca = cupos.containsKey(a['id']) ? 0 : 1, cb = cupos.containsKey(b['id']) ? 0 : 1;
            return ca != cb ? ca - cb : '${a['nombre']}'.compareTo('${b['nombre']}');
          });

        Widget chip(String t, bool on, VoidCallback f) => Padding(
              padding: const EdgeInsets.only(right: 6),
              child: ChoiceChip(label: Text(t), selected: on, onSelected: (_) => f()),
            );

        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const SizedBox(height: 8),
          TextField(
            onChanged: (v) => setState(() => _q = v),
            decoration: const InputDecoration(
                hintText: 'Buscar persona…', prefixIcon: Icon(Icons.search_rounded), isDense: true),
          ),
          const SizedBox(height: 8),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(children: [
              chip('Todos los teams', _team == null, () => setState(() => _team = null)),
              for (final t in teams) chip(t, _team == t, () => setState(() => _team = t)),
            ]),
          ),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(children: [
              chip('Todos', _rol == null, () => setState(() => _rol = null)),
              chip('Relacionadores', _rol == 'rrpp', () => setState(() => _rol = 'rrpp')),
              chip('Jefes', _rol == 'jefe', () => setState(() => _rol = 'jefe')),
              chip('Admins', _rol == 'admin', () => setState(() => _rol = 'admin')),
            ]),
          ),
          const SizedBox(height: 8),
          // el mismo cupo a todos los filtrados (un team entero, por ejemplo)
          Row(children: [
            Expanded(
              child: Text('Dar a los ${filtrados.length} filtrados',
                  style: const TextStyle(fontWeight: FontWeight.w700)),
            ),
            SizedBox(
              width: 72,
              child: TextField(
                  controller: _todos,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Cupo', isDense: true)),
            ),
            const SizedBox(width: 6),
            IconButton.filledTonal(
              tooltip: 'Aplicar a todos los filtrados',
              onPressed: filtrados.isEmpty
                  ? null
                  : () {
                      final n = int.tryParse(_todos.text.trim());
                      if (n == null || n < 0) {
                        avisar(context, 'Poné la cantidad', tipo: TipoAviso.aviso);
                        return;
                      }
                      final repo = ref.read(gestionRepositoryProvider);
                      _hacer(() async {
                        for (final g in filtrados) {
                          await repo.fijarCupo(widget.listaId, g['id'] as String, n);
                        }
                      }, '${filtrados.length} personas con cupo $n');
                    },
              icon: const Icon(Icons.done_all_rounded),
            ),
          ]),
          const SizedBox(height: 4),
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 340),
            child: ListView(
              shrinkWrap: true,
              children: [
                if (filtrados.isEmpty)
                  Padding(
                    padding: EdgeInsets.all(16),
                    child: Text('Nadie coincide con el filtro.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: VenueColors.textoSuave)),
                  ),
                for (final g in filtrados)
                  ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    title: Text('${g['nombre']}', style: const TextStyle(fontWeight: FontWeight.w600)),
                    subtitle: Text('${g['team'] ?? 'Sin team'} · ${g['rol'] ?? ''}'),
                    trailing: cupos.containsKey(g['id'])
                        ? Chip(
                            label: Text('cupo ${cupos[g['id']]}'),
                            visualDensity: VisualDensity.compact,
                            side: BorderSide(color: Theme.of(context).colorScheme.primary))
                        : Text('general', style: TextStyle(color: VenueColors.textoSuave)),
                    onTap: () => _editar(g, cupos[g['id']]),
                  ),
              ],
            ),
          ),
        ]);
      },
    );
  }
}

// ── fases de preventa ──
class _Fases extends ConsumerStatefulWidget {
  const _Fases({required this.evento});
  final Fila evento;
  @override
  ConsumerState<_Fases> createState() => _FasesState();
}

class _FasesState extends ConsumerState<_Fases> {
  late bool _on = widget.evento['venta_por_fases'] == true;
  late Future<List<Fila>> _f = _cargar();
  String get _id => widget.evento['id'] as String;
  Future<List<Fila>> _cargar() => ref.read(gestionRepositoryProvider).fases(_id);
  void _recargar() => setState(() => _f = _cargar());

  Future<void> _form([Fila? f]) async {
    final n = TextEditingController(text: f == null ? '' : '${f['nombre']}');
    final p = TextEditingController(text: f == null ? '' : '${f['precio']}');
    final c = TextEditingController(text: f?['cupo'] == null ? '' : '${f!['cupo']}');
    final o = TextEditingController(text: '${f?['orden'] ?? 1}');
    DateTime? d = _dt(f?['desde']), h = _dt(f?['hasta']);
    final ok = await _hoja<bool>(
      context,
      StatefulBuilder(
        builder: (context, set) => ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
          children: [
            Text(f == null ? 'Nueva fase' : 'Editar fase',
                style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
            const SizedBox(height: 12),
            TextField(controller: n, decoration: const InputDecoration(labelText: 'Nombre', hintText: 'Hot Tickets', isDense: true)),
            const SizedBox(height: 10),
            Row(children: [
              Expanded(child: TextField(controller: p, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Precio Bs', isDense: true))),
              const SizedBox(width: 8),
              Expanded(child: TextField(controller: c, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Stock', hintText: 'sin tope', isDense: true))),
              const SizedBox(width: 8),
              SizedBox(width: 70, child: TextField(controller: o, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Orden', isDense: true))),
            ]),
            const SizedBox(height: 10),
            CampoFechaHora(etiqueta: 'Abre', valor: d, alCambiar: (v) => set(() => d = v)),
            const SizedBox(height: 10),
            CampoFechaHora(etiqueta: 'Cierra', valor: h, alCambiar: (v) => set(() => h = v)),
            const SizedBox(height: 14),
            FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Guardar')),
          ],
        ),
      ),
    );
    if (ok != true || n.text.trim().isEmpty) return;
    try {
      await ref.read(gestionRepositoryProvider).guardarFase(_id,
          id: f?['id'] as String?, nombre: n.text, precio: num.tryParse(p.text) ?? 0,
          cupo: int.tryParse(c.text), desde: d, hasta: h, orden: int.tryParse(o.text) ?? 0);
      _recargar();
    } catch (e) {
      if (mounted) avisar(context, mensajeDeError(e), tipo: TipoAviso.aviso);
    }
  }

  @override
  Widget build(BuildContext context) {
    final repo = ref.read(gestionRepositoryProvider);
    return FutureBuilder(
      future: _f,
      builder: (context, s) {
        final fs = s.data ?? const <Fila>[];
        return ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
          children: [
            Text('Fases de preventa · ${widget.evento['nombre']}',
                style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Vender por fases'),
              subtitle: const Text(
                  'Cada fase tiene su precio y su stock: cuando se agota una, sigue la siguiente. Apagado, el evento vende con un solo precio.'),
              value: _on,
              onChanged: (v) async {
                try {
                  await repo.ventaPorFases(_id, v);
                  setState(() => _on = v);
                } catch (e) {
                  if (context.mounted) avisar(context, mensajeDeError(e), tipo: TipoAviso.aviso);
                }
              },
            ),
            for (final f in fs)
              Card(
                margin: const EdgeInsets.only(top: 8),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(14, 8, 4, 8),
                  child: Row(children: [
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text('${f['nombre']} · ${f['precio']} Bs',
                            style: const TextStyle(fontWeight: FontWeight.w800)),
                        Text(
                          [
                            '${f['vendidas'] ?? 0} vendidas',
                            if (f['cupo'] != null) 'quedan ${f['quedan']}',
                            if (f['vigente'] == true) 'VIGENTE',
                            if (f['agotada'] == true) 'agotada',
                            if (f['ticket_url'] != null) 'con arte propio',
                          ].join(' · '),
                          style: TextStyle(
                              color: f['vigente'] == true ? VenueColors.ok : VenueColors.textoSuave,
                              fontSize: 13),
                        ),
                      ]),
                    ),
                    PopupMenuButton<String>(
                      onSelected: (k) async {
                        try {
                          switch (k) {
                            case 'editar':
                              await _form(f);
                            case 'arte':
                              final b = await elegirImagen(lado: 1400);
                              if (b == null) return;
                              final url = await ref.read(archivosProvider)
                                  .subirDiseno(b, 'fase-${f['id']}.jpg');
                              await repo.arteDeFase(f['id'] as String, url);
                              _recargar();
                            case 'cupos':
                              await _hoja(context, _CuposFase(fase: f));
                            case 'borrar':
                              await repo.borrarFase(f['id'] as String);
                              _recargar();
                          }
                        } catch (e) {
                          if (context.mounted) avisar(context, mensajeDeError(e), tipo: TipoAviso.aviso);
                        }
                      },
                      itemBuilder: (_) => const [
                        PopupMenuItem(value: 'editar', child: Text('Editar')),
                        PopupMenuItem(value: 'cupos', child: Text('Cupos por team')),
                        PopupMenuItem(value: 'arte', child: Text('Arte de la fase')),
                        PopupMenuItem(value: 'borrar', child: Text('Eliminar')),
                      ],
                    ),
                  ]),
                ),
              ),
            const SizedBox(height: 10),
            OutlinedButton.icon(
                onPressed: _form, icon: const Icon(Icons.add_rounded), label: const Text('Nueva fase')),
          ],
        );
      },
    );
  }
}

class _CuposFase extends ConsumerStatefulWidget {
  const _CuposFase({required this.fase});
  final Fila fase;
  @override
  ConsumerState<_CuposFase> createState() => _CuposFaseState();
}

class _CuposFaseState extends ConsumerState<_CuposFase> {
  int _v = 0;

  @override
  Widget build(BuildContext context) {
    final repo = ref.read(gestionRepositoryProvider);
    return FutureBuilder(
      key: ValueKey(_v),
      future: repo.cuposPorTeam(widget.fase['id'] as String),
      builder: (context, s) => ListView(
        shrinkWrap: true,
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
        children: [
          Text('Cupos por team · ${widget.fase['nombre']}',
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
          Text('Cuántas entradas de esta fase puede vender cada team. Vacío o 0 = sin tope propio.',
              style: TextStyle(color: VenueColors.textoSuave)),
          if (!s.hasData)
            const Padding(padding: EdgeInsets.all(20), child: Center(child: CircularProgressIndicator())),
          for (final t in s.data ?? const <Fila>[])
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Row(children: [
                Expanded(
                  child: Text('${t['team']} · ${t['vendidas'] ?? 0} vendidas',
                      style: const TextStyle(fontWeight: FontWeight.w600)),
                ),
                SizedBox(
                  width: 96,
                  child: TextFormField(
                    initialValue: t['cupo'] == null ? '' : '${t['cupo']}',
                    keyboardType: TextInputType.number,
                    textAlign: TextAlign.center,
                    decoration: const InputDecoration(isDense: true, hintText: 'sin tope'),
                    onFieldSubmitted: (v) async {
                      try {
                        await repo.fijarCupoTeam(widget.fase['id'] as String,
                            t['team_id'] as String, int.tryParse(v) ?? 0);
                        setState(() => _v++);
                        if (context.mounted) avisar(context, 'Cupo de ${t['team']} guardado');
                      } catch (e) {
                        if (context.mounted) avisar(context, mensajeDeError(e), tipo: TipoAviso.aviso);
                      }
                    },
                  ),
                ),
              ]),
            ),
        ],
      ),
    );
  }
}

// ── horario de venta y excepciones ──
class _Horarios extends ConsumerStatefulWidget {
  const _Horarios({required this.evento});
  final Fila evento;
  @override
  ConsumerState<_Horarios> createState() => _HorariosState();
}

class _HorariosState extends ConsumerState<_Horarios> {
  late DateTime? _d = _dt(widget.evento['manilla_desde']), _h = _dt(widget.evento['manilla_hasta_ts']);
  DateTime? _hasta;
  bool _porTeam = true;
  String? _quien;
  int _v = 0;
  String get _id => widget.evento['id'] as String;

  @override
  Widget build(BuildContext context) {
    final repo = ref.read(gestionRepositoryProvider);
    final teams = ref.watch(teamsInfoProvider).value ?? const <TeamInfo>[];
    final gente = ref.watch(usuariosProvider).value ?? const <Usuario>[];
    Future<void> hacer(Future<void> Function() f, String ok) async {
      try {
        await f();
        if (!mounted) return;
        setState(() => _v++);
        avisar(this.context, ok);
      } catch (e) {
        if (mounted) avisar(this.context, mensajeDeError(e), tipo: TipoAviso.aviso);
      }
    }

    return ListView(
      shrinkWrap: true,
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
      children: [
        const Text('Horario de venta de prepagadas',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
        const SizedBox(height: 12),
        CampoFechaHora(etiqueta: 'Se vende desde', valor: _d, alCambiar: (v) => setState(() => _d = v)),
        const SizedBox(height: 10),
        CampoFechaHora(etiqueta: 'Se vende hasta', valor: _h, alCambiar: (v) => setState(() => _h = v)),
        const SizedBox(height: 10),
        FilledButton(
            onPressed: () => hacer(() => repo.ventanaDeVenta(_id, _d, _h), 'Horario guardado'),
            child: const Text('Guardar horario')),
        const Divider(height: 28),
        const Text('Excepciones', style: TextStyle(fontWeight: FontWeight.w800)),
        Text('Un team (o una persona) que puede vender más tarde que el resto.',
            style: TextStyle(color: VenueColors.textoSuave)),
        FutureBuilder(
          key: ValueKey(_v),
          future: repo.excepciones(_id),
          builder: (context, s) => Column(children: [
            for (final x in s.data ?? const <Fila>[])
              ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                title: Text('${x['nombre']}'),
                subtitle: Text('${x['tipo']} · hasta ${_fh(x['hasta_ts'])}'),
                trailing: IconButton(
                    tooltip: 'Quitar excepción',
                    icon: const Icon(Icons.close_rounded),
                    onPressed: () => hacer(() => repo.quitarExcepcion(x['id'] as String), 'Excepción quitada')),
              ),
          ]),
        ),
        SegmentedButton<bool>(
          showSelectedIcon: false,
          segments: const [
            ButtonSegment(value: true, label: Text('Un team')),
            ButtonSegment(value: false, label: Text('Una persona')),
          ],
          selected: {_porTeam},
          onSelectionChanged: (v) => setState(() {
            _porTeam = v.first;
            _quien = null;
          }),
        ),
        const SizedBox(height: 10),
        DropdownButtonFormField<String?>(
          borderRadius: BorderRadius.circular(12),
          dropdownColor: VenueColors.superficie,
          icon: Icon(Icons.keyboard_arrow_down_rounded, color: VenueColors.textoSuave),
          menuMaxHeight: 420,
          key: ValueKey(_porTeam),
          initialValue: _quien,
          isExpanded: true,
          decoration: InputDecoration(labelText: _porTeam ? 'Team' : 'Persona', isDense: true),
          items: [
            if (_porTeam)
              for (final t in teams) DropdownMenuItem<String?>(value: t.id, child: Text(t.nombre))
            else
              for (final g in gente.where((g) => g.rol == 'rrpp' || g.rol == 'jefe'))
                DropdownMenuItem<String?>(value: g.id, child: Text(g.nombre)),
          ],
          onChanged: (v) => setState(() => _quien = v),
        ),
        const SizedBox(height: 10),
        CampoFechaHora(etiqueta: 'Puede vender hasta', valor: _hasta, alCambiar: (v) => setState(() => _hasta = v)),
        const SizedBox(height: 10),
        OutlinedButton(
          onPressed: () {
            if (_quien == null || _hasta == null) {
              avisar(context, 'Elegí a quién y hasta qué hora', tipo: TipoAviso.aviso);
              return;
            }
            hacer(
                () => repo.fijarExcepcion(_id, _hasta!,
                    teamId: _porTeam ? _quien : null, usuarioId: _porTeam ? null : _quien),
                'Excepción guardada');
          },
          child: const Text('Guardar excepción'),
        ),
      ],
    );
  }
}

// ── avisos al equipo ──
class _Avisos extends ConsumerStatefulWidget {
  const _Avisos();
  @override
  ConsumerState<_Avisos> createState() => _AvisosState();
}

class _AvisosState extends ConsumerState<_Avisos> {
  final _t = TextEditingController(), _m = TextEditingController();
  String _destino = 'todos';
  String? _team;
  int _v = 0;

  @override
  void dispose() {
    _t.dispose();
    _m.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final club = ref.watch(clubActivoIdProvider)!;
    final repo = ref.read(gestionRepositoryProvider);
    final teams = ref.watch(teamsInfoProvider).value ?? const <TeamInfo>[];
    Future<void> hacer(Future<void> Function() f, String ok) async {
      try {
        await f();
        if (!mounted) return;
        setState(() => _v++);
        avisar(this.context, ok);
      } catch (e) {
        if (mounted) avisar(this.context, mensajeDeError(e), tipo: TipoAviso.aviso);
      }
    }

    return ListView(
      shrinkWrap: true,
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
      children: [
        const Text('Avisos al equipo', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
        Text('Le aparecen a cada uno al entrar, una sola vez. Queda registrado quién lo leyó.',
            style: TextStyle(color: VenueColors.textoSuave)),
        const SizedBox(height: 12),
        TextField(controller: _t, decoration: const InputDecoration(labelText: 'Título', isDense: true)),
        const SizedBox(height: 10),
        TextField(
            controller: _m, minLines: 2, maxLines: 5,
            decoration: const InputDecoration(labelText: 'Mensaje', isDense: true)),
        const SizedBox(height: 10),
        Row(children: [
          Expanded(
            child: DropdownButtonFormField<String>(
              borderRadius: BorderRadius.circular(12),
              dropdownColor: VenueColors.superficie,
              icon: Icon(Icons.keyboard_arrow_down_rounded, color: VenueColors.textoSuave),
              menuMaxHeight: 420,
              initialValue: _destino,
              decoration: const InputDecoration(labelText: 'Para', isDense: true),
              items: const [
                DropdownMenuItem(value: 'todos', child: Text('Todos')),
                DropdownMenuItem(value: 'rrpp', child: Text('Relacionadores')),
                DropdownMenuItem(value: 'jefes', child: Text('Jefes')),
                DropdownMenuItem(value: 'team', child: Text('Un team')),
              ],
              onChanged: (v) => setState(() => _destino = v!),
            ),
          ),
          if (_destino == 'team') ...[
            const SizedBox(width: 8),
            Expanded(
              child: DropdownButtonFormField<String?>(
                borderRadius: BorderRadius.circular(12),
                dropdownColor: VenueColors.superficie,
                icon: Icon(Icons.keyboard_arrow_down_rounded, color: VenueColors.textoSuave),
                menuMaxHeight: 420,
                initialValue: _team,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Team', isDense: true),
                items: [for (final t in teams) DropdownMenuItem<String?>(value: t.id, child: Text(t.nombre))],
                onChanged: (v) => setState(() => _team = v),
              ),
            ),
          ],
        ]),
        const SizedBox(height: 10),
        FilledButton(
          onPressed: () {
            if (_t.text.trim().isEmpty || _m.text.trim().isEmpty || (_destino == 'team' && _team == null)) {
              avisar(context, 'Completá título, mensaje y destinatario', tipo: TipoAviso.aviso);
              return;
            }
            hacer(() async {
              await repo.crearAviso(club, titulo: _t.text, mensaje: _m.text, destino: _destino, teamId: _team);
              _t.clear();
              _m.clear();
            }, 'Aviso enviado');
          },
          child: const Text('Enviar aviso'),
        ),
        const Divider(height: 28),
        FutureBuilder(
          key: ValueKey(_v),
          future: repo.avisos(club),
          builder: (context, s) => Column(children: [
            if (s.hasData && s.data!.isEmpty) const Text('Sin avisos enviados.'),
            for (final a in s.data ?? const <Fila>[])
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text('${a['titulo']}',
                    style: TextStyle(
                        fontWeight: FontWeight.w700,
                        color: a['activo'] == true ? null : VenueColors.textoSuave)),
                subtitle: Text(
                    '${a['destino']}${a['team'] == null ? '' : ' · ${a['team']}'} · lo leyeron ${a['leidos']} de ${a['alcance']}'),
                onTap: () => _hoja(
                    context,
                    FutureBuilder(
                      future: repo.lectores(a['id'] as String),
                      builder: (context, l) => ListView(
                        shrinkWrap: true,
                        padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
                        children: [
                          Text('Quién leyó "${a['titulo']}"',
                              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
                          if (l.hasData && l.data!.isEmpty) const Text('Todavía nadie.'),
                          for (final x in l.data ?? const <Fila>[])
                            ListTile(
                                dense: true,
                                contentPadding: EdgeInsets.zero,
                                title: Text('${x['nombre'] ?? x['usuario'] ?? '?'}'),
                                subtitle: Text(_fh(x['visto_at'] ?? x['at']))),
                        ],
                      ),
                    )),
                trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                  Switch(
                      value: a['activo'] == true,
                      onChanged: (v) => hacer(() => repo.activarAviso(a['id'] as String, v),
                          v ? 'Aviso activado' : 'Aviso en pausa')),
                  IconButton(
                      tooltip: 'Eliminar aviso',
                      icon: Icon(Icons.close_rounded, color: VenueColors.mal),
                      onPressed: () => hacer(() => repo.borrarAviso(a['id'] as String), 'Aviso eliminado')),
                ]),
              ),
          ]),
        ),
      ],
    );
  }
}
