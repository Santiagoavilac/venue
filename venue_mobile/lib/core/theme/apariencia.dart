import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'venue_theme.dart';

/// Modo de la app. Se elige en el panel de perfil y queda guardado en el
/// teléfono. Arranca en claro; el oscuro queda para quien lo prefiera de noche.
enum Apariencia {
  oscura('Oscuro'),
  clara('Claro');

  const Apariencia(this.etiqueta);
  final String etiqueta;

  static Apariencia desde(String? s) =>
      values.where((a) => a.name == s).firstOrNull ?? Apariencia.clara;

  Paleta get paleta => this == Apariencia.clara ? Paleta.clara : Paleta.oscura;
}

const _clave = 'venue.apariencia';

/// Lo guardado, leído en main() antes de dibujar (así no parpadea al abrir).
Future<Apariencia> aparienciaGuardada() async {
  try {
    return Apariencia.desde((await SharedPreferences.getInstance()).getString(_clave));
  } catch (_) {
    return Apariencia.clara;
  }
}

final aparienciaInicialProvider = Provider<Apariencia>((_) => Apariencia.clara);

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
