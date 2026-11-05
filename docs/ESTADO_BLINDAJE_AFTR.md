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
| 2.5 | Topes en `aftr_historias`, `aftr_eventos` y `aftr_calor` | ok `20261106140000` |

**Fase 2 cerrada**, menos lo que quedó anotado abajo para su propia fase.

## Fase 3 · El marketplace, blindado

| # | Qué | Estado |
|---|-----|--------|
| 3.1 | La plataforma fija las reglas, el boliche prende y apaga | ok `20261106150000` |
| 3.2 | El vendedor acepta primero | ok `20261106150000` |
| 3.3 | La oferta reservada sigue en el mercado, con "vuelve en N min" | ok `20261106150000` |
| 3.4 | El techo contra lo que se pagó (`precio_base`) | ok `20261106150000` |
| 3.5 | La sesión se exige arriba, no por el orden de los `if` | ok `20261106150000` |
| 3.6 | Lo que no se toca, con pruebas nuevas | ok (33 pruebas) |

**Fase 3 cerrada.**

Sobre 3.5: el plan decía partir `aftr_reventa` en dos funciones. Se hizo de otra
forma -la sesión se exige arriba, con la lista de acciones públicas- porque
partirla rompería las apps publicadas, que llaman `aftr_reventa('mercado')` sin
sesión. El agujero que el plan señalaba (un `p_accion` nuevo puesto arriba abre
todo) queda cerrado igual, y sin depender del orden.

## Fase 4 · El borde: funciones, archivos y la web

| # | Qué | Estado |
|---|-----|--------|
| 4.1 | `historias-media` con su propio secreto, comparación en tiempo constante y límite por IP | ok |
| 4.2 | Los bytes se validan, no el nombre (`aftr-p2p` y `aftr-perfiles`) | ok |
| 4.3 | CORS acotado, CSP, cabeceras y SRI en los tres CDN | ok |
| 4.4 | Nonce por intento en Google | ok |

**Fase 4 cerrada**, con dos cosas dichas de frente:

- `crear-usuario` sigue con `CORS *`. No se toca porque no sé desde qué dominio
  la llama la web de Venue, y acotarla a ciegas la dejaría sin poder crear
  cuentas. Hay que confirmar el dominio y agregarlo a la misma lista.
- La CSP deja `style-src 'unsafe-inline'`: los templates de la web arman
  estilos en línea en casi cien lugares y sacarlos es otro trabajo. Lo que sí
  quedó cerrado es `script-src` sin `'unsafe-inline'`, que es lo que hace que un
  XSS no pueda ejecutar nada; por eso en los templates ya no hay ni un
  `onclick=` ni un `onload=`.
- Los tres scripts de CDN quedaron con SRI y versión fija en vez de bajados a
  `vendor/`: con el hash, un CDN comprometido no puede inyectar nada, y la
  página no carga un megabyte más del repo.

## Fase 5 · Las incidencias, con pantalla

Hecho, `20261106170000`. Dos RPC -listar y resolver- y un panel en Venue con el
contador en el menú lateral: quién pagó, cuánto, cuándo, qué dijo el banco, y
tres salidas (emitir, devolver, cerrar) más el botón para escribirle. Siempre
con una nota, que queda con el nombre de quien la escribió.

El permiso se comprueba adentro en vez de entrar por la matriz de `db/19` como
decía el plan: la matriz se genera con un bloque `do` de cien líneas que vive en
un archivo de historia, y copiarlo a una migración para dos funciones es justo
lo que se desincroniza después. Son dos de las 98 que ya comprueban adentro, y
`tests/rpc_con_guarda.py` las ve igual. El portero y el jefe quedan afuera:
probado con los dos contra la base real.

## Fase 6 · Listas y puerta (Venue)

| # | Qué | Estado |
|---|-----|--------|
| 6.1 | Los cupos, sólo de quien corresponde | ok (ya lo estaba; probado) |
| 6.2 | Inhabilitar el QR de un invitado | ok `20261106180000` |
| 6.3 | Buscador dentro del escáner | ok |

