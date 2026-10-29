import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show PostgrestException, UserAttributes;

import '../../../core/media/imagenes.dart';
import '../../../core/networking/supabase.dart';
import '../../../core/sync/cola_offline.dart';
import '../../../core/theme/apariencia.dart';
import '../../../core/theme/venue_theme.dart';
import '../../../core/widgets/avisos.dart';
import '../../../core/widgets/foto_persona.dart';
import '../../../core/widgets/patron.dart' hide MarcaClub;
import '../../authentication/data/sesion.dart';
import '../../clubs/data/clubs.dart';
import '../../clubs/ui/selector_club_screen.dart';
import '../../clubs/ui/ubicacion_screen.dart';
import '../../teams/data/gente.dart';
import '../../teams/ui/gente_screen.dart' show OpcionesBoliche;
import '../data/perfil_cambios.dart';
import 'credencial.dart';
import 'tutorial.dart';

/// Panel de perfil: se abre desde la inicial de arriba a la derecha. Tiene
/// lo de la cuenta y los ajustes (lo secundario: lo de todos los días está en
/// la barra de abajo).
class PanelPerfil extends ConsumerWidget {
  const PanelPerfil({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final perfil = ref.watch(perfilProvider).value;
    final club = ref.watch(clubActivoProvider);
    final rol = ref.watch(rolProvider).value;
    final variosClubs = (ref.watch(clubsProvider).value?.length ?? 0) > 1;
    // el superadmin entra a la lista de boliches aunque tenga uno solo (ahí da de alta)
    final plataforma = ref.watch(plataformaProvider).value ?? false;
    final apariencia = ref.watch(aparienciaProvider);
    void cerrarYHacer(void Function() f) {
      Navigator.pop(context);
      f();
    }

    return Drawer(
      backgroundColor: VenueColors.fondo,
      width: (MediaQuery.sizeOf(context).width * .86).clamp(280.0, 380.0),
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.horizontal(left: Radius.circular(24))),
      child: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
          children: [
            Row(children: [
              const Spacer(),
              IconButton(
                tooltip: 'Cerrar',
                onPressed: () => Navigator.pop(context),
                icon: Icon(Icons.close_rounded, color: VenueColors.textoSuave),
              ),
            ]),
            // la cuenta arriba: es donde se la espera
            Column(children: [
              // tocando la foto se cambia (la primera vez directo; después la aprueba el admin)
              Semantics(
                button: true,
                label: 'Cambiar foto',
                child: InkWell(
                  customBorder: const CircleBorder(),
                  onTap: perfil == null ? null : () => cambiarMiFoto(context, ref, perfil),
                  child: Stack(clipBehavior: Clip.none, children: [
                    FotoPersona(nombre: perfil?.nombre ?? '·', url: perfil?.fotoUrl, tam: 72),
                    Positioned(
                      right: -4,
                      bottom: -2,
                      child: Container(
                        width: 28,
                        height: 28,
                        decoration: BoxDecoration(
                          color: VenueColors.superficie,
                          shape: BoxShape.circle,
                          border: Border.all(color: VenueColors.linea),
                        ),
                        child: Icon(Icons.photo_camera_outlined, size: 15, color: VenueColors.texto),
                      ),
                    ),
                  ]),
                ),
              ),
              const SizedBox(height: 12),
              Text(perfil?.nombre ?? '',
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
              const SizedBox(height: 2),
              Text(
                [
                  if (perfil != null) '@${perfil.usuario}',
                  if (rol != null) rol.etiqueta,
                ].join(' · '),
                style: TextStyle(color: VenueColors.textoSuave, fontSize: 14),
              ),
              const SizedBox(height: 14),
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(minimumSize: const Size(0, 44)),
                onPressed: perfil == null
                    ? null
                    : () => cerrarYHacer(() => _editarPerfil(context, ref, perfil)),
                icon: const Icon(Icons.edit_outlined, size: 18),
                label: const Text('Editar perfil'),
              ),
              const _Pendiente(),
            ]),
            if (rol != null && rol != Rol.portero) ...[
              const SizedBox(height: 18),
              _Grupo(children: [
                _Fila(
                  inicio: _Circulo(Icons.qr_code_2_rounded, club?.primario ?? VenueColors.marcaPorDefecto),
                  titulo: 'Mi credencial',
                  detalle: 'Tu QR para mostrar en la puerta',
                  alTocar: () => cerrarYHacer(() => verMiCredencial(context)),
                ),
                if (rol == Rol.admin && club != null)
                  _Fila(
                    inicio: _Circulo(Icons.how_to_reg_outlined, VenueColors.aviso),
                    titulo: 'Cambios de perfil',
                    detalle: 'Fotos y nombres por aprobar',
                    alTocar: () => cerrarYHacer(() => verSolicitudesPerfil(context, club.id)),
                  ),
              ]),
            ],
            if (club != null) ...[
              const _Rotulo('Boliche'),
              _Grupo(children: [
                _Fila(
                  inicio: MarcaClub(club: club, lado: 34),
                  titulo: club.nombre,
                  detalle: variosClubs || plataforma ? 'Ver todos los boliches' : club.subtitulo,
                  alTocar: variosClubs || plataforma
                      ? () => cerrarYHacer(
                          () => ref.read(clubActivoIdProvider.notifier).elegir(null))
                      : null,
                ),
                // El logo y los colores son del boliche: los cambia su admin
                // (el servidor solo deja escribir `clubs` al admin).
                if (rol == Rol.admin)
                  _Fila(
                    inicio: _Circulo(Icons.palette_outlined, club.primario ?? VenueColors.marcaPorDefecto),
                    titulo: 'Colores de la app',
                    detalle: 'Los ve todo el equipo',
                    alTocar: () => cerrarYHacer(() => _cambiarColores(context, ref, club)),
                  ),
                if (rol == Rol.admin)
                  _Fila(
                    inicio: _Circulo(Icons.payments_outlined, VenueColors.ok),
                    titulo: 'Relacionadores y comisiones',
                    detalle: !club.usaRelacionadores
                        ? 'Sin relacionadores'
                        : !club.usaTeams
                            ? 'Sin teams'
                            : 'Con teams y jefes',
                    alTocar: () => cerrarYHacer(() => _opcionesBoliche(context, ref, club)),
                  ),
                if (rol == Rol.admin)
                  _Fila(
                    inicio: _Circulo(Icons.image_outlined, VenueColors.info),
                    titulo: 'Logo del boliche',
                    detalle: club.logoUrl == null ? 'Sin logo: se ve la inicial' : 'Tocá para cambiarlo',
                    alTocar: () => cerrarYHacer(() => _cambiarLogo(context, ref, club)),
                  ),
                // dónde queda: con esto sale en el mapa de AFTR
                if (rol == Rol.admin)
                  _Fila(
                    inicio: _Circulo(Icons.place_outlined, VenueColors.aviso),
                    titulo: 'Ubicación del boliche',
                    detalle: club.ubicado
                        ? (club.direccion ?? 'Cargada · tocá para cambiarla')
                        : 'Sin cargar: no sale en el mapa de AFTR',
                    alTocar: () => cerrarYHacer(() => Navigator.of(context).push(
                          MaterialPageRoute<void>(builder: (_) => UbicacionClubScreen(club: club)),
                        )),
                  ),
              ]),
            ],
            const _Rotulo('Ajustes'),
            _Grupo(children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                child: Row(children: [
                  _Circulo(
                      apariencia == Apariencia.oscura
                          ? Icons.dark_mode_outlined
                          : Icons.light_mode_outlined,
                      VenueColors.aviso),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Text('Modo oscuro',
                        style: TextStyle(fontSize: 15.5, fontWeight: FontWeight.w500)),
                  ),
                  Switch(
                    value: apariencia == Apariencia.oscura,
                    onChanged: (v) => ref
                        .read(aparienciaProvider.notifier)
                        .elegir(v ? Apariencia.oscura : Apariencia.clara),
                  ),
                ]),
              ),
            ]),
            const SizedBox(height: 10),
            _Grupo(children: [
              _Fila(
                inicio: _Circulo(Icons.school_outlined, VenueColors.ok),
                titulo: 'Ver el tutorial',
                detalle: 'Qué hay en cada parte de la app',
                alTocar: () => cerrarYHacer(() => ref.read(tutorialPedidoProvider.notifier).pedir()),
              ),
            ]),
            const SizedBox(height: 24),
            _Grupo(children: [
              _Fila(
                inicio: _Circulo(Icons.logout_rounded, VenueColors.mal),
                titulo: 'Cerrar sesión',
                color: VenueColors.mal,
                sinFlecha: true,
                alTocar: () => cerrarYHacer(() => _salir(context, ref)),
              ),
            ]),
          ],
        ),
      ),
    );
  }
}

