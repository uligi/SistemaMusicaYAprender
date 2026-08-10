# BL-MVP-026D — corrección del verificador de cookies

## Motivo

La ejecución local de BL-MVP-026 alcanzó el smoke de login después de aprobar compilación, calidad,
E2E, unitarias, PostgreSQL, contenedores y regresiones. El smoke reportó falsamente que la cookie
antifalsificación no contenía `Path=/`.

La comprobación manual por la misma ruta de mismo origen usada por el smoke confirmó un `HTTP 200`
y una cabecera equivalente a:

`Set-Cookie: __Host-MusicaAprender.Csrf=<redacted>; path=/; secure; samesite=strict; httponly`

El contrato de la aplicación es correcto. El falso RED queda aislado al uso de `grep` con here-string
dentro de `assert_contains_ci()` y a la comprobación equivalente de `Domain`.

## Alcance

Este correctivo:

- modifica exclusivamente `scripts/ci/identity/verify-personal-login.sh`;
- reemplaza las dos comparaciones `grep` sobre here-string por comparación nativa de Bash;
- mantiene las comprobaciones de `Path=/`, `Secure`, `HttpOnly`, `SameSite=Strict` y ausencia de `Domain`;
- no modifica `Program.cs`, PostgreSQL, SQL maestro, `compose.yml`, Nginx ni certificados;
- no ejecuta `git add`, commit ni push;
- después de aplicarse exige volver a ejecutar la puerta completa `scripts/apply-bl-mvp-026.ps1`.

## Instalación

Extraer el ZIP directamente sobre la raíz del repositorio, sin carpeta envolvente, y ejecutar:

```powershell
Get-ChildItem .\scripts\*.ps1 -Recurse | Unblock-File
.\scripts\apply-bl-mvp-026d.ps1
```

Después, si BL-MVP-026D termina correctamente:

```powershell
.\scripts\apply-bl-mvp-026.ps1
```

No usar opciones `Skip*`. BL-MVP-026 no se considera GREEN hasta que el instalador completo termine
correctamente y se revise el inventario.
