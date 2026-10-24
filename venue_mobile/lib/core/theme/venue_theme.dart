import 'package:flutter/material.dart';

/// Paleta de un modo (oscuro o claro). Los de estado son fijos por modo y no
/// dependen de la marca del boliche: en la puerta el verde y el rojo tienen
/// que significar siempre lo mismo.
class Paleta {
  const Paleta({
    required this.brillo, required this.fondo, required this.superficie,
    required this.superficie2, required this.superficieAlta, required this.lateral,
    required this.linea, required this.lineaSuave, required this.texto,
    required this.textoSuave, required this.textoTenue, required this.ok,
    required this.aviso, required this.mal, required this.neutro, required this.info,
  });
  final Brightness brillo;
  final Color fondo, superficie, superficie2, superficieAlta, lateral, linea, lineaSuave;
  final Color texto, textoSuave, textoTenue, ok, aviso, mal, neutro, info;

  static const oscura = Paleta(
    brillo: Brightness.dark,
    fondo: Color(0xFF0B0B0D),
    superficie: Color(0xFF141416),
    superficie2: Color(0xFF1B1B1E),
    superficieAlta: Color(0xFF242428),
    lateral: Color(0xFF0F0F11),
    linea: Color(0x17FFFFFF),
    lineaSuave: Color(0x0FFFFFFF),
    texto: Color(0xFFF4F4F5),
    textoSuave: Color(0xFFA1A1AA),
    textoTenue: Color(0xFF71717A),
    ok: Color(0xFF34C77B),
    aviso: Color(0xFFF5A524),
    mal: Color(0xFFF25C5C),
    neutro: Color(0xFF7C8598),
    info: Color(0xFF5AA9FF),
  );

  /// Claro, como Fourvenues: fondo gris muy suave y tarjetas blancas sin
  /// sombra; la jerarquía la da la tipografía, no la decoración.
  static const clara = Paleta(
    brillo: Brightness.light,
    fondo: Color(0xFFF5F6FA),
    superficie: Color(0xFFFFFFFF),
    superficie2: Color(0xFFF2F4F7),
    superficieAlta: Color(0xFFE4E7EC),
    lateral: Color(0xFFFFFFFF),
    linea: Color(0x14101828),
    lineaSuave: Color(0x0D101828),
    texto: Color(0xFF101828),
    textoSuave: Color(0xFF667085),
    textoTenue: Color(0xFF98A2B3),
    ok: Color(0xFF12B76A),
    aviso: Color(0xFFF79009),
    mal: Color(0xFFF04438),
    neutro: Color(0xFF667085),
    info: Color(0xFF2E90FA),
  );
}

/// Sombra suave de las tarjetas en modo claro (en oscuro van con borde).
List<BoxShadow> get sombraTarjeta => VenueColors.paleta.brillo == Brightness.light
    ? const [BoxShadow(color: Color(0x0F101828), blurRadius: 16, offset: Offset(0, 4))]
    : const [];

/// Borde de las tarjetas: solo en oscuro, donde la sombra no se ve.
BoxBorder? get bordeTarjeta =>
    VenueColors.paleta.brillo == Brightness.dark ? Border.all(color: VenueColors.lineaSuave) : null;

/// Radio de tarjetas: generoso, como las apps de referencia.
const radioTarjeta = 18.0;

/// Para tarjetas tocables hechas con Material: misma forma que [Tarjeta].
ShapeBorder get formaTarjeta => RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(radioTarjeta),
      side: VenueColors.paleta.brillo == Brightness.dark
          ? BorderSide(color: VenueColors.lineaSuave)
          : BorderSide.none,
    );

double get elevacionTarjeta => VenueColors.paleta.brillo == Brightness.light ? 1.5 : 0;

/// Colores de la app. Leen la paleta del modo activo: al cambiar de modo la
/// app se vuelve a montar entera (ver VenueApp), así nada queda con el viejo.
class VenueColors {
  static Paleta paleta = Paleta.oscura;

  static Color get fondo => paleta.fondo;
  static Color get superficie => paleta.superficie;
  static Color get superficie2 => paleta.superficie2;
  static Color get superficieAlta => paleta.superficieAlta;
  static Color get lateral => paleta.lateral;
  static Color get linea => paleta.linea;
  static Color get lineaSuave => paleta.lineaSuave;
  static Color get texto => paleta.texto;
  static Color get textoSuave => paleta.textoSuave;
  static Color get textoTenue => paleta.textoTenue;

