import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';

/// Escritor mínimo de libros .xlsx (SpreadsheetML).
///
/// Hace exactamente lo que necesita el libro contable: texto, números,
/// fórmulas CON su valor ya calculado, formatos, colores, bordes, celdas
/// combinadas, anchos, hipervínculos internos y paneles fijos.
///
/// Las fórmulas llevan el valor calculado porque el visor del teléfono
/// (Vista rápida, WhatsApp) no recalcula: sin eso mostraría ceros.

String _x(String s) => s
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;');

/// A1 → (columna, fila) y viceversa.
String col(int n) {
  var s = '';
  while (n > 0) {
    n--;
    s = String.fromCharCode(65 + n % 26) + s;
    n ~/= 26;
  }
  return s;
}

int _colDe(String ref) {
  var n = 0;
  for (final c in ref.codeUnits) {
    if (c < 65 || c > 90) break;
    n = n * 26 + (c - 64);
  }
  return n;
}

int _filaDe(String ref) => int.parse(ref.replaceAll(RegExp('[A-Z]'), ''));

class Estilo {
  const Estilo({
    this.tam = 11, this.negrita = false, this.color = 'FF1F2933', this.fondo,
    this.formato, this.alinear = 'left', this.bordeAbajo, this.bordeArriba,
    this.caja, this.grueso = false,
  });
  final double tam;
  final bool negrita;
  final String color;
  final String? fondo;

  /// Código de formato numérico de Excel, p. ej. `"Bs" #,##0.00`.
  final String? formato;
  final String alinear;
  final String? bordeAbajo, bordeArriba, caja;
  final bool grueso;

  String get _fuente => '$tam|$negrita|$color';
  String get _borde => '$bordeAbajo|$bordeArriba|$caja|$grueso';
  String get _clave => '$_fuente|$fondo|$formato|$alinear|$_borde';
}

class _Celda {
  _Celda(this.valor, this.formula, this.estilo);
  final Object? valor; // String | num | null
  final String? formula;
  final Estilo estilo;
}

class Hoja {
  Hoja(this.nombre, {this.fijarFilas = 0, this.horizontal = false});
  final String nombre;
  final int fijarFilas;
  final bool horizontal;
  final _celdas = <String, _Celda>{};
  final _combinadas = <String>[];
  final _links = <String, String>{};
  final anchos = <int, double>{};
  final altos = <int, double>{};

  void texto(String ref, String v, [Estilo e = const Estilo()]) =>
      _celdas[ref] = _Celda(v, null, e);
  void numero(String ref, num v, [Estilo e = const Estilo()]) =>
      _celdas[ref] = _Celda(v, null, e);

  /// [valor] es el resultado ya calculado de la fórmula.
  void formula(String ref, String f, num valor, [Estilo e = const Estilo()]) =>
      _celdas[ref] = _Celda(valor, f, e);
  void estilo(String ref, Estilo e) => _celdas[ref] ??= _Celda(null, null, e);
  void combinar(String rango) => _combinadas.add(rango);

  /// Enlace a otra hoja del mismo libro.
  void enlace(String ref, String texto, String destino, [Estilo e = const Estilo()]) {
    _celdas[ref] = _Celda(texto, null, e);
    _links[ref] = destino;
  }

  Object? valorDe(String ref) => _celdas[ref]?.valor;
  String? formulaDe(String ref) => _celdas[ref]?.formula;
}

class Libro {
  final hojas = <Hoja>[];
  Hoja hoja(String nombre, {int fijarFilas = 0, bool horizontal = false}) {
    final h = Hoja(nombre, fijarFilas: fijarFilas, horizontal: horizontal);
    hojas.add(h);
    return h;
  }

