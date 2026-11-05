import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:image_picker/image_picker.dart';
import '../../../core/networking/supabase.dart';
import '../../../core/theme/venue_theme.dart';
import '../../../core/widgets/avisos.dart';
import '../../clubs/data/clubs.dart';
import '../../events/data/eventos.dart';
import '../data/aftr_operacion.dart';
import '../../../core/widgets/esqueleto.dart';

class AftrOperacionScreen extends ConsumerStatefulWidget {
  const AftrOperacionScreen({super.key});
  @override
  ConsumerState<AftrOperacionScreen> createState() => _OperacionState();
}

class _OperacionState extends ConsumerState<AftrOperacionScreen> {
  int _tab = 0;
  String? _identidad;
  Future<dynamic>? _datos;
  Timer? _reloj, _espera;
  RealtimeChannel? _canal;
  SupabaseClient? _sb;
  bool _ocupado = false;
  List<String> get _tabs {
    final r = ref.read(rolProvider).value;
    return r == Rol.barra
        ? ['Pedidos']
        : r == Rol.admin || r == Rol.propietario
        ? ['Pedidos', 'Mesas', 'Catálogo', 'Liquidaciones']
        : ['Mesas'];
  }

  void _cargar() {
    if (!mounted) return;
    final ev = ref.read(eventoActivoProvider);
    final club = ref.read(clubActivoIdProvider);
    if (club == null) return;
    final repo = ref.read(operacionAftrProvider);
    final nombre = _tabs[_tab.clamp(0, _tabs.length - 1)];
    setState(
      () => _datos = switch (nombre) {
        'Pedidos' =>
          ev == null ? Future.value(<dynamic>[]) : repo.pedidos(ev.id),
        'Mesas' =>
          ev == null
              ? Future.value({'mesas': [], 'barras': []})
              : repo.rpc('venue_mesas_aftr', {'p_evento': ev.id}),
        'Catálogo' => repo.catalogo(club),
        _ => repo.rpc('venue_liquidaciones', {'p_club': club}),
      },
    );
  }

  @override
  void dispose() {
    _reloj?.cancel();
    _espera?.cancel();
    if (_canal != null) _sb?.removeChannel(_canal!);
    super.dispose();
  }

