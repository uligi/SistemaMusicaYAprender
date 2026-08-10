# BL-MVP-022A — Corrección del apply para CRLF/LF en Windows

## Fallo observado

La primera ejecución de:

```powershell
.\scripts\apply-bl-mvp-022.ps1
```

se detuvo con:

```text
No se encontro el ancla esperada en scripts/check-quality.ps1.
```

El fallo ocurrió **antes** de instalar dependencias, ejecutar Playwright o validar BL-MVP-022.

## Causa

El apply original buscaba en `scripts/check-quality.ps1` un bloque multilínea mediante `String.Contains(...)` con saltos de línea exactos.

En Windows, Git puede materializar un `.ps1` con CRLF aunque el contenido lógico sea el mismo. El ancla del apply se construyó con LF, por lo que la comparación byte-a-byte falló.

El archivo real sí conserva la secuencia lógica esperada:

1. `restore-and-build.ps1`
2. pruebas unitarias
3. pruebas de arquitectura

No era un problema de la puerta de calidad ni de Playwright.

## Corrección

BL-MVP-022A reemplaza solamente:

```text
scripts/apply-bl-mvp-022.ps1
```

Ahora el apply:

- localiza una línea estable (`dotnet test tests/UnitTests/...`);
- verifica que `restore-and-build.ps1` aparezca antes;
- detecta si el archivo local usa CRLF o LF;
- inserta los pasos BL-MVP-022 conservando el estilo de EOL local;
- sigue siendo idempotente: si `verify-e2e-harness.mjs` ya está agregado, no duplica nada.

## Estado parcial de la primera ejecución

La primera ejecución alcanzó la edición de `.github/workflows/ci.yml` antes de fallar. Eso es seguro porque el apply ya comprueba si los pasos CI existen antes de intentar insertarlos nuevamente.

La instalación npm, Chromium, las pruebas E2E y la puerta de calidad **todavía no habían ocurrido**.

## Siguiente ejecución

Extraer este ZIP sobre la raíz del repositorio y aceptar la sobrescritura de:

```text
scripts\apply-bl-mvp-022.ps1
```

Luego ejecutar:

```powershell
.\scripts\apply-bl-mvp-022.ps1
```

No hacer `git add`, commit ni push hasta que la ejecución termine y se revise su salida.
