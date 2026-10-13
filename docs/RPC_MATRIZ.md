# Matriz de permisos de las RPC

Generado desde `db/19-rpc-guardas.sql` (tabla `impl.rpc_permiso`), que es la fuente de verdad:
la misma tabla genera las guardas que corren en el servidor.

- **Alcance**: de qué entidad sale el boliche en el que se exige el rol.
- **Roles**: rol EFECTIVO en ese boliche (`rol_en_club`). `*` = cualquier rol del boliche.
- Ninguna RPC es ejecutable sin sesión.

## Lectura de evento

| Función | Alcance | Roles | Regla adicional |
| --- | --- | --- | --- |
| `liquidacion_evento` | evento | admin | plata del evento |
| `resumen_evento` | evento | admin, jefe, rrpp, portero |  |
| `reporte_fases` | evento | admin |  |
| `reporte_filtro` | evento | admin |  |
| `fases_evento` | evento | admin, jefe, rrpp |  |
| `fase_vigente` | evento | admin, jefe, rrpp |  |
| `cupos_fase` | fase | admin |  |
| `mis_cupos` | evento | admin, jefe, rrpp |  |
| `ventana_venta` | evento | admin, jefe, rrpp | el rrpp solo consulta la suya |
| `excepciones_venta` | evento | admin |  |
| `vendedores_posibles` | evento | admin, jefe, rrpp |  |
| `mis_permisos_mesa` | evento | admin, jefe, rrpp, portero |  |
| `buscar_registros` | evento | admin, jefe, rrpp, portero |  |
| `contabilidad_evento` | evento | admin, jefe | la función además exige contabilidad_total o ser jefe del team |

## Lectura por boliche

| Función | Alcance | Roles | Regla adicional |
| --- | --- | --- | --- |
| `teams_efectivos` | club | admin, jefe, rrpp, portero, caja |  |
| `roster_relacionadores` | club | admin, caja, portero |  |
| `roster_caja` | club | admin, caja, portero |  |
| `roster_cupos` | club | admin |  |
| `roster_mi_team` | club | admin, jefe, rrpp |  |
| `usuarios_sin_tope` | club | admin, jefe, rrpp, portero |  |
| `telefonos_equipo` | club | admin, jefe | dato personal: el jefe solo ve los teléfonos de su team |
| `historico_eventos` | club | admin |  |
| `ranking_rrpp` | club | admin |  |
| `avisos_pendientes` | club | * |  |
| `avisos_admin` | club | admin |  |
| `aviso_lectores` | aviso | admin |  |
| `marcar_aviso_visto` | aviso | * |  |

## Puerta

| Función | Alcance | Roles | Regla adicional |
| --- | --- | --- | --- |
| `validar_entrada` | evento | admin, portero | CONSUME la entrada · máx. 40 códigos inexistentes cada 5 min |
| `validar_qr_lista` | evento | admin, portero | marca el ingreso · máx. 40 códigos inexistentes cada 5 min |
| `descheckin_entrada` | evento | admin, portero |  |
| `marcar_filtro_entrada` | evento | admin, portero |  |
| `marcar_filtro_lista` | evento | admin, portero |  |
| `marcar_filtro_registro` | registro | admin, portero |  |
| `checkin_registro` | registro | admin, portero, jefe, rrpp | jefe/rrpp solo con puede_tickear (regla que ya tenía la UI) |
| `descheckin_registro` | registro | admin, portero, jefe, rrpp |  |

## Listas y entradas

| Función | Alcance | Roles | Regla adicional |
| --- | --- | --- | --- |
| `registrar_lista` | lista | admin, jefe, rrpp |  |
| `eliminar_registro` | registro | admin, jefe, rrpp | la función exige además ser quien lo anotó o admin |
| `heredar_cupos_lista` | lista | admin |  |
| `generar_qr_lista` | registro | admin, jefe, rrpp | el rrpp solo genera QR de sus invitados |
| `generar_qr_lista_masivo` | sesión | (interno) | la función ya filtra por rol/team registro por registro |
| `generar_entrada` | evento | admin, jefe, rrpp |  |
| `anular_entrada` | entrada | admin, jefe, rrpp | la función exige vendedor o admin |
| `eliminar_entrada` | entrada | admin, jefe, rrpp |  |

## Mesas

| Función | Alcance | Roles | Regla adicional |
| --- | --- | --- | --- |
| `vender_mesa` | mesa | admin, jefe, rrpp | bloquea la mesa: sin doble venta |
| `vender_mesa_grupo` | mesas | admin, jefe, rrpp | bloquea las mesas en orden: sin doble venta ni deadlock |
| `editar_mesa` | mesa | admin, jefe |  |
| `pagar_mesa` | mesa | admin, jefe, rrpp | el rrpp solo paga las mesas que vendió |
| `verificar_mesa` | mesa | admin | verificación de pago |
| `estado_mesa` | mesa | admin, jefe, rrpp | liberar/ocupar: admin, quien la vendió o el jefe de su team |
| `liberar_reservas_vencidas` | evento | admin, jefe, rrpp, portero | barrido automático al abrir Mesas |
| `heredar_mesas` | evento | admin |  |
| `copiar_mesas` | evento×2 | admin | admin en el boliche de AMBOS eventos |

## Pagos

| Función | Alcance | Roles | Regla adicional |
| --- | --- | --- | --- |
| `crear_pago` | evento | admin, jefe, rrpp |  |
| `estado_pago` | pago | admin | verificación de pago |
| `adjuntar_comprobante` | pago | admin, jefe, rrpp | la función exige dueño del pago o admin |

## Eventos y catálogo

| Función | Alcance | Roles | Regla adicional |
| --- | --- | --- | --- |
| `publicar_evento` | evento | admin |  |
| `eliminar_evento` | evento | admin | DESTRUCTIVA |
| `guardar_fase` | evento | admin |  |
| `borrar_fase` | fase | admin |  |
| `fase_arte` | fase | admin |  |
| `guardar_cupo_team` | fase | admin |  |
| `set_venta_por_fases` | evento | admin |  |
| `set_manillas_externas` | evento | admin |  |

## Equipo

| Función | Alcance | Roles | Regla adicional |
| --- | --- | --- | --- |
| `eliminar_usuario` | usuario | admin de todos sus boliches | DESTRUCTIVA |
| `eliminar_team` | team | admin de todos sus boliches | DESTRUCTIVA |
| `set_team_qr` | team | jefe (su team) · admin del team | el QR de cobro del team recibe plata: no lo cambia un rrpp |
| `guardar_telefono_de` | usuario | admin de todos sus boliches |  |
| `guardar_telefono` | sesión | * | el propio |
| `mi_telefono` | sesión | * | el propio |

## Barra

| Función | Alcance | Roles | Regla adicional |
| --- | --- | --- | --- |
| `bar_disponibilidad` | club | admin, propietario, barra |  |
| `bar_proyeccion_compra` | club | admin, propietario |  |
| `bar_cortesias_evento` | evento | admin, propietario, barra |  |
| `bar_conteo_pendiente` | evento | admin, propietario |  |
| `bar_conteo_masivo` | evento | admin, propietario |  |
| `bar_recibir_lote` | bebida | admin, propietario, deposito |  |
| `bar_vender` | evento | admin, propietario, barra | la barra tiene que ser del mismo boliche que el evento |
| `bar_anular_venta` | venta | admin, propietario, barra | el bartender solo anula sus propias ventas (bar_ventas.vendido_por, 25-auditoria.sql) |
| `bar_ajuste_conteo` | lote | admin, propietario |  |
| `bar_baja` | lote | admin, propietario |  |
