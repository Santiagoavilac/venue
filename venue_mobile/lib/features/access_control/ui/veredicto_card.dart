import 'package:flutter/material.dart';

import '../../../core/theme/venue_theme.dart';
import '../../../core/widgets/foto_persona.dart';
import '../data/resultado.dart';

Color colorDeVeredicto(Veredicto v) => switch (v) {
      Veredicto.pasa => VenueColors.ok,
      Veredicto.yaIngreso => VenueColors.aviso,
      Veredicto.sinConexion => VenueColors.neutro,
      Veredicto.credencial => VenueColors.info,
      _ => VenueColors.mal,
    };

IconData iconoDeVeredicto(Veredicto v) => switch (v) {
      Veredicto.pasa => Icons.check_rounded,
      Veredicto.yaIngreso => Icons.warning_amber_rounded,
      Veredicto.sinConexion => Icons.wifi_off_rounded,
      Veredicto.fueraDeHorario => Icons.schedule_rounded,
      Veredicto.eventoIncorrecto => Icons.event_busy_rounded,
      Veredicto.sinPermiso => Icons.lock_outline_rounded,
      Veredicto.noValido => Icons.close_rounded,
      Veredicto.credencial => Icons.badge_outlined,
    };

String _hhmm(DateTime t) =>
    '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

/// Resultado de un escaneo. En la puerta no se lee, se mira: el veredicto va
/// primero y enorme, sobre un bloque de color pleno; después el nombre, y al
/// final los datos de apoyo.
class VeredictoCard extends StatelessWidget {
  const VeredictoCard({super.key, required this.resultado});

  final ResultadoEscaneo resultado;

  @override
  Widget build(BuildContext context) {
    final r = resultado;
    final color = colorDeVeredicto(r.veredicto);
    final sobre =
        ThemeData.estimateBrightnessForColor(color) == Brightness.dark
            ? Colors.white
            : Colors.black;
    final hora = r.hora;

    return Semantics(
      liveRegion: true,
      label: '${r.veredicto.texto}. ${r.nombre ?? ''}',
      child: Container(
        width: double.infinity,
        decoration: BoxDecoration(
          color: VenueColors.superficie,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: color, width: 2),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              color: color,
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
              child: Row(
                children: [
                  Icon(iconoDeVeredicto(r.veredicto), color: sobre, size: 38),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FittedBox(
                      alignment: Alignment.centerLeft,
                      fit: BoxFit.scaleDown,
                      child: Text(
                        r.veredicto.texto,
                        style: TextStyle(
                          color: sobre,
                          fontSize: 34,
                          fontWeight: FontWeight.w900,
                          letterSpacing: .5,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 14, 18, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (r.credencial != null) ...[
                    Center(child: FotoPersona(nombre: r.credencial!.nombre, url: r.credencial!.fotoUrl, tam: 150)),
                    const SizedBox(height: 12),
                  ],
                  if (r.nombre != null && r.nombre!.isNotEmpty)
                    Text(
                      r.nombre!,
                      style: const TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.w800,
                        height: 1.15,
                      ),
                    ),
                  if (r.tipo != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      r.tipo!,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: color,
                      ),
                    ),
                  ],
                  if (r.quien != null) ...[
                    const SizedBox(height: 6),
                    Text(
                      r.quien!,
                      style: TextStyle(
                        fontSize: 15,
                        color: VenueColors.textoSuave,
                      ),
                    ),
                  ],
                  if (hora != null) ...[
                    const SizedBox(height: 6),
                    Text(
                      'Ingresó a las ${_hhmm(hora)}',
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                  if (r.detalle != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      r.detalle!,
                      style: TextStyle(
                        fontSize: 15,
                        height: 1.35,
                        color: VenueColors.textoSuave,
                      ),
                    ),
                  ],
                  if (r.credencial != null) _DatosCredencial(c: r.credencial!),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

const _rolTexto = {'admin': 'Admin', 'jefe': 'Jefe de team', 'rrpp': 'Relacionador', 'portero': 'Portero'};

/// Quién es y qué tiene esta noche en cada lista. Va debajo de la foto.
class _DatosCredencial extends StatelessWidget {
  const _DatosCredencial({required this.c});
  final Credencial c;

  @override
  Widget build(BuildContext context) {
    final suave = TextStyle(fontSize: 14, color: VenueColors.textoSuave, height: 1.35);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 4),
        Text(
          [
            _rolTexto[c.rol] ?? c.rol ?? 'Sin rol en este boliche',
            if (c.team != null) 'Team ${c.team}',
          ].join(' · '),
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
        ),
        Text('@${c.usuario}', style: suave),
        if (c.fotoUrl == null) ...[
          const SizedBox(height: 6),
          Text('No tiene foto cargada: pedile su carnet.', style: suave.copyWith(color: VenueColors.aviso)),
        ],
        for (final l in c.listas) ...[
          const SizedBox(height: 10),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: VenueColors.superficie2,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  Flexible(
                    child: Text(l.nombre,
                        style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                  ),
                  if (l.especial) ...[
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: VenueColors.ok.withValues(alpha: .14),
                        borderRadius: BorderRadius.circular(99),
                      ),
                      child: Text('excepción',
                          style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: VenueColors.ok)),
                    ),
                  ],
                ]),
                const SizedBox(height: 2),
                Text(
                  '${l.cupo == null ? '${l.anotados} anotados' : '${l.anotados} de ${l.cupo} anotados'} · ${l.ingresaron} entraron',
                  style: suave,
                ),
                Text(
                  c.sinTope
                      ? 'Sus invitados entran a cualquier hora'
                      : l.entraHasta != null
                          ? 'Sus invitados entran hasta las ${l.entraHasta}'
                          : 'Sin hora de cierre',
                  style: suave,
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}
