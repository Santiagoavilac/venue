import 'dart:io';

import 'package:share_plus/share_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../events/data/eventos.dart';
import 'xlsx.dart';

/// Libro contable del evento: el MISMO que arma la web (`contabilidad.js`).
///
/// Hoja Resumen + una hoja por team, con fórmulas vivas: precios y % viven
/// en una celda cada uno y todo el libro los apunta.
///
/// SOLO PUERTA: prepagadas y lista INGRESADAS. No hay mesas en el libro.
///   Rendición         = (prepagadas − externos) × precio × % local
///   Pago de Lista     = lista × precio de lista × % local
///   Total a depositar = Rendición − Pago de Lista
///
/// Quién puede lo decide el servidor (`contabilidad_evento`): las cuentas
/// con `contabilidad_total`, todo; un jefe, solo su team.

class TeamContable {
  TeamContable(this.nombre, this.jefe);
  final String nombre;
  final String jefe;
  final rrpps = <({String nombre, int pre, int lis})>[];
  int get prepagadas => rrpps.fold(0, (a, r) => a + r.pre);
  int get lista => rrpps.fold(0, (a, r) => a + r.lis);
}

class DatosContables {
  const DatosContables({
    required this.teams, required this.precioManilla, required this.porManilla,
    required this.externas, required this.precioLista, required this.alcance,
    this.teamNombre,
  });
  final List<TeamContable> teams;
  final num precioManilla, porManilla, precioLista;
  final int externas;

  /// total | team
  final String alcance;
  final String? teamNombre;

  num get pctLocal => precioManilla > 0 ? porManilla / precioManilla : 0;

  /// Agrupa las filas de `contabilidad_evento` por team, con el mismo orden
  /// que la web: teams por prepagadas, personas por actividad.
  factory DatosContables.desde(Map<String, dynamic> data, num precioLista) {
    final liq = Map<String, dynamic>.from(data['liq'] as Map? ?? const {});
    final grupos = <String, TeamContable>{};
    for (final x in (data['filas'] as List? ?? const [])) {
      final r = Map<String, dynamic>.from(x as Map);
      final pre = (r['prepagadas'] as num? ?? 0).toInt();
      final lis = (r['lista'] as num? ?? 0).toInt();
      if (pre == 0 && lis == 0) continue; // sin actividad no entra al libro
      final id = r['team_id'] as String?;
      final base = r['team'] as String? ?? (id != null ? 'Team' : 'Sin team');
      final g = grupos.putIfAbsent(
          id ?? '__sin__',
          () => TeamContable(
              id == null
                  ? base
                  : RegExp('^team', caseSensitive: false).hasMatch(base)
                      ? base
                      : 'Team $base',
              r['jefe'] as String? ?? ''));
      g.rrpps.add((nombre: r['rrpp'] as String? ?? '?', pre: pre, lis: lis));
    }
    for (final g in grupos.values) {
      g.rrpps.sort((a, b) {
        final d = (b.pre + b.lis).compareTo(a.pre + a.lis);
        return d != 0 ? d : a.nombre.compareTo(b.nombre);
      });
    }
    return DatosContables(
      teams: grupos.values.toList()..sort((a, b) => b.prepagadas.compareTo(a.prepagadas)),
      precioManilla: liq['precio_manilla'] as num? ?? 0,
      porManilla: liq['por_manilla'] as num? ?? 0,
      externas: (liq['manillas_externas'] as num? ?? 0).toInt(),
      precioLista: precioLista,
      alcance: data['alcance'] as String? ?? 'team',
      teamNombre: data['team'] as String?,
    );
  }

  // Resultados (los mismos que calculan las fórmulas del libro).
  int get totalPrepagadas => teams.fold(0, (a, t) => a + t.prepagadas);
  int get totalLista => teams.fold(0, (a, t) => a + t.lista);
  num get rendicion {
    final n = totalPrepagadas - externas;
    return (n < 0 ? 0 : n) * precioManilla * pctLocal;
  }

  num get pagoDeLista => totalLista * precioLista * pctLocal;
  num get totalADepositar => rendicion - pagoDeLista;
}

/// Nombre de hoja válido: Excel prohíbe `: \ / ? * [ ]` y corta en 31.
String nombreDeHoja(String base, Set<String> usados) {
  var n = base.replaceAll(RegExp(r'[:\\/?*\[\]]'), '-').trim();
  if (n.length > 31) n = n.substring(0, 31).trim();
  if (n.isEmpty) n = 'Team';
  final orig = n;
  var i = 2;
  while (usados.contains(n.toLowerCase())) {
    final suf = ' (${i++})';
    n = orig.substring(0, orig.length > 31 - suf.length ? 31 - suf.length : orig.length) + suf;
  }
  usados.add(n.toLowerCase());
  return n;
}

