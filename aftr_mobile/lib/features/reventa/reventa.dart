import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/networking/supabase.dart';
import '../../core/theme/aftr_theme.dart';
import '../../core/widgets/piezas.dart';
import '../../data/aftr_repo.dart';
import '../../data/pulse_repo.dart';
import '../../data/social_repo.dart';
import '../auth/asegurar_cuenta.dart';

String precioReventa(Object? centavos) => 'Bs ${importePulse(centavos)}';
String relojReventa(Duration d) => '${(d.inSeconds ~/ 60).toString().padLeft(2, '0')}:${(d.inSeconds % 60).toString().padLeft(2, '0')}';

void refrescarReventa(WidgetRef ref) {
  ref.invalidate(mercadoProvider); ref.invalidate(misReventasProvider);
  ref.invalidate(accesosProvider);
}

class ReventaScreen extends ConsumerStatefulWidget {
  const ReventaScreen({super.key, this.eventoId});
  final String? eventoId;
  @override
  ConsumerState<ReventaScreen> createState() => _ReventaState();
}

class _ReventaState extends ConsumerState<ReventaScreen> {
  bool _comprando = false;
  Future<void> _comprar(DatosSocial oferta) async {
    if (_comprando || !await asegurarCuenta(context, ref) || !mounted) return;
    // El vendedor acepta primero: hasta entonces no se ve ningún dato de cobro
    // y no hay nada que pagar. El texto decía lo contrario.
    final acepta = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(
      title: const Text('Pedir esta entrada'),
      content: Text('${oferta['evento']}\n${precioReventa(oferta['precio_centavos'])}\n\nSe le pide la entrada al vendedor. Cuando acepte vas a ver sus datos de cobro y tenés ${oferta['pago_minutos'] ?? 15} minutos para pagarle. Hasta entonces no transfieras nada.'),
      actions: [TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Volver')),
        TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Enviar pedido'))]));
    if (acepta != true || !mounted) return;
    setState(() => _comprando = true);
    try {
      final orden = await ref.read(socialRepoProvider).reventa('comprar', {'oferta_id': oferta['id'], 'client_key': nuevaOperacion()});
      refrescarReventa(ref);
      if (mounted) await context.push('/reventa/orden/${orden['id']}');
    } catch (e) { if (mounted) avisar(context, mensajeDeError(e)); }
    finally { if (mounted) setState(() => _comprando = false); }
  }
  Future<void> _vender() async {
    if (!await asegurarCuenta(context, ref) || !mounted) return;
    await Navigator.of(context).push<void>(MaterialPageRoute(builder: (_) => const PublicarReventaScreen()));
  }
  @override
  Widget build(BuildContext context) {
    final mercado = ref.watch(mercadoProvider);
    final conCuenta = ref.watch(usuarioIdProvider) != null;
    final mias = conCuenta ? ref.watch(misReventasProvider) : null;
    final ofertas = listaSocial(mercado.value?['ofertas']).where((e) => widget.eventoId == null || e['evento_id'] == widget.eventoId).toList();
    return DefaultTabController(length: 2, child: Scaffold(
      appBar: AppBar(title: const Text('Reventa oficial'), bottom: const TabBar(tabs: [Tab(text: 'Marketplace'), Tab(text: 'Mis operaciones')])),
      body: TabBarView(children: [
        RefreshIndicator(onRefresh: () => ref.refresh(mercadoProvider.future), child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 24, 20, 50), children: [
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [Expanded(child: Text('Otra oportunidad\npara estar ahí.', style: Aftr.titular(34))),
              Container(padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: Aftr.acento.withValues(alpha: .12), borderRadius: BorderRadius.circular(16)),
                child: const Icon(Icons.swap_horiz_rounded, color: Aftr.acento, size: 28))]),
            const SizedBox(height: 12),
            Text('Entradas verificadas por AFTR. Pago directo entre personas y un nuevo QR al completarse la compra.', style: Aftr.cuerpo(14)),
            const SizedBox(height: 22), BotonAftr('Vender una entrada', secundario: true, onTap: _vender),
            const SizedBox(height: 26),
            if (mercado.isLoading && mercado.value == null) const Center(child: CircularProgressIndicator(color: Aftr.acento)),
            if (mercado.hasError) _ErrorReventa(mercado.error!, () => ref.invalidate(mercadoProvider)),
            if (!mercado.isLoading && !mercado.hasError && ofertas.isEmpty) const _VacioReventa('Todavía no hay entradas en reventa para esta selección.'),
            // La oferta en operación no desaparece del mercado: dice cuándo
            // vuelve. Esconderla hacía ver un mercado más chico del que hay.
            for (final o in ofertas) _PanelReventa(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const _Etiqueta('ENTRADA VERIFICADA', icono: Icons.verified_outlined),
              const SizedBox(height: 16), Text('${o['evento']}', style: Aftr.fuerte(22)),
              const SizedBox(height: 6), Text('${o['club'] ?? ''} · ${o['fecha'] ?? ''}', style: Aftr.cuerpo(13)),
              const SizedBox(height: 20), Row(children: [Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(precioReventa(o['precio_centavos']), style: Aftr.fuerte(25)),
                Text('Vende ${o['vendedor'] ?? 'un usuario de AFTR'}', style: Aftr.cuerpo(12))])),
                if (o['estado'] == 'reservada')
                  Text(enPagoVuelve(o['vuelve_at'], DateTime.now().add(desfaseSocial(mercado.value ?? {}))),
                    textAlign: TextAlign.right, style: Aftr.cuerpo(13, c: Aftr.acento))
                else
                  FilledButton(onPressed: _comprando ? null : () => _comprar(o), child: const Text('Comprar'))]),
            ])),
          ])),
        if (!conCuenta) Center(child: Padding(padding: const EdgeInsets.all(28), child: BotonAftr('Ingresar para ver mis operaciones', onTap: () => asegurarCuenta(context, ref))))
        else RefreshIndicator(onRefresh: () => ref.refresh(misReventasProvider.future), child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 22, 20, 50), children: [
            if (mias!.hasError) _ErrorReventa(mias.error!, () => ref.invalidate(misReventasProvider)),
            if (mias.isLoading && mias.value == null) const Center(child: CircularProgressIndicator(color: Aftr.acento)),
            Text('Operaciones', style: Aftr.fuerte(23)), const SizedBox(height: 14),
            if (listaSocial(mias.value?['ordenes']).isEmpty && !mias.isLoading) const _VacioReventa('Tus compras, ventas, cancelaciones y disputas aparecen acá.'),
            for (final o in listaSocial(mias.value?['ordenes'])) _PanelReventa(child: InkWell(
              onTap: () => context.push('/reventa/orden/${o['id']}'), child: Row(children: [
                const Icon(Icons.receipt_long_outlined, color: Aftr.acento), const SizedBox(width: 14),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text('${o['evento']}', style: Aftr.fuerte(16)),
                  const SizedBox(height: 5), Text('${etiquetaReventa(o['estado'])} · ${precioReventa(o['precio_centavos'])}', style: Aftr.cuerpo(13))])),
                const Icon(Icons.chevron_right),
              ]))),
            const SizedBox(height: 24), Text('Publicaciones', style: Aftr.fuerte(23)), const SizedBox(height: 14),
            for (final o in listaSocial(mias.value?['ofertas'])) _MiOferta(o),
            BotonAftr('Publicar una entrada', secundario: true, onTap: _vender),
          ])),
      ]),
    ));
  }
}

