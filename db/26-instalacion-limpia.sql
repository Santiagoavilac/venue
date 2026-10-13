-- Ajustes para que una instalación desde cero funcione y quede prolija.
-- Re-ejecutable.

-- profiles: el README pedía un INSERT que omitía columnas NOT NULL sin valor
-- por defecto (created_at, clubs, puede_tickear) y fallaba.
alter table profiles alter column created_at      set default now();
alter table profiles alter column clubs           set default '{}';
alter table profiles alter column puede_tickear   set default false;
alter table profiles alter column activo          set default true;
alter table profiles alter column admin_principal set default false;

-- search_path fijo en las funciones que no lo tenían (aviso 0011 del linter
-- de Supabase): evita que alguien las desvíe creando objetos homónimos.
alter function gen_code_evento(uuid)        set search_path = public;
alter function mesa_limpiar(uuid)           set search_path = public;
alter function lista_limite_ingreso(uuid)   set search_path = public;
alter function telefono_normalizar(text)    set search_path = public;
alter function es_servicio()                set search_path = public;
alter function impl.g(text, text, text)     set search_path = public;
