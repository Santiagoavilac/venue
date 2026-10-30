-- 46 · Color de cada team
--
-- Para distinguir los teams de un vistazo (usuarios, entradas, listas).
-- Sin color elegido, la app le asigna uno fijo a partir del id del team.
alter table teams add column if not exists color text
  check (color is null or color ~ '^#[0-9A-Fa-f]{6}$');
