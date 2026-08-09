# BL-MVP-006C — Limpieza de documentación

Este parche corrige dos detalles documentales detectados después del push de BL-MVP-006:

1. elimina marcas `filecite` que son referencias internas de ChatGPT y no pertenecen al repositorio;
2. cambia la versión documentada de MinIO para que coincida con `compose.yml`:
   `RELEASE.2025-04-22T22-12-26Z`.

No modifica el comportamiento de Docker ni los contenedores.

## Uso

Copie la carpeta `scripts` sobre la carpeta `scripts` del repositorio y ejecute:

```powershell
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
Unblock-File .\scripts\*.ps1
.\scripts\apply-bl-mvp-006c.ps1
```

Después:

```powershell
git status
git add .
git commit -m "docs: alinear documentacion Docker BL-MVP-006C"
git push origin main
```
