# Dónde vuelve la gente después de entrar

**El error:** alguien entraba con Google o Apple desde AFTR y terminaba en
Venue, el panel del boliche. No era del código de la app: era la configuración
de autenticación del proyecto de Supabase.

Supabase valida el `redirect_to` contra una lista blanca. Si la URL no está en
la lista **no falla: manda a la Site URL**. Y la configuración era:

    site_url       = https://venue-web-amber.vercel.app      ← Venue
    uri_allow_list = venue-web-amber.vercel.app/**,
                     aftr-web.vercel.app/**,
                     venue://login-callback

La web pública de AFTR vive en `www.aftrvenue.com`, que **no estaba en la
lista**. Entonces cada persona que entraba desde el dominio de verdad caía en la
Site URL, que era Venue. Desde `aftr-web.vercel.app` funcionaba, por eso en
pruebas no se veía.

**Cómo quedó (06/11/2026):**

    site_url       = https://www.aftrvenue.com
    uri_allow_list = https://www.aftrvenue.com/**,
                     https://aftrvenue.com/**,
                     https://aftr-web.vercel.app/**,
                     https://venue-web-amber.vercel.app/**,
                     venue://login-callback,
                     http://localhost:5173/**, http://localhost:8000/**

La Site URL es AFTR y no Venue a propósito: es la que usa el público, y un
respaldo que te deja en el panel de administración del boliche es lo peor que
puede pasar. Venue sigue andando porque su dominio está en la lista.

## Qué dominio es cada cosa

| Dominio | Qué sirve |
|---------|-----------|
| `www.aftrvenue.com` (y `aftrvenue.com`, que redirige) | AFTR, la app pública |
| `aftr-web.vercel.app` | la misma AFTR, dominio de Vercel |
| `venue-web-amber.vercel.app` | Venue, el panel del boliche |

## Si se agrega un dominio

Hay que tocarlo en **tres** lugares, o vuelve a pasar algo parecido:

1. la lista de arriba (Supabase → Authentication → URL Configuration);
2. `ORIGENES_PERMITIDOS` de las Edge Functions, o la lista fija en
   `db/functions/*/index.ts` y `handler.ts` (CORS);
3. la CSP de `vercel.json` y del `<meta>` de `index.html`, si cambia de dónde
   se cargan los scripts.

Las apps de iOS no usan redirección: entran con `signInWithIdToken`, que
cambia el token de Apple o Google por la sesión sin salir de la app. Por eso el
error sólo se veía en la web.

## Qué más se revisó el 06/11 buscando lo mismo

Un error de configuración no se ve en el código, así que se revisó todo lo que
esta sesión tocó y podía estar roto en producción sin avisar:

- **Funciones duplicadas.** `create or replace` con un parámetro nuevo crea
  OTRA función y deja las llamadas ambiguas. Se revisaron todas las de `public`:
  no queda ninguna duplicada nuestra.
- **`select * into` desde una vista.** Rellena por posición: si la vista tiene
  menos columnas que la tabla, los últimos campos llegan vacíos. Pasó con
  `pase_libre`. Se revisaron las 15 funciones que leen `entradas_vigentes`: la
  única afectada ya está arreglada.
- **Las 15 funciones donde se inyectó una línea** (límites de uso y cuenta
  real): se llamó a cada una con una sesión real y todas contestan su propio
  error de negocio, ninguna un error de estructura.
- **Los ocho crones**: 0 fallos en dos horas.
- **CORS de las tres Edge Functions**: se habían acotado a `aftrvenue.com` y
  dejaban afuera los dominios de Vercel, donde también viven las dos webs. Con
  eso, crear cuentas desde Venue habría dejado de andar. Corregido y probado
  contra los cuatro dominios.
- **`Permissions-Policy: camera=()`** del `vercel.json`: la web de Venue escanea
  QR con la cámara. Corregido a `camera=(self)` para Venue; AFTR no usa cámara.
- **La CSP** se comparó contra todo host que tocan los JS de AFTR y contra el
  estilo del mapa (`tiles.basemaps.cartocdn.com`): entra en `connect-src`.
- **`search_path`** sin fijar en dos funciones nuevas: corregido.
- **`exige_comprobante`** estaba prendido en burtown y sitroom, y ni la web ni
  las apps publicadas saben mandar el comprobante: desde la mañana no podían
  generar entradas con precio. Se apagó, y la web de Venue aprendió a mandarlo
  para poder volver a prenderlo.

## Por qué las webs no se actualizaban

Las dos webs servían el código del **05/11 a las 03:47** mientras la base y las
Edge Functions ya tenían todo lo nuevo. No era el push: los dos proyectos de
Vercel **no estaban conectados al repo**. Comprobado por API:

    /v9/projects/venue-web → link: null
    /v9/projects/aftr-web  → link: null

y los ocho despliegues de cada uno tienen `meta: {}`, sin commit asociado: todos
eran `vercel deploy` a mano. Un `git push` no tenía forma de llegar a la web.

Tampoco se podían conectar, por tres razones concretas:

1. **El repo está en otra cuenta de GitHub.** Es de `Santiagoavilac`, y la cuenta
   de GitHub conectada a Vercel es `venuegestion-lab`: Vercel contesta
   `repo_no_access` al intentar enlazarlo.
2. **`config.js` no se versiona** (está en `.gitignore`, ver `config.example.js`).
   Un build desde el repo lo dejaba afuera y la web arrancaba sin base.
3. **Publicar la raíz publicaría el repo entero**: `db/`, `docs/`, `supabase/`,
   `tests/` y las dos apps Flutter, en texto plano.

Cómo quedó:

- `tools/armar_web.mjs` y `aftr_web/armar.mjs` arman la carpeta `dist/` que se
  publica, copiando **sólo** los archivos que la web usa, nombre por nombre; si
  falta uno, el build falla en vez de publicar una web a medias. Y escriben
  `config.js` desde `SUPABASE_URL` y `SUPABASE_ANON_KEY`, que ya están cargadas
  en los dos proyectos (la anon key es pública: viaja al navegador igual y lo
  que protege los datos es RLS). Sin esas variables usan el `config.js` local,
  así que un despliegue a mano desde la máquina sigue andando igual.
- `.github/workflows/publicar-webs.yml` publica las dos en cada push a `main`.
  **Falta un paso que es tuyo**: cargar el secreto `VERCEL_TOKEN` en el repo
  (GitHub → Settings → Secrets and variables → Actions), con un token de Vercel
  del equipo `venue6`. Hasta que esté, el workflow falla a propósito y lo dice.
- `cleanUrls` en `aftr_web/vercel.json`: `/terminos`, `/privacidad` y `/normas`
  se enlazan sin extensión y contestaban 404.

Lo mejor sigue siendo la integración de Git de Vercel, porque además trae un
preview por rama. Para eso hay que darle a `venuegestion-lab` acceso de
escritura al repo `Santiagoavilac/venue`; con eso hecho, se conecta y el
workflow se puede borrar.