class _MiOferta extends ConsumerStatefulWidget {
  const _MiOferta(this.oferta);
  final DatosSocial oferta;
  @override
  ConsumerState<_MiOferta> createState() => _MiOfertaState();
}
class _MiOfertaState extends ConsumerState<_MiOferta> {
  bool _ocupado = false;
  @override
  Widget build(BuildContext context) {
    final o = widget.oferta;
    final cancelable = const {'publicada', 'activa', 'abierta', 'disponible'}.contains(o['estado']);
    return _PanelReventa(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('${o['evento']}', style: Aftr.fuerte(17)), const SizedBox(height: 6),
      Text('${precioReventa(o['precio_centavos'])} · ${etiquetaReventa(o['estado'])}', style: Aftr.cuerpo(14)),
      if (cancelable) TextButton(onPressed: _ocupado ? null : () async {
        setState(() => _ocupado = true);
        try { await ref.read(socialRepoProvider).reventa('cancelar', {'oferta_id': o['id']}); refrescarReventa(ref); }
        catch (e) { if (context.mounted) avisar(context, mensajeDeError(e)); }
        finally { if (mounted) setState(() => _ocupado = false); }
      }, child: const Text('Retirar publicación')),
    ]));
  }
}

class PublicarReventaScreen extends ConsumerStatefulWidget {
  const PublicarReventaScreen({super.key, this.entradaId});
  final String? entradaId;
  @override
  ConsumerState<PublicarReventaScreen> createState() => _PublicarReventaState();
}
class _PublicarReventaState extends ConsumerState<PublicarReventaScreen> {
  final _form = GlobalKey<FormState>();
  final _precio = TextEditingController(), _titular = TextEditingController(),
      _banco = TextEditingController(), _cuenta = TextEditingController();
  final _clave = nuevaOperacion();
  String? _entrada, _qrPath, _error;
  Uint8List? _qr;
  bool _ocupado = false, _publicada = false;
  SocialRepo? _repo;
  @override
  void initState() { super.initState(); _entrada = widget.entradaId; _repo = ref.read(socialRepoProvider); }
  @override
  void dispose() {
    _precio.dispose(); _titular.dispose(); _banco.dispose(); _cuenta.dispose();
    if (!_publicada && _qrPath != null) _repo?.borrar('aftr-p2p', _qrPath!);
    super.dispose();
  }
  bool get _tieneQr => _qr != null || _qrPath != null;
  Future<void> _elegirQr() async {
    try {
      final archivo = await ImagePicker().pickImage(source: ImageSource.gallery, maxWidth: 1600, imageQuality: 90);
      if (archivo == null) return;
      if (await archivo.length() > 8 * 1024 * 1024) throw const FormatException('El QR debe pesar menos de 8 MB.');
      final b = await archivo.readAsBytes(); if (tipoMedio(b).video) throw const FormatException('Elegí una imagen.');
      if (!mounted) return;
      if (_qrPath != null) { await _repo!.borrar('aftr-p2p', _qrPath!); _qrPath = null; }
      setState(() => _qr = b);
      _form.currentState?.validate();
    } catch (e) { if (mounted) setState(() => _error = mensajeDeError(e)); }
  }
  Future<void> _publicar() async {
    if (_ocupado || !_form.currentState!.validate()) return;
    setState(() { _ocupado = true; _error = null; });
    try {
      if (_qr != null) _qrPath ??= await _repo!.subir(_qr!, historia: false);
      await _repo!.reventa('publicar', {'entrada_id': _entrada,
        'precio_centavos': centavosDe(_precio.text), 'client_key': _clave,
        'metodo': {'titular': _titular.text.trim(), 'banco': _banco.text.trim(),
          'cuenta': _cuenta.text.trim(), if (_qrPath != null) 'qr_path': _qrPath}});
      _publicada = true; refrescarReventa(ref);
      if (mounted) { avisar(context, 'Entrada publicada.'); Navigator.pop(context); }
    } catch (e) { if (mounted) setState(() => _error = mensajeDeError(e)); }
    finally { if (mounted) setState(() => _ocupado = false); }
  }
  @override
  Widget build(BuildContext context) {
    final datos = ref.watch(misReventasProvider);
    final entradas = listaSocial(datos.value?['entradas']);
    final existe = entradas.any((e) => e['id'] == _entrada);
    return Scaffold(appBar: AppBar(title: const Text('Vender una entrada')), body: Form(key: _form, child: ListView(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 40), children: [
        Text('Tu entrada,\notra noche para alguien.', style: Aftr.titular(32)),
        const SizedBox(height: 12), Text('Solo podés publicar entradas tuyas, sin usar y habilitadas para reventa por el boliche. Precio en bolivianos, sin comisión.', style: Aftr.cuerpo(14)),
        const SizedBox(height: 24),
        if (datos.isLoading) const LinearProgressIndicator(color: Aftr.acento),
        if (datos.hasError) _ErrorReventa(datos.error!, () => ref.invalidate(misReventasProvider)),
        if (!datos.isLoading && entradas.isEmpty) const _VacioReventa('No tenés entradas habilitadas para revender.'),
        DropdownButtonFormField<String>(initialValue: existe ? _entrada : null, isExpanded: true,
          decoration: const InputDecoration(labelText: 'Entrada'),
          items: [for (final e in entradas) DropdownMenuItem(value: '${e['id']}', child: Text('${e['evento']} · ${'${e['id']}'.substring(0, 8)}', overflow: TextOverflow.ellipsis))],
          onChanged: _ocupado ? null : (v) => _entrada = v,
          validator: (v) => v == null ? 'Elegí una entrada disponible.' : null),
        const SizedBox(height: 14),
        TextFormField(controller: _precio, enabled: !_ocupado, keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(labelText: 'Precio en Bs', hintText: '150.00'),
          validator: (v) => (centavosDe(v ?? '') ?? 0) <= 0 ? 'Ingresá un precio mayor a cero, con hasta dos decimales.' : null),
        const SizedBox(height: 26), Text('Dónde vas a recibir el pago', style: Aftr.fuerte(19)), const SizedBox(height: 8),
        Text('Alcanza con el QR de cobro: el número de cuenta solo hace falta si no adjuntás uno.', style: Aftr.cuerpo(13)),
        const SizedBox(height: 14),
        for (final campo in [(_titular, 'Titular de la cuenta'), (_banco, 'Banco')]) ...[
          TextFormField(controller: campo.$1, enabled: !_ocupado, maxLength: 120,
            decoration: InputDecoration(labelText: campo.$2),
            validator: (v) => (v ?? '').trim().isEmpty ? 'Completá este dato.' : null), const SizedBox(height: 10)],
        // con QR adjunto el comprador ya tiene cómo pagar: pedir además el
        // número de cuenta dejaba la publicación trabada sin motivo
        TextFormField(controller: _cuenta, enabled: !_ocupado, maxLength: 120,
          decoration: InputDecoration(labelText: 'Número de cuenta${_tieneQr ? ' (opcional)' : ''}'),
          validator: (v) => _tieneQr || (v ?? '').trim().isNotEmpty ? null
            : 'Poné el número de cuenta o adjuntá tu QR de cobro.'),
        const SizedBox(height: 10),
        if (_qr != null) SizedBox(height: 180, child: Image.memory(_qr!, fit: BoxFit.contain)),
        OutlinedButton.icon(onPressed: _ocupado ? null : _elegirQr, icon: const Icon(Icons.qr_code_2), label: Text(_qr == null ? 'Adjuntar QR de cobro' : 'Cambiar QR de cobro')),
        const SizedBox(height: 14), Text('Cuando alguien compre, revisá el ingreso en tu banco antes de confirmar. Al confirmar, tu QR de entrada se invalida definitivamente.', style: Aftr.cuerpo(13)),
        if (_error != null) Padding(padding: const EdgeInsets.symmetric(vertical: 16), child: Text(_error!, style: Aftr.cuerpo(14, c: Aftr.alerta))),
        const SizedBox(height: 20), BotonAftr('Publicar entrada', cargando: _ocupado, onTap: entradas.isEmpty ? null : _publicar),
      ])));
  }
}

