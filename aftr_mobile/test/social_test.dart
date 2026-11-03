import 'package:aftr_mobile/core/networking/supabase.dart';
import 'package:aftr_mobile/data/modelos.dart';
import 'package:aftr_mobile/data/social_repo.dart';
import 'package:aftr_mobile/features/reventa/reventa.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('una entrada bloqueada nunca muestra el QR previo', () {
    final accesos = Accesos.desde({'entradas':[{'id':'ticket','estado':'bloqueada','qr':'EVT:ev:OLD',
      'evento':{'id':'ev','nombre':'Noche','fecha':'2026-11-02','hora_inicio':'22:00','hora_fin':'04:00','club':{'id':'club','nombre':'Club'}}}]});
    expect(accesos.todos.single.estado,EstadoAcceso.bloqueada);
    expect(accesos.todos.single.tieneQr,isFalse);
    expect(accesos.todos.single.transferible,isFalse);
  });
  test('la cuenta regresiva no reinicia al reabrir una orden', () {
    final local=DateTime.utc(2026,11,1,12);
    final offset=desfaseSocial({'ahora':DateTime.utc(2026,11,1,12,5).toIso8601String()},local);
    expect(tiempoRestante('2026-11-01T12:15:00Z',local.add(offset)),const Duration(minutes:10));
    expect(tiempoRestante('2026-11-01T11:00:00Z',local),Duration.zero);
  });
  testWidgets('la disputa no permite pagar o cancelar y ofrece adjuntar pruebas',(t) async {
    await t.pumpWidget(ProviderScope(overrides:[
      usuarioIdProvider.overrideWithValue('buyer'),
      ordenReventaProvider('order').overrideWith((ref) async => {
        'id':'order','estado':'en_disputa','comprador_id':'buyer','vendedor_id':'seller',
        'evento':'Noche','precio_centavos':5000,'ahora':DateTime.now().toIso8601String(),
        'metodo':<String,dynamic>{},'historial':<Object>[],
      }),
    ],child:const MaterialApp(home:OrdenReventaScreen(id:'order'))));
    await t.pumpAndSettle();
    expect(find.text('En disputa'),findsOneWidget);
    expect(find.text('Ya pagué'),findsNothing);
    expect(find.text('Cancelar operación'),findsNothing);
    expect(find.text('Adjuntar prueba'),findsOneWidget);
  });
  testWidgets('un pago tardío conserva una vía real para abrir disputa',(t) async {
    await t.pumpWidget(ProviderScope(overrides:[
      usuarioIdProvider.overrideWithValue('buyer'),
      ordenReventaProvider('expired').overrideWith((ref) async => {
        'id':'expired','estado':'vencida','comprador_id':'buyer','evento':'Noche',
        'precio_centavos':5000,'historial':<Object>[],
      }),
    ],child:const MaterialApp(home:OrdenReventaScreen(id:'expired'))));
    await t.pumpAndSettle();
    expect(find.text('Pagué fuera de plazo · Abrir disputa'),findsOneWidget);
    expect(find.text('Ya pagué'),findsNothing);
  });
}
