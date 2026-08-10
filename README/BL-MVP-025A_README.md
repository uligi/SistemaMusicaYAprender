# BL-MVP-025A — correctivo de nombres CA1707

## Propósito

Este correctivo incremental permite que la prueba unitaria nueva de BL-MVP-025 compile con los analizadores .NET habilitados como errores.

La primera ejecución de `scripts/apply-bl-mvp-025.ps1` llegó hasta `dotnet build` y falló únicamente con tres diagnósticos `CA1707` en los nombres públicos de los métodos de `AccountVerificationTokenServiceTests`.

## Cambio

Se reemplazan los tres nombres con guion bajo por nombres PascalCase sin guiones bajos:

- `CreateTokenRoundTripsSignedIdentifiersAndHash`
- `TryReadTokenRejectsTamperedMaterial`
- `ConstructorRejectsKeysWithUnexpectedLength`

Los cuerpos, datos y aserciones de las pruebas permanecen intactos. No cambia el token, la API, el worker, PostgreSQL, los consentimientos ni el alcance funcional de BL-MVP-025.

## Aplicación

1. No volver a extraer `BL-MVP-025_Paquete_Instalacion.zip`.
2. Extraer `BL-MVP-025A_Paquete_Correctivo.zip` directamente sobre la raíz del repositorio y aceptar la sobrescritura.
3. Ejecutar nuevamente, sin opciones `Skip`:

   ```powershell
   Get-ChildItem .\scripts\*.ps1 -Recurse | Unblock-File
   .\scripts\apply-bl-mvp-025.ps1
   ```

No ejecutar `git add`, commit ni push antes de obtener el cierre GREEN y revisar el inventario Git.
