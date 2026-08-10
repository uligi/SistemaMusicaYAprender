# BL-MVP-024B — Estado estable al aceptar consentimientos

## Fallo observado

Después de aplicar BL-MVP-024A, la segunda ejecución completa de:

```powershell
.\scripts\apply-bl-mvp-024.ps1
```

aprobó restauración, formato, compilación y cuatro de las cinco pruebas Playwright. La prueba de
registro localizó y validó ambos checkboxes, pero el segundo dejó de existir inmediatamente después
de activar el primero con `Space`:

```text
Locator: locator('#registration-consent-privacy_policy')
Error: element(s) not found
```

## Causa

El manejador `onChange` consultaba `event.currentTarget.checked` dentro del actualizador funcional de
estado. React puede ejecutar ese actualizador cuando el evento sintético ya no conserva su
`currentTarget`; el acceso tardío interrumpía la representación del formulario después de marcar el
primer consentimiento.

## Corrección

BL-MVP-024B reemplaza únicamente:

```text
apps/web/src/routes/public/PersonalAccountRegistrationPage.tsx
```

El manejador captura el valor booleano de `checked` mientras el evento sigue vigente y entrega ese
valor inmutable al actualizador de estado. La prueba de BL-MVP-024A permanece sin cambios y continúa
recorriendo el formulario con `Tab`, `Space` y `Enter`.

## Alcance

No cambia el contrato HTTP, las versiones exigidas, la transacción de registro, PostgreSQL,
idempotencia, secretos, migraciones ni CI. Tampoco incorpora verificación, credenciales o sesiones.

## Siguiente ejecución

Extraiga este ZIP sobre la raíz del repositorio, acepte la sobrescritura de la página y ejecute de
nuevo, sin switches `Skip`:

```powershell
Get-ChildItem .\scripts\*.ps1 -Recurse | Unblock-File
.\scripts\apply-bl-mvp-024.ps1
```

No ejecute `git add`, commit ni push hasta revisar la salida completa y obtener el cierre GREEN.
