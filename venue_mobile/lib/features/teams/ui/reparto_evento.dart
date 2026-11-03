import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/networking/supabase.dart';
import '../../../core/theme/venue_theme.dart';
import '../../../core/widgets/avisos.dart';
import '../../events/data/eventos.dart';

/// Reparto del jefe en un evento con la operación nueva (db/52): el boliche
/// le da al team un % de cada manilla (y, si corresponde, de mesas y combos)
/// y el jefe decide qué % de eso va a cada relacionador. Si no lo definió
/// para este evento, rige el último que usó (la primera vez, 50 %).
class RepartoEvento extends ConsumerStatefulWidget {
  const RepartoEvento({super.key, required this.evento});
  final Evento evento;

  @override
  ConsumerState<RepartoEvento> createState() => _RepartoEventoState();
}

class _RepartoEventoState extends ConsumerState<RepartoEvento> {
  Map<String, dynamic>? _r;
  final _pct = TextEditingController();
  bool _ocupado = false;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  @override
  void dispose() {
    _pct.dispose();
    super.dispose();
  }

  Future<void> _cargar() async {
    try {
      final r = await ref.read(supabaseProvider).rpc('reparto_jefe', params: {'p_evento': widget.evento.id});
      if (!mounted) return;
      setState(() {
        _r = Map<String, dynamic>.from(r as Map);
        _pct.text = _bs(_r!['pct_rrpp'] as num? ?? 50);
      });
    } catch (_) {
      // sin reparto posible (no es jefe, o base sin db/52): no se muestra
    }
  }

  static String _bs(num v) => v == v.roundToDouble() ? '${v.round()}' : v.toStringAsFixed(2);

  Future<void> _guardar() async {
    final v = num.tryParse(_pct.text.trim());
    if (v == null || v < 0 || v > 100) {
      avisar(context, 'Poné un número entre 0 y 100', tipo: TipoAviso.aviso);
      return;
    }
    final acepta = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Confirmar reparto'),
        content: Text('${_bs(v)} % para cada relacionador y ${_bs(100 - v)} % para vos, en ${widget.evento.nombre}.\n\n'
            'Se aplica a todas las ventas de tu team en este evento y administración ve el cambio.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Acepto')),
        ],
      ),
    );
    if (acepta != true || !mounted) return;
    setState(() => _ocupado = true);
    try {
      final r = await ref.read(supabaseProvider).rpc('fijar_reparto_jefe',
          params: {'p_evento': widget.evento.id, 'p_pct_rrpp': v});
      if (!mounted) return;
      setState(() {
        _r = Map<String, dynamic>.from(r as Map);
        _ocupado = false;
      });
      avisar(context, 'Reparto guardado');
    } catch (e) {
      if (!mounted) return;
      setState(() => _ocupado = false);
      avisar(context, mensajeDeError(e), tipo: TipoAviso.aviso);
    }
  }

  @override
  Widget build(BuildContext context) {
    final r = _r;
    if (r == null) return const SizedBox.shrink();
    final tituloStyle = const TextStyle(fontSize: 16, fontWeight: FontWeight.w700);
    final suave = TextStyle(fontSize: 13.5, color: VenueColors.textoSuave, height: 1.35);
    if (r['modo'] != 'jefes') {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Reparto de comisiones', style: tituloStyle),
            const SizedBox(height: 4),
            Text(
              r['modo'] == 'ninguno'
                  ? 'En este evento no se pagan comisiones.'
                  : 'En este evento cada relacionador cobra su comisión entera: no hay reparto del jefe.',
              style: suave,
            ),
          ]),
        ),
      );
    }
    final pozo = r['pozo_manilla'] as num? ?? 0;
    final v = num.tryParse(_pct.text.trim());
    final rel = v == null ? null : (pozo * v).round() / 100;
    final extras = [
      if (r['comision_mesas'] == true) 'el ${_bs(r['pct_comision_mesas'] as num? ?? 0)} % de cada mesa',
      if (r['comision_combos'] == true) 'la comisión de cada combo',
    ];
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Reparto de comisiones · ${widget.evento.nombre}', style: tituloStyle),
          if (r['definido'] != true) ...[
            const SizedBox(height: 6),
            Text('Todavía no definiste el reparto de este evento: se usa el último que usaste '
                '(${_bs(r['pct_rrpp'] as num? ?? 50)} %). Confirmalo o cambialo.',
                style: TextStyle(fontSize: 13.5, color: VenueColors.aviso)),
          ],
          const SizedBox(height: 6),
          Text(
            'Tu team gana ${_bs(pozo)} Bs por manilla${extras.isEmpty ? '' : ', más ${extras.join(' y ')}'}. '
            'Elegí qué parte va a cada relacionador; el resto es tuyo. Lo que vendés vos es todo tuyo.',
            style: suave,
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: 220,
            child: TextField(
              controller: _pct,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(labelText: '% para cada relacionador', suffixText: '%'),
              onChanged: (_) => setState(() {}),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            rel == null || v! < 0 || v > 100
                ? 'Poné un número entre 0 y 100.'
                : 'Por manilla: cada relacionador ${_bs(rel)} Bs · vos ${_bs(pozo - rel)} Bs.',
            style: suave,
          ),
          const SizedBox(height: 12),
          FilledButton(
            onPressed: _ocupado ? null : _guardar,
            child: Text(_ocupado ? 'Guardando…' : (r['definido'] == true ? 'Guardar reparto' : 'Confirmar reparto')),
          ),
        ]),
      ),
    );
  }
}
