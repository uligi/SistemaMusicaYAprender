# BL-MVP-003D - Corrección de Program.cs del Worker

Corrige el único error restante detectado en la compilación:

`CS0103: El nombre 'Host' no existe en el contexto actual`

El proyecto `MusicaAprender.Worker` usa el SDK base de .NET con una referencia al
framework ASP.NET Core, por lo que `Program.cs` necesita importar explícitamente:

- `Microsoft.Extensions.Hosting`
- `Microsoft.Extensions.DependencyInjection`

El script también conserva las reglas de formato del repositorio: UTF-8 sin BOM y LF.

## Uso

Copie la carpeta `scripts` sobre la carpeta `scripts` del repositorio y ejecute:

```powershell
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
Unblock-File .\scripts\*.ps1
.\scripts\apply-bl-mvp-003d-fixes.ps1
.\scripts\check-quality.ps1
```
