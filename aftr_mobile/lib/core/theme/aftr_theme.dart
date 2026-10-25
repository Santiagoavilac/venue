import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// AFTR es siempre oscura: no hay tema claro ni se sigue al sistema.
abstract final class Aftr {
  static const fondo = Color(0xFF000000);
  static const superficie = Color(0xFF0E0E10);
  static const superficie2 = Color(0xFF1A1A1D);
  static const superficie3 = Color(0xFF26262A);
  static const borde = Color(0x14FFFFFF);
  static const bordeFuerte = Color(0x29FFFFFF);
  static const texto = Color(0xFFFFFFFF);
  static const texto2 = Color(0xFFA1A1AA);
  static const texto3 = Color(0xFF6B6B73);

  /// El único color: un dorado de luz de pista, para lo que está pasando ya.
  static const acento = Color(0xFFE8C26A);
  static const vivo = Color(0xFF34D399);
  static const alerta = Color(0xFFF87171);

  static const radio = 20.0;
  static const radioChico = 12.0;

  /// La del logo: serif de alto contraste. Bodoni 72 viene con iOS, no hay
  /// que empaquetarla.
  static const serif = 'Bodoni 72';
  static const sans = 'Inter';

  static const curva = Curves.easeOutCubic;
  static const rapido = Duration(milliseconds: 180);
  static const medio = Duration(milliseconds: 320);
  static const lento = Duration(milliseconds: 560);

  static TextStyle titular(double t, {FontWeight w = FontWeight.w400, Color c = texto}) =>
      TextStyle(fontFamily: serif, fontSize: t, fontWeight: w, color: c, height: 1.05, letterSpacing: -0.3);

  static TextStyle fuerte(double t, {Color c = texto}) =>
      TextStyle(fontFamily: sans, fontSize: t, fontWeight: FontWeight.w800, color: c, height: 1.15, letterSpacing: -0.4);

  static TextStyle cuerpo(double t, {Color c = texto2, FontWeight w = FontWeight.w400}) =>
      TextStyle(fontFamily: sans, fontSize: t, fontWeight: w, color: c, height: 1.35);

  static TextStyle etiqueta({Color c = texto3}) =>
      TextStyle(fontFamily: sans, fontSize: 11, fontWeight: FontWeight.w600, color: c, letterSpacing: 1.6);
}

ThemeData temaAftr() {
  const esquema = ColorScheme.dark(
    surface: Aftr.fondo,
    onSurface: Aftr.texto,
    primary: Aftr.texto,
    onPrimary: Aftr.fondo,
    secondary: Aftr.acento,
    onSecondary: Aftr.fondo,
    error: Aftr.alerta,
    outline: Aftr.borde,
  );
  final base = ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    colorScheme: esquema,
    scaffoldBackgroundColor: Aftr.fondo,
    fontFamily: Aftr.sans,
    splashFactory: NoSplash.splashFactory,
    highlightColor: Colors.transparent,
  );
  return base.copyWith(
    appBarTheme: const AppBarTheme(
      backgroundColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      systemOverlayStyle: SystemUiOverlayStyle.light,
    ),
    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: Aftr.superficie,
      surfaceTintColor: Colors.transparent,
      showDragHandle: false,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: Aftr.superficie3,
      contentTextStyle: Aftr.cuerpo(14, c: Aftr.texto),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: Aftr.superficie2,
      hintStyle: Aftr.cuerpo(16, c: Aftr.texto3),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
      contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
    ),
  );
}
