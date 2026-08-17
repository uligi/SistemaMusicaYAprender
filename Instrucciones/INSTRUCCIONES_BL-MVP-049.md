# Instalación BL-MVP-049

Base exigida:

`24e263f010b55f70109f840a6def802ccc8cf31f`

El instalador:

- verifica rama `main`;
- verifica el SHA exacto;
- exige working tree limpia antes de aplicar;
- no ejecuta `git add`, `git commit`, `git push` ni crea ramas;
- crea/actualiza únicamente archivos de BL049;
- deja el instalador como temporal para borrarlo antes del staging.

Ejecutar desde la raíz:

```powershell
Get-ChildItem .\scripts\*.ps1 -Recurse | Unblock-File

powershell.exe -NoProfile -ExecutionPolicy Bypass `
  -File .\scripts\apply-bl-mvp-049-review-workflow.ps1
```

Después pegar únicamente:

```powershell
git status --short --untracked-files=all
git diff --check
git diff --stat
git diff --name-status
```

No hacer staging todavía.
