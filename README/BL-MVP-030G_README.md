# BL-MVP-030G — corregir CA1720 en el enum interno de alcance

## Motivo

Después de 030F, `dotnet format --verify-no-changes` quedó aprobado, pero el build del módulo
Security se detuvo por el analizador:

```text
CA1720: El identificador “Object” contiene el nombre de tipo.
```

El identificador afectado era el miembro interno:

```csharp
AuthorizationScopeKind.Object
```

No era el valor físico `scope_type = 'OBJECT'` de PostgreSQL.

## Corrección

BL-MVP-030G renombra exclusivamente el miembro interno del enum:

```text
Object -> Target
```

y actualiza `AuthorizationScopeMatcher`.

La API pública `AuthorizationScope.ForObject(...)` se conserva y el matcher continúa reconociendo
el valor físico:

```text
OBJECT
```

Por tanto no cambia el contrato de base de datos, el modelo físico, los scopes persistidos ni la
semántica de autorización.

## Validación

030G ejecuta:

- toolchain;
- restore locked;
- `dotnet format --verify-no-changes`;
- build del módulo Security;
- build de UnitTests;
- UnitTests;
- restauración defensiva de `tsconfig.app.tsbuildinfo`;
- `git diff --check`.

No modifica SQL, API HTTP, frontend, permisos ni sesiones.
