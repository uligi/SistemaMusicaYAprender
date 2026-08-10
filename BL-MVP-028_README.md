# BL-MVP-028 — Política de credenciales y Argon2id

## Resultado

Este incremento completa la dependencia técnica requerida por BL-MVP-026. El registro personal ahora exige una contraseña larga, accesible y compatible con Unicode, y conserva únicamente un derivado Argon2id versionado en `security.credential`.

La base requerida es `e77dfabd303628f7106167defdd2b3ca6f033b0b`, donde BL-MVP-025 ya está publicada y GREEN. El paquete no ejecuta `git add`, `commit` ni `push`.

## Garantías incluidas

- política `PASSWORD_V1_2026-08-10`, 15–128 puntos de código, NFC, espacios y Unicode;
- sin reglas arbitrarias de composición y con pegado/gestores permitidos;
- rechazo local de valores comunes o comprometidos sin llamada externa de runtime;
- Argon2id v19 con 64 MiB, tres iteraciones, paralelismo uno, sal aleatoria de 16 bytes y derivado de 32 bytes;
- límites mínimos y máximos defensivos para configuración y verificación;
- creación atómica de cuenta y credencial bajo el RLS existente;
- huella HMAC con clave separada para preservar la semántica de `Idempotency-Key` sin persistir una huella rápida de la contraseña;
- secreto externo `identity_password_fingerprint_key` para local, Compose y CI;
- UI de registro con `autocomplete="new-password"`, ayuda, foco de error y limpieza tras aceptación;
- pruebas unitarias, E2E y smoke PostgreSQL/API que verifican política, derivación, parámetros, idempotencia y ausencia de texto claro.

## Fuera de alcance

BL-MVP-028 no implementa inicio de sesión, cookie, sesión, CSRF, cierre de sesión, rate limiting, recuperación, MFA ni auditoría completa. No modifica el SQL maestro, la migración inicial ni sus hashes: la tabla `security.credential`, el índice de credencial activa, las concesiones y RLS ya existen.

## Dependencia nueva

`Konscious.Security.Cryptography.Argon2` 1.3.1 queda fijada centralmente y en los lockfiles de todos los consumidores transitivos del módulo Security. La restauración en modo bloqueado sigue siendo reproducible.

## Validación esperada

Ejecuta desde PowerShell, en la raíz del repositorio:

```powershell
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
Get-ChildItem .\scripts\*.ps1 -Recurse | Unblock-File
.\scripts\apply-bl-mvp-028.ps1
```

No uses opciones `Skip*` para declarar GREEN. El cierre correcto es:

```text
OK: BL-MVP-028 instalado y validado localmente con política, Argon2id, PostgreSQL, API y navegador.
```

Después comparte la salida completa y `git status --short --untracked-files=all`. No publiques todavía si el instalador informa una omisión o un fallo.