  /// Partes XML del libro (ruta → contenido). Separado de [bytes] para
  /// poder inspeccionarlo en los tests.
  Map<String, String> partes() {
    final fuentes = <String>[], rellenos = <String?>[null], bordes = <String>['null|null|null|false'];
    final formatos = <String>[], xfs = <String>[], indice = <String, int>{};
    final fuenteDe = <String, Estilo>{}, bordeDe = <String, Estilo>{};
    int est(Estilo e) => indice.putIfAbsent(e._clave, () {
          var f = fuentes.indexOf(e._fuente);
          if (f < 0) {
            fuentes.add(e._fuente);
            fuenteDe[e._fuente] = e;
            f = fuentes.length - 1;
          }
          var r = 0;
          if (e.fondo != null) {
            r = rellenos.indexOf(e.fondo);
            if (r < 0) {
              rellenos.add(e.fondo);
              r = rellenos.length - 1;
            }
          }
          var b = bordes.indexOf(e._borde);
          if (b < 0) {
            bordes.add(e._borde);
            bordeDe[e._borde] = e;
            b = bordes.length - 1;
          }
          var n = 0;
          if (e.formato != null) {
            var k = formatos.indexOf(e.formato!);
            if (k < 0) {
              formatos.add(e.formato!);
              k = formatos.length - 1;
            }
            n = 164 + k;
          }
          // fillId: 0 = ninguno, 1 = gris125 (reservado), los propios desde 2
          xfs.add('<xf numFmtId="$n" fontId="$f" fillId="${r == 0 ? 0 : r + 1}" borderId="$b" xfId="0" '
              'applyFont="1" applyFill="1" applyBorder="1" applyNumberFormat="1" applyAlignment="1">'
              '<alignment horizontal="${e.alinear}" vertical="center"/></xf>');
          return xfs.length - 1;
        });

    final p = <String, String>{};
    for (var i = 0; i < hojas.length; i++) {
      final h = hojas[i];
      final filas = <int, List<String>>{};
      for (final ref in h._celdas.keys) {
        filas.putIfAbsent(_filaDe(ref), () => []).add(ref);
      }
      final b = StringBuffer(
          '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
          '<worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" '
          'xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">'
          '<sheetViews><sheetView showGridLines="0" workbookViewId="0">');
      if (h.fijarFilas > 0) {
        b.write('<pane ySplit="${h.fijarFilas}" topLeftCell="A${h.fijarFilas + 1}" '
            'activePane="bottomLeft" state="frozen"/>');
      }
      b.write('</sheetView></sheetViews><sheetFormatPr defaultRowHeight="15"/>');
      if (h.anchos.isNotEmpty) {
        b.write('<cols>');
        for (final a in (h.anchos.entries.toList()..sort((x, y) => x.key.compareTo(y.key)))) {
          b.write('<col min="${a.key}" max="${a.key}" width="${a.value}" customWidth="1"/>');
        }
        b.write('</cols>');
      }
      b.write('<sheetData>');
      for (final f in filas.keys.toList()..sort()) {
        final alto = h.altos[f];
        b.write('<row r="$f"${alto == null ? '' : ' ht="$alto" customHeight="1"'}>');
        for (final ref in filas[f]!..sort((x, y) => _colDe(x).compareTo(_colDe(y)))) {
          final c = h._celdas[ref]!;
          final s = est(c.estilo);
          if (c.formula != null) {
            b.write('<c r="$ref" s="$s"><f>${_x(c.formula!)}</f><v>${c.valor}</v></c>');
          } else if (c.valor is num) {
            b.write('<c r="$ref" s="$s"><v>${c.valor}</v></c>');
          } else if (c.valor is String) {
            b.write('<c r="$ref" s="$s" t="inlineStr"><is><t xml:space="preserve">${_x(c.valor as String)}</t></is></c>');
          } else {
            b.write('<c r="$ref" s="$s"/>');
          }
        }
        b.write('</row>');
      }
      b.write('</sheetData>');
      if (h._combinadas.isNotEmpty) {
        b.write('<mergeCells count="${h._combinadas.length}">'
            '${h._combinadas.map((m) => '<mergeCell ref="$m"/>').join()}</mergeCells>');
      }
      if (h._links.isNotEmpty) {
        b.write('<hyperlinks>${h._links.entries.map((l) => '<hyperlink ref="${l.key}" location="${_x(l.value)}" display="${_x(h._celdas[l.key]!.valor as String)}"/>').join()}</hyperlinks>');
      }
      b.write('<pageMargins left="0.5" right="0.5" top="0.6" bottom="0.6" header="0.3" footer="0.3"/>'
          '<pageSetup paperSize="9" orientation="${h.horizontal ? 'landscape' : 'portrait'}" fitToHeight="0"/>'
          '</worksheet>');
      p['xl/worksheets/sheet${i + 1}.xml'] = b.toString();
    }

    String borde(String? c, String tag, bool grueso) => c == null
        ? '<$tag/>'
        : '<$tag style="${grueso ? 'medium' : 'thin'}"><color rgb="$c"/></$tag>';
    p['xl/styles.xml'] = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<styleSheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">'
        '${formatos.isEmpty ? '' : '<numFmts count="${formatos.length}">${[for (var i = 0; i < formatos.length; i++) '<numFmt numFmtId="${164 + i}" formatCode="${_x(formatos[i])}"/>'].join()}</numFmts>'}'
        '<fonts count="${fuentes.length}">${fuentes.map((f) {
      final e = fuenteDe[f]!;
      return '<font>${e.negrita ? '<b/>' : ''}<sz val="${e.tam}"/><color rgb="${e.color}"/><name val="Calibri"/></font>';
    }).join()}</fonts>'
        '<fills count="${rellenos.length + 1}"><fill><patternFill patternType="none"/></fill>'
        '<fill><patternFill patternType="gray125"/></fill>'
        '${rellenos.skip(1).map((r) => '<fill><patternFill patternType="solid"><fgColor rgb="$r"/></patternFill></fill>').join()}</fills>'
        '<borders count="${bordes.length}">${bordes.map((k) {
      final e = bordeDe[k];
      if (e == null) return '<border><left/><right/><top/><bottom/><diagonal/></border>';
      final c = e.caja;
      return '<border>${borde(c, 'left', false)}${borde(c, 'right', false)}'
          '${borde(c ?? e.bordeArriba, 'top', false)}${borde(c ?? e.bordeAbajo, 'bottom', e.grueso)}<diagonal/></border>';
    }).join()}</borders>'
        '<cellStyleXfs count="1"><xf numFmtId="0" fontId="0" fillId="0" borderId="0"/></cellStyleXfs>'
        '<cellXfs count="${xfs.length}">${xfs.join()}</cellXfs>'
        '<cellStyles count="1"><cellStyle name="Normal" xfId="0" builtinId="0"/></cellStyles>'
        '</styleSheet>';

    p['xl/workbook.xml'] = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" '
        'xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">'
        '<sheets>${[for (var i = 0; i < hojas.length; i++) '<sheet name="${_x(hojas[i].nombre)}" sheetId="${i + 1}" r:id="rId${i + 1}"/>'].join()}</sheets>'
        '<calcPr calcId="0" fullCalcOnLoad="1"/></workbook>';
    p['xl/_rels/workbook.xml.rels'] = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
        '${[for (var i = 0; i < hojas.length; i++) '<Relationship Id="rId${i + 1}" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet${i + 1}.xml"/>'].join()}'
        '<Relationship Id="rId${hojas.length + 1}" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/>'
        '</Relationships>';
    p['_rels/.rels'] = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
        '<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/>'
        '</Relationships>';
    p['[Content_Types].xml'] = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">'
        '<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>'
        '<Default Extension="xml" ContentType="application/xml"/>'
        '<Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/>'
        '<Override PartName="/xl/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.styles+xml"/>'
        '${[for (var i = 0; i < hojas.length; i++) '<Override PartName="/xl/worksheets/sheet${i + 1}.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/>'].join()}'
        '</Types>';
    return p;
  }

  Uint8List bytes() {
    final a = Archive();
    partes().forEach((ruta, xml) {
      final d = utf8.encode(xml);
      a.addFile(ArchiveFile(ruta, d.length, d));
    });
    return Uint8List.fromList(ZipEncoder().encode(a));
  }
}
