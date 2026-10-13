-- Esquema de tablas · plataforma de boliches
--
-- Reconstruido desde el respaldo de datos (9.316 filas, 19 tablas) leído de
-- kdkjmqrbiszmkcprinir el 2026-08-19. Los tipos salen de los valores reales;
-- las claves foráneas se verificaron comprobando que todo valor hijo exista
-- en su tabla padre.
--
-- LO QUE NO ESTÁ VERIFICADO va marcado con "-- ?" en su línea:
--   · columnas 100 % nulas en el respaldo (tipo deducido de app.js)
--   · NOT NULL en tablas con muestra chica
-- Ver PARIDAD.md para el detalle.

create table if not exists clubs (
  id                   text primary key,  -- ? sin null en 2 filas; muestra chica
  nombre               text,  -- ? sin null en 2 filas; muestra chica
  qr_cobro_url         text  -- ? sin null en 2 filas; muestra chica
);

create table if not exists profiles (
  id                   uuid primary key,
  usuario              text not null,
  nombre               text not null,
  rol                  text not null,
  team_id              uuid,
  activo               boolean not null,
  creado_por           uuid,
  created_at           timestamptz not null,
  cut_rel              integer,
  clubs                text[] not null,
  puede_tickear        boolean not null,
  eliminado_at         timestamptz,
  admin_principal      boolean not null
);

create table if not exists teams (
  id                   uuid primary key,
  nombre               text not null,
  jefe_id              uuid,
  activo               boolean not null,
  created_at           timestamptz not null,
  invite_code          text not null,
  clubs                text[] not null,
  qr_cobro_url         text
);

create table if not exists eventos (
  id                   uuid primary key,
  club_id              text not null,
  nombre               text not null,
  flyer_url            text,  -- ? tipo deducido: url de imagen, como ticket_url
  fecha                date not null,
  hora_inicio          time not null,
  hora_fin             time not null,
  edad_min             integer not null,
  precio_manilla       integer not null,
  pct_boliche          integer not null,
  pct_rrpp             integer not null,
  estado               text not null,
  created_at           timestamptz not null,
  ticket_url           text not null,
  entrada_hasta        timestamptz,
  lista_hasta          time not null,
  manilla_hasta        time,  -- ? tipo deducido: hora tope, como lista_hasta; el ts vive en manilla_hasta_ts
  manilla_desde        timestamptz,
  manilla_hasta_ts     timestamptz,
  cut_rrpp             integer not null,
  manillas_externas    integer not null,
  venta_por_fases      boolean not null,
  publicado            boolean not null,
  publicado_por        uuid,
  publicado_at         timestamptz not null,
  permite_reserva      boolean not null,
  horas_reserva        integer not null,
  permite_agrupar      boolean not null,
  combo_obligatorio    boolean not null,
  combo_por_mesa       boolean not null,
  cut_base             text not null,
  cut_umbral           integer,
  cut_sobre_umbral     integer
);

create table if not exists lista_tipos (
  id                   uuid primary key,
  evento_id            uuid not null,
  nombre               text not null,
  cupo_por_rrpp        integer,
  registro_desde       timestamptz,
  registro_hasta       timestamptz not null,
  orden                integer not null,
  cupo_total           integer,
  cupo_jefe            integer,
  cupo_admin           integer,  -- ? tipo deducido: cupo, igual que cupo_por_rrpp y cupo_jefe
  ingreso_hasta        time
);

create table if not exists combos (
  id                   uuid primary key,  -- ? sin null en 12 filas; muestra chica
  club_id              text,  -- ? sin null en 12 filas; muestra chica
  nombre               text,  -- ? sin null en 12 filas; muestra chica
  descripcion          text,  -- ? tipo deducido: texto libre
  productos            text[],  -- ? sin null en 12 filas; muestra chica
  precio               integer,  -- ? sin null en 12 filas; muestra chica
  comision_rrpp        integer,  -- ? sin null en 12 filas; muestra chica
  comision_jefe        integer,  -- ? sin null en 12 filas; muestra chica
  incluye_manillas     integer,  -- ? sin null en 12 filas; muestra chica
  activo               boolean,  -- ? sin null en 12 filas; muestra chica
  categorias           text[]
);