  Future<void> _hacer(Future<dynamic> Function() fn) async {
    if (_ocupado) return;
    setState(() => _ocupado = true);
    try {
      await fn();
      _cargar();
    } catch (e) {
      if (mounted) avisar(context, mensajeDeError(e), tipo: TipoAviso.aviso);
    } finally {
      if (mounted) setState(() => _ocupado = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final club = ref.watch(clubActivoIdProvider);
    final ev = ref.watch(eventoActivoProvider);
    ref.watch(rolProvider);
    final identidad = '$club/${ev?.id}';
    if (identidad != _identidad) {
      _identidad = identidad;
      _tab = 0;
      _reloj?.cancel();
      if (_canal != null) _sb?.removeChannel(_canal!);
      _sb = ref.read(supabaseProvider);
      _canal = _sb!
          .channel('venue-aftr-$identidad')
          .onPostgresChanges(
            event: PostgresChangeEvent.all,
            schema: 'public',
            table: 'aftr_bar_pedidos',
            filter: PostgresChangeFilter(
              type: PostgresChangeFilterType.eq,
              column: 'evento_id',
              value: ev?.id ?? '',
            ),
            callback: (_) {
              _espera?.cancel();
              _espera = Timer(const Duration(milliseconds: 300), _cargar);
            },
          )
          .subscribe();
      _reloj = Timer.periodic(const Duration(seconds: 15), (_) {
        if (_tabs[_tab] == 'Pedidos') _cargar();
      });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _cargar();
      });
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  'AFTR · ${ev?.nombre ?? 'Elegí un evento'}',
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              IconButton(onPressed: _cargar, icon: const Icon(Icons.refresh)),
            ],
          ),
        ),
        DefaultTabController(
          key: ValueKey(_tabs.join()),
          length: _tabs.length,
          child: TabBar(
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            onTap: (n) {
              _tab = n;
              _cargar();
            },
            tabs: [for (final t in _tabs) Tab(text: t)],
          ),
        ),
        if (_ocupado) const LinearProgressIndicator(),
        Expanded(
          child: FutureBuilder<dynamic>(
            future: _datos,
            builder: (context, s) {
              if (s.hasError)
                return Center(
                  child: TextButton(
                    onPressed: _cargar,
                    child: Text('${mensajeDeError(s.error!)} · Reintentar'),
                  ),
                );
              if (!s.hasData)
                return const EsqueletoLista(conFoto: false);
              return switch (_tabs[_tab]) {
                'Pedidos' => _pedidos(s.data as List),
                'Mesas' => _mesas(Map<String, dynamic>.from(s.data as Map)),
                'Catálogo' => _catalogo(
                  Map<String, dynamic>.from(s.data as Map),
                ),
                _ => _liquidaciones(Map<String, dynamic>.from(s.data as Map)),
              };
            },
          ),
        ),
      ],
    );
  }

  Widget _pedidos(List pedidos) {
    final activos = pedidos.where((p) => p['estado'] != 'entregado').toList();
    final entregados = pedidos
        .where((p) => p['estado'] == 'entregado')
        .toList();
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        if (activos.isEmpty)
          const Padding(
            padding: EdgeInsets.all(24),
            child: Text('No hay pedidos pendientes de preparar.'),
          ),
        for (final p in [...activos, ...entregados])
          Container(
            margin: const EdgeInsets.only(bottom: 20),
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: VenueColors.superficie,
              border: Border.all(color: VenueColors.linea),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${p['mesa']} · ${p['cliente']}',
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  '${p['estado']}'.replaceAll('_', ' '),
                  style: TextStyle(color: VenueColors.textoSuave),
                ),
                Text(
                  '${DateTime.now().difference(DateTime.tryParse('${p['created_at']}') ?? DateTime.now()).inMinutes} min · Bs ${bsCentavos(p['total_centavos'])} · ${p['metodo'] == 'pulse' ? 'PULSE' : 'QR'}',
                ),
                const Divider(height: 28),
                for (final i in p['items'] as List)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Text(
                      '${i['qty']} × ${i['nombre']}',
                      style: const TextStyle(fontSize: 17),
                    ),
                  ),
                if ('${p['observaciones']}'.isNotEmpty)
                  Text('${p['observaciones']}'),
                if (p['estado'] != 'entregado')
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton(
                      onPressed: _ocupado
                          ? null
                          : () => _hacer(
                              () => ref
                                  .read(operacionAftrProvider)
                                  .rpc('venue_avanzar_pedido', {
                                    'p_pedido': p['id'],
                                    'p_estado': switch (p['estado']) {
                                      'recibido' => 'en_preparacion',
                                      'en_preparacion' => 'listo',
                                      _ => 'entregado',
                                    },
                                  }),
                            ),
                      child: Text(switch (p['estado']) {
                        'recibido' => 'Comenzar preparación',
                        'en_preparacion' => 'Marcar listo',
                        _ => 'Marcar entregado',
                      }),
                    ),
                  ),
                TextButton(
                  onPressed: () async {
                    final detalle = await _texto(
                      'Registrar incidencia',
                      'Describí qué ocurrió',
                    );
                    if (detalle != null && detalle.isNotEmpty)
                      await _hacer(
                        () => ref.read(operacionAftrProvider).rpc(
                          'venue_incidencia_pedido',
                          {'p_pedido': p['id'], 'p_detalle': detalle},
                        ),
                      );
                  },
                  child: const Text('Registrar incidencia'),
                ),
              ],
            ),
          ),
      ],
    );
  }

  Future<String?> _texto(String titulo, String etiqueta) async {
    final c = TextEditingController();
    final r = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(titulo),
        content: TextField(
          controller: c,
          decoration: InputDecoration(labelText: etiqueta),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, c.text.trim()),
            child: const Text('Continuar'),
          ),
        ],
      ),
    );
    c.dispose();
    return r;
  }

  Widget _mesas(Map<String, dynamic> d) => ListView(
    padding: const EdgeInsets.all(20),
    children: [
      const Text(
        'Asigná mesas pagadas a cuentas AFTR. La capacidad física se configura por separado de las manillas.',
      ),
      const SizedBox(height: 20),
      for (final m in d['mesas'] as List)
        ListTile(
          contentPadding: EdgeInsets.zero,
          title: Text('${m['etiqueta']}'),
          subtitle: Text(
            '${m['usuario'] == null ? 'Sin cuenta asignada' : '@${m['usuario']}'} · Capacidad ${m['capacidad'] ?? 'sin configurar'}',
          ),
          trailing: TextButton(
            onPressed: () => _asignar(m, List.from(d['barras'] as List)),
            child: const Text('Asignar'),
          ),
        ),
    ],
  );
  Future<void> _asignar(dynamic m, List barras) async {
    final usuario = await _texto(
      'Buscar cuenta AFTR',
      'Usuario, al menos 3 caracteres',
    );
    if (usuario == null || !mounted) return;
    try {
      final usuarios =
          await ref.read(operacionAftrProvider).rpc(
                'venue_buscar_cliente_aftr',
                {'p_club': ref.read(clubActivoIdProvider), 'p_q': usuario},
              )
              as List;
      if (!mounted) return;
      final elegido = await showDialog<dynamic>(
        context: context,
        builder: (ctx) => SimpleDialog(
          title: const Text('Elegir titular'),
          children: [
            SimpleDialogOption(
              onPressed: () => Navigator.pop(ctx, {'user_id': null}),
              child: const Text('Retirar asignación'),
            ),
            for (final u in usuarios)
              SimpleDialogOption(
                onPressed: () => Navigator.pop(ctx, u),
                child: Text('${u['nombre']} · @${u['usuario']}'),
              ),
          ],
        ),
      );
      if (elegido == null || !mounted) return;
      final capacidad = TextEditingController(text: '${m['capacidad'] ?? ''}');
      String? barra = m['barra_id'] as String?;
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => StatefulBuilder(
          builder: (ctx, estado) => AlertDialog(
            title: const Text('Configurar mesa'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: capacidad,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Capacidad física',
                  ),
                ),
                DropdownButtonFormField<String>(
                  initialValue: barra,
                  decoration: const InputDecoration(
                    labelText: 'Barra responsable',
                  ),
                  items: [
                    for (final b in barras)
                      DropdownMenuItem(
                        value: b['id'] as String,
                        child: Text('${b['nombre']}'),
                      ),
                  ],
                  onChanged: (v) => estado(() => barra = v),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancelar'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Guardar'),
              ),
            ],
          ),
        ),
      );
      final n = int.tryParse(capacidad.text);
      capacidad.dispose();
      if (ok != true) return;
      await _hacer(
        () => ref.read(operacionAftrProvider).rpc('venue_asignar_mesa_aftr', {
          'p_mesa': m['id'],
          'p_cliente': elegido['user_id'],
          'p_capacidad': n,
          'p_barra': barra,
        }),
      );
    } catch (e) {
      if (mounted) avisar(context, mensajeDeError(e), tipo: TipoAviso.aviso);
    }
  }

  Widget _catalogo(Map<String, dynamic> d) => ListView(
    padding: const EdgeInsets.all(20),
    children: [
      SwitchListTile(
        contentPadding: EdgeInsets.zero,
        title: const Text('Pedidos desde AFTR'),
        subtitle: Text(
          d['config']['habilitado'] == true
              ? 'Habilitados según el horario configurado'
              : 'Desactivados',
        ),
        value: d['config']['habilitado'] == true,
        onChanged: (v) => _configurar(d['config'] as Map, v),
      ),
      ListTile(
        contentPadding: EdgeInsets.zero,
        title: const Text('Horarios y permisos'),
        subtitle: Text('${d['config']['desde']} a ${d['config']['hasta']}'),
        onTap: () =>
            _configurar(d['config'] as Map, d['config']['habilitado'] == true),
      ),
      const Divider(height: 28),
      const Text(
        'Los borradores requieren foto, presentación, precio y receta antes de publicarse.',
      ),
      ExpansionTile(
        tilePadding: EdgeInsets.zero,
        title: const Text('Bebidas base · configurar presentaciones'),
        children: [
          for (final b in d['bebidas'] as List)
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text('${b['nombre']}'),
              subtitle: Text(
                (b['volumen_ml'] as num) > 0
                    ? '${b['volumen_ml']} ml'
                    : 'Envase por confirmar',
              ),
              trailing: TextButton(
                onPressed: () async {
                  final volumen = await _texto(
                    'Presentación de ${b['nombre']}',
                    'Volumen real del envase en ml',
                  );
                  if (volumen == null) return;
                  await _hacer(
                    () => ref.read(operacionAftrProvider).rpc(
                      'venue_guardar_bebida_catalogo',
                      {'p_bebida': b['id'], 'p_volumen': int.tryParse(volumen)},
                    ),
                  );
                },
                child: const Text('Configurar'),
              ),
            ),
        ],
      ),
      for (final p in d['productos'] as List)
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: p['foto_url'] == null
              ? const Icon(Icons.local_bar_outlined)
              : Image.network(
                  '${p['foto_url']}',
                  width: 48,
                  height: 64,
                  fit: BoxFit.contain,
                  errorBuilder: (_, _, _) =>
                      const Icon(Icons.local_bar_outlined),
                ),
          title: Text('${p['nombre']}'),
          subtitle: Text(
            '${p['publicado_aftr'] == true ? 'Publicado' : 'Borrador'} · Bs ${p['precio_venta']}',
          ),
          trailing: TextButton(
            onPressed: () async {
              await Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => _ProductoEditor(
                    producto: Map.from(p as Map),
                    bebidas: List.from(d['bebidas'] as List),
                  ),
                ),
              );
              _cargar();
            },
            child: const Text('Editar'),
          ),
        ),
    ],
  );
  Future<void> _configurar(Map cfg, bool habilitado) async {
    final desde = TextEditingController(
          text: '${cfg['desde']}'.substring(0, 5),
        ),
        hasta = TextEditingController(text: '${cfg['hasta']}'.substring(0, 5));
    final roles = Set<String>.from(cfg['roles_asignan'] as List);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, estado) => AlertDialog(
          title: const Text('Pedidos a mesa'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: desde,
                  decoration: const InputDecoration(labelText: 'Desde · HH:MM'),
                ),
                TextField(
                  controller: hasta,
                  decoration: const InputDecoration(labelText: 'Hasta · HH:MM'),
                ),
                const SizedBox(height: 20),
                const Text('Quién puede asignar y retirar mesas'),
                for (final r in [
                  'admin',
                  'propietario',
                  'jefe',
                  'rrpp',
                  'caja',
                ])
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(r),
                    value: roles.contains(r),
                    onChanged: (v) => estado(() {
                      v == true ? roles.add(r) : roles.remove(r);
                    }),
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancelar'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Guardar'),
            ),
          ],
        ),
      ),
    );
    final a = desde.text, b = hasta.text;
    desde.dispose();
    hasta.dispose();
    if (ok == true)
      await _hacer(
        () => ref.read(operacionAftrProvider).rpc('venue_configurar_pedidos', {
          'p_club': ref.read(clubActivoIdProvider),
          'p_habilitado': habilitado,
          'p_desde': a,
          'p_hasta': b,
          'p_roles': roles.toList(),
        }),
      );
  }

  Widget _liquidaciones(Map<String, dynamic> d) {
    final ventas = (d['ventas_centavos'] as num).toInt(),
        pagado = (d['liquidado_centavos'] as num).toInt();
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        const Text('Pendiente de liquidar'),
        Text(
          'Bs ${bsCentavos(ventas - pagado)}',
          style: const TextStyle(fontSize: 38, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 16),
        Text(
          'Ventas: Bs ${bsCentavos(ventas)}\nLiquidado: Bs ${bsCentavos(pagado)}',
        ),
        const SizedBox(height: 20),
        if (d['puede_liquidar'] == true)
          TextButton(
            onPressed: _ocupado
                ? null
                : () async {
                    final importe = await _texto(
                      'Registrar transferencia realizada',
                      'Importe en Bs',
                    );
                    if (importe == null) return;
                    final centavos = leerCentavos(importe);
                    if (centavos == null || !mounted) return;
                    final fecha = await showDatePicker(
                      context: context,
                      initialDate: DateTime.now(),
                      firstDate: DateTime(2020),
                      lastDate: DateTime.now(),
                    );
                    if (fecha == null) return;
                    final comprobante = await _texto(
                      'Comprobante',
                      'Referencia o enlace al comprobante',
                    );
                    if (comprobante == null) return;
                    final clave = claveAftr();
                    await _hacer(
                      () => ref
                          .read(operacionAftrProvider)
                          .rpc('venue_registrar_liquidacion', {
                            'p_club': ref.read(clubActivoIdProvider),
                            'p_centavos': centavos,
                            'p_fecha': fecha.toIso8601String().substring(0, 10),
                            'p_comprobante': comprobante,
                            'p_client_key': clave,
                          }),
                    );
                  },
            child: const Text('Registrar liquidación manual'),
          ),
        const Divider(height: 30),
        const Text(
          'Liquidaciones registradas',
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
        ),
        for (final l in d['liquidaciones'] as List)
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(
              'Bs ${bsCentavos(l['importe_centavos'])} · ${l['fecha']}',
            ),
            subtitle: Text('${l['comprobante']}'),
          ),
        const Divider(height: 30),
        const Text(
          'Ventas AFTR',
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
        ),
        for (final v in d['ventas'] as List)
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(
              'Bs ${bsCentavos(v['importe_centavos'])} · ${v['metodo']}',
            ),
            subtitle: Text('${v['referencia']}'),
          ),
      ],
    );
  }
}

