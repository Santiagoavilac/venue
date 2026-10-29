import 'package:flutter/material.dart';

import '../../../core/widgets/fondo_video.dart';

/// Piezas del ingreso, que es siempre oscuro sin importar el modo de la app
/// (las mismas medidas que el login de usuario y contraseña).
abstract final class Acceso {
  static const fondo = Color(0xFF16181C), campo = Color(0xFF26292F), suave = Color(0xFF9AA0A9),
      tarjeta = Color(0xFF1C1F24), error = Color(0xFFFF8A80);

  static InputDecoration campoDeco({String? pista, Widget? sufijo}) => InputDecoration(
        filled: true,
        fillColor: campo,
        hintText: pista,
        suffixIcon: sufijo,
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
        focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Colors.white24)),
        hintStyle: const TextStyle(color: Colors.white38),
      );

  static Widget rotulo(String t) => Padding(
        padding: const EdgeInsets.only(bottom: 8, left: 2, top: 14),
        child: Text(t,
            style: const TextStyle(color: suave, fontSize: 11.5, fontWeight: FontWeight.w600, letterSpacing: .6)),
      );

  static Widget titulo(String t, String sub) => Padding(
        padding: const EdgeInsets.only(top: 6, bottom: 16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(t, style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.w700)),
          const SizedBox(height: 6),
          Text(sub, style: const TextStyle(color: suave, fontSize: 14.5, height: 1.35)),
        ]),
      );

  static Widget errorTexto(String? e) => e == null
      ? const SizedBox.shrink()
      : Padding(
          padding: const EdgeInsets.only(top: 14),
          child: Text(e, style: const TextStyle(color: error, height: 1.35)),
        );

  static Widget botonBlanco(String texto, VoidCallback? alTocar, {bool cargando = false}) => FilledButton(
        onPressed: cargando ? null : alTocar,
        style: FilledButton.styleFrom(
          backgroundColor: Colors.white,
          foregroundColor: Colors.black,
          disabledBackgroundColor: Colors.white24,
          disabledForegroundColor: Colors.white54,
          minimumSize: const Size.fromHeight(54),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
        ),
        child: cargando
            ? const SizedBox(
                width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.4, color: Colors.black))
            : Text(texto),
      );

  static Widget botonBorde(Widget icono, String texto, VoidCallback alTocar) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: OutlinedButton(
          onPressed: alTocar,
          style: OutlinedButton.styleFrom(
            foregroundColor: Colors.white,
            minimumSize: const Size.fromHeight(52),
            side: const BorderSide(color: Colors.white24),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
          ),
          child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            icono,
            const SizedBox(width: 10),
            Text(texto),
          ]),
        ),
      );
}

/// Fondo oscuro con el brillo cálido abajo, ancho máximo y zona segura.
class FondoAcceso extends StatelessWidget {
  const FondoAcceso({super.key, required this.child, this.alVolver, this.marca = false});
  final Widget child;
  final VoidCallback? alVolver;
  final bool marca;

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: Acceso.fondo,
        body: FondoVideo(
          'assets/fondos/acceso.mp4',
          child: SafeArea(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 460),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 4, 20, 16),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    SizedBox(
                      height: 48,
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: alVolver != null
                            ? IconButton(
                                tooltip: 'Volver',
                                onPressed: alVolver,
                                padding: EdgeInsets.zero,
                                alignment: Alignment.centerLeft,
                                icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white, size: 20),
                              )
                            : marca
                                ? const Text('VENUE',
                                    style: TextStyle(
                                        color: Colors.white, fontSize: 15, fontWeight: FontWeight.w900, letterSpacing: 5))
                                : null,
                      ),
                    ),
                    Expanded(child: child),
                  ]),
                ),
              ),
            ),
          ),
        ),
      );
}

/// Logo de Google en colores (sin paquete de íconos de marca).
class LogoGoogle extends StatelessWidget {
  const LogoGoogle({super.key});
  @override
  Widget build(BuildContext context) => Container(
        width: 22,
        height: 22,
        alignment: Alignment.center,
        decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
        child: const Text('G',
            style: TextStyle(color: Color(0xFF4285F4), fontWeight: FontWeight.w800, fontSize: 14, height: 1)),
      );
}
