import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/aftr_theme.dart';
import '../../core/networking/supabase.dart';
import '../../core/widgets/piezas.dart';
import '../../data/social_repo.dart';

/// Las cuentas que bloqueaste, para poder desbloquearlas.
///
/// La App Store exige poder bloquear a alguien en apps con contenido de
/// usuarios (Guideline 1.2); si se puede bloquear, también tiene que haber
/// una forma visible de revertirlo.
final bloqueadosProvider = FutureProvider.autoDispose<List<DatosSocial>>((
  ref,
) async {
  final r = await ref.read(socialRepoProvider).historias('bloqueados');
  return listaSocial(r['bloqueados']);
});

class BloqueadosScreen extends ConsumerWidget {
  const BloqueadosScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final lista = ref.watch(bloqueadosProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Cuentas bloqueadas')),
      body: lista.when(
        loading: () => const Center(child: CircularProgressIndicator(color: Aftr.acento)),
        error: (e, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(30),
            child: Text(mensajeDeError(e), textAlign: TextAlign.center),
          ),
        ),
        data: (gente) => gente.isEmpty
            ? const Center(
                child: Padding(
                  padding: EdgeInsets.all(30),
                  child: Text(
                    'No bloqueaste a nadie.\n\nSi bloqueás a alguien desde una historia,\nva a aparecer acá para poder deshacerlo.',
                    textAlign: TextAlign.center,
                  ),
                ),
              )
            : ListView.separated(
                itemCount: gente.length,
                separatorBuilder: (_, _) => const Divider(height: 1),
                itemBuilder: (_, i) {
                  final p = gente[i];
                  final nombre = (p['nombre'] as String?)?.trim();
                  return ListTile(
                    leading: const CircleAvatar(child: Icon(Icons.block_outlined, size: 20)),
                    title: Text(
                      nombre == null || nombre.isEmpty ? 'Cuenta sin nombre' : nombre,
                    ),
                    trailing: TextButton(
                      onPressed: () async {
                        try {
                          await ref.read(socialRepoProvider).historias('bloquear', {
                            'usuario': p['id'],
                            'on': false,
                          });
                          ref.invalidate(bloqueadosProvider);
                          if (context.mounted) avisar(context, 'Desbloqueada.');
                        } catch (e) {
                          if (context.mounted) avisar(context, mensajeDeError(e));
                        }
                      },
                      child: const Text('Desbloquear'),
                    ),
                  );
                },
              ),
      ),
    );
  }
}
