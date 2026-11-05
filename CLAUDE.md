# Venue · AFTR

Dos apps Flutter y una web sobre el mismo Supabase.

- `venue_mobile/` — gestión del boliche (admin, jefe de team, relacionador, portero).
- `aftr_mobile/` — app pública: descubrir, comprar entradas, historias, reventa, PULSE.
- `aftr_web/` + raíz (`app.js`, `index.html`, …) — la misma experiencia en web.
- `db/*.sql` — esquema base, en orden de instalación. Es historia: **no se edita para
  arreglar algo en producción**.
- `supabase/migrations/*.sql` — todo cambio de base va acá, con `create or replace`
  y un comentario arriba que explique qué se rompía.
- `tests/` — pruebas de base sobre PostgreSQL descartable y pruebas de la web.

## Trabajo en curso

El plan vigente es `docs/PLAN_EXPERIENCIA_VENUE.md` y el avance se anota en
`docs/ESTADO_PLAN_VENUE.md`. **Al empezar una sesión, leé los dos**: el plan no
vive en el contexto de ninguna conversación, vive ahí.

Al terminar cada tarea, actualizá el estado en el mismo commit. Si el contexto se
pierde, esos dos archivos tienen que alcanzar para seguir sin preguntar nada.

## Cómo quiere trabajar Santiago

- **No parar a preguntar.** Ante una duda, elegí la opción razonable, dejala
  anotada en el commit y seguí. Preguntar solo si hacerlo mal sería destructivo
  e irreversible (borrar datos de producción, mandar algo a Apple, cobrar plata).
- **Terminar lo empezado.** Una pantalla se cierra completa: visual, bugs,
  permisos y tutorial de esa pantalla. Nada de dejar la mitad y avisar.
- **Un commit por cosa terminada**, en español, explicando qué se rompía y por qué
  esta es la forma de arreglarlo. Nunca `git push` sin pedido explícito.
- **Nada de "ya está" sin probarlo.** Ver *Verificación*.
- No achicar el alcance por las tuyas. Si algo del plan no se puede, hacé todo lo
  demás y dejá dicho qué quedó afuera y por qué.

## Verificación obligatoria

Antes de dar algo por terminado:

- `cd venue_mobile && flutter analyze` sin errores ni advertencias, y `flutter test`
  en verde (hoy 115 pruebas). Lo mismo en `aftr_mobile` si se tocó.
- Si se tocó base: `node --check` para la web, y para SQL levantar un PostgreSQL
  descartable y correr `python3 tests/social_database_test.py <socket> <raíz>`.
  Los roles (`anon`, `authenticated`, `service_role`) son del cluster: para repetir
  hay que borrarlos junto con la base.
- **La privacidad se prueba con `curl` al endpoint REST, no con la app**: esconder
  un dato en Flutter no lo protege, sale igual con la sesión propia.
- Pruebas nuevas para cada arreglo que se pueda probar sin red.

## Cosas que ya se decidieron (no re-discutir)

- Sin subdominios por boliche: cada uno vive en `aftrvenue.com/#/lugar/<club>`,
  una sola sesión para todos.
- El evento activo se mantiene global, pero el cambio tiene que ser visible.
- Login normal con usuario y contraseña; las cuentas de equipo se crean por enlace
  con rol, no a mano.
- Criterios P0 de `deep-research-report (2).md` (contraste 4.5:1, targets 44–48,
  labels permanentes, feedback inmediato, estados de carga/vacío/error, nada que
  dependa solo del color) son bloqueantes.

## Una sola sesión por vez

Dos ventanas de Claude Code sobre este repo escriben el mismo árbol y se pisan.
Si hace falta trabajo en paralelo, que cada una use su propio worktree.
