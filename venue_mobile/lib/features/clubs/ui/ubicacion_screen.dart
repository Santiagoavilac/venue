import 'dart:async';

import 'package:apple_maps_flutter/apple_maps_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geocoding/geocoding.dart' as geo;

import '../../../core/networking/supabase.dart';
import '../../../core/theme/venue_theme.dart';
import '../../../core/widgets/avisos.dart';
import '../../teams/data/gente.dart';
import '../data/clubs.dart';

/// El admin pone dónde queda el boliche: busca la dirección o mueve el mapa
/// hasta dejar el pin del centro sobre la puerta. Con eso el boliche sale en
/// el mapa de AFTR. La búsqueda es la de Apple (viene con el iPhone).
class UbicacionClubScreen extends ConsumerStatefulWidget {
  const UbicacionClubScreen({super.key, required this.club});

  final Club club;

  @override
  ConsumerState<UbicacionClubScreen> createState() => _UbicacionClubScreenState();
}

class _UbicacionClubScreenState extends ConsumerState<UbicacionClubScreen> {
  // sin ubicación cargada se arranca en Santa Cruz
  static const _santaCruz = LatLng(-17.7833, -63.1821);

  final _busqueda = TextEditingController();
  final _geo = geo.Geocoding();
  AppleMapController? _mapa;
  late LatLng _centro = widget.club.ubicado ? LatLng(widget.club.lat!, widget.club.lng!) : _santaCruz;
  bool _moviendo = false;
  bool _buscando = false;
  bool _guardando = false;
  String? _direccion;
  String? _zona;
  String? _ciudad;
  Timer? _espera;

  @override
  void initState() {
    super.initState();
    _direccion = widget.club.direccion;
    if (widget.club.ubicado) _leerDireccion(_centro);
  }

  @override
  void dispose() {
    _espera?.cancel();
    _busqueda.dispose();
    super.dispose();
  }

  Future<void> _leerDireccion(LatLng p) async {
    try {
      final r = await _geo.placemarkFromCoordinates(p.latitude, p.longitude);
      if (!mounted || r.isEmpty) return;
      final m = r.first;
      final calle = [m.thoroughfare, m.subThoroughfare].whereType<String>().where((s) => s.isNotEmpty).join(' ');
      setState(() {
        _direccion = calle.isNotEmpty ? calle : m.name;
        _zona = m.subLocality?.isNotEmpty == true ? m.subLocality : null;
        _ciudad = m.locality?.isNotEmpty == true ? m.locality : m.administrativeArea;
      });
    } catch (_) {
      // sin señal o Apple no encontró nada: se guarda igual con las coordenadas
    }
  }

  Future<void> _buscar() async {
    final t = _busqueda.text.trim();
    if (t.isEmpty) return;
    FocusScope.of(context).unfocus();
    setState(() => _buscando = true);
    try {
      final ciudad = _ciudad ?? 'Santa Cruz, Bolivia';
      var r = await _geo.locationFromAddress('$t, $ciudad');
      if (r.isEmpty) r = await _geo.locationFromAddress(t);
      if (r.isEmpty) throw const FormatException('No encontramos esa dirección.');
      final p = LatLng(r.first.latitude, r.first.longitude);
      await _mapa?.animateCamera(CameraUpdate.newLatLngZoom(p, 17));
    } catch (e) {
      if (mounted) avisar(context, 'No encontramos esa dirección. Probá moviendo el mapa.', tipo: TipoAviso.aviso);
    } finally {
      if (mounted) setState(() => _buscando = false);
    }
  }

