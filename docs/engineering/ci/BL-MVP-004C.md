# BL-MVP-004C — Actualización de GitHub Actions a Node 24+

La ejecución inicial de BL-MVP-004 fue exitosa, pero GitHub mostró una advertencia porque
las versiones `v4` de varias Actions todavía declaraban Node.js 20 como runtime interno.

Se actualizan únicamente las Actions del workflow, sin cambiar la lógica del pipeline:

- `actions/checkout@v7`
- `actions/setup-dotnet@v6`
- `actions/setup-node@v7`
- `actions/upload-artifact@v7`

El objetivo es mantener el mismo comportamiento aprobado en BL-MVP-004 y eliminar la
advertencia de deprecación de Node.js 20.

## Aplicación

Copie el contenido del ZIP sobre la raíz del repositorio y reemplace archivos.

Luego ejecute:

```powershell
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
Unblock-File .\scripts\*.ps1
.\scripts\apply-bl-mvp-004c.ps1
```

Si la puerta local termina correctamente:

```powershell
git status
git add .
git commit -m "ci: actualizar GitHub Actions a Node 24 BL-MVP-004C"
git push origin main
```

En GitHub, confirme que el workflow `CI` termina en verde y que ya no aparece la
advertencia de Node.js 20.
