# Instalación BL-MVP-054

Base Git exacta requerida:

`7ab4a063159c4faa9c7fae787346baa171dbd0a1`

1. Extraer el ZIP en la raíz de `SistemaMusicaYAprender`, permitiendo sobrescribir los tres archivos BL053 incluidos.
2. Desbloquear scripts PowerShell.
3. Ejecutar `scripts/apply-bl-mvp-054.ps1`.
4. No hacer staging, commit ni push.
5. Después de GREEN local, reiniciar el stack y abrir `/editorial/canciones/{id}/letra`.

La validación incluye editor de secciones/líneas/voces, marcadores de contenido desconocido, previsualización sin
publicar, ETag/If-Match, conflicto 412, Playwright/axe, 320 px, quality gate, Release y smoke PostgreSQL.
