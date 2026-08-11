# BL-MVP-030J — actualizar regresión de logout al contrato de sesión BL-MVP-030

## Evidencia del RED

La puerta completa BL-MVP-030 llegó a Playwright con:

```text
15 passed
1 failed
```

El único fallo fue:

`tests/E2ETests/personal-logout.spec.ts`

porque no apareció el botón `Cerrar sesión`.

## Causa

BL-MVP-030 amplía `GET /api/v1/auth/session` para devolver:

- `role`;
- `roles`;
- `capabilities`.

`AccessContext` consume `capabilities` para construir el snapshot visible de acceso.

La regresión E2E de BL-MVP-027 seguía simulando el contrato anterior:

```json
{
  "status": "AUTHENTICATED",
  "role": "STUDENT"
}
```

Por tanto el test ya no representaba una respuesta válida de sesión BL-MVP-030.

## Corrección

El mock se actualiza a:

```json
{
  "status": "AUTHENTICATED",
  "role": "STUDENT",
  "roles": ["STUDENT"],
  "capabilities": ["PROFILE.READ", "CONTENT.READ", "LEARNING.START"]
}
```

No se relaja `AccessContext` para aceptar respuestas incompletas. El contrato nuevo permanece
estricto y la prueba antigua se adapta al contrato vigente.

No cambia la lógica de logout, autorización, cookie, CSRF ni servidor.
