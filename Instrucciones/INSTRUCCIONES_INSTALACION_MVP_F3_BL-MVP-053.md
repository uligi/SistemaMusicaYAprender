# Instalación BL-MVP-053

Base Git exacta requerida:

`04490943a5d0f6ed5d17ae79c896e9bdcbd33b73`

1. Extraer el ZIP en la raíz de `SistemaMusicaYAprender`.
2. Desbloquear scripts PowerShell.
3. Ejecutar `scripts/apply-bl-mvp-053.ps1`.
4. No hacer staging, commit ni push.
5. Después de GREEN local, reiniciar el stack y abrir `/editorial/canciones/{id}/letra`.

La validación incluye superficie Unicode original frente a normalización separada, historial de revisiones,
identificadores opacos, checksum, Playwright/axe, 320 px, quality gate, Release y smoke PostgreSQL.
