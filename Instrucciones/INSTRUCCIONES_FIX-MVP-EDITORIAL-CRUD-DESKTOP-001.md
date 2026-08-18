# Instalación FIX-MVP-EDITORIAL-CRUD-DESKTOP-001

Base exigida:

`ede5b0d30a6c103136c0da946fa9aa6522f0e889`

El instalador exige rama `main` y permite como único archivo no rastreado el propio instalador.
No ejecuta `git add`, `commit`, `push` ni cambia de rama.

Desde la raíz:

```powershell
Get-ChildItem .\scripts\*.ps1 -Recurse | Unblock-File

powershell.exe -NoProfile -ExecutionPolicy Bypass `
  -File .\scripts\apply-fix-mvp-editorial-crud-desktop-001.ps1
```

Después pega:

```powershell
git status --short --untracked-files=all
git diff --check
git diff --stat
git diff --name-status
```

No hagas staging todavía.