/// Aviso de un cambio propio que espera al admin.
class _Pendiente extends ConsumerWidget {
  const _Pendiente();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(miSolicitudProvider).value;
    if (s == null) return const SizedBox.shrink();
    final que = [
      if (s.fotoNueva != null) 'foto',
      if (s.nombreNuevo != null) 'nombre (${s.nombreNuevo})',
    ].join(' y ');
    return Container(
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: VenueColors.aviso.withValues(alpha: .12),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text('Cambio de $que esperando al administrador.',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 13, color: VenueColors.aviso)),
    );
  }
}

/// Ícono blanco en un círculo de color (filas del panel).
class _Circulo extends StatelessWidget {
  const _Circulo(this.icono, this.color);
  final IconData icono;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
        width: 34,
        height: 34,
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        child: Icon(icono, size: 18,
            color: ThemeData.estimateBrightnessForColor(color) == Brightness.dark
                ? Colors.white
                : Colors.black),
      );
}

/// Nombre, teléfono y contraseña de la propia cuenta. El usuario no se
/// cambia: es con lo que se entra.
Future<void> _editarPerfil(BuildContext context, WidgetRef ref, Perfil perfil) =>
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (c) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(c).viewInsets.bottom),
        child: _EditarPerfil(perfil: perfil),
      ),
    );

