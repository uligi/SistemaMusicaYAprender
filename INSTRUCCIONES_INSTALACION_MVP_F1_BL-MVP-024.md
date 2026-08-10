# Instalación desde ZIP — F1 hasta BL-MVP-024

Esta guía instala y valida **BL-MVP-024 — Registrar consentimientos vigentes y versionados** sobre la base publicada BL-MVP-035 `44d716e`.

BL-MVP-024 amplía el registro existente: la API publica las versiones vigentes de términos y privacidad, exige ambas decisiones afirmativas y conserva dos evidencias append-only dentro de la misma transacción que crea la cuenta `PENDING` y el perfil mínimo. No incluye todavía token de verificación, credencial, sesión ni autorización.

El ZIP se extrae directamente sobre la raíz del repositorio y contiene 14 archivos con sus rutas reales. El Prompt Maestro se entrega por separado y no forma parte del paquete.

## 1. Requisitos

- Windows 10 u 11 de 64 bits.
- PowerShell 5.1 o posterior.
- Git for Windows, incluido Git Bash.
- Docker Desktop iniciado con Linux containers y Docker Compose v2.
- .NET SDK 9.0.x, según `global.json` y ADR-0001.
- Node.js 24.18.0.
- npm 11.16.0.

La arquitectura normativa ya apunta a .NET 10, pero este corte conserva .NET 9 por la decisión ejecutable vigente. No mezcle esa migración con BL-MVP-024.

## 2. Preparar y extraer

Repositorio:

```text
C:\Users\ul13m\Documents\GitHub\SistemaMusicaYAprender
```

Antes de extraer:

```powershell
cd C:\Users\ul13m\Documents\GitHub\SistemaMusicaYAprender
git status --short --untracked-files=all
git log -3 --oneline
```

El último commit debe ser:

```text
44d716e feat: publicar configuracion minima BL-MVP-035
```

Si hay cambios propios posteriores, deténgase antes de aceptar sobrescrituras y comparta el estado.

Extraiga **el contenido** de `BL-MVP-024_Paquete_Instalacion.zip` dentro de la raíz. No cree una carpeta intermedia. Debe quedar:

```text
C:\Users\ul13m\Documents\GitHub\SistemaMusicaYAprender\scripts\apply-bl-mvp-024.ps1
```

Confirme reemplazos cuando Windows lo solicite: cada archivo incluido es una versión completa.

## 3. Ejecutar la validación completa

```powershell
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
Get-ChildItem .\scripts\*.ps1 -Recurse | Unblock-File
.\scripts\apply-bl-mvp-024.ps1
```

El instalador:

1. exige que `HEAD` descienda de `44d716e`;
2. valida Git, Git Bash, Docker, .NET, Node y npm;
3. prepara secretos locales fuera de Git y valida Compose;
4. restaura dependencias e instala Chromium fijado;
5. ejecuta formato, compilación, pruebas, arquitectura, límites modulares y Playwright/axe;
6. construye y levanta los siete servicios;
7. comprueba el health check de configuración mínima;
8. prueba las versiones vigentes, la alta atómica y los rechazos contra API/PostgreSQL reales;
9. comprueba que las aceptaciones confirmadas no pueden modificarse;
10. elimina la identidad sintética con un procedimiento administrativo limitado al arnés;
11. restaura `apps/web/tsconfig.app.tsbuildinfo` si fue generado; y
12. muestra el inventario Git sin ejecutar staging, commit ni push.

El cierre correcto es:

```text
OK: BL-MVP-024 instalado y validado localmente con API, PostgreSQL y navegador.
```

## 4. Comprobación manual

Abra:

- Registro: <http://localhost:5173/registro>
- Catálogo técnico vigente: <http://localhost:5080/api/v1/auth/registration-consents>
- Readiness: <http://localhost:5080/health/ready>

Compruebe en `/registro`:

1. aparecen términos y privacidad con versión `2026-08-10`;
2. ambos controles se alcanzan y activan con teclado;
3. sin una aceptación el formulario conserva el correo y enfoca el primer control pendiente;
4. tras aceptar ambos, la respuesta sigue siendo genérica y no revela si el correo ya existía;
5. no aparece todavía contraseña; y
6. a 320 CSS px no hay recorte ni desplazamiento horizontal.

La versión visible es un identificador técnico. El texto jurídico definitivo debe pasar la aprobación legal/editorial correspondiente antes de producción.

## 5. Si aparece un error

No ejecute `git add`, commit, push, `git reset` ni borre volúmenes como corrección automática. Envíe toda la salida de PowerShell y además:

```powershell
git status --short --untracked-files=all
git diff --check
git diff --stat
git diff --name-only
docker compose ps
docker compose logs --tail 200 api postgres web
```

Se preparará un ZIP correctivo incremental `BL-MVP-024A`, luego `024B`, etc., solo con los archivos completos que deban cambiar y sus rutas desde la raíz. El Prompt Maestro continuará entregándose aparte.

## 6. Publicación bloqueada hasta GREEN

No publique mientras el instalador no termine sin switches `Skip` y la revisión manual no sea satisfactoria. Después del GREEN se entregará un bloque de staging explícito limitado a los 14 archivos de BL-MVP-024.

El instalador nunca ejecuta `git add`, commit, push ni migraciones de producción.
