# BL-MVP-028D — normalización CRLF de métricas HTTP

## Motivo

La cuarta ejecución de `scripts/apply-bl-mvp-028.ps1` aprobó la puerta local completa, 9/9 pruebas E2E, 14/14 pruebas unitarias, límites modulares, PostgreSQL, migraciones, compilación de imágenes y salud de los siete servicios. El diagnóstico añadido por BL-MVP-028C confirmó que el registro válido devolvió el estado HTTP esperado `202`, pero Git Bash conservó un retorno de carro al leer la salida multilínea de `curl`, por lo que el smoke comparó `202\r` con `202`.

## Alcance

Este correctivo:

- elimina únicamente retornos de carro de las dos métricas que `curl` escribe en su salida estándar: estado HTTP y tiempo total;
- mantiene intactos el cuerpo JSON guardado en archivo y todas las aserciones del smoke;
- conserva el objetivo obligatorio de derivación Argon2id de al menos 100 ms;
- no modifica API, web, worker, PostgreSQL, Argon2id, parámetros, secretos, contratos ni pruebas;
- no imprime contraseñas, cuerpos de solicitud, correos, hashes, sales ni secretos;
- reutiliza el instalador completo `scripts/apply-bl-mvp-028.ps1` del paquete base.

## Instalación

Después de haber extraído BL-MVP-028 y los correctivos BL-MVP-028A, BL-MVP-028B y BL-MVP-028C, extraer este ZIP sobre la raíz del repositorio, aceptar la sobrescritura y ejecutar:

```powershell
Get-ChildItem .\scripts\*.ps1 -Recurse | Unblock-File
.\scripts\apply-bl-mvp-028.ps1
```

No volver a extraer los paquetes anteriores. No usar opciones `Skip*` ni ejecutar `git add`, commit o push antes de revisar el GREEN y el inventario.