class OrdenReventaScreen extends ConsumerStatefulWidget {
  const OrdenReventaScreen({super.key, required this.id});
  final String id;
  @override
  ConsumerState<OrdenReventaScreen> createState() => _OrdenState();
}
class _OrdenState extends ConsumerState<OrdenReventaScreen> {
  final _referencia = TextEditingController(), _mensaje = TextEditingController();
  Timer? _reloj;
  bool _ocupado = false;
  String? _comprobante, _error;
  Uint8List? _foto;
  @override
  void initState() { super.initState(); _reloj = Timer.periodic(const Duration(seconds: 1), (_) { if (mounted) setState(() {}); }); }
  @override
  void dispose() { _reloj?.cancel(); _referencia.dispose(); _mensaje.dispose(); super.dispose(); }
  Future<void> _accion(String accion, [DatosSocial datos = const {}]) async {
    if (_ocupado) return;
    setState(() { _ocupado = true; _error = null; });
    try {
      await ref.read(socialRepoProvider).reventa(accion, {'id': widget.id, ...datos});
      ref.invalidate(ordenReventaProvider(widget.id)); refrescarReventa(ref);
      if (accion == 'mensaje') _mensaje.clear();
      if (mounted && accion != 'mensaje') avisar(context, switch (accion) {
        'aceptar' => 'Aceptaste. El comprador ya ve tus datos y tiene unos minutos para pagar.',
        'rechazar' => 'Pedido rechazado. Tu entrada vuelve al mercado.',
        'confirmar' => 'Venta completada. El comprador ya tiene su nueva entrada.',
        'informar_pago' => 'Pago informado. Esperando confirmación del vendedor.',
        'disputar' => 'Disputa abierta. La entrada sigue protegida durante la revisión.',
        'cancelar' => 'Operación cancelada.',
        _ => 'Operación actualizada.',
      });
    } catch (e) { if (mounted) setState(() => _error = mensajeDeError(e)); }
    finally { if (mounted) setState(() => _ocupado = false); }
  }
  Future<void> _adjuntar() async {
    setState(() { _ocupado = true; _error = null; });
    try {
      final f = await ImagePicker().pickImage(source: ImageSource.gallery, maxWidth: 1800, imageQuality: 88);
      if (f == null) return;
      if (await f.length() > 8 * 1024 * 1024) throw const FormatException('El comprobante debe pesar menos de 8 MB.');
      final bytes = await f.readAsBytes();
      final path = await ref.read(socialRepoProvider).subir(bytes, historia: false);
      if (!mounted) return;
      final anterior = _comprobante;
      setState(() { _comprobante = path; _foto = bytes; });
      if (anterior != null) await ref.read(socialRepoProvider).borrar('aftr-p2p', anterior);
    } catch (e) { if (mounted) setState(() => _error = mensajeDeError(e)); }
    finally { if (mounted) setState(() => _ocupado = false); }
  }
  Future<void> _confirmar() async {
    final ok = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(title: const Text('Confirmar dinero recibido'),
      content: const Text('Confirmá únicamente después de verificar el ingreso en tu banco. Esta acción entrega la entrada al comprador e invalida definitivamente tu QR anterior.'),
      actions: [TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Volver')),
        TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Recibí el dinero'))]));
    if (ok == true && mounted) await _accion('confirmar');
  }
  Future<void> _disputar() async {
    final motivo = TextEditingController();
    final texto = await showDialog<String>(context: context, builder: (ctx) => AlertDialog(title: const Text('Abrir disputa'),
      content: TextField(controller: motivo, maxLines: 4, maxLength: 1000, decoration: const InputDecoration(hintText: 'Explicá lo ocurrido. Incluí detalles que permitan revisar el pago.')),
      actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Volver')),
        TextButton(onPressed: () { if (motivo.text.trim().length >= 10) Navigator.pop(ctx, motivo.text.trim()); }, child: const Text('Enviar disputa'))]));
    // Dialog routes finish their reverse animation before the controller is
    // disposed, avoiding a TextField using a disposed controller.
    Future<void>.delayed(const Duration(seconds: 1), motivo.dispose);
    if (texto != null && mounted) await _accion('disputar', {'motivo': texto});
  }
  Future<void> _cancelar() async {
    final ok = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(title: const Text('Cancelar operación'),
      content: const Text('Cancelá solo si no hiciste el pago. Si ya transferiste o hay un problema, abrí una disputa.'),
      actions: [TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Volver')),
        TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('No pagué, cancelar'))]));
    if (ok == true && mounted) await _accion('cancelar');
  }
  @override
  Widget build(BuildContext context) {
    final async = ref.watch(ordenReventaProvider(widget.id));
    final o = async.value;
    if (o == null) return Scaffold(appBar: AppBar(title: const Text('Orden de reventa')), body: Center(child: async.hasError ?
      _ErrorReventa(async.error!, () => ref.invalidate(ordenReventaProvider(widget.id))) : const CircularProgressIndicator(color: Aftr.acento)));
    final comprador = ref.watch(usuarioIdProvider) == o['comprador_id'];
    final fin = ordenTerminada(o['estado']);
    final informado = pagoInformado(o['estado']);
    final disputa = const {'en_disputa', 'disputada', 'disputa'}.contains(o['estado']);
    final espera = esperaAlVendedor(o['estado']);
    final ahora = DateTime.now().add(desfaseSocial(o));
    final restante = tiempoRestante(informado ? o['confirmar_hasta'] : o['vence_at'], ahora);
    final metodo = mapaSocial(o['metodo']);
    return Scaffold(appBar: AppBar(title: const Text('Orden de reventa'), actions: [IconButton(onPressed: () => ref.invalidate(ordenReventaProvider(widget.id)), icon: const Icon(Icons.refresh))]),
      body: RefreshIndicator(onRefresh: () => ref.refresh(ordenReventaProvider(widget.id).future), child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 40), children: [
          _Etiqueta(comprador ? 'ESTÁS COMPRANDO' : 'ESTÁS VENDIENDO', icono: Icons.swap_horiz_rounded),
          const SizedBox(height: 14), Text('${o['evento']}', style: Aftr.titular(33)),
          const SizedBox(height: 10), Text(precioReventa(o['precio_centavos']), style: Aftr.fuerte(30)),
          const SizedBox(height: 20), _PanelReventa(child: Row(children: [
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(etiquetaReventa(o['estado']), style: Aftr.fuerte(18)),
              const SizedBox(height: 6), Text(fin ? 'Consultá el detalle en el historial.' : disputa ? 'La entrada sigue bloqueada durante la revisión.' :
                espera ? (comprador
                    ? 'El vendedor tiene que aceptar antes de que veas sus datos de cobro. No transfieras nada todavía.'
                    : 'Alguien quiere tu entrada. Si aceptás, se le muestran tus datos de cobro y tiene unos minutos para pagar.')
                : informado ? 'El vendedor debe verificar el ingreso.' : 'La entrada está protegida durante la operación.', style: Aftr.cuerpo(13))])),
            if (!fin && !disputa) Padding(padding: const EdgeInsets.only(left: 12), child: Text(relojReventa(restante), style: Aftr.fuerte(26, c: Aftr.acento))),
          ])),
          if (!fin && !disputa && restante == Duration.zero) const Padding(padding: EdgeInsets.only(bottom: 18),
            child: Text('El plazo terminó. Actualizando el estado con el servidor…')),
          if (!comprador && espera) ...[
            const SizedBox(height: 6),
            BotonAftr('Aceptar y mostrar mis datos', cargando: _ocupado, onTap: () => _accion('aceptar')),
            const SizedBox(height: 10),
            TextButton(onPressed: _ocupado ? null : () => _accion('rechazar'), child: const Text('Rechazar el pedido')),
          ],
          // Los datos de cobro recién existen cuando el vendedor aceptó: antes
          // alcanzaba con iniciar una orden para juntarlos de todo el mercado.
          if (comprador && !fin && !espera) ...[
            Text('Datos para pagar al vendedor', style: Aftr.fuerte(19)), const SizedBox(height: 12),
            _PanelReventa(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              for (final campo in [('Titular', metodo['titular']), ('Banco', metodo['banco']), ('Cuenta', metodo['cuenta'])])
                if ('${campo.$2 ?? ''}'.trim().isNotEmpty) Padding(padding: const EdgeInsets.only(bottom: 10), child: Row(children: [Expanded(child: SelectableText('${campo.$1}: ${campo.$2 ?? ''}', style: Aftr.cuerpo(14, c: Aftr.texto))),
                  IconButton(tooltip: 'Copiar ${campo.$1.toLowerCase()}', onPressed: () => Clipboard.setData(ClipboardData(text: '${campo.$2 ?? ''}')), icon: const Icon(Icons.copy_outlined, size: 18))])),
              if (metodo['qr_path'] != null) ImagenP2p(path: '${metodo['qr_path']}'),
            ])),
            if (!informado && !disputa) ...[
              Text('Informar el pago', style: Aftr.fuerte(20)), const SizedBox(height: 12),
              Text('Transferí el importe exacto y adjuntá tu comprobante. AFTR no cobra esta operación con PULSE ni con el QR de recargas.', style: Aftr.cuerpo(13)),
              const SizedBox(height: 14),
              if (_foto != null) SizedBox(height: 180, child: Image.memory(_foto!, fit: BoxFit.contain)),
              OutlinedButton.icon(onPressed: _ocupado ? null : _adjuntar, icon: const Icon(Icons.attach_file), label: Text(_foto == null ? 'Adjuntar comprobante' : 'Cambiar comprobante')),
              const SizedBox(height: 12), TextField(controller: _referencia, maxLength: 120, decoration: const InputDecoration(labelText: 'Referencia de la transferencia')),
              const SizedBox(height: 14), BotonAftr('Ya pagué', cargando: _ocupado, onTap: _comprobante == null ? null :
                () => _accion('informar_pago', {'comprobante_path': _comprobante, 'referencia': _referencia.text.trim()})),
            ],
          ],
          if (o['comprobante_path'] != null) ...[
            const SizedBox(height: 18), Text('Comprobante informado', style: Aftr.fuerte(19)), const SizedBox(height: 12),
            ImagenP2p(path: '${o['comprobante_path']}'),
            if (o['referencia'] != null) SelectableText('Referencia: ${o['referencia']}', style: Aftr.cuerpo(14)),
          ],
          if (!comprador && informado && !disputa && !fin) ...[const SizedBox(height: 20), BotonAftr('Confirmar dinero recibido', cargando: _ocupado, onTap: _confirmar)],
          if (comprador && const {'vencida','cancelada'}.contains(o['estado']) && o['resolucion'] == null)
            TextButton(onPressed: _ocupado ? null : _disputar, child: const Text('Pagué fuera de plazo · Abrir disputa')),
          if (disputa) OutlinedButton.icon(onPressed: _ocupado ? null : () async {
            await _adjuntar();
            if (_comprobante != null && mounted) await _accion('mensaje', {'texto':'Prueba adjunta para revisión de AFTR','archivo_path':_comprobante});
          }, icon: const Icon(Icons.attach_file), label: const Text('Adjuntar prueba')),
          if (!fin) ...[const SizedBox(height: 12),
            if (!informado && !disputa) TextButton(onPressed: _ocupado ? null : _cancelar, child: const Text('Cancelar operación')),
            // sin datos de cobro mostrados no hay nada que disputar
            if (!disputa && !espera) TextButton(onPressed: _ocupado ? null : _disputar, child: const Text('Tengo un problema · Abrir disputa')),
          ],
          if (o['estado'] == 'completada' || o['estado'] == 'confirmada') ...[
            const SizedBox(height: 16), BotonAftr(comprador ? 'Ver mi nueva entrada' : 'Ver mis accesos', onTap: () => context.go('/accesos'))],
          if (_error != null) Padding(padding: const EdgeInsets.symmetric(vertical: 16), child: Text(_error!, style: Aftr.cuerpo(14, c: Aftr.alerta))),
          const SizedBox(height: 28), Text('Conversación e historial', style: Aftr.fuerte(22)), const SizedBox(height: 14),
          for (final h in listaSocial(o['historial'])) _PanelReventa(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('${h['autor'] ?? etiquetaReventa(h['tipo'])}', style: Aftr.fuerte(13)), const SizedBox(height: 6),
            SelectableText('${h['texto'] ?? etiquetaReventa(h['tipo'])}', style: Aftr.cuerpo(14, c: Aftr.texto)),
            if (h['archivo_path'] != null) ImagenP2p(path: '${h['archivo_path']}'),
            const SizedBox(height: 8), Text(_fechaHistorial(h['created_at']), style: Aftr.cuerpo(11)),
          ])),
          if (!fin) Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Expanded(child: TextField(controller: _mensaje, maxLength: 2000, minLines: 1, maxLines: 4,
              decoration: const InputDecoration(hintText: 'Escribí en la operación…'))),
            const SizedBox(width: 10), IconButton.filled(tooltip: 'Enviar mensaje', onPressed: _ocupado ? null : () {
              final texto = _mensaje.text.trim(); if (texto.isNotEmpty) _accion('mensaje', {'texto': texto});
            }, icon: const Icon(Icons.arrow_upward_rounded)),
          ]),
          const SizedBox(height: 14), SelectableText('Orden ${widget.id}', style: Aftr.cuerpo(11)),
        ])));
  }
}

