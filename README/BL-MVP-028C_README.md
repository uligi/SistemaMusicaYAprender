# BL-MVP-028C — corrección diagnóstica del smoke de credenciales

## Motivo

La tercera ejecución de `scripts/apply-bl-mvp-028.ps1` aprobó la puerta local completa, 9/9 pruebas E2E, 14/14 pruebas unitarias, límites modulares, PostgreSQL, migraciones, compilación de imágenes y salud de los siete servicios. Se detuvo en `scripts/ci/identity/verify-personal-registration.sh`, pero las comparaciones directas bajo `set -e` solo devolvieron código 1 y no identificaron el contrato incumplido.

La comparación del objetivo temporal de Argon2id también dependía de la interpretación numérica de `awk`, que puede variar con la configuración regional de Git Bash aunque `curl` siempre emita el tiempo con punto decimal.

## Alcance

Este correctivo:

- conserva el objetivo obligatorio de derivación de al menos 100 ms;
- interpreta el tiempo con `Number` de Node.js, independientemente de la configuración regional;
- da nombre y valores no sensibles a cada aserción HTTP, temporal, idempotente y PostgreSQL;
- nunca imprime contraseñas, cuerpos de solicitud, hashes, sales, correos ni secretos;
- no modifica API, web, worker, PostgreSQL, Argon2id, parámetros, secretos, contratos ni pruebas;
- reutiliza el instalador completo `scripts/apply-bl-mvp-028.ps1` del paquete base.

## Instalación

Después de haber extraído BL-MVP-028, BL-MVP-028A y BL-MVP-028B, extraer este ZIP sobre la raíz del repositorio, aceptar la sobrescritura y ejecutar:

```powershell
Get-ChildItem .\scripts\*.ps1 -Recurse | Unblock-File
.\scripts\apply-bl-mvp-028.ps1
```

No volver a extraer los paquetes anteriores. No usar opciones `Skip*` ni ejecutar `git add`, commit o push antes de revisar el GREEN y el inventario.
