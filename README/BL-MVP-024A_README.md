# BL-MVP-024A — Locator estable para el recorrido de teclado

## Fallo observado

La primera ejecución completa de:

```powershell
.\scripts\apply-bl-mvp-024.ps1
```

aprobó restauración, formato, compilación y cuatro de las cinco pruebas Playwright. La prueba de
registro se detuvo al comprobar el foco del checkbox de privacidad:

```text
getByRole('checkbox', { name: /Acepto política de privacidad.*2026-08-10/i })
Error: element(s) not found
```

El mismo control había sido localizado y validado como visible antes de iniciar el recorrido de
teclado. La aplicación y las otras pruebas de consentimiento no fallaron.

## Causa

La prueba reutilizaba un locator por rol y nombre accesible durante una actualización controlada de
React. Después de activar el primer checkbox con `Space`, Playwright volvía a resolver el segundo
control mediante su nombre accesible completo. Esa resolución resultó inestable en Chromium aunque
el input conserva un identificador DOM determinista y su etiqueta accesible correcta.

## Corrección

BL-MVP-024A reemplaza únicamente:

```text
tests/E2ETests/base-accessibility.spec.ts
```

Los dos checkboxes se localizan ahora mediante sus identificadores estables:

```text
#registration-consent-terms_of_use
#registration-consent-privacy_policy
```

La prueba sigue comprobando por separado que cada input expone el nombre accesible con finalidad y
versión, y conserva el recorrido real con `Tab`, `Space` y `Enter`. No se relaja la cobertura de
teclado, accesibilidad, versión o respuesta genérica.

## Alcance

No cambia la interfaz, el contrato HTTP, la transacción de registro, PostgreSQL, consentimientos,
idempotencia, secretos, migraciones ni CI. Tampoco incorpora verificación, credenciales o sesiones.

## Siguiente ejecución

Extraiga este ZIP sobre la raíz del repositorio, acepte la sobrescritura del archivo E2E y ejecute
de nuevo, sin switches `Skip`:

```powershell
Get-ChildItem .\scripts\*.ps1 -Recurse | Unblock-File
.\scripts\apply-bl-mvp-024.ps1
```

No ejecute `git add`, commit ni push hasta revisar la salida completa y obtener el cierre GREEN.
