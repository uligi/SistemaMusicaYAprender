# BL-MVP-025C — correo canónico en el smoke integral

## Propósito

Este correctivo incremental alinea la aserción SMTP del smoke de BL-MVP-025 con la canonización de correo ya implementada y validada por el producto.

La tercera ejecución de `scripts/apply-bl-mvp-025.ps1`, ya con BL-MVP-025A y BL-MVP-025B, aprobó restauración, analizadores, compilación, 8/8 pruebas Playwright, 4/4 pruebas unitarias, arquitectura, calidad y los siete servicios. El diagnóstico seguro aisló el fallo en `entrega-correo-valido`; PostgreSQL confirmó `email_job|SUCCEEDED|1|` y `outbox|PROCESSED|0|`.

## Causa

El registro protege la dirección después de normalizarla a mayúsculas. El worker descifra y entrega esa dirección canónica. El verificador encontraba el mensaje correcto por su asunto y validaba el token, pero buscaba en el detalle de Mailpit la dirección sintética original en minúsculas. Esa comparación sensible a mayúsculas mantenía `mail_found=false` aunque la entrega SMTP hubiera finalizado correctamente.

## Cambio

`scripts/ci/identity/verify-account-verification.sh` ahora:

- calcula explícitamente la forma canónica de la dirección sintética válida con la misma regla ASCII ya usada para su hash de búsqueda; y
- comprueba que Mailpit conserve esa dirección canónica junto con el token esperado.

No cambia API, worker, PostgreSQL, interfaz, token, plantilla, destinatario real ni reglas funcionales. Tampoco imprime direcciones, códigos de verificación, claves, cuerpos de correo o payloads.

## Aplicación

1. No volver a extraer el paquete base, BL-MVP-025A ni BL-MVP-025B.
2. Extraer `BL-MVP-025C_Paquete_Correctivo.zip` directamente sobre la raíz del repositorio y aceptar la sobrescritura.
3. Ejecutar nuevamente, sin opciones `Skip`:

   ```powershell
   Get-ChildItem .\scripts\*.ps1 -Recurse | Unblock-File
   .\scripts\apply-bl-mvp-025.ps1
   ```

No ejecutar `git add`, commit ni push antes de obtener el cierre GREEN y revisar el inventario Git.