class _EditarPerfil extends ConsumerStatefulWidget {
  const _EditarPerfil({required this.perfil});
  final Perfil perfil;

  @override
  ConsumerState<_EditarPerfil> createState() => _EditarPerfilState();
}

class _EditarPerfilState extends ConsumerState<_EditarPerfil> {
  late final _nombre = TextEditingController(text: widget.perfil.nombre);
  final _tel = TextEditingController();
  final _clave = TextEditingController();
  final _clave2 = TextEditingController();
  late final _correoActual = () {
    final e = ref.read(supabaseProvider).auth.currentUser?.email ?? '';
    return e.endsWith('@plataforma.local') ? '' : e;
  }();
  late final _correo = TextEditingController(text: _correoActual);
  bool _ocupado = false;

  @override
  void dispose() {
    for (final t in [_nombre, _tel, _clave, _clave2, _correo]) {
      t.dispose();
    }
    super.dispose();
  }

  Future<void> _guardar() async {
    final nombre = _nombre.text.trim();
    final clave = _clave.text;
    if (nombre.isEmpty) return avisar(context, 'Poné tu nombre', tipo: TipoAviso.aviso);
    if (clave.isNotEmpty && clave.length < 6) {
      return avisar(context, 'La contraseña tiene que tener 6 caracteres o más', tipo: TipoAviso.aviso);
    }
    if (clave != _clave2.text) {
      return avisar(context, 'Las contraseñas no coinciden', tipo: TipoAviso.aviso);
    }
    final correo = _correo.text.trim().toLowerCase();
    if (correo.isNotEmpty && !RegExp(r'^[^@\s]+@[^@\s]+\.[a-z]{2,}$').hasMatch(correo)) {
      return avisar(context, 'Ese correo no parece válido', tipo: TipoAviso.aviso);
    }
    setState(() => _ocupado = true);
    final sb = ref.read(supabaseProvider);
    try {
      // solo el nombre: el resto del perfil (rol, team…) no se toca desde acá.
      // Salvo para el admin, queda esperando que el admin lo apruebe.
      var pendiente = false;
      if (nombre != widget.perfil.nombre) {
        pendiente = !await ref.read(perfilCambiosProvider).solicitar(nombre: nombre);
      }
      if (_tel.text.trim().isNotEmpty) {
        await sb.rpc('guardar_telefono', params: {'p_tel': _tel.text.trim()});
      }
      if (clave.isNotEmpty) await sb.auth.updateUser(UserAttributes(password: clave));
      // correo propio para entrar (db/43): desde ahí entra con el correo
      final correoNuevo = correo.isNotEmpty && correo != _correoActual;
      if (correoNuevo) {
        await sb.rpc('fijar_mi_correo', params: {'p_correo': correo});
        await sb.auth.refreshSession();
      }
      ref.invalidate(perfilProvider);
      ref.invalidate(miSolicitudProvider);
      if (!mounted) return;
      Navigator.pop(context);
      avisar(context, correoNuevo
          ? 'Listo: desde ahora entrás con $correo'
          : pendiente
              ? 'Listo. El cambio de nombre queda esperando al administrador'
              : 'Perfil actualizado');
    } catch (e) {
      if (mounted) {
        avisar(context, mensajeDeError(e), tipo: TipoAviso.aviso);
        setState(() => _ocupado = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) => ListView(
        shrinkWrap: true,
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
        children: [
          const Text('Editar perfil', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          Text(
              _correoActual.isNotEmpty
                  ? 'Entrás con $_correoActual y tu contraseña.'
                  : 'Hoy entrás con tu usuario @${widget.perfil.usuario}. Si cargás tu correo, desde ahí entrás con el correo y la misma contraseña.',
              style: TextStyle(fontSize: 13, color: VenueColors.textoSuave)),
          const SizedBox(height: 16),
          TextField(
              controller: _nombre,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(labelText: 'Nombre')),
          const SizedBox(height: 10),
          TextField(
              controller: _tel,
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(
                  labelText: 'Teléfono', hintText: 'Dejalo vacío para no cambiarlo')),
          const SizedBox(height: 10),
          TextField(
              controller: _correo,
              keyboardType: TextInputType.emailAddress,
              autocorrect: false,
              textCapitalization: TextCapitalization.none,
              decoration: const InputDecoration(labelText: 'Correo para entrar', hintText: 'tu@correo.com')),
          const SizedBox(height: 18),
          Text('Cambiar contraseña', style: TextStyle(fontSize: 13, color: VenueColors.textoSuave)),
          const SizedBox(height: 8),
          TextField(
              controller: _clave,
              obscureText: true,
              decoration: const InputDecoration(labelText: 'Nueva contraseña (opcional)')),
          const SizedBox(height: 10),
          TextField(
              controller: _clave2,
              obscureText: true,
              decoration: const InputDecoration(labelText: 'Repetila')),
          const SizedBox(height: 18),
          FilledButton(onPressed: _ocupado ? null : _guardar, child: const Text('Guardar')),
        ],
      );
}

Future<void> _cambiarLogo(BuildContext context, WidgetRef ref, Club club) async {
  final accion = await showModalBottomSheet<String>(
    context: context,
    builder: (c) => SafeArea(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: LogoClub(
              inicial: club.inicial, color: club.primario, url: club.logoUrl, lado: 84),
        ),
        Text('Logo de ${club.nombre}',
            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
        const SizedBox(height: 4),
        Text('Cuadrado. Se ve arriba a la izquierda y al elegir boliche.',
            style: TextStyle(fontSize: 13, color: VenueColors.textoSuave)),
        const SizedBox(height: 8),
        ListTile(
          leading: const Icon(Icons.photo_library_outlined),
          title: const Text('Elegir de la galería'),
          onTap: () => Navigator.pop(c, 'galeria'),
        ),
        ListTile(
          leading: const Icon(Icons.photo_camera_outlined),
          title: const Text('Sacar foto'),
          onTap: () => Navigator.pop(c, 'camara'),
        ),
        if (club.logoUrl != null)
          ListTile(
            leading: Icon(Icons.delete_outline_rounded, color: VenueColors.mal),
            title: Text('Quitar logo', style: TextStyle(color: VenueColors.mal)),
            onTap: () => Navigator.pop(c, 'quitar'),
          ),
        const SizedBox(height: 8),
      ]),
    ),
  );
  if (accion == null || !context.mounted) return;
  final repo = ref.read(genteRepositoryProvider);
  try {
    if (accion == 'quitar') {
      await repo.fijarLogo(club.id, null);
    } else {
      final b = await elegirImagen(camara: accion == 'camara', lado: 512);
      if (b == null) return;
      final url = await ref.read(archivosProvider).subirDiseno(b, 'logos/${club.id}.jpg');
      await repo.fijarLogo(club.id, url);
    }
    ref.invalidate(clubsProvider);
    if (context.mounted) {
      avisar(context, accion == 'quitar' ? 'Logo quitado' : 'Logo actualizado');
    }
  } catch (e) {
    if (context.mounted) avisar(context, mensajeDeError(e), tipo: TipoAviso.aviso);
  }
}

/// Colores que se pueden elegir: probados para que el texto se lea encima.
const _coloresMarca = <String>[
  '#C8102E', '#E11D48', '#DB2777', '#C026D3', '#7C3AED', '#6D28D9',
  '#4F46E5', '#2563EB', '#0284C7', '#0891B2', '#0D9488', '#059669',
  '#16A34A', '#65A30D', '#CA8A04', '#D97706', '#EA580C', '#DC2626',
  '#78716C', '#18181B',
];

String _hex(Color c) =>
    '#${(c.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase()}';

Future<void> _cambiarColores(BuildContext context, WidgetRef ref, Club club) async {
  final elegido = await showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    builder: (c) {
      var actual = _hex(club.primario ?? VenueColors.marcaPorDefecto);
      return StatefulBuilder(
        builder: (c, set) {
          final color = colorDesdeHex(actual) ?? VenueColors.marcaPorDefecto;
          return SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
              child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                const Text('Colores de la app',
                    style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
                const SizedBox(height: 4),
                Text('Es el color de los botones y de lo que está elegido. Lo ve todo el equipo.',
                    style: TextStyle(fontSize: 13, color: VenueColors.textoSuave)),
                const SizedBox(height: 16),
                Wrap(spacing: 12, runSpacing: 12, children: [
                  for (final h in _coloresMarca)
                    GestureDetector(
                      onTap: () => set(() => actual = h),
                      child: Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          color: colorDesdeHex(h),
                          shape: BoxShape.circle,
                          border: Border.all(
                              color: h == actual ? VenueColors.texto : Colors.transparent, width: 3),
                        ),
                        child: h == actual
                            ? Icon(Icons.check_rounded,
                                color: ThemeData.estimateBrightnessForColor(colorDesdeHex(h)!) ==
                                        Brightness.dark
                                    ? Colors.white
                                    : Colors.black)
                            : null,
                      ),
                    ),
                ]),
                const SizedBox(height: 18),
                // vista previa: un botón y una pestaña elegida con ese color
                Row(children: [
                  Expanded(
                    child: FilledButton(
                      style: FilledButton.styleFrom(
                        backgroundColor: color,
                        foregroundColor: ThemeData.estimateBrightnessForColor(color) == Brightness.dark
                            ? Colors.white
                            : Colors.black,
                      ),
                      onPressed: () => Navigator.pop(c, actual),
                      child: const Text('Usar este color'),
                    ),
                  ),
                ]),
              ]),
            ),
          );
        },
      );
    },
  );
  if (elegido == null || !context.mounted) return;
  try {
    // el secundario (íconos activos, etiquetas) sale del mismo color, un
    // poco más claro, para que siempre combinen
    final base = colorDesdeHex(elegido)!;
    final secundario = _hex(Color.lerp(base, Colors.white, .22)!);
    await ref.read(genteRepositoryProvider).fijarColores(club.id, primario: elegido, secundario: secundario);
    ref.invalidate(clubsProvider);
    if (context.mounted) avisar(context, 'Colores actualizados');
  } catch (e) {
    if (context.mounted) avisar(context, mensajeDeError(e), tipo: TipoAviso.aviso);
  }
}

