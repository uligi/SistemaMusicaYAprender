# Instalación coordinada BL-MVP-050 + BL-MVP-051

Base exigida:

`0f883f389314f1d06737444a7ff35f87444348cf`

El instalador exige `main`, SHA exacto y working tree limpia salvo el propio instalador. Aplica BL050 y BL051 con documentos/pruebas separados, no crea migración y no ejecuta `git add`, `git commit`, `git push` ni crea ramas.

Ejecutar desde la raíz:

```powershell
Get-ChildItem .\scripts\*.ps1 -Recurse | Unblock-File

powershell.exe -NoProfile -ExecutionPolicy Bypass `
  -File .\scripts\apply-bl-mvp-050-051-publication-correction.ps1
```

Después:

```powershell
git status --short --untracked-files=all
git diff --check
git diff --stat
git diff --name-status
```

No hacer staging todavía.
