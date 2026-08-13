# Instalación BL-MVP-055

Base Git exacta requerida:

`c5ec099d1c4632e9503bc48305246062e6cb6cd9`

1. Extraer el ZIP en la raíz de `SistemaMusicaYAprender`.
2. Desbloquear scripts PowerShell.
3. Ejecutar `scripts/apply-bl-mvp-055.ps1`.
4. No hacer staging, commit ni push.
5. Después de GREEN local, reiniciar el stack y abrir `/editorial/canciones/{id}/letra`.

La validación incluye offsets UTF-16, superficie derivada del japonés original, unión de tokens contiguos,
advertencias de impacto sobre tiempos/traducciones/análisis, Playwright/axe, 320 px, quality gate, Release y
smoke PostgreSQL.
