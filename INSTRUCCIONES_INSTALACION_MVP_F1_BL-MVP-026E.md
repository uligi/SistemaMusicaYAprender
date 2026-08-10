# Instrucciones de instalación — BL-MVP-026E

Repositorio:
`C:\Users\ul13m\Documents\GitHub\SistemaMusicaYAprender`

## 1. Extracción

Extraer `BL-MVP-026E_Paquete_Instalacion.zip` directamente sobre la raíz del repositorio,
sin carpeta envolvente.

El paquete contiene:

- `scripts/apply-bl-mvp-026e.ps1`
- `README/BL-MVP-026E_README.md`
- `INSTRUCCIONES_INSTALACION_MVP_F1_BL-MVP-026E.md`

No es necesario revertir BL-MVP-026D. El cambio funcional que alcanzó a aplicar es correcto.

## 2. Ejecución

Desde PowerShell en la raíz:

```powershell
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
Get-ChildItem .\scripts\*.ps1 -Recurse | Unblock-File
.\scripts\apply-bl-mvp-026e.ps1
```

BL-MVP-026E usa Git Bash localizado desde `git.exe`; no usa el stub `bash.exe` de WSL.

## 3. Puerta completa

Si BL-MVP-026E queda OK:

```powershell
.\scripts\apply-bl-mvp-026.ps1
```

No usar `Skip*`.

## 4. Hasta obtener GREEN

No ejecutar `git add`, `git commit` ni `git push`.

Después del GREEN se revisará el inventario completo antes de staging.
