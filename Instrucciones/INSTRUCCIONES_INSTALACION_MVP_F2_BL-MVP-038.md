# Instalación — BL-MVP-038

Base exacta esperada:

`f4151ec6b433c2a55a3bfbe1fafc36494eb2458a`

## 1. Extraer

Extraiga `BL-MVP-038_Paquete_Instalacion.zip` directamente sobre la raíz del repositorio:

`C:\Users\ul13m\Documents\GitHub\SistemaMusicaYAprender`

El ZIP agrega doce archivos nuevos. El instalador modifica de forma controlada seis archivos ya versionados.

## 2. Ejecutar

```powershell
Get-ChildItem .\scripts\*.ps1 -Recurse | Unblock-File

powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\apply-bl-mvp-038.ps1
```

No ejecute `git add`, commit ni push antes de que el instalador termine en GREEN y se revise el inventario.

## 3. Validaciones incluidas

El instalador ejecuta:

- rama `main` y HEAD exacto;
- índice Git sin staging previo;
- inventario limitado a BL-MVP-038;
- toolchain fijada;
- Docker Compose;
- secret store local;
- restore .NET locked;
- formato .NET focalizado;
- `npm ci`;
- Prettier;
- sintaxis Bash;
- Chromium Playwright;
- puerta local completa;
- entorno Docker reproducible;
- health checks;
- smoke real contra API/PostgreSQL;
- restauración del `tsconfig.app.tsbuildinfo`;
- `git diff --check`;
- inventario final.

## 4. Evidencia esperada del smoke

Debe verificar, entre otros:

- acceso anónimo denegado;
- editor sintético con permiso vigente;
- artista canónico reutilizable;
- URL de YouTube normalizada a `external_ref`;
- obra, grabación y fuente con UUID distintos;
- estado DRAFT;
- duración de grabación separada de duración de fuente;
- replay idempotente;
- conflicto para la misma clave con contenido distinto;
- referencia de YouTube inválida rechazada;
- `external_ref` exacto ya usado bloqueado;
- título similar detectado como duplicado potencial;
- auditoría `CATALOG.SONG_DRAFT.CREATE`;
- no se descarga ni almacena audiovisual.

## 5. Tras GREEN

Primero revisar:

```powershell
git diff --check
git status --short --untracked-files=all
git diff --stat
git diff --name-status
```

Solo después se preparará staging explícito de las rutas aprobadas. Nunca use `git add .` para este incremento.
