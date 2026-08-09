# BL-MVP-009B — Corrección CA1859

El analizador `CA1859` se convirtió en error porque el repositorio usa
`TreatWarningsAsErrors=true`.

`RequireNonSecret` recibía `IConfiguration`, aunque dentro de este archivo siempre
se invoca con el `ConfigurationManager` de `builder.Configuration`.

La corrección cambia únicamente la firma privada:

```csharp
IConfiguration configuration
```

por:

```csharp
ConfigurationManager configuration
```

No cambia el comportamiento funcional ni el contrato de configuración.

Después de copiar el parche:

```powershell
Unblock-File .\scripts\*.ps1
.\scripts\apply-bl-mvp-009b.ps1
```

Si compila, vuelva a ejecutar:

```powershell
.\scripts\apply-bl-mvp-009.ps1
```
