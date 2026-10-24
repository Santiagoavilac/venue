import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Pedido de ir a una sección del inicio por su título ("Accesos",
/// "Reporte"…). Lo atiende el shell y lo limpia; si el rol no tiene esa
/// sección, no pasa nada.
class SeccionPedida extends Notifier<String?> {
  @override
  String? build() => null;

  void ir(String titulo) => state = titulo;
  void atendida() => state = null;
}

final seccionPedidaProvider = NotifierProvider<SeccionPedida, String?>(SeccionPedida.new);
