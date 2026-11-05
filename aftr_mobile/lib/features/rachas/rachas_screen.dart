import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/networking/supabase.dart';
import '../../core/theme/aftr_theme.dart';
import '../../core/widgets/avatar.dart';
import '../../core/widgets/movimiento.dart';
import '../../core/widgets/piezas.dart';
import '../../data/rachas.dart';
import '../../data/social_repo.dart';
import 'buscar_amigos.dart';

/// Rachas: la tuya, la de tu gente y la de la ciudad.
///
/// Una racha son semanas seguidas saliendo, y se cuenta en la puerta: cuenta
/// la semana en la que entraste a un evento, no la que compraste la entrada.
class RachasScreen extends ConsumerWidget {
  const RachasScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(rachasProvider);
    final r = async.value;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Rachas'),
        actions: [
          IconButton(
            tooltip: 'Agregar amigos',
            onPressed: () => hojaAgregarAmigos(context),
            icon: const Icon(Icons.person_add_alt_1_rounded),
          ),
        ],
      ),
      body: RefreshIndicator(
        color: Aftr.texto,
        backgroundColor: Aftr.superficie2,
        onRefresh: () => ref.refresh(rachasProvider.future),
        child: async.hasError && r == null
            ? ListView(
                padding: const EdgeInsets.all(28),
                children: [
                  Text(mensajeDeError(async.error!), style: Aftr.cuerpo(15)),
                  const SizedBox(height: 16),
                  BotonAftr('Reintentar', onTap: () => ref.invalidate(rachasProvider)),
                ],
              )
            : r == null
            ? const Center(child: CircularProgressIndicator(color: Aftr.acento))
            : ListView(
                padding: EdgeInsets.fromLTRB(
                  20, 10, 20, 40 + MediaQuery.paddingOf(context).bottom),
                children: [
                  _MiRacha(r),
                  const SizedBox(height: 18),
                  // Blanco: es lo único que hay que hacer en esta pantalla.
                  BotonAftr(
                    'Agregar amigos',
                    icono: const Icon(Icons.person_add_alt_1_rounded,
                        size: 18, color: Aftr.fondo),
                    onTap: () => hojaAgregarAmigos(context),
                  ),
                  if (r.pedidos.isNotEmpty) ...[
                    const SizedBox(height: 26),
                    Text('Te quieren agregar', style: Aftr.fuerte(20)),
                    const SizedBox(height: 10),
                    for (final p in r.pedidos) _Pedido(p),
                  ],
                  const SizedBox(height: 26),
                  Text('Tu gente', style: Aftr.fuerte(20)),
                  const SizedBox(height: 4),
                  Text(
                    r.gente.isEmpty
                        ? 'Agregá a alguien, o salí con alguien: quienes comparten '
                              'una mesa con vos o te pasan una entrada aparecen acá solos.'
                        : r.porDelante == 0
                        ? 'Nadie de tu gente te pasa.'
                        : r.porDelante == 1
                        ? 'Una persona te pasa. Falta una noche.'
                        : '${r.porDelante} personas te pasan.',
                    style: Aftr.cuerpo(13),
                  ),
                  if (r.gente.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    _Podio(r.gente, yo: r.mia),
                    const SizedBox(height: 10),
                    for (var i = 0; i < r.gente.length; i++)
                      _FilaRanking(r.gente[i], puesto: i + 1),
                  ],
                  if (r.ciudad.isNotEmpty) ...[
                    const SizedBox(height: 30),
                    Text('La ciudad', style: Aftr.fuerte(20)),
                    const SizedBox(height: 4),
                    Text(
                      'Las rachas más largas de AFTR. Entrás al ranking con dos '
                      'semanas seguidas.',
                      style: Aftr.cuerpo(13),
                    ),
                    const SizedBox(height: 14),
                    for (var i = 0; i < r.ciudad.length; i++)
                      _FilaRanking(r.ciudad[i], puesto: i + 1, soloUsuario: true),
                  ],
                ],
              ),
      ),
    );
  }
}

class _MiRacha extends StatelessWidget {
  const _MiRacha(this.r);
  final Rachas r;