Future<void> _salir(BuildContext context, WidgetRef ref) async {
  final pend = ref.read(pendientesProvider);
  if (pend > 0) {
    final si = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text('Hay $pend operación(es) sin enviar'),
        content: const Text(
            'Si cerrás sesión ahora se pierden: todavía no llegaron al servidor.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: const Text('Seguir conectado')),
          TextButton(
              onPressed: () => Navigator.pop(c, true),
              style: TextButton.styleFrom(foregroundColor: VenueColors.mal),
              child: const Text('Cerrar y descartar')),
        ],
      ),
    );
    if (si != true) return;
  }
  // La cola guarda nombres de clientes: no queda en el teléfono.
  await ref.read(colaOfflineProvider).vaciar();
  await ref.read(authRepositoryProvider).salir();
}

/// Rótulo chico sobre un grupo de filas.
class _Rotulo extends StatelessWidget {
  const _Rotulo(this.texto);
  final String texto;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 24, 4, 8),
        child: Text(texto,
            style: TextStyle(
                fontSize: 13, fontWeight: FontWeight.w500, color: VenueColors.textoTenue)),
      );
}

/// Filas agrupadas en una tarjeta, separadas por una línea fina.
class _Grupo extends StatelessWidget {
  const _Grupo({required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Tarjeta(
        padding: EdgeInsets.zero,
        child: Column(children: [
          for (var i = 0; i < children.length; i++) ...[
            if (i > 0) Divider(height: 1, indent: 60, color: VenueColors.lineaSuave),
            children[i],
          ],
        ]),
      );
}

class _Fila extends StatelessWidget {
  const _Fila({
    required this.inicio,
    required this.titulo,
    this.detalle,
    this.alTocar,
    this.color,
    this.sinFlecha = false,
  });
  final Widget inicio;
  final String titulo;
  final String? detalle;
  final VoidCallback? alTocar;
  final Color? color;
  final bool sinFlecha;

  @override
  Widget build(BuildContext context) => InkWell(
        onTap: alTocar,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(children: [
            SizedBox(width: 34, child: Center(child: inicio)),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(titulo,
                    style: TextStyle(fontSize: 15.5, fontWeight: FontWeight.w500, color: color)),
                if (detalle != null)
                  Text(detalle!, style: TextStyle(fontSize: 13, color: VenueColors.textoSuave)),
              ]),
            ),
            if (alTocar != null && !sinFlecha)
              Icon(Icons.chevron_right_rounded, color: VenueColors.textoTenue),
          ]),
        ),
      );
}


