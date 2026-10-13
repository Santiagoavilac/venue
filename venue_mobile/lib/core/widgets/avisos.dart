import 'package:flutter/material.dart';

import '../theme/venue_theme.dart';

enum TipoAviso { ok, aviso }

/// Mensaje breve al pie (el "toast" de la web).
void avisar(BuildContext context, String texto, {TipoAviso tipo = TipoAviso.ok}) {
  final m = ScaffoldMessenger.maybeOf(context);
  if (m == null) return;
  m
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(
      duration: const Duration(milliseconds: 2600),
      content: Row(
        children: [
          Icon(
            tipo == TipoAviso.ok
                ? Icons.check_circle_rounded
                : Icons.warning_amber_rounded,
            color: tipo == TipoAviso.ok ? VenueColors.ok : VenueColors.aviso,
            size: 20,
          ),
          const SizedBox(width: 10),
          Expanded(child: Text(texto)),
        ],
      ),
    ));
}

String horaCorta(DateTime t) =>
    '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

/// Sin tildes y en minúsculas, para buscar "jose" y encontrar "José".
String normalizar(String s) {
  const de = 'áàäâãéèëêíìïîóòöôõúùüûñç';
  const a = 'aaaaaeeeeiiiiooooouuuunc';
  final b = StringBuffer();
  for (final c in s.toLowerCase().split('')) {
    final i = de.indexOf(c);
    b.write(i < 0 ? c : a[i]);
  }
  return b.toString();
}
