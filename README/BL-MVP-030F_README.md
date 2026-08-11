# BL-MVP-030F — importar xUnit en la prueba de scopes

## Motivo

La puerta completa de BL-MVP-030 avanzó correctamente por:

- reconciliación del `route-manifest`;
- toolchain;
- secret store;
- npm/Chromium;
- secret scan;
- TypeScript;
- Prettier;
- frontend build.

Se detuvo en `dotnet format --verify-no-changes` porque el nuevo archivo:

`tests/UnitTests/Modules/Security/AuthorizationScopeMatcherTests.cs`

usaba `[Fact]` sin importar `Xunit`.

Los errores fueron `CS0246` para `FactAttribute` y `Fact`.

## Corrección

BL-MVP-030F agrega únicamente:

```csharp
using Xunit;
```

al test nuevo. Es la misma convención que usan las pruebas existentes del repositorio.

El correctivo valida:

- toolchain;
- restore locked;
- `dotnet format --verify-no-changes`;
- build de `MusicaAprender.UnitTests.csproj`;
- ejecución de las unitarias;
- `git diff --check`.

No cambia el motor de autorización, los scopes, la API, PostgreSQL ni el frontend.
