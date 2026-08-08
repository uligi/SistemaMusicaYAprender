# BL-MVP-004A — Corrección de referencia xUnit

El proyecto de pruebas ya tiene las dependencias de xUnit, pero `EntityTests.cs`
no importaba el espacio de nombres `Xunit`. Por eso C# no encontraba `[Fact]`.

Este parche agrega:

```csharp
using Xunit;
```

y conserva las reglas del repositorio: UTF-8 sin BOM y LF.

## Uso

Copie la carpeta `scripts` encima de la carpeta `scripts` del repositorio y ejecute:

```powershell
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
Unblock-File .\scripts\*.ps1
.\scripts\apply-bl-mvp-004a-fixes.ps1
.\scripts\check-quality.ps1
```
