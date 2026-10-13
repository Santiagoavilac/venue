import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../networking/supabase.dart';
import '../theme/venue_theme.dart';

/// Mensaje centrado para pantallas sin datos o con error.
class MensajeVista extends StatelessWidget {
  const MensajeVista({
    super.key,
    required this.icono,
    required this.titulo,
    this.detalle,
    this.accion,
    this.alTocar,
  });

  final IconData icono;
  final String titulo;
  final String? detalle;
  final String? accion;
  final VoidCallback? alTocar;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icono, size: 44, color: VenueColors.textoSuave),
            const SizedBox(height: 16),
            Text(
              titulo,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
            ),
            if (detalle != null) ...[
              const SizedBox(height: 8),
              Text(
                detalle!,
                textAlign: TextAlign.center,
                style: const TextStyle(color: VenueColors.textoSuave, height: 1.4),
              ),
            ],
            if (accion != null && alTocar != null) ...[
              const SizedBox(height: 20),
              OutlinedButton(
                onPressed: alTocar,
                style: OutlinedButton.styleFrom(minimumSize: const Size(180, 48)),
                child: Text(accion!),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Pinta un [AsyncValue] con los tres estados resueltos: cargando, error con
/// "Reintentar" y datos. Evita que cada pantalla invente los suyos.
class VistaAsync<T> extends StatelessWidget {
  const VistaAsync({
    super.key,
    required this.valor,
    required this.datos,
    this.reintentar,
  });

  final AsyncValue<T> valor;
  final Widget Function(T) datos;
  final VoidCallback? reintentar;

  @override
  Widget build(BuildContext context) {
    return valor.when(
      skipLoadingOnRefresh: true,
      data: datos,
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => MensajeVista(
        icono: esFallaDeRed(e) ? Icons.wifi_off_rounded : Icons.error_outline,
        titulo: esFallaDeRed(e) ? 'Sin conexión' : 'No se pudo cargar',
        detalle: mensajeDeError(e),
        accion: reintentar == null ? null : 'Reintentar',
        alTocar: reintentar,
      ),
    );
  }
}
