# BL-MVP-025B — diagnóstico seguro del smoke integral

## Propósito

Este correctivo incremental hace observable el primer fallo real del smoke de BL-MVP-025 sin exponer correo, token, secreto ni payload.

La segunda ejecución de `scripts/apply-bl-mvp-025.ps1`, ya con BL-MVP-025A, aprobó restauración, analizadores, compilación, 8/8 pruebas Playwright, 4/4 pruebas unitarias, arquitectura, calidad y los siete servicios. El verificador integral devolvió código `1`, pero sus aserciones silenciosas no indicaron qué etapa falló.

## Cambio

`scripts/ci/identity/verify-account-verification.sh` ahora:

- conserva `set -e`, `pipefail` y la limpieza de identidades sintéticas;
- registra una etapa segura antes de cada bloque funcional;
- al fallar, imprime solo etapa y código de salida;
- si ya existe la cuenta sintética válida, muestra únicamente estado y contador de intentos de outbox/job, junto con un código de error controlado; y
- guarda el mismo resumen sanitizado en `artifacts/test-results/account-verification-smoke-failure.txt`.

No cambia API, worker, PostgreSQL, interfaz, token, consentimientos ni reglas funcionales. Tampoco imprime direcciones, códigos de verificación, claves, cuerpos de correo o payloads.

## Aplicación

1. No volver a extraer el paquete base ni BL-MVP-025A.
2. Extraer `BL-MVP-025B_Paquete_Correctivo.zip` directamente sobre la raíz del repositorio y aceptar la sobrescritura.
3. Ejecutar nuevamente, sin opciones `Skip`:

   ```powershell
   Get-ChildItem .\scripts\*.ps1 -Recurse | Unblock-File
   .\scripts\apply-bl-mvp-025.ps1
   ```

No ejecutar `git add`, commit ni push antes de obtener el cierre GREEN y revisar el inventario Git.
