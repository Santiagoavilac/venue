import 'package:flutter_test/flutter_test.dart';
import 'package:venue_mobile/features/guestlists/data/listas.dart';
import 'package:venue_mobile/features/tickets/data/entradas.dart';
import 'package:venue_mobile/features/tickets/data/ticket_imagen.dart';
import 'package:venue_mobile/features/tickets/ui/entradas_screen.dart';
import 'package:venue_mobile/features/guestlists/ui/listas_screen.dart';
import 'package:venue_mobile/features/access_control/ui/accesos_screen.dart';
import 'package:venue_mobile/features/clubs/data/clubs.dart';
import 'package:venue_mobile/features/access_control/data/qr.dart';

void main() {
  test('separar nombres: líneas, comas y el "+N" se descarta', () {
    expect(separarNombres('Ana Paz\n Jorge Vaca ,Luis +2\n\n'),
        ['Ana Paz', 'Jorge Vaca', 'Luis']);
    expect(separarNombres('  \n , '), isEmpty);
  });

  test('lista abierta según su ventana de registro', () {
    final l = ListaTipo.desde({
      'id': 'l1', 'nombre': 'Free',
      'registro_desde': '2026-10-13T12:00:00Z',
      'registro_hasta': '2026-10-13T20:00:00Z',
      'ingreso_hasta': '00:30:00',
    });
    expect(l.abierta(DateTime.utc(2026, 10, 13, 11).toLocal()), isFalse);
    expect(l.abierta(DateTime.utc(2026, 10, 13, 15).toLocal()), isTrue);
    expect(l.abierta(DateTime.utc(2026, 10, 13, 21).toLocal()), isFalse);
    expect(l.ingresoHasta, '00:30');
    expect(ListaTipo.desde({'id': 'x', 'nombre': 'y'}).abierta(DateTime.now()), isTrue);
  });

  test('el QR que genera la app lo entiende el escáner', () {
    const ev = 'c4405f20-e8c7-46a4-b431-a40b27844d56';
    final e = QrLeido.interpretar(payloadEntrada(ev, 'QHXNG5PZK6'))!;
    expect((e.codigo, e.esLista, e.eventoId), ('QHXNG5PZK6', false, ev));
    final l = QrLeido.interpretar(payloadLista(ev, 'RS7JHPB2H4'))!;
    expect((l.codigo, l.esLista), ('RS7JHPB2H4', true));
  });

  test('entrada e invitado desde el servidor', () {
    final e = Entrada.desde({'id': '1', 'code': 'ABC', 'cliente': 'Ana', 'precio': 100, 'estado': 'valida'});
    expect(e.valida, isTrue);
    final i = Invitado.desde({'id': 'r', 'lista_tipo_id': 'l', 'nombre': 'Luis', 'rrpp_id': 'u', 'ingreso_at': '2026-10-13T23:00:00Z'});
    expect(i.ingreso, isTrue);
    expect(i.codigo, isNull);
  });

  test('el ticket se dibuja como PNG, con y sin sello de fase y marco', () async {
    TestWidgetsFlutterBinding.ensureInitialized();
    const base = TicketDatos(
      payload: 'EVT:ev:ABC123', codigo: 'ABC123', cliente: 'Carlos Roca',
      boliche: 'Aurora Club', evento: 'Noche Aurora', fecha: 'mar 13 oct',
      tipo: 'Entrada prepagada',
    );
    final png = await dibujarTicket(base);
    expect(png.sublist(0, 4), [0x89, 0x50, 0x4E, 0x47]); // firma PNG
    final conSello = await dibujarTicket(const TicketDatos(
      payload: 'EVT:ev:ABC123', codigo: 'ABC123', cliente: 'Carlos Roca',
      boliche: 'Aurora Club', evento: 'Noche Aurora', fecha: 'mar 13 oct',
      tipo: 'Hot Tickets', fase: 'Hot Tickets', oro: true,
    ));
    expect(conSello.length, isNot(png.length));
    expect(base.mensaje, contains('Presentá este QR en puerta'));
  });

  test('ventana de venta: antes, dentro y después', () {
    final d = DateTime(2026, 10, 13, 18), h = DateTime(2026, 10, 13, 23);
    expect(motivoVentaCerrada((desde: d, hasta: h), DateTime(2026, 10, 13, 17)),
        startsWith('La venta abre'));
    expect(motivoVentaCerrada((desde: d, hasta: h), DateTime(2026, 10, 13, 20)), isNull);
    expect(motivoVentaCerrada((desde: d, hasta: h), DateTime(2026, 10, 14, 0)),
        startsWith('La venta cerró'));
    expect(motivoVentaCerrada((desde: null, hasta: null), DateTime.now()), isNull);
  });

  test('fase: cuántas quedan', () {
    expect(Fase.desde({'id': 'f', 'nombre': 'Hot', 'precio': 90, 'cupo': 30, 'vendidas': 28}).quedan, 2);
    expect(Fase.desde({'id': 'f', 'nombre': 'F2', 'precio': 150}).quedan, isNull);
  });

  test('permisos sobre un invitado según el rol', () {
    Invitado inv(String rrpp, {bool entro = false}) => Invitado(
        id: 'i', listaId: 'l', nombre: 'x', rrppId: rrpp,
        ingresoAt: entro ? DateTime(2026) : null);
    PermisosLista per(Rol r, {bool tick = false}) => PermisosLista(
        rol: r, yo: 'yo', miTeam: 't1', puedeTickear: tick,
        teamDe: (u) => {'yo': 't1', 'companero': 't1', 'otro': 't2'}[u]);

    final rrpp = per(Rol.rrpp);
    expect(rrpp.mandar(inv('yo')), isTrue);
    expect(rrpp.mandar(inv('companero')), isFalse);
    expect(rrpp.quitar(inv('companero')), isFalse);
    expect(rrpp.tickea, isFalse);

    final jefe = per(Rol.jefe, tick: true);
    expect(jefe.mandar(inv('companero')), isTrue);   // su team
    expect(jefe.mandar(inv('otro')), isFalse);
    expect(jefe.quitar(inv('companero')), isFalse);  // no borra ajenos
    expect(jefe.tickea, isFalse);                     // tickear en Listas es del admin

    final admin = per(Rol.admin, tick: true);
    expect(admin.mandar(inv('otro')), isTrue);
    expect(admin.quitar(inv('otro')), isTrue);
    expect(admin.tickea, isTrue);
    expect(per(Rol.admin).tickea, isFalse);           // sin puede_tickear
    expect(admin.generarQr(inv('otro', entro: true)), isFalse);

    expect(per(Rol.portero).anota, isFalse);
  });

  test('historial: une listas y entradas, lo más reciente primero', () {
    final h = armarHistorial([
      Invitado(id: '1', listaId: 'l', nombre: 'Ana', rrppId: 'u', rrppNombre: 'Mateo', ingresoAt: DateTime(2026, 10, 13, 22)),
      const Invitado(id: '2', listaId: 'l', nombre: 'No vino', rrppId: 'u'),
    ], [
      Entrada(id: 'e', codigo: 'A', cliente: 'Luis', precio: 100, estado: 'usada', usedAt: DateTime(2026, 10, 13, 23)),
      const Entrada(id: 'f', codigo: 'B', cliente: 'Sin usar', precio: 100, estado: 'valida'),
    ], {'l': 'Invitados'});
    expect(h.map((i) => '${i.nombre}/${i.categoria}'), ['Luis/Entradas', 'Ana/Invitados']);
  });
}
