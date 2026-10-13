import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/networking/supabase.dart';
import '../../core/theme/venue_theme.dart';
import '../../core/widgets/avisos.dart';
import '../clubs/data/clubs.dart';

/// Lo que pasa una vez al entrar a un boliche, igual que en la web:
///  1. los avisos del administrador que la persona todavía no leyó, de a
///     uno, quedando registrado que los vio;
///  2. el pedido del número de WhatsApp si no lo cargó. Para relacionadores
///     y jefes es obligatorio; seguridad y caja pueden postergarlo.
/// Los roles de barra no reciben ninguna de las dos cosas.
Future<void> correrBienvenida(BuildContext context, WidgetRef ref) async {
  final club = ref.read(clubActivoIdProvider);
  final rol = ref.read(rolProvider).value;
  if (club == null || rol == null) return;
  if (const {Rol.propietario, Rol.barra, Rol.deposito}.contains(rol)) return;
  final sb = ref.read(supabaseProvider);

  try {
    final pend = (await sb.rpc('avisos_pendientes', params: {'p_club': club})
            as List?) ??
        const [];
    for (var i = 0; i < pend.length; i++) {
      final a = Map<String, dynamic>.from(pend[i] as Map);
      if (!context.mounted) return;
      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (c) => AlertDialog(
          icon: const Icon(Icons.campaign_rounded, size: 34),
          title: Text(a['titulo'] as String? ?? 'Aviso'),
          content: SingleChildScrollView(
              child: Text(a['mensaje'] as String? ?? '',
                  style: const TextStyle(height: 1.45))),
          actions: [
            FilledButton(
              onPressed: () => Navigator.pop(c),
              child: Text(pend.length > 1
                  ? 'Entendido (${i + 1}/${pend.length})'
                  : 'Entendido'),
            ),
          ],
        ),
      );
      await sb.rpc('marcar_aviso_visto', params: {'p_aviso': a['id']});
    }

    final tiene = await sb.rpc('mi_telefono');
    if (tiene != null || !context.mounted) return;
    final obliga = rol == Rol.rrpp || rol == Rol.jefe;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      isDismissible: !obliga,
      enableDrag: !obliga,
      backgroundColor: VenueColors.superficie,
      builder: (_) => PopScope(canPop: !obliga, child: _PedirTelefono(obliga: obliga)),
    );
  } catch (_) {
    // Sin señal al entrar: no se traba el ingreso. Se vuelve a intentar la
    // próxima vez que abra la app.
  }
}

class _PedirTelefono extends ConsumerStatefulWidget {
  const _PedirTelefono({required this.obliga});
  final bool obliga;

  @override
  ConsumerState<_PedirTelefono> createState() => _PedirTelefonoState();
}

class _PedirTelefonoState extends ConsumerState<_PedirTelefono> {
  final _tel = TextEditingController();
  bool _guardando = false;

  @override
  void dispose() {
    _tel.dispose();
    super.dispose();
  }

  Future<void> _guardar() async {
    final v = _tel.text.trim();
    if (v.isEmpty) {
      avisar(context, 'Escribí tu número', tipo: TipoAviso.aviso);
      return;
    }
    setState(() => _guardando = true);
    try {
      await ref.read(supabaseProvider).rpc('guardar_telefono', params: {'p_tel': v});
      if (mounted) {
        Navigator.pop(context);
        avisar(context, 'Listo, quedó guardado');
      }
    } catch (e) {
      if (mounted) {
        avisar(context, mensajeDeError(e), tipo: TipoAviso.aviso);
        setState(() => _guardando = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
          22, 22, 22, 22 + MediaQuery.of(context).viewInsets.bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Icon(Icons.phone_iphone_rounded, size: 34),
          const SizedBox(height: 8),
          const Text('Registrá tu WhatsApp',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
          const SizedBox(height: 8),
          const Text(
            'Es para avisarte los cambios de horario, el cierre de venta y lo de tu rendición sin depender de que estés en el grupo. Se carga una sola vez.',
            textAlign: TextAlign.center,
            style: TextStyle(color: VenueColors.textoSuave, height: 1.45),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _tel,
            autofocus: true,
            keyboardType: TextInputType.phone,
            autofillHints: const [AutofillHints.telephoneNumber],
            onSubmitted: (_) => _guardar(),
            decoration: const InputDecoration(
              prefixText: '+591  ',
              hintText: '71234567',
              helperText:
                  'Los 8 dígitos. Si es de otro país, escribilo completo con el código.',
              helperMaxLines: 2,
            ),
          ),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: _guardando ? null : _guardar,
            child: const Text('Guardar'),
          ),
          const SizedBox(height: 8),
          if (widget.obliga)
            const Text('Sin tu número no vas a poder seguir usando la app.',
                textAlign: TextAlign.center,
                style: TextStyle(color: VenueColors.aviso))
          else
            TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Ahora no')),
        ],
      ),
    );
  }
}