class _ProductoEditor extends ConsumerStatefulWidget {
  const _ProductoEditor({required this.producto, required this.bebidas});
  final Map<String, dynamic> producto;
  final List bebidas;
  @override
  ConsumerState<_ProductoEditor> createState() => _ProductoState();
}

class _ProductoState extends ConsumerState<_ProductoEditor> {
  late final _nombre = TextEditingController(
        text: '${widget.producto['nombre']}',
      ),
      _precio = TextEditingController(
        text: '${widget.producto['precio_venta']}',
      ),
      _foto = TextEditingController(
        text: widget.producto['foto_url'] as String? ?? '',
      ),
      _fuente = TextEditingController(
        text: widget.producto['foto_fuente'] as String? ?? '',
      ),
      _presentacion = TextEditingController(
        text: widget.producto['presentacion'] as String? ?? '',
      ),
      _categoria = TextEditingController(
        text: '${widget.producto['categoria_aftr']}',
      );
  late bool _publicado = widget.producto['publicado_aftr'] == true;
  bool _guardando = false;
  late final List<Map<String, dynamic>> _receta = [
    for (final x in widget.producto['receta'] as List)
      Map<String, dynamic>.from(x as Map),
  ];
  @override
  void dispose() {
    for (final c in [
      _nombre,
      _precio,
      _foto,
      _fuente,
      _presentacion,
      _categoria,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Producto AFTR')),
    body: ListView(
      padding: const EdgeInsets.all(24),
      children: [
        for (final x in [
          (_nombre, 'Nombre'),
          (_precio, 'Precio en Bs'),
          (_foto, 'Foto · URL HTTPS'),
          (_fuente, 'Fuente de la fotografía'),
          (_presentacion, 'Presentación'),
          (_categoria, 'Categoría'),
        ])
          Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: TextField(
              controller: x.$1,
              decoration: InputDecoration(labelText: x.$2),
            ),
          ),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            icon: const Icon(Icons.add_photo_alternate_outlined),
            label: const Text('Subir foto del boliche'),
            onPressed: _guardando
                ? null
                : () async {
                    try {
                      final f = await ImagePicker().pickImage(
                        source: ImageSource.gallery,
                        maxWidth: 900,
                        maxHeight: 900,
                        imageQuality: 85,
                      );
                      if (f == null) return;
                      final bytes = await f.readAsBytes();
                      if (bytes.length > 1048576)
                        throw Exception('La foto debe pesar menos de 1 MB.');
                      final png =
                          bytes.length > 4 && bytes[0] == 137 && bytes[1] == 80;
                      final jpg =
                          bytes.length > 2 &&
                          bytes[0] == 255 &&
                          bytes[1] == 216;
                      if (!png && !jpg)
                        throw Exception('Elegí una foto JPG o PNG.');
                      final sb = ref.read(supabaseProvider);
                      final ruta =
                          '${widget.producto['club_id']}/${claveAftr()}.${png ? 'png' : 'jpg'}';
                      await sb.storage
                          .from('bar-catalogo')
                          .uploadBinary(
                            ruta,
                            bytes,
                            fileOptions: FileOptions(
                              contentType: png ? 'image/png' : 'image/jpeg',
                            ),
                          );
                      if (mounted)
                        setState(() {
                          _foto.text = sb.storage
                              .from('bar-catalogo')
                              .getPublicUrl(ruta);
                          _fuente.text = 'Foto propia del boliche';
                        });
                    } catch (e) {
                      if (context.mounted)
                        avisar(
                          context,
                          mensajeDeError(e),
                          tipo: TipoAviso.aviso,
                        );
                    }
                  },
          ),
        ),
        const SizedBox(height: 12),
        const Text(
          'Receta',
          style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
        ),
        for (var n = 0; n < _receta.length; n++)
          Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<String>(
                  initialValue: _receta[n]['bebida_id'] as String?,
                  items: [
                    for (final b in widget.bebidas)
                      DropdownMenuItem(
                        value: b['id'] as String,
                        child: Text(
                          '${b['nombre']}',
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                  ],
                  isExpanded: true,
                  onChanged: (v) => setState(() => _receta[n]['bebida_id'] = v),
                ),
              ),
              const SizedBox(width: 12),
              SizedBox(
                width: 80,
                child: TextFormField(
                  initialValue: '${_receta[n]['ml'] ?? ''}',
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: const InputDecoration(labelText: 'ml'),
                  onChanged: (v) =>
                      _receta[n]['ml'] = num.tryParse(v.replaceAll(',', '.')),
                ),
              ),
              IconButton(
                onPressed: () => setState(() => _receta.removeAt(n)),
                icon: const Icon(Icons.close),
              ),
            ],
          ),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton(
            onPressed: () =>
                setState(() => _receta.add({'bebida_id': null, 'ml': null})),
            child: const Text('Agregar ingrediente'),
          ),
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Publicado en AFTR'),
          value: _publicado,
          onChanged: (v) => setState(() => _publicado = v),
        ),
        const SizedBox(height: 20),
        FilledButton(
          onPressed: _guardando
              ? null
              : () async {
                  final precio = leerCentavos(_precio.text);
                  if (precio == null) {
                    avisar(context, 'Ingresá un precio válido.');
                    return;
                  }
                  setState(() => _guardando = true);
                  try {
                    await ref
                        .read(operacionAftrProvider)
                        .rpc('venue_guardar_producto_aftr', {
                          'p_trago': widget.producto['id'],
                          'p_nombre': _nombre.text,
                          'p_centavos': precio,
                          'p_foto': _foto.text.isEmpty ? null : _foto.text,
                          'p_fuente': _fuente.text,
                          'p_presentacion': _presentacion.text,
                          'p_categoria': _categoria.text,
                          'p_publicado': _publicado,
                          'p_receta': _receta,
                        });
                    if (context.mounted) Navigator.pop(context);
                  } catch (e) {
                    if (context.mounted)
                      avisar(context, mensajeDeError(e), tipo: TipoAviso.aviso);
                  } finally {
                    if (mounted) setState(() => _guardando = false);
                  }
                },
          child: Text(_guardando ? 'Guardando…' : 'Guardar producto'),
        ),
      ],
    ),
  );
}
