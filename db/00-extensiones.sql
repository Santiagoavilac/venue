-- Extensiones que el esquema usa y que un proyecto nuevo no trae activadas.
-- Faltaba en la instalación limpia: 02f-rpc-busqueda.sql fallaba con
-- "function unaccent(text) does not exist".
--
-- Van en `public` porque las RPC fijan search_path = public y llaman a
-- unaccent() sin esquema.
create extension if not exists unaccent with schema public;
create extension if not exists pgcrypto with schema extensions;
