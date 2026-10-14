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

Los archivos de `db/` se aplican **en orden** (`00-extensiones.sql`,
`01-tablas.sql`, … hasta `26-instalacion-limpia.sql`). Dos formas:

- A mano: pegarlos uno por uno en el SQL Editor de Supabase.
- Con el script (necesita `.env.local` con la URL y la service role key):
  ejecutar `tools/instalador.sql` en el SQL Editor y después

  ```bash
  python3 tools/aplicar.py $(ls db/*.sql | sort)
  ```

  Al terminar, borrar el instalador:
  `drop function if exists public._venue_exec(text);`

Los archivos 18 en adelante son la capa de seguridad (permisos por boliche,
guardas de las RPC, RLS, auditoría). **No son opcionales.**

Desplegar también la Edge Function `db/functions/crear-usuario`.

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
email `admin@plataforma.local` y una contraseña. Después, en el SQL Editor:

```sql
insert into profiles (id, usuario, nombre, rol, admin_principal)
values ('<uuid del usuario creado arriba>', 'admin', 'Administrador', 'admin', true);
```

`admin_principal = true` la vuelve administradora de la **plataforma**: ve
todos los boliches, los crea (**Admin → Boliches**) y nombra a los admins de
cada uno. Un admin común solo administra los boliches de `profiles.clubs`.

Para un entorno de prueba con dos boliches y un usuario por rol:
`python3 tools/seed_demo.py`.

## Pruebas

```bash
python3 tools/seed_demo.py && python3 tests/test_seguridad.py   # 103 casos de permisos contra el proyecto de .env.local
cd venue_mobile && flutter test                                  # app móvil
```

## Estructura

| Archivo / carpeta | Contenido |
| --- | --- |
| `index.html` | Estructura de todas las pantallas |
| `styles.css` | Sistema de diseño (tokens de color, tipografía) |
| `app.js` | Lógica: roles, listas, QR, mesas, barra, boliches |
| `motion.js` | Movimiento con GSAP + ScrollTrigger (opcional: sin él la web anda igual) |
| `contabilidad.js` | Exportación de contabilidad a Excel |
| `config.js` | Credenciales de Supabase (no versionar) |
| `db/*.sql` | Esquema completo, en orden de aplicación |
| `db/functions/` | Edge Functions de Supabase |
| `docs/RPC_MATRIZ.md` | Quién puede llamar a cada función del servidor |
| `tools/` | Instalador de SQL y datos de demostración |
| `tests/` | Pruebas de permisos contra un proyecto de prueba |
| `venue_mobile/` | App Flutter (iOS / Android) |
| `IMPLEMENTATION_STATUS.md` | Qué está hecho, probado y pendiente |

## Notas

- La `anon key` es pública por diseño (viaja al navegador de todos modos).
  Lo que protege los datos son las guardas de las RPC y RLS por boliche
  (`db/18` a `db/25`), no esconder esa clave.
- La `service_role` key **nunca** va en el cliente ni en `config.js`.
- Sin build ni bundler: HTML + CSS + JS plano. `node dev.mjs` sirve los
  archivos sin caché para que los cambios se vean al recargar.
