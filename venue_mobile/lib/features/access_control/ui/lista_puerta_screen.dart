import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/networking/supabase.dart';
import '../../../core/theme/venue_theme.dart';
import '../../../core/widgets/avisos.dart';
import '../../../core/widgets/estado_vista.dart';
import '../../events/data/eventos.dart';
import '../data/persona_puerta.dart';
import '../data/puerta_repository.dart';
import '../data/resultado.dart';

/// Lista en puerta: buscar por nombre y marcar el ingreso. Sirve para los
/// invitados de lista y para quien compró manilla y no tiene el QR a mano.
class ListaPuertaScreen extends ConsumerStatefulWidget {
  const ListaPuertaScreen({super.key});

  @override
  ConsumerState<ListaPuertaScreen> createState() => _ListaPuertaScreenState();
}

class _ListaPuertaScreenState extends ConsumerState<ListaPuertaScreen> {
  final _q = TextEditingController();
  Timer? _espera;
  List<PersonaPuerta>? _filas;
  Object? _error;
  bool _cargando = false;
  int _pedido = 0;

  /// Fila armada para desmarcar: hay que tocar dos veces, porque desmarcar
  /// por error deja entrar dos veces a la misma persona.
  String? _armada;
  Timer? _desarmar;

  @override
  void dispose() {
    _espera?.cancel();
    _desarmar?.cancel();
    _q.dispose();
    super.dispose();
  }

  void _alEscribir(String _) {
    _espera?.cancel();
    _espera = Timer(const Duration(milliseconds: 250), _buscar);
  }

  Future<void> _buscar() async {
    final ev = ref.read(eventoActivoProvider);
    final crudo = _q.text;
    final texto = crudo.trim();
    if (ev == null || texto.length < 2) {
      setState(() {
        _filas = null;
        _error = null;
      });
      return;
    }
    final n = ++_pedido;
    setState(() => _cargando = true);
    try {
      final r = await ref.read(puertaRepositoryProvider).buscar(ev.id, texto);
      if (!mounted || n != _pedido) return; // llegó tarde: ya hay otra búsqueda
      setState(() {
        _filas = PersonaPuerta.ordenar(r,
            discreto: crudo.isNotEmpty && crudo[0] == ' ');
        _error = null;
        _cargando = false;
      });
    } catch (e) {
      if (!mounted || n != _pedido) return;
      setState(() {
        _error = e;
        _cargando = false;
      });
    }
  }

  Future<void> _hacer(Future<void> Function() accion) async {
    try {
      await accion();
    } catch (e) {
      if (mounted) avisar(context, mensajeDeError(e), tipo: TipoAviso.aviso);
    }
    if (mounted) await _buscar();
  }

  Future<void> _marcar(PersonaPuerta p, String eventoId) => _hacer(() async {
        final repo = ref.read(puertaRepositoryProvider);
        if (p.esEntrada) {
          // Mismo camino que el escáner: aplica anulada, usada y horario.
          final r = await repo.validar(eventoId: eventoId, crudo: p.codigo ?? '');
          if (!mounted) return;
          if (r.veredicto.dejaPasar) {
            HapticFeedback.mediumImpact();
            avisar(context, 'Ingreso: ${r.nombre ?? p.nombre}');
          } else {
            HapticFeedback.heavyImpact();
            avisar(
              context,
              r.veredicto == Veredicto.yaIngreso && r.hora != null
                  ? '${p.nombre} ya había ingresado ${horaCorta(r.hora!)}'
                  : '${p.nombre}: ${r.detalle ?? r.veredicto.texto}',
              tipo: TipoAviso.aviso,
            );
          }
        } else {
          final entro = await repo.ingresoDeLista(p.id!);
          if (!mounted) return;
          HapticFeedback.mediumImpact();
          avisar(context, entro ? 'Ingreso: ${p.nombre}' : 'Ya había ingresado',
              tipo: entro ? TipoAviso.ok : TipoAviso.aviso);
        }
      });

