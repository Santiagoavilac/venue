import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/media/imagenes.dart';
import '../../../core/networking/supabase.dart';
import '../../../core/theme/venue_theme.dart';
import '../../../core/widgets/avisos.dart';
import '../../../core/widgets/estado_vista.dart';
import '../../clubs/data/clubs.dart';
import '../../teams/data/gente.dart';
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
        datos: (lista) => ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          children: [
            Row(children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: () async {
                    if (await _hoja<bool>(context, const _NuevoEvento()) == true) recargar();
                  },
                  icon: const Icon(Icons.add_rounded),
                  label: const Text('Nuevo evento'),
                ),
              ),
              const SizedBox(width: 8),
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(minimumSize: const Size(0, 54)),
                onPressed: () => _hoja(context, const _Avisos()),
                icon: const Icon(Icons.campaign_outlined),
                label: const Text('Avisos'),
              ),
            ]),
            if (lista.isEmpty)
              const Padding(
                padding: EdgeInsets.only(top: 40),
                child: MensajeVista(
                  icono: Icons.event_outlined,
                  titulo: 'Todavía no hay eventos',
                  detalle: 'Creá el primero. Nace como borrador: nadie lo ve hasta que lo publiques.',
                ),
              ),
            for (final e in lista)
              _TarjetaEvento(
                evento: e,
                seleccionado: e['id'] == activo?.id,
                alElegir: e['estado'] == 'cerrado'
                    ? null
                    : () => ref.read(eventoElegidoProvider.notifier).elegir(e['id'] as String),
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
                      }, 'Arte del ticket actualizado');
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
          ],
        ),
      ),
    );
  }
}

class _TarjetaEvento extends StatelessWidget {
  const _TarjetaEvento({
    required this.evento, required this.seleccionado, required this.alElegir, required this.alAccion,
  });
  final Fila evento;
  final bool seleccionado;
  final VoidCallback? alElegir;
  final ValueChanged<String> alAccion;

  @override
  Widget build(BuildContext context) {
    final e = evento;
    final a = accionesDeEvento(e);
    final cerrado = e['estado'] == 'cerrado';
    final marca = Theme.of(context).colorScheme.primary;
    return Card(
      margin: const EdgeInsets.only(top: 10),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: seleccionado ? marca : VenueColors.linea, width: seleccionado ? 1.8 : 1),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: alElegir,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 4, 12),
          child: Row(children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('${e['nombre']}',
                    style: TextStyle(
                        fontSize: 17, fontWeight: FontWeight.w800,
                        color: cerrado ? VenueColors.textoSuave : null)),
                const SizedBox(height: 2),
                Text(
                  [
                    '${e['fecha']}',
                    '${e['precio_manilla']} Bs',
                    if (e['publicado'] == false) 'BORRADOR · solo lo ves vos',
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
            PopupMenuButton<String>(
              tooltip: 'Acciones del evento',
              onSelected: alAccion,
              itemBuilder: (_) => [
                const PopupMenuItem(value: 'editar', child: Text('Editar')),
                const PopupMenuItem(value: 'listas', child: Text('Listas y cupos')),
                const PopupMenuItem(value: 'fases', child: Text('Fases de preventa')),
                const PopupMenuItem(value: 'horarios', child: Text('Horario de venta')),
                const PopupMenuItem(value: 'arte', child: Text('Arte del ticket')),
                if (a.cerrar) const PopupMenuItem(value: 'cerrar', child: Text('Cerrar evento')),
                const PopupMenuItem(value: 'eliminar', child: Text('Eliminar')),
              ],
            ),
          ]),
        ),
      ),
    );
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
        const Text('Nace como borrador, con las listas "Invitados" y "Free Cover Girls".',
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
  int _v = 0;

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
          const Text(
              'El cupo de acá manda sobre el general. Ejemplo: la lista da 1 invitado a cada relacionador, pero a una persona puntual le das 3.',
              style: TextStyle(color: VenueColors.textoSuave, fontSize: 12.5, height: 1.35)),
          FutureBuilder(
            key: ValueKey(_v),
            future: Future.wait([
              repo.cuposDeLista(l!['id'] as String),
              repo.personasConCupo(club),
            ]),
            builder: (context, s) {
              if (!s.hasData) {
                return const Padding(
                    padding: EdgeInsets.all(16), child: Center(child: CircularProgressIndicator()));
              }
              final cupos = s.data![0], gente = s.data![1];
              final nombre = {for (final g in gente) g['id'] as String: '${g['nombre']} · ${g['team'] ?? ''}'};
              String? quien;
              final cant = TextEditingController();
              return StatefulBuilder(
                builder: (context, set) => Column(children: [
                  for (final c in cupos)
                    ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      title: Text(nombre[c['user_id']] ?? '?'),
                      subtitle: Text('cupo ${c['cupo']}'),
                      trailing: IconButton(
                          tooltip: 'Quitar cupo especial',
                          icon: const Icon(Icons.close_rounded),
                          onPressed: () async {
                            await repo.quitarCupo(l!['id'] as String, c['user_id'] as String);
                            setState(() => _v++);
                          }),
                    ),
                  Row(children: [
                    Expanded(
                      child: DropdownButtonFormField<String?>(
                        initialValue: quien,
                        isExpanded: true,
                        decoration: const InputDecoration(labelText: 'Persona', isDense: true),
                        items: [
                          for (final g in gente)
                            DropdownMenuItem<String?>(
                                value: g['id'] as String,
                                child: Text(nombre[g['id']]!, overflow: TextOverflow.ellipsis)),
                        ],
                        onChanged: (v) => set(() => quien = v),
                      ),
                    ),
                    const SizedBox(width: 8),
                    SizedBox(
                      width: 80,
                      child: TextField(
                          controller: cant,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(labelText: 'Cupo', isDense: true)),
                    ),
                    IconButton.filledTonal(
                      tooltip: 'Guardar cupo especial',
                      onPressed: () async {
                        final n = int.tryParse(cant.text);
                        if (quien == null || n == null || n < 0) {
                          avisar(context, 'Elegí persona y cantidad', tipo: TipoAviso.aviso);
                          return;
                        }
                        try {
                          await repo.fijarCupo(l!['id'] as String, quien!, n);
                          setState(() => _v++);
                        } catch (e) {
                          if (context.mounted) avisar(context, mensajeDeError(e), tipo: TipoAviso.aviso);
                        }
                      },
                      icon: const Icon(Icons.check_rounded),
                    ),
                  ]),
                ]),
              );
            },
          ),
        ],
      ],
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
          const Text('Cuántas entradas de esta fase puede vender cada team. Vacío o 0 = sin tope propio.',
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
        const Text('Un team (o una persona) que puede vender más tarde que el resto.',
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
        const Text('Le aparecen a cada uno al entrar, una sola vez. Queda registrado quién lo leyó.',
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
                      icon: const Icon(Icons.close_rounded, color: VenueColors.mal),
                      onPressed: () => hacer(() => repo.borrarAviso(a['id'] as String), 'Aviso eliminado')),
                ]),
              ),
          ]),
        ),
      ],
    );
  }
}
