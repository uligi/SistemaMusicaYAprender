# Instalación desde ZIP — F1 hasta BL-MVP-025

Esta guía instala y valida **BL-MVP-025 — Verificar la cuenta mediante token de un uso** sobre la base publicada BL-MVP-024 `4f0342c`.

El ZIP amplía el registro existente con emisión atómica, correo versionado, pantalla `/verificar-cuenta`, consumo único, vencimiento, revalidación de consentimientos y reenvío no enumerable. No incorpora contraseña, inicio de sesión ni recuperación.

Extraiga el contenido directamente sobre la raíz del repositorio. El Prompt Maestro se entrega por separado y no forma parte del paquete.

## 1. Requisitos

- Windows 10 u 11 de 64 bits.
- PowerShell 5.1 o posterior.
- Git for Windows, incluido Git Bash.
- Docker Desktop iniciado con Linux containers y Docker Compose v2.
- .NET SDK 9.0.x, según `global.json` y ADR-0001.
- Node.js 24.18.0.
- npm 11.16.0.

La arquitectura normativa apunta a .NET 10, pero este corte conserva .NET 9 por la decisión ejecutable vigente. No mezcle esa migración con BL-MVP-025.

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
4f0342c feat: registrar consentimientos versionados BL-MVP-024
```

Si hay cambios propios posteriores, deténgase antes de aceptar sobrescrituras y comparta el estado.

Extraiga **el contenido** de `BL-MVP-025_Paquete_Instalacion.zip` dentro de la raíz. No cree una carpeta intermedia. Debe quedar:

```text
C:\Users\ul13m\Documents\GitHub\SistemaMusicaYAprender\scripts\apply-bl-mvp-025.ps1
```

Confirme reemplazos cuando Windows lo solicite: cada archivo incluido es una versión completa.

## 3. Ejecutar la validación completa

```powershell
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
Get-ChildItem .\scripts\*.ps1 -Recurse | Unblock-File
.\scripts\apply-bl-mvp-025.ps1
```

El instalador:

1. exige que `HEAD` descienda de `4f0342c`;
2. valida Git, Git Bash, Docker, .NET, Node y npm;
3. crea la nueva clave local fuera de Git y valida Compose;
4. restaura dependencias e instala Chromium fijado;
5. ejecuta formato, compilación, unit, arquitectura y Playwright/axe;
6. aplica solo los accesos PostgreSQL auxiliares aprobados, sin tocar el modelo físico;
7. construye y levanta los siete servicios;
8. registra cuentas sintéticas y espera el correo real en Mailpit;
9. verifica éxito/replay, manipulación, caducidad y prerrequisitos contra API/PostgreSQL reales;
10. compara reenvío para cuenta pendiente y correo inexistente, incluida idempotencia;
11. comprueba que outbox, logs y evidencia no contienen correo ni token;
12. elimina las identidades sintéticas con un procedimiento administrativo limitado al arnés; y
13. muestra el inventario Git sin ejecutar staging, commit ni push.

El cierre correcto es:

```text
OK: BL-MVP-025 instalado y validado localmente con API, worker, SMTP, PostgreSQL y navegador.
```

## 4. Comprobación manual

Abra:

- Registro: <http://localhost:5173/registro>
- Verificación: <http://localhost:5173/verificar-cuenta>
- Mailpit: <http://localhost:8025>
- Readiness: <http://localhost:5080/health/ready>

Compruebe:

1. registre un correo de prueba con términos y privacidad;
2. abra el correo cuyo asunto comienza con `[BL025][ACCOUNT_VERIFICATION:v1]`;
3. copie solo el código y péguelo manualmente en `/verificar-cuenta`;
4. confirme el estado “Cuenta verificada”;
5. repita el código y confirme la misma respuesta, sin nueva activación;
6. solicite otro código para un correo inexistente y compruebe que la respuesta es indistinguible; y
7. use teclado y ancho de 320 CSS px sin recorte horizontal.

No coloque el código en la URL, capturas, logs ni mensajes. Mailpit es solo infraestructura local de desarrollo.

## 5. Si aparece un error

No ejecute `git add`, commit, push, `git reset` ni borre volúmenes como corrección automática. Envíe toda la salida de PowerShell y además:

```powershell
git status --short --untracked-files=all
git diff --check
git diff --stat
git diff --name-only
docker compose ps
docker compose logs --tail 200 api worker postgres web smtp-sink
```

No copie el cuerpo del correo ni el token. Se preparará un ZIP correctivo incremental `BL-MVP-025A`, luego `025B`, etc., solo con los archivos completos que deban cambiar y sus rutas desde la raíz.

## 6. Publicación bloqueada hasta GREEN

No publique mientras el instalador no termine sin switches `Skip`, la revisión manual no sea satisfactoria y el CI remoto no esté verde. Después se entregará un bloque de staging explícito limitado a los archivos de BL-MVP-025.

El instalador nunca ejecuta `git add`, commit, push ni migraciones de producción.
