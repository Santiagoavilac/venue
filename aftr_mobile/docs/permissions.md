# Permisos de AFTR

## Fotos de perfil

- Uso: elegir una imagen de la biblioteca, verla y guardarla como foto de perfil.
- iOS: `NSPhotoLibraryUsageDescription`. Selector de fotos del sistema, sin solicitar metadatos completos.
- Android: Photo Picker de `image_picker`, sin acceso general a archivos. Se contempla recuperación de la selección si Android recrea la actividad.
- No se pide cámara ni micrófono para esta función.
- Imágenes limitadas a 800 × 800 al seleccionar, hasta 2 MB en Storage. JPG, PNG y WebP.
- Bucket privado `aftr-perfiles`, con RLS por carpeta de usuario y URLs firmadas de una hora.
- La foto anterior se conserva hasta confirmar el cambio. Después se elimina su archivo anterior cuando es posible.
- Validación: pruebas de formatos y verificación transaccional de permisos en Supabase. La selección de una foto personal en el dispositivo requiere la interacción del usuario.
