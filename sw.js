/* Service worker mínimo. app.js lo registra en https para que la web se
   pueda instalar como app. NO guarda nada en caché a propósito: una
   versión vieja de app.js contra un servidor con permisos nuevos rompería
   cosas en plena noche. Todo va a la red, como sin service worker. */
self.addEventListener("install", () => self.skipWaiting());
self.addEventListener("activate", e => e.waitUntil(self.clients.claim()));
