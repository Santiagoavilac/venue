import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/venue_theme.dart';
import '../../../core/widgets/patron.dart';
import '../data/gestion.dart';

/// Tarjeta grande del evento de trabajo: la foto con el estado, el nombre y
/// el horario; abajo los cuatro números, "Gestionar evento" y los atajos de
/// la noche.
class HeroEvento extends StatelessWidget {
  const HeroEvento({
    super.key,
    required this.eventoId,
    required this.nombre,
    required this.detalle,
    this.imagen,
    this.estado,
    this.menu,
    this.principal,
    this.gestionar,
    this.atajos = const [],
  });

  final String eventoId;
  final String nombre;
  final String detalle;
  final String? imagen;

  /// Texto y color de la etiqueta (null: el de la marca).
  final (String, Color?)? estado;
  final Widget? menu;
  final Widget? principal;
  final VoidCallback? gestionar;

  /// (ícono, texto, al tocar): los botones chicos de abajo.
  final List<(IconData, String, VoidCallback)> atajos;

  @override
  Widget build(BuildContext context) {
    final marca = Theme.of(context).colorScheme.primary;
    final conImagen = imagen != null && imagen!.isNotEmpty;
    final ce = estado?.$2 ?? marca;
    final fondo = DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color.lerp(marca, Oscuro.fondo, .35)!,
            Color.lerp(marca, Oscuro.fondo, .8)!,
          ],
        ),
      ),
    );
    final etiqueta = estado == null
        ? null
        : estado!.$1.isEmpty
        ? ''
        : estado!.$1[0].toUpperCase() + estado!.$1.substring(1);

    final portada = ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: SizedBox(
        height: conImagen ? 200 : 170,
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (conImagen)
              Image.network(
                imagen!,
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => fondo,
              )
            else
              fondo,
            // velo para que el texto se lea sobre cualquier foto
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Oscuro.fondo.withValues(alpha: .15),
                    Oscuro.fondo.withValues(alpha: .35),
                    Oscuro.fondo.withValues(alpha: .80),
                  ],
                  stops: const [0, .45, 1],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 10, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      if (etiqueta != null)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 5,
                          ),
                          decoration: BoxDecoration(
                            color: Color.lerp(ce, Colors.white, .80),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Container(
                                width: 8,
                                height: 8,
                                decoration: BoxDecoration(
                                  color: ce,
                                  shape: BoxShape.circle,
                                ),
                              ),
                              const SizedBox(width: 6),
                              Text(
                                etiqueta,
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  color: Color.lerp(ce, Colors.black, .45),
                                ),
                              ),
                            ],
                          ),
                        ),
                      const Spacer(),
                      if (menu != null)
                        Container(
                          decoration: BoxDecoration(
                            color: Oscuro.fondo.withValues(alpha: .35),
                            shape: BoxShape.circle,
                          ),
                          child: IconTheme(
                            data: const IconThemeData(color: Oscuro.texto),
                            child: menu!,
                          ),
                        ),
                    ],
                  ),
                  const Spacer(),
                  Text(
                    nombre,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 28,
                      height: 1.08,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.4,
                      color: Oscuro.texto,
                      shadows: [
                        Shadow(
                          color: Oscuro.fondo.withValues(alpha: .5),
                          blurRadius: 12,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    detalle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 14,
                      color: Oscuro.texto.withValues(alpha: .88),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );

    final botonGestionar = gestionar == null
        ? null
        : (principal != null ? FilledButton.tonal : FilledButton.new)(
            onPressed: gestionar,
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(52),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
              textStyle: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
            child: const Row(
              children: [
                SizedBox(width: 22),
                Expanded(
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.settings_rounded, size: 22),
                      SizedBox(width: 10),
                      Text('Gestionar evento'),
                    ],
                  ),
                ),
                Icon(Icons.chevron_right_rounded, size: 22),
              ],
            ),
          );

    return Tarjeta(
      padding: const EdgeInsets.all(10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          portada,
          const SizedBox(height: 10),
          NumerosEvento(eventoId: eventoId),
          if (principal != null) ...[const SizedBox(height: 10), principal!],
          if (botonGestionar != null) ...[
            const SizedBox(height: 10),
            botonGestionar,
          ],
          if (atajos.isNotEmpty) ...[
            const SizedBox(height: 10),
            Row(
              children: [
                for (final (k, (icono, texto, f)) in atajos.indexed) ...[
                  if (k > 0) const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton(
                      onPressed: f,
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size.fromHeight(46),
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        foregroundColor: VenueColors.texto,
                        backgroundColor: VenueColors.superficie2,
                        side: BorderSide(color: VenueColors.linea),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(icono, size: 20),
                            const SizedBox(width: 8),
                            Text(
                              texto,
                              style: const TextStyle(
                                fontSize: 14.5,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ],
        ],
      ),
    );
  }
}

/// Cómo va la noche: cuánta gente hay adentro, cuántos de los anotados
/// llegaron, cuántas entradas se usaron y cuántas mesas se vendieron.
class NumerosEvento extends ConsumerWidget {
  const NumerosEvento({super.key, required this.eventoId});
  final String eventoId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final n = ref.watch(numerosEventoProvider(eventoId)).value;
    String v(int? x) => x == null ? '…' : '$x';
    // de a pares: cuántos de los anotados llegaron, cuántas de las entradas
    // vendidas se usaron. Un contador suelto no dice cómo va la noche.
    return FilaFichas(
      children: [
        TarjetaCifra(
          icono: Icons.how_to_reg_outlined,
          etiqueta: 'Adentro',
          valor: n == null ? '…' : '${adentroDe(n)}',
          tono: Tono.ok,
        ),
        TarjetaCifra(
          icono: Icons.groups_outlined,
          etiqueta: 'De lista',
          valor: v(n?.ingresaron),
          de: v(n?.anotados),
        ),
        TarjetaCifra(
          icono: Icons.qr_code_2_rounded,
          etiqueta: 'Entradas',
          valor: v(n?.qrUsados),
          de: v(n?.entradas),
        ),
        TarjetaCifra(
          icono: Icons.table_bar_outlined,
          etiqueta: 'Mesas',
          valor: v(n?.mesas),
        ),
      ],
    );
  }
}
