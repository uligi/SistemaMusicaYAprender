# BL-MVP-030H — corregir parser de PowerShell en 030G

## Motivo

`apply-bl-mvp-030g.ps1` no llegó a ejecutar ninguna validación. Windows PowerShell rechazó el
archivo al parsearlo porque dos expresiones `if` dividían la condición antes del operador `-or`:

```powershell
if ($scopeContent.Contains(...)
    -or $matcherContent.Contains(...)) {
```

El error fue `MissingEndParenthesisAfterStatement`.

Esto significa que el RED de 030G fue del script de validación, no una nueva evidencia contra la
corrección `AuthorizationScopeKind.Object -> AuthorizationScopeKind.Target`.

## Corrección

030H reemplaza esas expresiones por variables booleanas explícitas y un `if` convencional:

```powershell
$scopeHasLegacyObject = ...
$matcherHasLegacyObject = ...

if ($scopeHasLegacyObject -or $matcherHasLegacyObject) {
```

También agrega una validación de sintaxis usando el parser nativo de PowerShell para:

- `apply-bl-mvp-030.ps1`
- `apply-bl-mvp-030g.ps1`
- `apply-bl-mvp-030h.ps1`

Después ejecuta el mismo tramo técnico que 030G: format/analyzers, build Security, build/test de
UnitTests y `git diff --check`.

No modifica la semántica del motor de autorización ni el contrato PostgreSQL `OBJECT`.