create table if not exists mesas (
  id                   uuid primary key,
  evento_id            uuid not null,
  planta               text not null,
  etiqueta             text not null,
  categoria            text not null,
  x                    numeric not null,
  y                    numeric not null,
  w                    integer not null,
  team_id              uuid,  -- ? tipo deducido: referencia a teams
  estado               text not null,
  cliente              text,
  combo_id             uuid,
  botellas             text[] not null,
  manillas             integer not null,
  precio               integer,
  vendido_por          uuid,
  updated_at           timestamptz not null,
  grupo_id             uuid,
  combo_qty            integer not null,
  h                    integer,
  pagada_por           uuid,
  pagada_at            timestamptz,
  reservada_at         timestamptz,  -- ? tipo deducido: momento de la reserva
  comprobante_url      text,
  pago_verificado      boolean not null,
  verificado_por       uuid,
  verificado_at        timestamptz,
  metodo_pago          text,
  reserva_vence_at     timestamptz,  -- ? tipo deducido: vencimiento de la reserva
  cortesia             boolean not null,
  cortesia_por         uuid,
  cargada_por          uuid
);

create table if not exists club_membership (
  user_id              uuid not null,
  club_id              text not null,
  rol                  text not null,
  team_id              uuid not null
);

create table if not exists registros (
  id                   uuid primary key,
  evento_id            uuid not null,
  lista_tipo_id        uuid not null,
  nombre               text not null,
  rrpp_id              uuid not null,
  ingreso_at           timestamptz,
  ingreso_por          uuid,
  created_at           timestamptz not null,
  code                 text,
  filtro_at            timestamptz,
  filtro_por           uuid,
  cargado_por          uuid  -- ? tipo deducido: referencia a profiles, como rrpp_id
);

create table if not exists entradas (
  id                   uuid primary key,
  evento_id            uuid not null,
  code                 text not null,
  cliente              text not null,
  rrpp_id              uuid not null,
  precio               integer not null,
  estado               text not null,
  created_at           timestamptz not null,
  used_at              timestamptz,
  portero_id           uuid,
  mesa_id              uuid,
  filtro_at            timestamptz,
  filtro_por           uuid,
  fase_id              uuid
);

create table if not exists pagos (
  id                   uuid primary key,
  evento_id            uuid not null,
  rrpp_id              uuid not null,
  monto                numeric not null,
  concepto             text not null,
  estado               text not null,
  nro_operacion        text,
  comprobante_url      text,
  verificado_por       uuid,  -- ? tipo deducido: referencia a profiles
  verificado_at        timestamptz,  -- ? tipo deducido: momento de la verificación
  created_at           timestamptz not null
);

create table if not exists qr_cobro (
  id                   uuid primary key,  -- ? sin null en 2 filas; muestra chica
  club_id              text,  -- ? sin null en 2 filas; muestra chica
  nombre               text,  -- ? sin null en 2 filas; muestra chica
  url                  text,  -- ? sin null en 2 filas; muestra chica
  orden                integer,  -- ? sin null en 2 filas; muestra chica
  activo               boolean,  -- ? sin null en 2 filas; muestra chica
  created_at           timestamptz  -- ? sin null en 2 filas; muestra chica
);

create table if not exists cupo_rrpp (
  lista_tipo_id        uuid,  -- ? sin null en 6 filas; muestra chica
  user_id              uuid,  -- ? sin null en 6 filas; muestra chica
  cupo                 integer  -- ? sin null en 6 filas; muestra chica
);

create table if not exists cupo_permanente (
  user_id              uuid,  -- ? sin null en 2 filas; muestra chica
  club_id              text,  -- ? sin null en 2 filas; muestra chica
  lista_nombre         text,  -- ? sin null en 2 filas; muestra chica
  cupo                 integer,  -- ? sin null en 2 filas; muestra chica
  nota                 text,  -- ? sin null en 2 filas; muestra chica
  updated_at           timestamptz  -- ? sin null en 2 filas; muestra chica
);

-- bonos: vacía en el respaldo, sin datos para inferir columnas.
--   Se crea con lo mínimo que usa la app; revisar antes de usar.

create table if not exists venta_excepcion (
  id                   uuid primary key,  -- ? sin null en 6 filas; muestra chica
  evento_id            uuid,  -- ? sin null en 6 filas; muestra chica
  team_id              uuid,
  user_id              uuid,
  desde_ts             timestamptz,  -- ? tipo deducido: inicio de la excepción; hay hasta_ts con datos
  hasta_ts             timestamptz,  -- ? sin null en 6 filas; muestra chica
  nota                 text,  -- ? tipo deducido: texto libre
  creado_por           uuid,  -- ? sin null en 6 filas; muestra chica
  created_at           timestamptz  -- ? sin null en 6 filas; muestra chica
);

create table if not exists caja_check (
  evento_id            uuid not null,
  user_id              uuid not null,
  marcado_por          uuid
);

create table if not exists plano_fondos (
  club_id              text,  -- ? sin null en 5 filas; muestra chica
  planta               text,  -- ? sin null en 5 filas; muestra chica
  url                  text,  -- ? sin null en 5 filas; muestra chica
  updated_at           timestamptz  -- ? sin null en 5 filas; muestra chica
);

