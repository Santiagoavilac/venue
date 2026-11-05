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
| 1.7 | `client_key` en `aftr_comprar` y `aftr_reservar_mesa` | ok `20261106110000` |
| 1.8 | Techo a la recarga de PULSE | ok `20261106110000` |

**Fase 1 cerrada.**

## Fase 2 · Cerrar los datos

| # | Qué | Estado |
|---|-----|--------|
| 2.1 | El feed anónimo deja de devolver uid y rutas | ok `20261106120000` |
| 2.2 | Clave opaca (`media_key`, `foto_key`) y firma en lote | ok `20261106120000` |
| 2.3 | `aftr_buscar_usuario` escapa, exige 3 letras y tiene límite | ok `20261106130000` |
| 2.4 | Límites de uso en una pieza sola | ok `20261106130000` |
| 2.5 | Topes en `aftr_historias`, `aftr_eventos` y `aftr_calor` | — |

## Fases 3 a 9

Sin empezar. El orden del plan es el orden de trabajo: primero la plata,
después los datos, después la experiencia.

## Anotado para las fases que siguen

- El límite de `aftr_reventa` (iniciar orden) va en la Fase 3, que reescribe ese
  despachador entero: ponerlo ahora obligaría a tocarlo dos veces.
- El límite por IP de subida de medios va en la Fase 4.1, con el resto de lo de
  la Edge Function.

## Lo que falta cerrar cuando caigan las apps viejas

- `impl.social_historia_json` todavía manda `storage_path` y `foto_archivo` a
  quien tiene sesión, porque las versiones publicadas firman el archivo por su
  cuenta con esa ruta. Al visitante anónimo -por donde se enumeraban los uid- ya
  no se las manda. Se saca del todo cuando esas versiones caigan.
- Las políticas `social_archivo_leer` y `aftr_foto_leer` de storage siguen
  abiertas a los clientes por lo mismo. Sin la ruta no se pueden usar, así que
  no filtran nada por sí solas.

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
- Dos compras con la misma `client_key` devuelven el mismo pedido (una sola fila);
  sin clave siguen siendo dos, como antes; con la misma clave y otra cantidad
  avisa en vez de devolver el pedido viejo. Recarga de Bs 3.000 rechazada, Bs 50
  aceptada. Probado contra la base real con la sesión del cliente, en una
  transacción que vuelve atrás.
- `node --test tests/*.test.mjs`: 17 pruebas de la web, dos nuevas del aviso de
  pago tardío.
- `tests/rpc_con_guarda.py` medía mal el cuerpo de cada función (cortaba en el
  próximo `$$;` del archivo, no en su propia comilla), así que una RPC sin
  control podía parecer que lo tenía leyendo el cuerpo de la de abajo. Arreglado:
  aparecieron diez, todas con control real (seis sólo `service_role`, dos que
  delegan en la compra, y `venue_avanzar_pedido`/`venue_pedidos_mesa` que usan
  `impl.aftr_bar_staff`, que faltaba en la lista de señales).
- `curl` sin sesión contra `aftr_historias`: ya no vuelven `autor_id`,
  `storage_path` ni `foto_archivo`; vuelven `media_key`, `foto_key` y `grupo`
  (un md5 del uid, estable y que no dice quién es). Los únicos uuid del feed son
  los de la historia, el evento y las dos claves.
- `curl` sin sesión a `historias-media` con `accion: firmar`: devuelve las dos
  URL firmadas, de los dos buckets, en una sola llamada. Es la primera vez que
  un visitante sin cuenta puede ver una historia y una foto de perfil: la
  política de lectura de storage llama a `es_platform_admin()`, que `anon` no
  puede ejecutar.
- Publicar con el archivo ya movido a `h/<uuid>`: la historia guarda la ruta
  opaca, el cliente sigue mandando la ruta que subió, y esa ruta vieja ya no se
  puede reusar. Probado contra la base real en una transacción que vuelve atrás.
- `aftr_mobile`: 25 pruebas (cinco nuevas del agrupador de firmas: una sola
  llamada por tanda, caché por clave, los fallos no se cachean, la firma se da
  por vencida al 80 % del plazo y un error de red no deja a nadie esperando).
- `venue_mobile`: `flutter analyze` sin advertencias -quedaban seis locales sin
  usar en el perfil del relacionador y la miniatura del comprobante sin pintar,
  de la reestructuración de la UI- y 148 pruebas en verde.
- `aftr_buscar_usuario('%%')` y `('___')` devuelven vacío; con dos letras,
  vacío; a la búsqueda 30 del minuto corta con el mensaje. Con veinte intentos
  de compra anotados, `aftr_comprar` corta con su mensaje. La limpieza borra lo
  de hace dos días y deja lo de hoy. Todo contra la base real, en transacciones
  que vuelven atrás.
- Edge Function `baneco` desplegada: era obligatorio, porque ahora una orden
  puede tener más de un QR y el `maybeSingle()` anterior habría fallado.

## Pendiente de decidir con Santiago

- `exige_comprobante` quedó prendido en los boliches `bt`. Las apps de Venue ya
  publicadas no mandan el comprobante, así que hasta que el equipo actualice no
  pueden vender entradas con precio. Se puede apagar por boliche desde Ajustes.
