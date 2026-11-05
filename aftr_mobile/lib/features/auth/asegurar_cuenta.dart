import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/networking/supabase.dart';
import '../../data/aftr_repo.dart';

/// Cuenta de verdad: Google o Apple.
///
/// Es lo que pide PULSE, las mesas, las historias, la reventa y las rachas:
/// guardan plata o se comparten con otra gente, y una sesión anónima se pierde
/// con el teléfono. Para comprar una entrada no hace falta: ver
/// [asegurarParaComprar].
Future<bool> asegurarCuenta(BuildContext context, WidgetRef ref) async {
  if (!ref.read(conCuentaProvider)) {
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

/// Para comprar no se pide cuenta: se piden los datos de la entrada una sola
/// vez -nombre, apellido, correo, carnet, 18+ y términos- y con eso alcanza.
/// Quien ya tiene cuenta no ve nada de esto.
Future<bool> asegurarParaComprar(BuildContext context, WidgetRef ref) async {
  final perfil = await ref.read(perfilProvider.future);
  if (perfil != null) return true;
  if (!context.mounted) return false;
  // el formulario crea la sesión anónima y guarda el perfil; si la persona
  // prefiere entrar con su cuenta, devuelve false y se abre el ingreso
  final listo = await context.push<bool>('/datos-de-compra');
  if (listo == true) return true;
  if (!context.mounted) return false;
  return asegurarCuenta(context, ref);
}
