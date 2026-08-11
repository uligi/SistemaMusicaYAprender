# Aplicación — limpieza del temporal Office

Base esperada:

`77d182bd75b7ac74e2021cc305090ddaa2d9183c`

Extrae el ZIP sobre la raíz del repositorio y ejecuta:

```powershell
Get-ChildItem .\scripts\*.ps1 -Recurse | Unblock-File
.\scripts\apply-repo-hygiene-office-temp.ps1
```

Resultado esperado:

```text
OK: limpieza de temporal Office preparada.
No se ejecuto git add, commit ni push.
```

Después revisar:

```powershell
git status --short --untracked-files=all
git diff --check
git diff -- .gitignore
```

No hacer commit hasta revisar la salida.
