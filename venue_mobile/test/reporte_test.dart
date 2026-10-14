import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:venue_mobile/features/analytics/data/contabilidad.dart';
import 'package:venue_mobile/features/analytics/data/reporte.dart';
import 'package:venue_mobile/features/analytics/data/xlsx.dart';

void main() {
  final cierre = Cierre.calcular(
    stats: [
      {'rrpp_id': 'a', 'rrpp': 'Mateo', 'team_id': 't', 'anotados': 10, 'ingresaron': 6,
        'entradas_vendidas': 5, 'entradas_usadas': 4, 'bruto_entradas': 400,
        'comision_rrpp': 60, 'comision_jefe': 20},
      {'rrpp_id': 'b', 'rrpp': 'Sin actividad', 'team_id': 't', 'anotados': 0, 'ingresaron': 0,
        'entradas_vendidas': 0, 'entradas_usadas': 0, 'bruto_entradas': 0,
        'comision_rrpp': 0, 'comision_jefe': 0},
    ],
    statsMesas: [
      {'rrpp_id': 'a', 'mesas_vendidas': 1, 'bruto_mesas': 900,
        'comision_rrpp_mesas': 60, 'comision_jefe_mesas': 20},
    ],
    bonos: [{'user_id': 'a', 'monto': 50}, {'user_id': 'a', 'monto': 25}],
    mesas: [
      {'precio': 900, 'combo_qty': 2, 'c': {'comision_rrpp': 60, 'comision_jefe': 20}},
    ],
    entradas: [
      {'precio': 100, 'estado': 'usada'}, {'precio': 100, 'estado': 'usada'},
      {'precio': 100, 'estado': 'valida'}, {'precio': 100, 'estado': 'anulada'},
    ],
    registros: [
      {'ingreso_at': '2026-10-13T23:00:00Z', 'lista_tipo_id': 'l1'},
      {'ingreso_at': null, 'lista_tipo_id': 'l1'},
      {'ingreso_at': null, 'lista_tipo_id': 'l2'},
    ],
    listas: {'l1': 'Invitados', 'l2': 'Free', 'l3': 'Vacía'},
  );

  test('cierre: totales reales y solo personas con actividad', () {
    expect(cierre.personas.map((p) => p.nombre), ['Mateo']);
    expect((cierre.entVendidas, cierre.entUsadas, cierre.entBruto), (3, 2, 200));
    expect((cierre.listaAnotados, cierre.listaIngresaron), (3, 1));
    expect((cierre.mesasN, cierre.mesasBruto, cierre.mesasComR, cierre.mesasComJ),
        (1, 900, 120, 40));
    expect(cierre.porLista.map((l) => '${l.nombre} ${l.ingresaron}/${l.anotados}'),
        ['Invitados 1/2', 'Free 0/1']);
    expect(cierre.bonos, 75);
    expect(cierre.personas.single.aPagar, 60 + 20 + 60 + 20 + 75);
  });

  test('cierre: comisiones y neto con la fórmula de la web', () {
    // comisiones de entradas (60+20) + de combos (120+40) + bonos (75)
    expect(cierre.comisionesTotal, 315);
    // (200 − 60 − 20) + 900 − 120 − 40 − 75
    expect(cierre.neto, 785);
    expect(textoCierre('Noche', 'Aurora', 'mar 13', cierre), contains('Para el boliche: 785 Bs'));
  });

  test('liquidación: 50 % de prepagadas + mesas netas − 50 % de compra en puerta', () {
    final l = liquidacion(
        brutoPrepagadasIngresadas: 1000, totalMesas: 740, puertaIngresaron: 4, puertaPrecio: 50);
    expect((l.prepagadas, l.mesas, l.puerta, l.total), (500, 740, 100, 1140));
    expect(liquidacion(brutoPrepagadasIngresadas: 0, totalMesas: 0, puertaIngresaron: 9, puertaPrecio: 0).total, 0);
  });

  final datos = DatosContables.desde({
    'alcance': 'total',
    'liq': {'precio_manilla': 100, 'por_manilla': 50, 'manillas_externas': 2},
    'filas': [
      {'team_id': 't1', 'team': 'Norte', 'jefe': 'Julián', 'rrpp': 'Mateo', 'prepagadas': 10, 'lista': 4},
      {'team_id': 't1', 'team': 'Norte', 'jefe': 'Julián', 'rrpp': 'Renata', 'prepagadas': 3, 'lista': 0},
      {'team_id': 't2', 'team': 'Team Sur', 'jefe': '', 'rrpp': 'Nico', 'prepagadas': 20, 'lista': 1},
      {'team_id': null, 'team': null, 'rrpp': 'Suelto', 'prepagadas': 0, 'lista': 2},
      {'team_id': 't1', 'team': 'Norte', 'rrpp': 'Sin actividad', 'prepagadas': 0, 'lista': 0},
    ],
  }, 40);

  test('contabilidad: agrupa por team, ordena y calcula igual que el libro', () {
    expect(datos.teams.map((t) => t.nombre), ['Team Sur', 'Team Norte', 'Sin team']);
    expect(datos.teams[1].rrpps.map((r) => r.nombre), ['Mateo', 'Renata']);
    expect(datos.pctLocal, .5);
    expect((datos.totalPrepagadas, datos.totalLista), (33, 7));
    expect(datos.rendicion, (33 - 2) * 100 * .5);      // 1550
    expect(datos.pagoDeLista, 7 * 40 * .5);            // 140
    expect(datos.totalADepositar, 1410);
  });

  test('libro: fórmulas vivas y valores ya calculados', () {
    final libro = construirLibro('Noche Aurora', DateTime(2026, 10, 13), 'Aurora Club', datos);
    expect(libro.hojas.map((h) => h.nombre), ['Resumen', 'Team Sur', 'Team Norte', 'Sin team']);
    final r = libro.hojas.first;
    expect(r.valorDe('B2'), 'Contabilidad Aurora Club');
    expect((r.valorDe('C9'), r.valorDe('D9'), r.valorDe('E9')), (100, 40, .5));
    expect(r.formulaDe('C13'), "SUM('Team Sur'!C6:C6)");
    expect(r.formulaDe('E13'), r'C13*$C$9*$E$9');
    expect(r.valorDe('E13'), 1000);
    // TOTAL en la fila 16 (3 teams), externos en 19, cierre desde 22
    expect(r.formulaDe('C16'), 'SUM(C13:C15)');
    expect(r.valorDe('C16'), 33);
    expect(r.valorDe('E19'), 2);
    expect(r.formulaDe('E22'), r'MAX(C16-E19,0)*$C$9*$E$9');
    expect(r.formulaDe('E23'), r'D16*$D$9*$E$9');
    expect(r.formulaDe('E25'), 'E22-E23');
    expect(r.valorDe('E25'), 1410);
    expect(r.valorDe('B25'), 'TOTAL A DEPOSITAR A AURORA CLUB');

    final norte = libro.hojas[2];
    expect(norte.valorDe('B6'), 'Mateo');
    expect(norte.formulaDe('E6'), r'C6*Resumen!$C$9*Resumen!$E$9');
    expect(norte.valorDe('G6'), 10 * 100 * .5 + 4 * 40 * .5);
    expect(norte.formulaDe('G8'), 'SUM(G6:G7)');
    expect(norte.valorDe('B3'), contains('Jefe: Julián'));
  });

  test('libro: es un .xlsx válido (zip con las partes y sus enlaces)', () async {
    final bytes = construirLibro('Noche & <Aurora>', DateTime(2026, 10, 13), 'Aurora', datos).bytes();
    final zip = ZipDecoder().decodeBytes(bytes);
    final nombres = zip.files.map((f) => f.name).toSet();
    expect(nombres, containsAll([
      '[Content_Types].xml', '_rels/.rels', 'xl/workbook.xml', 'xl/styles.xml',
      'xl/_rels/workbook.xml.rels', 'xl/worksheets/sheet1.xml', 'xl/worksheets/sheet4.xml',
    ]));
    final hoja1 = String.fromCharCodes(zip.findFile('xl/worksheets/sheet1.xml')!.content as List<int>);
    expect(hoja1, contains('<hyperlink ref="G13" location="&apos;Team Sur&apos;!A1"'.replaceAll('&apos;', "'")));
    expect(hoja1, contains('<mergeCell ref="B2:G2"/>'));
    expect(hoja1, contains('Noche &amp; &lt;Aurora&gt;'));
    await File('${Directory.systemTemp.path}/venue-prueba.xlsx').writeAsBytes(bytes);
  });

  test('nombres de hoja: sin caracteres prohibidos, máximo 31, sin repetir', () {
    final u = <String>{};
    expect(nombreDeHoja('Team A/B: [VIP]', u), 'Team A-B- -VIP-');
    expect(nombreDeHoja('x' * 40, u).length, 31);
    final a = nombreDeHoja('Team Norte', u), b = nombreDeHoja('team norte', u);
    expect((a, b), ('Team Norte', 'team norte (2)'));
  });

  test('columnas de Excel', () {
    expect([col(1), col(26), col(27), col(52)], ['A', 'Z', 'AA', 'AZ']);
  });
}
