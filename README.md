# Venue

Plataforma de gestión de eventos: listas, entradas QR, control de ingreso,
mesas, barra y caja. Multi-boliche: los locales se crean desde la app
(Admin → Boliches), no hardcodeados en el código.

## Puesta en marcha desde cero

**1 · Crear el proyecto en Supabase**

Creá un proyecto nuevo en [supabase.com](https://supabase.com), y anotá:

- Project URL
- anon / public key

(Settings → API, dentro del proyecto)

**2 · Crear el esquema**

En el SQL Editor de Supabase, pegá y ejecutá los archivos de `db/` **en
orden numérico** (`01-tablas.sql`, `02-rpc-lectura.sql`, … hasta
`17-boliches-dinamicos.sql`), uno por uno.

**3 · Configurar la app**

```bash
cp config.example.js config.js
```

Completá `config.js` con la URL y la anon key del paso 1.

**4 · Levantar la app**

Necesita Node instalado.

```bash
node dev.mjs
```

Abrí <http://localhost:5173>.

**5 · Crear el primer usuario admin**

En Supabase → Authentication → Users → **Add user**, creá una cuenta con
email y contraseña. Después, en el SQL Editor:

```sql
insert into profiles (id, usuario, nombre, rol, activo, admin_principal)
values (
  '<uuid del usuario creado arriba>',
  'admin',
  'Administrador',
  'admin',
  true,
  true
);
```

Con esa cuenta entrás a la app y desde **Admin → Boliches** creás el o los
locales (nombre, colores de marca, etc.), y desde **Admin → Usuarios**
das de alta al resto del equipo con su rol (portero, caja, RRPP, jefe...).

## Estructura

| Archivo / carpeta | Contenido |
| --- | --- |
| `index.html` | Estructura de todas las pantallas |
| `styles.css` | Sistema de diseño (tokens de color, tipografía) |
| `app.js` | Lógica: roles, listas, QR, mesas, barra, boliches |
| `contabilidad.js` | Exportación de contabilidad a Excel |
| `config.js` | Credenciales de Supabase (no versionar) |
| `db/*.sql` | Esquema completo, en orden de aplicación |
| `db/functions/` | Edge Functions de Supabase |

## Notas

- La `anon key` es pública por diseño (viaja al navegador de todos modos).
  Lo que protege los datos es RLS (`db/06-rls.sql` y
  `db/09-endurecimiento.sql`), no esconder esa clave.
- La `service_role` key **nunca** va en el cliente ni en `config.js`.
- Sin build ni bundler: HTML + CSS + JS plano. `node dev.mjs` sirve los
  archivos sin caché para que los cambios se vean al recargar.
