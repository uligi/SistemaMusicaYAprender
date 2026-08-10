# BL-MVP-028A — corrección de formato Markdown

## Motivo

La primera ejecución de `scripts/apply-bl-mvp-028.ps1` se detuvo en `npm run format:check` porque Prettier 3.9.6 exigía realinear la tabla de parámetros de `docs/engineering/security/argon2id-password-policy.md`.

## Alcance

Este correctivo:

- aplica únicamente el formato determinista de Prettier a la tabla;
- conserva intactos texto, parámetros, código de producto y pruebas;
- no modifica API, web, worker, PostgreSQL, Argon2id, secretos ni contratos;
- reutiliza el instalador completo `scripts/apply-bl-mvp-028.ps1` del paquete base.

## Instalación

Después de haber extraído el paquete base BL-MVP-028, extraer este ZIP sobre la raíz del repositorio, aceptar la sobrescritura y ejecutar:

```powershell
Get-ChildItem .\scripts\*.ps1 -Recurse | Unblock-File
.\scripts\apply-bl-mvp-028.ps1
```

No volver a extraer el paquete base. No usar opciones `Skip*` ni ejecutar `git add`, commit o push antes de revisar el GREEN y el inventario.
