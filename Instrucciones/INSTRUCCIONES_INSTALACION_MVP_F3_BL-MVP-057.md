# Instalación BL-MVP-057

Base Git exacta requerida:

`9505acc212a8c8b0313c1d8ec70c36ab70bb5b93`

1. Extraer el ZIP en la raíz de `SistemaMusicaYAprender`.
2. Desbloquear los scripts PowerShell.
3. Ejecutar `scripts/apply-bl-mvp-057.ps1`.
4. No hacer `git add`, commit ni push.
5. Después de GREEN local, reiniciar el stack normal y revisar `/editorial/canciones/{id}/sincronizacion`.

La validación incluye marcado por teclado, límites individuales, desplazamiento múltiple, previsualización local, borrador parcial, conflicto de revisión, tiempos inválidos, axe, 320 px, quality gate, Release y smoke PostgreSQL.
