import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/networking/supabase.dart';
import '../../../core/theme/venue_theme.dart';
import '../../../core/widgets/avisos.dart';

/// Operación y comisiones de un boliche (evento null) o de un evento.
///
/// Los campos, sus etiquetas y cuándo se ven los decide el servidor
/// (`opciones_operacion`): si mañana se agrega una opción, aparece acá sin
/// publicar una versión nueva de la app. Devuelve true si se guardó.
Future<bool> abrirOperacion(BuildContext context, WidgetRef ref,
    {required String clubId, String? eventoId}) async {
  final Map<String, dynamic> data;
  try {
    data = Map<String, dynamic>.from(await ref.read(supabaseProvider).rpc('opciones_operacion',
        params: {'p_club': clubId, 'p_evento': eventoId}) as Map);
  } catch (e) {
    if (context.mounted) avisar(context, mensajeDeError(e), tipo: TipoAviso.aviso);
    return false;
  }
  if (!context.mounted) return false;
  final ok = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => _OperacionSheet(clubId: clubId, eventoId: eventoId, data: data),
  );
  return ok == true;
}

class _OperacionSheet extends ConsumerStatefulWidget {
  const _OperacionSheet({required this.clubId, required this.eventoId, required this.data});
  final String clubId;
  final String? eventoId;
  final Map<String, dynamic> data;
  @override
  ConsumerState<_OperacionSheet> createState() => _OperacionSheetState();
}

class _OperacionSheetState extends ConsumerState<_OperacionSheet> {
  late final List<Map<String, dynamic>> _campos = [
    for (final c in (widget.data['campos'] as List? ?? const [])) Map<String, dynamic>.from(c as Map),
  ];
  final _valores = <String, dynamic>{};
  final _textos = <String, TextEditingController>{};
  bool _ocupado = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    for (final c in _campos) {
      final k = c['clave'] as String;
      _valores.putIfAbsent(k, () => c['valor']);
      if (c['tipo'] == 'porcentaje') {
        _textos.putIfAbsent(k, () => TextEditingController(text: _num(c['valor'])));
      }
    }
  }

  @override
  void dispose() {
    for (final t in _textos.values) {
      t.dispose();
    }
    super.dispose();
  }

  String _num(Object? v) {
    if (v is! num) return '';
    return v == v.roundToDouble() ? v.toInt().toString() : v.toString();
  }

  bool _visible(Map<String, dynamic> c) {
    final reglas = Map<String, dynamic>.from(c['visible_si'] as Map? ?? const {});
    return reglas.entries.every((r) => (r.value as List).contains(_valores[r.key]));
  }

  Future<void> _guardar() async {
    for (final c in _campos.where((c) => _visible(c) && c['tipo'] == 'porcentaje')) {
      final v = num.tryParse(_textos[c['clave']]!.text.trim());
      if (v == null || v < 0 || v > 100) {
        setState(() => _error = 'Los porcentajes van de 0 a 100.');
        return;
      }
      _valores[c['clave'] as String] = v;
    }
    setState(() {
      _ocupado = true;
      _error = null;
    });
    try {
      await ref.read(supabaseProvider).rpc('guardar_opciones_operacion', params: {
        'p_club': widget.clubId,
        'p_evento': widget.eventoId,
        'p_valores': _valores,
      });
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        setState(() {
          _ocupado = false;
          _error = mensajeDeError(e);
        });
      }
    }
  }

  Widget _campo(Map<String, dynamic> c) {
    final k = c['clave'] as String;
    final ayuda = c['ayuda'] as String?;
    Widget nota(String t) => Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text(t, style: TextStyle(fontSize: 12.5, color: VenueColors.textoSuave)),
        );
    switch (c['tipo']) {
      case 'opcion':
        final ops = [for (final o in (c['opciones'] as List? ?? const [])) Map<String, dynamic>.from(o as Map)];
        final elegida = ops.where((o) => o['valor'] == _valores[k]).firstOrNull;
        return Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(c['etiqueta'] as String, style: const TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            SegmentedButton<String>(
              showSelectedIcon: false,
              segments: [
                for (final o in ops)
                  ButtonSegment(value: o['valor'] as String, label: Text(o['etiqueta'] as String)),
              ],
              selected: {if (_valores[k] is String) _valores[k] as String},
              onSelectionChanged: (s) => setState(() => _valores[k] = s.first),
            ),
            if (elegida?['ayuda'] != null) nota(elegida!['ayuda'] as String),
          ]),
        );
      case 'si_no':
        return SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(c['etiqueta'] as String),
          subtitle: ayuda == null ? null : Text(ayuda),
          value: _valores[k] == true,
          onChanged: (v) => setState(() => _valores[k] = v),
        );
      case 'porcentaje':
        return Padding(
          padding: const EdgeInsets.only(bottom: 14),
          child: TextField(
            controller: _textos[k],
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(labelText: c['etiqueta'] as String, suffixText: '%', helperText: ayuda, helperMaxLines: 3),
          ),
        );
    }
    return const SizedBox.shrink();
  }

  @override
  Widget build(BuildContext context) {
    final aviso = widget.data['aviso'] as String?;
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 18, 20, 20 + MediaQuery.viewInsetsOf(context).bottom),
      child: SingleChildScrollView(
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(widget.eventoId == null ? 'Relacionadores y comisiones' : 'Comisiones de este evento',
              style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w700)),
          const SizedBox(height: 6),
          if (aviso != null)
            Text(aviso, style: TextStyle(fontSize: 13.5, color: VenueColors.aviso))
          else if (widget.eventoId == null)
            Text('Es lo que usa cada evento nuevo. Cada evento se puede cambiar después, sin tocar los demás.',
                style: TextStyle(fontSize: 13.5, color: VenueColors.textoSuave)),
          const SizedBox(height: 16),
          for (final c in _campos)
            if (_visible(c)) _campo(c),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Text(_error!, style: TextStyle(color: VenueColors.mal)),
            ),
          FilledButton(
            onPressed: _ocupado ? null : _guardar,
            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(50)),
            child: Text(_ocupado ? 'Guardando…' : 'Guardar'),
          ),
        ]),
      ),
    );
  }
}