  void _desmarcar(PersonaPuerta p, String eventoId) {
    final clave = p.esEntrada ? 'e:${p.codigo}' : 'r:${p.id}';
    if (_armada != clave) {
      setState(() => _armada = clave);
      _desarmar?.cancel();
      _desarmar = Timer(const Duration(milliseconds: 2500), () {
        if (mounted) setState(() => _armada = null);
      });
      avisar(context, 'Tocá de nuevo para desmarcar el ingreso',
          tipo: TipoAviso.aviso);
      return;
    }
    setState(() => _armada = null);
    _hacer(() async {
      final repo = ref.read(puertaRepositoryProvider);
      if (p.esEntrada) {
        await repo.desmarcarEntrada(eventoId, p.codigo!);
      } else {
        await repo.desmarcarLista(p.id!);
      }
      if (mounted) {
        avisar(context, 'Ingreso desmarcado a ${p.nombre}', tipo: TipoAviso.aviso);
      }
    });
  }

  Future<void> _filtro(PersonaPuerta p, String eventoId) => _hacer(() async {
        final r = await ref
            .read(puertaRepositoryProvider)
            .alternarFiltro(eventoId, p);
        if (!mounted) return;
        avisar(
          context,
          r.marcado
              ? '${r.nombre} marcado: no pasó el filtro${r.rrpp.isEmpty ? '' : ' · lo trajo ${r.rrpp}'}'
              : 'Marca quitada a ${r.nombre}',
          tipo: r.marcado ? TipoAviso.aviso : TipoAviso.ok,
        );
      });

  @override
  Widget build(BuildContext context) {
    final ev = ref.watch(eventoActivoProvider);
    if (ev == null) {
      return const MensajeVista(
        icono: Icons.event_busy_rounded,
        titulo: 'No hay evento activo',
      );
    }
    final filas = _filas;

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
          child: TextField(
            controller: _q,
            onChanged: _alEscribir,
            autocorrect: false,
            textInputAction: TextInputAction.search,
            onSubmitted: (_) => _buscar(),
            decoration: InputDecoration(
              hintText: 'Buscar nombre…',
              prefixIcon: const Icon(Icons.search_rounded),
              suffixIcon: _cargando
                  ? const Padding(
                      padding: EdgeInsets.all(14),
                      child: SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    )
                  : IconButton(
                      tooltip: 'Traer lo último',
                      icon: const Icon(Icons.refresh_rounded),
                      onPressed: _buscar,
                    ),
            ),
          ),
        ),
        Expanded(
          child: _error != null
              ? MensajeVista(
                  icono: esFallaDeRed(_error!)
                      ? Icons.wifi_off_rounded
                      : Icons.error_outline,
                  titulo: esFallaDeRed(_error!) ? 'Sin conexión' : 'No se pudo buscar',
                  detalle: mensajeDeError(_error!),
                  accion: 'Reintentar',
                  alTocar: _buscar,
                )
              : filas == null
                  ? const MensajeVista(
                      icono: Icons.person_search_rounded,
                      titulo: 'Escribí al menos 2 letras',
                      detalle:
                          'Buscá por nombre y marcá el ingreso. Sirve para los de lista y para quien compró manilla y no tiene el QR a mano.',
                    )
                  : filas.isEmpty
                      ? const MensajeVista(
                          icono: Icons.search_off_rounded,
                          titulo: 'Sin resultados',
                        )
                      : ListView.separated(
                          padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                          itemCount: filas.length,
                          separatorBuilder: (_, _) => const SizedBox(height: 8),
                          itemBuilder: (context, i) {
                            final p = filas[i];
                            final clave =
                                p.esEntrada ? 'e:${p.codigo}' : 'r:${p.id}';
                            return _Fila(
                              persona: p,
                              armada: _armada == clave,
                              alMarcar: () => _marcar(p, ev.id),
                              alDesmarcar: () => _desmarcar(p, ev.id),
                              alFiltrar: () => _filtro(p, ev.id),
                            );
                          },
                        ),
        ),
      ],
    );
  }
}

