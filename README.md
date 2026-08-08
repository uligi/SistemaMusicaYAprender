# BL-MVP-004B — Corrección CA1707 en la primera prueba unitaria

El analizador de .NET está configurado como error de compilación y no permite guiones bajos
en nombres de miembros públicos (`CA1707`).

Se cambia:

```csharp
Constructor_PreservesIdentifier()
```

por:

```csharp
ConstructorPreservesIdentifier()
```

## Uso

Copie la carpeta `scripts` sobre la carpeta `scripts` del repositorio y ejecute:

```powershell
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
Unblock-File .\scripts\*.ps1
.\scripts\apply-bl-mvp-004b-fixes.ps1
.\scripts\check-quality.ps1
```