  static Color get ok => paleta.ok;
  static Color get aviso => paleta.aviso;
  static Color get mal => paleta.mal;
  static Color get neutro => paleta.neutro;
  static Color get info => paleta.info;

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

/// Tema de la app con el acento del boliche activo, en el modo de [paleta].
///
/// Criterio (Fourvenues, iOS 2026): superficies planas sin brillos ni
/// degradés, bordes de un pelo, el color de marca solo en lo accionable y
/// los colores de estado solo para estados. Menos ruido = se lee más rápido
/// en la puerta, con poca luz y apuro.
ThemeData temaVenue({Color? primario, Color? secundario, Paleta paleta = Paleta.oscura}) {
  VenueColors.paleta = paleta;
  final p = paleta;
  final oscuro = p.brillo == Brightness.dark;
  final marca = primario ?? VenueColors.marcaPorDefecto;
  final esquema = ColorScheme.fromSeed(seedColor: marca, brightness: p.brillo).copyWith(
    primary: marca,
    secondary: secundario ?? marca,
    surface: p.superficie,
    surfaceContainerLowest: p.fondo,
    surfaceContainerLow: p.superficie,
    surfaceContainer: p.superficie,
    surfaceContainerHigh: p.superficie2,
    surfaceContainerHighest: p.superficieAlta,
    error: p.mal,
    onSurface: p.texto,
    onSurfaceVariant: p.textoSuave,
    outline: p.linea,
    outlineVariant: p.lineaSuave,
  );
  // El texto sobre el color de marca tiene que leerse sea cual sea el color
  // que eligió el boliche.
  final sobreMarca =
      ThemeData.estimateBrightnessForColor(marca) == Brightness.dark ? Colors.white : Colors.black;

  const radio = BorderRadius.all(Radius.circular(12));
  const radioTarjetaB = BorderRadius.all(Radius.circular(radioTarjeta));
  final base = ThemeData(brightness: p.brillo, fontFamily: fuenteVenue);
  // en claro las tarjetas blancas se separan del fondo gris solas: sin borde
  final lado = oscuro ? BorderSide(color: p.linea) : BorderSide.none;
  return ThemeData(
    useMaterial3: true,
    brightness: p.brillo,
    fontFamily: fuenteVenue,
    splashFactory: InkSparkle.splashFactory,
    textTheme: base.textTheme.apply(
      fontFamily: fuenteVenue,
      bodyColor: p.texto,
      displayColor: p.texto,
    ),
    colorScheme: esquema.copyWith(onPrimary: sobreMarca),
    scaffoldBackgroundColor: p.fondo,
    canvasColor: p.superficie,
    dividerColor: p.lineaSuave,
    dividerTheme: DividerThemeData(color: p.lineaSuave, space: 1),
    appBarTheme: AppBarTheme(
      backgroundColor: p.fondo,
      foregroundColor: p.texto,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      titleTextStyle: TextStyle(
        fontFamily: fuenteVenue,
        fontSize: 17,
        fontWeight: FontWeight.w600,
        color: p.texto,
      ),
    ),
    cardTheme: CardThemeData(
      color: p.superficie,
      elevation: oscuro ? 0 : 1.5,
      shadowColor: const Color(0x29101828),
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(borderRadius: radioTarjetaB, side: lado),
    ),
    listTileTheme: ListTileThemeData(
      iconColor: p.textoSuave,
      shape: const RoundedRectangleBorder(borderRadius: radio),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: p.superficie,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      labelStyle: TextStyle(color: p.textoSuave),
      hintStyle: TextStyle(color: p.textoTenue),
      prefixIconColor: p.textoTenue,
      border: OutlineInputBorder(borderRadius: radio, borderSide: BorderSide(color: p.linea)),
      enabledBorder:
          OutlineInputBorder(borderRadius: radio, borderSide: BorderSide(color: p.linea)),
      focusedBorder:
          OutlineInputBorder(borderRadius: radio, borderSide: BorderSide(color: marca, width: 1.4)),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: marca,
        foregroundColor: sobreMarca,
        elevation: 0,
        minimumSize: const Size.fromHeight(48),
        shape: const RoundedRectangleBorder(borderRadius: radio),
        textStyle:
            const TextStyle(fontFamily: fuenteVenue, fontSize: 15, fontWeight: FontWeight.w600),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: p.texto,
        backgroundColor: p.superficie,
        minimumSize: const Size.fromHeight(48),
        side: BorderSide(color: p.linea),
        shape: const RoundedRectangleBorder(borderRadius: radio),
        textStyle:
            const TextStyle(fontFamily: fuenteVenue, fontSize: 15, fontWeight: FontWeight.w600),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: p.texto,
        textStyle: const TextStyle(fontFamily: fuenteVenue, fontWeight: FontWeight.w600),
      ),
    ),
    // Subpestañas como el control segmentado de iOS: riel gris y la activa
    // en blanco (o gris alto en oscuro). Sin teñir con la marca.
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: ButtonStyle(
        backgroundColor: WidgetStateProperty.resolveWith((s) =>
            s.contains(WidgetState.selected) ? (oscuro ? p.superficieAlta : p.superficie) : p.superficie2),
        foregroundColor: WidgetStateProperty.resolveWith(
            (s) => s.contains(WidgetState.selected) ? p.texto : p.textoSuave),
        side: WidgetStatePropertyAll(BorderSide(color: p.lineaSuave)),
        shape: const WidgetStatePropertyAll(RoundedRectangleBorder(borderRadius: radio)),
        textStyle: const WidgetStatePropertyAll(
            TextStyle(fontFamily: fuenteVenue, fontWeight: FontWeight.w600, fontSize: 14)),
        minimumSize: const WidgetStatePropertyAll(Size(0, 40)),
      ),
    ),
    tabBarTheme: TabBarThemeData(
      dividerColor: p.lineaSuave,
      indicatorColor: p.texto,
      labelColor: p.texto,
      unselectedLabelColor: p.textoSuave,
      labelStyle: const TextStyle(fontFamily: fuenteVenue, fontWeight: FontWeight.w600, fontSize: 14),
      unselectedLabelStyle:
          const TextStyle(fontFamily: fuenteVenue, fontWeight: FontWeight.w500, fontSize: 14),
    ),
    chipTheme: ChipThemeData(
      backgroundColor: p.superficie,
      selectedColor: Color.alphaBlend(marca.withValues(alpha: .14), p.superficie),
      side: BorderSide(color: p.linea),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(8))),
      labelStyle: TextStyle(fontFamily: fuenteVenue, fontWeight: FontWeight.w500, color: p.texto),
    ),
    // Barra de abajo al estilo iOS: sin píldora, la activa con el color.
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: p.superficie,
      surfaceTintColor: Colors.transparent,
      indicatorColor: Colors.transparent,
      overlayColor: const WidgetStatePropertyAll(Colors.transparent),
      height: 64,
      iconTheme: WidgetStateProperty.resolveWith(
        (s) => IconThemeData(
          size: 24,
          color: s.contains(WidgetState.selected) ? marca : p.textoTenue,
        ),
      ),
      labelTextStyle: WidgetStateProperty.resolveWith(
        (s) => TextStyle(
          fontFamily: fuenteVenue,
          fontSize: 11,
          fontWeight: s.contains(WidgetState.selected) ? FontWeight.w600 : FontWeight.w500,
          color: s.contains(WidgetState.selected) ? marca : p.textoTenue,
        ),
      ),
    ),
    switchTheme: SwitchThemeData(
      trackColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? p.ok : p.superficieAlta),
      thumbColor: const WidgetStatePropertyAll(Colors.white),
      trackOutlineColor: const WidgetStatePropertyAll(Colors.transparent),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: p.superficie,
      surfaceTintColor: Colors.transparent,
      showDragHandle: true,
      dragHandleColor: p.superficieAlta,
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: p.superficie,
      surfaceTintColor: Colors.transparent,
      shape: const RoundedRectangleBorder(borderRadius: radioTarjetaB),
    ),
    popupMenuTheme: PopupMenuThemeData(
      color: p.superficie,
      surfaceTintColor: Colors.transparent,
      elevation: 8,
      shadowColor: Colors.black.withValues(alpha: oscuro ? .5 : .12),
      textStyle: TextStyle(fontFamily: fuenteVenue, fontSize: 15, color: p.texto),
      shape: RoundedRectangleBorder(
          borderRadius: radio, side: BorderSide(color: p.linea)),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: oscuro ? p.superficieAlta : const Color(0xFF1F1F24),
      contentTextStyle:
          const TextStyle(fontFamily: fuenteVenue, color: Colors.white, fontSize: 15),
    ),
  );
}
