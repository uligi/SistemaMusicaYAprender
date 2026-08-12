# Instalación BL-MVP-046

Base Git exacta requerida:

`11c79f40461bfaf0b1ad69f5f2b5282f9fd7e521`

1. Extraer el paquete en la raíz de `SistemaMusicaYAprender`.
2. Desbloquear scripts PowerShell.
3. Ejecutar `scripts/apply-bl-mvp-046.ps1`.
4. Reiniciar el stack normal.
5. Abrir un expediente real desde `/editorial`.
6. Revisar inventario antes de cualquier staging.

El instalador no ejecuta `git add`, commit ni push.
