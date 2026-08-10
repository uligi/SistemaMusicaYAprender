# Instalación — BL-MVP-027B

## Precondición

Repositorio:

`C:\Users\ul13m\Documents\GitHub\SistemaMusicaYAprender`

Rama: `main`

HEAD:

`32a2cbdb5bf0102b3e527cb1998fb5a227a56294`

BL-MVP-027A debe haber terminado en:

```text
OK: BL-MVP-027A aplicado y validado.
```

y el intento posterior de BL-MVP-027 debe haberse detenido únicamente por los archivos 027A no
reconocidos en el inventario.

## Extracción

Extrae `BL-MVP-027B_Paquete_Correctivo.zip` directamente sobre la raíz del repositorio, sin carpeta
envolvente.

El paquete incluye la versión completa corregida de:

`scripts/apply-bl-mvp-027.ps1`

además del instalador y documentación B.

## Ejecución

```powershell
Get-ChildItem .\scripts\*.ps1 -Recurse | Unblock-File
.\scripts\apply-bl-mvp-027b.ps1
```

Resultado esperado:

```text
OK: sintaxis PowerShell de apply-bl-mvp-027.ps1 aprobada.
OK: git diff --check aprobado.
OK: BL-MVP-027B aplicado y validado.
```

Después:

```powershell
.\scripts\apply-bl-mvp-027.ps1
```

No usar `Skip*`. No ejecutar staging, commit ni push hasta que la puerta completa quede GREEN.
