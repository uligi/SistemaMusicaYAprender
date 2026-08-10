# BL-MVP-026C — Correctivo de validación antifalsificación del login

## Motivo

La tercera ejecución del instalador de BL-MVP-026 confirmó que `SecuritySessionTokenService` ya compila y que el estado incremental de TypeScript se restaura correctamente. La compilación se detuvo después en `PersonalAccountLoginEndpoint` porque `RouteHandlerBuilder` no expone `RequireAntiforgery()` en la configuración actual de la API.

## Corrección

- se retira exclusivamente la llamada no resoluble a `RequireAntiforgery()`;
- el manejador recibe `IAntiforgery` desde inyección de dependencias;
- antes de verificar credenciales o crear una sesión, invoca `ValidateRequestAsync(HttpContext)`;
- un token ausente o inválido se transforma en un problema HTTP 400 con código estable `identity.login.csrf.invalid`;
- el instalador admite este README dentro del inventario protegido acumulado de 29 rutas.

No se deshabilita CSRF. Se conservan `AddAntiforgery`, `UseAntiforgery`, la cookie `__Host-MusicaAprender.Csrf`, el encabezado `X-CSRF-TOKEN` y el smoke que exige HTTP 400 cuando falta el token. Tampoco cambian la verificación Argon2id, la no enumeración, la cookie de sesión, PostgreSQL ni los contratos funcionales de BL-MVP-026.

## Aplicación

Extrae únicamente `BL-MVP-026C_Paquete_Correctivo.zip` sobre la raíz donde ya se extrajeron BL-MVP-026, BL-MVP-026A y BL-MVP-026B, acepta las sobrescrituras y ejecuta:

```powershell
Get-ChildItem .\scripts\*.ps1 -Recurse | Unblock-File
.\scripts\apply-bl-mvp-026.ps1
```

No vuelvas a extraer paquetes anteriores, no uses opciones `Skip*` para declarar GREEN y no ejecutes `git add`, commit ni push antes de revisar la salida completa.
