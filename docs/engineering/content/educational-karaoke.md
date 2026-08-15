# Reproductor educativo y karaoke accesible

BL-MVP-060 integra el adaptador de YouTube BL058 y el motor de sincronización BL059 con una superficie propia de karaoke.

## Flujo

1. Se revalida la canción pública.
2. Se cargan en paralelo sincronización y capas educativas propias.
3. La letra se renderiza antes del adaptador externo.
4. `SynchronizedYouTubePreview` emite un `LocalSynchronizationSnapshot`.
5. `EducationalKaraoke` marca la línea activa sin mover foco.
6. Solo un snapshot `TOKEN` puede activar un token.
7. Un error de YouTube no desmonta la letra ni sus capas.

## Invariantes

- No `focus()` ni `scrollIntoView()` por cambio temporal.
- No karaoke progresivo si la precisión disponible es LINE.
- La fuente externa nunca es fuente de letra, traducción o análisis.
- La UI no crea una revisión ni publica contenido.
