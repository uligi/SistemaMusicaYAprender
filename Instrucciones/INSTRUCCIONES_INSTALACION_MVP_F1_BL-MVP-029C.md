# Instalación — BL-MVP-029C

## Precondición

Rama: `main`

HEAD:

`147e86ffe9b53435d7f277282f6c091aef3523d0`

BL-MVP-029A y BL-MVP-029B ya fueron extraídos. 029B se detuvo únicamente durante su validación
PowerShell antes de ejecutar Prettier/TypeScript/Playwright.

## Extracción

Extrae `BL-MVP-029C_Paquete_Correctivo.zip` directamente sobre la raíz del repositorio.

## Ejecución

```powershell
Get-ChildItem .\scripts\*.ps1 -Recurse | Unblock-File
.\scripts\apply-bl-mvp-029c.ps1
```

Resultado esperado:

```text
OK: Prettier aprobado.
OK: TypeScript E2E aprobado.
OK: Playwright focalizado BL-MVP-029C aprobado.
OK: git diff --check aprobado.
OK: BL-MVP-029C aplicado y validado.
```

Después ejecuta:

```powershell
.\scripts\apply-bl-mvp-029.ps1
```

Sin `Skip*`. No ejecutar staging, commit ni push hasta GREEN completo.
