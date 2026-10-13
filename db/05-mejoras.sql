-- ETAPA 2 · MEJORAS (1/2): índices y constraints de integridad.
-- NO cambia ningún comportamiento que la app pueda observar en un flujo
-- válido: cada CHECK se validó contra los datos reales (cero violaciones)
-- y contra TODOS los caminos de escritura de las RPCs y de la UI.
--
-- Evidencia de los dominios:
-- · entradas.estado: valida/usada/anulada (datos + RPCs). El biconditional
--   usada⇔used_at se sostiene en todos los caminos: checkin setea ambos,
--   descheckin limpia ambos, anular_entrada solo opera sobre 'valida'.
-- · mesas.estado: EST_LABEL (app.js:5164) es el set COMPLETO de la UI:
--   disponible/reservada/pagada/ocupada.
-- · pagos.estado: pendiente → pagado → verificado (app.js:2653/2777 —
--   'verificado' NO aparece en los datos actuales pero la UI lo manda).
-- · Los pares filtro_at/filtro_por e ingreso_at/ingreso_por siempre se
--   setean o limpian juntos (case-when en las RPCs; 0 violaciones en datos).

-- ==== CHECKS ====

alter table entradas add constraint entradas_estado_valido
  check (estado in ('valida', 'usada', 'anulada'));
alter table entradas add constraint entradas_usada_con_hora
  check ((estado = 'usada') = (used_at is not null));
alter table entradas add constraint entradas_filtro_par
  check ((filtro_at is null) = (filtro_por is null));
alter table entradas add constraint entradas_precio_no_negativo
  check (precio >= 0);

alter table registros add constraint registros_ingreso_par
  check ((ingreso_at is null) = (ingreso_por is null));
alter table registros add constraint registros_filtro_par
  check ((filtro_at is null) = (filtro_por is null));

alter table mesas add constraint mesas_estado_valido
  check (estado in ('disponible', 'reservada', 'pagada', 'ocupada'));
alter table mesas add constraint mesas_combo_positivo
  check (combo_qty >= 1);

alter table pagos add constraint pagos_estado_valido
  check (estado in ('pendiente', 'pagado', 'verificado'));
alter table pagos add constraint pagos_monto_positivo
  check (monto > 0);

alter table evento_fase add constraint fase_precio_no_negativo check (precio >= 0);
alter table evento_fase add constraint fase_cupo_no_negativo check (cupo >= 0);

alter table lotes add constraint lotes_ml_no_negativo check (ml_actual >= 0);
alter table bar_venta_items add constraint bar_items_qty_positivo check (qty > 0);

-- ==== UNICIDAD DE CÓDIGOS (por evento; 0 duplicados en 3.285 + 5.049) ====
-- gen_code_evento ya la garantiza al generar; esto la vuelve un invariante
-- de la base y de paso acelera los lookups del scanner.

create unique index if not exists entradas_code_unico_por_evento
  on entradas (evento_id, code) where code is not null;
create unique index if not exists registros_code_unico_por_evento
  on registros (evento_id, code) where code is not null;
create index if not exists registros_code_idx
  on registros (code) where code is not null;

-- ==== ÍNDICES (derivados de los patrones de las RPCs y la app) ====

create index if not exists entradas_evento_idx on entradas (evento_id);
create index if not exists entradas_rrpp_idx on entradas (rrpp_id);
create index if not exists entradas_mesa_idx on entradas (mesa_id) where mesa_id is not null;
create index if not exists entradas_fase_idx on entradas (fase_id) where fase_id is not null;

create index if not exists registros_evento_idx on registros (evento_id);
create index if not exists registros_lista_idx on registros (lista_tipo_id);
create index if not exists registros_rrpp_idx on registros (rrpp_id);

create index if not exists lista_tipos_evento_idx on lista_tipos (evento_id);
create index if not exists mesas_evento_idx on mesas (evento_id);
create index if not exists mesas_grupo_idx on mesas (grupo_id) where grupo_id is not null;
create index if not exists pagos_evento_idx on pagos (evento_id);
create index if not exists pagos_rrpp_idx on pagos (rrpp_id);
create index if not exists venta_excepcion_evento_idx on venta_excepcion (evento_id);
create index if not exists evento_fase_evento_idx on evento_fase (evento_id);
create index if not exists eventos_club_idx on eventos (club_id);
create index if not exists aviso_visto_user_idx on aviso_visto (user_id);

create index if not exists lotes_bebida_idx on lotes (bebida_id);
create index if not exists stock_mov_evento_idx on stock_mov (evento_id);
create index if not exists stock_mov_bebida_idx on stock_mov (bebida_id);
create index if not exists stock_mov_motivo_idx on stock_mov (motivo) where tipo = 'salida';
create index if not exists bar_ventas_evento_idx on bar_ventas (evento_id);
create index if not exists bar_venta_items_venta_idx on bar_venta_items (venta_id);
create index if not exists bar_conteos_evento_idx on bar_conteos (evento_id);
