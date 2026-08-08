# BL-MVP-005A — Corrección de lectura UTF-8

El contenido de `pull_request_template.md` sí contiene `## Revisión requerida`.

El fallo se produce porque Windows PowerShell 5.1 puede interpretar un archivo UTF-8 sin BOM
usando la página de códigos local cuando se llama a `Get-Content`. En ese caso `Revisión`
se convierte internamente en texto mojibake y la comparación literal falla.

Este parche cambia el verificador para leer los archivos explícitamente como UTF-8 mediante
`System.IO.File.ReadAllText`.

## Uso

Copie la carpeta `scripts` sobre la carpeta `scripts` del repositorio y ejecute:

```powershell
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
Unblock-File .\scripts\*.ps1
.\scripts\apply-bl-mvp-005a-fixes.ps1
```

Si muestra que las plantillas fueron verificadas, continúe con:

```powershell
.\scripts\apply-bl-mvp-005.ps1
```