  @override
  Widget build(BuildContext context) {
    final m = r.mia;
    final viva = m.viva;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(Aftr.radio),
        border: Border.all(
          color: viva ? Aftr.acento.withValues(alpha: 0.45) : Aftr.borde,
        ),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: viva
              ? [Aftr.acento.withValues(alpha: 0.16), Aftr.superficie]
              : [Aftr.superficie2, Aftr.superficie],
        ),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(
            viva ? Icons.local_fire_department_rounded : Icons.local_fire_department_outlined,
            color: viva ? Aftr.acento : Aftr.texto3,
            size: 34,
          ),
          const SizedBox(width: 10),
          Text(
            '${viva ? m.semanas : m.mejor}',
            style: Aftr.titular(60, c: viva ? Aftr.acento : Aftr.texto3),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              viva
                  ? (m.semanas == 1 ? 'semana\nsaliendo' : 'semanas\nseguidas')
                  : m.mejor > 0
                  ? 'fue tu\nmejor racha'
                  : 'todavía\nsin racha',
              style: Aftr.cuerpo(14, c: Aftr.texto),
            ),
          ),
        ]),
        const SizedBox(height: 14),
        Text(
          !viva
              ? (m.mejor > 0
                    ? 'Se cortó. Una noche esta semana y arranca de nuevo.'
                    : 'Entrá a un evento y arranca. Cuenta la puerta, no la compra.')
              : !m.cerrada
              ? 'Esta semana todavía no saliste: tenés hasta el domingo para no perderla.'
              : m.mejor > m.semanas
              ? 'Tu mejor fueron ${m.mejor} semanas.'
              : 'Es tu mejor racha hasta ahora.',
          style: Aftr.cuerpo(13, c: viva && !m.cerrada ? Aftr.acento : Aftr.texto2),
        ),
        if (r.noches > 0) ...[
          const SizedBox(height: 16),
          Row(children: [
            Expanded(child: _Dato('${r.noches}', 'noches en 30 días')),
            if (r.lugar != null) Expanded(child: _Dato(r.lugar!, 'donde más vas')),
          ]),
        ],
      ]),
    );
  }
}

class _Dato extends StatelessWidget {
  const _Dato(this.valor, this.que);
  final String valor;
  final String que;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(valor, maxLines: 1, overflow: TextOverflow.ellipsis, style: Aftr.fuerte(19)),
      Text(que, style: Aftr.cuerpo(12, c: Aftr.texto3)),
    ],
  );
}

/// Los tres primeros, con el del medio más alto. Es la parte divertida.
class _Podio extends StatelessWidget {
  const _Podio(this.gente, {required this.yo});
  final List<Racha> gente;
  final Racha yo;

  @override
  Widget build(BuildContext context) {
    // se compite con la propia adentro: un podio sin uno mismo no dice nada
    final todos = [...gente, yo]..sort((a, b) {
      final s = (b.viva ? b.semanas : 0).compareTo(a.viva ? a.semanas : 0);
      return s != 0 ? s : a.nombre.compareTo(b.nombre);
    });
    final tres = todos.take(3).toList();
    if (tres.length < 2) return const SizedBox.shrink();
    // el primero al medio
    final orden = tres.length == 2 ? [tres[1], tres[0]] : [tres[1], tres[0], tres[2]];
    return SizedBox(
      // 178: el escalón del primero es más alto y arriba lleva la copa
      height: 178,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          for (final p in orden)
            Expanded(
              child: _Escalon(
                p,
                primero: p == tres.first,
                esYo: p.usuario == yo.usuario,
              ),
            ),
        ],
      ),
    );
  }
}

class _Escalon extends StatelessWidget {
  const _Escalon(this.r, {required this.primero, required this.esYo});
  final Racha r;
  final bool primero;
  final bool esYo;