  Future<void> _guardar() async {
    setState(() => _guardando = true);
    try {
      await ref.read(genteRepositoryProvider).fijarUbicacion(
            widget.club.id,
            lat: _centro.latitude,
            lng: _centro.longitude,
            direccion: _direccion,
            zona: _zona,
            ciudad: _ciudad,
          );
      ref.invalidate(clubsProvider);
      if (!mounted) return;
      avisar(context, 'Ubicación guardada. Ya sale en el mapa de AFTR.');
      Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) avisar(context, mensajeDeError(e), tipo: TipoAviso.aviso);
    } finally {
      if (mounted) setState(() => _guardando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final arriba = MediaQuery.paddingOf(context).top;
    final abajo = MediaQuery.paddingOf(context).bottom;
    final marca = widget.club.primario ?? VenueColors.marcaPorDefecto;
    return Scaffold(
      resizeToAvoidBottomInset: false,
      body: Stack(children: [
        Positioned.fill(
          child: AppleMap(
            initialCameraPosition: CameraPosition(target: _centro, zoom: widget.club.ubicado ? 17 : 13),
            onMapCreated: (m) => _mapa = m,
            myLocationEnabled: true,
            myLocationButtonEnabled: true,
            compassEnabled: false,
            pitchGesturesEnabled: false,
            onCameraMoveStarted: () => setState(() => _moviendo = true),
            onCameraMove: (c) => _centro = c.target,
            onCameraIdle: () {
              setState(() => _moviendo = false);
              HapticFeedback.selectionClick();
              _espera?.cancel();
              _espera = Timer(const Duration(milliseconds: 350), () => _leerDireccion(_centro));
            },
          ),
        ),
        // el pin fijo del centro: se levanta mientras se mueve el mapa
        IgnorePointer(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.only(bottom: 44),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                AnimatedSlide(
                  duration: const Duration(milliseconds: 220),
                  curve: Curves.easeOutBack,
                  offset: Offset(0, _moviendo ? -0.35 : 0),
                  child: Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: marca,
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 3),
                      boxShadow: const [BoxShadow(color: Color(0x55000000), blurRadius: 10, offset: Offset(0, 4))],
                    ),
                    child: Center(
                      child: Text(widget.club.inicial,
                          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 18)),
                    ),
                  ),
                ),
                AnimatedContainer(
                  duration: const Duration(milliseconds: 220),
                  width: _moviendo ? 6 : 10,
                  height: _moviendo ? 3 : 5,
                  margin: const EdgeInsets.only(top: 4),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.35),
                    borderRadius: BorderRadius.circular(5),
                  ),
                ),
              ]),
            ),
          ),
        ),
        // atrás y búsqueda
        Positioned(
          top: arriba + 8,
          left: 12,
          right: 12,
          child: Row(children: [
            Material(
              color: cs.surface,
              shape: const CircleBorder(),
              elevation: 3,
              child: IconButton(
                onPressed: () => Navigator.of(context).pop(),
                icon: const Icon(Icons.arrow_back_rounded),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Material(
                color: cs.surface,
                elevation: 3,
                borderRadius: BorderRadius.circular(16),
                child: TextField(
                  controller: _busqueda,
                  textInputAction: TextInputAction.search,
                  onSubmitted: (_) => _buscar(),
                  decoration: InputDecoration(
                    hintText: 'Buscar dirección',
                    border: InputBorder.none,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                    suffixIcon: _buscando
                        ? const Padding(
                            padding: EdgeInsets.all(14),
                            child: SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
                          )
                        : IconButton(onPressed: _buscar, icon: const Icon(Icons.search_rounded)),
                  ),
                ),
              ),
            ),
          ]),
        ),
        // tarjeta de abajo: la dirección que queda y Guardar
        Positioned(
          left: 12,
          right: 12,
          bottom: abajo + 12,
          child: Material(
            color: cs.surface,
            elevation: 6,
            borderRadius: BorderRadius.circular(22),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
              child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Ubicación de ${widget.club.nombre}',
                    style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
                const SizedBox(height: 4),
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 200),
                  child: Text(
                    _moviendo
                        ? 'Soltá el mapa sobre la puerta del boliche'
                        : [_direccion, _zona, _ciudad].whereType<String>().where((s) => s.isNotEmpty).join(', ').ifEmpty(
                            'Mové el mapa hasta dejar el pin sobre el boliche'),
                    key: ValueKey('$_moviendo$_direccion$_zona'),
                    style: TextStyle(fontSize: 14, color: VenueColors.textoSuave),
                  ),
                ),
                const SizedBox(height: 14),
                SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: FilledButton(
                    onPressed: _guardando || _moviendo ? null : _guardar,
                    style: FilledButton.styleFrom(
                      backgroundColor: marca,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    ),
                    child: _guardando
                        ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                        : const Text('Guardar ubicación', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                  ),
                ),
              ]),
            ),
          ),
        ),
      ]),
    );
  }
}

extension on String {
  String ifEmpty(String otro) => isEmpty ? otro : this;
}