String _fechaHistorial(Object? v) {
  final d = DateTime.tryParse('$v')?.toLocal();
  if (d == null) return '';
  return '${d.day}/${d.month}/${d.year} · ${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
}

class ImagenP2p extends ConsumerStatefulWidget {
  const ImagenP2p({super.key, required this.path});
  final String path;
  @override
  ConsumerState<ImagenP2p> createState() => _ImagenP2pState();
}
class _ImagenP2pState extends ConsumerState<ImagenP2p> {
  late Future<String> _url;
  @override
  void initState() { super.initState(); _url = ref.read(socialRepoProvider).firmar('aftr-p2p', widget.path); }
  @override
  void didUpdateWidget(covariant ImagenP2p oldWidget) { super.didUpdateWidget(oldWidget); if (oldWidget.path != widget.path) _recargar(); }
  void _recargar() { setState(() => _url = ref.read(socialRepoProvider).firmar('aftr-p2p', widget.path)); }
  @override
  Widget build(BuildContext context) => FutureBuilder<String>(future: _url, builder: (_, s) {
    if (s.hasError) return TextButton(onPressed: _recargar, child: const Text('Reintentar abrir imagen'));
    if (s.data == null) return const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator(color: Aftr.acento)));
    return InkWell(onTap: () => Navigator.of(context).push<void>(MaterialPageRoute(builder: (_) => Scaffold(
      appBar: AppBar(title: const Text('Comprobante / QR de pago')),
      body: Center(child: InteractiveViewer(minScale: .5, maxScale: 5, child: Image.network(s.data!, fit: BoxFit.contain,
        errorBuilder: (_, _, _) => TextButton(onPressed: () { Navigator.pop(context); _recargar(); }, child: const Text('Renovar acceso a la imagen')))))))),
      child: Padding(padding: const EdgeInsets.symmetric(vertical: 12), child: SizedBox(height: 230, child: Image.network(s.data!, fit: BoxFit.contain,
        errorBuilder: (_, _, _) => TextButton(onPressed: _recargar, child: const Text('Renovar acceso a la imagen'))))));
  });
}

