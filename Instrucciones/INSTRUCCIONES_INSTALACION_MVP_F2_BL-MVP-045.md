# Instalación BL-MVP-045

Base Git exacta requerida:

`a8c02b3ee6f15435ff0a66b6e804ec198a810fea`

1. Extraer el paquete en la raíz de `SistemaMusicaYAprender`.
2. Desbloquear scripts PowerShell.
3. Ejecutar `scripts/apply-bl-mvp-045.ps1`.
4. Reiniciar el stack normal.
5. Revisar visualmente `/editorial/canciones/nueva`.
6. Revisar inventario antes de cualquier staging.

El instalador no ejecuta `git add`, commit ni push.
