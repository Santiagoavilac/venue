import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/networking/supabase.dart';
import '../../core/theme/aftr_theme.dart';
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
      onTap: () => context.push('/rachas'),
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