create table if not exists avisos (
  id                   uuid primary key,  -- ? sin null en 1 filas; muestra chica
  club_id              text,  -- ? sin null en 1 filas; muestra chica
  titulo               text,  -- ? sin null en 1 filas; muestra chica
  mensaje              text,  -- ? sin null en 1 filas; muestra chica
  destino              text,  -- ? sin null en 1 filas; muestra chica
  team_id              uuid,  -- ? tipo deducido: referencia a teams
  hasta_ts             timestamptz,  -- ? sin null en 1 filas; muestra chica
  activo               boolean,  -- ? sin null en 1 filas; muestra chica
  creado_por           uuid,  -- ? sin null en 1 filas; muestra chica
  created_at           timestamptz  -- ? sin null en 1 filas; muestra chica
);


-- Claves foráneas verificadas contra los datos del respaldo
alter table eventos add constraint eventos_club_id_fkey
  foreign key (club_id) references clubs(id);   -- 10 valores verificados
alter table lista_tipos add constraint lista_tipos_evento_id_fkey
  foreign key (evento_id) references eventos(id);   -- 27 valores verificados
alter table profiles add constraint profiles_team_id_fkey
  foreign key (team_id) references teams(id);   -- 235 valores verificados
alter table teams add constraint teams_jefe_id_fkey
  foreign key (jefe_id) references profiles(id);   -- 1 valores verificados
alter table club_membership add constraint club_membership_user_id_fkey
  foreign key (user_id) references profiles(id);   -- 96 valores verificados
alter table club_membership add constraint club_membership_club_id_fkey
  foreign key (club_id) references clubs(id);   -- 96 valores verificados
alter table club_membership add constraint club_membership_team_id_fkey
  foreign key (team_id) references teams(id);   -- 96 valores verificados
alter table registros add constraint registros_evento_id_fkey
  foreign key (evento_id) references eventos(id);   -- 5049 valores verificados
alter table registros add constraint registros_lista_tipo_id_fkey
  foreign key (lista_tipo_id) references lista_tipos(id);   -- 5049 valores verificados
alter table registros add constraint registros_rrpp_id_fkey
  foreign key (rrpp_id) references profiles(id);   -- 5049 valores verificados
alter table entradas add constraint entradas_evento_id_fkey
  foreign key (evento_id) references eventos(id);   -- 3273 valores verificados
alter table entradas add constraint entradas_rrpp_id_fkey
  foreign key (rrpp_id) references profiles(id);   -- 3273 valores verificados
alter table entradas add constraint entradas_mesa_id_fkey
  foreign key (mesa_id) references mesas(id);   -- 426 valores verificados
alter table mesas add constraint mesas_evento_id_fkey
  foreign key (evento_id) references eventos(id);   -- 235 valores verificados
alter table mesas add constraint mesas_combo_id_fkey
  foreign key (combo_id) references combos(id);   -- 174 valores verificados
alter table mesas add constraint mesas_vendido_por_fkey
  foreign key (vendido_por) references profiles(id);   -- 174 valores verificados
alter table mesas add constraint mesas_pagada_por_fkey
  foreign key (pagada_por) references profiles(id);   -- 136 valores verificados
alter table combos add constraint combos_club_id_fkey
  foreign key (club_id) references clubs(id);   -- 12 valores verificados
alter table pagos add constraint pagos_evento_id_fkey
  foreign key (evento_id) references eventos(id);   -- 96 valores verificados
alter table cupo_rrpp add constraint cupo_rrpp_lista_tipo_id_fkey
  foreign key (lista_tipo_id) references lista_tipos(id);   -- 6 valores verificados
alter table cupo_rrpp add constraint cupo_rrpp_user_id_fkey
  foreign key (user_id) references profiles(id);   -- 6 valores verificados
alter table cupo_permanente add constraint cupo_permanente_user_id_fkey
  foreign key (user_id) references profiles(id);   -- 2 valores verificados
alter table caja_check add constraint caja_check_evento_id_fkey
  foreign key (evento_id) references eventos(id);   -- 231 valores verificados
alter table plano_fondos add constraint plano_fondos_club_id_fkey
  foreign key (club_id) references clubs(id);   -- 5 valores verificados
alter table avisos add constraint avisos_club_id_fkey
  foreign key (club_id) references clubs(id);   -- 1 valores verificados

-- NO verificadas: se documentan pero no se crean.
--   bonos.evento_id -> eventos: tabla hija vacía en el respaldo
--   bonos.user_id -> profiles: tabla hija vacía en el respaldo
