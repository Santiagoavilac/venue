import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'venue_theme.dart';

/// Modo de la app. Se elige en el panel de perfil y queda guardado en el
/// teléfono.
///
/// Arranca en **oscuro**: Venue se usa de noche y adentro de un boliche, y
/// todo lo que no se puede aclarar (el ingreso sobre el video, el velo del
/// tutorial, la foto del evento, el splash) ya es oscuro. Arrancar en claro
/// era lo que hacía ver una pestaña gris clara debajo de un encabezado
/// oscuro. El claro sigue estando para quien lo prefiera.
enum Apariencia {
  oscura('Oscuro'),
  clara('Claro');

  const Apariencia(this.etiqueta);
  final String etiqueta;

  static Apariencia desde(String? s) =>
      values.where((a) => a.name == s).firstOrNull ?? Apariencia.oscura;

  Paleta get paleta => this == Apariencia.clara ? Paleta.clara : Paleta.oscura;
}

const _clave = 'venue.apariencia';

/// Lo guardado, leído en main() antes de dibujar (así no parpadea al abrir).
Future<Apariencia> aparienciaGuardada() async {
  try {
    return Apariencia.desde((await SharedPreferences.getInstance()).getString(_clave));
  } catch (_) {
    return Apariencia.oscura;
  }
}

final aparienciaInicialProvider = Provider<Apariencia>((_) => Apariencia.oscura);

class AparienciaNotifier extends Notifier<Apariencia> {
  @override
  Apariencia build() => ref.read(aparienciaInicialProvider);

  Future<void> elegir(Apariencia a) async {
    state = a;
    try {
      await (await SharedPreferences.getInstance()).setString(_clave, a.name);
    } catch (_) {
      // si no se pudo guardar, vale igual para esta sesión
    }
  }
}

final aparienciaProvider =
    NotifierProvider<AparienciaNotifier, Apariencia>(AparienciaNotifier.new);
