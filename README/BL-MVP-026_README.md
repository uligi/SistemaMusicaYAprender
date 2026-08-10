# BL-MVP-026 — Inicio de sesión con cookie segura de mismo origen

## Resultado

Este incremento implementa CU-MVP-03 y UI-MVP-007 sobre la base publicada `60e71775dd6e85769bd6d8ace6bf5d9b4f6dc1ea`, donde BL-MVP-023 y BL-MVP-028 ya están GREEN. Una cuenta personal activa y verificada puede autenticarse con su credencial Argon2id y obtiene una sesión opaca, revocable y validada por el servidor en cada solicitud.

El paquete no ejecuta `git add`, `commit` ni `push` y no modifica el SQL maestro ni la migración inicial.

## Garantías incluidas

- respuesta `401` uniforme para correo desconocido, contraseña incorrecta y cuenta no activa;
- verificación Argon2id aun en rutas rechazadas para reducir diferencias observables;
- sesión persistida en `security.session` con un SHA-256 del identificador opaco, nunca con el identificador en claro;
- cookie `__Host-MusicaAprender.Session`, `HttpOnly`, `Secure`, `SameSite=Strict`, `Path=/` y sin `Domain`;
- vencimiento por inactividad de 12 horas y absoluto de 30 días;
- cuenta, expiración y revocación comprobadas en PostgreSQL en cada solicitud autenticada;
- token antifalsificación requerido por `POST /api/v1/auth/login` mediante cookie `__Host-` y encabezado `X-CSRF-TOKEN`;
- consulta de sesión por `GET /api/v1/auth/session`, sin devolver identificadores de cuenta, sesión ni tokens;
- UI accesible con teclado, pegado y gestores de credenciales, foco de corrección y limpieza de contraseña;
- ausencia de sesión en URL, `localStorage` y `sessionStorage`;
- pruebas unitarias, E2E y smoke real para respuesta no enumerable, cookies, CSRF, expiración y revocación.
- TLS interno local entre Nginx y Kestrel, con certificado autofirmado fuera del repositorio, para conservar `SecurePolicy=Always` durante el smoke de mismo origen.

## Endpoints

| Método | Ruta                   | Protección                   | Resultado                                 |
| ------ | ---------------------- | ---------------------------- | ----------------------------------------- |
| GET    | `/api/v1/auth/csrf`    | Mismo origen, `no-store`     | Token de solicitud y nombre de encabezado |
| POST   | `/api/v1/auth/login`   | Antiforgery obligatorio      | Cookie de sesión o problema genérico      |
| GET    | `/api/v1/auth/session` | Cookie y validación servidor | Estado autenticado y rol seguro           |

## Fuera de alcance

BL-MVP-026 no incorpora cierre de sesión visible (BL-MVP-027), límites de intentos o sesiones y controles de abuso (BL-MVP-029), permisos efectivos (BL-MVP-030), recuperación, MFA ni auditoría completa (BL-MVP-033). El rol `STUDENT` del ticket es el contexto mínimo para la sesión; cada operación protegida seguirá necesitando autorización del servidor y los permisos efectivos se incorporarán en su BL dedicado.

## Validación esperada

Desde PowerShell, en la raíz del repositorio:

```powershell
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
Get-ChildItem .\scripts\*.ps1 -Recurse | Unblock-File
.\scripts\apply-bl-mvp-026.ps1
```

No uses opciones `Skip*` para declarar GREEN. El cierre correcto es:

```text
OK: BL-MVP-026 instalado y validado localmente con login, cookie segura, CSRF, expiracion y revocacion.
```

Después comparte la salida completa y `git status --short --untracked-files=all`. No publiques hasta revisar el inventario.