  @override
  Widget build(BuildContext context) => Column(
    mainAxisAlignment: MainAxisAlignment.end,
    children: [
      if (primero) const Icon(Icons.emoji_events_rounded, color: Aftr.acento, size: 20),
      const SizedBox(height: 4),
      AvatarRemoto(
        nombre: r.nombre,
        foto: r.foto,
        clave: r.fotoKey,
        radio: primero ? 28 : 22,
      ),
      const SizedBox(height: 6),
      Text(
        esYo ? 'Vos' : r.nombre.split(' ').first,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: Aftr.cuerpo(12, c: esYo ? Aftr.acento : Aftr.texto, w: FontWeight.w700),
      ),
      Text(
        '${r.viva ? r.semanas : 0}',
        style: Aftr.fuerte(primero ? 22 : 18, c: primero ? Aftr.acento : Aftr.texto),
      ),
      Container(
        margin: const EdgeInsets.only(top: 6),
        height: primero ? 34 : 20,
        decoration: BoxDecoration(
          color: primero ? Aftr.acento.withValues(alpha: 0.25) : Aftr.superficie2,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(8)),
        ),
      ),
    ],
  );
}

class _FilaRanking extends StatelessWidget {
  const _FilaRanking(this.r, {required this.puesto, this.soloUsuario = false});
  final Racha r;
  final int puesto;

  /// En el ranking de la ciudad va sólo el usuario, que es lo público.
  final bool soloUsuario;

  @override
  Widget build(BuildContext context) {
    final viva = r.viva;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(children: [
        SizedBox(
          width: 22,
          child: Text('$puesto', style: Aftr.cuerpo(13, c: Aftr.texto3, w: FontWeight.w700)),
        ),
        AvatarRemoto(nombre: soloUsuario ? r.usuario : r.nombre,
          foto: r.foto, clave: r.fotoKey, radio: 18),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(
              soloUsuario ? '@${r.usuario}' : r.nombre,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Aftr.fuerte(15),
            ),
            if (!soloUsuario) ...[
              const SizedBox(height: 1),
              Text(
                [
                  '@${r.usuario}',
                  if (!r.amigo) 'salieron juntos',
                ].join(' · '),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Aftr.cuerpo(13, c: Aftr.texto3),
              ),
            ],
          ]),
        ),
        Icon(
          viva ? Icons.local_fire_department_rounded : Icons.local_fire_department_outlined,
          size: 17,
          color: viva ? Aftr.acento : Aftr.texto3,
        ),
        const SizedBox(width: 3),
        Text(
          '${viva ? r.semanas : r.mejor}',
          style: Aftr.fuerte(17, c: viva ? Aftr.acento : Aftr.texto3),
        ),
      ]),
    );
  }
}

class _Pedido extends ConsumerStatefulWidget {
  const _Pedido(this.r);
  final Racha r;

  @override
  ConsumerState<_Pedido> createState() => _PedidoState();
}

class _PedidoState extends ConsumerState<_Pedido> {
  bool _ocupado = false;
  String? _resuelto;

  Future<void> _responder(String accion) async {
    setState(() => _ocupado = true);
    try {
      await ref.read(socialRepoProvider).amistad(accion, widget.r.usuario);
      ref.invalidate(rachasProvider);
      if (mounted) {
        setState(() => _resuelto = accion == 'aceptar' ? 'Amigos' : 'Listo');
      }
    } catch (e) {
      if (mounted) avisar(context, mensajeDeError(e));
    } finally {
      if (mounted) setState(() => _ocupado = false);
    }
  }

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 7),
    child: Row(children: [
      AvatarRemoto(nombre: widget.r.nombre, foto: widget.r.foto,
        clave: widget.r.fotoKey, radio: 20),
      const SizedBox(width: 12),
      Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(widget.r.nombre, maxLines: 1, overflow: TextOverflow.ellipsis,
            style: Aftr.fuerte(15)),
          Text('@${widget.r.usuario}', maxLines: 1, overflow: TextOverflow.ellipsis,
            style: Aftr.cuerpo(13, c: Aftr.texto3)),
        ]),
      ),
      if (_resuelto != null)
        Text(_resuelto!, style: Aftr.cuerpo(13, c: Aftr.texto3))
      else if (_ocupado)
        const SizedBox(width: 18, height: 18,
          child: CircularProgressIndicator(strokeWidth: 2, color: Aftr.acento))
      else ...[
        Presionable(
          onTap: () => _responder('aceptar'),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              color: Aftr.texto,
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text('Aceptar',
              style: Aftr.cuerpo(13, c: Aftr.fondo, w: FontWeight.w700)),
          ),
        ),
        TextButton(onPressed: () => _responder('borrar'), child: const Text('No')),
      ],
    ]),
  );
}
