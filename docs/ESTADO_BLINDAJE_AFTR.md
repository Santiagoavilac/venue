# Estado · Blindar AFTR

Avance de `docs/PLAN_BLINDAJE_AFTR.md`. Se anota en el mismo commit que el
trabajo, para que si se pierde el contexto esto alcance para seguir.

Leyenda: `ok` hecho y verificado · `—` sin empezar.

## Fase 1 · Que no se pierda plata

| # | Qué | Estado |
|---|-----|--------|
| 1.1 | Único parcial en `pago_qr`: se puede pedir un QR nuevo | ok `20261106090000` |
| 1.2 | El cobro vive diez minutos (`limite_at`) | ok `20261106090000` |
| 1.3 | El pago tardío no emite: `revisar` + incidencia | ok `20261106100000` |
| 1.4 | El usuario se entera (tarjeta + WhatsApp 75028040) | ok app y web |
| 1.5 | Un solo camino para cancelar | ok `20261106090000` |
| 1.6 | Crones `aftr-vencer` y `aftr-mesas-vencer` | ok `20261106090000` |
| 1.7 | `client_key` en `aftr_comprar` y `aftr_reservar_mesa` | — |
| 1.8 | Techo a la recarga de PULSE | — |

## Fases 2 a 9

Sin empezar. El orden del plan es el orden de trabajo: primero la plata,
después los datos, después la experiencia.

## Verificado a mano

- Índices parciales vivos (3), uniques viejos borrados (0), `impl.aftr_mesas_vencer`
  existe, dos crones agendados, `baneco_reservar_destino` con los diez minutos,
  `aftr_cancelar_mi_orden` delegando en `aftr_cancelar_cobro` y `baneco_qr_anulado`
  liberando la mesa.
- `python3 tests/rpc_con_guarda.py`: ninguna RPC de `public` sin control.
- Pago tardío y a tiempo probados contra la base real dentro de una transacción
  que vuelve atrás: tarde deja 0 entradas, `revisar / PAGADO_FUERA_DE_PLAZO` e
  incidencia abierta con monto y transacción del banco; a tiempo emite y
  confirma la orden sin incidencia.
- `aftr_mobile`: `flutter analyze` sin errores y 21 pruebas en verde (dos nuevas
  del aviso de pago tardío). `node --check aftr_web/aftr.js`. 31 pruebas de la
  Edge Function, dos nuevas: un QR anulado no impide pedir otro, y el estado
  informa `limite` y `nota`.
- Edge Function `baneco` desplegada: era obligatorio, porque ahora una orden
  puede tener más de un QR y el `maybeSingle()` anterior habría fallado.

## Pendiente de decidir con Santiago

- `exige_comprobante` quedó prendido en los boliches `bt`. Las apps de Venue ya
  publicadas no mandan el comprobante, así que hasta que el equipo actualice no
  pueden vender entradas con precio. Se puede apagar por boliche desde Ajustes.
