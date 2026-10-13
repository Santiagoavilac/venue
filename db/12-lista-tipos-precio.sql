-- FIX (2026-08-22) · lista_tipos.precio faltaba en el destino.
-- La app (sheetEditarLista → "Compra en Puerta") guarda lista_tipos.precio
-- para el cálculo del cierre, pero la columna nunca se creó en la base
-- reconstruida: PostgREST devolvía "Could not find the 'precio' column".
-- Es la MISMA columna que la app ya usa (esListaPuerta / cierre); no se
-- crea ninguna alternativa. Solo dato para el cálculo — no habilita
-- cobros ni entradas.
--   · numeric, NULL para listas sin precio, >= 0.
--   · no toca filas existentes (arrancan en NULL).
alter table lista_tipos add column if not exists precio numeric;
alter table lista_tipos drop constraint if exists lista_tipos_precio_no_negativo;
alter table lista_tipos add constraint lista_tipos_precio_no_negativo
  check (precio is null or precio >= 0);

-- refrescar el schema cache de PostgREST para que reconozca la columna ya
notify pgrst, 'reload schema';
