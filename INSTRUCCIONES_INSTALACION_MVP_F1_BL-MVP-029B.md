# Instalación — BL-MVP-029B

## Precondición

Rama: `main`

HEAD:

`147e86ffe9b53435d7f277282f6c091aef3523d0`

BL-MVP-029A ya debe estar aplicado. La reejecución de BL-MVP-029 debe haberse detenido únicamente en
la prueba Playwright `personal-login-abuse.spec.ts`, con 13 pruebas aprobadas y 1 fallida.

## Extracción

Extrae `BL-MVP-029B_Paquete_Correctivo.zip` sobre la raíz del repositorio.

## Ejecución

```powershell
Get-ChildItem .\scripts\*.ps1 -Recurse | Unblock-File
.\scripts\apply-bl-mvp-029b.ps1
```

El correctivo ejecuta Prettier check, TypeScript E2E y la prueba Playwright focalizada.

Resultado esperado:

```text
OK: Prettier aprobado.
OK: TypeScript E2E aprobado.
OK: Playwright focalizado BL-MVP-029B aprobado.
OK: git diff --check aprobado.
OK: BL-MVP-029B aplicado y validado.
```

Después:

```powershell
.\scripts\apply-bl-mvp-029.ps1
```

Sin `Skip*`. No ejecutar staging, commit ni push hasta GREEN completo.
