-- DERIVA DEL ORIGEN (2026-08-21) · registros.qr_anulado
--
-- El tercero sigue desarrollando el origen: `chequear-esquema.mjs` la
-- detectó como columna NUEVA sin replicar (igual que oculto/solo_invitaciones
-- el 2026-08-20). Se replica el ESQUEMA, no comportamiento inventado.
--
-- Forma medida en el origen (solo lectura, 5068 filas de registros):
--   · boolean, sin nulos       -> true: 0 · false: 5068 · null: 0
--   · todas en false           -> NOT NULL default false, igual que `oculto`
--     (misma familia: banderas por registro que el origen agregó después).
--
-- SUPUESTO (no verificable todavía): el origen NO la usa aún. Medido:
--   · ningún registro tiene qr_anulado = true;
--   · no existe RPC de anulación en el origen (probadas por nombre:
--     anular_qr_lista / anular_qr / toggle_qr_anulado / anular_registro
--     -> las cuatro "no existe");
--   · validar_qr_lista del origen sigue respondiendo igual que la réplica.
-- Por eso acá NO se cambia ninguna RPC: agregar un corte por qr_anulado en
-- validar_qr_lista sería inventar una regla que el original todavía no
-- aplica, y esa regla decide quién entra por la puerta. Queda anotado como
-- MEJORA PENDIENTE en db/ESTADO.md; cuando el origen la empiece a usar,
-- `chequear-esquema.mjs` + una sonda de la RPC dirán la semántica real
-- (probable: mismo corte que entradas.estado='anulada', que devuelve
-- {resultado:'anulada'} ANTES de consumir el ingreso).
--
-- No toca filas existentes: todas arrancan en false, igual que el origen.
alter table registros add column if not exists qr_anulado boolean not null default false;

-- refrescar el schema cache de PostgREST para que la reconozca ya
notify pgrst, 'reload schema';
