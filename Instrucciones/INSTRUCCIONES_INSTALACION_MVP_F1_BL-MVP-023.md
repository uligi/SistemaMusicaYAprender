# Instalación desde ZIP — F1 hasta BL-MVP-023

Esta guía instala y valida el estado actual de **Sistema Música y Aprender** en Windows. El corte incluido llega hasta **BL-MVP-023 — Registrar una cuenta personal**.

BL-MVP-023 crea una cuenta `PENDING` y su perfil mínimo mediante una operación idempotente y no enumerativa. Todavía no incluye consentimientos versionados, verificación por token, contraseña ni Argon2id; esas capacidades pertenecen a BL-MVP-024, 025 y 028.

El ZIP se extrae directamente sobre la raíz del repositorio. Su estructura replica las rutas reales del proyecto: por ejemplo, el instalador queda en `scripts\apply-bl-mvp-023.ps1` y el resto de los archivos cae en `apps`, `src`, `tests`, `config`, `docs` y sus demás destinos. El paquete parte de la base publicada BL-MVP-022 `3c1d957` y detiene la ejecución si detecta una instalación parcial.

El prompt maestro de continuación se entrega como archivo separado y **no forma parte del ZIP de instalación**.

## 1. Requisitos

- Windows 10 u 11 de 64 bits.
- PowerShell 5.1 o posterior.
- Git.
- Docker Desktop iniciado con **Linux containers** y Docker Compose v2.
- .NET SDK 9.0.x, según `global.json` y ADR-0001.
- Node.js 24.18.0.
- npm 11.16.0.

La arquitectura normativa ya apunta a .NET 10, pero este repositorio conserva temporalmente .NET 9 porque es la decisión ejecutable registrada en ADR-0001. No actualice el runtime durante esta instalación.

Puertos locales predeterminados:

| Servicio                                |              Puerto |
| --------------------------------------- | ------------------: |
| Web                                     |                5173 |
| API                                     |                5080 |
| PostgreSQL                              |                5432 |
| MinIO API / consola                     |         9000 / 9001 |
| Mailpit SMTP / UI                       |         1025 / 8025 |
| OpenTelemetry OTLP gRPC / HTTP / health | 4317 / 4318 / 13133 |

Si un puerto está ocupado, cierre el proceso que lo usa o defina otro valor en `.env` a partir de las variables documentadas en `.env.example`.

## 2. Preparar el repositorio y extraer el ZIP

El repositorio de trabajo está en:

```text
C:\Users\ul13m\Documents\GitHub\SistemaMusicaYAprender
```

Antes de extraer, compruebe que está en la rama y base esperadas y que no hay cambios propios que puedan ser sobrescritos:

```powershell
cd C:\Users\ul13m\Documents\GitHub\SistemaMusicaYAprender
git status --short --untracked-files=all
git log -1 --oneline
```

El último commit debe ser `3c1d957 test: preparar arnes E2E BL-MVP-022`. Si hay cambios distintos de BL-MVP-023, deténgase y respáldelos o comparta el estado antes de continuar.

Extraiga **el contenido** de `BL-MVP-023_Paquete_Instalacion.zip` dentro de:

```text
C:\Users\ul13m\Documents\GitHub\SistemaMusicaYAprender
```

No cree una carpeta intermedia. Después de extraer debe existir:

```text
C:\Users\ul13m\Documents\GitHub\SistemaMusicaYAprender\scripts\apply-bl-mvp-023.ps1
```

Si Windows pregunta por archivos existentes, confirme reemplazarlos: el ZIP contiene las versiones completas correspondientes a BL-MVP-023.

## 3. Habilitar los scripts para esta sesión

Primero permita scripts solo para la sesión actual y desbloquee los archivos descargados:

```powershell
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
Get-ChildItem .\scripts\*.ps1 -Recurse | Unblock-File
```

Verifique además que Docker Desktop esté abierto y configurado para **Linux containers**.

## 4. Instalación y validación completa

Ejecute:

```powershell
.\scripts\apply-bl-mvp-023.ps1
```

El instalador realiza estas operaciones:

1. comprueba que el historial contiene la base publicada BL-MVP-022 `3c1d957`;
2. valida Git, Docker, .NET, Node y npm;
3. genera secretos locales fuera de Git y valida Docker Compose;
4. restaura dependencias fijadas e instala Chromium de Playwright;
5. ejecuta la puerta local de calidad: formato, compilación, pruebas, arquitectura, límites modulares y Playwright/axe;
6. aplica el bootstrap y la migración local explícita, construye y levanta los siete servicios;
7. verifica health checks y prueba BL-MVP-023 contra la API y PostgreSQL reales;
8. elimina la identidad sintética creada por la prueba;
9. restaura `apps/web/tsconfig.app.tsbuildinfo` si TypeScript lo modificó;
10. muestra estado y diff sin ejecutar `git add`, commit ni push.

El final correcto es:

```text
OK: BL-MVP-023 instalado y validado localmente con API, PostgreSQL y navegador.
```

## 5. Comprobación manual

Abra:

- Web de registro: <http://localhost:5173/registro>
- Readiness de API: <http://localhost:5080/health/ready>
- Mailpit: <http://localhost:8025>
- MinIO: <http://localhost:9001>

En `/registro` compruebe:

1. solo se solicita correo; no aparece contraseña;
2. un correo inválido enfoca el campo y muestra una corrección asociada;
3. un correo válido devuelve una confirmación genérica;
4. la confirmación no indica si el correo ya existía;
5. la vista funciona con teclado y a 320 CSS px.

## 6. Si aparece un error

No modifique archivos a ciegas, no ejecute `git reset`, no borre volúmenes y no continúe con commit o push. Copie **toda la salida de PowerShell**, desde el primer comando hasta el error, y envíela en el chat.

Añada también esta evidencia:

```powershell
git status --short --untracked-files=all
git diff --check
git diff --stat
git diff --name-only
docker compose ps
docker compose logs --tail 200 api postgres web
```

Con esa salida se preparará un ZIP correctivo incremental, por ejemplo `BL-MVP-023A`, que contendrá únicamente los archivos que deban corregirse, siempre con sus rutas reales desde la raíz. Cada archivo incluido será una versión completa, no un fragmento para copiar manualmente.

Extraiga ese ZIP sobre la raíz del proyecto, confirme reemplazos y vuelva a ejecutar `.\scripts\apply-bl-mvp-023.ps1`. El ZIP correctivo solo incluirá otro PS1 cuando el propio instalador deba cambiar. El prompt maestro actualizado se descargará aparte y nunca estará dentro del ZIP. Cada corrección se validará antes de entregarse; no se asumirá que un error está resuelto sin volver a comprobar la salida.

## 7. Operación diaria

Iniciar o verificar de nuevo:

```powershell
.\scripts\local\start.ps1
.\scripts\local\verify-running.ps1
```

Detener sin borrar datos:

```powershell
.\scripts\local\stop.ps1
```

El comando siguiente elimina volúmenes y datos **solo locales**. No lo use como corrección automática ni contra datos reales:

```powershell
.\scripts\local\reset.ps1
```

## 8. Publicación: bloqueada hasta GREEN

No ejecute staging, commit, push ni CI mientras el instalador no termine sin omisiones y la revisión manual no sea satisfactoria.

Después de obtener GREEN, revise primero:

```powershell
git status --short --untracked-files=all
git diff --check
git diff --stat
git diff --name-only
git --no-pager diff
```

El staging debe ser explícito, revisado y limitado a BL-MVP-023. La instalación nunca publica cambios por sí sola.
