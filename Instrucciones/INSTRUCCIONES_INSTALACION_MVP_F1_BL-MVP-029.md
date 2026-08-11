# Instalación desde ZIP — BL-MVP-029

## Base requerida

Repositorio:

`C:\Users\ul13m\Documents\GitHub\SistemaMusicaYAprender`

Rama:

`main`

HEAD exacto:

`147e86ffe9b53435d7f277282f6c091aef3523d0`

Commit:

`chore: limpiar temporal Office y proteger archivos Word`

GitHub Actions debe estar en Success para esa revisión.

## Alcance

BL-MVP-029 agrega limitación temporal no enumerativa:

- 5 fallos por clave de cuenta / 15 min;
- 20 fallos por cliente / 15 min;
- recuperación automática;
- `Retry-After`;
- eventos seudonimizados;
- comprobación de 12 h / 30 días y revocación de sesión.

No modifica el SQL maestro ni la migración inicial.

## Extracción

Extrae `BL-MVP-029_Paquete_Instalacion.zip` directamente en la raíz del repositorio, sin carpeta
envolvente.

El instalador vive en:

`scripts/apply-bl-mvp-029.ps1`

Dos archivos existentes (`compose.yml` y
`src/BuildingBlocks/Infrastructure/Configuration/ExternalConfigurationExtensions.cs`) reciben
transformaciones exactas controladas por el instalador para incorporar el nuevo secreto y la
política.
El instalador se detiene si la base no coincide con el contrato esperado.

## Ejecución

```powershell
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
Get-ChildItem .\scripts\*.ps1 -Recurse | Unblock-File
.\scripts\apply-bl-mvp-029.ps1
```

No uses opciones `Skip*` para declarar GREEN.

## Validación esperada

La puerta completa debe aprobar:

- toolchain fijada;
- secret scan;
- TypeScript/Prettier/Vite;
- build y analizadores .NET;
- Playwright/axe;
- unitarias y arquitectura;
- Docker Compose y siete servicios Healthy;
- regresiones BL-MVP-026 y BL-MVP-027;
- smoke real BL-MVP-029 en API HTTPS standalone y PostgreSQL.

El smoke usa una ventana temporal de 30 segundos exclusivamente para comprobar recuperación sin
esperar 15 minutos. Los valores predeterminados de runtime siguen siendo 900 segundos, 5 fallos por
cuenta y 20 por cliente.

Cierre esperado:

```text
OK: BL-MVP-029 instalado y validado localmente con limites de abuso, recuperacion y sesion
revocable.
```

No ejecutar `git add`, commit ni push hasta revisar la salida completa y el inventario.
