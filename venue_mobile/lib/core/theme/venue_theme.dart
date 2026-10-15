import 'package:flutter/material.dart';

/// Colores de la app. Son los mismos tokens que la web (styles.css, capa
/// "PATRÓN 2026"): fondo casi negro, superficies en cuatro niveles y bordes
/// finos. Los de estado son fijos y no dependen de la marca del boliche: en
/// la puerta el verde y el rojo tienen que significar siempre lo mismo.
class VenueColors {
  static const fondo = Color(0xFF09090B);
  static const superficie = Color(0xFF111114);
  static const superficie2 = Color(0xFF16161A);
  static const superficieAlta = Color(0xFF1C1C22);
  static const lateral = Color(0xFF0D0D10);
  static const linea = Color(0x1CFFFFFF);
  static const lineaSuave = Color(0x12FFFFFF);
  static const texto = Color(0xFFF5F5F7);
  static const textoSuave = Color(0xFFA8A8B8);
  static const textoTenue = Color(0xFF82829A);

  static const ok = Color(0xFF2ED573);
  static const aviso = Color(0xFFFFB020);
  static const mal = Color(0xFFFF4D5E);
  static const neutro = Color(0xFF7C8598);
  static const info = Color(0xFF5AA9FF);

  static const marcaPorDefecto = Color(0xFF7C3AED);
}

