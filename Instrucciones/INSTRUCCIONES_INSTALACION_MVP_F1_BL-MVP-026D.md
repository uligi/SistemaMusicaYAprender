# Instrucciones de instalación — BL-MVP-026D

Repositorio esperado:
`C:\Users\ul13m\Documents\GitHub\SistemaMusicaYAprender`

## 1. Extracción

Extraer `BL-MVP-026D_Paquete_Instalacion.zip` directamente en la raíz del repositorio.

El ZIP no contiene carpeta envolvente. Al extraer debe quedar, entre otros:

- `scripts/apply-bl-mvp-026d.ps1`
- `README/BL-MVP-026D_README.md`
- `INSTRUCCIONES_INSTALACION_MVP_F1_BL-MVP-026D.md`

## 2. Aplicación

Desde PowerShell en la raíz:

```powershell
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
Get-ChildItem .\scripts\*.ps1 -Recurse | Unblock-File
.\scripts\apply-bl-mvp-026d.ps1
```

El instalador modifica de forma controlada únicamente:

`./scripts/ci/identity/verify-personal-login.sh`

La modificación se rehúsa si no encuentra los bloques exactos esperados. También tolera una segunda
ejecución si el correctivo ya fue aplicado.

## 3. Validación completa

Si el correctivo termina en OK:

```powershell
.\scripts\apply-bl-mvp-026.ps1
```

No usar `Skip*`.

## 4. Prohibiciones hasta GREEN

No ejecutar:

- `git add`
- `git commit`
- `git push`

Después del GREEN se revisarán `git status`, `git diff --check`, `git diff --stat`,
`git diff --name-only` y el inventario antes de staging.
