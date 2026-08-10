# BL-MVP-026E — corrección del instalador de BL-MVP-026D

## Motivo

BL-MVP-026D sí aplicó correctamente el cambio funcional sobre
`scripts/ci/identity/verify-personal-login.sh`, pero su validación posterior resolvió `bash`
mediante el alias/stub de WSL disponible en Windows. En este equipo ese stub intenta ejecutar
`/bin/bash` dentro de WSL y falla porque no existe una distribución Linux disponible.

El repositorio ya tiene una solución canónica para este problema: los instaladores BL-MVP-024,
BL-MVP-025 y BL-MVP-028 localizan explícitamente **Git Bash** a partir de `git.exe`.

BL-MVP-026E adopta exactamente ese patrón.

## Alcance

Este correctivo:

- vive dentro de `scripts/apply-bl-mvp-026e.ps1`;
- detecta Git Bash con el mismo patrón usado por los instaladores existentes del repositorio;
- reconoce si BL-MVP-026D ya modificó correctamente el verificador;
- si BL-MVP-026D no alcanzó a modificarlo, aplica de forma idempotente el mismo cambio;
- ejecuta `bash -n` usando la ruta real de Git Bash;
- ejecuta `git diff --check`;
- no modifica `Program.cs`, PostgreSQL, SQL maestro, `compose.yml`, Nginx ni certificados;
- no ejecuta `git add`, commit ni push.

## Resultado esperado

Debe terminar con:

```text
OK: cambio funcional de BL-MVP-026D ya presente.
Git Bash: <ruta a Git for Windows>\bash.exe
OK: bash -n aprobado con Git Bash.
OK: git diff --check aprobado.
OK: BL-MVP-026E validado.
```

Después debe volver a ejecutarse la puerta completa:

```powershell
.\scripts\apply-bl-mvp-026.ps1
```
