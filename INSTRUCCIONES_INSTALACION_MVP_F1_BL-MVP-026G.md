# Instrucciones de instalación — BL-MVP-026G

Repositorio:
`C:\Users\ul13m\Documents\GitHub\SistemaMusicaYAprender`

Base esperada:
`4d515484b8597615b9665be4b0c5bded43565a6e`

## 1. Extracción

Extraer `BL-MVP-026G_Paquete_Instalacion.zip` directamente sobre la raíz del repositorio,
sin carpeta envolvente.

El paquete contiene:

- `scripts/apply-bl-mvp-026g.ps1`
- `README/BL-MVP-026G_README.md`
- `INSTRUCCIONES_INSTALACION_MVP_F1_BL-MVP-026G.md`

Los movimientos históricos de README que ya existen en el working tree pueden permanecer sin staging.
No agregar el archivo temporal de Office `~$...docx`.

## 2. Ejecución

Desde PowerShell en la raíz:

```powershell
Get-ChildItem .\scripts\*.ps1 -Recurse | Unblock-File
.\scripts\apply-bl-mvp-026g.ps1
```

Resultado esperado al final:

```text
OK: bash -n aprobado.
OK: git diff --check aprobado.
OK: BL-MVP-026 login no enumerable, cookie __Host, CSRF y sesion revocable verificados.
OK: BL-MVP-026G validado localmente contra el camino standalone HTTPS usado por CI.
```

## 3. Después de GREEN del correctivo

No usar `git add .`.

Revisar primero:

```powershell
git status --short --untracked-files=all
git diff --check
git diff -- scripts/ci/identity/verify-personal-login.sh
```

El delta funcional esperado en el verificador es únicamente la adición de `--no-launch-profile`.

Después se hará staging controlado de:

- `scripts/ci/identity/verify-personal-login.sh`
- `scripts/apply-bl-mvp-026g.ps1`
- `README/BL-MVP-026G_README.md`
- `INSTRUCCIONES_INSTALACION_MVP_F1_BL-MVP-026G.md`

No hacer commit ni push hasta revisar ese inventario.