**6.1 no necesitaba arreglo, y eso se probó en vez de suponerlo.** Con la sesión
de un relacionador de burtown, contra la base real: `jefe_fijar_cupos` contesta
"Solo para jefes de team"; un `insert` directo en `cupo_rrpp` con el rol
`authenticated` choca contra la política de RLS; y un `update` de
`lista_tipos.cupo_por_rrpp` no toca ninguna fila -el cupo queda en 10-. El admin
sí fija el cupo general de la lista y el de cada persona, que es lo que el plan
pedía para los boliches sin jefes, y ya estaba en la pantalla de gestión.

## Fases 7 a 9

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
- `aftr_eventos` con el rango `1900-01-01 → 2100-01-01` devuelve sólo los días
  que la app muestra; `aftr_historias` con un `p_datos` de 20 KB contesta "Datos
  no válidos"; `aftr_calor` sale de la caché y coincide con el cálculo en vivo.
- `tests/social_database_test.py` sobre PostgreSQL descartable: 33 pruebas en
  verde, siete nuevas -los datos de cobro no salen hasta que el vendedor acepta
  (ni al comprador ni al vendedor), el rechazo devuelve la entrada al mercado,
  una sola operación abierta por comprador, no se insiste sobre la misma oferta,
  el tope diario cuenta las que no salieron, sólo la plataforma escribe la
  política, y la oferta en operación sigue en el mercado con su `vuelve_at`-. Y
  `test_17` cambió de sentido: el techo ahora se mide contra lo que pagó quien
  revende, no contra el precio original de siempre.
- El mismo flujo probado además contra la base real en una transacción que
  vuelve atrás, con dos cuentas.
- `curl` con `Origin: https://malicioso.example` contra las dos Edge Functions:
  no vuelve `Access-Control-Allow-Origin`; con el dominio propio, sí. `revisar`
  sin sesión contesta "Iniciá sesión"; `firmar` sin sesión sigue andando, que es
  para lo que existe.
- 32 pruebas de la Edge Function del banco (una nueva de CORS) y 7 del
  validador de medios (dos nuevas: un HTML, un .exe, un PDF y un GIF no pasan
  como comprobante, y un video no sirve de foto de perfil).
- El ciclo completo de una incidencia, contra la base real en una transacción
  que vuelve atrás: un pago tardío por el camino de verdad deja la incidencia
  con su monto y su transacción, el admin la ve con el nombre de quien pagó, la
  resuelve emitiendo (una entrada, orden confirmada), el contador baja a cero y
  un segundo intento de resolverla avisa que ya se resolvió. El portero y el
  jefe reciben "Solo el administrador del boliche ve los cobros a resolver".
- `venue_mobile`: 153 pruebas, cinco nuevas del panel de incidencias.
- El ciclo del QR de invitado, contra la base real en una transacción que
  vuelve atrás: el relacionador recibe "No autorizado"; el portero lo
  inhabilita con motivo; la puerta contesta `anulada` **sin consumir el
  ingreso** (`ingreso_at` sigue vacío, que era la trampa: si se consumía, la
  persona quedaba marcada como que entró); el buscador lo muestra con el
  motivo; y al volver a habilitarlo la puerta dice `valida` otra vez.
- `venue_mobile`: 156 pruebas, tres nuevas del QR inhabilitado.
- Edge Function `baneco` desplegada: era obligatorio, porque ahora una orden
  puede tener más de un QR y el `maybeSingle()` anterior habría fallado.

## Pendiente de decidir con Santiago

- `exige_comprobante` quedó prendido en los boliches `bt`. Las apps de Venue ya
  publicadas no mandan el comprobante, así que hasta que el equipo actualice no
  pueden vender entradas con precio. Se puede apagar por boliche desde Ajustes.
