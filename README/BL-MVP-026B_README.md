# BL-MVP-026B — Correctivo de estado incremental TypeScript

## Motivo

La segunda ejecución del instalador de BL-MVP-026 se detuvo antes de las validaciones porque `apps/web/tsconfig.app.tsbuildinfo` había cambiado durante el `tsc -b` de la primera ejecución. El archivo está rastreado en la base publicada, pero es una salida incremental del compilador y no forma parte del delta funcional de BL-MVP-026.

## Corrección

- el instalador exige primero que el índice Git esté vacío;
- restaura exclusivamente `apps/web/tsconfig.app.tsbuildinfo` desde `HEAD` antes de validar el inventario;
- vuelve a restaurarlo en un bloque `finally`, tanto si las puertas terminan correctamente como si una validación posterior falla;
- conserva el rechazo de cualquier otra ruta ajena al paquete;
- admite este README dentro del inventario protegido acumulado de 28 rutas.

No cambia el login, la cookie, CSRF, el token opaco, la persistencia, PostgreSQL ni los contratos funcionales de BL-MVP-026.

## Aplicación

Extrae únicamente `BL-MVP-026B_Paquete_Correctivo.zip` sobre la raíz donde ya se extrajeron BL-MVP-026 y BL-MVP-026A, acepta la sobrescritura del instalador y ejecuta:

```powershell
Get-ChildItem .\scripts\*.ps1 -Recurse | Unblock-File
.\scripts\apply-bl-mvp-026.ps1
```

No borres ni restaures manualmente otros archivos, no vuelvas a extraer los paquetes anteriores, no uses opciones `Skip*` para declarar GREEN y no ejecutes `git add`, commit ni push antes de revisar la salida completa.
