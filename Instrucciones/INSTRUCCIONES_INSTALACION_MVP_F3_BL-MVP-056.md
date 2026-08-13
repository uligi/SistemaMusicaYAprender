# Instalación BL-MVP-056

Base Git exacta requerida:

`022f2ffd076744591ef7672b4cd4ddba472c151e`

1. Extraer el ZIP en la raíz de `SistemaMusicaYAprender`.
2. Desbloquear scripts PowerShell.
3. Ejecutar `scripts/apply-bl-mvp-056.ps1`.
4. No hacer staging, commit ni push.
5. Después de GREEN local, reiniciar el stack y abrir `/editorial/canciones/{id}/sincronizacion`.

La validación incluye fuentes independientes, milisegundos, duración, orden, precisión de línea/token, solapamientos
justificados por voces diferenciadas, Playwright/axe, 320 px, quality gate, Release y smoke PostgreSQL.
