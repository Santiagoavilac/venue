import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/networking/supabase.dart';
import '../../data/aftr_repo.dart';

/// Mirar no pide cuenta; comprar, reservar o anotarse sí. Abre el ingreso o la
/// bienvenida si hace falta y devuelve si al final hay perfil.
Future<bool> asegurarCuenta(BuildContext context, WidgetRef ref) async {
  if (ref.read(usuarioIdProvider) == null) {
    final ok = await context.push<bool>('/ingresar');
    if (ok != true) return false;
  }
  var perfil = await ref.read(perfilProvider.future);
  if (perfil == null) {
    if (!context.mounted) return false;
    final ok = await context.push<bool>('/bienvenida');
    if (ok != true) return false;
    perfil = await ref.read(perfilProvider.future);
  }
  return perfil != null;
}