String _fecha(DateTime f) =>
    '${f.day.toString().padLeft(2, '0')}/${f.month.toString().padLeft(2, '0')}/${f.year}';

const _suave = 'FF7B8794', _linea = 'FFD4DAE0', _lineaFte = 'FF9AA5B1';
const _cabecera = 'FFEDF2F7', _verde = 'FFEAF3E7', _gris = 'FFF2F4F6', _ambar = 'FFFBF3DC';
const _totalFila = 'FFE6EBF0', _acento = 'FFF5C542', _azul = 'FF2A6FB5';
const _bs = '"Bs" #,##0.00', _cant = '#,##0', _pct = '0%';

Libro construirLibro(String evento, DateTime fecha, String club, DatosContables d) {
  final libro = Libro();
  final r = libro.hoja('Resumen', horizontal: true);
  r.anchos.addAll({1: 2.5, 2: 30, 3: 13, 4: 13, 5: 17, 6: 17, 7: 15, 8: 2.5});
  const rotulo = Estilo(tam: 9, negrita: true, color: _suave);

  r.combinar('B2:G2');
  r.texto('B2', 'Contabilidad $club', const Estilo(tam: 22, negrita: true));
  r.altos[2] = 32;
  r.combinar('B3:G3');
  r.texto('B3', _fecha(fecha), const Estilo(tam: 12, color: _suave));
  r.combinar('B4:G4');
  r.texto('B4', '$evento · solo ingresados', const Estilo(tam: 10, color: _suave));
  for (final c in ['B', 'C', 'D', 'E', 'F', 'G']) {
    r.estilo('${c}5', const Estilo(bordeAbajo: _lineaFte, grueso: true));
  }
  r.altos[5] = 6;

  // PARÁMETROS: cada precio y el % en su celda; todo el libro los apunta.
  r.texto('B7', 'PARÁMETROS', rotulo);
  r.texto('B9', 'Valores del evento', const Estilo(tam: 10, color: _suave));
  const etq = Estilo(tam: 9, negrita: true, color: _suave, alinear: 'center');
  r.texto('C8', 'Precio prepago', etq);
  r.texto('D8', 'Precio lista', etq);
  r.texto('E8', '% Local', etq);
  Estilo par(String f) =>
      Estilo(negrita: true, fondo: _ambar, formato: f, alinear: 'center', caja: _linea);
  r.numero('C9', d.precioManilla, par(_bs));
  r.numero('D9', d.precioLista, par(_bs));
  r.numero('E9', d.pctLocal, par(_pct));
  r.altos[9] = 22;
  const pre = r'$C$9', lis = r'$D$9', pct = r'$E$9';

  // TABLA PRINCIPAL
  r.texto('B11', 'DETALLE POR TEAM', rotulo);
  Estilo cab(String a) => Estilo(
      tam: 10, negrita: true, fondo: _cabecera, alinear: a,
      bordeArriba: _lineaFte, bordeAbajo: _lineaFte);
  r.texto('B12', 'Team', cab('left'));
  r.texto('C12', 'Prepagadas', cab('center'));
  r.texto('D12', 'Lista', cab('center'));
  r.texto('E12', 'Importe prepago', cab('right'));
  r.texto('F12', 'Importe lista', cab('right'));
  r.texto('G12', '', cab('center'));
  r.altos[12] = 24;

  const fila0 = 13;
  final usados = <String>{'resumen'};
  final hojas = <({TeamContable team, String hoja})>[];
  for (var i = 0; i < d.teams.length; i++) {
    final g = d.teams[i];
    final nom = nombreDeHoja(g.nombre, usados);
    hojas.add((team: g, hoja: nom));
    final f = fila0 + i;
    final hasta = 6 + (g.rrpps.isEmpty ? 1 : g.rrpps.length) - 1;
    r.texto('B$f', g.nombre, const Estilo(bordeAbajo: _linea));
    r.formula('C$f', "SUM('$nom'!C6:C$hasta)", g.prepagadas,
        const Estilo(fondo: _verde, formato: _cant, alinear: 'center', bordeAbajo: _linea));
    r.formula('D$f', "SUM('$nom'!D6:D$hasta)", g.lista,
        const Estilo(fondo: _gris, formato: _cant, alinear: 'center', bordeAbajo: _linea));
    r.formula('E$f', 'C$f*$pre*$pct', g.prepagadas * d.precioManilla * d.pctLocal,
        const Estilo(formato: _bs, alinear: 'right', bordeAbajo: _linea));
    r.formula('F$f', 'D$f*$lis*$pct', g.lista * d.precioLista * d.pctLocal,
        const Estilo(formato: _bs, alinear: 'right', bordeAbajo: _linea));
    r.enlace('G$f', 'Ver desglose  ›', "'$nom'!A1",
        const Estilo(tam: 10, color: _azul, alinear: 'center', bordeAbajo: _linea));
    r.altos[f] = 20;
  }
  final filaFin = fila0 + (d.teams.isEmpty ? 1 : d.teams.length) - 1;
  final ft = filaFin + 1;
  Estilo tot(String a, [String? f]) => Estilo(
      negrita: true, fondo: _totalFila, alinear: a, formato: f,
      bordeArriba: _lineaFte, bordeAbajo: _lineaFte);
  r.texto('B$ft', 'TOTAL', tot('left'));
  r.formula('C$ft', 'SUM(C$fila0:C$filaFin)', d.totalPrepagadas, tot('center', _cant));
  r.formula('D$ft', 'SUM(D$fila0:D$filaFin)', d.totalLista, tot('center', _cant));
  r.formula('E$ft', 'SUM(E$fila0:E$filaFin)',
      d.totalPrepagadas * d.precioManilla * d.pctLocal, tot('right', _bs));
  r.formula('F$ft', 'SUM(F$fila0:F$filaFin)', d.pagoDeLista, tot('right', _bs));
  r.estilo('G$ft', tot('center'));

  // AJUSTES
  final aj = ft + 2, fex = aj + 1;
  r.texto('B$aj', 'AJUSTES', rotulo);
  r.combinar('B$fex:D$fex');
  r.texto('B$fex', 'Manillas de externos (se descuentan)');
  r.numero('E$fex', d.externas,
      const Estilo(negrita: true, fondo: _ambar, formato: _cant, alinear: 'right', caja: _linea));

  // CIERRE
  final cie = fex + 2, fRend = cie + 1, fLista = cie + 2, fd = cie + 4;
  r.texto('B$cie', 'CIERRE', rotulo);
  const nota = Estilo(tam: 9, color: _suave);
  r.combinar('B$fRend:D$fRend');
  r.texto('B$fRend', 'Rendición manillas');
  r.formula('E$fRend', 'MAX(C$ft-E$fex,0)*$pre*$pct', d.rendicion,
      const Estilo(formato: _bs, alinear: 'right'));
  r.texto('G$fRend', '(prepagadas − externos) × precio × %', nota);
  r.combinar('B$fLista:D$fLista');
  r.texto('B$fLista', 'Pago de Lista');
  r.formula('E$fLista', 'D$ft*$lis*$pct', d.pagoDeLista,
      const Estilo(formato: _bs, alinear: 'right'));
  r.texto('G$fLista', d.precioLista > 0 ? 'lista × precio × %' : 'sin precio de lista ⇒ 0', nota);
  r.combinar('B$fd:D$fd');
  r.texto('B$fd', 'TOTAL A DEPOSITAR A ${club.toUpperCase()}',
      const Estilo(tam: 12, negrita: true, fondo: _acento, caja: 'FFD9A404'));
  r.estilo('C$fd', const Estilo(fondo: _acento, caja: 'FFD9A404'));
  r.estilo('D$fd', const Estilo(fondo: _acento, caja: 'FFD9A404'));
  r.combinar('E$fd:F$fd');
  r.formula('E$fd', 'E$fRend-E$fLista', d.totalADepositar,
      const Estilo(tam: 14, negrita: true, fondo: _acento, formato: _bs, alinear: 'right', caja: 'FFD9A404'));
  r.estilo('F$fd', const Estilo(fondo: _acento, caja: 'FFD9A404'));
  r.texto('G$fd', 'Rendición − Pago de Lista', nota);
  r.altos[fd] = 26;
  final pie = fd + 2;
  r.combinar('B$pie:G$pie');
  r.texto('B$pie',
      'Venue · $evento · $club · ${_fecha(fecha)} — cuenta únicamente a quienes ingresaron.',
      nota);

  // UNA HOJA POR TEAM
  for (final h in hojas) {
    final g = h.team;
    final w = libro.hoja(h.hoja, fijarFilas: 5);
    w.anchos.addAll({1: 2.5, 2: 30, 3: 13, 4: 13, 5: 17, 6: 17, 7: 17, 8: 2.5});
    w.combinar('B2:G2');
    w.texto('B2', g.nombre, const Estilo(tam: 18, negrita: true));
    w.altos[2] = 28;
    w.combinar('B3:G3');
    w.texto('B3',
        '${g.jefe.isEmpty ? '' : 'Jefe: ${g.jefe}  ·  '}$evento  ·  $club  ·  ${_fecha(fecha)}',
        const Estilo(tam: 10, color: _suave));
    w.enlace('B4', '‹  Volver al Resumen', 'Resumen!A1', const Estilo(tam: 10, color: _azul));
    w.texto('B5', 'Relacionador', cab('left'));
    w.texto('C5', 'Prepagadas', cab('center'));
    w.texto('D5', 'Lista', cab('center'));
    w.texto('E5', 'Importe prepago', cab('right'));
    w.texto('F5', 'Importe lista', cab('right'));
    w.texto('G5', 'Total', cab('right'));
    num tE = 0, tF = 0;
    for (var i = 0; i < g.rrpps.length; i++) {
      final p = g.rrpps[i];
      final f = 6 + i;
      final e = p.pre * d.precioManilla * d.pctLocal, fl = p.lis * d.precioLista * d.pctLocal;
      tE += e;
      tF += fl;
      w.texto('B$f', p.nombre, const Estilo(bordeAbajo: _linea));
      w.numero('C$f', p.pre,
          const Estilo(fondo: _verde, formato: _cant, alinear: 'center', bordeAbajo: _linea));
      w.numero('D$f', p.lis,
          const Estilo(fondo: _gris, formato: _cant, alinear: 'center', bordeAbajo: _linea));
      w.formula('E$f', 'C$f*Resumen!$pre*Resumen!$pct', e,
          const Estilo(formato: _bs, alinear: 'right', bordeAbajo: _linea));
      w.formula('F$f', 'D$f*Resumen!$lis*Resumen!$pct', fl,
          const Estilo(formato: _bs, alinear: 'right', bordeAbajo: _linea));
      w.formula('G$f', 'E$f+F$f', e + fl,
          const Estilo(formato: _bs, alinear: 'right', bordeAbajo: _linea));
    }
    final ult = 6 + (g.rrpps.isEmpty ? 1 : g.rrpps.length) - 1, tf = ult + 1;
    w.texto('B$tf', 'TOTAL ${g.nombre}', tot('left'));
    w.formula('C$tf', 'SUM(C6:C$ult)', g.prepagadas, tot('center', _cant));
    w.formula('D$tf', 'SUM(D6:D$ult)', g.lista, tot('center', _cant));
    w.formula('E$tf', 'SUM(E6:E$ult)', tE, tot('right', _bs));
    w.formula('F$tf', 'SUM(F6:F$ult)', tF, tot('right', _bs));
    w.formula('G$tf', 'SUM(G6:G$ult)', tE + tF, tot('right', _bs));
    w.texto('B${tf + 2}',
        'Importes = parte del local (cantidad × precio × %). Solo ingresados.', nota);
  }
  return libro;
}

