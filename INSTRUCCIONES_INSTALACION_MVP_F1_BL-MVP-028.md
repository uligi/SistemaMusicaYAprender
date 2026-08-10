# Instalación BL-MVP-028

## 1. Precondición

Repositorio esperado:

```text
C:\Users\ul13m\Documents\GitHub\SistemaMusicaYAprender
```

BL-MVP-025 debe estar publicada en `main` y la revisión `e77dfabd303628f7106167defdd2b3ca6f033b0b` debe ser ancestro de `HEAD`.

Antes de extraer el ZIP, abre PowerShell en la raíz y conserva la salida:

```powershell
git status --short --untracked-files=all
git log -5 --oneline --decorate
git diff --check
```

Si existen cambios propios no relacionados, detente y respáldalos antes de sobrescribir rutas.

## 2. Extracción

Extrae `BL-MVP-028_Paquete_Instalacion.zip` directamente en la raíz del repositorio, sin crear una carpeta envolvente. Confirma la sustitución de archivos cuando Windows lo solicite.

No copies el Prompt Maestro al repositorio.

## 3. Ejecución completa

```powershell
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
Get-ChildItem .\scripts\*.ps1 -Recurse | Unblock-File
.\scripts\apply-bl-mvp-028.ps1
```

La primera ejecución puede tardar por la instalación de Chromium, restauración de NuGet, compilación y reconstrucción de contenedores. No uses `SkipBrowserInstall`, `SkipQualityGate`, `SkipStart`, `SkipRegistrationSmoke` ni `SkipVerificationSmoke` para declarar GREEN.

## 4. Qué valida

El instalador comprueba:

1. base publicada BL-MVP-025 y toolchain fijado;
2. secretos externos, incluido `identity_password_fingerprint_key`;
3. definición Docker Compose;
4. restauración bloqueable y lockfiles de Argon2id;
5. TypeScript, Prettier, build de frontend y verificadores estáticos;
6. analizadores, compilación .NET, pruebas unitarias y arquitectura;
7. Playwright/axe, teclado, pegado y reflujo de 320 CSS px;
8. servicios locales y health checks;
9. registro real con contraseña Unicode y creación atómica de credencial;
10. parámetros Argon2id, sal individual, bloqueo local, idempotencia y ausencia de texto claro;
11. que BL-MVP-025 continúa verificando token, worker y SMTP;
12. que no se ejecutó staging, commit, push ni migración de producción.

## 5. Resultado

El cierre completo debe mostrar:

```text
OK: BL-MVP-028 instalado y validado localmente con política, Argon2id, PostgreSQL, API y navegador.
```

También mostrará el estado y el inventario de archivos modificados. La restauración del `tsconfig.app.tsbuildinfo` generado es automática.

## 6. Entrega de evidencia

Comparte:

- salida completa del instalador;
- `git status --short --untracked-files=all`;
- `git diff --check`;
- `git diff --stat`;
- `git diff --name-only`.

No ejecutes `git add`, `commit` ni `push` hasta revisar el inventario y confirmar el GREEN local.
