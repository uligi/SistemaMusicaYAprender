# BL-MVP-030I — corregir CA1707 en nombres de pruebas

## Motivo

030H ya confirmó:

- sintaxis PowerShell correcta;
- preservación de `scope_type = OBJECT`;
- `dotnet format` y analyzers del código de producción;
- compilación correcta del módulo Security sin CA1720.

El siguiente fallo apareció al compilar `MusicaAprender.UnitTests`:

```text
CA1707: Quite los caracteres de subrayado del nombre de miembro
```

Afectó exclusivamente los cinco métodos nuevos de `AuthorizationScopeMatcherTests.cs`.

## Corrección

BL-MVP-030I renombra los métodos a PascalCase sin `_`:

- `UnscopedAssignmentGrantsGlobalModuleAndTargetScopes`
- `ModuleAssignmentIsNotGlobal`
- `ModuleAssignmentGrantsOnlyItsModuleAndTargets`
- `TargetAssignmentRequiresExactTarget`
- `UnknownOrMalformedScopeFailsClosed`

También se evita usar `Object` en nombres de miembros del test para no reintroducir CA1720.

No cambia assertions, casos cubiertos ni lógica del motor.

## Validación

030I ejecuta:

- toolchain;
- restore locked;
- `dotnet format --verify-no-changes`;
- build de UnitTests;
- UnitTests;
- restauración defensiva de `tsconfig.app.tsbuildinfo`;
- `git diff --check`.