class _Fila extends StatelessWidget {
  const _Fila({
    required this.persona,
    required this.armada,
    required this.alMarcar,
    required this.alDesmarcar,
    required this.alFiltrar,
  });

  final PersonaPuerta persona;
  final bool armada;
  final VoidCallback alMarcar;
  final VoidCallback alDesmarcar;
  final VoidCallback alFiltrar;

  @override
  Widget build(BuildContext context) {
    final p = persona;
    final sub = p.esEntrada
        ? [p.lista ?? 'Prepagada', if (p.codigo != null) '#${p.codigo}'].join(' · ')
        : [
            if (p.lista?.isNotEmpty ?? false) p.lista!,
            if (p.rrpp?.isNotEmpty ?? false) 'lo anotó ${p.rrpp}',
          ].join(' · ');

    return Opacity(
      opacity: p.filtrada ? .55 : 1,
      child: Container(
        padding: const EdgeInsets.fromLTRB(14, 10, 8, 10),
        decoration: BoxDecoration(
          color: VenueColors.superficie,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: p.sinTope
                ? const Color(0xFFE8B530)
                : p.ingreso
                    ? VenueColors.ok.withValues(alpha: .5)
                    : VenueColors.linea,
          ),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    p.nombre,
                    style: const TextStyle(
                        fontSize: 17, fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 2),
                  Text(sub,
                      style: TextStyle(
                          color: VenueColors.textoSuave, fontSize: 13)),
                  if (p.sinTope || p.filtrada || p.anulada)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Wrap(spacing: 6, children: [
                        if (p.sinTope)
                          const _Chip('de la casa', Color(0xFFE8B530)),
                        if (p.filtrada)
                          _Chip('no pasó filtro', VenueColors.mal),
                        if (p.anulada) _Chip('anulada', VenueColors.mal),
                      ]),
                    ),
                ],
              ),
            ),
            if (!p.sinTope)
              IconButton(
                tooltip: 'No pasó el control del boliche',
                onPressed: alFiltrar,
                icon: Icon(
                  p.filtrada ? Icons.flag_rounded : Icons.flag_outlined,
                  color: p.filtrada ? VenueColors.mal : VenueColors.textoSuave,
                ),
              ),
            if (p.anulada)
              const SizedBox(width: 56)
            else if (p.ingreso) ...[
              Text(horaCorta(p.ingresoAt!),
                  style: TextStyle(
                      color: VenueColors.textoSuave,
                      fontWeight: FontWeight.w600)),
              const SizedBox(width: 6),
              _Caja(
                marcada: true,
                color: armada ? VenueColors.mal : VenueColors.ok,
                etiqueta: 'Desmarcar ingreso de ${p.nombre}',
                alTocar: alDesmarcar,
              ),
            ] else
              _Caja(
                marcada: false,
                color: VenueColors.textoSuave,
                etiqueta: 'Marcar ingreso de ${p.nombre}',
                alTocar: alMarcar,
              ),
          ],
        ),
      ),
    );
  }
}

/// Casilla grande de ingreso: el objetivo táctil es de 52 px porque se usa
/// de pie, de noche y apurado.
class _Caja extends StatelessWidget {
  const _Caja({
    required this.marcada,
    required this.color,
    required this.etiqueta,
    required this.alTocar,
  });
  final bool marcada;
  final Color color;
  final String etiqueta;
  final VoidCallback alTocar;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: etiqueta,
      child: InkWell(
        onTap: alTocar,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          width: 52,
          height: 52,
          decoration: BoxDecoration(
            color: marcada ? color.withValues(alpha: .18) : Colors.transparent,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: color, width: 2),
          ),
          child: marcada ? Icon(Icons.check_rounded, color: color, size: 30) : null,
        ),
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip(this.texto, this.color);
  final String texto;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        decoration: BoxDecoration(
          color: color.withValues(alpha: .16),
          borderRadius: BorderRadius.circular(7),
        ),
        child: Text(texto,
            style: TextStyle(
                color: color, fontSize: 11.5, fontWeight: FontWeight.w700)),
      );
}
