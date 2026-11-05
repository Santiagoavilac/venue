import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/networking/supabase.dart';
import '../../core/theme/aftr_theme.dart';
import '../../core/widgets/avatar.dart';
import '../../core/widgets/movimiento.dart';
import '../../data/rachas.dart';

/// La racha al lado de la foto de perfil: una llama y el número de semanas.
///
/// Es chica a propósito -vive en la cabecera, pegada al avatar- y se toca para
/// ver la tuya contra la de tu gente.
class LlamaDeRacha extends ConsumerWidget {
  const LlamaDeRacha({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (ref.watch(usuarioIdProvider) == null) return const SizedBox.shrink();
    final r = ref.watch(rachasProvider).value;
    // mientras no se sabe no se dibuja nada: la cabecera no tiene que saltar
    if (r == null) return const SizedBox.shrink();
    final viva = r.mia.viva;
    final n = viva ? r.mia.semanas : r.mia.mejor;
    return Presionable(
      onTap: () => hojaDeRachas(context),
      child: Container(
        margin: const EdgeInsets.only(right: 10),
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
        decoration: BoxDecoration(
          color: viva ? Aftr.acento.withValues(alpha: 0.16) : Aftr.superficie2,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: viva ? Aftr.acento.withValues(alpha: 0.5) : Aftr.borde,
          ),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(
            viva ? Icons.local_fire_department_rounded : Icons.local_fire_department_outlined,
            size: 15,
            color: viva ? Aftr.acento : Aftr.texto3,
          ),
          const SizedBox(width: 4),
          Text(
            '$n',
            style: Aftr.cuerpo(13, c: viva ? Aftr.acento : Aftr.texto3, w: FontWeight.w700),
          ),
        ]),
      ),
    );
  }
}

Future<void> hojaDeRachas(BuildContext context) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  backgroundColor: Aftr.superficie,
  showDragHandle: true,
  builder: (_) => const HojaDeRachas(),
);

class HojaDeRachas extends ConsumerWidget {
  const HojaDeRachas({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(rachasProvider);
    final r = async.value;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(22, 4, 22, 26),
        child: async.isLoading && r == null
            ? const SizedBox(
                height: 180,
                child: Center(child: CircularProgressIndicator(color: Aftr.acento)),
              )
            : r == null
            ? SizedBox(
                height: 180,
                child: Center(
                  child: Text(mensajeDeError(async.error!), style: Aftr.cuerpo(14)),
                ),
              )
            : SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Rachas', style: Aftr.titular(32)),
                    const SizedBox(height: 6),
                    Text(
                      'Semanas seguidas saliendo. Cuenta la semana en la que entrás '
                      'a un evento, no la que comprás la entrada.',
                      style: Aftr.cuerpo(13),
                    ),
                    const SizedBox(height: 20),
                    _Fila(r.mia, yo: true),
                    if (r.gente.isNotEmpty) ...[
                      const SizedBox(height: 18),
                      Text(
                        r.porDelante == 0
                            ? 'Nadie de tu gente te pasa'
                            : r.porDelante == 1
                            ? 'Una persona de tu gente te pasa'
                            : '${r.porDelante} de tu gente te pasan',
                        style: Aftr.fuerte(16),
                      ),
                      const SizedBox(height: 10),
                      for (final g in r.gente.take(15)) _Fila(g),
                    ] else ...[
                      const SizedBox(height: 18),
                      Text(
                        'Todavía no tenés con quién compararte. Tu gente son las '
                        'personas con las que compartiste una mesa o te pasaste una '
                        'entrada: cuando eso pase, aparecen acá.',
                        style: Aftr.cuerpo(13),
                      ),
                    ],
                    if (r.mia.viva && !r.mia.cerrada) ...[
                      const SizedBox(height: 18),
                      Text(
                        'Esta semana todavía no saliste: tenés hasta el domingo para '
                        'no perder la racha.',
                        style: Aftr.cuerpo(13, c: Aftr.acento),
                      ),
                    ],
                  ],
                ),
              ),
      ),
    );
  }
}

class _Fila extends StatelessWidget {
  const _Fila(this.r, {this.yo = false});
  final Racha r;
  final bool yo;

  @override
  Widget build(BuildContext context) {
    final viva = r.viva;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(children: [
        AvatarRemoto(nombre: r.nombre, foto: r.foto, clave: r.fotoKey, radio: yo ? 24 : 18),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(yo ? 'Vos' : r.nombre, style: Aftr.fuerte(yo ? 18 : 15)),
            Text(
              viva
                  ? (r.mejor > r.semanas ? 'Su mejor fue ${r.mejor}' : 'Es su mejor racha')
                  : r.mejor > 0
                  ? 'Cortada · su mejor fue ${r.mejor}'
                  : 'Todavía sin racha',
              style: Aftr.cuerpo(12, c: Aftr.texto3),
            ),
          ]),
        ),
        Icon(
          viva ? Icons.local_fire_department_rounded : Icons.local_fire_department_outlined,
          size: yo ? 22 : 18,
          color: viva ? Aftr.acento : Aftr.texto3,
        ),
        const SizedBox(width: 4),
        Text(
          '${viva ? r.semanas : r.mejor}',
          style: Aftr.fuerte(yo ? 22 : 18, c: viva ? Aftr.acento : Aftr.texto3),
        ),
      ]),
    );
  }
}
