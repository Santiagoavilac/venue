import 'package:flutter/material.dart';

import 'venue_theme.dart';

/// Tokens de tipografía y espaciado.
///
/// Antes de esto había 385 `fontSize` literales con 28 valores distintos, 493
/// `EdgeInsets` sueltos y 17 radios. Eso es lo que hace que la app se vea
/// improvisada: dos pantallas que muestran lo mismo lo muestran distinto.
///
/// La regla: ningún texto, espacio ni radio nuevo se escribe a mano. Las
/// pantallas se van pasando a estos tokens a medida que se tocan.

/// Escala de espaciado de 4 en 4. Los nombres son de tamaño, no de uso, para
/// que no haya que inventar uno nuevo cada vez.
abstract final class Esp {
  /// 4 — separación mínima, entre un ícono y su texto.
  static const xs = 4.0;

  /// 8 — dentro de un mismo bloque.
  static const sm = 8.0;

  /// 12 — entre elementos de una lista.
  static const md = 12.0;

  /// 16 — margen lateral estándar de pantalla.
  static const lg = 16.0;

  /// 24 — entre bloques distintos.
  static const xl = 24.0;

  /// 32 — antes de un título de sección.
  static const xxl = 32.0;

  /// Margen lateral de las pantallas.
  static const EdgeInsets pantalla = EdgeInsets.symmetric(horizontal: lg);

  /// Relleno interno de una tarjeta.
  static const EdgeInsets tarjeta = EdgeInsets.all(lg);
}

/// Radios de las esquinas. Se llama Redondeo y no Radio porque Flutter ya
/// tiene un Radio (el botón de opción) y dos nombres iguales se confunden.
/// `radioTarjeta` ya existía en venue_theme y se respeta.
abstract final class Redondeo {
  /// 10 — chips y botones chicos.
  static const chico = 10.0;

  /// 14 — campos y botones.
  static const medio = 14.0;

  /// 18 — tarjetas. Es el `radioTarjeta` de siempre.
  static const tarjeta = radioTarjeta;

  /// 999 — píldoras y badges.
  static const pildora = 999.0;
}

/// Roles tipográficos, no tamaños sueltos.
///
/// El informe de diseño pide que el 100 % del texto use un rol documentado.
/// Cada rol dice para qué sirve, así no hace falta decidir un tamaño.
abstract final class Tipo {
  /// 30/w800 — el saludo y poco más. Uno por pantalla como mucho.
  static TextStyle get display =>
      const TextStyle(fontSize: 30, fontWeight: FontWeight.w800, height: 1.2);

  /// 22/w700 — título de pantalla.
  static TextStyle get titulo =>
      const TextStyle(fontSize: 22, fontWeight: FontWeight.w700, height: 1.25);

  /// 18/w700 — título de bloque dentro de una pantalla.
  static TextStyle get bloque =>
      const TextStyle(fontSize: 18, fontWeight: FontWeight.w700, height: 1.3);

  /// 16/w600 — título de una fila o tarjeta.
  static TextStyle get fila =>
      const TextStyle(fontSize: 16, fontWeight: FontWeight.w600, height: 1.35);

  /// 15/w400 — texto corrido. Interlineado 1.5 como pide el informe.
  static TextStyle get cuerpo =>
      const TextStyle(fontSize: 15, fontWeight: FontWeight.w400, height: 1.5);

  /// 13/w500 — apoyo debajo de un título, en gris.
  static TextStyle get apoyo => TextStyle(
    fontSize: 13,
    fontWeight: FontWeight.w500,
    height: 1.4,
    color: VenueColors.textoSuave,
  );

  /// 12/w700 en mayúsculas — etiqueta de sección.
  static TextStyle get etiqueta => TextStyle(
    fontSize: 12,
    fontWeight: FontWeight.w700,
    letterSpacing: .6,
    color: VenueColors.textoTenue,
  );

  /// 28/w800 — una cifra que es el dato principal de su tarjeta.
  static TextStyle get cifra =>
      const TextStyle(fontSize: 28, fontWeight: FontWeight.w800, height: 1.1);

  /// 20/w700 — una cifra secundaria.
  static TextStyle get cifraChica =>
      const TextStyle(fontSize: 20, fontWeight: FontWeight.w700, height: 1.15);
}

/// Duraciones de animación.
///
/// El informe recomienda entre 150 y 250 ms para cambios chicos, y advierte
/// que nunca hay que hacer esperar a quien está en la puerta.
abstract final class Mov {
  /// 120 ms — respuesta a un toque.
  static const toque = Duration(milliseconds: 120);

  /// 200 ms — aparecer, desplazarse, cambiar de estado.
  static const normal = Duration(milliseconds: 200);

  /// 320 ms — entrar a una pantalla.
  static const pantalla = Duration(milliseconds: 320);
}

/// Tamaño mínimo de cualquier cosa que se toque.
///
/// Apple pide 44 pt y Android 48 dp; 48 cubre a los dos.
const double tocable = 48.0;
