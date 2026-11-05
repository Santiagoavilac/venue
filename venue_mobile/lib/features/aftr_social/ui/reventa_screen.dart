import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/networking/supabase.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/theme/venue_theme.dart';
import '../../../core/widgets/avisos.dart';
import '../../authentication/data/sesion.dart';
import '../../clubs/data/clubs.dart';
import '../data/social_aftr.dart';
import 'historias_screen.dart';
import '../../../core/widgets/esqueleto.dart';

class ReventaScreen extends ConsumerStatefulWidget {
  const ReventaScreen({super.key});
  @override
  ConsumerState<ReventaScreen> createState() => _ReventaState();
}

class _ReventaState extends ConsumerState<ReventaScreen>
    with WidgetsBindingObserver {
  bool _global = false, _ocupado = false;
  int _tab = 0;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  void _refrescar() => ref.invalidate(reventaGestionProvider(_global));
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _refrescar();
  }

  Future<void> _orden(DatosSocial orden, bool principal) async {
    final cambio = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => _OrdenReventa(
          id: '${orden['orden_id'] ?? orden['id']}',
          principal: principal,
        ),
      ),
    );
    if (cambio == true) _refrescar();
  }

  Future<void> _retirarOferta(DatosSocial oferta) async {
    final motivo = await motivoSocial(
      context,
      titulo: 'Retirar oferta',
      explicacion:
          'La entrada volverá al vendedor si no hay una operación en curso.',
    );
    if (motivo == null || _ocupado) return;
    setState(() => _ocupado = true);
    try {
      await ref.read(socialAftrProvider).reventa('retirar_oferta', {
        'oferta_id': oferta['id'],
        'motivo': motivo,
      });
      _refrescar();
      if (mounted) avisar(context, 'Oferta retirada');
    } catch (e) {
      if (mounted) avisar(context, mensajeDeError(e), tipo: TipoAviso.aviso);
    } finally {
      if (mounted) setState(() => _ocupado = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final principalPerfil =
        ref.watch(perfilProvider).value?.adminPrincipal == true;
    final gestion = ref.watch(reventaGestionProvider(_global));
    final club = ref.watch(clubActivoProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  _global
                      ? 'Supervisión de la plataforma'
                      : club?.nombre ?? 'Reventa oficial',
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              IconButton(
                tooltip: 'Actualizar reventa',
                onPressed: _refrescar,
                icon: const Icon(Icons.refresh),
              ),
            ],
          ),
        ),
        if (principalPerfil)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: SegmentedButton<bool>(
              segments: const [
                ButtonSegment(value: false, label: Text('Este boliche')),
                ButtonSegment(value: true, label: Text('Todos')),
              ],
              selected: {_global},
              onSelectionChanged: (s) => setState(() {
                _global = s.first;
                _tab = 0;
              }),
            ),
          ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Text(
            'Una entrada, un dueño y un QR vigente. Los pagos son entre usuarios.',
            style: TextStyle(color: VenueColors.textoSuave),
          ),
        ),
        if (_ocupado) const LinearProgressIndicator(),
        Expanded(
          child: gestion.when(
            loading: () => const EsqueletoLista(),
            error: (e, _) => Center(
              child: TextButton(
                onPressed: _refrescar,
                child: Text(
                  '${mensajeDeError(e)}\nReintentar',
                  textAlign: TextAlign.center,
                ),
              ),
            ),
            data: (j) {
              final principal = j['admin_principal'] == true;
              final tabs = [
                'Ofertas',
                'Operaciones',
                if (principal) 'Disputas',
              ];
              final indice = _tab.clamp(0, tabs.length - 1);
              final filas = filasSocial(
                j[switch (indice) {
                  0 => 'ofertas',
                  1 => 'ordenes',
                  _ => 'disputas',
                }],
              );
              return Column(
                children: [
                  if (!_global)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
                      child: Card(
                        child: ListTile(
                          leading: Icon(
                            mapaSocial(j['config'])['habilitada'] == true
                                ? Icons.verified_outlined
                                : Icons.pause_circle_outline,
                            color: mapaSocial(j['config'])['habilitada'] == true
                                ? VenueColors.ok
                                : VenueColors.neutro,
                          ),
                          title: Text(
                            mapaSocial(j['config'])['habilitada'] == true
                                ? 'Reventa habilitada'
                                : 'Reventa desactivada',
                          ),
                          subtitle: const Text('Prender o apagar, y tus condiciones'),
                          trailing: const Icon(Icons.tune),
                          onTap: () async {
                            final cambio = await Navigator.of(context)
                                .push<bool>(
                                  MaterialPageRoute(
                                    builder: (_) => _ConfigReventa(
                                      config: mapaSocial(j['config']),
                                      politica: mapaSocial(j['politica']),
                                    ),
                                  ),
                                );
                            if (cambio == true) _refrescar();
                          },
                        ),
                      ),
                    ),
                  DefaultTabController(
                    key: ValueKey('${tabs.length}-$_global'),
                    length: tabs.length,
                    child: TabBar(
                      onTap: (v) => setState(() => _tab = v),
                      tabs: [for (final t in tabs) Tab(text: t)],
                    ),
                  ),
                  Expanded(
                    child: RefreshIndicator(
                      onRefresh: () async {
                        _refrescar();
                        await ref.read(reventaGestionProvider(_global).future);
                      },
                      child: ListView(
                        padding: const EdgeInsets.all(16),
                        children: [
                          if (filas.isEmpty)
                            SocialVacio(
                              icono: indice == 2
                                  ? Icons.shield_outlined
                                  : Icons.confirmation_number_outlined,
                              titulo: indice == 0
                                  ? 'Sin ofertas por ahora'
                                  : indice == 1
                                  ? 'Sin operaciones registradas'
                                  : 'Sin disputas pendientes',
                              detalle: indice == 0
                                  ? 'Las entradas que el público publique en AFTR aparecerán acá.'
                                  : 'Los cambios se actualizan automáticamente.',
                            ),
                          for (final fila in filas)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 12),
                              child: Card(
                                child: Column(
                                  children: [
                                    ListTile(
                                      onTap: indice == 0
                                          ? null
                                          : () => _orden(fila, principal),
                                      leading: Icon(
                                        indice == 2
                                            ? Icons.gpp_maybe_outlined
                                            : Icons
                                                  .confirmation_number_outlined,
                                        color: indice == 2
                                            ? VenueColors.aviso
                                            : null,
                                      ),
                                      title: Text(
                                        textoSocial(fila['evento']),
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                      subtitle: Text(
                                        indice == 0
                                            ? '${textoSocial(fila['vendedor'])}\n${estadoSocial(fila['estado'])}'
                                            : '${textoSocial(fila['vendedor'])} → ${textoSocial(fila['comprador'])}\n${estadoSocial(fila['estado'])}${fila['motivo'] == null ? '' : ' · ${fila['motivo']}'}',
                                      ),
                                      isThreeLine: true,
                                      trailing: Text(
                                        dineroSocial(fila['precio_centavos']),
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w800,
                                        ),
                                      ),
                                    ),
                                    if (indice == 0 &&
                                        [
                                          'publicada',
                                          'activa',
                                          'disponible',
                                        ].contains(fila['estado']))
                                      Align(
                                        alignment: Alignment.centerRight,
                                        child: TextButton.icon(
                                          onPressed: _ocupado
                                              ? null
                                              : () => _retirarOferta(fila),
                                          icon: const Icon(
                                            Icons.remove_circle_outline,
                                            size: 18,
                                          ),
                                          label: const Text('Retirar oferta'),
                                        ),
                                      ),
                                    if (indice != 0)
                                      Align(
                                        alignment: Alignment.centerRight,
                                        child: TextButton(
                                          onPressed: () =>
                                              _orden(fila, principal),
                                          child: Text(
                                            principal
                                                ? 'Ver operación e historial'
                                                : 'Ver seguimiento',
                                          ),
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ],
    );
  }
}

class _ConfigReventa extends ConsumerStatefulWidget {
  const _ConfigReventa({required this.config, required this.politica});

  /// Los plazos y el techo de precio los fija AFTR, iguales para todos: acá se
  /// muestran como información, no como campos. Un boliche poniendo el plazo
  /// de pago en 30 minutos son 30 minutos de entrada bloqueada por alguien que
  /// puede no pagar nunca.
  final DatosSocial politica;
  final DatosSocial config;
  @override
  ConsumerState<_ConfigReventa> createState() => _ConfigState();
}

class _ConfigState extends ConsumerState<_ConfigReventa> {
  final _form = GlobalKey<FormState>();
  late bool _habilitada;
  late TextEditingController _condiciones;

  /// El techo de precio es del boliche, no de AFTR: es su mercado. Vacío es
  /// precio libre, como siempre.
  late TextEditingController _maximo;
  bool _ocupado = false;
  String? _error;
  @override
  void initState() {
    super.initState();
    final c = widget.config;
    _habilitada = c['habilitada'] == true;
    _condiciones = TextEditingController(text: '${c['condiciones'] ?? ''}');
    _maximo = TextEditingController(
      text: c['max_precio_pct'] == null ? '' : '${c['max_precio_pct']}',
    );
  }

  @override
  void dispose() {
    _condiciones.dispose();
    _maximo.dispose();
    super.dispose();
  }

  Future<void> _guardar() async {
    if (_ocupado || !_form.currentState!.validate()) return;
    final club = ref.read(clubActivoIdProvider);
    if (club == null) return;
    setState(() {
      _ocupado = true;
      _error = null;
    });
    try {
      await ref.read(socialAftrProvider).reventa('configurar', {
        'club_id': club,
        'habilitada': _habilitada,
        'max_precio_pct': _maximo.text.trim().isEmpty
            ? null
            : int.parse(_maximo.text.trim()),
        'condiciones': _condiciones.text.trim(),
      });
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) setState(() => _error = mensajeDeError(e));
    } finally {
      if (mounted) setState(() => _ocupado = false);
    }
  }

  /// Las reglas de AFTR, como información. No son editables acá a propósito:
  /// son las mismas para todos los boliches.
  Widget _reglasDeAftr() {
    final p = widget.politica;
    int n(String k, int def) => (p[k] as num?)?.toInt() ?? def;
    final filas = <(String, String)>[
      ('El vendedor acepta', 'tiene ${n('aceptacion_minutos', 30)} min para responder'),
      ('Luego el comprador paga', 'tiene ${n('pago_minutos', 15)} min'),
      ('Y el vendedor confirma', 'tiene ${n('confirmacion_minutos', 30)} min'),
      ('Operaciones por persona', '${n('max_abiertas', 1)} a la vez · ${n('max_dia', 5)} por día'),
    ];
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: VenueColors.superficie2,
        borderRadius: BorderRadius.circular(Redondeo.medio),
        border: Border.all(color: VenueColors.linea),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Los plazos los pone AFTR', style: Tipo.bloque),
        const SizedBox(height: 4),
        Text(
          'Iguales en todos los boliches, para que el público sepa a qué atenerse. '
          'El precio lo decidís vos, acá arriba. Los datos de cobro del vendedor '
          'no se muestran hasta que acepta el pedido.',
          style: Tipo.apoyo,
        ),
        const SizedBox(height: 12),
        for (final f in filas)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Row(children: [
              Expanded(child: Text(f.$1, style: Tipo.apoyo)),
              Text(f.$2, style: Tipo.cuerpo),
            ]),
          ),
      ]),
    );
  }
  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_ocupado,
    child: Scaffold(
      appBar: AppBar(title: const Text('Condiciones de reventa')),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640),
            child: Form(
              key: _form,
              child: ListView(
                padding: const EdgeInsets.all(20),
                children: [
                  SwitchListTile.adaptive(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Permitir reventa oficial'),
                    subtitle: const Text(
                      'El público puede ofrecer sus entradas compradas.',
                    ),
                    value: _habilitada,
                    onChanged: _ocupado
                        ? null
                        : (v) => setState(() => _habilitada = v),
                  ),
                  const SizedBox(height: 20),
                  TextFormField(
                    controller: _maximo,
                    enabled: !_ocupado,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Precio máximo (% de lo que pagó quien revende)',
                      helperText: 'Vacío: precio libre. 100: hasta lo que pagó.',
                      helperMaxLines: 2,
                    ),
                    validator: (t) {
                      final v = (t ?? '').trim();
                      if (v.isEmpty) return null;
                      final n = int.tryParse(v);
                      if (n == null || n < 100 || n > 1000) {
                        return 'De 100 a 1000, o vacío para precio libre';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 16),
                  _reglasDeAftr(),
                  const SizedBox(height: 20),
                  TextFormField(
                    controller: _condiciones,
                    enabled: !_ocupado,
                    minLines: 4,
                    maxLines: 8,
                    maxLength: 2000,
                    decoration: const InputDecoration(
                      labelText: 'Condiciones del boliche',
                    ),
                  ),
                  const SizedBox(height: 14),
                  Text(
                    'La plataforma bloquea el QR durante la reventa. Una disputa mantiene la entrada bloqueada hasta que se resuelva.',
                    style: TextStyle(color: VenueColors.textoSuave),
                  ),
                  if (_error != null)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      child: Text(
                        _error!,
                        style: TextStyle(color: VenueColors.mal),
                      ),
                    ),
                  const SizedBox(height: 20),
                  if (_ocupado) const LinearProgressIndicator(),
                  FilledButton(
                    onPressed: _ocupado ? null : _guardar,
                    child: Text(
                      _ocupado ? 'Guardando…' : 'Guardar condiciones',
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

class _OrdenReventa extends ConsumerStatefulWidget {
  const _OrdenReventa({required this.id, required this.principal});
  final String id;
  final bool principal;
  @override
  ConsumerState<_OrdenReventa> createState() => _OrdenState();
}

class _OrdenState extends ConsumerState<_OrdenReventa>
    with WidgetsBindingObserver {
  Future<DatosSocial>? _datos;
  Timer? _reloj;
  bool _ocupado = false;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _cargar();
    _reloj = Timer.periodic(const Duration(seconds: 10), (_) => _cargar());
  }

  void _cargar() {
    if (!mounted || _ocupado) return;
    setState(
      () => _datos = ref.read(socialAftrProvider).reventa('orden', {
        'id': widget.id,
      }),
    );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _cargar();
  }

  @override
  void dispose() {
    _reloj?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  Future<void> _resolver(String resolucion) async {
    final motivo = await motivoSocial(
      context,
      titulo: resolucion == 'entregar'
          ? 'Entregar al comprador'
          : 'Cancelar la operación',
      explicacion: resolucion == 'entregar'
          ? 'Confirmá que verificaste el pago y la evidencia. Se invalidará el QR del vendedor y se emitirá otro al comprador.'
          : 'Verificá el no pago o la devolución entre usuarios antes de cancelar. La plataforma no devuelve transferencias bancarias.',
    );
    if (motivo == null || _ocupado) return;
    setState(() => _ocupado = true);
    try {
      await ref.read(socialAftrProvider).reventa('resolver', {
        'id': widget.id,
        'resolucion': resolucion,
        'motivo': motivo,
      });
      if (mounted) {
        avisar(context, 'Resolución registrada');
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (mounted) avisar(context, mensajeDeError(e), tipo: TipoAviso.aviso);
    } finally {
      if (mounted) {
        setState(() => _ocupado = false);
        _cargar();
      }
    }
  }

  Future<void> _archivo(String path) async {
    try {
      final url = await ref.read(socialAftrProvider).medio('aftr-p2p', path);
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (c) => Dialog(
          child: Stack(
            children: [
              InteractiveViewer(
                child: Image.network(
                  url,
                  fit: BoxFit.contain,
                  errorBuilder: (_, _, _) => const Padding(
                    padding: EdgeInsets.all(30),
                    child: Text(
                      'No se pudo abrir el comprobante. Volvé a intentar.',
                    ),
                  ),
                ),
              ),
              Positioned(
                right: 4,
                top: 4,
                child: IconButton.filled(
                  tooltip: 'Cerrar comprobante',
                  onPressed: () => Navigator.pop(c),
                  icon: const Icon(Icons.close),
                ),
              ),
            ],
          ),
        ),
      );
    } catch (e) {
      if (mounted) avisar(context, mensajeDeError(e), tipo: TipoAviso.aviso);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Operación de reventa'),
      actions: [
        IconButton(onPressed: _cargar, icon: const Icon(Icons.refresh)),
      ],
    ),
    body: FutureBuilder<DatosSocial>(
      future: _datos,
      builder: (c, s) {
        if (s.hasError)
          return Center(
            child: TextButton(
              onPressed: _cargar,
              child: Text(
                '${mensajeDeError(s.error!)}\nReintentar',
                textAlign: TextAlign.center,
              ),
            ),
          );
        if (!s.hasData) return const EsqueletoLista(filas: 3);
        final j = s.data!;
        final disputa = ['disputa', 'en_disputa'].contains(j['estado']);
        return SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 720),
              child: ListView(
                padding: const EdgeInsets.all(20),
                children: [
                  Text(
                    textoSocial(j['evento']),
                    style: const TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    dineroSocial(j['precio_centavos']),
                    style: const TextStyle(
                      fontSize: 36,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 14),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(18),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(
                            estadoSocial(j['estado']),
                            style: TextStyle(
                              fontSize: 19,
                              fontWeight: FontWeight.w800,
                              color: disputa
                                  ? VenueColors.aviso
                                  : VenueColors.texto,
                            ),
                          ),
                          if (j['vendedor'] != null)
                            Text('Vendedor: ${textoSocial(j['vendedor'])}'),
                          if (j['comprador'] != null)
                            Text('Comprador: ${textoSocial(j['comprador'])}'),
                          if (j['vence_at'] != null)
                            Text(
                              'Plazo de pago: ${fechaSocial(j['vence_at'])}',
                            ),
                          if (j['confirmar_hasta'] != null)
                            Text(
                              'Confirmación hasta: ${fechaSocial(j['confirmar_hasta'])}',
                            ),
                          if (j['metodo'] != null)
                            Text('Método: ${textoSocial(j['metodo'])}'),
                        ],
                      ),
                    ),
                  ),
                  if (widget.principal && j['comprobante_path'] is String)
                    OutlinedButton.icon(
                      onPressed: () =>
                          _archivo(j['comprobante_path'] as String),
                      icon: const Icon(Icons.receipt_long_outlined),
                      label: const Text('Ver comprobante'),
                    ),
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 18),
                    child: Text(
                      'Historial de la operación',
                      style: TextStyle(
                        fontSize: 21,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  for (final h in filasSocial(j['historial']))
                    Card(
                      child: ListTile(
                        leading: const Icon(Icons.history_rounded),
                        title: Text(
                          textoSocial(h['texto']).isNotEmpty
                              ? textoSocial(h['texto'])
                              : estadoSocial(h['tipo']),
                        ),
                        subtitle: Text(
                          '${textoSocial(h['autor'])} · ${fechaSocial(h['created_at'])}',
                        ),
                        trailing:
                            widget.principal && h['archivo_path'] is String
                            ? IconButton(
                                tooltip: 'Ver archivo',
                                onPressed: () =>
                                    _archivo(h['archivo_path'] as String),
                                icon: const Icon(Icons.attachment),
                              )
                            : null,
                      ),
                    ),
                  if (widget.principal && disputa) ...[
                    const SizedBox(height: 20),
                    Text(
                      'Resolver disputa',
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                        color: VenueColors.aviso,
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Revisá la evidencia de ambas partes. La resolución y tu motivo quedan en el historial.',
                    ),
                    if (_ocupado) const LinearProgressIndicator(),
                    const SizedBox(height: 14),
                    FilledButton.icon(
                      onPressed: _ocupado ? null : () => _resolver('entregar'),
                      icon: const Icon(Icons.verified_outlined),
                      label: const Text('Entregar entrada al comprador'),
                    ),
                    OutlinedButton.icon(
                      onPressed: _ocupado ? null : () => _resolver('cancelar'),
                      icon: const Icon(Icons.cancel_outlined),
                      label: const Text(
                        'Cancelar y devolver entrada al vendedor',
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        );
      },
    ),
  );
}

String estadoSocial(dynamic valor) => switch (valor) {
  'publicada' || 'activa' || 'disponible' => 'Publicada',
  'pendiente_pago' || 'esperando_pago' || 'pendiente' => 'Esperando pago',
  'pago_reportado' ||
  'pagada' ||
  'por_confirmar' => 'Pago informado · esperando confirmación',
  'completada' || 'completa' || 'confirmada' => 'Completada',
  'cancelada' || 'cancelado' => 'Cancelada',
  'vencida' || 'expirada' => 'Vencida',
  'disputa' || 'en_disputa' => 'En disputa · QR bloqueado',
  'vendida' => 'Vendida',
  'retirada' => 'Retirada',
  _ => textoSocial(valor).replaceAll('_', ' '),
};

Future<String?> motivoSocial(
  BuildContext context, {
  required String titulo,
  required String explicacion,
}) async {
  final texto = TextEditingController();
  final form = GlobalKey<FormState>();
  try {
    return await showDialog<String>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(titulo),
        content: SingleChildScrollView(
          child: Form(
            key: form,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(explicacion),
                const SizedBox(height: 18),
                TextFormField(
                  controller: texto,
                  minLines: 2,
                  maxLines: 5,
                  maxLength: 1000,
                  decoration: const InputDecoration(
                    labelText: 'Motivo de la decisión',
                  ),
                  validator: (s) => (s?.trim().length ?? 0) < 10
                      ? 'Explicá el motivo (al menos 10 caracteres)'
                      : null,
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c),
            child: const Text('Volver'),
          ),
          FilledButton(
            onPressed: () {
              if (form.currentState!.validate())
                Navigator.pop(c, texto.text.trim());
            },
            child: const Text('Confirmar'),
          ),
        ],
      ),
    );
  } finally {
    texto.dispose();
  }
}
