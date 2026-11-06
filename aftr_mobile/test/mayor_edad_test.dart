import 'package:aftr_mobile/core/widgets/piezas.dart';
import 'package:aftr_mobile/features/auth/bienvenida_screen.dart';
import 'package:aftr_mobile/features/auth/casilla_mayor_edad.dart';
import 'package:aftr_mobile/features/auth/ingreso.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

// Qué se rompía: el 18+ y los términos sólo se pedían al comprar sin cuenta.
// Quien abría cuenta con Google o Apple no declaraba nada, y es la mitad que
// además usa PULSE, mesas y reventa. La casilla es una sola pieza para las dos
// puertas, así que las dos dicen exactamente lo mismo; esto es de que lo diga,
// y de que no se pueda seguir sin marcarla.
void main() {
  Future<bool?> casilla(WidgetTester t, {bool valor = false}) async {
    bool? ultimo;
    await t.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CasillaMayorEdad(valor: valor, alCambiar: (v) => ultimo = v),
        ),
      ),
    );
    return ultimo;
  }

  testWidgets('dice los 18 y los términos, en una sola casilla', (t) async {
    await casilla(t);
    expect(find.textContaining('mayor de 18 años'), findsOneWidget);
    expect(find.textContaining('términos y condiciones'), findsOneWidget);
    expect(find.byType(Checkbox), findsOneWidget);
  });

  testWidgets('tocar el texto la marca, no hace falta pegarle al cuadrito', (t) async {
    bool? ultimo;
    await t.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CasillaMayorEdad(valor: false, alCambiar: (v) => ultimo = v),
        ),
      ),
    );
    await t.tap(find.textContaining('mayor de 18 años'));
    expect(ultimo, isTrue);
  });

  testWidgets('desactivada no se puede marcar', (t) async {
    bool? ultimo;
    await t.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CasillaMayorEdad(
            valor: false,
            activa: false,
            alCambiar: (v) => ultimo = v,
          ),
        ),
      ),
    );
    await t.tap(find.byType(Checkbox), warnIfMissed: false);
    expect(ultimo, isNull);
  });

  test('el aviso de que falta marcarla es uno solo', () {
    expect(CasillaMayorEdad.falta, contains('mayor de 18'));
    expect(CasillaMayorEdad.falta, contains('términos'));
  });

  puerta();
}

/* Y la puerta: sin marcarla, "Empezar" no se puede tocar. */
class _IngresoSinNada extends Ingreso {
  _IngresoSinNada(this.cliente) : super(cliente);
  // Un cliente de verdad porque Ingreso lo pide, pero sin refresco
  // automático: ese temporizador queda colgado y hace fallar la prueba.
  final SupabaseClient cliente;
  @override
  String? nombreSugerido() => 'Ana Pérez';
}

void puerta() {
  testWidgets('abrir cuenta: no se puede empezar sin marcar la casilla', (t) async {
    final ingreso = _IngresoSinNada(SupabaseClient(
      'https://p.supabase.co',
      'x',
      authOptions: const AuthClientOptions(autoRefreshToken: false),
    ));
    await t.pumpWidget(
      ProviderScope(
        overrides: [ingresoProvider.overrideWith((ref) => ingreso)],
        child: const MaterialApp(home: BienvenidaScreen()),
      ),
    );
    await t.pumpAndSettle();

    // Paso 1: el nombre ya viene del proveedor, así que se puede seguir.
    await t.tap(find.text('Siguiente'));
    await t.pumpAndSettle();

    // Paso 2: el @usuario también viene sugerido y aun así no alcanza.
    expect(find.textContaining('mayor de 18 años'), findsOneWidget);
    BotonAftr boton() => t.widget<BotonAftr>(find.widgetWithText(BotonAftr, 'Empezar'));
    expect(boton().onTap, isNull, reason: 'se podía crear la cuenta sin declarar los 18+');

    await t.tap(find.textContaining('mayor de 18 años'));
    await t.pumpAndSettle();
    expect(boton().onTap, isNotNull);
  });
}