/// Pide la contabilidad al servidor, arma el libro y abre la hoja de
/// compartir. Lanza el error del servidor si la cuenta no está autorizada.
Future<void> compartirContabilidad(SupabaseClient sb, Evento ev, String club) async {
  final data = Map<String, dynamic>.from(
      await sb.rpc('contabilidad_evento', params: {'p_evento': ev.id}) as Map);
  // precio de la lista "Compra en puerta" (se reconoce por el nombre)
  final ls = await sb.from('lista_tipos').select('nombre, precio').eq('evento_id', ev.id);
  final lp = ls
      .where((l) => RegExp('puerta', caseSensitive: false).hasMatch(l['nombre'] as String? ?? ''))
      .firstOrNull;
  final d = DatosContables.desde(data, lp?['precio'] as num? ?? 0);
  final f = '${ev.fecha.day.toString().padLeft(2, '0')}-${ev.fecha.month.toString().padLeft(2, '0')}-${ev.fecha.year}';
  final suf = d.alcance == 'team' && d.teamNombre != null ? '_${d.teamNombre}' : '';
  final archivo = File(
      '${Directory.systemTemp.path}/Contabilidad_$club${suf}_$f.xlsx'.replaceAll(' ', '_'));
  await archivo.writeAsBytes(construirLibro(ev.nombre, ev.fecha, club, d).bytes());
  await SharePlus.instance.share(ShareParams(files: [
    XFile(archivo.path,
        mimeType: 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet'),
  ]));
}
