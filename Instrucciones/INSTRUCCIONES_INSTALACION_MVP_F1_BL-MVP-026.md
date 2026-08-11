# Instalación BL-MVP-026

## 1. Precondición exacta

Repositorio esperado:

```text
C:\Users\ul13m\Documents\GitHub\SistemaMusicaYAprender
```

La rama debe ser `main` y `HEAD` debe coincidir exactamente con la revisión publicada y GREEN de BL-MVP-028:

```text
60e71775dd6e85769bd6d8ace6bf5d9b4f6dc1ea
```

Antes de extraer el ZIP, abre PowerShell en la raíz y conserva la salida:

```powershell
git branch --show-current
git rev-parse HEAD
git status --short --untracked-files=all
git diff --check
```

Si existen cambios propios, detente y respáldalos. El instalador rechazará staging previo y rutas modificadas que no pertenezcan al paquete.

## 2. Extracción

Extrae `BL-MVP-026_Paquete_Instalacion.zip` directamente en la raíz del repositorio, sin crear una carpeta envolvente. Confirma la sustitución de archivos cuando Windows lo solicite.

No copies el Prompt Maestro al repositorio.

## 3. Ejecución completa

```powershell
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
Get-ChildItem .\scripts\*.ps1 -Recurse | Unblock-File
.\scripts\apply-bl-mvp-026.ps1
```

La primera ejecución puede tardar por la restauración reproducible, Chromium, compilación, pruebas y reconstrucción de contenedores. No uses `SkipBrowserInstall`, `SkipQualityGate`, `SkipStart`, `SkipRegistrationSmoke`, `SkipVerificationSmoke` ni `SkipLoginSmoke` para declarar GREEN.

## 4. Qué valida

El instalador comprueba:

1. rama `main`, revisión base exacta e inventario sin cambios ajenos;
2. toolchain fijado, secretos externos y Docker Compose;
3. TypeScript estricto, Prettier, build y verificadores del frontend;
4. analizadores, compilación .NET, pruebas unitarias y arquitectura;
5. Playwright/axe, teclado, pegado, gestores y reflujo a 320 CSS px;
6. regresiones de registro Argon2id y verificación de cuenta;
7. emisión de antiforgery y rechazo de un login mutable sin CSRF;
8. respuesta idéntica para contraseña errónea, correo desconocido y cuenta no activa;
9. cookie de sesión `__Host-`, `Secure`, `HttpOnly`, `SameSite=Strict`, `Path=/` y sin `Domain`;
10. almacenamiento exclusivo del SHA-256 del identificador opaco;
11. inactividad máxima de 12 horas y vencimiento absoluto máximo de 30 días;
12. rechazo server-side de sesiones vencidas o revocadas;
13. ausencia de credenciales y tokens en respuestas, logs y evidencia;
14. que no se ejecutó staging, commit, push ni migración de producción.

## 5. Resultado

El cierre completo debe mostrar:

```text
OK: BL-MVP-026 instalado y validado localmente con login, cookie segura, CSRF, expiracion y revocacion.
```

La restauración del `apps/web/tsconfig.app.tsbuildinfo` generado es automática.

## 6. Evidencia para revisión

Comparte:

- salida completa del instalador;
- `git status --short --untracked-files=all`;
- `git diff --check`;
- `git diff --stat`;
- `git diff --name-only`.

No ejecutes `git add`, `commit` ni `push` hasta confirmar el GREEN local y revisar todas las rutas.
