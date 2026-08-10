# BL-MVP-026A — Correctivo de análisis estático del token de sesión

## Motivo

La primera ejecución del instalador de BL-MVP-026 alcanzó la compilación .NET y se detuvo porque `CA1822` se trata como error. `SecuritySessionTokenService.CreateToken` y `TryHashToken` no accedían a estado de instancia.

## Corrección

- `SecuritySessionTokenService` pasa a ser una utilidad estática y sus dos operaciones se marcan `static`;
- se retira su registro singleton y la inyección innecesaria en `SecuritySessionTicketStore`;
- los consumidores y las pruebas unitarias invocan explícitamente las operaciones estáticas;
- el instalador admite este README dentro del inventario protegido acumulado de 27 rutas.

No cambia el formato del identificador opaco, el uso de 32 bytes aleatorios, la codificación Base64URL, el SHA-256 persistido, la cookie, CSRF ni los contratos funcionales de BL-MVP-026.

## Aplicación

Extrae únicamente `BL-MVP-026A_Paquete_Correctivo.zip` sobre la raíz donde ya se extrajo BL-MVP-026, acepta las sobrescrituras y ejecuta:

```powershell
Get-ChildItem .\scripts\*.ps1 -Recurse | Unblock-File
.\scripts\apply-bl-mvp-026.ps1
```

No vuelvas a extraer el paquete base, no uses opciones `Skip*` para declarar GREEN y no ejecutes `git add`, commit ni push antes de revisar la salida completa.