/// Tipografía de toda la app (empaquetada en assets/fonts).
const fuenteVenue = 'Inter';

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
    surfaceContainerLowest: VenueColors.fondo,
    surfaceContainerLow: VenueColors.superficie,
    surfaceContainer: VenueColors.superficie,
    surfaceContainerHigh: VenueColors.superficie2,
    surfaceContainerHighest: VenueColors.superficieAlta,
    error: VenueColors.mal,
    onSurface: VenueColors.texto,
    onSurfaceVariant: VenueColors.textoSuave,
    outline: VenueColors.linea,
    outlineVariant: VenueColors.lineaSuave,
  );
  // El texto sobre el color de marca tiene que leerse sea cual sea el color
  // que eligió el boliche.
  final sobreMarca =
      ThemeData.estimateBrightnessForColor(marca) == Brightness.dark
          ? Colors.white
          : Colors.black;

  const radio = BorderRadius.all(Radius.circular(12));
  const radioTarjeta = BorderRadius.all(Radius.circular(16));
  final base = ThemeData(brightness: Brightness.dark, fontFamily: fuenteVenue);
  return ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    fontFamily: fuenteVenue,
    textTheme: base.textTheme.apply(
      fontFamily: fuenteVenue,
      bodyColor: VenueColors.texto,
      displayColor: VenueColors.texto,
    ),
    colorScheme: esquema.copyWith(onPrimary: sobreMarca),
    scaffoldBackgroundColor: VenueColors.fondo,
    dividerColor: VenueColors.lineaSuave,
    dividerTheme: const DividerThemeData(color: VenueColors.lineaSuave, space: 1),
    appBarTheme: const AppBarTheme(
      backgroundColor: VenueColors.fondo,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      titleTextStyle: TextStyle(
        fontFamily: fuenteVenue,
        fontSize: 19,
        fontWeight: FontWeight.w700,
        color: VenueColors.texto,
      ),
    ),
    cardTheme: const CardThemeData(
      color: VenueColors.superficie,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: radioTarjeta,
        side: BorderSide(color: VenueColors.linea),
      ),
    ),
    listTileTheme: const ListTileThemeData(
      iconColor: VenueColors.textoSuave,
      shape: RoundedRectangleBorder(borderRadius: radio),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: VenueColors.superficie,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      labelStyle: const TextStyle(color: VenueColors.textoSuave),
      hintStyle: const TextStyle(color: VenueColors.textoTenue),
      prefixIconColor: VenueColors.textoTenue,
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
        minimumSize: const Size.fromHeight(52),
        shape: const RoundedRectangleBorder(borderRadius: radio),
        textStyle: const TextStyle(
            fontFamily: fuenteVenue, fontSize: 15.5, fontWeight: FontWeight.w600),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: VenueColors.texto,
        backgroundColor: VenueColors.superficie,
        minimumSize: const Size.fromHeight(52),
        side: const BorderSide(color: VenueColors.linea),
        shape: const RoundedRectangleBorder(borderRadius: radio),
        textStyle: const TextStyle(
            fontFamily: fuenteVenue, fontSize: 15.5, fontWeight: FontWeight.w600),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: VenueColors.texto,
        textStyle: const TextStyle(fontFamily: fuenteVenue, fontWeight: FontWeight.w600),
      ),
    ),
    // Subpestañas: contenedor con borde y la activa teñida con la marca,
    // igual que Usuarios | Teams en la web.
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: ButtonStyle(
        backgroundColor: WidgetStateProperty.resolveWith((s) =>
            s.contains(WidgetState.selected)
                ? Color.alphaBlend(marca.withValues(alpha: .22), VenueColors.superficie)
                : VenueColors.superficie),
        foregroundColor: WidgetStateProperty.resolveWith((s) =>
            s.contains(WidgetState.selected) ? VenueColors.texto : VenueColors.textoSuave),
        side: const WidgetStatePropertyAll(BorderSide(color: VenueColors.linea)),
        shape: const WidgetStatePropertyAll(RoundedRectangleBorder(borderRadius: radio)),
        textStyle: const WidgetStatePropertyAll(
            TextStyle(fontFamily: fuenteVenue, fontWeight: FontWeight.w600, fontSize: 14.5)),
        minimumSize: const WidgetStatePropertyAll(Size(0, 46)),
      ),
    ),
    tabBarTheme: TabBarThemeData(
      dividerColor: VenueColors.lineaSuave,
      indicatorColor: marca,
      labelColor: VenueColors.texto,
      unselectedLabelColor: VenueColors.textoSuave,
      labelStyle: const TextStyle(fontFamily: fuenteVenue, fontWeight: FontWeight.w600, fontSize: 14.5),
      unselectedLabelStyle:
          const TextStyle(fontFamily: fuenteVenue, fontWeight: FontWeight.w500, fontSize: 14.5),
    ),
    chipTheme: ChipThemeData(
      backgroundColor: VenueColors.superficie,
      selectedColor: Color.alphaBlend(marca.withValues(alpha: .22), VenueColors.superficie),
      side: const BorderSide(color: VenueColors.linea),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(10))),
      labelStyle: const TextStyle(fontFamily: fuenteVenue, fontWeight: FontWeight.w500),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: VenueColors.fondo,
      surfaceTintColor: Colors.transparent,
      indicatorColor: marca.withValues(alpha: .20),
      height: 70,
      iconTheme: WidgetStateProperty.resolveWith(
        (s) => IconThemeData(
          size: 23,
          color: s.contains(WidgetState.selected) ? secundario ?? marca : VenueColors.textoTenue,
        ),
      ),
      labelTextStyle: WidgetStateProperty.resolveWith(
        (s) => TextStyle(
          fontFamily: fuenteVenue,
          fontSize: 11.5,
          fontWeight: s.contains(WidgetState.selected) ? FontWeight.w600 : FontWeight.w500,
          color: s.contains(WidgetState.selected)
              ? VenueColors.texto
              : VenueColors.textoTenue,
        ),
      ),
    ),
    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: VenueColors.superficie,
      surfaceTintColor: Colors.transparent,
      showDragHandle: true,
    ),
    dialogTheme: const DialogThemeData(
      backgroundColor: VenueColors.superficie,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: radioTarjeta),
    ),
    snackBarTheme: const SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: VenueColors.superficieAlta,
      contentTextStyle:
          TextStyle(fontFamily: fuenteVenue, color: VenueColors.texto, fontSize: 15),
    ),
  );
}
