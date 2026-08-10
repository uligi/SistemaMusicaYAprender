# Instalación BL-MVP-027

## Precondición

Repositorio:

`C:\Users\ul13m\Documents\GitHub\SistemaMusicaYAprender`

Rama: `main`

HEAD esperado:

`32a2cbdb5bf0102b3e527cb1998fb5a227a56294`

BL-MVP-026 y su correctivo G deben estar publicados con GitHub Actions en Success.

## Extracción

Extrae `BL-MVP-027_Paquete_Instalacion.zip` directamente sobre la raíz del repositorio, sin carpeta
envolvente.

Los movimientos históricos de README ya verificados pueden permanecer en el working tree. El
instalador los tolera, pero no los modifica ni los incorpora a BL-MVP-027. El temporal `~$...docx`
de Office también queda fuera.

## Ejecución

```powershell
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
Get-ChildItem .\scripts\*.ps1 -Recurse | Unblock-File
.\scripts\apply-bl-mvp-027.ps1
```

No usar opciones `Skip*` para declarar GREEN.

## Resultado esperado

La puerta completa valida quality, Playwright/axe, runtime, regresión BL-MVP-026 y el smoke real de
cierre/revocación. El cierre esperado es:

```text
OK: BL-MVP-027 instalado y validado localmente con cierre de sesion, CSRF y revocacion aislada.
```

No ejecutar staging, commit ni push hasta revisar la salida y el inventario.