class _PanelReventa extends StatelessWidget {
  const _PanelReventa({required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) => Container(margin: const EdgeInsets.only(bottom: 14), padding: const EdgeInsets.all(20),
    decoration: BoxDecoration(color: Aftr.superficie, borderRadius: BorderRadius.circular(22), border: Border.all(color: Aftr.borde)), child: child);
}
class _Etiqueta extends StatelessWidget {
  const _Etiqueta(this.texto, {required this.icono});
  final String texto; final IconData icono;
  @override
  Widget build(BuildContext context) => Row(children: [Icon(icono, size: 17, color: Aftr.acento), const SizedBox(width: 7),
    Expanded(child: Text(texto, style: Aftr.etiqueta(c: Aftr.acento)))]);
}
class _ErrorReventa extends StatelessWidget {
  const _ErrorReventa(this.error, this.reintentar);
  final Object error; final VoidCallback reintentar;
  @override
  Widget build(BuildContext context) => Padding(padding: const EdgeInsets.all(20), child: Column(mainAxisSize: MainAxisSize.min, children: [
    Text(mensajeDeError(error), textAlign: TextAlign.center, style: Aftr.cuerpo(14)),
    TextButton(onPressed: reintentar, child: const Text('Reintentar'))]));
}
class _VacioReventa extends StatelessWidget {
  const _VacioReventa(this.texto);
  final String texto;
  @override
  Widget build(BuildContext context) => Padding(padding: const EdgeInsets.symmetric(vertical: 28),
    child: Text(texto, style: Aftr.cuerpo(15)));
}
