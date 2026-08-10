# BL-MVP-027 — Cerrar sesión y revocar sesiones

## Definición normativa

- Fase: F1 — Identidad, acceso y configuración.
- Tipo: Historia.
- Traza: CU-MVP-03; UI-MVP-007; CE-01.
- Story Points: 3.
- Dependencia: BL-MVP-026.
- Resultado: cerrar sesión invalida la sesión actual y las rutas protegidas dejan de aceptar la
  cookie sin afectar otras cuentas.

## Implementación

Se agrega `POST /api/v1/auth/logout` con autorización y antiforgery. ASP.NET Core ejecuta el
`SignOutAsync` sobre el mismo esquema cookie de BL-MVP-026; el `ITicketStore` ya existente revoca
únicamente el identificador opaco de la sesión presentada y la respuesta elimina la cookie
`__Host-MusicaAprender.Session`.

UI-MVP-007 muestra `Cerrar sesión` cuando existe una sesión visible. Al confirmar el cierre, el
contexto de acceso vuelve a anónimo y una ruta protegida exige autenticación otra vez.

## Evidencia

- Playwright dedicado: teclado, foco, CSRF, cambio a estado anónimo, axe y ruta protegida.
- Smoke API/PostgreSQL con dos sesiones concurrentes:
  - logout sin CSRF = 400 y no revoca;
  - logout válido = 200;
  - reutilizar la cookie cerrada = 401;
  - la otra sesión continúa = 200;
  - PostgreSQL refleja una revocada y una activa.
- CI ejecuta el smoke BL-MVP-027 después de BL-MVP-026.

## Fuera de alcance

- rate limiting, bloqueo y límites de sesión: BL-MVP-029;
- motor de permisos efectivos: BL-MVP-030;
- MFA/reautenticación privilegiada: BL-MVP-032;
- auditoría primaria completa: BL-MVP-033;
- revocar todas las sesiones de una cuenta;
- cambios de SQL maestro, migración inicial o esquema físico.