/// Cómo trabaja el boliche con relacionadores y comisiones (admin).
Future<void> _opcionesBoliche(BuildContext context, WidgetRef ref, Club club) async {
  final valores = {
    'usa_relacionadores': club.usaRelacionadores,
    'usa_teams': club.usaTeams,
    'comision_manillas': club.comisionManillas,
    'comision_combos': club.comisionCombos,
  };
  final ok = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    backgroundColor: VenueColors.superficie,
    builder: (c) => StatefulBuilder(
      builder: (c, set) => ListView(
        shrinkWrap: true,
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
        children: [
          Text('Relacionadores y comisiones', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
          Text(club.nombre, style: TextStyle(color: VenueColors.textoSuave)),
          const SizedBox(height: 8),
          OpcionesBoliche(valores: valores, alCambiar: (k, v) => set(() => valores[k] = v)),
          const SizedBox(height: 6),
          Text(
            'Con teams, cada jefe decide en "Mi team" cuánto le da a cada relacionador de la comisión de su team; '
            'lo que vende el jefe es todo suyo.',
            style: TextStyle(color: VenueColors.textoSuave, fontSize: 13, height: 1.35),
          ),
          const SizedBox(height: 14),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Guardar')),
        ],
      ),
    ),
  );
  if (ok != true || !context.mounted) return;
  try {
    await ref.read(genteRepositoryProvider).fijarOpciones(club.id, valores);
    ref.invalidate(clubsProvider);
    if (context.mounted) avisar(context, 'Configuración guardada');
  } catch (e) {
    if (!context.mounted) return;
    final falta = e is PostgrestException && (e.code == '42703' || e.code == 'PGRST204');
    avisar(context, falta ? 'Falta preparar la base para esto (db/33-comisiones-configurables.sql)' : mensajeDeError(e),
        tipo: TipoAviso.aviso);
  }
}
