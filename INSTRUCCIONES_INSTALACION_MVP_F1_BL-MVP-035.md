# Instalación desde ZIP — F1 hasta BL-MVP-035

Esta guía instala y valida **BL-MVP-035 — Publicar catálogos y parámetros efectivos mínimos** sobre la base publicada BL-MVP-023 `b8ec17b`.

El ZIP replica las rutas reales del repositorio y se extrae directamente sobre su raíz. No contiene carpeta envolvente. El instalador debe quedar en `scripts\apply-bl-mvp-035.ps1`. El prompt maestro de continuación se entrega separado y nunca forma parte del ZIP.

## 1. Requisitos

- Windows 10 u 11 de 64 bits.
- PowerShell 5.1 o posterior.
- Git.
- Docker Desktop iniciado con Linux containers y Docker Compose v2.
- .NET SDK 9.0.x, conforme a `global.json` y ADR-0001.
- Node.js 24.18.0.
- npm 11.16.0.

No mezcle una migración a .NET 10 ni cambios de esquema con esta historia.

## 2. Preparar y extraer

Abra PowerShell y ejecute:

```powershell
cd C:\Users\ul13m\Documents\GitHub\SistemaMusicaYAprender
git status --short --untracked-files=all
git log -1 --oneline
```

La base esperada es:

```text
b8ec17b feat: registrar cuenta personal BL-MVP-023
```

Si hay cambios propios que puedan coincidir con los archivos del paquete, deténgase y respáldelos o comparta primero el estado.

Extraiga **el contenido** de `BL-MVP-035_Paquete_Instalacion.zip` en:

```text
C:\Users\ul13m\Documents\GitHub\SistemaMusicaYAprender
```

No cree una carpeta intermedia. Después de extraer debe existir:

```text
C:\Users\ul13m\Documents\GitHub\SistemaMusicaYAprender\scripts\apply-bl-mvp-035.ps1
```

## 3. Ejecutar la validación completa

Con Docker Desktop abierto y usando Linux containers:

```powershell
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
Get-ChildItem .\scripts\*.ps1 -Recurse | Unblock-File
.\scripts\apply-bl-mvp-035.ps1
```

El instalador:

1. comprueba la base `b8ec17b` y el inventario de BL-MVP-035;
2. valida Git, Docker, .NET, Node y npm;
3. prepara secretos locales ignorados y valida Compose;
4. instala dependencias y Chromium fijados;
5. ejecuta formato, compilación, pruebas, arquitectura, límites y Playwright/axe;
6. aplica el bootstrap y la migración local ya existente, y levanta los siete servicios;
7. verifica readiness y dependencias;
8. valida en PostgreSQL los 12 catálogos, 59 entradas, 10 parámetros, 4 roles y 3 políticas;
9. exige `minimum-configuration = Healthy` en la API real;
10. muestra estado y diff sin ejecutar staging, commit ni push.

El final esperado es:

```text
OK: BL-MVP-035 instalado y validado localmente con API, PostgreSQL y la puerta completa.
```

## 4. Comprobación manual

Abra:

- <http://localhost:5080/health/ready>
- <http://localhost:5080/health/dependencies>

En ambas respuestas, `minimum-configuration` debe aparecer una sola vez y con estado `Healthy`. El endpoint no debe exponer valores de parámetros, secretos ni la lista de elementos ausentes.

BL-MVP-035 no agrega pantalla de administración: `UI-MVP-030` mutable pertenece a BL-MVP-036, después del motor de permisos y la auditoría requeridos.

## 5. Si aparece un error

No ejecute `git reset`, no borre volúmenes, no cambie semillas manualmente y no continúe con commit o push. Envíe toda la salida de PowerShell desde el inicio hasta el primer error, junto con:

```powershell
git status --short --untracked-files=all
git diff --check
git diff --stat
git diff --name-only
docker compose ps
docker compose logs --tail 200 api postgres
```

Se preparará un ZIP correctivo incremental `BL-MVP-035A`, `BL-MVP-035B`, etc. Cada ZIP contendrá solo los archivos completos que deban cambiar, con sus rutas desde la raíz. Se extrae sobre el mismo repositorio y se vuelve a ejecutar `.\scripts\apply-bl-mvp-035.ps1`. El prompt actualizado seguirá entregándose por separado.

## 6. Publicación bloqueada hasta GREEN

No ejecute `git add`, commit, push ni CI hasta que el instalador termine sin switches `Skip` y se revise:

```powershell
git status --short --untracked-files=all
git diff --check
git diff --stat
git diff --name-only
git --no-pager diff
```

La instalación no publica cambios. Después de recibir la salida completa se preparará la secuencia de staging explícito, commit y push correspondiente a BL-MVP-035.
