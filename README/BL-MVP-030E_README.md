# BL-MVP-030E — corregir `.Count` bajo StrictMode

## Motivo

BL-MVP-030D sí completó los siete reemplazos legacy restantes, pasó Prettier, pasó TypeScript y
restauró `apps/web/tsconfig.app.tsbuildinfo`.

Después falló únicamente en su validación final con:

```text
No se encuentra la propiedad 'Count' en este objeto.
```

La causa está en esta forma de PowerShell:

```powershell
$legacy = @(
    "..."
) | Where-Object { ... }
```

El `@(...)` envolvía solo la colección de entrada, no el resultado del pipeline. Bajo
`Set-StrictMode -Version Latest`, cuando `Where-Object` devuelve cero o un elemento, la variable
puede no conservar una colección con `.Count` disponible de la forma esperada.

## Corrección

030E y la versión reconciliada de 030D envuelven **todo el resultado del pipeline**:

```powershell
$legacy = @(
    @(
        "..."
    ) | Where-Object { ... }
)
```

Así `.Count` es estable para 0, 1 o N resultados.

030E no vuelve a cambiar el `route-manifest`: valida el estado dejado por 030D, exige cero aliases
legacy y todos los permisos canónicos, ejecuta Prettier, TypeScript, restaura `tsbuildinfo` y hace
`git diff --check`.

No cambia el motor de autorización ni su diseño.
