import 'package:flutter/material.dart';

/// Colores de estado de la operación. Son fijos en toda la app y no dependen
/// de la marca del boliche: en la puerta el verde y el rojo tienen que
/// significar siempre lo mismo.
class VenueColors {
  static const fondo = Color(0xFF07070A);
  static const superficie = Color(0xFF121218);
  static const superficieAlta = Color(0xFF1B1B24);
  static const linea = Color(0xFF2A2A36);
  static const texto = Color(0xFFF4F4F7);
  static const textoSuave = Color(0xFFA2A2B4);

  static const ok = Color(0xFF1FD286);
  static const aviso = Color(0xFFFFB020);
  static const mal = Color(0xFFFF4D5E);
  static const neutro = Color(0xFF7C8598);

  static const marcaPorDefecto = Color(0xFF7C3AED);
}

/// `#RRGGBB` → Color. Devuelve null si el texto no es un color válido, para
/// que un dato mal cargado en `clubs` no rompa el tema.
Color? colorDesdeHex(String? hex) {
  if (hex == null) return null;
  final h = hex.replaceAll('#', '').trim();
  if (h.length != 6) return null;
  final v = int.tryParse(h, radix: 16);
  return v == null ? null : Color(0xFF000000 | v);
}

/// Tema oscuro con el acento del boliche activo.
ThemeData temaVenue({Color? primario, Color? secundario}) {
  final marca = primario ?? VenueColors.marcaPorDefecto;
  final esquema = ColorScheme.fromSeed(
    seedColor: marca,
    brightness: Brightness.dark,
  ).copyWith(
    primary: marca,
    secondary: secundario ?? marca,
    surface: VenueColors.superficie,
    error: VenueColors.mal,
    onSurface: VenueColors.texto,
    outline: VenueColors.linea,
  );
  // El texto sobre el color de marca tiene que leerse sea cual sea el color
  // que eligió el boliche.
  final sobreMarca =
      ThemeData.estimateBrightnessForColor(marca) == Brightness.dark
          ? Colors.white
          : Colors.black;

  const radio = BorderRadius.all(Radius.circular(14));
  return ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    colorScheme: esquema.copyWith(onPrimary: sobreMarca),
    scaffoldBackgroundColor: VenueColors.fondo,
    dividerColor: VenueColors.linea,
    appBarTheme: const AppBarTheme(
      backgroundColor: VenueColors.fondo,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      centerTitle: false,
      titleTextStyle: TextStyle(
        fontSize: 20,
        fontWeight: FontWeight.w700,
        color: VenueColors.texto,
      ),
    ),
    cardTheme: const CardThemeData(
      color: VenueColors.superficie,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: radio,
        side: BorderSide(color: VenueColors.linea),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: VenueColors.superficieAlta,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      labelStyle: const TextStyle(color: VenueColors.textoSuave),
      border: const OutlineInputBorder(
        borderRadius: radio,
        borderSide: BorderSide(color: VenueColors.linea),
      ),
      enabledBorder: const OutlineInputBorder(
        borderRadius: radio,
        borderSide: BorderSide(color: VenueColors.linea),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: radio,
        borderSide: BorderSide(color: marca, width: 1.6),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: marca,
        foregroundColor: sobreMarca,
        minimumSize: const Size.fromHeight(54),
        shape: const RoundedRectangleBorder(borderRadius: radio),
        textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: VenueColors.texto,
        minimumSize: const Size.fromHeight(54),
        side: const BorderSide(color: VenueColors.linea),
        shape: const RoundedRectangleBorder(borderRadius: radio),
        textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
      ),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: VenueColors.superficie,
      surfaceTintColor: Colors.transparent,
      indicatorColor: marca.withValues(alpha: .22),
      height: 68,
      labelTextStyle: WidgetStateProperty.resolveWith(
        (s) => TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: s.contains(WidgetState.selected)
              ? VenueColors.texto
              : VenueColors.textoSuave,
        ),
      ),
    ),
    snackBarTheme: const SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: VenueColors.superficieAlta,
      contentTextStyle: TextStyle(color: VenueColors.texto, fontSize: 15),
    ),
  );
}
