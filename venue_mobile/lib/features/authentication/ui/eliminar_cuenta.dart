import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/networking/supabase.dart';
import '../../../core/theme/venue_theme.dart';
import '../../../core/widgets/avisos.dart';
import '../data/sesion.dart';

/// Borrado de la propia cuenta. Lo exige la App Store cuando la app permite
/// crear cuentas, y VENUE permite tres altas distintas.
///
/// Si la persona ya trabajó eventos, el boliche conserva el historial para su
/// contabilidad, pero sin nada que la identifique. El acceso se corta siempre.
Future<void> eliminarMiCuenta(BuildContext context, WidgetRef ref) async {
  final seguro = await showDialog<bool>(
    context: context,
    builder: (c) => AlertDialog(
      title: const Text('¿Eliminar tu cuenta?'),
      content: const Text(
        'Se borran tus datos personales y perdés el acceso a los boliches con '
        'los que trabajás. Si ya trabajaste eventos, el boliche conserva esos '
        'registros para su contabilidad, sin tu nombre ni tu foto.\n\n'
        'No se puede deshacer.',
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancelar')),
        TextButton(
          onPressed: () => Navigator.pop(c, true),
          style: TextButton.styleFrom(foregroundColor: VenueColors.mal),
          child: const Text('Eliminar cuenta'),
        ),
      ],
    ),
  );
  if (seguro != true || !context.mounted) return;
  try {
    await ref.read(authRepositoryProvider).eliminarMiCuenta();
    if (context.mounted) avisar(context, 'Tu cuenta se eliminó.');
  } catch (e) {
    if (context.mounted) avisar(context, mensajeDeError(e), tipo: TipoAviso.aviso);
  }
}


/// Páginas públicas y contacto de VENUE. Apple pide que se alcancen desde
/// adentro de la app, no solo desde la ficha de la App Store.
const venuePrivacidad = 'https://www.venuebol.com/privacidad';
const venueNormas = 'https://www.aftrvenue.com/normas';
const venueTerminos = 'https://www.aftrvenue.com/terminos';
const venueSoporte = 'mailto:soporte.aftrvenue@aftrvenue.com';

Future<void> abrirEnlace(String url) =>
    launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
