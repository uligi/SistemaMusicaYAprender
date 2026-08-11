# BL-MVP-032 — MFA y reautenticación en acciones privilegiadas

**Historia · 8 SP · dependencias 026 y 030**

Trazabilidad: CU-MVP-23 y CU-MVP-25; UI-MVP-029 y UI-MVP-031; CE-09 y CE-14.

Resultado: los actores privilegiados no acceden ni ejecutan acciones sensibles sin factor
adicional o reautenticación vigente.

## Entrega

- catálogo de política `MFA-POLICY-1` con TOTP de seis dígitos y 30 segundos como factor P0.
- Inscripción con contraseña actual y confirmación independiente.
- Retos ligados a cuenta, sesión, propósito y expiración; máximo cinco intentos.
- Retos consumidos no reutilizables y contadores TOTP de step-up protegidos contra repetición.
- Secreto TOTP cifrado mediante `IObjectStore`; PostgreSQL conserva referencia opaca.
- `security.session.assurance_level = MFA` después del step-up.
- Aserción reciente por sesión de 15 minutos.
- Sesión reforzada con inactividad máxima de 15 minutos y absoluto máximo de ocho horas.
- filtro backend reutilizable `RequireRecentPrivilegedAssurance()`.
- `/administracion/roles` incorpora inscripción/step-up y no muestra la gestión hasta confirmar
  la verificación reforzada.
- role assignment catalog/list/grant/revoke requieren permiso efectivo **y** MFA reciente.
- smoke real API/PostgreSQL/MinIO y E2E accesible.

BL-MVP-033 sigue siendo responsable de la auditoría primaria transversal. BL-MVP-032 no implementa
la pantalla de auditoría UI-MVP-031; deja lista la puerta de assurance que ese flujo reutilizará.
